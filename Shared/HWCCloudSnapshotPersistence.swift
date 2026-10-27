import CryptoKit
import Foundation
import Security

enum HWCCloudSnapshotOutboxFailureStage: Equatable, Sendable {
    case afterGenerationWrite
    case afterRecoveryWrite
    case beforeCurrentWrite
}

enum HWCCloudSnapshotPersistenceError: Error, Equatable {
    case corruptManifest
    case corruptGeneration(UUID)
    case missingGeneration(UUID)
    case invalidKeyMaterial(String)
    case invalidRandomKey
    case defaultsVerificationFailed(String)
}

struct HWCCloudSnapshotJournalLocationAudit: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case empty
        case legacyOnly
        case preferredOnly
        case conflict
    }

    let state: State
    let legacyRootURL: URL
    let preferredRootURL: URL
}

/// Read-only planner for the legacy App Group root journal and a future
/// CoreDevice-readable Library/Application Support location. It never creates,
/// copies, moves, replaces, or removes backup data.
enum HWCCloudSnapshotJournalLocationPlanner {
    static let directoryName = "HWCEncryptedCloudSnapshotsV1"

    static func legacyRootURL(containerURL: URL) -> URL {
        containerURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func preferredRootURL(containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static func audit(
        containerURL: URL,
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
    ) -> HWCCloudSnapshotJournalLocationAudit {
        let legacy = legacyRootURL(containerURL: containerURL)
        let preferred = preferredRootURL(containerURL: containerURL)
        let legacyExists = fileExists(legacy.path)
        let preferredExists = fileExists(preferred.path)
        let state: HWCCloudSnapshotJournalLocationAudit.State
        switch (legacyExists, preferredExists) {
        case (false, false): state = .empty
        case (true, false): state = .legacyOnly
        case (false, true): state = .preferredOnly
        case (true, true): state = .conflict
        }
        return HWCCloudSnapshotJournalLocationAudit(
            state: state,
            legacyRootURL: legacy,
            preferredRootURL: preferred
        )
    }
}

/// Crash-recoverable local history. Generation files are immutable. The prior
/// checksummed manifest becomes recovery before the current pointer advances.
/// Confirming a cloud head never removes a local generation.
final class HWCCloudSnapshotDurableOutbox: HWCCloudSnapshotHistoryOutbox {
    private static let manifestSchemaVersion = 1
    private static let currentManifestName = "manifest.current.json"
    private static let recoveryManifestName = "manifest.recovery.json"

    private let directoryURL: URL
    private let lock = NSRecursiveLock()
    var failureInjector: ((HWCCloudSnapshotOutboxFailureStage) throws -> Void)?

    init(directoryURL: URL) throws {
        self.directoryURL = directoryURL
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        _ = try loadState()
    }

    var confirmedHead: HWCCloudSnapshotRemoteHead? {
        lock.lock()
        defer { lock.unlock() }
        return (try? loadState())?.confirmedHead
    }

    func persist(_ envelope: HWCEncryptedCloudSnapshotEnvelope) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !envelope.keyID.isEmpty, !envelope.sealedPayload.isEmpty else {
            throw HWCCloudSnapshotPersistenceError.corruptGeneration(envelope.snapshotID)
        }

        var state = try loadState()
        let encodedEnvelope = try Self.encode(envelope)
        let fingerprint = Self.fingerprint(encodedEnvelope)
        let generationURL = generationURL(for: envelope.snapshotID)
        if FileManager.default.fileExists(atPath: generationURL.path) {
            let existing = try Data(contentsOf: generationURL)
            guard existing == encodedEnvelope else {
                throw HWCCloudSnapshotPersistenceError.corruptGeneration(envelope.snapshotID)
            }
        } else {
            try Self.writeAtomically(encodedEnvelope, to: generationURL)
        }
        try failureInjector?(.afterGenerationWrite)

        if let existing = state.generations.first(where: {
            $0.snapshotID == envelope.snapshotID
        }) {
            guard existing.fingerprint == fingerprint,
                  existing.keyID == envelope.keyID else {
                throw HWCCloudSnapshotPersistenceError.corruptGeneration(envelope.snapshotID)
            }
        } else {
            state.generations.append(GenerationMetadata(
                snapshotID: envelope.snapshotID,
                keyID: envelope.keyID,
                originSequence: envelope.originSequence,
                fingerprint: fingerprint
            ))
        }
        state.revision += 1
        try commit(state)
    }

    func confirm(
        snapshotID: UUID,
        remoteHead: HWCCloudSnapshotRemoteHead
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        var state = try loadState()
        guard remoteHead.snapshotID == snapshotID,
              let metadata = state.generations.first(where: {
                  $0.snapshotID == snapshotID
              }),
              metadata.keyID == remoteHead.keyID else {
            throw HWCCloudSnapshotPersistenceError.missingGeneration(snapshotID)
        }
        state.confirmedHead = remoteHead
        state.revision += 1
        try commit(state)
    }

    func loadEnvelopes() throws -> [HWCEncryptedCloudSnapshotEnvelope] {
        lock.lock()
        defer { lock.unlock() }
        let state = try loadState()
        return try state.generations.map { metadata in
            try loadEnvelope(metadata)
        }
    }

    private func commit(_ state: Manifest) throws {
        let previous = try loadState()
        if !previous.generations.isEmpty || previous.confirmedHead != nil || previous.revision > 0 {
            try Self.writeAtomically(
                try Self.encodeManifest(previous),
                to: manifestURL(Self.recoveryManifestName)
            )
            try failureInjector?(.afterRecoveryWrite)
        }
        try failureInjector?(.beforeCurrentWrite)
        try Self.writeAtomically(
            try Self.encodeManifest(state),
            to: manifestURL(Self.currentManifestName)
        )
    }

    private func loadState() throws -> Manifest {
        let currentURL = manifestURL(Self.currentManifestName)
        let recoveryURL = manifestURL(Self.recoveryManifestName)
        let currentExists = FileManager.default.fileExists(atPath: currentURL.path)
        let recoveryExists = FileManager.default.fileExists(atPath: recoveryURL.path)

        if currentExists,
           let state = try? decodedAndValidatedManifest(at: currentURL) {
            return state
        }
        if recoveryExists,
           let state = try? decodedAndValidatedManifest(at: recoveryURL) {
            return state
        }
        guard !currentExists, !recoveryExists else {
            throw HWCCloudSnapshotPersistenceError.corruptManifest
        }
        return Manifest(
            schemaVersion: Self.manifestSchemaVersion,
            revision: 0,
            generations: [],
            confirmedHead: nil
        )
    }

    private func decodedAndValidatedManifest(at url: URL) throws -> Manifest {
        let envelope = try JSONDecoder().decode(
            ManifestEnvelope.self,
            from: Data(contentsOf: url)
        )
        guard envelope.payload.schemaVersion == Self.manifestSchemaVersion,
              envelope.checksum == Self.fingerprint(try Self.encode(envelope.payload)),
              Set(envelope.payload.generations.map(\.snapshotID)).count == envelope.payload.generations.count else {
            throw HWCCloudSnapshotPersistenceError.corruptManifest
        }
        for metadata in envelope.payload.generations {
            _ = try loadEnvelope(metadata)
        }
        if let confirmed = envelope.payload.confirmedHead,
           !envelope.payload.generations.contains(where: {
               $0.snapshotID == confirmed.snapshotID && $0.keyID == confirmed.keyID
           }) {
            throw HWCCloudSnapshotPersistenceError.corruptManifest
        }
        return envelope.payload
    }

    private func loadEnvelope(
        _ metadata: GenerationMetadata
    ) throws -> HWCEncryptedCloudSnapshotEnvelope {
        let url = generationURL(for: metadata.snapshotID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw HWCCloudSnapshotPersistenceError.missingGeneration(metadata.snapshotID)
        }
        let data = try Data(contentsOf: url)
        guard Self.fingerprint(data) == metadata.fingerprint,
              let envelope = try? JSONDecoder().decode(
                  HWCEncryptedCloudSnapshotEnvelope.self,
                  from: data
              ),
              envelope.snapshotID == metadata.snapshotID,
              envelope.keyID == metadata.keyID,
              envelope.originSequence == metadata.originSequence else {
            throw HWCCloudSnapshotPersistenceError.corruptGeneration(metadata.snapshotID)
        }
        return envelope
    }

    private func manifestURL(_ name: String) -> URL {
        directoryURL.appendingPathComponent(name, isDirectory: false)
    }

    private func generationURL(for snapshotID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "generation-\(snapshotID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private static func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }

    private static func fingerprint(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func encodeManifest(_ manifest: Manifest) throws -> Data {
        try encode(ManifestEnvelope(
            payload: manifest,
            checksum: fingerprint(try encode(manifest))
        ))
    }

    private struct GenerationMetadata: Codable, Equatable {
        let snapshotID: UUID
        let keyID: String
        let originSequence: UInt64
        let fingerprint: Data
    }

    private struct Manifest: Codable, Equatable {
        let schemaVersion: Int
        var revision: UInt64
        var generations: [GenerationMetadata]
        var confirmedHead: HWCCloudSnapshotRemoteHead?
    }

    private struct ManifestEnvelope: Codable, Equatable {
        let payload: Manifest
        let checksum: Data
    }
}

struct HWCCloudSnapshotKeyMaterial: Codable, Equatable, Sendable {
    let keyID: String
    let keyData: Data
    let createdAtMilliseconds: Int64

    func validatedKey() throws -> HWCCloudSnapshotKey {
        let key = try HWCCloudSnapshotKey(data: keyData)
        guard key.id == keyID else {
            throw HWCCloudSnapshotPersistenceError.invalidKeyMaterial(keyID)
        }
        return key
    }
}

protocol HWCCloudSnapshotKeyMaterialStoring: AnyObject {
    func loadAll() throws -> [HWCCloudSnapshotKeyMaterial]
    func save(_ material: HWCCloudSnapshotKeyMaterial) throws
}

protocol HWCCloudSnapshotCurrentKeyStoring: AnyObject {
    var currentKeyID: String? { get set }
}

final class HWCCloudSnapshotMemoryKeyMaterialStore: HWCCloudSnapshotKeyMaterialStoring {
    private(set) var materials: [HWCCloudSnapshotKeyMaterial]

    init(materials: [HWCCloudSnapshotKeyMaterial] = []) {
        self.materials = materials
    }

    func loadAll() throws -> [HWCCloudSnapshotKeyMaterial] {
        materials
    }

    func save(_ material: HWCCloudSnapshotKeyMaterial) throws {
        if let index = materials.firstIndex(where: { $0.keyID == material.keyID }) {
            guard materials[index] == material else {
                throw HWCCloudSnapshotPersistenceError.invalidKeyMaterial(material.keyID)
            }
            return
        }
        materials.append(material)
    }
}

final class HWCCloudSnapshotMemoryCurrentKeyStore: HWCCloudSnapshotCurrentKeyStoring {
    var currentKeyID: String?

    init(currentKeyID: String? = nil) {
        self.currentKeyID = currentKeyID
    }
}

/// Versioned key ring. Old keys remain addressable for historical CloudKit
/// generations. The concrete production material store uses synchronizable
/// Keychain items; this type never silently replaces malformed material.
final class HWCCloudSnapshotSynchronizableKeyRing: HWCCloudSnapshotKeyRing {
    private let keyStore: HWCCloudSnapshotKeyMaterialStoring
    private let currentKeyStore: HWCCloudSnapshotCurrentKeyStoring
    private let nowMilliseconds: () -> Int64
    private let randomKeyData: () -> Data
    private let lock = NSRecursiveLock()

    init(
        keyStore: HWCCloudSnapshotKeyMaterialStoring,
        currentKeyStore: HWCCloudSnapshotCurrentKeyStoring,
        nowMilliseconds: @escaping () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        },
        randomKeyData: @escaping () -> Data = {
            var bytes = Data(count: 32)
            let result = bytes.withUnsafeMutableBytes { buffer in
                SecRandomCopyBytes(kSecRandomDefault, 32, buffer.baseAddress!)
            }
            return result == errSecSuccess ? bytes : Data()
        }
    ) {
        self.keyStore = keyStore
        self.currentKeyStore = currentKeyStore
        self.nowMilliseconds = nowMilliseconds
        self.randomKeyData = randomKeyData
    }

    func currentKey() throws -> HWCCloudSnapshotKey {
        lock.lock()
        defer { lock.unlock() }
        let materials = try validatedMaterials()
        if let currentKeyID = currentKeyStore.currentKeyID,
           let material = materials.first(where: { $0.keyID == currentKeyID }) {
            return try material.validatedKey()
        }
        if let material = materials.max(by: {
            if $0.createdAtMilliseconds != $1.createdAtMilliseconds {
                return $0.createdAtMilliseconds < $1.createdAtMilliseconds
            }
            return $0.keyID < $1.keyID
        }) {
            currentKeyStore.currentKeyID = material.keyID
            return try material.validatedKey()
        }
        return try rotate(
            randomKeyData: randomKeyData,
            createdAtMilliseconds: nowMilliseconds()
        )
    }

    func keyData(for keyID: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard let materials = try? validatedMaterials(),
              let material = materials.first(where: { $0.keyID == keyID }),
              (try? material.validatedKey()) != nil else {
            return nil
        }
        return material.keyData
    }

    @discardableResult
    func rotate(
        randomKeyData: () -> Data,
        createdAtMilliseconds: Int64
    ) throws -> HWCCloudSnapshotKey {
        lock.lock()
        defer { lock.unlock() }
        let keyData = randomKeyData()
        guard keyData.count == 32 else {
            throw HWCCloudSnapshotPersistenceError.invalidRandomKey
        }
        let key = try HWCCloudSnapshotKey(data: keyData)
        let material = HWCCloudSnapshotKeyMaterial(
            keyID: key.id,
            keyData: key.data,
            createdAtMilliseconds: createdAtMilliseconds
        )
        try keyStore.save(material)
        currentKeyStore.currentKeyID = key.id
        return key
    }

    private func validatedMaterials() throws -> [HWCCloudSnapshotKeyMaterial] {
        let materials = try keyStore.loadAll()
        var seen = Set<String>()
        for material in materials {
            _ = try material.validatedKey()
            guard seen.insert(material.keyID).inserted else {
                throw HWCCloudSnapshotPersistenceError.invalidKeyMaterial(material.keyID)
            }
        }
        return materials
    }
}

enum HWCCloudSnapshotDefaultsJournalFailureStage: Equatable, Sendable {
    case afterPreparedJournalWrite
    case afterAppliedMutationCount(Int)
    case afterCommittedJournalWrite
}

/// UserDefaults itself has no multi-key transaction. This adapter records a
/// checksummed before/after journal first. Restart recovery rolls a prepared
/// write back or completes a committed write, so restore exposes old-or-new.
final class HWCCloudSnapshotJournaledDefaultsBacking: HWCCloudSnapshotUserDefaultsBacking {
    private static let journalSchemaVersion = 1
    private static let journalFileName = "defaults-restore-journal.json"

    private let sharedDefaults: UserDefaults
    private let standardDefaults: UserDefaults
    private let standardKeys: Set<String>
    private let journalURL: URL
    private let lock = NSRecursiveLock()
    var failureInjector: ((HWCCloudSnapshotDefaultsJournalFailureStage) throws -> Void)?

    init(
        sharedDefaults: UserDefaults,
        standardDefaults: UserDefaults = .standard,
        journalDirectoryURL: URL,
        standardKeys: Set<String> = ["companion.settingsMode.customSelected"]
    ) throws {
        self.sharedDefaults = sharedDefaults
        self.standardDefaults = standardDefaults
        self.standardKeys = standardKeys
        try FileManager.default.createDirectory(
            at: journalDirectoryURL,
            withIntermediateDirectories: true
        )
        journalURL = journalDirectoryURL.appendingPathComponent(
            Self.journalFileName,
            isDirectory: false
        )
        try recoverIfNeeded()
    }

    func object(forKey key: String) -> Any? {
        defaults(for: key).object(forKey: key)
    }

    func replaceAtomically(
        _ mutation: HWCCloudSnapshotUserDefaultsMutation
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        try recoverIfNeeded()
        let keys = mutation.touchedKeys.sorted()
        let before = try keys.map { key in
            HWCCloudSnapshotEntry(
                key: key,
                value: try object(forKey: key).map(
                    HWCCloudSnapshotUserDefaultsAdapter.snapshotValue(from:)
                )
            )
        }
        let desired = try keys.map { key -> HWCCloudSnapshotEntry in
            if let value = mutation.values[key] {
                return HWCCloudSnapshotEntry(
                    key: key,
                    value: try HWCCloudSnapshotUserDefaultsAdapter.snapshotValue(
                        from: value
                    )
                )
            }
            return HWCCloudSnapshotEntry(key: key, value: nil)
        }
        var journal = DefaultsJournal(
            schemaVersion: Self.journalSchemaVersion,
            transactionID: UUID(),
            phase: .prepared,
            before: before,
            desired: desired
        )
        try writeJournal(journal)
        try failureInjector?(.afterPreparedJournalWrite)

        try apply(desired, injectingFailures: true)
        try verify(desired)
        journal.phase = .committed
        try writeJournal(journal)
        try failureInjector?(.afterCommittedJournalWrite)
        try removeJournalIfPresent()
    }

    private func recoverIfNeeded() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        let envelope = try JSONDecoder().decode(
            DefaultsJournalEnvelope.self,
            from: Data(contentsOf: journalURL)
        )
        guard envelope.payload.schemaVersion == Self.journalSchemaVersion,
              envelope.checksum == Self.fingerprint(
                  try Self.encode(envelope.payload)
              ) else {
            throw HWCCloudSnapshotPersistenceError.corruptManifest
        }
        switch envelope.payload.phase {
        case .prepared:
            try apply(envelope.payload.before, injectingFailures: false)
            try verify(envelope.payload.before)
        case .committed:
            try apply(envelope.payload.desired, injectingFailures: false)
            try verify(envelope.payload.desired)
        }
        try removeJournalIfPresent()
    }

    private func apply(
        _ entries: [HWCCloudSnapshotEntry],
        injectingFailures: Bool
    ) throws {
        for (offset, entry) in entries.sorted(by: { $0.key < $1.key }).enumerated() {
            let defaults = defaults(for: entry.key)
            if let value = entry.value {
                defaults.set(
                    try HWCCloudSnapshotUserDefaultsAdapter.userDefaultsValue(
                        from: value
                    ),
                    forKey: entry.key
                )
            } else {
                defaults.removeObject(forKey: entry.key)
            }
            if injectingFailures {
                try failureInjector?(.afterAppliedMutationCount(offset + 1))
            }
        }
        sharedDefaults.synchronize()
        if standardDefaults !== sharedDefaults {
            standardDefaults.synchronize()
        }
    }

    private func verify(_ entries: [HWCCloudSnapshotEntry]) throws {
        for entry in entries {
            let actual = try object(forKey: entry.key).map(
                HWCCloudSnapshotUserDefaultsAdapter.snapshotValue(from:)
            )
            guard actual == entry.value else {
                throw HWCCloudSnapshotPersistenceError.defaultsVerificationFailed(
                    entry.key
                )
            }
        }
    }

    private func defaults(for key: String) -> UserDefaults {
        standardKeys.contains(key) ? standardDefaults : sharedDefaults
    }

    private func writeJournal(_ journal: DefaultsJournal) throws {
        let envelope = DefaultsJournalEnvelope(
            payload: journal,
            checksum: Self.fingerprint(try Self.encode(journal))
        )
        try Self.encode(envelope).write(to: journalURL, options: [.atomic])
    }

    private func removeJournalIfPresent() throws {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return }
        try FileManager.default.removeItem(at: journalURL)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func fingerprint(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    private enum DefaultsJournalPhase: String, Codable {
        case prepared
        case committed
    }

    private struct DefaultsJournal: Codable {
        let schemaVersion: Int
        let transactionID: UUID
        var phase: DefaultsJournalPhase
        let before: [HWCCloudSnapshotEntry]
        let desired: [HWCCloudSnapshotEntry]
    }

    private struct DefaultsJournalEnvelope: Codable {
        let payload: DefaultsJournal
        let checksum: Data
    }
}

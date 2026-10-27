import CryptoKit
import Foundation

enum HWCCloudSnapshotStoreID: String, CaseIterable, Codable, Sendable {
    case settings
    case paidLayerContent
    case clipboardSnippets
    case customDictionary
    case adaptiveLearning
    case rawTypedSamples
    case autocorrectionLearning
    case languageLearning
    case motorCalibration
    case gizmoSnapshot
    case autobotLearning
}

enum HWCCloudSnapshotMergePolicy: String, Codable, Sendable {
    case newestRecordWithConflictRetention
}

struct HWCCloudSnapshotStoreDescriptor: Equatable, Sendable {
    let id: HWCCloudSnapshotStoreID
    let schemaVersion: Int
    let sourceKeys: Set<String>
    let snapshotKeys: Set<String>
    let maximumEncodedBytes: Int
    let mergePolicy: HWCCloudSnapshotMergePolicy

    init(
        id: HWCCloudSnapshotStoreID,
        schemaVersion: Int = 1,
        sourceKeys: Set<String>,
        snapshotKeys: Set<String> = [],
        maximumEncodedBytes: Int,
        mergePolicy: HWCCloudSnapshotMergePolicy = .newestRecordWithConflictRetention
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.sourceKeys = sourceKeys
        self.snapshotKeys = snapshotKeys.isEmpty ? sourceKeys : snapshotKeys
        self.maximumEncodedBytes = maximumEncodedBytes
        self.mergePolicy = mergePolicy
    }
}

struct HWCCloudSnapshotRegistry: Equatable, Sendable {
    let descriptors: [HWCCloudSnapshotStoreDescriptor]

    var backedUpSourceKeys: Set<String> {
        descriptors.reduce(into: Set<String>()) { result, descriptor in
            result.formUnion(descriptor.sourceKeys)
        }
    }

    func descriptor(for id: HWCCloudSnapshotStoreID) -> HWCCloudSnapshotStoreDescriptor? {
        descriptors.first { $0.id == id }
    }

    static let v1 = HWCCloudSnapshotRegistry(descriptors: [
        HWCCloudSnapshotStoreDescriptor(
            id: .settings,
            sourceKeys: [
                "app.theme",
                "app.accentPalette",
                "app.customKeyStyle",
                "keyboard.vibrationEnabled",
                "keyboard.feedbackLevel",
                "keyboard.autoPairEnabled",
                "keyboard.startExpanded",
                "keyboard.defaultSymbolLayer",
                "keyboard.showQuickInsertRow",
                "keyboard.hideKeyboardEnabled",
                "keyboard.highContrastKeys",
                "keyboard.largeLegends",
                "keyboard.showControlLabels",
                "keyboard.capitalizeFirstLetterEnabled",
                "keyboard.doubleSpacePeriodEnabled",
                "keyboard.autocorrectEnabled",
                "keyboard.autocompleteEnabled",
                "keyboard.clickToFixEnabled",
                "keyboard.autocorrectRankingMethod",
                "keyboard.autocorrectLogicRecipe",
                "keyboard.autocorrectLogicBlocks",
                "keyboard.autocorrectLogicLanes",
                "keyboard.customTextRules",
                "keyboard.suggestionSwipeUpAction",
                "keyboard.suggestionSwipeDownAction",
                "keyboard.suggestionSwipeLeftDeleteEnabled",
                "keyboard.suggestionSwipeRightSpaceEnabled",
                "keyboard.suggestionHoldForRolodexEnabled",
                "keyboard.hardwareAutocorrectSelectorEnabled",
                "keyboard.hardwareAutocorrectSelectorInitiationKey",
                "keyboard.hardwareAutocorrectSelectorSelectionKey",
                "keyboard.physicalReturnBehavior",
                "keyboard.showQuickInsertHandle",
                "keyboard.capsHoldToLockEnabled",
                "keyboard.capsHoldDurationMs",
                "keyboard.menuHoldToLatchEnabled",
                "keyboard.menuHoldDurationMs",
                "keyboard.keyHoldDurationMs",
                "keyboard.rolodexSelectHoldDurationMs",
                "keyboard.menuTapLockWindowMs",
                "keyboard.deleteHoldEnabled",
                "keyboard.deleteHoldWordsBeforeSentence",
                "keyboard.layoutPreset",
                "keyboard.layoutLocale",
                "keyboard.runtimeLayoutRoute",
                "keyboard.toolbarHeight",
                "keyboard.expandedKeyHeight",
                "keyboard.suggestionVisibleWordCount",
                "keyboard.suggestionRowHeight",
                "keyboard.toolbarKeyCount",
                "keyboard.symbolTopRowKeyCount",
                "keyboard.symbolMiddleRowKeyCount",
                "keyboard.symbolBottomRowKeyCount",
                "keyboard.letterTopRowKeyCount",
                "keyboard.letterMiddleRowKeyCount",
                "keyboard.letterBottomRowKeyCount",
                "keyboard.clipboardDisabled",
                "keyboard.saveClipboardSettingsWithLiveKeyboard",
                "keyboard.inputKernelFallbackDisabled",
                "keyboard.predictionDisabled",
                "keyboard.glideDisabled",
                "companion.settingsMode.customSelected",
                "keyboard.signalRelayEnabled",
                "keyboard.signalRelayEmitKeyUp",
                "keyboard.signalRelayPriorityMode",
                "keyboard.signalRelaySessionPersist",
                "keyboard.signalRelayHoldTriggerMs",
            ],
            maximumEncodedBytes: 512 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .paidLayerContent,
            sourceKeys: [
                "keyboard.keymapData",
                "keyboard.savedKeymapPresets",
            ],
            maximumEncodedBytes: 2 * 1_024 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .clipboardSnippets,
            sourceKeys: ["keyboard.encryptedClipboard.snippetRecords"],
            snapshotKeys: ["clipboard.plaintext.v1"],
            maximumEncodedBytes: 256 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .customDictionary,
            sourceKeys: ["keyboard.customDictionaryWords"],
            maximumEncodedBytes: 128 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .adaptiveLearning,
            sourceKeys: [
                "keyboard.adaptiveUnigramCounts",
                "keyboard.adaptiveBigramCounts",
            ],
            maximumEncodedBytes: 256 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .rawTypedSamples,
            sourceKeys: ["keyboard.rawTypedTextMLSamples"],
            maximumEncodedBytes: 512 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .autocorrectionLearning,
            sourceKeys: [
                "keyboard.autocorrection.rejectionFingerprints.v1",
                "keyboard.autocorrection.personalization.v1",
            ],
            maximumEncodedBytes: 128 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .languageLearning,
            sourceKeys: [
                "keyboard.languageBrain.events.v1",
                "keyboard.languageBrain.snapshot.v1",
                "keyboard.languageBrain.snapshot.revision",
                "keyboard.languageBrain.phrases.v1",
            ],
            maximumEncodedBytes: 256 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .motorCalibration,
            sourceKeys: ["keyboard.motorCalibration.v1"],
            maximumEncodedBytes: 32 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .gizmoSnapshot,
            sourceKeys: ["keyboard.gizmoImprovement.latestSnapshot"],
            maximumEncodedBytes: 256 * 1_024
        ),
        HWCCloudSnapshotStoreDescriptor(
            id: .autobotLearning,
            sourceKeys: [
                "keyboard.autobot.typingEpisodes.v2",
                "keyboard.autobot.typingEpisodes.v1",
                "keyboard.autobot.romanizedHypotheses.v1",
                "keyboard.autobot.ruleHypotheses.v1",
                "keyboard.autobot.ruleHypothesisDecisions.v1",
                "keyboard.autobot.episodeCredit.v1",
                "keyboard.autobot.brainSnapshot.current.v1",
                "keyboard.autobot.brainSnapshot.recovery.v1",
                "keyboard.autobot.brainSnapshot.resetEpoch.v1",
                "keyboard.autobot.portableFingerprintSecret.v1",
            ],
            snapshotKeys: [
                "keyboard.autobot.typingEpisodes.v2",
                "keyboard.autobot.typingEpisodes.v1",
                "keyboard.autobot.romanizedHypotheses.v1",
                "keyboard.autobot.ruleHypotheses.v1",
                "keyboard.autobot.ruleHypothesisDecisions.v1",
                "keyboard.autobot.episodeCredit.v1",
                "keyboard.autobot.brainSnapshot.current.v1",
                "keyboard.autobot.brainSnapshot.recovery.v1",
                "keyboard.autobot.brainSnapshot.resetEpoch.v1",
                "keyboard.autobot.portableFingerprintSecret.v1",
            ],
            maximumEncodedBytes: 1 * 1_024 * 1_024
        ),
    ])
}

indirect enum HWCCloudSnapshotValue: Codable, Equatable, Sendable {
    case data(Data)
    case string(String)
    case integer(Int64)
    case double(Double)
    case boolean(Bool)
    case array([HWCCloudSnapshotValue])
    case dictionary([String: HWCCloudSnapshotValue])
}

struct HWCCloudSnapshotEntry: Codable, Equatable, Sendable {
    let key: String
    var value: HWCCloudSnapshotValue?
}

enum HWCCloudSnapshotError: Error, Equatable {
    case invalidKey
    case invalidEnvelopeVersion(Int)
    case unsupportedAlgorithm(String)
    case unsupportedLegacyPayloadSchema(Int)
    case payloadSchemaRequiresNewerApp(Int)
    case invalidSnapshot(String)
    case invalidRecord(HWCCloudSnapshotStoreID)
    case unknownStore(HWCCloudSnapshotStoreID)
    case unsupportedStoreSchema(HWCCloudSnapshotStoreID, Int)
    case unexpectedStoreKey(HWCCloudSnapshotStoreID, String)
    case recordTooLarge(HWCCloudSnapshotStoreID, Int)
    case conflictJournalTooLarge(Int)
    case authenticationFailed
}

struct HWCCloudSnapshotRecord: Codable, Equatable, Sendable {
    let id: HWCCloudSnapshotStoreID
    let schemaVersion: Int
    let revision: UInt64
    let modifiedAtMilliseconds: Int64
    var entries: [HWCCloudSnapshotEntry]
    let contentHash: Data

    static func make(
        id: HWCCloudSnapshotStoreID,
        schemaVersion: Int,
        revision: UInt64,
        modifiedAtMilliseconds: Int64,
        entries: [HWCCloudSnapshotEntry]
    ) throws -> HWCCloudSnapshotRecord {
        let normalizedEntries = entries.sorted { $0.key < $1.key }
        guard schemaVersion > 0,
              Set(normalizedEntries.map(\.key)).count == normalizedEntries.count,
              normalizedEntries.allSatisfy({ !$0.key.isEmpty }) else {
            throw HWCCloudSnapshotError.invalidRecord(id)
        }
        let material = HWCCloudSnapshotRecordHashMaterial(
            id: id,
            schemaVersion: schemaVersion,
            revision: revision,
            modifiedAtMilliseconds: modifiedAtMilliseconds,
            entries: normalizedEntries
        )
        let hash = Data(SHA256.hash(data: try HWCCloudSnapshotCoding.encode(material)))
        return HWCCloudSnapshotRecord(
            id: id,
            schemaVersion: schemaVersion,
            revision: revision,
            modifiedAtMilliseconds: modifiedAtMilliseconds,
            entries: normalizedEntries,
            contentHash: hash
        )
    }

    func validate() throws {
        let rebuilt = try Self.make(
            id: id,
            schemaVersion: schemaVersion,
            revision: revision,
            modifiedAtMilliseconds: modifiedAtMilliseconds,
            entries: entries
        )
        guard rebuilt.contentHash == contentHash,
              rebuilt.entries == entries else {
            throw HWCCloudSnapshotError.invalidRecord(id)
        }
    }
}

private struct HWCCloudSnapshotRecordHashMaterial: Codable {
    let id: HWCCloudSnapshotStoreID
    let schemaVersion: Int
    let revision: UInt64
    let modifiedAtMilliseconds: Int64
    let entries: [HWCCloudSnapshotEntry]
}

struct HWCCloudSnapshotStoreTombstone: Codable, Equatable, Sendable {
    let id: HWCCloudSnapshotStoreID
    let schemaVersion: Int
    let revision: UInt64
    let modifiedAtMilliseconds: Int64
    let contentHash: Data

    static func make(
        id: HWCCloudSnapshotStoreID,
        schemaVersion: Int,
        revision: UInt64,
        modifiedAtMilliseconds: Int64
    ) throws -> HWCCloudSnapshotStoreTombstone {
        guard schemaVersion > 0 else {
            throw HWCCloudSnapshotError.invalidRecord(id)
        }
        let material = HWCCloudSnapshotStoreTombstoneHashMaterial(
            id: id,
            schemaVersion: schemaVersion,
            revision: revision,
            modifiedAtMilliseconds: modifiedAtMilliseconds
        )
        return HWCCloudSnapshotStoreTombstone(
            id: id,
            schemaVersion: schemaVersion,
            revision: revision,
            modifiedAtMilliseconds: modifiedAtMilliseconds,
            contentHash: Data(SHA256.hash(
                data: try HWCCloudSnapshotCoding.encode(material)
            ))
        )
    }

    func validate() throws {
        let rebuilt = try Self.make(
            id: id,
            schemaVersion: schemaVersion,
            revision: revision,
            modifiedAtMilliseconds: modifiedAtMilliseconds
        )
        guard rebuilt.contentHash == contentHash else {
            throw HWCCloudSnapshotError.invalidRecord(id)
        }
    }
}

private struct HWCCloudSnapshotStoreTombstoneHashMaterial: Codable {
    let id: HWCCloudSnapshotStoreID
    let schemaVersion: Int
    let revision: UInt64
    let modifiedAtMilliseconds: Int64
}

struct HWCCloudSnapshotPayload: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let maximumRetainedConflictCount = 64
    static let maximumRetainedConflictBytes = 4 * 1_024 * 1_024

    let schemaVersion: Int
    let snapshotID: UUID
    let parentSnapshotIDs: [UUID]
    let originDeviceID: String
    let originSequence: UInt64
    let createdAtMilliseconds: Int64
    let records: [HWCCloudSnapshotRecord]
    let storeTombstones: [HWCCloudSnapshotStoreTombstone]
    let retainedConflictRecords: [HWCCloudSnapshotRecord]
    let retainedConflictTombstones: [HWCCloudSnapshotStoreTombstone]

    init(
        schemaVersion: Int = currentSchemaVersion,
        snapshotID: UUID,
        parentSnapshotIDs: [UUID],
        originDeviceID: String,
        originSequence: UInt64,
        createdAtMilliseconds: Int64,
        records: [HWCCloudSnapshotRecord],
        storeTombstones: [HWCCloudSnapshotStoreTombstone] = [],
        retainedConflictRecords: [HWCCloudSnapshotRecord] = [],
        retainedConflictTombstones: [HWCCloudSnapshotStoreTombstone] = []
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotID = snapshotID
        self.parentSnapshotIDs = parentSnapshotIDs
        self.originDeviceID = originDeviceID
        self.originSequence = originSequence
        self.createdAtMilliseconds = createdAtMilliseconds
        self.records = records
        self.storeTombstones = storeTombstones
        self.retainedConflictRecords = retainedConflictRecords
        self.retainedConflictTombstones = retainedConflictTombstones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        snapshotID = try container.decode(UUID.self, forKey: .snapshotID)
        parentSnapshotIDs = try container.decode([UUID].self, forKey: .parentSnapshotIDs)
        originDeviceID = try container.decode(String.self, forKey: .originDeviceID)
        originSequence = try container.decode(UInt64.self, forKey: .originSequence)
        createdAtMilliseconds = try container.decode(Int64.self, forKey: .createdAtMilliseconds)
        records = try container.decode([HWCCloudSnapshotRecord].self, forKey: .records)
        storeTombstones = try container.decodeIfPresent(
            [HWCCloudSnapshotStoreTombstone].self,
            forKey: .storeTombstones
        ) ?? []
        retainedConflictRecords = try container.decodeIfPresent(
            [HWCCloudSnapshotRecord].self,
            forKey: .retainedConflictRecords
        ) ?? []
        retainedConflictTombstones = try container.decodeIfPresent(
            [HWCCloudSnapshotStoreTombstone].self,
            forKey: .retainedConflictTombstones
        ) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case snapshotID
        case parentSnapshotIDs
        case originDeviceID
        case originSequence
        case createdAtMilliseconds
        case records
        case storeTombstones
        case retainedConflictRecords
        case retainedConflictTombstones
    }

    func validate() throws {
        guard schemaVersion >= Self.currentSchemaVersion else {
            throw HWCCloudSnapshotError.unsupportedLegacyPayloadSchema(schemaVersion)
        }
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw HWCCloudSnapshotError.payloadSchemaRequiresNewerApp(schemaVersion)
        }
        guard !originDeviceID.isEmpty,
              !parentSnapshotIDs.contains(snapshotID),
              Set(parentSnapshotIDs).count == parentSnapshotIDs.count,
              Set(records.map(\.id)).count == records.count,
              Set(storeTombstones.map(\.id)).count == storeTombstones.count,
              Set(records.map(\.id)).isDisjoint(with: Set(storeTombstones.map(\.id))) else {
            throw HWCCloudSnapshotError.invalidSnapshot(snapshotID.uuidString)
        }
        try records.forEach { try $0.validate() }
        try storeTombstones.forEach { try $0.validate() }
        try retainedConflictRecords.forEach { try $0.validate() }
        try retainedConflictTombstones.forEach { try $0.validate() }
        let retainedCount = retainedConflictRecords.count + retainedConflictTombstones.count
        let retainedBytes = try HWCCloudSnapshotCoding.encode(
            HWCCloudSnapshotConflictJournalMaterial(
                records: retainedConflictRecords,
                tombstones: retainedConflictTombstones
            )
        ).count
        guard retainedCount <= Self.maximumRetainedConflictCount,
              retainedBytes <= Self.maximumRetainedConflictBytes else {
            throw HWCCloudSnapshotError.conflictJournalTooLarge(
                max(retainedCount, retainedBytes)
            )
        }
    }
}

private struct HWCCloudSnapshotConflictJournalMaterial: Codable {
    let records: [HWCCloudSnapshotRecord]
    let tombstones: [HWCCloudSnapshotStoreTombstone]
}

enum HWCCloudSnapshotEncryptionAlgorithm: String, Codable, Equatable, Sendable {
    case chaChaPoly1305 = "ChaCha20-Poly1305"
}

struct HWCEncryptedCloudSnapshotEnvelope: Codable, Equatable, Sendable {
    static let currentEnvelopeVersion = 1

    var envelopeVersion: Int
    var algorithm: HWCCloudSnapshotEncryptionAlgorithm
    var keyID: String
    var snapshotID: UUID
    var parentSnapshotIDs: [UUID]
    var originDeviceID: String
    var originSequence: UInt64
    var createdAtMilliseconds: Int64
    var plaintextHash: Data
    var sealedPayload: Data
}

enum HWCCloudSnapshotCryptor {
    static func seal(
        _ payload: HWCCloudSnapshotPayload,
        keyData: Data
    ) throws -> HWCEncryptedCloudSnapshotEnvelope {
        try payload.validate()
        let key = try symmetricKey(from: keyData)
        let plaintext = try HWCCloudSnapshotCoding.encode(payload)
        let plaintextHash = Data(SHA256.hash(data: plaintext))
        let keyID = keyIdentifier(for: keyData)
        let header = HWCEncryptedCloudSnapshotHeader(
            envelopeVersion: HWCEncryptedCloudSnapshotEnvelope.currentEnvelopeVersion,
            algorithm: .chaChaPoly1305,
            keyID: keyID,
            snapshotID: payload.snapshotID,
            parentSnapshotIDs: payload.parentSnapshotIDs,
            originDeviceID: payload.originDeviceID,
            originSequence: payload.originSequence,
            createdAtMilliseconds: payload.createdAtMilliseconds,
            plaintextHash: plaintextHash
        )
        let authenticatedHeader = try HWCCloudSnapshotCoding.encode(header)
        let sealedBox = try ChaChaPoly.seal(
            plaintext,
            using: key,
            authenticating: authenticatedHeader
        )
        return HWCEncryptedCloudSnapshotEnvelope(
            envelopeVersion: header.envelopeVersion,
            algorithm: header.algorithm,
            keyID: header.keyID,
            snapshotID: header.snapshotID,
            parentSnapshotIDs: header.parentSnapshotIDs,
            originDeviceID: header.originDeviceID,
            originSequence: header.originSequence,
            createdAtMilliseconds: header.createdAtMilliseconds,
            plaintextHash: header.plaintextHash,
            sealedPayload: sealedBox.combined
        )
    }

    static func open(
        _ envelope: HWCEncryptedCloudSnapshotEnvelope,
        keyData: Data
    ) throws -> HWCCloudSnapshotPayload {
        guard envelope.envelopeVersion == HWCEncryptedCloudSnapshotEnvelope.currentEnvelopeVersion else {
            throw HWCCloudSnapshotError.invalidEnvelopeVersion(envelope.envelopeVersion)
        }
        guard envelope.algorithm == .chaChaPoly1305 else {
            throw HWCCloudSnapshotError.unsupportedAlgorithm(envelope.algorithm.rawValue)
        }
        let key = try symmetricKey(from: keyData)
        guard envelope.keyID == keyIdentifier(for: keyData) else {
            throw HWCCloudSnapshotError.invalidKey
        }
        let header = HWCEncryptedCloudSnapshotHeader(envelope: envelope)
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: envelope.sealedPayload)
            let plaintext = try ChaChaPoly.open(
                sealedBox,
                using: key,
                authenticating: HWCCloudSnapshotCoding.encode(header)
            )
            guard Data(SHA256.hash(data: plaintext)) == envelope.plaintextHash else {
                throw HWCCloudSnapshotError.authenticationFailed
            }
            let payload = try HWCCloudSnapshotCoding.decode(
                HWCCloudSnapshotPayload.self,
                from: plaintext
            )
            try payload.validate()
            guard payload.snapshotID == envelope.snapshotID,
                  payload.parentSnapshotIDs == envelope.parentSnapshotIDs,
                  payload.originDeviceID == envelope.originDeviceID,
                  payload.originSequence == envelope.originSequence,
                  payload.createdAtMilliseconds == envelope.createdAtMilliseconds else {
                throw HWCCloudSnapshotError.authenticationFailed
            }
            return payload
        } catch let error as HWCCloudSnapshotError {
            throw error
        } catch {
            throw HWCCloudSnapshotError.authenticationFailed
        }
    }

    private static func symmetricKey(from data: Data) throws -> SymmetricKey {
        guard data.count == 32 else { throw HWCCloudSnapshotError.invalidKey }
        return SymmetricKey(data: data)
    }

    static func keyIdentifier(for data: Data) -> String {
        SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

private struct HWCEncryptedCloudSnapshotHeader: Codable {
    let envelopeVersion: Int
    let algorithm: HWCCloudSnapshotEncryptionAlgorithm
    let keyID: String
    let snapshotID: UUID
    let parentSnapshotIDs: [UUID]
    let originDeviceID: String
    let originSequence: UInt64
    let createdAtMilliseconds: Int64
    let plaintextHash: Data

    init(
        envelopeVersion: Int,
        algorithm: HWCCloudSnapshotEncryptionAlgorithm,
        keyID: String,
        snapshotID: UUID,
        parentSnapshotIDs: [UUID],
        originDeviceID: String,
        originSequence: UInt64,
        createdAtMilliseconds: Int64,
        plaintextHash: Data
    ) {
        self.envelopeVersion = envelopeVersion
        self.algorithm = algorithm
        self.keyID = keyID
        self.snapshotID = snapshotID
        self.parentSnapshotIDs = parentSnapshotIDs
        self.originDeviceID = originDeviceID
        self.originSequence = originSequence
        self.createdAtMilliseconds = createdAtMilliseconds
        self.plaintextHash = plaintextHash
    }

    init(envelope: HWCEncryptedCloudSnapshotEnvelope) {
        self.init(
            envelopeVersion: envelope.envelopeVersion,
            algorithm: envelope.algorithm,
            keyID: envelope.keyID,
            snapshotID: envelope.snapshotID,
            parentSnapshotIDs: envelope.parentSnapshotIDs,
            originDeviceID: envelope.originDeviceID,
            originSequence: envelope.originSequence,
            createdAtMilliseconds: envelope.createdAtMilliseconds,
            plaintextHash: envelope.plaintextHash
        )
    }
}

enum HWCCloudSnapshotMerger {
    static func merge(
        _ local: HWCCloudSnapshotPayload,
        _ remote: HWCCloudSnapshotPayload,
        mergedSnapshotID: UUID,
        originDeviceID: String,
        originSequence: UInt64,
        createdAtMilliseconds: Int64
    ) throws -> HWCCloudSnapshotPayload {
        try local.validate()
        try remote.validate()
        guard local.snapshotID != remote.snapshotID,
              mergedSnapshotID != local.snapshotID,
              mergedSnapshotID != remote.snapshotID,
              !originDeviceID.isEmpty else {
            throw HWCCloudSnapshotError.invalidSnapshot(mergedSnapshotID.uuidString)
        }

        let localByID = currentObjects(in: local)
        let remoteByID = currentObjects(in: remote)
        let allStoreIDs = Set(localByID.keys).union(remoteByID.keys)
        var records = [HWCCloudSnapshotRecord]()
        var tombstones = [HWCCloudSnapshotStoreTombstone]()
        var recordConflicts = local.retainedConflictRecords + remote.retainedConflictRecords
        var tombstoneConflicts = local.retainedConflictTombstones + remote.retainedConflictTombstones

        for id in allStoreIDs.sorted(by: { $0.rawValue < $1.rawValue }) {
            switch (localByID[id], remoteByID[id]) {
            case (.some(let localObject), .some(let remoteObject)):
                let preference = preferredCurrentObject(
                    localObject,
                    from: local,
                    remoteObject,
                    from: remote
                )
                append(preference.winner, records: &records, tombstones: &tombstones)
                if !sameCurrentObject(localObject, remoteObject) {
                    switch preference.loser {
                    case .record(let record):
                        recordConflicts.append(record)
                    case .tombstone(let tombstone):
                        tombstoneConflicts.append(tombstone)
                    }
                }
            case (.some(let object), .none):
                append(object, records: &records, tombstones: &tombstones)
            case (.none, .some(let object)):
                append(object, records: &records, tombstones: &tombstones)
            case (.none, .none):
                break
            }
        }

        var seenRecordHashes = Set<Data>()
        let retainedRecords = recordConflicts
            .filter { seenRecordHashes.insert($0.contentHash).inserted }
            .sorted {
                if $0.id != $1.id { return $0.id.rawValue < $1.id.rawValue }
                if $0.modifiedAtMilliseconds != $1.modifiedAtMilliseconds {
                    return $0.modifiedAtMilliseconds < $1.modifiedAtMilliseconds
                }
                return $0.contentHash.lexicographicallyPrecedes($1.contentHash)
            }
        var seenTombstoneHashes = Set<Data>()
        let retainedTombstones = tombstoneConflicts
            .filter { seenTombstoneHashes.insert($0.contentHash).inserted }
            .sorted {
                if $0.id != $1.id { return $0.id.rawValue < $1.id.rawValue }
                if $0.modifiedAtMilliseconds != $1.modifiedAtMilliseconds {
                    return $0.modifiedAtMilliseconds < $1.modifiedAtMilliseconds
                }
                return $0.contentHash.lexicographicallyPrecedes($1.contentHash)
            }
        let merged = HWCCloudSnapshotPayload(
            snapshotID: mergedSnapshotID,
            parentSnapshotIDs: [local.snapshotID, remote.snapshotID].sorted {
                $0.uuidString < $1.uuidString
            },
            originDeviceID: originDeviceID,
            originSequence: originSequence,
            createdAtMilliseconds: createdAtMilliseconds,
            records: records,
            storeTombstones: tombstones,
            retainedConflictRecords: retainedRecords,
            retainedConflictTombstones: retainedTombstones
        )
        try merged.validate()
        return merged
    }

    private enum CurrentObject {
        case record(HWCCloudSnapshotRecord)
        case tombstone(HWCCloudSnapshotStoreTombstone)

        var id: HWCCloudSnapshotStoreID {
            switch self {
            case .record(let value): return value.id
            case .tombstone(let value): return value.id
            }
        }

        var revision: UInt64 {
            switch self {
            case .record(let value): return value.revision
            case .tombstone(let value): return value.revision
            }
        }

        var modifiedAtMilliseconds: Int64 {
            switch self {
            case .record(let value): return value.modifiedAtMilliseconds
            case .tombstone(let value): return value.modifiedAtMilliseconds
            }
        }

        var contentHash: Data {
            switch self {
            case .record(let value): return value.contentHash
            case .tombstone(let value): return value.contentHash
            }
        }
    }

    private static func currentObjects(
        in payload: HWCCloudSnapshotPayload
    ) -> [HWCCloudSnapshotStoreID: CurrentObject] {
        var result = Dictionary(uniqueKeysWithValues: payload.records.map {
            ($0.id, CurrentObject.record($0))
        })
        for tombstone in payload.storeTombstones {
            result[tombstone.id] = .tombstone(tombstone)
        }
        return result
    }

    private static func sameCurrentObject(
        _ lhs: CurrentObject,
        _ rhs: CurrentObject
    ) -> Bool {
        switch (lhs, rhs) {
        case (.record(let left), .record(let right)):
            return left.contentHash == right.contentHash
        case (.tombstone(let left), .tombstone(let right)):
            return left.contentHash == right.contentHash
        default:
            return false
        }
    }

    private static func append(
        _ object: CurrentObject,
        records: inout [HWCCloudSnapshotRecord],
        tombstones: inout [HWCCloudSnapshotStoreTombstone]
    ) {
        switch object {
        case .record(let record): records.append(record)
        case .tombstone(let tombstone): tombstones.append(tombstone)
        }
    }

    private static func preferredCurrentObject(
        _ localObject: CurrentObject,
        from local: HWCCloudSnapshotPayload,
        _ remoteObject: CurrentObject,
        from remote: HWCCloudSnapshotPayload
    ) -> (winner: CurrentObject, loser: CurrentObject) {
        if local.parentSnapshotIDs.contains(remote.snapshotID) {
            return (localObject, remoteObject)
        }
        if remote.parentSnapshotIDs.contains(local.snapshotID) {
            return (remoteObject, localObject)
        }
        let localOrder = (
            localObject.modifiedAtMilliseconds,
            localObject.revision,
            local.originSequence,
            local.originDeviceID
        )
        let remoteOrder = (
            remoteObject.modifiedAtMilliseconds,
            remoteObject.revision,
            remote.originSequence,
            remote.originDeviceID
        )
        if order(localOrder, precedes: remoteOrder) {
            return (remoteObject, localObject)
        }
        if order(remoteOrder, precedes: localOrder) {
            return (localObject, remoteObject)
        }
        if localObject.contentHash.lexicographicallyPrecedes(remoteObject.contentHash) {
            return (remoteObject, localObject)
        }
        return (localObject, remoteObject)
    }

    private static func order(
        _ lhs: (Int64, UInt64, UInt64, String),
        precedes rhs: (Int64, UInt64, UInt64, String)
    ) -> Bool {
        if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
        if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
        if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
        return lhs.3 < rhs.3
    }
}

protocol HWCCloudSnapshotValueStore: AnyObject {
    var values: [String: HWCCloudSnapshotValue] { get }
    func replaceValues(_ values: [String: HWCCloudSnapshotValue])
}

final class HWCCloudSnapshotMemoryValueStore: HWCCloudSnapshotValueStore {
    private(set) var values: [String: HWCCloudSnapshotValue]

    init(values: [String: HWCCloudSnapshotValue] = [:]) {
        self.values = values
    }

    func replaceValues(_ values: [String: HWCCloudSnapshotValue]) {
        self.values = values
    }
}

enum HWCCloudSnapshotRestorer {
    static func restore(
        _ payload: HWCCloudSnapshotPayload,
        registry: HWCCloudSnapshotRegistry,
        into destination: HWCCloudSnapshotValueStore
    ) throws {
        try payload.validate()

        var validatedEntries = [HWCCloudSnapshotEntry]()
        for record in payload.records {
            guard let descriptor = registry.descriptor(for: record.id) else {
                throw HWCCloudSnapshotError.unknownStore(record.id)
            }
            guard record.schemaVersion == descriptor.schemaVersion else {
                throw HWCCloudSnapshotError.unsupportedStoreSchema(
                    record.id,
                    record.schemaVersion
                )
            }
            for entry in record.entries where !descriptor.snapshotKeys.contains(entry.key) {
                throw HWCCloudSnapshotError.unexpectedStoreKey(record.id, entry.key)
            }
            let encodedSize = try HWCCloudSnapshotCoding.encode(record.entries).count
            guard encodedSize <= descriptor.maximumEncodedBytes else {
                throw HWCCloudSnapshotError.recordTooLarge(record.id, encodedSize)
            }
            validatedEntries.append(contentsOf: record.entries)
        }
        for tombstone in payload.storeTombstones {
            guard let descriptor = registry.descriptor(for: tombstone.id) else {
                throw HWCCloudSnapshotError.unknownStore(tombstone.id)
            }
            guard tombstone.schemaVersion == descriptor.schemaVersion else {
                throw HWCCloudSnapshotError.unsupportedStoreSchema(
                    tombstone.id,
                    tombstone.schemaVersion
                )
            }
            try tombstone.validate()
            validatedEntries.append(contentsOf: descriptor.snapshotKeys.map {
                HWCCloudSnapshotEntry(key: $0, value: nil)
            })
        }

        var nextValues = destination.values
        for entry in validatedEntries {
            if let value = entry.value {
                nextValues[entry.key] = value
            } else {
                nextValues.removeValue(forKey: entry.key)
            }
        }
        destination.replaceValues(nextValues)
    }
}

enum HWCCloudSnapshotAccountStatus: String, Codable, Equatable, Sendable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

enum HWCCloudSnapshotPendingReason: String, Codable, Equatable, Sendable {
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

enum HWCCloudSnapshotSystemAction: Equatable, Sendable {
    case reconcile
    case keepLocalPending(reason: HWCCloudSnapshotPendingReason)
}

enum HWCCloudSnapshotSystemPolicy {
    static func action(
        accountStatus: HWCCloudSnapshotAccountStatus
    ) -> HWCCloudSnapshotSystemAction {
        switch accountStatus {
        case .available:
            return .reconcile
        case .noAccount:
            return .keepLocalPending(reason: .noAccount)
        case .restricted:
            return .keepLocalPending(reason: .restricted)
        case .couldNotDetermine:
            return .keepLocalPending(reason: .couldNotDetermine)
        case .temporarilyUnavailable:
            return .keepLocalPending(reason: .temporarilyUnavailable)
        }
    }
}

private enum HWCCloudSnapshotCoding {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}

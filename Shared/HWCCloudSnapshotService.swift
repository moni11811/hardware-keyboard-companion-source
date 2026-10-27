import Foundation

extension Notification.Name {
    static let hwcCloudSnapshotSourceDidChange = Notification.Name(
        "dev.moni11811.hwc.cloud-snapshot-source-did-change"
    )
}

protocol HWCCloudSnapshotIdentityStoring: AnyObject {
    var deviceID: String { get }
    func takeNextSequence() -> UInt64
}

final class HWCCloudSnapshotMemoryIdentityStore: HWCCloudSnapshotIdentityStoring {
    let deviceID: String
    private var nextValue: UInt64

    init(deviceID: String, nextSequence: UInt64 = 1) {
        self.deviceID = deviceID
        nextValue = nextSequence
    }

    func takeNextSequence() -> UInt64 {
        defer { nextValue += 1 }
        return nextValue
    }
}

final class HWCCloudSnapshotUserDefaultsIdentityStore: HWCCloudSnapshotIdentityStoring {
    private static let deviceIDKey = "cloudSnapshot.originDeviceID.v1"
    private static let sequenceKey = "cloudSnapshot.originSequence.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    var deviceID: String {
        lock.lock()
        defer { lock.unlock() }
        if let stored = defaults.string(forKey: Self.deviceIDKey), !stored.isEmpty {
            return stored
        }
        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: Self.deviceIDKey)
        defaults.synchronize()
        return generated
    }

    func takeNextSequence() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let stored = defaults.object(forKey: Self.sequenceKey) as? NSNumber
        let next = max(1, stored?.uint64Value ?? 1)
        defaults.set(NSNumber(value: next + 1), forKey: Self.sequenceKey)
        defaults.synchronize()
        return next
    }
}

enum HWCCloudSnapshotServiceResult: Equatable, Sendable {
    case synchronized(
        head: HWCCloudSnapshotRemoteHead,
        restoredRemote: Bool,
        uploaded: Bool
    )
    case localPending(HWCCloudSnapshotSyncPendingReason)
}

/// Cloud record metadata is useful for choosing a generation, but is not
/// authenticated until `inspectRemoteGeneration(snapshotID:)` opens its
/// encrypted envelope.
struct HWCCloudSnapshotGenerationMetadata: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let keyID: String
    let originSequence: UInt64
    let createdAtMilliseconds: Int64
}

struct HWCCloudSnapshotGenerationListing: Equatable, Sendable {
    let metadata: [HWCCloudSnapshotGenerationMetadata]
    let omittedGenerationCount: Int
}

/// CloudKit history is advisory until a selected envelope authenticates. One
/// malformed metadata row must not hide unrelated immutable generations.
struct HWCCloudSnapshotGenerationMetadataCandidate: Equatable, Sendable {
    let recordName: String?
    let snapshotIDString: String?
    let keyID: String?
    let originSequence: Int64?
    let createdAtMilliseconds: Int64?

    init(
        recordName: String? = nil,
        snapshotIDString: String?,
        keyID: String?,
        originSequence: Int64?,
        createdAtMilliseconds: Int64?
    ) {
        self.recordName = recordName
        self.snapshotIDString = snapshotIDString
        self.keyID = keyID
        self.originSequence = originSequence
        self.createdAtMilliseconds = createdAtMilliseconds
    }
}

enum HWCCloudSnapshotGenerationMetadataValidator {
    static func listing(
        from candidates: [HWCCloudSnapshotGenerationMetadataCandidate]
    ) -> HWCCloudSnapshotGenerationListing {
        var metadata: [HWCCloudSnapshotGenerationMetadata] = []
        var seenSnapshotIDs = Set<UUID>()
        var omittedGenerationCount = 0

        for candidate in candidates {
            guard let snapshotIDString = candidate.snapshotIDString,
                  let snapshotID = UUID(uuidString: snapshotIDString),
                  candidate.recordName == canonicalRecordName(for: snapshotID),
                  let keyID = candidate.keyID,
                  !keyID.isEmpty,
                  let originSequence = candidate.originSequence,
                  originSequence > 0,
                  let createdAtMilliseconds = candidate.createdAtMilliseconds,
                  createdAtMilliseconds > 0,
                  seenSnapshotIDs.insert(snapshotID).inserted else {
                omittedGenerationCount += 1
                continue
            }
            metadata.append(HWCCloudSnapshotGenerationMetadata(
                snapshotID: snapshotID,
                keyID: keyID,
                originSequence: UInt64(originSequence),
                createdAtMilliseconds: createdAtMilliseconds
            ))
        }
        return HWCCloudSnapshotGenerationListing(
            metadata: metadata,
            omittedGenerationCount: omittedGenerationCount
        )
    }

    static func validMetadata(
        from candidates: [HWCCloudSnapshotGenerationMetadataCandidate]
    ) -> [HWCCloudSnapshotGenerationMetadata] {
        listing(from: candidates).metadata
    }

    private static func canonicalRecordName(for snapshotID: UUID) -> String {
        "generation-\(snapshotID.uuidString.lowercased())"
    }
}

/// Non-sensitive, authenticated summary of a selected encrypted generation.
struct HWCCloudSnapshotGenerationInspection: Equatable, Sendable {
    let snapshotID: UUID
    let keyID: String
    let parentSnapshotIDs: [UUID]
    let createdAtMilliseconds: Int64
    let storeIDs: [HWCCloudSnapshotStoreID]
    let entryCount: Int
    let retainedConflictCount: Int
}

enum HWCCloudSnapshotHistoryError: Error, Equatable, Sendable {
    case unsupportedTransport
    case missingDecryptionKey(keyID: String)
    case invalidGeneration
    case cloudUnavailable(HWCCloudSnapshotSyncPendingReason)
}

/// Kept separate from the head/sync protocol so existing sync-only transports
/// fail closed instead of silently presenting an incomplete backup history.
protocol HWCCloudSnapshotHistoryRemoteTransport: AnyObject {
    func listGenerationMetadata() async throws -> HWCCloudSnapshotGenerationListing
}

/// End-to-end snapshot orchestration. It restores a remote generation first only
/// when the caller proves local state is empty/seeded. Otherwise it snapshots
/// local state before remote reads, preserving both branches through the sync
/// coordinator and applying only the authenticated committed result.
actor HWCCloudSnapshotService {
    private let registry: HWCCloudSnapshotRegistry
    private let backing: HWCCloudSnapshotUserDefaultsBacking
    private let transformers: [HWCCloudSnapshotStoreID: HWCCloudSnapshotStoreTransformer]
    private let transport: HWCCloudSnapshotRemoteTransport
    private let outbox: HWCCloudSnapshotHistoryOutbox
    private let keyRing: HWCCloudSnapshotKeyRing
    private let identityStore: HWCCloudSnapshotIdentityStoring
    private let makeUUID: () -> UUID
    private let nowMilliseconds: () -> Int64

    init(
        registry: HWCCloudSnapshotRegistry,
        backing: HWCCloudSnapshotUserDefaultsBacking,
        transformers: [HWCCloudSnapshotStoreID: HWCCloudSnapshotStoreTransformer],
        transport: HWCCloudSnapshotRemoteTransport,
        outbox: HWCCloudSnapshotHistoryOutbox,
        keyRing: HWCCloudSnapshotKeyRing,
        identityStore: HWCCloudSnapshotIdentityStoring,
        makeUUID: @escaping () -> UUID = UUID.init,
        nowMilliseconds: @escaping () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }
    ) {
        self.registry = registry
        self.backing = backing
        self.transformers = transformers
        self.transport = transport
        self.outbox = outbox
        self.keyRing = keyRing
        self.identityStore = identityStore
        self.makeUUID = makeUUID
        self.nowMilliseconds = nowMilliseconds
    }

    func reconcile(
        localIsSafeToReplace: Bool
    ) async -> HWCCloudSnapshotServiceResult {
        await reconcile(
            localIsSafeToReplace: localIsSafeToReplace,
            remainingLocalChangeRetries: 1
        )
    }

    func listRemoteHistory() async throws -> HWCCloudSnapshotGenerationListing {
        guard let historyTransport = transport as? HWCCloudSnapshotHistoryRemoteTransport else {
            throw HWCCloudSnapshotHistoryError.unsupportedTransport
        }
        do {
            let listing = try await historyTransport.listGenerationMetadata()
            return HWCCloudSnapshotGenerationListing(
                metadata: listing.metadata.sorted(by: Self.newestFirst),
                omittedGenerationCount: listing.omittedGenerationCount
            )
        } catch let error as HWCCloudSnapshotRemoteError {
            throw HWCCloudSnapshotHistoryError.cloudUnavailable(Self.pendingReason(error))
        }
    }

    func inspectRemoteGeneration(
        snapshotID: UUID
    ) async throws -> HWCCloudSnapshotGenerationInspection {
        let envelope: HWCEncryptedCloudSnapshotEnvelope
        do {
            envelope = try await transport.fetchEnvelope(snapshotID: snapshotID)
        } catch let error as HWCCloudSnapshotRemoteError {
            throw HWCCloudSnapshotHistoryError.cloudUnavailable(Self.pendingReason(error))
        }
        guard envelope.snapshotID == snapshotID,
              let key = keyRing.keyData(for: envelope.keyID) else {
            throw HWCCloudSnapshotHistoryError.missingDecryptionKey(keyID: envelope.keyID)
        }
        do {
            let payload = try HWCCloudSnapshotCryptor.open(envelope, keyData: key)
            return HWCCloudSnapshotGenerationInspection(
                snapshotID: payload.snapshotID,
                keyID: envelope.keyID,
                parentSnapshotIDs: payload.parentSnapshotIDs,
                createdAtMilliseconds: payload.createdAtMilliseconds,
                storeIDs: payload.records.map(\.id).sorted { $0.rawValue < $1.rawValue },
                entryCount: payload.records.reduce(0) { $0 + $1.entries.count },
                retainedConflictCount: payload.retainedConflictRecords.count +
                    payload.retainedConflictTombstones.count
            )
        } catch {
            throw HWCCloudSnapshotHistoryError.invalidGeneration
        }
    }

    /// Restores a selected immutable generation locally, then immediately
    /// commits a distinct successor envelope. Neither the selected record nor
    /// any older envelope is edited or deleted.
    func restoreRemoteGeneration(
        snapshotID: UUID
    ) async throws -> HWCCloudSnapshotRemoteHead {
        let accountStatus = await transport.accountStatus()
        switch HWCCloudSnapshotSystemPolicy.action(accountStatus: accountStatus) {
        case .reconcile:
            break
        case .keepLocalPending(let reason):
            throw HWCCloudSnapshotHistoryError.cloudUnavailable(Self.syncReason(reason))
        }

        let selectedEnvelope: HWCEncryptedCloudSnapshotEnvelope
        let expectedHead: HWCCloudSnapshotRemoteHead?
        do {
            expectedHead = try await transport.fetchHead()
            selectedEnvelope = try await transport.fetchEnvelope(snapshotID: snapshotID)
        } catch let error as HWCCloudSnapshotRemoteError {
            throw HWCCloudSnapshotHistoryError.cloudUnavailable(Self.pendingReason(error))
        }
        guard selectedEnvelope.snapshotID == snapshotID,
              let selectedKey = keyRing.keyData(for: selectedEnvelope.keyID) else {
            throw HWCCloudSnapshotHistoryError.missingDecryptionKey(keyID: selectedEnvelope.keyID)
        }

        let selectedPayload: HWCCloudSnapshotPayload
        do {
            selectedPayload = try HWCCloudSnapshotCryptor.open(
                selectedEnvelope,
                keyData: selectedKey
            )
        } catch {
            throw HWCCloudSnapshotHistoryError.invalidGeneration
        }

        let successorPayload = HWCCloudSnapshotPayload(
            snapshotID: makeUUID(),
            parentSnapshotIDs: [selectedPayload.snapshotID],
            originDeviceID: identityStore.deviceID,
            originSequence: identityStore.takeNextSequence(),
            createdAtMilliseconds: nowMilliseconds(),
            records: selectedPayload.records,
            storeTombstones: selectedPayload.storeTombstones,
            retainedConflictRecords: selectedPayload.retainedConflictRecords,
            retainedConflictTombstones: selectedPayload.retainedConflictTombstones
        )
        let successorKey: HWCCloudSnapshotKey
        let successorEnvelope: HWCEncryptedCloudSnapshotEnvelope
        let restoreMutation: HWCCloudSnapshotUserDefaultsMutation
        do {
            try successorPayload.validate()
            successorKey = try keyRing.currentKey()
            successorEnvelope = try HWCCloudSnapshotCryptor.seal(
                successorPayload,
                keyData: successorKey.data
            )
            restoreMutation = try HWCCloudSnapshotUserDefaultsAdapter.validatedRestoreMutation(
                selectedPayload,
                registry: registry,
                transformers: transformers
            )
            try outbox.persist(successorEnvelope)
        } catch {
            throw HWCCloudSnapshotHistoryError.invalidGeneration
        }

        do {
            let committed = try await transport.commitAtomically(
                envelope: successorEnvelope,
                expectedHead: expectedHead
            )
            try backing.replaceAtomically(restoreMutation)
            try outbox.confirm(snapshotID: successorEnvelope.snapshotID, remoteHead: committed)
            HWKAutobotEpisodeFingerprint.invalidateCachedKey()
            KeyboardSharedPreferences.postSettingsDidChangeNotification()
            return committed
        } catch let error as HWCCloudSnapshotRemoteError {
            throw HWCCloudSnapshotHistoryError.cloudUnavailable(Self.pendingReason(error))
        } catch {
            throw HWCCloudSnapshotHistoryError.invalidGeneration
        }
    }

    private func reconcile(
        localIsSafeToReplace: Bool,
        remainingLocalChangeRetries: Int
    ) async -> HWCCloudSnapshotServiceResult {
        var restoredRemote = false
        do {
            if try outbox.loadEnvelopes().isEmpty, localIsSafeToReplace {
                switch await restoreInitialRemoteIfPresent() {
                case .restored:
                    restoredRemote = true
                case .none:
                    break
                case .pending(let reason):
                    return .localPending(reason)
                }
            }

            let previous = try latestLocalPayload()
            let now = nowMilliseconds()
            let stagedRecords = try HWCCloudSnapshotUserDefaultsAdapter.capture(
                from: backing,
                registry: registry,
                revision: 1,
                modifiedAtMilliseconds: now,
                transformers: transformers
            )
            let previousByID = Dictionary(uniqueKeysWithValues:
                (previous?.records ?? []).map { ($0.id, $0) }
            )
            let changed = stagedRecords.contains { staged in
                guard let prior = previousByID[staged.id] else { return true }
                return staged.schemaVersion != prior.schemaVersion ||
                    staged.entries != prior.entries
            }

            let candidate: HWCCloudSnapshotPayload
            let candidateWasExisting: Bool
            if !changed, let previous {
                candidate = previous
                candidateWasExisting = true
            } else {
                let sequence = identityStore.takeNextSequence()
                let records = try stagedRecords.map { staged -> HWCCloudSnapshotRecord in
                    if let prior = previousByID[staged.id],
                       prior.schemaVersion == staged.schemaVersion,
                       prior.entries == staged.entries {
                        return prior
                    }
                    return try HWCCloudSnapshotRecord.make(
                        id: staged.id,
                        schemaVersion: staged.schemaVersion,
                        revision: sequence,
                        modifiedAtMilliseconds: now,
                        entries: staged.entries
                    )
                }
                candidate = HWCCloudSnapshotPayload(
                    snapshotID: makeUUID(),
                    parentSnapshotIDs: previous.map { [$0.snapshotID] } ?? [],
                    originDeviceID: identityStore.deviceID,
                    originSequence: sequence,
                    createdAtMilliseconds: now,
                    records: records,
                    retainedConflictRecords: previous?.retainedConflictRecords ?? [],
                    retainedConflictTombstones: previous?.retainedConflictTombstones ?? []
                )
                try candidate.validate()
                candidateWasExisting = false
            }

            let coordinator = HWCCloudSnapshotSyncCoordinator(
                transport: transport,
                outbox: outbox,
                keyRing: keyRing,
                makeUUID: makeUUID,
                nowMilliseconds: nowMilliseconds
            )
            switch await coordinator.synchronize(localPayload: candidate) {
            case .pending(let reason):
                return .localPending(reason)
            case .committed(let head):
                guard try localSourceStillMatches(stagedRecords) else {
                    guard remainingLocalChangeRetries > 0 else {
                        return .localPending(.localChangedDuringSync)
                    }
                    let retried = await reconcile(
                        localIsSafeToReplace: false,
                        remainingLocalChangeRetries: remainingLocalChangeRetries - 1
                    )
                    if restoredRemote,
                       case .synchronized(let retryHead, _, let uploaded) = retried {
                        return .synchronized(
                            head: retryHead,
                            restoredRemote: true,
                            uploaded: uploaded
                        )
                    }
                    return retried
                }
                if head.snapshotID != candidate.snapshotID {
                    try applyCommittedGeneration(head)
                }
                return .synchronized(
                    head: head,
                    restoredRemote: restoredRemote,
                    uploaded: !candidateWasExisting || head.snapshotID != candidate.snapshotID
                )
            }
        } catch let error as ServiceError {
            switch error {
            case .missingKey(let keyID):
                return .localPending(.missingDecryptionKey(keyID: keyID))
            case .invalidLocal:
                return .localPending(.localPersistenceFailure)
            case .invalidRemote:
                return .localPending(.invalidRemoteSnapshot)
            }
        } catch let error as HWCCloudSnapshotRemoteError {
            return .localPending(Self.pendingReason(error))
        } catch let error as HWKEncryptedClipboardStoreError
            where error == .keyUnavailable {
            return .localPending(.keyStoreFailure)
        } catch {
            return .localPending(.localPersistenceFailure)
        }
    }

    private func localSourceStillMatches(
        _ capturedRecords: [HWCCloudSnapshotRecord]
    ) throws -> Bool {
        let current = try HWCCloudSnapshotUserDefaultsAdapter.capture(
            from: backing,
            registry: registry,
            revision: 1,
            modifiedAtMilliseconds: 0,
            transformers: transformers
        )
        let capturedEntries = Dictionary(uniqueKeysWithValues:
            capturedRecords.map { ($0.id, $0.entries) }
        )
        let currentEntries = Dictionary(uniqueKeysWithValues:
            current.map { ($0.id, $0.entries) }
        )
        return currentEntries == capturedEntries
    }

    private func restoreInitialRemoteIfPresent() async -> InitialRestoreResult {
        let status = await transport.accountStatus()
        guard case .reconcile = HWCCloudSnapshotSystemPolicy.action(
            accountStatus: status
        ) else {
            return .none
        }
        do {
            guard let head = try await transport.fetchHead() else { return .none }
            let envelope = try await transport.fetchEnvelope(snapshotID: head.snapshotID)
            guard envelope.keyID == head.keyID,
                  let key = keyRing.keyData(for: envelope.keyID) else {
                return .pending(.missingDecryptionKey(keyID: envelope.keyID))
            }
            let payload: HWCCloudSnapshotPayload
            do {
                payload = try HWCCloudSnapshotCryptor.open(envelope, keyData: key)
                try HWCCloudSnapshotUserDefaultsAdapter.restore(
                    payload,
                    registry: registry,
                    into: backing,
                    transformers: transformers
                )
            } catch {
                return .pending(.invalidRemoteSnapshot)
            }
            try outbox.persist(envelope)
            try outbox.confirm(snapshotID: envelope.snapshotID, remoteHead: head)
            HWKAutobotEpisodeFingerprint.invalidateCachedKey()
            KeyboardSharedPreferences.postSettingsDidChangeNotification()
            return .restored
        } catch let error as HWCCloudSnapshotRemoteError {
            return .pending(Self.pendingReason(error))
        } catch {
            return .pending(.invalidRemoteSnapshot)
        }
    }

    private func latestLocalPayload() throws -> HWCCloudSnapshotPayload? {
        let envelopes = try outbox.loadEnvelopes()
        guard !envelopes.isEmpty else {
            return nil
        }

        var envelopesByID: [UUID: HWCEncryptedCloudSnapshotEnvelope] = [:]
        var parentSnapshotIDs = Set<UUID>()
        for envelope in envelopes {
            envelopesByID[envelope.snapshotID] = envelope
            parentSnapshotIDs.formUnion(envelope.parentSnapshotIDs)
        }
        let leaves = envelopes.filter {
            !parentSnapshotIDs.contains($0.snapshotID)
        }
        let nonCyclicCandidates = leaves.isEmpty ? envelopes : leaves
        let causalCandidates: [HWCEncryptedCloudSnapshotEnvelope]
        if let confirmedSnapshotID = outbox.confirmedHead?.snapshotID {
            let descendants = nonCyclicCandidates.filter {
                Self.envelope(
                    $0,
                    descendsFromOrEquals: confirmedSnapshotID,
                    envelopesByID: envelopesByID
                )
            }
            causalCandidates = descendants.isEmpty
                ? nonCyclicCandidates
                : descendants
        } else {
            causalCandidates = nonCyclicCandidates
        }
        let localDeviceID = identityStore.deviceID
        guard let latest = causalCandidates.max(by: { lhs, rhs in
            let lhsIsLocal = lhs.originDeviceID == localDeviceID
            let rhsIsLocal = rhs.originDeviceID == localDeviceID
            if lhsIsLocal != rhsIsLocal {
                return !lhsIsLocal && rhsIsLocal
            }
            if lhs.originDeviceID == rhs.originDeviceID,
               lhs.originSequence != rhs.originSequence {
                return lhs.originSequence < rhs.originSequence
            }
            return lhs.snapshotID.uuidString < rhs.snapshotID.uuidString
        }) else {
            return nil
        }
        guard let key = keyRing.keyData(for: latest.keyID) else {
            throw ServiceError.missingKey(latest.keyID)
        }
        do {
            return try HWCCloudSnapshotCryptor.open(latest, keyData: key)
        } catch {
            throw ServiceError.invalidLocal
        }
    }

    private static func envelope(
        _ envelope: HWCEncryptedCloudSnapshotEnvelope,
        descendsFromOrEquals ancestorSnapshotID: UUID,
        envelopesByID: [UUID: HWCEncryptedCloudSnapshotEnvelope]
    ) -> Bool {
        var pending = [envelope.snapshotID]
        var visited = Set<UUID>()
        while let snapshotID = pending.popLast() {
            if snapshotID == ancestorSnapshotID {
                return true
            }
            guard visited.insert(snapshotID).inserted,
                  let candidate = envelopesByID[snapshotID] else {
                continue
            }
            pending.append(contentsOf: candidate.parentSnapshotIDs)
        }
        return false
    }

    private func applyCommittedGeneration(
        _ head: HWCCloudSnapshotRemoteHead
    ) throws {
        guard let envelope = try outbox.loadEnvelopes().first(where: {
            $0.snapshotID == head.snapshotID
        }), let key = keyRing.keyData(for: envelope.keyID) else {
            throw ServiceError.missingKey(head.keyID)
        }
        let payload: HWCCloudSnapshotPayload
        do {
            payload = try HWCCloudSnapshotCryptor.open(envelope, keyData: key)
        } catch {
            throw ServiceError.invalidRemote
        }
        try HWCCloudSnapshotUserDefaultsAdapter.restore(
            payload,
            registry: registry,
            into: backing,
            transformers: transformers
        )
        HWKAutobotEpisodeFingerprint.invalidateCachedKey()
        KeyboardSharedPreferences.postSettingsDidChangeNotification()
    }

    private static func pendingReason(
        _ error: HWCCloudSnapshotRemoteError
    ) -> HWCCloudSnapshotSyncPendingReason {
        switch error {
        case .headChanged: return .headChanged
        case .quotaExceeded: return .quotaExceeded
        case .networkUnavailable: return .networkUnavailable
        case .permissionDenied: return .permissionDenied
        case .missingGeneration: return .remoteGenerationMissing
        case .serverRejected: return .serverRejected
        case .unknown: return .unknown
        }
    }

    private static func syncReason(
        _ reason: HWCCloudSnapshotPendingReason
    ) -> HWCCloudSnapshotSyncPendingReason {
        switch reason {
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine: return .couldNotDetermine
        case .temporarilyUnavailable: return .temporarilyUnavailable
        }
    }

    private static func newestFirst(
        _ lhs: HWCCloudSnapshotGenerationMetadata,
        _ rhs: HWCCloudSnapshotGenerationMetadata
    ) -> Bool {
        if lhs.createdAtMilliseconds != rhs.createdAtMilliseconds {
            return lhs.createdAtMilliseconds > rhs.createdAtMilliseconds
        }
        if lhs.originSequence != rhs.originSequence {
            return lhs.originSequence > rhs.originSequence
        }
        return lhs.snapshotID.uuidString > rhs.snapshotID.uuidString
    }

    private enum InitialRestoreResult {
        case restored
        case none
        case pending(HWCCloudSnapshotSyncPendingReason)
    }

    private enum ServiceError: Error {
        case missingKey(String)
        case invalidLocal
        case invalidRemote
    }
}

import Foundation

struct HWCCloudSnapshotRemoteHead: Codable, Equatable, Sendable {
    let snapshotID: UUID
    let generation: UInt64
    let keyID: String
    let revisionToken: String
}

enum HWCCloudSnapshotRemoteError: Error, Equatable, Sendable {
    case headChanged
    case quotaExceeded
    case networkUnavailable
    case permissionDenied
    case missingGeneration
    case serverRejected
    case unknown
}

enum HWCCloudSnapshotSyncPendingReason: Equatable, Sendable {
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case missingDecryptionKey(keyID: String)
    case invalidRemoteSnapshot
    case remoteGenerationMissing
    case quotaExceeded
    case networkUnavailable
    case permissionDenied
    case headChanged
    case localChangedDuringSync
    case serverRejected
    case localPersistenceFailure
    case keyStoreFailure
    case unknown
}

enum HWCCloudSnapshotSyncResult: Equatable, Sendable {
    case committed(HWCCloudSnapshotRemoteHead)
    case pending(HWCCloudSnapshotSyncPendingReason)
}

protocol HWCCloudSnapshotRemoteTransport: AnyObject {
    func accountStatus() async -> HWCCloudSnapshotAccountStatus
    func fetchHead() async throws -> HWCCloudSnapshotRemoteHead?
    func fetchEnvelope(snapshotID: UUID) async throws -> HWCEncryptedCloudSnapshotEnvelope
    func commitAtomically(
        envelopes: [HWCEncryptedCloudSnapshotEnvelope],
        advancingHeadTo headEnvelope: HWCEncryptedCloudSnapshotEnvelope,
        expectedHead: HWCCloudSnapshotRemoteHead?
    ) async throws -> HWCCloudSnapshotRemoteHead
}

extension HWCCloudSnapshotRemoteTransport {
    func commitAtomically(
        envelope: HWCEncryptedCloudSnapshotEnvelope,
        expectedHead: HWCCloudSnapshotRemoteHead?
    ) async throws -> HWCCloudSnapshotRemoteHead {
        try await commitAtomically(
            envelopes: [envelope],
            advancingHeadTo: envelope,
            expectedHead: expectedHead
        )
    }
}

protocol HWCCloudSnapshotOutbox: AnyObject {
    func persist(_ envelope: HWCEncryptedCloudSnapshotEnvelope) throws
    func confirm(
        snapshotID: UUID,
        remoteHead: HWCCloudSnapshotRemoteHead
    ) throws
}

protocol HWCCloudSnapshotHistoryOutbox: HWCCloudSnapshotOutbox {
    var confirmedHead: HWCCloudSnapshotRemoteHead? { get }
    func loadEnvelopes() throws -> [HWCEncryptedCloudSnapshotEnvelope]
}

struct HWCCloudSnapshotKey: Equatable, Sendable {
    let id: String
    let data: Data

    init(data: Data) throws {
        guard data.count == 32 else { throw HWCCloudSnapshotError.invalidKey }
        self.data = data
        id = HWCCloudSnapshotCryptor.keyIdentifier(for: data)
    }
}

protocol HWCCloudSnapshotKeyRing: AnyObject {
    func currentKey() throws -> HWCCloudSnapshotKey
    func keyData(for keyID: String) -> Data?
}

final class HWCCloudSnapshotMemoryKeyRing: HWCCloudSnapshotKeyRing {
    private var keys: [String: Data]
    private var currentKeyID: String

    init(currentKeyData: Data, historicalKeyData: [Data] = []) {
        var keys = Dictionary(uniqueKeysWithValues: historicalKeyData.map {
            (HWCCloudSnapshotCryptor.keyIdentifier(for: $0), $0)
        })
        let currentID = HWCCloudSnapshotCryptor.keyIdentifier(for: currentKeyData)
        keys[currentID] = currentKeyData
        self.keys = keys
        currentKeyID = currentID
    }

    func currentKey() throws -> HWCCloudSnapshotKey {
        guard let data = keys[currentKeyID] else {
            throw HWCCloudSnapshotError.invalidKey
        }
        return try HWCCloudSnapshotKey(data: data)
    }

    func keyData(for keyID: String) -> Data? {
        keys[keyID]
    }

    func rotate(to data: Data) throws {
        let key = try HWCCloudSnapshotKey(data: data)
        keys[key.id] = key.data
        currentKeyID = key.id
    }
}

final class HWCCloudSnapshotMemoryOutbox: HWCCloudSnapshotHistoryOutbox {
    private(set) var generations: [HWCEncryptedCloudSnapshotEnvelope] = []
    private(set) var confirmedHead: HWCCloudSnapshotRemoteHead?
    private(set) var events: [String] = []

    func persist(_ envelope: HWCEncryptedCloudSnapshotEnvelope) throws {
        if let index = generations.firstIndex(where: { $0.snapshotID == envelope.snapshotID }) {
            generations[index] = envelope
        } else {
            generations.append(envelope)
        }
        events.append("outbox.persist:\(envelope.snapshotID.uuidString)")
    }

    func confirm(
        snapshotID: UUID,
        remoteHead: HWCCloudSnapshotRemoteHead
    ) throws {
        guard generations.contains(where: { $0.snapshotID == snapshotID }),
              remoteHead.snapshotID == snapshotID else {
            throw HWCCloudSnapshotError.invalidSnapshot(snapshotID.uuidString)
        }
        confirmedHead = remoteHead
        events.append("outbox.confirm:\(snapshotID.uuidString)")
    }

    func recordExternalEvent(_ event: String) {
        events.append(event)
    }

    func loadEnvelopes() throws -> [HWCEncryptedCloudSnapshotEnvelope] {
        generations
    }
}

/// Persists an encrypted local generation before any cloud read or write. Remote
/// reconciliation then advances a compare-and-swap head. A failed cloud step
/// leaves every locally acknowledged generation recoverable in the outbox.
final class HWCCloudSnapshotSyncCoordinator {
    private static let maximumRetainedAncestryCount = 512

    private enum LocalEnvelopeResolutionError: Error {
        case missingDecryptionKey(String)
        case payloadMismatch
    }

    private let transport: HWCCloudSnapshotRemoteTransport
    private let outbox: HWCCloudSnapshotOutbox
    private let keyRing: HWCCloudSnapshotKeyRing
    private let makeUUID: () -> UUID
    private let nowMilliseconds: () -> Int64

    init(
        transport: HWCCloudSnapshotRemoteTransport,
        outbox: HWCCloudSnapshotOutbox,
        keyRing: HWCCloudSnapshotKeyRing,
        makeUUID: @escaping () -> UUID = UUID.init,
        nowMilliseconds: @escaping () -> Int64 = {
            Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        }
    ) {
        self.transport = transport
        self.outbox = outbox
        self.keyRing = keyRing
        self.makeUUID = makeUUID
        self.nowMilliseconds = nowMilliseconds
    }

    func synchronize(
        localPayload: HWCCloudSnapshotPayload
    ) async -> HWCCloudSnapshotSyncResult {
        let key: HWCCloudSnapshotKey
        let localEnvelope: HWCEncryptedCloudSnapshotEnvelope
        do {
            try localPayload.validate()
            key = try keyRing.currentKey()
            localEnvelope = try authenticatedLocalEnvelope(
                for: localPayload,
                sealingKey: key
            )
        } catch LocalEnvelopeResolutionError.missingDecryptionKey(let keyID) {
            return .pending(.missingDecryptionKey(keyID: keyID))
        } catch let error as HWCCloudSnapshotError where error == .invalidKey {
            return .pending(.keyStoreFailure)
        } catch {
            return .pending(.localPersistenceFailure)
        }

        let accountStatus = await transport.accountStatus()
        switch HWCCloudSnapshotSystemPolicy.action(accountStatus: accountStatus) {
        case .reconcile:
            break
        case .keepLocalPending(let reason):
            return .pending(Self.syncReason(for: reason))
        }

        var candidate = localPayload
        var locallyPendingEnvelopes: [HWCEncryptedCloudSnapshotEnvelope]
        do {
            locallyPendingEnvelopes = try retainedLocalAncestry(
                endingAt: localEnvelope
            )
        } catch let error as HWCCloudSnapshotError where error == .invalidKey {
            return .pending(.keyStoreFailure)
        } catch {
            return .pending(.localPersistenceFailure)
        }
        for attempt in 0..<2 {
            do {
                let remoteHead = try await transport.fetchHead()
                if let remoteHead, remoteHead.snapshotID == candidate.snapshotID {
                    do {
                        let remoteEnvelope = try await transport.fetchEnvelope(
                            snapshotID: remoteHead.snapshotID
                        )
                        guard remoteEnvelope == localEnvelope,
                              remoteEnvelope.keyID == remoteHead.keyID else {
                            throw HWCCloudSnapshotRemoteError.serverRejected
                        }
                        try outbox.confirm(
                            snapshotID: candidate.snapshotID,
                            remoteHead: remoteHead
                        )
                        return .committed(remoteHead)
                    } catch HWCCloudSnapshotRemoteError.missingGeneration {
                        let repairedHead = try await commitWithRetainedAnchorRepair(
                            envelope: localEnvelope,
                            localEnvelope: localEnvelope,
                            locallyPendingEnvelopes: locallyPendingEnvelopes,
                            expectedHead: remoteHead
                        )
                        try outbox.confirm(
                            snapshotID: candidate.snapshotID,
                            remoteHead: repairedHead
                        )
                        return .committed(repairedHead)
                    }
                }

                let commitPayload: HWCCloudSnapshotPayload
                if let remoteHead,
                   try !candidateDescends(
                       candidate,
                       from: remoteHead.snapshotID
                   ) {
                    let remoteEnvelope = try await transport.fetchEnvelope(
                        snapshotID: remoteHead.snapshotID
                    )
                    guard remoteEnvelope.keyID == remoteHead.keyID,
                          let remoteKey = keyRing.keyData(for: remoteEnvelope.keyID) else {
                        return .pending(.missingDecryptionKey(keyID: remoteEnvelope.keyID))
                    }
                    let remotePayload: HWCCloudSnapshotPayload
                    do {
                        remotePayload = try HWCCloudSnapshotCryptor.open(
                            remoteEnvelope,
                            keyData: remoteKey
                        )
                    } catch {
                        return .pending(.invalidRemoteSnapshot)
                    }
                    if try await remotePayloadDescends(
                        remotePayload,
                        from: candidate.snapshotID
                    ) {
                        try outbox.persist(remoteEnvelope)
                        try outbox.confirm(
                            snapshotID: remoteEnvelope.snapshotID,
                            remoteHead: remoteHead
                        )
                        return .committed(remoteHead)
                    }
                    commitPayload = try HWCCloudSnapshotMerger.merge(
                        candidate,
                        remotePayload,
                        mergedSnapshotID: makeUUID(),
                        originDeviceID: candidate.originDeviceID,
                        originSequence: max(
                            candidate.originSequence,
                            remotePayload.originSequence
                        ) + 1,
                        createdAtMilliseconds: max(
                            nowMilliseconds(),
                            max(
                                candidate.createdAtMilliseconds,
                                remotePayload.createdAtMilliseconds
                            )
                        )
                    )
                } else {
                    commitPayload = candidate
                }

                let envelope: HWCEncryptedCloudSnapshotEnvelope
                do {
                    envelope = try authenticatedLocalEnvelope(
                        for: commitPayload,
                        sealingKey: key
                    )
                } catch LocalEnvelopeResolutionError.missingDecryptionKey(let keyID) {
                    return .pending(.missingDecryptionKey(keyID: keyID))
                } catch let error as HWCCloudSnapshotError where error == .invalidKey {
                    return .pending(.keyStoreFailure)
                } catch {
                    return .pending(.localPersistenceFailure)
                }
                do {
                    let committedHead = try await commitWithRetainedAnchorRepair(
                        envelope: envelope,
                        localEnvelope: localEnvelope,
                        locallyPendingEnvelopes: locallyPendingEnvelopes,
                        expectedHead: remoteHead
                    )
                    try outbox.confirm(
                        snapshotID: envelope.snapshotID,
                        remoteHead: committedHead
                    )
                    return .committed(committedHead)
                } catch HWCCloudSnapshotRemoteError.headChanged where attempt == 0 {
                    locallyPendingEnvelopes = Self.uniqueEnvelopes(
                        locallyPendingEnvelopes + [envelope]
                    )
                    candidate = commitPayload
                    continue
                }
            } catch let error as HWCCloudSnapshotRemoteError {
                return .pending(Self.syncReason(for: error))
            } catch let error as HWCCloudSnapshotError {
                switch error {
                case .authenticationFailed, .invalidSnapshot, .invalidRecord,
                     .unknownStore, .unsupportedStoreSchema, .unexpectedStoreKey,
                     .recordTooLarge, .conflictJournalTooLarge,
                     .invalidEnvelopeVersion, .unsupportedAlgorithm,
                     .unsupportedLegacyPayloadSchema,
                     .payloadSchemaRequiresNewerApp:
                    return .pending(.invalidRemoteSnapshot)
                case .invalidKey:
                    return .pending(.keyStoreFailure)
                }
            } catch {
                return .pending(.unknown)
            }
        }
        return .pending(.headChanged)
    }

    /// A locally confirmed generation is normally the remote durability
    /// boundary, so ordinary commits omit it and older ancestors. A CloudKit
    /// environment change or damaged remote history can invalidate that
    /// assumption while the authenticated immutable bytes remain in the local
    /// outbox. Retry exactly once with that retained chain. Missing local bytes
    /// still fail closed; no generation is rewritten or deleted.
    private func commitWithRetainedAnchorRepair(
        envelope: HWCEncryptedCloudSnapshotEnvelope,
        localEnvelope: HWCEncryptedCloudSnapshotEnvelope,
        locallyPendingEnvelopes: [HWCEncryptedCloudSnapshotEnvelope],
        expectedHead: HWCCloudSnapshotRemoteHead?
    ) async throws -> HWCCloudSnapshotRemoteHead {
        let initialEnvelopes = Self.uniqueEnvelopes(
            locallyPendingEnvelopes + [envelope]
        )
        do {
            return try await transport.commitAtomically(
                envelopes: initialEnvelopes,
                advancingHeadTo: envelope,
                expectedHead: expectedHead
            )
        } catch HWCCloudSnapshotRemoteError.missingGeneration {
            let retainedAnchorChain = try retainedLocalAncestry(
                endingAt: localEnvelope,
                includeConfirmedHead: true
            )
            let repairEnvelopes = Self.uniqueEnvelopes(
                retainedAnchorChain + locallyPendingEnvelopes + [envelope]
            )
            guard Set(repairEnvelopes.map(\.snapshotID)) !=
                    Set(initialEnvelopes.map(\.snapshotID)) else {
                throw HWCCloudSnapshotRemoteError.missingGeneration
            }
            return try await transport.commitAtomically(
                envelopes: repairEnvelopes,
                advancingHeadTo: envelope,
                expectedHead: expectedHead
            )
        }
    }

    private static func uniqueEnvelopes(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope]
    ) -> [HWCEncryptedCloudSnapshotEnvelope] {
        var seen = Set<UUID>()
        return envelopes.filter { seen.insert($0.snapshotID).inserted }
    }

    /// A snapshot UUID names one immutable encrypted generation. Reusing that
    /// UUID must reuse its authenticated bytes because ChaChaPoly sealing uses
    /// a fresh nonce and therefore cannot be repeated byte-for-byte.
    private func authenticatedLocalEnvelope(
        for payload: HWCCloudSnapshotPayload,
        sealingKey: HWCCloudSnapshotKey
    ) throws -> HWCEncryptedCloudSnapshotEnvelope {
        if let historyOutbox = outbox as? HWCCloudSnapshotHistoryOutbox,
           let existing = try historyOutbox.loadEnvelopes().first(where: {
               $0.snapshotID == payload.snapshotID
           }) {
            guard let keyData = keyRing.keyData(for: existing.keyID) else {
                throw LocalEnvelopeResolutionError.missingDecryptionKey(existing.keyID)
            }
            let persistedPayload = try HWCCloudSnapshotCryptor.open(
                existing,
                keyData: keyData
            )
            guard persistedPayload == payload else {
                throw LocalEnvelopeResolutionError.payloadMismatch
            }
            return existing
        }

        let envelope = try HWCCloudSnapshotCryptor.seal(
            payload,
            keyData: sealingKey.data
        )
        try outbox.persist(envelope)
        return envelope
    }

    private func retainedLocalAncestry(
        endingAt localEnvelope: HWCEncryptedCloudSnapshotEnvelope,
        includeConfirmedHead: Bool = false
    ) throws -> [HWCEncryptedCloudSnapshotEnvelope] {
        guard let historyOutbox = outbox as? HWCCloudSnapshotHistoryOutbox else {
            return [localEnvelope]
        }
        var envelopesByID: [UUID: HWCEncryptedCloudSnapshotEnvelope] = [:]
        for envelope in try historyOutbox.loadEnvelopes() {
            envelopesByID[envelope.snapshotID] = envelope
        }
        envelopesByID[localEnvelope.snapshotID] = localEnvelope

        let confirmedSnapshotID = historyOutbox.confirmedHead?.snapshotID
        var pending = [localEnvelope.snapshotID]
        var visited = Set<UUID>()
        var retained = [HWCEncryptedCloudSnapshotEnvelope]()
        while let snapshotID = pending.popLast() {
            if !includeConfirmedHead, snapshotID == confirmedSnapshotID {
                continue
            }
            guard visited.count < Self.maximumRetainedAncestryCount else {
                break
            }
            guard visited.insert(snapshotID).inserted,
                  let envelope = envelopesByID[snapshotID] else {
                continue
            }
            guard let keyData = keyRing.keyData(for: envelope.keyID) else {
                throw HWCCloudSnapshotError.invalidKey
            }
            _ = try HWCCloudSnapshotCryptor.open(
                envelope,
                keyData: keyData
            )
            retained.append(envelope)
            pending.append(contentsOf: envelope.parentSnapshotIDs)
        }
        return retained
    }

    /// A retained local generation graph can prove that an older remote head is
    /// already included by the candidate. In that case a merge would invent a
    /// false conflict and an unnecessary generation. A missing or individually
    /// unreadable ancestor proves nothing, so reconciliation conservatively
    /// falls back to the existing authenticated remote merge path.
    private func candidateDescends(
        _ candidate: HWCCloudSnapshotPayload,
        from ancestorSnapshotID: UUID
    ) throws -> Bool {
        if candidate.parentSnapshotIDs.contains(ancestorSnapshotID) {
            return true
        }
        guard let historyOutbox = outbox as? HWCCloudSnapshotHistoryOutbox else {
            return false
        }

        var envelopesByID: [UUID: HWCEncryptedCloudSnapshotEnvelope] = [:]
        for envelope in try historyOutbox.loadEnvelopes() {
            envelopesByID[envelope.snapshotID] = envelope
        }
        var pending = candidate.parentSnapshotIDs
        var visited = Set<UUID>()
        while let snapshotID = pending.popLast() {
            if snapshotID == ancestorSnapshotID {
                return true
            }
            guard visited.insert(snapshotID).inserted,
                  let envelope = envelopesByID[snapshotID],
                  let keyData = keyRing.keyData(for: envelope.keyID),
                  let payload = try? HWCCloudSnapshotCryptor.open(
                      envelope,
                      keyData: keyData
                  ) else {
                continue
            }
            pending.append(contentsOf: payload.parentSnapshotIDs)
        }
        return false
    }

    private func remotePayloadDescends(
        _ remotePayload: HWCCloudSnapshotPayload,
        from ancestorSnapshotID: UUID
    ) async throws -> Bool {
        var pending = remotePayload.parentSnapshotIDs
        var visited = Set<UUID>()
        while let snapshotID = pending.popLast() {
            if snapshotID == ancestorSnapshotID {
                return true
            }
            guard visited.count < 512 else {
                return false
            }
            guard visited.insert(snapshotID).inserted else {
                continue
            }
            let envelope = try await transport.fetchEnvelope(
                snapshotID: snapshotID
            )
            guard let keyData = keyRing.keyData(for: envelope.keyID) else {
                continue
            }
            let payload = try HWCCloudSnapshotCryptor.open(
                envelope,
                keyData: keyData
            )
            pending.append(contentsOf: payload.parentSnapshotIDs)
        }
        return false
    }

    private static func syncReason(
        for reason: HWCCloudSnapshotPendingReason
    ) -> HWCCloudSnapshotSyncPendingReason {
        switch reason {
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine: return .couldNotDetermine
        case .temporarilyUnavailable: return .temporarilyUnavailable
        }
    }

    private static func syncReason(
        for error: HWCCloudSnapshotRemoteError
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
}

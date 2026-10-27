import CloudKit
import Foundation

/// Private-database CloudKit transport. Each encrypted generation is immutable.
/// A generation CKAsset and the mutable head record commit in one atomic custom-
/// zone operation using ifServerRecordUnchanged compare-and-swap semantics.
final class HWCCloudKitSnapshotTransport: HWCCloudSnapshotRemoteTransport,
    HWCCloudSnapshotHistoryRemoteTransport {
    private static let accountStatusDeadline: TimeInterval = 10
    private static let requestDeadline: TimeInterval = 15
    private static let resourceDeadline: TimeInterval = 60
    private static let callbackDeadline: TimeInterval = 65

    private enum Schema {
        static let zoneName = "HWCEncryptedSnapshotZoneV1"
        static let generationRecordType = "HWCEncryptedSnapshotGenerationV1"
        static let headRecordType = "HWCEncryptedSnapshotHeadV1"
        static let headRecordName = "head"
        static let payloadAsset = "encryptedPayload"
        static let snapshotID = "snapshotID"
        static let generation = "generation"
        static let keyID = "keyID"
        static let originSequence = "originSequence"
        static let createdAtMilliseconds = "createdAtMilliseconds"
    }

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let cacheLock = NSLock()
    private var cachedHeads: [String: CKRecord] = [:]
    private let zoneLock = NSLock()
    private var zoneReady = false

    init(container: CKContainer = .default()) {
        self.container = container
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(
            zoneName: Schema.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    func accountStatus() async -> HWCCloudSnapshotAccountStatus {
        Self.diagnose("account.begin")
        return await withCheckedContinuation { continuation in
            let watchdog = HWCCloudSnapshotOperationWatchdog<
                HWCCloudSnapshotAccountStatus
            >(
                timeoutInterval: Self.accountStatusDeadline,
                timeoutValue: { .couldNotDetermine },
                completion: { continuation.resume(returning: $0) }
            )
            container.accountStatus { status, _ in
                Self.diagnose("account.result", code: status.rawValue)
                watchdog.resolve(Self.mappedAccountStatus(status))
            }
        }
    }

    func fetchHead() async throws -> HWCCloudSnapshotRemoteHead? {
        Self.diagnose("head.begin")
        defer { Self.diagnose("head.end") }
        try await ensureZone()
        do {
            let record = try await fetchRecord(
                id: CKRecord.ID(
                    recordName: Schema.headRecordName,
                    zoneID: zoneID
                )
            )
            let head = try decodeHead(record)
            cacheHead(record, token: head.revisionToken)
            return head
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw Self.remoteError(error)
        }
    }

    func fetchEnvelope(
        snapshotID: UUID
    ) async throws -> HWCEncryptedCloudSnapshotEnvelope {
        Self.diagnose("envelope.begin")
        defer { Self.diagnose("envelope.end") }
        try await ensureZone()
        do {
            let record = try await fetchRecord(id: generationRecordID(snapshotID))
            return try decodeEnvelope(record, expectedSnapshotID: snapshotID)
        } catch let error as HWCCloudSnapshotRemoteError {
            throw error
        } catch {
            throw Self.remoteError(error)
        }
    }

    func listGenerationMetadata() async throws -> HWCCloudSnapshotGenerationListing {
        Self.diagnose("history.begin")
        defer { Self.diagnose("history.end") }
        try await ensureZone()
        do {
            let candidates = try await fetchGenerationRecords().map(
                generationMetadataCandidate
            )
            return HWCCloudSnapshotGenerationMetadataValidator.listing(
                from: candidates
            )
        } catch let error as HWCCloudSnapshotRemoteError {
            throw error
        } catch {
            throw Self.remoteError(error)
        }
    }

    func commitAtomically(
        envelopes: [HWCEncryptedCloudSnapshotEnvelope],
        advancingHeadTo headEnvelope: HWCEncryptedCloudSnapshotEnvelope,
        expectedHead: HWCCloudSnapshotRemoteHead?
    ) async throws -> HWCCloudSnapshotRemoteHead {
        try await ensureZone()
        let normalizedEnvelopes = try Self.normalizedCommitEnvelopes(
            envelopes,
            headEnvelope: headEnvelope
        )
        try await validateParentClosure(normalizedEnvelopes)
        let parentEnvelopes = normalizedEnvelopes.filter {
            $0.snapshotID != headEnvelope.snapshotID
        }
        let missingParents = try await missingImmutableGenerations(
            parentEnvelopes
        )
        try await persistMissingImmutableGenerations(missingParents)
        var assetURLs = [URL]()
        defer { assetURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        var generationRecords = [CKRecord]()
        if try await !immutableGenerationAlreadyExists(headEnvelope) {
            let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "hwc-cloud-generation-\(headEnvelope.snapshotID.uuidString.lowercased()).json",
                isDirectory: false
            )
            try JSONEncoder().encode(headEnvelope).write(to: assetURL, options: [.atomic])
            assetURLs.append(assetURL)
            generationRecords.append(
                generationRecord(envelope: headEnvelope, assetURL: assetURL)
            )
        }

        let headRecord = try await recordForHeadUpdate(expectedHead: expectedHead)
        let nextGeneration = (expectedHead?.generation ?? 0) + 1
        headRecord[Schema.snapshotID] = headEnvelope.snapshotID.uuidString.lowercased() as CKRecordValue
        headRecord[Schema.generation] = NSNumber(value: nextGeneration)
        headRecord[Schema.keyID] = headEnvelope.keyID as CKRecordValue

        let saved = try await modifyAtomically(
            recordsToSave: generationRecords + [headRecord]
        )
        guard let savedHead = saved.first(where: {
            $0.recordID.recordName == Schema.headRecordName
        }) else {
            throw HWCCloudSnapshotRemoteError.serverRejected
        }
        let result = try decodeHead(savedHead)
        cacheHead(savedHead, token: result.revisionToken)
        return result
    }

    private func validateParentClosure(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope]
    ) async throws {
        let includedSnapshotIDs = Set(envelopes.map(\.snapshotID))
        let externalParentIDs = Set(
            envelopes.flatMap(\.parentSnapshotIDs)
        ).subtracting(includedSnapshotIDs)
        for parentSnapshotID in externalParentIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            _ = try await fetchEnvelope(snapshotID: parentSnapshotID)
        }
    }

    /// Ancestors are immutable and stage before the visible head compare-and-
    /// swap. Partial batch progress can leave only unreachable encrypted
    /// records; exact-byte preflight makes every retry idempotent.
    private func persistMissingImmutableGenerations(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope]
    ) async throws {
        do {
            try await HWCCloudSnapshotOperationBatcher.performWeightedBatches(
                envelopes,
                weight: { try JSONEncoder().encode($0).count },
                shouldSplit: Self.isOperationLimitError,
                operation: { [self] batch in
                    try await persistImmutableGenerationBatch(batch)
                }
            )
        } catch {
            throw Self.remoteError(error)
        }
    }

    private func persistImmutableGenerationBatch(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope]
    ) async throws {
        guard !envelopes.isEmpty else { return }
        var assetURLs = [URL]()
        defer { assetURLs.forEach { try? FileManager.default.removeItem(at: $0) } }
        let records = try envelopes.map { envelope in
            let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent(
                "hwc-cloud-generation-\(envelope.snapshotID.uuidString.lowercased())-\(UUID().uuidString.lowercased()).json",
                isDirectory: false
            )
            try JSONEncoder().encode(envelope).write(to: assetURL, options: [.atomic])
            assetURLs.append(assetURL)
            return generationRecord(envelope: envelope, assetURL: assetURL)
        }

        do {
            let saved = try await modifyAtomicallyRaw(recordsToSave: records)
            guard Set(saved.map(\.recordID)) == Set(records.map(\.recordID)) else {
                throw HWCCloudSnapshotRemoteError.serverRejected
            }
        } catch {
            if Self.isOperationLimitError(error) { throw error }
            if Self.isImmutableRecordConflict(error) {
                let stillMissing = try await missingImmutableGenerations(envelopes)
                guard stillMissing.count < envelopes.count else {
                    throw HWCCloudSnapshotRemoteError.serverRejected
                }
                try await persistImmutableGenerationBatch(stillMissing)
                return
            }
            throw Self.remoteError(error)
        }
    }

    private func missingImmutableGenerations(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope]
    ) async throws -> [HWCEncryptedCloudSnapshotEnvelope] {
        var missing = [HWCEncryptedCloudSnapshotEnvelope]()
        for batch in HWCCloudSnapshotOperationBatcher.batches(envelopes) {
            let results = try await fetchImmutableGenerationResults(batch)
            for envelope in batch {
                let recordID = generationRecordID(envelope.snapshotID)
                guard let result = results[recordID] else {
                    throw HWCCloudSnapshotRemoteError.serverRejected
                }
                switch result {
                case .success(let record):
                    let existing = try decodeEnvelope(
                        record,
                        expectedSnapshotID: envelope.snapshotID
                    )
                    guard existing == envelope else {
                        throw HWCCloudSnapshotRemoteError.serverRejected
                    }
                case .failure(let error):
                    if Self.isUnknownItem(error) {
                        missing.append(envelope)
                    } else {
                        throw Self.remoteError(error)
                    }
                }
            }
        }
        return missing
    }

    private func fetchImmutableGenerationResults(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope]
    ) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        let recordIDs = envelopes.map { generationRecordID($0.snapshotID) }
        do {
            return try await fetchRecordResults(ids: recordIDs)
        } catch {
            guard envelopes.count > 1, Self.isOperationLimitError(error) else {
                throw Self.remoteError(error)
            }
            let midpoint = envelopes.count / 2
            var results = try await fetchImmutableGenerationResults(
                Array(envelopes[..<midpoint])
            )
            let remainder = try await fetchImmutableGenerationResults(
                Array(envelopes[midpoint...])
            )
            results.merge(remainder) { _, newer in newer }
            return results
        }
    }

    private static func normalizedCommitEnvelopes(
        _ envelopes: [HWCEncryptedCloudSnapshotEnvelope],
        headEnvelope: HWCEncryptedCloudSnapshotEnvelope
    ) throws -> [HWCEncryptedCloudSnapshotEnvelope] {
        var byID: [UUID: HWCEncryptedCloudSnapshotEnvelope] = [:]
        for envelope in envelopes + [headEnvelope] {
            guard !envelope.keyID.isEmpty,
                  !envelope.sealedPayload.isEmpty else {
                throw HWCCloudSnapshotRemoteError.serverRejected
            }
            if let existing = byID[envelope.snapshotID], existing != envelope {
                throw HWCCloudSnapshotRemoteError.serverRejected
            }
            byID[envelope.snapshotID] = envelope
        }
        guard byID[headEnvelope.snapshotID] == headEnvelope else {
            throw HWCCloudSnapshotRemoteError.serverRejected
        }
        return byID.values.sorted {
            $0.snapshotID.uuidString < $1.snapshotID.uuidString
        }
    }

    private func immutableGenerationAlreadyExists(
        _ envelope: HWCEncryptedCloudSnapshotEnvelope
    ) async throws -> Bool {
        do {
            let existing = try await fetchEnvelope(snapshotID: envelope.snapshotID)
            guard existing == envelope else {
                throw HWCCloudSnapshotRemoteError.serverRejected
            }
            return true
        } catch HWCCloudSnapshotRemoteError.missingGeneration {
            return false
        }
    }

    private func generationRecord(
        envelope: HWCEncryptedCloudSnapshotEnvelope,
        assetURL: URL
    ) -> CKRecord {
        let record = CKRecord(
            recordType: Schema.generationRecordType,
            recordID: generationRecordID(envelope.snapshotID)
        )
        record[Schema.payloadAsset] = CKAsset(fileURL: assetURL)
        record[Schema.snapshotID] = envelope.snapshotID.uuidString.lowercased() as CKRecordValue
        record[Schema.keyID] = envelope.keyID as CKRecordValue
        record[Schema.originSequence] = NSNumber(value: envelope.originSequence)
        record[Schema.createdAtMilliseconds] = NSNumber(
            value: envelope.createdAtMilliseconds
        )
        return record
    }

    private func recordForHeadUpdate(
        expectedHead: HWCCloudSnapshotRemoteHead?
    ) async throws -> CKRecord {
        guard let expectedHead else {
            return CKRecord(
                recordType: Schema.headRecordType,
                recordID: CKRecord.ID(
                    recordName: Schema.headRecordName,
                    zoneID: zoneID
                )
            )
        }
        let cached = cachedHead(token: expectedHead.revisionToken)
        if let cached { return cached }

        let fetched: CKRecord
        do {
            fetched = try await fetchRecord(
                id: CKRecord.ID(
                    recordName: Schema.headRecordName,
                    zoneID: zoneID
                )
            )
        } catch {
            throw Self.remoteError(error)
        }
        let actual = try decodeHead(fetched)
        guard actual == expectedHead else {
            throw HWCCloudSnapshotRemoteError.headChanged
        }
        return fetched
    }

    private func ensureZone() async throws {
        if isZoneReady() { return }

        let zone = CKRecordZone(zoneID: zoneID)
        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordZonesOperation(
                    recordZonesToSave: [zone],
                    recordZoneIDsToDelete: nil
                )
                Self.configure(operation)
                let watchdog = HWCCloudSnapshotOperationWatchdog<
                    Result<Void, Error>
                >(
                    timeoutInterval: Self.callbackDeadline,
                    timeoutValue: {
                        .failure(HWCCloudSnapshotRemoteError.networkUnavailable)
                    },
                    onTimeout: { operation.cancel() },
                    completion: { continuation.resume(with: $0) }
                )
                operation.modifyRecordZonesResultBlock = { result in
                    watchdog.resolve(result)
                }
                database.add(operation)
            }
            markZoneReady()
        } catch {
            throw Self.remoteError(error)
        }
    }

    private func fetchRecord(id: CKRecord.ID) async throws -> CKRecord {
        let results = try await fetchRecordResults(ids: [id])
        guard let result = results[id] else {
            throw HWCCloudSnapshotRemoteError.serverRejected
        }
        return try result.get()
    }

    private func fetchRecordResults(
        ids: [CKRecord.ID]
    ) async throws -> [CKRecord.ID: Result<CKRecord, Error>] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: ids)
            Self.configure(operation)
            let lock = NSLock()
            var results: [CKRecord.ID: Result<CKRecord, Error>] = [:]
            let watchdog = HWCCloudSnapshotOperationWatchdog<
                Result<[CKRecord.ID: Result<CKRecord, Error>], Error>
            >(
                timeoutInterval: Self.callbackDeadline,
                timeoutValue: {
                    .failure(HWCCloudSnapshotRemoteError.networkUnavailable)
                },
                onTimeout: { operation.cancel() },
                completion: { continuation.resume(with: $0) }
            )
            operation.perRecordResultBlock = { recordID, result in
                lock.lock()
                results[recordID] = result
                lock.unlock()
            }
            operation.fetchRecordsResultBlock = { result in
                lock.lock()
                let captured = results
                lock.unlock()
                if let limitError = HWCCloudSnapshotOperationBatcher.firstMatchingError(
                    in: Array(captured.values),
                    matching: Self.isOperationLimitError
                ) {
                    watchdog.resolve(.failure(limitError))
                    return
                }
                switch result {
                case .success:
                    guard captured.count == ids.count else {
                        watchdog.resolve(.failure(
                            HWCCloudSnapshotRemoteError.serverRejected
                        ))
                        return
                    }
                    watchdog.resolve(.success(captured))
                case .failure(let error):
                    if captured.count == ids.count {
                        watchdog.resolve(.success(captured))
                    } else {
                        watchdog.resolve(.failure(error))
                    }
                }
            }
            database.add(operation)
        }
    }

    private func fetchGenerationRecords() async throws -> [CKRecord] {
        try Task.checkCancellation()
        // A nil token reads the current custom-zone contents without relying on
        // query indexes. Fetch every page before exposing any recovery entries.
        let records: [CKRecord] = try await withCheckedThrowingContinuation { continuation in
            let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            configuration.desiredKeys = [
                Schema.snapshotID,
                Schema.keyID,
                Schema.originSequence,
                Schema.createdAtMilliseconds,
            ]
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: configuration]
            )
            operation.fetchAllChanges = true
            Self.configure(operation)
            let lock = NSLock()
            var page = HWCCloudSnapshotZoneHistoryAccumulator<CKRecord.ID, CKRecord>()
            var zoneFinished = false
            var zoneError: Error?
            let watchdog = HWCCloudSnapshotOperationWatchdog<
                Result<[CKRecord], Error>
            >(
                timeoutInterval: Self.callbackDeadline,
                timeoutValue: {
                    .failure(HWCCloudSnapshotRemoteError.networkUnavailable)
                },
                onTimeout: { operation.cancel() },
                completion: { continuation.resume(with: $0) }
            )
            operation.recordWasChangedBlock = { id, result in
                lock.lock()
                defer { lock.unlock() }
                switch result {
                case .success(let record) where record.recordType == Schema.generationRecordType:
                    page.record(.success(record), id: id)
                case .failure(let error):
                    page.record(.failure(error), id: id)
                default:
                    break
                }
            }
            operation.recordWithIDWasDeletedBlock = { id, _ in
                lock.lock()
                page.delete(id: id)
                lock.unlock()
            }
            operation.recordZoneFetchResultBlock = { _, result in
                lock.lock()
                defer { lock.unlock() }
                switch result {
                case .success(let change): zoneFinished = !change.moreComing
                case .failure(let error): zoneError = error
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    lock.lock()
                    let pageResult: Result<[CKRecord], Error>
                    do {
                        if let zoneError { throw zoneError }
                        guard zoneFinished else {
                            throw HWCCloudSnapshotRemoteError.serverRejected
                        }
                        pageResult = .success(try page.validatedRecords())
                    } catch {
                        pageResult = .failure(error)
                    }
                    lock.unlock()
                    switch pageResult {
                    case .success(let records):
                        watchdog.resolve(.success(records))
                    case .failure(let error):
                        watchdog.resolve(.failure(error))
                    }
                case .failure(let error):
                    watchdog.resolve(.failure(error))
                }
            }
            database.add(operation)
        }
        try Task.checkCancellation()
        return records
    }

    private func modifyAtomically(
        recordsToSave: [CKRecord]
    ) async throws -> [CKRecord] {
        do {
            return try await modifyAtomicallyRaw(recordsToSave: recordsToSave)
        } catch {
            throw Self.remoteError(error)
        }
    }

    private func modifyAtomicallyRaw(
        recordsToSave: [CKRecord]
    ) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(
                recordsToSave: recordsToSave,
                recordIDsToDelete: nil
            )
            Self.configure(operation)
            operation.isAtomic = true
            operation.savePolicy = .ifServerRecordUnchanged
            let resultLock = NSLock()
            var savedRecords = [CKRecord]()
            let watchdog = HWCCloudSnapshotOperationWatchdog<
                Result<[CKRecord], Error>
            >(
                timeoutInterval: Self.callbackDeadline,
                timeoutValue: {
                    .failure(HWCCloudSnapshotRemoteError.networkUnavailable)
                },
                onTimeout: { operation.cancel() },
                completion: { continuation.resume(with: $0) }
            )
            operation.perRecordSaveBlock = { _, result in
                if case .success(let record) = result {
                    resultLock.lock()
                    savedRecords.append(record)
                    resultLock.unlock()
                }
            }
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    resultLock.lock()
                    let records = savedRecords
                    resultLock.unlock()
                    watchdog.resolve(.success(records))
                case .failure(let error):
                    watchdog.resolve(.failure(error))
                }
            }
            database.add(operation)
        }
    }

    private func generationRecordID(_ snapshotID: UUID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "generation-\(snapshotID.uuidString.lowercased())",
            zoneID: zoneID
        )
    }

    private func cacheHead(_ record: CKRecord, token: String) {
        cacheLock.lock()
        cachedHeads[token] = record
        cacheLock.unlock()
    }

    private func cachedHead(token: String) -> CKRecord? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cachedHeads[token]
    }

    private func isZoneReady() -> Bool {
        zoneLock.lock()
        defer { zoneLock.unlock() }
        return zoneReady
    }

    private func markZoneReady() {
        zoneLock.lock()
        zoneReady = true
        zoneLock.unlock()
    }

    private func decodeHead(_ record: CKRecord) throws -> HWCCloudSnapshotRemoteHead {
        guard let snapshotIDString = record[Schema.snapshotID] as? String,
              let snapshotID = UUID(uuidString: snapshotIDString),
              let generationNumber = record[Schema.generation] as? NSNumber,
              let keyID = record[Schema.keyID] as? String,
              !keyID.isEmpty,
              let revisionToken = record.recordChangeTag,
              !revisionToken.isEmpty else {
            throw HWCCloudSnapshotRemoteError.serverRejected
        }
        return HWCCloudSnapshotRemoteHead(
            snapshotID: snapshotID,
            generation: generationNumber.uint64Value,
            keyID: keyID,
            revisionToken: revisionToken
        )
    }

    private func decodeEnvelope(
        _ record: CKRecord,
        expectedSnapshotID: UUID
    ) throws -> HWCEncryptedCloudSnapshotEnvelope {
        guard let asset = record[Schema.payloadAsset] as? CKAsset,
              let fileURL = asset.fileURL else {
            throw HWCCloudSnapshotRemoteError.missingGeneration
        }
        let envelope = try JSONDecoder().decode(
            HWCEncryptedCloudSnapshotEnvelope.self,
            from: Data(contentsOf: fileURL)
        )
        guard envelope.snapshotID == expectedSnapshotID,
              record[Schema.snapshotID] as? String == expectedSnapshotID.uuidString.lowercased(),
              record[Schema.keyID] as? String == envelope.keyID else {
            throw HWCCloudSnapshotRemoteError.serverRejected
        }
        return envelope
    }

    private func generationMetadataCandidate(
        _ record: CKRecord
    ) -> HWCCloudSnapshotGenerationMetadataCandidate {
        HWCCloudSnapshotGenerationMetadataCandidate(
            recordName: record.recordID.recordName,
            snapshotIDString: record[Schema.snapshotID] as? String,
            keyID: record[Schema.keyID] as? String,
            originSequence: (record[Schema.originSequence] as? NSNumber)?.int64Value,
            createdAtMilliseconds: (
                record[Schema.createdAtMilliseconds] as? NSNumber
            )?.int64Value
        )
    }

    private static func remoteError(_ error: Error) -> HWCCloudSnapshotRemoteError {
        if let cloud = error as? CKError {
            diagnose("cloud.error", code: cloud.code.rawValue)
            for nested in cloud.partialErrorsByItemID?.values ?? Dictionary<AnyHashable, Error>().values {
                if let nested = nested as? CKError {
                    diagnose("cloud.partial.error", code: nested.code.rawValue)
                }
            }
        }
        if let remote = error as? HWCCloudSnapshotRemoteError { return remote }
        guard let cloud = error as? CKError else { return .unknown }
        switch cloud.code {
        case .serverRecordChanged:
            return .headChanged
        case .quotaExceeded:
            return .quotaExceeded
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return .networkUnavailable
        case .notAuthenticated, .permissionFailure, .managedAccountRestricted:
            return .permissionDenied
        case .unknownItem, .zoneNotFound:
            return .missingGeneration
        case .batchRequestFailed, .partialFailure:
            if let partial = cloud.partialErrorsByItemID?.values.compactMap({
                $0 as? CKError
            }).first(where: { $0.code == .serverRecordChanged }) {
                _ = partial
                return .headChanged
            }
            return .serverRejected
        default:
            return .serverRejected
        }
    }

    private static func configure(_ operation: CKOperation) {
        diagnose("operation." + String(describing: type(of: operation)))
        operation.configuration.timeoutIntervalForRequest = requestDeadline
        operation.configuration.timeoutIntervalForResource = resourceDeadline
        operation.configuration.qualityOfService = .userInitiated
    }

    // Opt-in developer diagnostics: no record IDs, keys, payloads, or error descriptions.
    private static func diagnose(_ event: String, code: Int? = nil) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["HWC_BACKUP_DIAGNOSTICS"] == "1" else { return }
        print("HWCBackup \(event) code=\(code.map(String.init) ?? "none") time=\(Int(Date().timeIntervalSince1970))")
        #endif
    }

    private static func mappedAccountStatus(
        _ status: CKAccountStatus
    ) -> HWCCloudSnapshotAccountStatus {
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .couldNotDetermine: return .couldNotDetermine
        case .temporarilyUnavailable: return .temporarilyUnavailable
        @unknown default: return .couldNotDetermine
        }
    }

    private static func isUnknownItem(_ error: Error) -> Bool {
        (error as? CKError)?.code == .unknownItem
    }

    private static func isOperationLimitError(_ error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        if cloud.code == .limitExceeded { return true }
        return cloud.partialErrorsByItemID?.values.contains(where: {
            ($0 as? CKError)?.code == .limitExceeded
        }) == true
    }

    private static func isImmutableRecordConflict(_ error: Error) -> Bool {
        guard let cloud = error as? CKError else { return false }
        if cloud.code == .serverRecordChanged { return true }
        return cloud.partialErrorsByItemID?.values.contains(where: {
            ($0 as? CKError)?.code == .serverRecordChanged
        }) == true
    }
}

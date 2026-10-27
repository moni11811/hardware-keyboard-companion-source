import CoreFoundation
import CryptoKit
import Darwin
import Foundation

enum HWKAutobotLearnerStoreID: String, CaseIterable, Codable, Hashable, Sendable {
    case customDictionary
    case adaptiveUnigrams
    case adaptiveBigrams
    case rawTypedSamples
    case rejections
    case personalization
    case languageEvents
    case languageSnapshot
    case learnedPhrases
    case motorCalibration
    case gizmoSnapshot
    case typingEpisodes
    case ruleHypotheses
    case ruleDecisions
    case romanizedHypotheses
    case legacyEpisodeCredit
    case brainSnapshot
}

struct HWKAutobotLearnerManifestMember: Codable, Equatable, Sendable {
    let storeID: HWKAutobotLearnerStoreID
    let sourceKeys: [String]
    let schemaVersion: Int
    let maximumArtifactBytes: Int
    let isPresent: Bool
    let encodedBytes: Int
    let contentFingerprint: String
    let artifactKey: String?
}

struct HWKAutobotLearnerManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let revision: UInt64
    let parentRevision: UInt64?
    let resetEpoch: String
    let createdAtMilliseconds: Int64
    let fingerprintKeySchemeVersion: Int
    let members: [HWKAutobotLearnerManifestMember]
}

enum HWKAutobotLearnerManifestDecision: String, Equatable, Sendable {
    case initializedEmpty
    case migratedLegacy
    case healthy
    case promoted
    case repairedSplitGeneration
    case recoveredPreviousGeneration
    case rolledBack
    case reset
    case resetUnrecoverable
    case staleWriterRejected
    case lockUnavailable
    case persistenceFailed
    case extensionLocalCommit
}

enum HWKAutobotLearnerTransactionMode: Equatable, Sendable {
    case automatic
    case fullManifest
    case extensionSafe
}

struct HWKAutobotLearnerManifestAudit: Equatable, Sendable {
    let decision: HWKAutobotLearnerManifestDecision
    let manifest: HWKAutobotLearnerManifest
    let isolatedStoreIDs: [HWKAutobotLearnerStoreID]
}

struct HWKAutobotLearnerMutationResult<Value> {
    let value: Value?
    let audit: HWKAutobotLearnerManifestAudit
    let committed: Bool
}

/// One commit pointer for every durable correction learner. Component artifacts are
/// encrypted and written first. The small checksummed manifest flips last.
struct HWKAutobotLearnerManifestStore {
    static let currentManifestKey = "keyboard.autobot.learnerManifest.current.v1"
    static let recoveryManifestKey = "keyboard.autobot.learnerManifest.recovery.v1"
    static let maximumManifestBytes = 64 * 1_024
    static let maximumCurrentArtifactBytes = 3 * 1_024 * 1_024
    static let maximumRetainedArtifactCopiesPerStore = 2

    private static let resetEpochKey = "keyboard.autobot.learnerManifest.resetEpoch.v1"
    private static let bootstrappedKey = "keyboard.autobot.learnerManifest.bootstrapped.v1"
    private static let artifactKeyPrefix = "keyboard.autobot.learnerArtifact.v1."
    private static let envelopeVersion = 1
    private static let manifestSchemaVersion = 1
    private static let lock = NSRecursiveLock()
    private static var transactionDepth = 0
    private static let transactionLockFilename = ".autobot-learner-manifest.lock"
    private static let lockRetryMicroseconds: useconds_t = 1_000
    private static let maximumLockWaitMicroseconds: useconds_t = 250_000

    private struct Descriptor: Equatable {
        let storeID: HWKAutobotLearnerStoreID
        let sourceKeys: [String]
        let schemaVersion: Int
        let maximumSourceBytes: Int
        let maximumArtifactBytes: Int
    }

    private static let descriptors: [Descriptor] = [
        Descriptor(
            storeID: .customDictionary,
            sourceKeys: ["keyboard.customDictionaryWords"],
            schemaVersion: 1,
            maximumSourceBytes: 128 * 1_024,
            maximumArtifactBytes: 256 * 1_024
        ),
        Descriptor(
            storeID: .adaptiveUnigrams,
            sourceKeys: ["keyboard.adaptiveUnigramCounts"],
            schemaVersion: 1,
            maximumSourceBytes: 64 * 1_024,
            maximumArtifactBytes: 128 * 1_024
        ),
        Descriptor(
            storeID: .adaptiveBigrams,
            sourceKeys: ["keyboard.adaptiveBigramCounts"],
            schemaVersion: 1,
            maximumSourceBytes: 128 * 1_024,
            maximumArtifactBytes: 256 * 1_024
        ),
        Descriptor(
            storeID: .rawTypedSamples,
            sourceKeys: ["keyboard.rawTypedTextMLSamples"],
            schemaVersion: 1,
            maximumSourceBytes: 512 * 1_024,
            maximumArtifactBytes: 768 * 1_024
        ),
        Descriptor(
            storeID: .rejections,
            sourceKeys: ["keyboard.autocorrection.rejectionFingerprints.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 64 * 1_024,
            maximumArtifactBytes: 128 * 1_024
        ),
        Descriptor(
            storeID: .personalization,
            sourceKeys: ["keyboard.autocorrection.personalization.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 16 * 1_024,
            maximumArtifactBytes: 32 * 1_024
        ),
        Descriptor(
            storeID: .languageEvents,
            sourceKeys: ["keyboard.languageBrain.events.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 64 * 1_024,
            maximumArtifactBytes: 128 * 1_024
        ),
        Descriptor(
            storeID: .languageSnapshot,
            sourceKeys: [
                "keyboard.languageBrain.snapshot.v1",
                "keyboard.languageBrain.snapshot.revision",
            ],
            schemaVersion: 1,
            maximumSourceBytes: 32 * 1_024,
            maximumArtifactBytes: 64 * 1_024
        ),
        Descriptor(
            storeID: .learnedPhrases,
            sourceKeys: ["keyboard.languageBrain.phrases.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 96 * 1_024,
            maximumArtifactBytes: 192 * 1_024
        ),
        Descriptor(
            storeID: .motorCalibration,
            sourceKeys: ["keyboard.motorCalibration.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 16 * 1_024,
            maximumArtifactBytes: 32 * 1_024
        ),
        Descriptor(
            storeID: .gizmoSnapshot,
            sourceKeys: ["keyboard.gizmoImprovement.latestSnapshot"],
            schemaVersion: 1,
            maximumSourceBytes: 128 * 1_024,
            maximumArtifactBytes: 256 * 1_024
        ),
        Descriptor(
            storeID: .typingEpisodes,
            sourceKeys: [
                "keyboard.autobot.typingEpisodes.v2",
                "keyboard.autobot.typingEpisodes.v1",
            ],
            schemaVersion: 2,
            maximumSourceBytes: 64 * 1_024,
            maximumArtifactBytes: 128 * 1_024
        ),
        Descriptor(
            storeID: .ruleHypotheses,
            sourceKeys: ["keyboard.autobot.ruleHypotheses.v1"],
            schemaVersion: 2,
            maximumSourceBytes: 32 * 1_024,
            maximumArtifactBytes: 64 * 1_024
        ),
        Descriptor(
            storeID: .ruleDecisions,
            sourceKeys: ["keyboard.autobot.ruleHypothesisDecisions.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 8 * 1_024,
            maximumArtifactBytes: 16 * 1_024
        ),
        Descriptor(
            storeID: .romanizedHypotheses,
            sourceKeys: ["keyboard.autobot.romanizedHypotheses.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 32 * 1_024,
            maximumArtifactBytes: 64 * 1_024
        ),
        Descriptor(
            storeID: .legacyEpisodeCredit,
            sourceKeys: ["keyboard.autobot.episodeCredit.v1"],
            schemaVersion: 1,
            maximumSourceBytes: 64 * 1_024,
            maximumArtifactBytes: 128 * 1_024
        ),
        Descriptor(
            storeID: .brainSnapshot,
            sourceKeys: [
                "keyboard.autobot.brainSnapshot.current.v1",
                "keyboard.autobot.brainSnapshot.recovery.v1",
                "keyboard.autobot.brainSnapshot.resetEpoch.v1",
            ],
            schemaVersion: 1,
            maximumSourceBytes: 256 * 1_024,
            maximumArtifactBytes: 512 * 1_024
        ),
    ]

    private indirect enum StoredValue: Codable, Equatable {
        case data(Data)
        case string(String)
        case integer(Int64)
        case double(Double)
        case boolean(Bool)
        case array([StoredValue])
        case dictionary([String: StoredValue])

        init?(foundationObject object: Any) {
            switch object {
            case let data as Data:
                self = .data(data)
            case let string as String:
                self = .string(string)
            case let array as [Any]:
                var values = [StoredValue]()
                values.reserveCapacity(array.count)
                for item in array {
                    guard let value = StoredValue(foundationObject: item) else { return nil }
                    values.append(value)
                }
                self = .array(values)
            case let dictionary as [String: Any]:
                var values = [String: StoredValue]()
                values.reserveCapacity(dictionary.count)
                for (key, item) in dictionary {
                    guard let value = StoredValue(foundationObject: item) else { return nil }
                    values[key] = value
                }
                self = .dictionary(values)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    self = .boolean(number.boolValue)
                } else {
                    let type = String(cString: number.objCType)
                    if type == "f" || type == "d" {
                        guard number.doubleValue.isFinite else { return nil }
                        self = .double(number.doubleValue)
                    } else {
                        self = .integer(number.int64Value)
                    }
                }
            default:
                return nil
            }
        }

        var foundationObject: Any {
            switch self {
            case let .data(value):
                return value
            case let .string(value):
                return value
            case let .integer(value):
                return NSNumber(value: value)
            case let .double(value):
                return NSNumber(value: value)
            case let .boolean(value):
                return NSNumber(value: value)
            case let .array(values):
                return values.map(\.foundationObject)
            case let .dictionary(values):
                return values.mapValues(\.foundationObject)
            }
        }

        var dataValue: Data? {
            guard case let .data(value) = self else { return nil }
            return value
        }

        var integerValue: Int64? {
            guard case let .integer(value) = self else { return nil }
            return value
        }
    }

    private struct Artifact: Codable, Equatable {
        let values: [String: StoredValue]
    }

    private struct EnvelopePayload: Codable {
        let envelopeVersion: Int
        let manifest: HWKAutobotLearnerManifest
    }

    private struct Envelope: Codable {
        let envelopeVersion: Int
        let manifest: HWKAutobotLearnerManifest
        let checksum: String
    }

    private struct Generation {
        let manifest: HWKAutobotLearnerManifest
        let envelopeData: Data
    }

    private struct Capture {
        let members: [HWKAutobotLearnerManifestMember]
        let isolatedStoreIDs: [HWKAutobotLearnerStoreID]
        let createdArtifactKeys: [String]
    }

    private let defaults: UserDefaults
    private let transactionLockFileURL: URL?
    private let persistenceBarrier: () -> Bool
    private let transactionMode: HWKAutobotLearnerTransactionMode

    init(
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        transactionLockFileURL: URL? = nil,
        transactionMode: HWKAutobotLearnerTransactionMode = .automatic,
        persistenceBarrier: (() -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.transactionLockFileURL = transactionLockFileURL
        self.transactionMode = transactionMode
        self.persistenceBarrier = persistenceBarrier ?? { defaults.synchronize() }
    }

    func loadAndRepair(
        timestampMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> HWKAutobotLearnerManifestAudit {
        withExclusiveLock(unavailable: {
            lockFailureAudit(timestampMilliseconds: timestampMilliseconds)
        }) {
            loadAndRepairLocked(timestampMilliseconds: timestampMilliseconds)
        }
    }

    func mutationEpoch(
        timestampMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> String {
        if usesExtensionSafeMutation {
            return defaults.string(forKey: Self.resetEpochKey) ?? ""
        }
        return withExclusiveLock(unavailable: {
            defaults.string(forKey: Self.resetEpochKey) ?? ""
        }) {
            if let epoch = defaults.string(forKey: Self.resetEpochKey),
               defaults.data(forKey: Self.currentManifestKey) != nil {
                return epoch
            }
            return loadAndRepairLocked(
                timestampMilliseconds: timestampMilliseconds
            ).manifest.resetEpoch
        }
    }

    @discardableResult
    func performMutation<T>(
        storeIDs: Set<HWKAutobotLearnerStoreID>,
        expectedResetEpoch: String? = nil,
        timestampMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000),
        _ mutation: () -> T
    ) -> HWKAutobotLearnerMutationResult<T> {
        if usesExtensionSafeMutation {
            return performExtensionSafeMutation(
                timestampMilliseconds: timestampMilliseconds,
                mutation
            )
        }
        let entryEpoch = expectedResetEpoch ?? defaults.string(forKey: Self.resetEpochKey)
        return withExclusiveLock(unavailable: {
            let audit = lockFailureAudit(timestampMilliseconds: timestampMilliseconds)
            return HWKAutobotLearnerMutationResult(
                value: nil,
                audit: audit,
                committed: false
            )
        }) {
            let repaired = loadAndRepairLocked(timestampMilliseconds: timestampMilliseconds)
            let epoch = repaired.manifest.resetEpoch
            if let entryEpoch, entryEpoch != epoch {
                let audit = HWKAutobotLearnerManifestAudit(
                    decision: .staleWriterRejected,
                    manifest: repaired.manifest,
                    isolatedStoreIDs: repaired.isolatedStoreIDs
                )
                return HWKAutobotLearnerMutationResult(
                    value: nil,
                    audit: audit,
                    committed: false
                )
            }

            let value = mutation()
            let audit = checkpoint(
                changedStoreIDs: storeIDs,
                expectedResetEpoch: epoch,
                timestampMilliseconds: timestampMilliseconds
            )
            let committed = audit.decision == .promoted || audit.decision == .healthy
            return HWKAutobotLearnerMutationResult(
                value: committed ? value : nil,
                audit: audit,
                committed: committed
            )
        }
    }

    private func performExtensionSafeMutation<T>(
        timestampMilliseconds: Int64,
        _ mutation: () -> T
    ) -> HWKAutobotLearnerMutationResult<T> {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let value = mutation()
        return HWKAutobotLearnerMutationResult(
            value: value,
            audit: extensionLocalAudit(timestampMilliseconds: timestampMilliseconds),
            committed: true
        )
    }

    private var usesExtensionSafeMutation: Bool {
        switch transactionMode {
        case .automatic:
            return Bundle.main.bundleURL.pathExtension == "appex"
        case .fullManifest:
            return false
        case .extensionSafe:
            return true
        }
    }

    private func extensionLocalAudit(
        timestampMilliseconds: Int64
    ) -> HWKAutobotLearnerManifestAudit {
        HWKAutobotLearnerManifestAudit(
            decision: .extensionLocalCommit,
            manifest: HWKAutobotLearnerManifest(
                schemaVersion: Self.manifestSchemaVersion,
                revision: 0,
                parentRevision: nil,
                resetEpoch: defaults.string(forKey: Self.resetEpochKey) ?? "",
                createdAtMilliseconds: max(0, timestampMilliseconds),
                fingerprintKeySchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
                members: []
            ),
            isolatedStoreIDs: []
        )
    }

    func checkpoint(
        changedStoreIDs: Set<HWKAutobotLearnerStoreID>? = nil,
        expectedResetEpoch: String? = nil,
        timestampMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> HWKAutobotLearnerManifestAudit {
        withExclusiveLock(unavailable: {
            lockFailureAudit(timestampMilliseconds: timestampMilliseconds)
        }) {
        let epoch = currentResetEpochLocked()
        if let expectedResetEpoch, expectedResetEpoch != epoch {
            let repaired = loadAndRepairLocked(timestampMilliseconds: timestampMilliseconds)
            return HWKAutobotLearnerManifestAudit(
                decision: .staleWriterRejected,
                manifest: repaired.manifest,
                isolatedStoreIDs: repaired.isolatedStoreIDs
            )
        }

        guard let base = decodedGenerationMetadata(
            forKey: Self.currentManifestKey,
            resetEpoch: epoch
        ) else {
            return loadAndRepairLocked(timestampMilliseconds: timestampMilliseconds)
        }

        let capture = captureMembers(
            previous: base.manifest.members,
            changedStoreIDs: changedStoreIDs
        )
        if capture.members == base.manifest.members {
            garbageCollectArtifactsLocked()
            return HWKAutobotLearnerManifestAudit(
                decision: capture.isolatedStoreIDs.isEmpty ? .healthy : .repairedSplitGeneration,
                manifest: base.manifest,
                isolatedStoreIDs: capture.isolatedStoreIDs
            )
        }

        guard base.manifest.revision < UInt64.max else {
            removeCreatedArtifacts(capture.createdArtifactKeys)
            restoreGeneration(base)
            return resetAllLearningLocked(
                timestampMilliseconds: timestampMilliseconds,
                decision: .resetUnrecoverable
            )
        }
        let next = HWKAutobotLearnerManifest(
            schemaVersion: Self.manifestSchemaVersion,
            revision: base.manifest.revision + 1,
            parentRevision: base.manifest.revision,
            resetEpoch: epoch,
            createdAtMilliseconds: max(0, timestampMilliseconds),
            fingerprintKeySchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
            members: capture.members
        )
        guard let nextData = encodedEnvelope(next),
              currentResetEpochLocked() == epoch else {
            removeCreatedArtifacts(capture.createdArtifactKeys)
            restoreGeneration(base)
            return HWKAutobotLearnerManifestAudit(
                decision: .staleWriterRejected,
                manifest: base.manifest,
                isolatedStoreIDs: capture.isolatedStoreIDs
            )
        }
        guard persistenceBarrier() else {
            return recoverAfterPersistenceFailure(base: base, capture: capture)
        }

        defaults.set(base.envelopeData, forKey: Self.recoveryManifestKey)
        guard persistenceBarrier() else {
            return recoverAfterPersistenceFailure(base: base, capture: capture)
        }
        guard currentResetEpochLocked() == epoch else {
            removeCreatedArtifacts(capture.createdArtifactKeys)
            restoreGeneration(base)
            return HWKAutobotLearnerManifestAudit(
                decision: .staleWriterRejected,
                manifest: base.manifest,
                isolatedStoreIDs: capture.isolatedStoreIDs
            )
        }
        defaults.set(nextData, forKey: Self.currentManifestKey)
        guard persistenceBarrier(),
              defaults.data(forKey: Self.currentManifestKey) == nextData,
              validatedGeneration(forKey: Self.currentManifestKey, resetEpoch: epoch) != nil else {
            return recoverAfterPersistenceFailure(base: base, capture: capture)
        }
        defaults.set(true, forKey: Self.bootstrappedKey)
        garbageCollectArtifactsLocked()
        guard persistenceBarrier() else {
            return recoverAfterPersistenceFailure(base: base, capture: capture)
        }
        return HWKAutobotLearnerManifestAudit(
            decision: .promoted,
            manifest: next,
            isolatedStoreIDs: capture.isolatedStoreIDs
        )
        }
    }

    private func recoverAfterPersistenceFailure(
        base: Generation,
        capture: Capture
    ) -> HWKAutobotLearnerManifestAudit {
        defaults.set(base.envelopeData, forKey: Self.currentManifestKey)
        defaults.removeObject(forKey: Self.recoveryManifestKey)
        let pointerRestored = persistenceBarrier()
        _ = restoreGeneration(base)
        if pointerRestored {
            removeCreatedArtifacts(capture.createdArtifactKeys)
            garbageCollectArtifactsLocked()
        }
        _ = persistenceBarrier()
        return HWKAutobotLearnerManifestAudit(
            decision: .persistenceFailed,
            manifest: base.manifest,
            isolatedStoreIDs: capture.isolatedStoreIDs
        )
    }

    func rollbackToPreviousRevision(
        timestampMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> HWKAutobotLearnerManifestAudit? {
        withExclusiveLock(unavailable: { nil }) {
        _ = loadAndRepairLocked(timestampMilliseconds: timestampMilliseconds)
        let epoch = currentResetEpochLocked()
        guard let current = validatedGeneration(
            forKey: Self.currentManifestKey,
            resetEpoch: epoch
        ),
        let recovery = validatedGeneration(
            forKey: Self.recoveryManifestKey,
            resetEpoch: epoch
        ),
        current.manifest.parentRevision == recovery.manifest.revision,
        current.manifest.revision < UInt64.max else {
            return nil
        }

        let rolledBack = HWKAutobotLearnerManifest(
            schemaVersion: Self.manifestSchemaVersion,
            revision: current.manifest.revision + 1,
            parentRevision: current.manifest.revision,
            resetEpoch: epoch,
            createdAtMilliseconds: max(0, timestampMilliseconds),
            fingerprintKeySchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
            members: recovery.manifest.members
        )
        guard let rolledBackData = encodedEnvelope(rolledBack),
              currentResetEpochLocked() == epoch else {
            return nil
        }
        guard persistenceBarrier() else {
            return rollbackPersistenceFailure(current: current, recovery: recovery)
        }
        defaults.set(current.envelopeData, forKey: Self.recoveryManifestKey)
        guard persistenceBarrier() else {
            return rollbackPersistenceFailure(current: current, recovery: recovery)
        }
        defaults.set(rolledBackData, forKey: Self.currentManifestKey)
        guard persistenceBarrier(),
              validatedGeneration(forKey: Self.currentManifestKey, resetEpoch: epoch) != nil else {
            return rollbackPersistenceFailure(current: current, recovery: recovery)
        }
        guard restoreGeneration(recovery), persistenceBarrier() else {
            return rollbackPersistenceFailure(current: current, recovery: recovery)
        }
        garbageCollectArtifactsLocked()
        _ = persistenceBarrier()
        return HWKAutobotLearnerManifestAudit(
            decision: .rolledBack,
            manifest: rolledBack,
            isolatedStoreIDs: []
        )
        }
    }

    private func rollbackPersistenceFailure(
        current: Generation,
        recovery: Generation
    ) -> HWKAutobotLearnerManifestAudit {
        defaults.set(current.envelopeData, forKey: Self.currentManifestKey)
        defaults.set(recovery.envelopeData, forKey: Self.recoveryManifestKey)
        _ = persistenceBarrier()
        _ = restoreGeneration(current)
        _ = persistenceBarrier()
        garbageCollectArtifactsLocked()
        _ = persistenceBarrier()
        return HWKAutobotLearnerManifestAudit(
            decision: .persistenceFailed,
            manifest: current.manifest,
            isolatedStoreIDs: []
        )
    }

    func resetAllLearning(
        timestampMilliseconds: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) -> HWKAutobotLearnerManifestAudit {
        withExclusiveLock(unavailable: {
            lockFailureAudit(timestampMilliseconds: timestampMilliseconds)
        }) {
            resetAllLearningLocked(
                timestampMilliseconds: timestampMilliseconds,
                decision: .reset
            )
        }
    }

    private func loadAndRepairLocked(
        timestampMilliseconds: Int64
    ) -> HWKAutobotLearnerManifestAudit {
        let epoch = currentResetEpochLocked()
        let currentMetadata = decodedGenerationMetadata(
            forKey: Self.currentManifestKey,
            resetEpoch: epoch
        )
        let current = validatedGeneration(forKey: Self.currentManifestKey, resetEpoch: epoch)

        if let current {
            let mismatches = rawMismatchStoreIDs(for: current)
            for storeID in mismatches {
                guard restoreMember(storeID, from: current) else {
                    return resetAllLearningLocked(
                        timestampMilliseconds: timestampMilliseconds,
                        decision: .resetUnrecoverable
                    )
                }
            }
            if !mismatches.isEmpty, !persistenceBarrier() {
                return HWKAutobotLearnerManifestAudit(
                    decision: .persistenceFailed,
                    manifest: current.manifest,
                    isolatedStoreIDs: mismatches
                )
            }
            defaults.set(true, forKey: Self.bootstrappedKey)
            garbageCollectArtifactsLocked()
            return HWKAutobotLearnerManifestAudit(
                decision: mismatches.isEmpty ? .healthy : .repairedSplitGeneration,
                manifest: current.manifest,
                isolatedStoreIDs: mismatches
            )
        }

        if let recovery = validatedGeneration(
            forKey: Self.recoveryManifestKey,
            resetEpoch: epoch
        ) {
            if let currentMetadata,
               currentMetadata.manifest.parentRevision != recovery.manifest.revision {
                return resetAllLearningLocked(
                    timestampMilliseconds: timestampMilliseconds,
                    decision: .resetUnrecoverable
                )
            }
            guard restoreGeneration(recovery) else {
                return resetAllLearningLocked(
                    timestampMilliseconds: timestampMilliseconds,
                    decision: .resetUnrecoverable
                )
            }
            let previousCurrent = defaults.data(forKey: Self.currentManifestKey)
            defaults.set(recovery.envelopeData, forKey: Self.currentManifestKey)
            guard persistenceBarrier(),
                  validatedGeneration(
                      forKey: Self.currentManifestKey,
                      resetEpoch: epoch
                  ) != nil else {
                restoreControlValue(previousCurrent, forKey: Self.currentManifestKey)
                defaults.set(recovery.envelopeData, forKey: Self.recoveryManifestKey)
                _ = persistenceBarrier()
                return HWKAutobotLearnerManifestAudit(
                    decision: .persistenceFailed,
                    manifest: recovery.manifest,
                    isolatedStoreIDs: []
                )
            }
            defaults.removeObject(forKey: Self.recoveryManifestKey)
            defaults.set(true, forKey: Self.bootstrappedKey)
            garbageCollectArtifactsLocked()
            _ = persistenceBarrier()
            return HWKAutobotLearnerManifestAudit(
                decision: .recoveredPreviousGeneration,
                manifest: recovery.manifest,
                isolatedStoreIDs: []
            )
        }

        if !defaults.bool(forKey: Self.bootstrappedKey) {
            return bootstrapLegacyLocked(timestampMilliseconds: timestampMilliseconds)
        }
        return resetAllLearningLocked(
            timestampMilliseconds: timestampMilliseconds,
            decision: .resetUnrecoverable
        )
    }

    private func bootstrapLegacyLocked(
        timestampMilliseconds: Int64
    ) -> HWKAutobotLearnerManifestAudit {
        let previousCurrent = defaults.data(forKey: Self.currentManifestKey)
        let previousRecovery = defaults.data(forKey: Self.recoveryManifestKey)
        let previousBootstrapped = defaults.object(forKey: Self.bootstrappedKey)
        let hadLegacyState = Self.descriptors.contains { descriptor in
            descriptor.sourceKeys.contains { defaults.object(forKey: $0) != nil }
        }
        let epoch = currentResetEpochLocked()
        let capture = captureMembers(previous: nil, changedStoreIDs: nil)
        let manifest = HWKAutobotLearnerManifest(
            schemaVersion: Self.manifestSchemaVersion,
            revision: 1,
            parentRevision: nil,
            resetEpoch: epoch,
            createdAtMilliseconds: max(0, timestampMilliseconds),
            fingerprintKeySchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
            members: capture.members
        )
        guard let data = encodedEnvelope(manifest) else {
            removeCreatedArtifacts(capture.createdArtifactKeys)
            return resetAllLearningLocked(
                timestampMilliseconds: timestampMilliseconds,
                decision: .resetUnrecoverable
            )
        }
        guard persistenceBarrier() else {
            removeCreatedArtifacts(capture.createdArtifactKeys)
            restoreControlValue(previousCurrent, forKey: Self.currentManifestKey)
            restoreControlValue(previousRecovery, forKey: Self.recoveryManifestKey)
            restoreControlValue(previousBootstrapped, forKey: Self.bootstrappedKey)
            _ = persistenceBarrier()
            return HWKAutobotLearnerManifestAudit(
                decision: .persistenceFailed,
                manifest: manifest,
                isolatedStoreIDs: capture.isolatedStoreIDs
            )
        }
        defaults.set(data, forKey: Self.currentManifestKey)
        defaults.removeObject(forKey: Self.recoveryManifestKey)
        defaults.set(true, forKey: Self.bootstrappedKey)
        guard persistenceBarrier(),
              validatedGeneration(forKey: Self.currentManifestKey, resetEpoch: epoch) != nil else {
            restoreControlValue(previousCurrent, forKey: Self.currentManifestKey)
            restoreControlValue(previousRecovery, forKey: Self.recoveryManifestKey)
            restoreControlValue(previousBootstrapped, forKey: Self.bootstrappedKey)
            _ = persistenceBarrier()
            removeCreatedArtifacts(capture.createdArtifactKeys)
            _ = persistenceBarrier()
            return HWKAutobotLearnerManifestAudit(
                decision: .persistenceFailed,
                manifest: manifest,
                isolatedStoreIDs: capture.isolatedStoreIDs
            )
        }
        garbageCollectArtifactsLocked()
        _ = persistenceBarrier()
        return HWKAutobotLearnerManifestAudit(
            decision: hadLegacyState ? .migratedLegacy : .initializedEmpty,
            manifest: manifest,
            isolatedStoreIDs: capture.isolatedStoreIDs
        )
    }

    private func resetAllLearningLocked(
        timestampMilliseconds: Int64,
        decision: HWKAutobotLearnerManifestDecision
    ) -> HWKAutobotLearnerManifestAudit {
        let previousEpoch = defaults.string(forKey: Self.resetEpochKey)
        let previousCurrent = defaults.data(forKey: Self.currentManifestKey)
        let previousRecovery = defaults.data(forKey: Self.recoveryManifestKey)
        let previousBootstrapped = defaults.object(forKey: Self.bootstrappedKey)
        let previousGeneration = previousEpoch.flatMap { epoch in
            validatedGeneration(forKey: Self.currentManifestKey, resetEpoch: epoch)
        }
        let epoch = UUID().uuidString.lowercased()
        let members = Self.descriptors.map(emptyMember)
        let manifest = HWKAutobotLearnerManifest(
            schemaVersion: Self.manifestSchemaVersion,
            revision: 1,
            parentRevision: nil,
            resetEpoch: epoch,
            createdAtMilliseconds: max(0, timestampMilliseconds),
            fingerprintKeySchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
            members: members
        )
        guard let data = encodedEnvelope(manifest) else {
            return HWKAutobotLearnerManifestAudit(
                decision: .persistenceFailed,
                manifest: previousGeneration?.manifest ?? manifest,
                isolatedStoreIDs: []
            )
        }

        defaults.set(epoch, forKey: Self.resetEpochKey)
        defaults.set(data, forKey: Self.currentManifestKey)
        defaults.removeObject(forKey: Self.recoveryManifestKey)
        defaults.set(true, forKey: Self.bootstrappedKey)
        guard persistenceBarrier(),
              validatedGeneration(forKey: Self.currentManifestKey, resetEpoch: epoch) != nil else {
            restoreControlValue(previousEpoch, forKey: Self.resetEpochKey)
            restoreControlValue(previousCurrent, forKey: Self.currentManifestKey)
            restoreControlValue(previousRecovery, forKey: Self.recoveryManifestKey)
            restoreControlValue(previousBootstrapped, forKey: Self.bootstrappedKey)
            _ = persistenceBarrier()
            return HWKAutobotLearnerManifestAudit(
                decision: .persistenceFailed,
                manifest: previousGeneration?.manifest ?? manifest,
                isolatedStoreIDs: []
            )
        }

        for descriptor in Self.descriptors {
            descriptor.sourceKeys.forEach { defaults.removeObject(forKey: $0) }
        }
        removeAllArtifactsLocked()
        _ = persistenceBarrier()
        return HWKAutobotLearnerManifestAudit(
            decision: decision,
            manifest: manifest,
            isolatedStoreIDs: []
        )
    }

    private func restoreControlValue(_ value: Any?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func captureMembers(
        previous: [HWKAutobotLearnerManifestMember]?,
        changedStoreIDs: Set<HWKAutobotLearnerStoreID>?
    ) -> Capture {
        let previousByID = Dictionary(uniqueKeysWithValues: (previous ?? []).map { ($0.storeID, $0) })
        var members = [HWKAutobotLearnerManifestMember]()
        var isolated = [HWKAutobotLearnerStoreID]()
        var createdArtifactKeys = [String]()
        members.reserveCapacity(Self.descriptors.count)

        for descriptor in Self.descriptors {
            if let changedStoreIDs,
               !changedStoreIDs.contains(descriptor.storeID),
               let previousMember = previousByID[descriptor.storeID] {
                members.append(previousMember)
                continue
            }

            let previousMember = previousByID[descriptor.storeID]
            guard let artifact = artifactFromDefaults(descriptor: descriptor) else {
                isolated.append(descriptor.storeID)
                if let previousMember,
                   restoreMember(previousMember, descriptor: descriptor) {
                    members.append(previousMember)
                } else {
                    descriptor.sourceKeys.forEach { defaults.removeObject(forKey: $0) }
                    members.append(emptyMember(descriptor))
                }
                continue
            }

            guard !artifact.values.isEmpty else {
                members.append(emptyMember(descriptor))
                continue
            }
            guard let clearData = encode(artifact),
                  clearData.count <= descriptor.maximumArtifactBytes else {
                isolated.append(descriptor.storeID)
                if let previousMember,
                   restoreMember(previousMember, descriptor: descriptor) {
                    members.append(previousMember)
                } else {
                    descriptor.sourceKeys.forEach { defaults.removeObject(forKey: $0) }
                    members.append(emptyMember(descriptor))
                }
                continue
            }
            let fingerprint = authenticationCode(
                domain: "artifact:\(descriptor.storeID.rawValue)",
                data: clearData
            )
            if let previousMember,
               previousMember.isPresent,
               previousMember.contentFingerprint == fingerprint {
                members.append(previousMember)
                continue
            }

            let key = artifactKey(storeID: descriptor.storeID, fingerprint: fingerprint)
            if !validArtifact(clearData, forKey: key) {
                guard let encrypted = encryptedArtifact(clearData) else {
                    isolated.append(descriptor.storeID)
                    if let previousMember,
                       restoreMember(previousMember, descriptor: descriptor) {
                        members.append(previousMember)
                    } else {
                        descriptor.sourceKeys.forEach { defaults.removeObject(forKey: $0) }
                        members.append(emptyMember(descriptor))
                    }
                    continue
                }
                defaults.set(encrypted, forKey: key)
                guard validArtifact(clearData, forKey: key) else {
                    defaults.removeObject(forKey: key)
                    isolated.append(descriptor.storeID)
                    if let previousMember,
                       restoreMember(previousMember, descriptor: descriptor) {
                        members.append(previousMember)
                    } else {
                        descriptor.sourceKeys.forEach { defaults.removeObject(forKey: $0) }
                        members.append(emptyMember(descriptor))
                    }
                    continue
                }
                createdArtifactKeys.append(key)
            }
            members.append(HWKAutobotLearnerManifestMember(
                storeID: descriptor.storeID,
                sourceKeys: descriptor.sourceKeys,
                schemaVersion: descriptor.schemaVersion,
                maximumArtifactBytes: descriptor.maximumArtifactBytes,
                isPresent: true,
                encodedBytes: clearData.count,
                contentFingerprint: fingerprint,
                artifactKey: key
            ))
        }
        return Capture(
            members: members,
            isolatedStoreIDs: isolated,
            createdArtifactKeys: createdArtifactKeys
        )
    }

    private func artifactFromDefaults(descriptor: Descriptor) -> Artifact? {
        var values = [String: StoredValue]()
        for key in descriptor.sourceKeys {
            guard let object = defaults.object(forKey: key) else { continue }
            guard let value = StoredValue(foundationObject: object) else { return nil }
            values[key] = value
        }
        let artifact = Artifact(values: values)
        return validateArtifact(artifact, descriptor: descriptor) ? artifact : nil
    }

    private func validateArtifact(_ artifact: Artifact, descriptor: Descriptor) -> Bool {
        guard Set(artifact.values.keys).isSubset(of: Set(descriptor.sourceKeys)) else { return false }
        let sourceBytes = artifact.values.values.reduce(0) { partial, value in
            partial + sourceByteCount(value)
        }
        guard sourceBytes <= descriptor.maximumSourceBytes else { return false }
        guard !artifact.values.isEmpty else { return true }

        switch descriptor.storeID {
        case .customDictionary:
            guard let value = artifact.values[descriptor.sourceKeys[0]],
                  case let .array(words) = value,
                  words.count <= 1_024 else { return false }
            return words.allSatisfy { word in
                guard case let .string(text) = word else { return false }
                return !text.isEmpty && text.count <= 128
            }
        case .adaptiveUnigrams:
            return validateCountDictionary(
                artifact.values[descriptor.sourceKeys[0]],
                maximumEntries: 384
            )
        case .adaptiveBigrams:
            return validateCountDictionary(
                artifact.values[descriptor.sourceKeys[0]],
                maximumEntries: 768
            )
        case .rawTypedSamples:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return KeyboardSharedPreferences.isValidRawTypedTextMLSamplesData(data)
        case .rejections:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKAutocorrectionRejectionStore.isValidPersistedData(data)
        case .personalization:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKAutocorrectionPersonalizationStore.isValidPersistedData(data)
        case .languageEvents:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKLanguageBrainEventStore.isValidPersistedData(data)
        case .languageSnapshot:
            let dataKey = descriptor.sourceKeys[0]
            let revisionKey = descriptor.sourceKeys[1]
            guard let data = artifact.values[dataKey]?.dataValue,
                  let revision = artifact.values[revisionKey]?.integerValue,
                  HWKLanguageBrainSnapshotStore.isValidPersistedData(
                      data,
                      revision: revision
                  ) else {
                return false
            }
            return true
        case .learnedPhrases:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKPersistentPhraseLearner.isValidPersistedData(data)
        case .motorCalibration:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKMotorCalibrationStore.isValidPersistedData(data)
        case .gizmoSnapshot:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKGizmoImprovementSnapshotStore.isValidPersistedData(data)
        case .typingEpisodes:
            guard artifact.values[descriptor.sourceKeys[1]] == nil else { return false }
            guard let replay = artifact.values[descriptor.sourceKeys[0]]?.dataValue,
                  !replay.isEmpty else { return false }
            return (try? HWKAutobotLiveEpisodeCoordinator(replaying: replay)) != nil
        case .ruleHypotheses:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKAutobotRuleHypothesisStore.isValidHypothesisPersistedData(data)
        case .ruleDecisions:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKAutobotRuleHypothesisStore.isValidDecisionPersistedData(data)
        case .romanizedHypotheses:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKAutobotRomanizedHypothesisStore.isValidPersistedData(data)
        case .legacyEpisodeCredit:
            guard let data = artifact.values[descriptor.sourceKeys[0]]?.dataValue else {
                return false
            }
            return HWKAutobotEpisodeCreditStore.isValidPersistedData(data)
        case .brainSnapshot:
            let resetEpoch: String
            if let epoch = artifact.values[descriptor.sourceKeys[2]] {
                guard case let .string(value) = epoch,
                      !value.isEmpty,
                      value.count <= 128 else { return false }
                resetEpoch = value
            } else {
                resetEpoch = "initial"
            }
            for key in descriptor.sourceKeys.prefix(2) where artifact.values[key] != nil {
                guard let data = artifact.values[key]?.dataValue,
                      HWKAutobotBrainSnapshotStore.isValidPersistedEnvelopeData(
                          data,
                          resetEpoch: resetEpoch
                      ) else { return false }
            }
            return true
        }
    }

    private func validateCountDictionary(
        _ value: StoredValue?,
        maximumEntries: Int
    ) -> Bool {
        guard let value, case let .dictionary(counts) = value,
              counts.count <= maximumEntries else { return false }
        return counts.allSatisfy { key, value in
            guard !key.isEmpty,
                  key.count <= 256,
                  case let .integer(count) = value else { return false }
            return count >= 0
        }
    }

    private func validateJSONArray(
        _ value: StoredValue?,
        maximumEntries: Int
    ) -> Bool {
        guard let data = value?.dataValue,
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return false
        }
        return array.count <= maximumEntries
    }

    private func validateJSONDictionary(
        _ value: StoredValue?,
        versionKey: String,
        version: Int
    ) -> Bool {
        guard let dictionary = jsonDictionary(value) else { return false }
        return (dictionary[versionKey] as? NSNumber)?.intValue == version
    }

    private func jsonDictionary(_ value: StoredValue?) -> [String: Any]? {
        guard let data = value?.dataValue,
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return object as? [String: Any]
    }

    private func sourceByteCount(_ value: StoredValue) -> Int {
        if let data = value.dataValue { return data.count }
        return encode(value)?.count ?? Int.max
    }

    private func rawMismatchStoreIDs(for generation: Generation) -> [HWKAutobotLearnerStoreID] {
        let membersByID = Dictionary(
            uniqueKeysWithValues: generation.manifest.members.map { ($0.storeID, $0) }
        )
        return Self.descriptors.compactMap { descriptor in
            guard let member = membersByID[descriptor.storeID],
                  let artifact = artifactFromDefaults(descriptor: descriptor) else {
                return descriptor.storeID
            }
            if artifact.values.isEmpty { return member.isPresent ? descriptor.storeID : nil }
            guard member.isPresent,
                  let clearData = encode(artifact) else { return descriptor.storeID }
            let fingerprint = authenticationCode(
                domain: "artifact:\(descriptor.storeID.rawValue)",
                data: clearData
            )
            return fingerprint == member.contentFingerprint ? nil : descriptor.storeID
        }
    }

    @discardableResult
    private func restoreGeneration(_ generation: Generation) -> Bool {
        for descriptor in Self.descriptors {
            guard restoreMember(descriptor.storeID, from: generation) else { return false }
        }
        return true
    }

    private func restoreMember(
        _ storeID: HWKAutobotLearnerStoreID,
        from generation: Generation
    ) -> Bool {
        guard let descriptor = Self.descriptors.first(where: { $0.storeID == storeID }),
              let member = generation.manifest.members.first(where: { $0.storeID == storeID }) else {
            return false
        }
        return restoreMember(member, descriptor: descriptor)
    }

    private func restoreMember(
        _ member: HWKAutobotLearnerManifestMember,
        descriptor: Descriptor
    ) -> Bool {
        guard member.isPresent else {
            descriptor.sourceKeys.forEach { defaults.removeObject(forKey: $0) }
            return true
        }
        guard let artifactKey = member.artifactKey,
              let encrypted = defaults.data(forKey: artifactKey),
              let clearData = decryptedArtifact(encrypted),
              clearData.count == member.encodedBytes,
              authenticationCode(
                domain: "artifact:\(descriptor.storeID.rawValue)",
                data: clearData
              ) == member.contentFingerprint,
              let artifact = decode(Artifact.self, from: clearData),
              validateArtifact(artifact, descriptor: descriptor) else {
            return false
        }
        for key in descriptor.sourceKeys {
            if let value = artifact.values[key] {
                defaults.set(value.foundationObject, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        return true
    }

    private func decodedGenerationMetadata(
        forKey key: String,
        resetEpoch: String
    ) -> Generation? {
        guard let data = defaults.data(forKey: key),
              !data.isEmpty,
              data.count <= Self.maximumManifestBytes,
              let envelope = decode(Envelope.self, from: data),
              envelope.envelopeVersion == Self.envelopeVersion,
              envelope.manifest.resetEpoch == resetEpoch,
              validateManifestMetadata(envelope.manifest),
              envelope.checksum == envelopeChecksum(envelope.manifest) else {
            return nil
        }
        return Generation(manifest: envelope.manifest, envelopeData: data)
    }

    private func validatedGeneration(
        forKey key: String,
        resetEpoch: String
    ) -> Generation? {
        guard let generation = decodedGenerationMetadata(forKey: key, resetEpoch: resetEpoch) else {
            return nil
        }
        var totalBytes = 0
        for member in generation.manifest.members where member.isPresent {
            guard let descriptor = Self.descriptors.first(where: { $0.storeID == member.storeID }),
                  let artifactKey = member.artifactKey,
                  let encrypted = defaults.data(forKey: artifactKey),
                  encrypted.count <= member.maximumArtifactBytes + 64,
                  let clearData = decryptedArtifact(encrypted),
                  clearData.count == member.encodedBytes,
                  clearData.count <= member.maximumArtifactBytes,
                  authenticationCode(
                    domain: "artifact:\(member.storeID.rawValue)",
                    data: clearData
                  ) == member.contentFingerprint,
                  let artifact = decode(Artifact.self, from: clearData),
                  validateArtifact(artifact, descriptor: descriptor) else {
                return nil
            }
            totalBytes += clearData.count
            guard totalBytes <= Self.maximumCurrentArtifactBytes else { return nil }
        }
        return generation
    }

    private func validateManifestMetadata(_ manifest: HWKAutobotLearnerManifest) -> Bool {
        guard manifest.schemaVersion == Self.manifestSchemaVersion,
              manifest.revision > 0,
              manifest.createdAtMilliseconds >= 0,
              !manifest.resetEpoch.isEmpty,
              manifest.resetEpoch.count <= 128,
              manifest.fingerprintKeySchemeVersion == HWKAutobotEpisodeFingerprint.schemeVersion,
              manifest.members.count == Self.descriptors.count else {
            return false
        }
        if let parentRevision = manifest.parentRevision {
            guard parentRevision < manifest.revision else { return false }
        }
        for (member, descriptor) in zip(manifest.members, Self.descriptors) {
            guard member.storeID == descriptor.storeID,
                  member.sourceKeys == descriptor.sourceKeys,
                  member.schemaVersion == descriptor.schemaVersion,
                  member.maximumArtifactBytes == descriptor.maximumArtifactBytes else {
                return false
            }
            if member.isPresent {
                guard member.encodedBytes > 0,
                      member.encodedBytes <= descriptor.maximumArtifactBytes,
                      member.contentFingerprint.count == 64,
                      let artifactKey = member.artifactKey,
                      artifactKey.hasPrefix(Self.artifactKeyPrefix) else {
                    return false
                }
            } else {
                guard member.encodedBytes == 0,
                      member.contentFingerprint.isEmpty,
                      member.artifactKey == nil else {
                    return false
                }
            }
        }
        return true
    }

    private func encodedEnvelope(_ manifest: HWKAutobotLearnerManifest) -> Data? {
        let envelope = Envelope(
            envelopeVersion: Self.envelopeVersion,
            manifest: manifest,
            checksum: envelopeChecksum(manifest)
        )
        guard let data = encode(envelope), data.count <= Self.maximumManifestBytes else { return nil }
        return data
    }

    private func envelopeChecksum(_ manifest: HWKAutobotLearnerManifest) -> String {
        let payload = EnvelopePayload(
            envelopeVersion: Self.envelopeVersion,
            manifest: manifest
        )
        guard let data = encode(payload) else { return "" }
        return authenticationCode(domain: "manifest", data: data)
    }

    private func encryptedArtifact(_ clearData: Data) -> Data? {
        let key = SymmetricKey(data: HWKAutobotEpisodeFingerprint.learnerManifestKeyData())
        return try? ChaChaPoly.seal(clearData, using: key).combined
    }

    private func decryptedArtifact(_ encryptedData: Data) -> Data? {
        let key = SymmetricKey(data: HWKAutobotEpisodeFingerprint.learnerManifestKeyData())
        guard let box = try? ChaChaPoly.SealedBox(combined: encryptedData) else { return nil }
        return try? ChaChaPoly.open(box, using: key)
    }

    private func validArtifact(_ clearData: Data, forKey key: String) -> Bool {
        guard let encrypted = defaults.data(forKey: key),
              let decoded = decryptedArtifact(encrypted) else { return false }
        return decoded == clearData
    }

    private func authenticationCode(domain: String, data: Data) -> String {
        let key = SymmetricKey(data: HWKAutobotEpisodeFingerprint.learnerManifestKeyData())
        var authenticated = Data((domain + "\u{001F}").utf8)
        authenticated.append(data)
        return HMAC<SHA256>.authenticationCode(for: authenticated, using: key)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func artifactKey(
        storeID: HWKAutobotLearnerStoreID,
        fingerprint: String
    ) -> String {
        Self.artifactKeyPrefix + storeID.rawValue + "." + fingerprint
    }

    private func currentResetEpochLocked() -> String {
        if let epoch = defaults.string(forKey: Self.resetEpochKey), !epoch.isEmpty {
            return epoch
        }
        let epoch = UUID().uuidString.lowercased()
        defaults.set(epoch, forKey: Self.resetEpochKey)
        return epoch
    }

    private func lockFailureAudit(
        timestampMilliseconds: Int64
    ) -> HWKAutobotLearnerManifestAudit {
        let persistedEpoch = defaults.string(forKey: Self.resetEpochKey)
        let epoch = persistedEpoch.flatMap { $0.isEmpty ? nil : $0 } ?? "lock-unavailable"
        if let generation = decodedGenerationMetadata(
            forKey: Self.currentManifestKey,
            resetEpoch: epoch
        ) ?? decodedGenerationMetadata(
            forKey: Self.recoveryManifestKey,
            resetEpoch: epoch
        ) {
            return HWKAutobotLearnerManifestAudit(
                decision: .lockUnavailable,
                manifest: generation.manifest,
                isolatedStoreIDs: []
            )
        }
        let manifest = HWKAutobotLearnerManifest(
            schemaVersion: Self.manifestSchemaVersion,
            revision: 1,
            parentRevision: nil,
            resetEpoch: epoch,
            createdAtMilliseconds: max(0, timestampMilliseconds),
            fingerprintKeySchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
            members: Self.descriptors.map(emptyMember)
        )
        return HWKAutobotLearnerManifestAudit(
            decision: .lockUnavailable,
            manifest: manifest,
            isolatedStoreIDs: []
        )
    }

    private func emptyMember(_ descriptor: Descriptor) -> HWKAutobotLearnerManifestMember {
        HWKAutobotLearnerManifestMember(
            storeID: descriptor.storeID,
            sourceKeys: descriptor.sourceKeys,
            schemaVersion: descriptor.schemaVersion,
            maximumArtifactBytes: descriptor.maximumArtifactBytes,
            isPresent: false,
            encodedBytes: 0,
            contentFingerprint: "",
            artifactKey: nil
        )
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }

    private func withExclusiveLock<T>(
        unavailable: () -> T,
        _ operation: () -> T
    ) -> T {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if Self.transactionDepth > 0 {
            return operation()
        }

        let descriptor = transactionLockDescriptor()
        guard descriptor >= 0 else { return unavailable() }
        guard acquireTransactionLock(descriptor) else {
            _ = Darwin.close(descriptor)
            return unavailable()
        }
        Self.transactionDepth = 1
        defer {
            Self.transactionDepth = 0
            _ = Darwin.lockf(descriptor, F_ULOCK, 0)
            _ = Darwin.close(descriptor)
        }
        return operation()
    }

    private func transactionLockDescriptor() -> Int32 {
        let fileManager = FileManager.default
        let lockURL: URL
        if let transactionLockFileURL {
            lockURL = transactionLockFileURL
        } else if let baseURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSharedPreferences.appGroupIdentifier
        ) {
            lockURL = baseURL.appendingPathComponent(
                Self.transactionLockFilename,
                isDirectory: false
            )
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            lockURL = fileManager.temporaryDirectory.appendingPathComponent(
                Self.transactionLockFilename,
                isDirectory: false
            )
        } else {
            return -1
        }
        return lockURL.path.withCString { path in
            Darwin.open(path, O_CREAT | O_RDWR, mode_t(0o600))
        }
    }

    private func acquireTransactionLock(_ descriptor: Int32) -> Bool {
        var waited: useconds_t = 0
        while Darwin.lockf(descriptor, F_TLOCK, 0) != 0 {
            let lockError = errno
            guard (lockError == EACCES || lockError == EAGAIN),
                  waited < Self.maximumLockWaitMicroseconds else {
                return false
            }
            Darwin.usleep(Self.lockRetryMicroseconds)
            waited += Self.lockRetryMicroseconds
        }
        return true
    }

    private func removeCreatedArtifacts(_ keys: [String]) {
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private func removeAllArtifactsLocked() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.artifactKeyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func garbageCollectArtifactsLocked() {
        let epoch = currentResetEpochLocked()
        let current = decodedGenerationMetadata(forKey: Self.currentManifestKey, resetEpoch: epoch)
        let recovery = decodedGenerationMetadata(forKey: Self.recoveryManifestKey, resetEpoch: epoch)
        let referenced = Set(
            [current, recovery]
                .compactMap { $0 }
                .flatMap { generation in
                    generation.manifest.members.compactMap(\.artifactKey)
                }
        )
        for key in defaults.dictionaryRepresentation().keys
            where key.hasPrefix(Self.artifactKeyPrefix) && !referenced.contains(key) {
            defaults.removeObject(forKey: key)
        }
    }
}

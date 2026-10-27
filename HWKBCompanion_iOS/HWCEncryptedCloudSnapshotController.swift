import CloudKit
import Combine
import Foundation
import UIKit

private enum HWCCloudSnapshotControllerDeadline {
    static let reconcileNoticeNanoseconds: UInt64 = 75_000_000_000
    static let historyTimeoutNanoseconds: UInt64 = 75_000_000_000
}

enum HWCEncryptedCloudSnapshotDisplayState: Equatable {
    case preparing
    case syncing
    case syncingSlow
    case synced(Date)
    case localOnly(String)
    case needsKey
    case error(String)

    var title: String {
        switch self {
        case .preparing: return "Preparing encrypted backup"
        case .syncing: return "Syncing encrypted backup"
        case .syncingSlow: return "Encrypted backup still working"
        case .synced: return "Encrypted iCloud backup current"
        case .localOnly: return "Encrypted backup saved locally"
        case .needsKey: return "Waiting for iCloud Keychain"
        case .error: return "Encrypted backup needs attention"
        }
    }

    var detail: String {
        switch self {
        case .preparing:
            return "HWC is preparing a protected local snapshot."
        case .syncing:
            return "HWC is reconciling its protected snapshot with your private iCloud database."
        case .syncingSlow:
            return "This backup is taking longer than expected. Existing local and cloud data remain preserved while the active request finishes safely."
        case .synced(let date):
            return "Last confirmed \(date.formatted(date: .abbreviated, time: .shortened)). iCloud access is controlled by iOS Settings."
        case .localOnly(let reason):
            return "Your latest encrypted snapshot remains on this device. \(reason) HWC will retry when opened or returned to the foreground."
        case .needsKey:
            return "Cloud data was preserved. HWC will not replace it while the matching iCloud Keychain key is unavailable."
        case .error(let message):
            return message
        }
    }
}

@MainActor
final class HWCEncryptedCloudSnapshotController: ObservableObject {
    static let shared = HWCEncryptedCloudSnapshotController()

    @Published private(set) var state: HWCEncryptedCloudSnapshotDisplayState = .preparing
    @Published private(set) var history: [HWCCloudSnapshotGenerationMetadata] = []
    @Published private(set) var historyOmittedGenerationCount = 0
    @Published private(set) var inspectedGeneration: HWCCloudSnapshotGenerationInspection?
    @Published private(set) var historyIsLoading = false
    @Published private(set) var historyLoadState: HWCCloudSnapshotHistoryLoadState = .idle
    @Published private(set) var inspectingHistorySnapshotID: UUID?
    @Published private(set) var restoringHistorySnapshotID: UUID?
    @Published private(set) var reconcileActivity = HWCCloudSnapshotOperationActivity()
    @Published private(set) var historyActivity = HWCCloudSnapshotOperationActivity()
    @Published private(set) var journalLocationAudit: HWCCloudSnapshotJournalLocationAudit?

    private let service: HWCCloudSnapshotService?
    private let sharedDefaults: UserDefaults
    private var scheduledTask: Task<Void, Never>?
    private var reconcileDeadlineTask: Task<Void, Never>?
    private var reconcileRequestGeneration: UInt64 = 0
    private var historyTask: Task<Void, Never>?
    private var historyDeadlineTask: Task<Void, Never>?
    private var historyRequestGeneration: UInt64 = 0
    private var reconcileGate = HWCCloudSnapshotReconcileGate()
    private var historyRefreshQueue = HWCCloudSnapshotHistoryRefreshQueue()
    private var observerTokens: [NSObjectProtocol] = []

    private init() {
        sharedDefaults = KeyboardSharedPreferences.defaults
        journalLocationAudit = Self.snapshotJournalLocationAudit()
        _ = HWKSettingsiCloudSync().restoreToSharedSettingsIfNeeded()
        _ = HWKAutobotEpisodeFingerprint.portableRootKeyData()

        do {
            let root = try Self.snapshotDirectoryURL()
            let outbox = try HWCCloudSnapshotDurableOutbox(
                directoryURL: root.appendingPathComponent("outbox", isDirectory: true)
            )
            let backing = try HWCCloudSnapshotJournaledDefaultsBacking(
                sharedDefaults: sharedDefaults,
                standardDefaults: .standard,
                journalDirectoryURL: root.appendingPathComponent("restore", isDirectory: true)
            )
            let keyRing = HWCCloudSnapshotSynchronizableKeyRing(
                keyStore: HWCCloudSnapshotSynchronizableKeychainMaterialStore(),
                currentKeyStore: HWCCloudSnapshotUserDefaultsCurrentKeyStore(
                    defaults: sharedDefaults
                )
            )
            service = HWCCloudSnapshotService(
                registry: .v1,
                backing: backing,
                transformers: [
                    .clipboardSnippets: HWCEncryptedClipboardSnapshotTransformer(
                        defaults: sharedDefaults
                    ),
                ],
                transport: HWCCloudKitSnapshotTransport(),
                outbox: outbox,
                keyRing: keyRing,
                identityStore: HWCCloudSnapshotUserDefaultsIdentityStore(
                    defaults: sharedDefaults
                )
            )
        } catch {
            service = nil
            state = .error(
                "HWC could not open its protected local snapshot journal. Existing data was left untouched."
            )
        }
        registerObservers()
        reconcileNow()
        #if DEBUG
        if ProcessInfo.processInfo.environment["HWC_BACKUP_DIAGNOSTICS"] == "1" {
            refreshHistory()
        }
        #endif
    }

    deinit {
        scheduledTask?.cancel()
        reconcileDeadlineTask?.cancel()
        historyTask?.cancel()
        historyDeadlineTask?.cancel()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }

    func scheduleSnapshot() {
        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 750_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.reconcileNow()
        }
    }

    func reconcileNow() {
        guard let service else { return }
        guard reconcileGate.request(isHistoryLoading: historyIsLoading) else { return }
        reconcileRequestGeneration &+= 1
        let requestGeneration = reconcileRequestGeneration
        scheduledTask?.cancel()
        scheduledTask = nil
        state = .syncing
        reconcileActivity.begin()
        reconcileDeadlineTask?.cancel()
        reconcileDeadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: HWCCloudSnapshotControllerDeadline.reconcileNoticeNanoseconds
                )
            } catch {
                return
            }
            self?.reconcileDeadlineDidFire(generation: requestGeneration)
        }
        let safeToReplace = Self.localIsSafeToReplace(
            sharedDefaults: sharedDefaults,
            standardDefaults: .standard
        )
        Task { @MainActor [weak self] in
            let result = await service.reconcile(localIsSafeToReplace: safeToReplace)
            guard let self else { return }
            guard self.reconcileRequestGeneration == requestGeneration else { return }
            self.reconcileDeadlineTask?.cancel()
            self.reconcileDeadlineTask = nil
            if case .synchronized = result {
                self.reconcileActivity.finish()
            } else {
                self.reconcileActivity.fail()
            }
            let shouldRetry = self.reconcileGate.finish()
            self.apply(result)
            if self.historyRefreshQueue.reconcileDidFinish(
                isReconciling: self.reconcileGate.isReconciling
            ) {
                self.startHistoryRefresh()
            }
            if shouldRetry {
                self.scheduleSnapshot()
            }
        }
    }

    private func reconcileDeadlineDidFire(generation: UInt64) {
        guard reconcileRequestGeneration == generation,
              reconcileGate.isReconciling else { return }
        reconcileDeadlineTask = nil
        reconcileActivity.markOverdue()
        state = .syncingSlow
    }

    func refreshHistory() {
        guard service != nil else { return }
        if !historyIsLoading { historyLoadState = .waiting }
        if historyRefreshQueue.request(isReconciling: reconcileGate.isReconciling) {
            startHistoryRefresh()
        }
    }

    private func startHistoryRefresh() {
        guard let service else { return }
        historyRequestGeneration &+= 1
        let requestGeneration = historyRequestGeneration
        historyIsLoading = true
        historyLoadState = .loading
        historyActivity.begin()
        historyDeadlineTask?.cancel()
        historyDeadlineTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: HWCCloudSnapshotControllerDeadline.historyTimeoutNanoseconds
                )
            } catch {
                return
            }
            self?.historyDeadlineDidFire(generation: requestGeneration)
        }
        historyTask = Task { @MainActor [weak self] in
            let result: Result<HWCCloudSnapshotGenerationListing, Error>
            do {
                let listing = try await service.listRemoteHistory()
                result = .success(listing)
            } catch {
                result = .failure(error)
            }
            guard !Task.isCancelled else { return }
            self?.finishHistoryRefresh(result, generation: requestGeneration)
        }
    }

    private func finishHistoryRefresh(
        _ result: Result<HWCCloudSnapshotGenerationListing, Error>,
        generation: UInt64
    ) {
        guard generation == historyRequestGeneration,
              historyIsLoading else { return }
        historyDeadlineTask?.cancel()
        historyDeadlineTask = nil
        historyTask = nil
        switch result {
        case .success(let listing):
            history = listing.metadata
            historyOmittedGenerationCount = listing.omittedGenerationCount
            historyLoadState = .loaded
            historyActivity.finish()
            #if DEBUG
            if ProcessInfo.processInfo.environment["HWC_BACKUP_DIAGNOSTICS"] == "1" {
                print("HWCBackup history.loaded count=\(listing.metadata.count) omitted=\(listing.omittedGenerationCount)")
            }
            #endif
        case .failure(let error):
            historyLoadState = .failed
            historyActivity.fail()
            applyHistoryError(error)
        }
        historyIsLoading = false
        if reconcileGate.resumeAfterHistory() {
            reconcileNow()
        }
        if historyRefreshQueue.queryDidFinish(
            isReconciling: reconcileGate.isReconciling
        ) {
            startHistoryRefresh()
        }
    }

    private func historyDeadlineDidFire(generation: UInt64) {
        guard generation == historyRequestGeneration,
              historyIsLoading else { return }
        historyRequestGeneration &+= 1
        historyDeadlineTask = nil
        historyTask?.cancel()
        historyTask = nil
        historyIsLoading = false
        historyActivity.markOverdue()
        historyActivity.fail()
        historyLoadState = .failed
        state = .error(
            "Backup history took too long to load. No backup data was changed. Try Refresh Backup History again when iCloud is available."
        )
        if reconcileGate.resumeAfterHistory() {
            reconcileNow()
        }
        if historyRefreshQueue.queryDidFinish(
            isReconciling: reconcileGate.isReconciling
        ) {
            startHistoryRefresh()
        }
    }

    func inspectHistoryGeneration(snapshotID: UUID) {
        guard let service else { return }
        guard inspectingHistorySnapshotID == nil else { return }
        inspectingHistorySnapshotID = snapshotID
        inspectedGeneration = nil
        Task { @MainActor [weak self] in
            defer { self?.inspectingHistorySnapshotID = nil }
            do {
                let inspection = try await service.inspectRemoteGeneration(snapshotID: snapshotID)
                self?.inspectedGeneration = inspection
            } catch {
                self?.applyHistoryError(error)
            }
        }
    }

    func restoreHistoryGeneration(snapshotID: UUID) {
        guard let service else { return }
        guard restoringHistorySnapshotID == nil else { return }
        restoringHistorySnapshotID = snapshotID
        state = .syncing
        Task { @MainActor [weak self] in
            defer { self?.restoringHistorySnapshotID = nil }
            do {
                _ = try await service.restoreRemoteGeneration(snapshotID: snapshotID)
                guard let self else { return }
                let now = Date()
                self.sharedDefaults.set(
                    now.timeIntervalSince1970,
                    forKey: "cloudSnapshot.lastConfirmedAt.v1"
                )
                self.state = .synced(now)
                self.refreshHistory()
            } catch {
                self?.applyHistoryError(error)
            }
        }
    }

    private func apply(_ result: HWCCloudSnapshotServiceResult) {
        switch result {
        case .synchronized:
            let now = Date()
            sharedDefaults.set(
                now.timeIntervalSince1970,
                forKey: "cloudSnapshot.lastConfirmedAt.v1"
            )
            state = .synced(now)
        case .localPending(let reason):
            switch reason {
            case .missingDecryptionKey:
                state = .needsKey
            case .noAccount:
                state = .localOnly("Sign in to iCloud in iOS Settings to resume cloud backup.")
            case .restricted:
                state = .localOnly("This Apple Account is restricted from iCloud access.")
            case .couldNotDetermine, .temporarilyUnavailable, .networkUnavailable:
                state = .localOnly("iCloud is temporarily unavailable.")
            case .permissionDenied:
                state = .localOnly("Allow HWC to use iCloud in iOS Settings to resume.")
            case .quotaExceeded:
                state = .localOnly("Your iCloud storage quota is full.")
            case .headChanged:
                state = .localOnly("Another device updated the backup; reconciliation will retry.")
            case .localChangedDuringSync:
                state = .localOnly("New local changes arrived during backup and were preserved.")
                scheduleSnapshot()
            case .invalidRemoteSnapshot:
                state = .error(
                    "An encrypted cloud generation could not be authenticated. Cloud and local data were preserved."
                )
            case .remoteGenerationMissing:
                state = .error(
                    "Cloud backup history references a missing generation. Existing cloud and local data were preserved."
                )
            case .serverRejected:
                state = .error(
                    "iCloud rejected inconsistent backup metadata. Existing cloud and local data were preserved."
                )
            case .localPersistenceFailure, .keyStoreFailure:
                state = .error(
                    "HWC could not safely confirm the local encrypted snapshot. Existing data was left untouched."
                )
            case .unknown:
                state = .localOnly("iCloud did not complete the request.")
            }
        }
    }

    private func applyHistoryError(_ error: Error) {
        guard let historyError = error as? HWCCloudSnapshotHistoryError else {
            state = .error(
                "HWC could not validate the selected encrypted backup. Existing data was left untouched."
            )
            return
        }
        switch historyError {
        case .missingDecryptionKey:
            state = .needsKey
        case .cloudUnavailable(let reason):
            apply(.localPending(reason))
        case .unsupportedTransport, .invalidGeneration:
            state = .error(
                "Cloud backup history failed validation. Existing data was left untouched."
            )
        }
    }

    private func registerObservers() {
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .hwcCloudSnapshotSourceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleSnapshot() }
        })
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileNow() }
        })
        observerTokens.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcileNow() }
        })
    }

    private static func snapshotDirectoryURL() throws -> URL {
        let fileManager = FileManager.default
        let base: URL
        if let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSharedPreferences.appGroupIdentifier
        ) {
            base = container
        } else {
            base = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let directory = HWCCloudSnapshotJournalLocationPlanner.legacyRootURL(
            containerURL: base
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func snapshotJournalLocationAudit()
        -> HWCCloudSnapshotJournalLocationAudit? {
        let fileManager = FileManager.default
        guard let container = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSharedPreferences.appGroupIdentifier
        ) else { return nil }
        return HWCCloudSnapshotJournalLocationPlanner.audit(
            containerURL: container,
            fileExists: fileManager.fileExists(atPath:)
        )
    }

    static func localIsSafeToReplace(
        sharedDefaults: UserDefaults,
        standardDefaults: UserDefaults
    ) -> Bool {
        let nonSettingKeys = HWCCloudSnapshotRegistry.v1.descriptors
            .filter { $0.id != .settings }
            .flatMap(\.sourceKeys)
            .filter {
                $0 != HWKAutobotEpisodeFingerprint.portableRootKeyStorageKey
            }
        guard nonSettingKeys.allSatisfy({
            sharedDefaults.object(forKey: $0) == nil
        }) else {
            return false
        }
        guard !standardDefaults.bool(
            forKey: "companion.settingsMode.customSelected"
        ) else {
            return false
        }
        guard KeyboardSharedPreferences.hasStoredSettings(in: sharedDefaults) else {
            return true
        }

        var local = KeyboardSettingsSnapshot.load(from: sharedDefaults)
        let baseline = KeyboardSettingsSnapshot.default
        local.stableUserBucket = baseline.stableUserBucket
        local.remoteConfig = baseline.remoteConfig
        local.remoteConfigFetchedAt = baseline.remoteConfigFetchedAt
        return local == baseline
    }
}

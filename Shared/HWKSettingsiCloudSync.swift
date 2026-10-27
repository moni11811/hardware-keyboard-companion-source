import Foundation

protocol HWKSettingsKeyValueStoring {
    func bool(forKey key: String) -> Bool
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: HWKSettingsKeyValueStoring {}

struct HWKSettingsiCloudSync {
    private enum StoreKey {
        static let enabled = "settings.iCloudSyncEnabled"
        static let payload = "settings.iCloudSnapshot"
        static let updatedAt = "settings.iCloudSnapshotUpdatedAt"
        static let restoredAt = "settings.iCloudRestoredAt"
    }

    private let store: HWKSettingsKeyValueStoring
    private let localDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        store: HWKSettingsKeyValueStoring = NSUbiquitousKeyValueStore.default,
        localDefaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) {
        self.store = store
        self.localDefaults = localDefaults
    }

    var isEnabled: Bool {
        Self.localEnabled(in: localDefaults) || store.bool(forKey: StoreKey.enabled)
    }

    func setEnabled(_ enabled: Bool, snapshot: KeyboardSettingsSnapshot = .load()) {
        localDefaults.set(enabled, forKey: KeyboardSharedPreferences.Key.settingsiCloudSyncEnabled)
        store.set(enabled, forKey: StoreKey.enabled)
        localDefaults.synchronize()
        store.synchronize()

        if enabled {
            if !restoreToSharedSettingsIfNeeded() {
                save(snapshot: snapshot)
            }
        }

        localDefaults.synchronize()
        store.synchronize()
    }

    @discardableResult
    func save(snapshot: KeyboardSettingsSnapshot = .load(), updatedAt: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        guard let data = try? encoder.encode(HWKSettingsiCloudArchive(snapshot: snapshot)) else { return false }

        store.set(true, forKey: StoreKey.enabled)
        store.set(data, forKey: StoreKey.payload)
        store.set(updatedAt.timeIntervalSince1970, forKey: StoreKey.updatedAt)
        store.synchronize()
        return true
    }

    @discardableResult
    func restoreToSharedSettingsIfNeeded(now: Date = Date()) -> Bool {
        store.synchronize()
        guard isEnabled else { return false }
        guard let data = store.data(forKey: StoreKey.payload),
              let archive = try? decoder.decode(HWKSettingsiCloudArchive.self, from: data)
        else {
            return false
        }

        if KeyboardSharedPreferences.hasStoredSettings(in: localDefaults) {
            guard !Self.hasSuggestionLearningData(in: localDefaults) else { return false }
            let localSnapshot = KeyboardSettingsSnapshot.load(from: localDefaults)
            if Self.shouldRestoreRemoteSnapshot(over: localSnapshot, remote: archive.snapshot) {
                Self.snapshotByRestoringSyncedSettings(from: archive.snapshot, into: localSnapshot)
                    .persist(to: localDefaults, notify: true)
            } else {
                guard Self.shouldRestoreRemoteKeymap(over: localSnapshot, remote: archive.snapshot) else {
                    return false
                }
                Self.snapshotByRestoringKeymap(from: archive.snapshot, into: localSnapshot)
                    .persist(to: localDefaults, notify: true)
            }
        } else {
            archive.snapshot.persist(to: localDefaults, notify: true)
        }
        localDefaults.set(true, forKey: KeyboardSharedPreferences.Key.settingsiCloudSyncEnabled)
        localDefaults.set(now.timeIntervalSince1970, forKey: StoreKey.restoredAt)
        localDefaults.synchronize()
        return true
    }

    private static func localEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: KeyboardSharedPreferences.Key.settingsiCloudSyncEnabled)
    }

    private static func hasSuggestionLearningData(in defaults: UserDefaults) -> Bool {
        [
            KeyboardSharedPreferences.Key.customDictionaryWords,
            KeyboardSharedPreferences.Key.adaptiveUnigramCounts,
            KeyboardSharedPreferences.Key.adaptiveBigramCounts,
        ].contains { defaults.object(forKey: $0) != nil }
    }

    private static func shouldRestoreRemoteKeymap(
        over local: KeyboardSettingsSnapshot,
        remote: KeyboardSettingsSnapshot
    ) -> Bool {
        let baseline = KeyboardSettingsSnapshot.default
        return !keymapPackageDiffers(local, baseline) && keymapPackageDiffers(remote, local)
    }

    private static func shouldRestoreRemoteSnapshot(
        over local: KeyboardSettingsSnapshot,
        remote: KeyboardSettingsSnapshot
    ) -> Bool {
        guard snapshotMatchesSeededDefaults(local) else { return false }
        return snapshotByRestoringSyncedSettings(from: remote, into: local) != local
    }

    private static func snapshotMatchesSeededDefaults(_ snapshot: KeyboardSettingsSnapshot) -> Bool {
        var normalized = snapshot
        let baseline = KeyboardSettingsSnapshot.default
        normalized.stableUserBucket = baseline.stableUserBucket
        normalized.remoteConfig = baseline.remoteConfig
        normalized.remoteConfigFetchedAt = baseline.remoteConfigFetchedAt
        normalized.inputKernelFallbackDisabled = baseline.inputKernelFallbackDisabled
        normalized.predictionDisabled = baseline.predictionDisabled
        normalized.glideDisabled = baseline.glideDisabled
        return normalized == baseline
    }

    private static func snapshotByRestoringKeymap(
        from remote: KeyboardSettingsSnapshot,
        into local: KeyboardSettingsSnapshot
    ) -> KeyboardSettingsSnapshot {
        var merged = local
        merged.layoutPreset = remote.layoutPreset
        merged.layoutLocale = remote.layoutLocale
        merged.runtimeLayoutRoute = remote.runtimeLayoutRoute
        merged.toolbarHeight = remote.toolbarHeight
        merged.expandedKeyHeight = remote.expandedKeyHeight
        merged.toolbarKeyCount = remote.toolbarKeyCount
        merged.symbolTopRowKeyCount = remote.symbolTopRowKeyCount
        merged.symbolMiddleRowKeyCount = remote.symbolMiddleRowKeyCount
        merged.symbolBottomRowKeyCount = remote.symbolBottomRowKeyCount
        merged.letterTopRowKeyCount = remote.letterTopRowKeyCount
        merged.letterMiddleRowKeyCount = remote.letterMiddleRowKeyCount
        merged.letterBottomRowKeyCount = remote.letterBottomRowKeyCount
        merged.keymap = remote.keymap
        return merged
    }

    private static func snapshotByRestoringSyncedSettings(
        from remote: KeyboardSettingsSnapshot,
        into local: KeyboardSettingsSnapshot
    ) -> KeyboardSettingsSnapshot {
        var merged = remote
        merged.stableUserBucket = local.stableUserBucket
        merged.remoteConfig = local.remoteConfig
        merged.remoteConfigFetchedAt = local.remoteConfigFetchedAt
        return merged
    }

    private static func keymapPackageDiffers(
        _ lhs: KeyboardSettingsSnapshot,
        _ rhs: KeyboardSettingsSnapshot
    ) -> Bool {
        lhs.layoutPreset != rhs.layoutPreset ||
            lhs.layoutLocale != rhs.layoutLocale ||
            lhs.runtimeLayoutRoute != rhs.runtimeLayoutRoute ||
            lhs.toolbarHeight != rhs.toolbarHeight ||
            lhs.expandedKeyHeight != rhs.expandedKeyHeight ||
            lhs.toolbarKeyCount != rhs.toolbarKeyCount ||
            lhs.symbolTopRowKeyCount != rhs.symbolTopRowKeyCount ||
            lhs.symbolMiddleRowKeyCount != rhs.symbolMiddleRowKeyCount ||
            lhs.symbolBottomRowKeyCount != rhs.symbolBottomRowKeyCount ||
            lhs.letterTopRowKeyCount != rhs.letterTopRowKeyCount ||
            lhs.letterMiddleRowKeyCount != rhs.letterMiddleRowKeyCount ||
            lhs.letterBottomRowKeyCount != rhs.letterBottomRowKeyCount ||
            lhs.keymap != rhs.keymap
    }
}

private struct HWKSettingsiCloudArchive: Codable {
    var appTheme: String
    var accentPalette: String
    var customKeyStyle: KeyboardCustomKeyStyle?
    var vibrationEnabled: Bool
    var feedbackLevel: String
    var autoPairEnabled: Bool
    var startExpanded: Bool
    var defaultSymbolLayer: Bool
    var showQuickInsertRow: Bool
    var hideKeyboardEnabled: Bool?
    var highContrastKeys: Bool
    var largeLegends: Bool
    var showControlLabels: Bool
    var capitalizeFirstLetterEnabled: Bool
    var doubleSpacePeriodEnabled: Bool?
    var autocorrectEnabled: Bool
    var autocompleteEnabled: Bool
    var clickToFixEnabled: Bool
    var autocorrectRankingMethod: String?
    var autocorrectLogicRecipe: String?
    var autocorrectLogicBlocks: [KeyboardAutocorrectLogicBlock]?
    var autocorrectLogicLanes: [KeyboardAutocorrectLogicLane]?
    var edgeSwipeConfiguration: KeyboardEdgeSwipeConfiguration?
    var semiFoldEnabled: Bool?
    var suggestionSwipeUpAction: String?
    var suggestionSwipeDownAction: String?
    var suggestionSwipeLeftDeleteEnabled: Bool?
    var suggestionSwipeRightSpaceEnabled: Bool?
    var suggestionHoldForRolodexEnabled: Bool?
    var saveClipboardSettingsWithLiveKeyboard: Bool?
    var showQuickInsertHandle: Bool
    var inputKernelFallbackDisabled: Bool?
    var predictionDisabled: Bool?
    var glideDisabled: Bool?
    var clipboardDisabled: Bool?
    var capsHoldToLockEnabled: Bool
    var capsHoldDurationMs: Int
    var menuHoldToLatchEnabled: Bool
    var menuHoldDurationMs: Int
    var keyHoldDurationMs: Int
    var rolodexSelectHoldDurationMs: Int?
    var menuTapLockWindowMs: Int
    var deleteHoldEnabled: Bool
    var deleteHoldWordsBeforeSentence: Int
    var layoutPreset: String
    var layoutLocale: String
    var runtimeLayoutRoute: String?
    var toolbarHeight: Int
    var expandedKeyHeight: Int
    var toolbarKeyCount: Int
    var symbolTopRowKeyCount: Int
    var symbolMiddleRowKeyCount: Int
    var symbolBottomRowKeyCount: Int
    var letterTopRowKeyCount: Int
    var letterMiddleRowKeyCount: Int
    var letterBottomRowKeyCount: Int
    var keymap: KeyboardKeymap
    #if HWC_INTERNAL_BUILD
    var signalRelayEnabled: Bool?
    var signalRelayEmitKeyUp: Bool?
    var signalRelayPriorityMode: Bool?
    var signalRelaySessionPersist: Bool?
    var signalRelayHoldTriggerMs: Int?
    #endif

    init(snapshot: KeyboardSettingsSnapshot) {
        appTheme = snapshot.appTheme.rawValue
        accentPalette = snapshot.accentPalette.rawValue
        customKeyStyle = snapshot.customKeyStyle.normalized
        vibrationEnabled = snapshot.vibrationEnabled
        feedbackLevel = snapshot.feedbackLevel.rawValue
        autoPairEnabled = snapshot.autoPairEnabled
        startExpanded = snapshot.startExpanded
        defaultSymbolLayer = snapshot.defaultSymbolLayer
        showQuickInsertRow = snapshot.showQuickInsertRow
        hideKeyboardEnabled = snapshot.hideKeyboardEnabled
        highContrastKeys = snapshot.highContrastKeys
        largeLegends = snapshot.largeLegends
        showControlLabels = snapshot.showControlLabels
        capitalizeFirstLetterEnabled = snapshot.capitalizeFirstLetterEnabled
        doubleSpacePeriodEnabled = snapshot.doubleSpacePeriodEnabled
        autocorrectEnabled = snapshot.autocorrectEnabled
        autocompleteEnabled = snapshot.autocompleteEnabled
        clickToFixEnabled = snapshot.clickToFixEnabled
        autocorrectRankingMethod = snapshot.autocorrectRankingMethod.rawValue
        autocorrectLogicRecipe = snapshot.autocorrectLogicRecipe.rawValue
        autocorrectLogicBlocks = snapshot.autocorrectLogicBlocks
        autocorrectLogicLanes = snapshot.autocorrectLogicLanes
        edgeSwipeConfiguration = snapshot.edgeSwipeConfiguration.normalized(for: snapshot.keymap)
        semiFoldEnabled = snapshot.semiFoldEnabled
        suggestionSwipeUpAction = snapshot.suggestionSwipeUpAction.rawValue
        suggestionSwipeDownAction = snapshot.suggestionSwipeDownAction.rawValue
        suggestionSwipeLeftDeleteEnabled = snapshot.suggestionSwipeLeftDeleteEnabled
        suggestionSwipeRightSpaceEnabled = snapshot.suggestionSwipeRightSpaceEnabled
        suggestionHoldForRolodexEnabled = true
        saveClipboardSettingsWithLiveKeyboard = snapshot.saveClipboardSettingsWithLiveKeyboard
        showQuickInsertHandle = snapshot.showQuickInsertHandle
        inputKernelFallbackDisabled = snapshot.inputKernelFallbackDisabled
        predictionDisabled = snapshot.predictionDisabled
        glideDisabled = snapshot.glideDisabled
        clipboardDisabled = snapshot.clipboardDisabled
        capsHoldToLockEnabled = snapshot.capsHoldToLockEnabled
        capsHoldDurationMs = snapshot.capsHoldDurationMs
        menuHoldToLatchEnabled = snapshot.menuHoldToLatchEnabled
        menuHoldDurationMs = snapshot.menuHoldDurationMs
        keyHoldDurationMs = snapshot.keyHoldDurationMs
        rolodexSelectHoldDurationMs = snapshot.rolodexSelectHoldDurationMs
        menuTapLockWindowMs = snapshot.menuTapLockWindowMs
        deleteHoldEnabled = snapshot.deleteHoldEnabled
        deleteHoldWordsBeforeSentence = snapshot.deleteHoldWordsBeforeSentence
        layoutPreset = snapshot.layoutPreset.rawValue
        layoutLocale = snapshot.layoutLocale.rawValue
        runtimeLayoutRoute = snapshot.runtimeLayoutRoute.rawValue
        toolbarHeight = snapshot.toolbarHeight
        expandedKeyHeight = snapshot.expandedKeyHeight
        toolbarKeyCount = snapshot.toolbarKeyCount
        symbolTopRowKeyCount = snapshot.symbolTopRowKeyCount
        symbolMiddleRowKeyCount = snapshot.symbolMiddleRowKeyCount
        symbolBottomRowKeyCount = snapshot.symbolBottomRowKeyCount
        letterTopRowKeyCount = snapshot.letterTopRowKeyCount
        letterMiddleRowKeyCount = snapshot.letterMiddleRowKeyCount
        letterBottomRowKeyCount = snapshot.letterBottomRowKeyCount
        keymap = snapshot.keymap
        #if HWC_INTERNAL_BUILD
        signalRelayEnabled = snapshot.signalRelayEnabled
        signalRelayEmitKeyUp = snapshot.signalRelayEmitKeyUp
        signalRelayPriorityMode = snapshot.signalRelayPriorityMode
        signalRelaySessionPersist = snapshot.signalRelaySessionPersist
        signalRelayHoldTriggerMs = snapshot.signalRelayHoldTriggerMs
        #endif
    }

    var snapshot: KeyboardSettingsSnapshot {
        var snapshot = KeyboardSettingsSnapshot.default
        snapshot.appTheme = CompanionAppTheme.resolved(from: appTheme) ?? snapshot.appTheme
        snapshot.accentPalette = KeyboardAccentPalette(rawValue: accentPalette) ?? snapshot.accentPalette
        snapshot.customKeyStyle = customKeyStyle?.normalized ?? snapshot.customKeyStyle
        snapshot.vibrationEnabled = vibrationEnabled
        snapshot.feedbackLevel = KeyboardFeedbackLevel(rawValue: feedbackLevel) ?? snapshot.feedbackLevel
        snapshot.autoPairEnabled = autoPairEnabled
        snapshot.startExpanded = startExpanded
        snapshot.defaultSymbolLayer = defaultSymbolLayer
        snapshot.showQuickInsertRow = showQuickInsertRow
        snapshot.hideKeyboardEnabled = hideKeyboardEnabled ?? snapshot.hideKeyboardEnabled
        snapshot.highContrastKeys = highContrastKeys
        snapshot.largeLegends = largeLegends
        snapshot.showControlLabels = showControlLabels
        snapshot.capitalizeFirstLetterEnabled = capitalizeFirstLetterEnabled
        snapshot.doubleSpacePeriodEnabled = doubleSpacePeriodEnabled ?? snapshot.doubleSpacePeriodEnabled
        snapshot.autocorrectEnabled = autocorrectEnabled
        snapshot.autocompleteEnabled = autocompleteEnabled
        snapshot.clickToFixEnabled = clickToFixEnabled
        snapshot.autocorrectRankingMethod = autocorrectRankingMethod
            .flatMap(KeyboardAutocorrectRankingMethod.init(rawValue:))
            ?? snapshot.autocorrectRankingMethod
        snapshot.autocorrectLogicRecipe = autocorrectLogicRecipe
            .flatMap(KeyboardAutocorrectLogicRecipe.init(rawValue:))
            ?? snapshot.autocorrectLogicRecipe
        snapshot.autocorrectLogicBlocks = autocorrectLogicBlocks ?? snapshot.autocorrectLogicBlocks
        snapshot.autocorrectLogicLanes = autocorrectLogicLanes ?? snapshot.autocorrectLogicLanes
        snapshot.suggestionSwipeUpAction = suggestionSwipeUpAction.flatMap(KeyboardSuggestionSwipeUpAction.init(rawValue:))
            ?? snapshot.suggestionSwipeUpAction
        snapshot.suggestionSwipeDownAction = suggestionSwipeDownAction.flatMap(KeyboardSuggestionSwipeDownAction.init(rawValue:))
            ?? snapshot.suggestionSwipeDownAction
        snapshot.suggestionSwipeLeftDeleteEnabled = suggestionSwipeLeftDeleteEnabled
            ?? snapshot.suggestionSwipeLeftDeleteEnabled
        snapshot.suggestionSwipeRightSpaceEnabled = suggestionSwipeRightSpaceEnabled
            ?? snapshot.suggestionSwipeRightSpaceEnabled
        snapshot.suggestionHoldForRolodexEnabled = true
        snapshot.saveClipboardSettingsWithLiveKeyboard = saveClipboardSettingsWithLiveKeyboard
            ?? snapshot.saveClipboardSettingsWithLiveKeyboard
        snapshot.showQuickInsertHandle = showQuickInsertHandle
        snapshot.inputKernelFallbackDisabled = inputKernelFallbackDisabled ?? snapshot.inputKernelFallbackDisabled
        snapshot.predictionDisabled = predictionDisabled ?? snapshot.predictionDisabled
        snapshot.glideDisabled = glideDisabled ?? snapshot.glideDisabled
        snapshot.clipboardDisabled = clipboardDisabled ?? snapshot.clipboardDisabled
        snapshot.capsHoldToLockEnabled = capsHoldToLockEnabled
        snapshot.capsHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(capsHoldDurationMs)
        snapshot.menuHoldToLatchEnabled = menuHoldToLatchEnabled
        snapshot.menuHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(menuHoldDurationMs)
        snapshot.keyHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(keyHoldDurationMs)
        snapshot.rolodexSelectHoldDurationMs = KeyboardLayoutBounds.clampedRolodexSelectHoldDurationMs(
            rolodexSelectHoldDurationMs ?? snapshot.rolodexSelectHoldDurationMs
        )
        snapshot.menuTapLockWindowMs = KeyboardLayoutBounds.clampedMenuTapLockWindowMs(menuTapLockWindowMs)
        snapshot.deleteHoldEnabled = deleteHoldEnabled
        snapshot.deleteHoldWordsBeforeSentence = KeyboardLayoutBounds.clampedDeleteHoldWordCount(
            deleteHoldWordsBeforeSentence
        )
        snapshot.layoutPreset = KeyboardLayoutPreset.resolved(from: layoutPreset) ?? snapshot.layoutPreset
        snapshot.layoutLocale = KeyboardLayoutLocale(rawValue: layoutLocale) ?? snapshot.layoutLocale
        snapshot.runtimeLayoutRoute = runtimeLayoutRoute
            .flatMap(KeyboardRuntimeLayoutRoute.init(rawValue:))
            ?? (snapshot.layoutPreset == .custom ? .storedKeymap : snapshot.runtimeLayoutRoute)
        snapshot.toolbarHeight = KeyboardLayoutBounds.clampedToolbarHeight(toolbarHeight)
        snapshot.expandedKeyHeight = KeyboardLayoutBounds.clampedExpandedKeyHeight(expandedKeyHeight)
        snapshot.toolbarKeyCount = KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount)
        snapshot.symbolTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount)
        snapshot.symbolMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount)
        snapshot.symbolBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount)
        snapshot.letterTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount)
        snapshot.letterMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount)
        snapshot.letterBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount)
        snapshot.keymap = keymap
        snapshot.edgeSwipeConfiguration = (edgeSwipeConfiguration ?? KeyboardEdgeSwipeConfiguration()).normalized(for: keymap)
        snapshot.semiFoldEnabled = semiFoldEnabled ?? false
        #if HWC_INTERNAL_BUILD
        snapshot.signalRelayEnabled = signalRelayEnabled ?? snapshot.signalRelayEnabled
        snapshot.signalRelayEmitKeyUp = signalRelayEmitKeyUp ?? snapshot.signalRelayEmitKeyUp
        snapshot.signalRelayPriorityMode = signalRelayPriorityMode ?? snapshot.signalRelayPriorityMode
        snapshot.signalRelaySessionPersist = signalRelaySessionPersist ?? snapshot.signalRelaySessionPersist
        snapshot.signalRelayHoldTriggerMs = KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(
            signalRelayHoldTriggerMs ?? snapshot.signalRelayHoldTriggerMs
        )
        #endif
        return snapshot
    }
}

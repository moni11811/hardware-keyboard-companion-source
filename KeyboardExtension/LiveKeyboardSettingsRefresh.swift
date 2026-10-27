import Foundation

struct LiveKeyboardSettingsRefreshLoader:
    KeyboardSettingsRefreshLoading,
    Sendable
{
    func load() -> KeyboardSettingsRefreshSnapshot {
        let autocorrectionRuntime = KeyboardLearningWriteCoordinator.withOrderedPersistenceRead {
            KeyboardAutocorrectionRuntimeSnapshot(
                personalizer: HWKAutocorrectionPersonalizationStore().load(),
                championCreditModel: HWKAutobotBrainSnapshotStore().loadChampion().creditModel,
                languageBrain: HWKLanguageBrainSnapshotStore().load(),
                rejectedAutocorrectionFingerprints:
                    HWKAutocorrectionRejectionStore().activeFingerprintsSnapshot()
            )
        }
        return KeyboardSettingsRefreshSnapshot(
            settings: KeyboardSettingsSnapshot.loadForExtensionRefresh(),
            customDictionaryWords: KeyboardSharedPreferences.customDictionaryWordsSnapshot(),
            autocorrectionRuntime: autocorrectionRuntime
        )
    }
}

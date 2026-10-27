import Foundation

protocol AutobotResetEpochProviding: Sendable {
    func currentResetEpoch() -> String
}

struct ExtensionSafeAutobotResetEpochProvider:
    AutobotResetEpochProviding,
    @unchecked Sendable
{
    private let manifestStore: HWKAutobotLearnerManifestStore

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        manifestStore = HWKAutobotLearnerManifestStore(
            defaults: defaults,
            transactionMode: .extensionSafe
        )
    }

    func currentResetEpoch() -> String {
        manifestStore.mutationEpoch()
    }
}

/// App Group adapter for `AutobotEpisodePersistenceCoordinator`.
/// Mutable stores are confined to the coordinator's serial executor.
struct LiveAutobotEpisodePersistenceExecutor:
    AutobotEpisodePersistenceExecuting,
    @unchecked Sendable
{
    private let typingEpisodeStore: HWKAutobotTypingEpisodeStore
    private let brainSnapshotStore: HWKAutobotBrainSnapshotStore
    private let ruleHypothesisStore: HWKAutobotRuleHypothesisStore
    private let romanizedHypothesisStore: HWKAutobotRomanizedHypothesisStore
    private let phraseLearner: HWKPersistentPhraseLearner
    private let resetEpochProvider: any AutobotResetEpochProviding

    init(
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        resetEpochProvider: (any AutobotResetEpochProviding)? = nil
    ) {
        typingEpisodeStore = HWKAutobotTypingEpisodeStore(defaults: defaults)
        brainSnapshotStore = HWKAutobotBrainSnapshotStore(defaults: defaults)
        ruleHypothesisStore = HWKAutobotRuleHypothesisStore(defaults: defaults)
        romanizedHypothesisStore = HWKAutobotRomanizedHypothesisStore(defaults: defaults)
        phraseLearner = HWKPersistentPhraseLearner(defaults: defaults)
        self.resetEpochProvider = resetEpochProvider
            ?? ExtensionSafeAutobotResetEpochProvider(defaults: defaults)
    }

    func loadTypingEpisodes(
        expectedResetEpoch: String
    ) -> AutobotEpisodeLoadOutcome {
        guard resetEpochProvider.currentResetEpoch() == expectedResetEpoch else {
            return .skippedStaleEpoch
        }
        let coordinator = typingEpisodeStore.load()
            ?? HWKAutobotLiveEpisodeCoordinator(
                capacity: 48,
                delayedRepairWindowMilliseconds: 60_000
            )
        guard resetEpochProvider.currentResetEpoch() == expectedResetEpoch else {
            return .skippedStaleEpoch
        }
        return .loaded(coordinator)
    }

    func execute(
        _ request: AutobotEpisodePersistenceRequest
    ) -> AutobotEpisodePersistenceOutcome {
        guard resetEpochIsCurrent(for: request) else {
            return .skippedStaleEpoch
        }

        switch request.kind {
        case .persist:
            if let candidate = request.candidateMemory {
                guard resetEpochIsCurrent(for: request) else {
                    return .skippedStaleEpoch
                }
                _ = ruleHypothesisStore.rememberCandidate(
                    source: candidate.source,
                    replacement: candidate.replacement,
                    isSensitive: false,
                    timestampMilliseconds: candidate.timestampMilliseconds
                )
                guard resetEpochIsCurrent(for: request) else {
                    return .skippedStaleEpoch
                }
                _ = romanizedHypothesisStore.rememberCandidate(
                    source: candidate.source,
                    replacement: candidate.replacement,
                    isSensitive: false,
                    timestampMilliseconds: candidate.timestampMilliseconds
                )
            }

            guard resetEpochIsCurrent(for: request),
                  let coordinator = request.coordinator,
                  typingEpisodeStore.save(coordinator) else {
                return resetEpochIsCurrent(for: request)
                    ? .failed
                    : .skippedStaleEpoch
            }
            return reconcileAfterLiveSave(request)

        case .reconcile:
            return reconcileAfterSettingsRefresh(request)
        }
    }

    private func reconcileAfterLiveSave(
        _ request: AutobotEpisodePersistenceRequest
    ) -> AutobotEpisodePersistenceOutcome {
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        _ = phraseLearner.reconcileParagraphPlanFeedback(request.snapshot)
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        _ = ruleHypothesisStore.reconcile(request.snapshot)
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        _ = romanizedHypothesisStore.reconcile(request.snapshot)
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        return brainOutcome(for: request)
    }

    private func reconcileAfterSettingsRefresh(
        _ request: AutobotEpisodePersistenceRequest
    ) -> AutobotEpisodePersistenceOutcome {
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        let brainOutcome = brainOutcome(
            for: request,
            requiresChampionRefresh: true
        )
        guard brainOutcome.status == .committed,
              resetEpochIsCurrent(for: request) else {
            return brainOutcome.status == .committed
                ? .skippedStaleEpoch
                : brainOutcome
        }
        _ = ruleHypothesisStore.reconcile(request.snapshot)
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        _ = romanizedHypothesisStore.reconcile(request.snapshot)
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        _ = phraseLearner.reconcileParagraphPlanFeedback(request.snapshot)
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        return brainOutcome
    }

    private func brainOutcome(
        for request: AutobotEpisodePersistenceRequest,
        requiresChampionRefresh: Bool = false
    ) -> AutobotEpisodePersistenceOutcome {
        guard resetEpochIsCurrent(for: request) else { return .skippedStaleEpoch }
        let update = brainSnapshotStore.observe(
            request.snapshot,
            timestampMilliseconds: request.timestampMilliseconds
        )
        let shouldReloadChampion = requiresChampionRefresh
            || update.decision == .promote
            || update.decision == .rollback
        return .committed(
            shouldReloadChampion: shouldReloadChampion,
            championCreditModel: shouldReloadChampion ? update.state.champion.creditModel : nil
        )
    }

    private func resetEpochIsCurrent(
        for request: AutobotEpisodePersistenceRequest
    ) -> Bool {
        resetEpochProvider.currentResetEpoch() == request.expectedResetEpoch
    }
}

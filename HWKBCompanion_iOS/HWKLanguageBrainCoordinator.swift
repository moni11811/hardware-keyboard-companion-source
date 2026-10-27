import Combine
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

protocol HWKLanguageBrainGenerating {
    /// `nil` means the on-device model is unavailable or failed. An empty array
    /// means it ran but found no policy worth proposing.
    func proposals(
        from events: [HWKLanguageBrainEvent]
    ) async -> [HWKLanguageBrainPolicyProposal]?
}

struct HWKAppleLanguageBrainGenerator: HWKLanguageBrainGenerating {
    static let systemInstructionsText = """
    You are HWC's private on-device autocorrection learner. Infer only repeated behavior
    supported by the supplied decision events. Never invent words, transformations, or
    evidence IDs. Return at most eight narrow policies. Use preferReplacement only when
    the person repeatedly accepted the same pair. Use suppressReplacement when the person
    repeatedly undid the same pair. Use protectTerm only when multiple rejected decisions
    prove that the original term is intentional. Keep intent and decision concise.
    The app validates every field and discards unsupported output.
    """

    static func policyKind(from value: String) -> HWKLanguageBrainPolicyKind? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "preferreplacement": return .preferReplacement
        case "suppressreplacement": return .suppressReplacement
        case "protectterm": return .protectTerm
        default: return nil
        }
    }

    func proposals(
        from events: [HWKLanguageBrainEvent]
    ) async -> [HWKLanguageBrainPolicyProposal]? {
        guard !events.isEmpty else { return [] }
#if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        let model = SystemLanguageModel.default
        guard model.isAvailable, model.supportsLocale(Locale.current) else { return nil }
        return await generate(from: events, model: model)
#else
        return nil
#endif
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generate(
        from events: [HWKLanguageBrainEvent],
        model: SystemLanguageModel
    ) async -> [HWKLanguageBrainPolicyProposal]? {
        let session = LanguageModelSession(
            model: model,
            instructions: Self.systemInstructionsText
        )

        do {
            let response = try await session.respond(
                to: Self.prompt(from: events),
                generating: GeneratedPolicyBatch.self
            )
            return response.content.policies.prefix(8).compactMap { $0.proposal }
        } catch {
            return nil
        }
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedPolicyBatch {
        @Guide(description: "Zero to eight narrow, evidence-backed learned policies")
        var policies: [GeneratedPolicy]
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedPolicy {
        @Guide(description: "Exactly preferReplacement, suppressReplacement, or protectTerm")
        var kind: String
        @Guide(description: "Exact original text from the cited events")
        var source: String
        @Guide(description: "Exact replacement from cited events; empty only for protectTerm")
        var replacement: String
        @Guide(description: "Short description of the person's inferred typing intent")
        var intent: String
        @Guide(description: "Short description of the safe runtime decision")
        var decision: String
        @Guide(description: "Confidence from 70 through 99")
        var confidencePercent: Int
        @Guide(description: "Exact UUID strings copied only from supporting events")
        var supportingEventIDs: [String]

        var proposal: HWKLanguageBrainPolicyProposal? {
            guard let policyKind = HWKAppleLanguageBrainGenerator.policyKind(from: kind) else {
                return nil
            }
            return HWKLanguageBrainPolicyProposal(
                kind: policyKind,
                source: source,
                replacement: replacement,
                intent: intent,
                decision: decision,
                confidence: Double(max(0, min(100, confidencePercent))) / 100,
                supportingEventIDs: supportingEventIDs.compactMap(UUID.init(uuidString:))
            )
        }
    }
#endif

    private static func prompt(from events: [HWKLanguageBrainEvent]) -> String {
        let payload = events.suffix(48).map { event in
            [
                "id": event.id.uuidString,
                "time": ISO8601DateFormatter().string(from: event.occurredAt),
                "original": event.original,
                "replacement": event.replacement,
                "outcome": event.outcome.rawValue,
                "contextBefore": event.contextBefore,
                "source": event.source
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return "Decision events:\n\(json)"
    }
}

@MainActor
final class HWKLanguageBrainCoordinator: ObservableObject {
    enum Status: Equatable {
        case idle
        case waiting(decisions: Int)
        case reasoning
        case learned(policies: Int)
        case failed

        var title: String {
            switch self {
            case .idle: return "Ready"
            case .waiting(let decisions): return "Learning from \(decisions) decision\(decisions == 1 ? "" : "s")"
            case .reasoning: return "Reasoning on device"
            case .learned(let policies): return "\(policies) learned behavior\(policies == 1 ? "" : "s")"
            case .failed: return "Using safe baseline"
            }
        }
    }

    @Published private(set) var snapshot: HWKLanguageBrainSnapshot
    @Published private(set) var status: Status = .idle
    @Published private(set) var observedDecisionCount = 0

    private let eventStore: HWKLanguageBrainEventStore
    private let snapshotStore: HWKLanguageBrainSnapshotStore
    private let autobotLearnerManifestStore: HWKAutobotLearnerManifestStore
    private let generator: HWKLanguageBrainGenerating
    private let now: () -> Date
    private var isConsolidating = false

    init(
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        generator: HWKLanguageBrainGenerating = HWKAppleLanguageBrainGenerator(),
        now: @escaping () -> Date = Date.init
    ) {
        eventStore = HWKLanguageBrainEventStore(defaults: defaults)
        snapshotStore = HWKLanguageBrainSnapshotStore(defaults: defaults)
        autobotLearnerManifestStore = HWKAutobotLearnerManifestStore(defaults: defaults)
        self.generator = generator
        self.now = now
        _ = autobotLearnerManifestStore.loadAndRepair()
        snapshot = snapshotStore.load()
        observedDecisionCount = eventStore.load().count
        status = snapshot.policies.isEmpty
            ? .waiting(decisions: observedDecisionCount)
            : .learned(policies: snapshot.policies.count)
    }

    @discardableResult
    func consolidate(force: Bool = false) async -> HWKLanguageBrainSnapshot {
        guard !isConsolidating else { return snapshot }
        let events = eventStore.load()
        observedDecisionCount = events.count
        guard events.count >= HWKLanguageBrainValidator.minimumEvidence else {
            status = .waiting(decisions: events.count)
            return snapshot
        }
        if !force,
           let latestEvent = events.last,
           snapshot.generatedAt >= latestEvent.occurredAt {
            status = snapshot.policies.isEmpty
                ? .waiting(decisions: events.count)
                : .learned(policies: snapshot.policies.count)
            return snapshot
        }

        isConsolidating = true
        status = .reasoning
        defer { isConsolidating = false }

        let validator = HWKLanguageBrainValidator()
        let generatedProposals = await generator.proposals(from: events)
        let modelPolicies = validator.validatedPolicies(
            proposals: generatedProposals ?? [],
            events: events,
            now: now()
        )
        let fallbackPolicies = validator.validatedPolicies(
            proposals: HWKLanguageBrainPatternMiner.proposals(from: events),
            events: events,
            now: now()
        )
        let selectedSource: HWKLanguageBrainModelSource = modelPolicies.isEmpty
            ? .deterministicFallback
            : .onDeviceFoundationModel
        let learnedPolicies = Self.mergedPolicies(
            primary: modelPolicies,
            fallback: fallbackPolicies
        )

        let published = HWKLanguageBrainSnapshot(
            revision: max(1, snapshot.revision + 1),
            generatedAt: now(),
            source: selectedSource,
            policies: learnedPolicies
        )
        guard snapshotStore.publish(published) else {
            status = .failed
            return snapshot
        }
        snapshot = published
        status = published.policies.isEmpty
            ? .waiting(decisions: events.count)
            : .learned(policies: published.policies.count)
        KeyboardSharedPreferences.sync()
        KeyboardSharedPreferences.postSettingsDidChangeNotification()
        return published
    }

    func refresh() {
        snapshot = snapshotStore.load()
        observedDecisionCount = eventStore.load().count
        status = snapshot.policies.isEmpty
            ? .waiting(decisions: observedDecisionCount)
            : .learned(policies: snapshot.policies.count)
    }

    func forget(policyID: String) {
        guard let forgottenPolicy = snapshot.policies.first(where: { $0.id == policyID }) else {
            return
        }
        let remaining = snapshot.policies.filter { $0.id != policyID }
        eventStore.removeEvidence(for: forgottenPolicy)
        observedDecisionCount = eventStore.load().count
        let revised = HWKLanguageBrainSnapshot(
            revision: max(1, snapshot.revision + 1),
            generatedAt: now(),
            source: snapshot.source,
            policies: remaining
        )
        guard snapshotStore.publish(revised) else { return }
        snapshot = revised
        status = remaining.isEmpty ? .waiting(decisions: observedDecisionCount) : .learned(policies: remaining.count)
        KeyboardSharedPreferences.sync()
        KeyboardSharedPreferences.postSettingsDidChangeNotification()
    }

    func reset() {
        eventStore.clear()
        snapshotStore.clear()
        snapshot = .empty
        observedDecisionCount = 0
        status = .waiting(decisions: 0)
        KeyboardSharedPreferences.sync()
        KeyboardSharedPreferences.postSettingsDidChangeNotification()
    }

    private static func mergedPolicies(
        primary: [HWKLanguageBrainPolicy],
        fallback: [HWKLanguageBrainPolicy]
    ) -> [HWKLanguageBrainPolicy] {
        var byID = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id, $0) })
        for policy in primary { byID[policy.id] = policy }
        return byID.values
            .sorted {
                if $0.evidenceCount != $1.evidenceCount { return $0.evidenceCount > $1.evidenceCount }
                return $0.id < $1.id
            }
            .prefix(HWKLanguageBrainValidator.maximumPolicies)
            .map { $0 }
    }
}

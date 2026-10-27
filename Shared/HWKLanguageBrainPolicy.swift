import Foundation

enum HWKLanguageBrainOutcome: String, Codable, Equatable, Sendable {
    case accepted
    case rejected
}

struct HWKLanguageBrainEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let occurredAt: Date
    let original: String
    let replacement: String
    let outcome: HWKLanguageBrainOutcome
    let contextBefore: String
    let source: String
}

enum HWKLanguageBrainPolicyKind: String, Codable, Equatable, Sendable {
    case preferReplacement
    case suppressReplacement
    case protectTerm
}

enum HWKLanguageBrainModelSource: String, Codable, Equatable, Sendable {
    case onDeviceFoundationModel
    case deterministicFallback
}

struct HWKLanguageBrainPolicyProposal: Equatable, Sendable {
    let kind: HWKLanguageBrainPolicyKind
    let source: String
    let replacement: String
    let intent: String
    let decision: String
    let confidence: Double
    let supportingEventIDs: [UUID]
}

struct HWKLanguageBrainPolicy: Codable, Equatable, Identifiable, Sendable {
    let kind: HWKLanguageBrainPolicyKind
    let source: String
    let replacement: String
    let intent: String
    let decision: String
    let confidence: Double
    let evidenceCount: Int
    let createdAt: Date

    var id: String {
        Self.identifier(kind: kind, source: source, replacement: replacement)
    }

    static func identifier(
        kind: HWKLanguageBrainPolicyKind,
        source: String,
        replacement: String
    ) -> String {
        "\(kind.rawValue):\(normalizedToken(source))->\(normalizedToken(replacement))"
    }

    private static func normalizedToken(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct HWKLanguageBrainSnapshot: Codable, Equatable, Sendable {
    let revision: Int
    let generatedAt: Date
    let source: HWKLanguageBrainModelSource
    let policies: [HWKLanguageBrainPolicy]

    static let empty = HWKLanguageBrainSnapshot(
        revision: 0,
        generatedAt: Date(timeIntervalSince1970: 0),
        source: .deterministicFallback,
        policies: []
    )
}

struct HWKLanguageBrainValidator {
    static let minimumEvidence = 3
    static let maximumPolicies = 32

    func validatedPolicies(
        proposals: [HWKLanguageBrainPolicyProposal],
        events: [HWKLanguageBrainEvent],
        now: Date = Date()
    ) -> [HWKLanguageBrainPolicy] {
        var policiesByID = [String: HWKLanguageBrainPolicy]()

        for proposal in proposals.prefix(Self.maximumPolicies * 2) {
            guard proposal.confidence.isFinite, proposal.confidence >= 0.70 else { continue }
            let source = Self.normalizedText(proposal.source, maximumLength: 96)
            let replacement = Self.normalizedText(proposal.replacement, maximumLength: 96)
            guard !source.isEmpty else { continue }
            guard proposal.kind == .protectTerm || (!replacement.isEmpty && source != replacement) else {
                continue
            }

            let citedIDs = Set(proposal.supportingEventIDs)
            let matchingEvents = events.filter { event in
                guard citedIDs.contains(event.id) else { return false }
                return Self.event(event, supports: proposal.kind, source: source, replacement: replacement)
            }
            guard matchingEvents.count >= Self.minimumEvidence else { continue }

            switch proposal.kind {
            case .preferReplacement, .suppressReplacement:
                let oppositeKind: HWKLanguageBrainPolicyKind = proposal.kind == .preferReplacement
                    ? .suppressReplacement
                    : .preferReplacement
                let supportingCount = events.filter {
                    Self.event($0, supports: proposal.kind, source: source, replacement: replacement)
                }.count
                let opposingCount = events.filter {
                    Self.event($0, supports: oppositeKind, source: source, replacement: replacement)
                }.count
                guard supportingCount > opposingCount else { continue }
            case .protectTerm:
                let distinctRejectedAlternatives = Set(matchingEvents.map {
                    Self.normalizedText($0.replacement, maximumLength: 96).lowercased()
                }.filter { !$0.isEmpty })
                let rejectedCount = events.filter {
                    Self.event($0, supports: .protectTerm, source: source, replacement: "")
                }.count
                let acceptedCount = events.filter { event in
                    let eventSource = Self.normalizedText(event.original, maximumLength: 96)
                    return event.outcome == .accepted &&
                        eventSource.caseInsensitiveCompare(source) == .orderedSame
                }.count
                guard distinctRejectedAlternatives.count >= 2, rejectedCount > acceptedCount else {
                    continue
                }
            }

            let latest = matchingEvents.max { $0.occurredAt < $1.occurredAt }
            let evidencedSource = latest?.original ?? source
            let evidencedReplacement = proposal.kind == .protectTerm
                ? ""
                : (latest?.replacement ?? replacement)
            let intent = Self.normalizedText(proposal.intent, maximumLength: 120)
            let decision = Self.normalizedText(proposal.decision, maximumLength: 180)
            let policy = HWKLanguageBrainPolicy(
                kind: proposal.kind,
                source: evidencedSource,
                replacement: evidencedReplacement,
                intent: intent.isEmpty ? Self.defaultIntent(for: proposal.kind) : intent,
                decision: decision.isEmpty ? Self.defaultDecision(for: proposal.kind) : decision,
                confidence: min(0.99, max(0.70, proposal.confidence)),
                evidenceCount: matchingEvents.count,
                createdAt: now
            )

            if let existing = policiesByID[policy.id],
               existing.evidenceCount > policy.evidenceCount ||
                (existing.evidenceCount == policy.evidenceCount && existing.confidence >= policy.confidence) {
                continue
            }
            policiesByID[policy.id] = policy
        }

        let conflictResolvedPolicies = policiesByID.values.filter { policy in
            let oppositeKind: HWKLanguageBrainPolicyKind
            switch policy.kind {
            case .preferReplacement: oppositeKind = .suppressReplacement
            case .suppressReplacement: oppositeKind = .preferReplacement
            case .protectTerm: return true
            }
            let oppositeID = HWKLanguageBrainPolicy.identifier(
                kind: oppositeKind,
                source: policy.source,
                replacement: policy.replacement
            )
            guard let opposite = policiesByID[oppositeID] else { return true }
            return policy.evidenceCount > opposite.evidenceCount
        }

        return conflictResolvedPolicies
            .sorted {
                if $0.evidenceCount != $1.evidenceCount { return $0.evidenceCount > $1.evidenceCount }
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.id < $1.id
            }
            .prefix(Self.maximumPolicies)
            .map { $0 }
    }

    private static func event(
        _ event: HWKLanguageBrainEvent,
        supports kind: HWKLanguageBrainPolicyKind,
        source: String,
        replacement: String
    ) -> Bool {
        let eventSource = normalizedText(event.original, maximumLength: 96)
        let eventReplacement = normalizedText(event.replacement, maximumLength: 96)
        guard eventSource.caseInsensitiveCompare(source) == .orderedSame else { return false }

        switch kind {
        case .preferReplacement:
            return event.outcome == .accepted &&
                eventReplacement.caseInsensitiveCompare(replacement) == .orderedSame
        case .suppressReplacement:
            return event.outcome == .rejected &&
                eventReplacement.caseInsensitiveCompare(replacement) == .orderedSame
        case .protectTerm:
            return event.outcome == .rejected
        }
    }

    private static func normalizedText(_ value: String, maximumLength: Int) -> String {
        let withoutControls = value.components(separatedBy: .controlCharacters).joined()
        return String(withoutControls.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    private static func defaultIntent(for kind: HWKLanguageBrainPolicyKind) -> String {
        switch kind {
        case .preferReplacement: return "Repeat a correction the person consistently chooses"
        case .suppressReplacement: return "Stop repeating a correction the person consistently undoes"
        case .protectTerm: return "Preserve a term the person intentionally types"
        }
    }

    private static func defaultDecision(for kind: HWKLanguageBrainPolicyKind) -> String {
        switch kind {
        case .preferReplacement: return "Prefer the evidenced replacement"
        case .suppressReplacement: return "Suppress the evidenced replacement pair"
        case .protectTerm: return "Keep the typed term unchanged"
        }
    }
}

enum HWKLanguageBrainPatternMiner {
    static func proposals(from events: [HWKLanguageBrainEvent]) -> [HWKLanguageBrainPolicyProposal] {
        struct Key: Hashable {
            let outcome: HWKLanguageBrainOutcome
            let source: String
            let replacement: String
        }

        let grouped = Dictionary(grouping: events) { event in
            Key(
                outcome: event.outcome,
                source: event.original.lowercased(),
                replacement: event.replacement.lowercased()
            )
        }

        let pairProposals: [HWKLanguageBrainPolicyProposal] = grouped.values.compactMap {
            matchingEvents -> HWKLanguageBrainPolicyProposal? in
            guard matchingEvents.count >= HWKLanguageBrainValidator.minimumEvidence,
                  let latest = matchingEvents.max(by: { $0.occurredAt < $1.occurredAt }) else {
                return nil
            }
            let kind: HWKLanguageBrainPolicyKind = latest.outcome == .accepted
                ? .preferReplacement
                : .suppressReplacement
            let confidence = min(0.98, 0.72 + (Double(matchingEvents.count) * 0.05))
            return HWKLanguageBrainPolicyProposal(
                kind: kind,
                source: latest.original,
                replacement: latest.replacement,
                intent: latest.outcome == .accepted
                    ? "Repeat a correction the person keeps choosing"
                    : "Respect a correction the person keeps undoing",
                decision: latest.outcome == .accepted
                    ? "Prefer \(latest.replacement) after repeated acceptance"
                    : "Stop changing \(latest.original) to \(latest.replacement)",
                confidence: confidence,
                supportingEventIDs: matchingEvents.map(\.id)
            )
        }
        let rejectedBySource = Dictionary(grouping: events.filter {
            $0.outcome == .rejected
        }) { event in
            event.original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        let protectionProposals: [HWKLanguageBrainPolicyProposal] = rejectedBySource.values.compactMap {
            matchingEvents -> HWKLanguageBrainPolicyProposal? in
            guard matchingEvents.count >= HWKLanguageBrainValidator.minimumEvidence,
                  let latest = matchingEvents.max(by: { $0.occurredAt < $1.occurredAt }) else {
                return nil
            }
            let alternatives = Set(matchingEvents.map {
                $0.replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty })
            guard alternatives.count >= 2 else { return nil }
            return HWKLanguageBrainPolicyProposal(
                kind: .protectTerm,
                source: latest.original,
                replacement: "",
                intent: "Preserve a term the person intentionally types",
                decision: "Keep \(latest.original) unchanged after distinct rejected alternatives",
                confidence: min(0.98, 0.72 + (Double(matchingEvents.count) * 0.05)),
                supportingEventIDs: matchingEvents.map(\.id)
            )
        }
        return pairProposals + protectionProposals
    }
}

struct HWKLanguageBrainRuntime {
    let snapshot: HWKLanguageBrainSnapshot

    func shouldSuppressReplacement(original: String, replacement: String) -> Bool {
        snapshot.policies.contains { policy in
            guard Self.matches(policy.source, original) else { return false }
            switch policy.kind {
            case .suppressReplacement:
                return Self.matches(policy.replacement, replacement)
            case .protectTerm:
                return true
            case .preferReplacement:
                return false
            }
        }
    }

    func scoreAdjustment(typed: String, candidate: String) -> Double {
        guard !shouldSuppressReplacement(original: typed, replacement: candidate) else {
            return -2.5
        }
        return snapshot.policies.contains { policy in
            policy.kind == .preferReplacement &&
                Self.matches(policy.source, typed) &&
                Self.matches(policy.replacement, candidate)
        } ? 0.35 : 0
    }

    private static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private static func normalized(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

struct HWKLanguageBrainEventStore {
    static let maximumEntries = 96
    static let maximumEncodedBytes = 64 * 1_024

    private static let storageKey = "keyboard.languageBrain.events.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.events.count <= Self.maximumEntries else {
            return false
        }
        let validator = Self(defaults: .standard)
        return envelope.events.allSatisfy { event in
            validator.normalized(event) == event
                && event.occurredAt.timeIntervalSince1970.isFinite
        }
    }

    @discardableResult
    func record(_ event: HWKLanguageBrainEvent) -> Bool {
        guard let normalized = normalized(event) else { return false }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.languageEvents]
        ) {
            var events = load()
            events.removeAll { $0.id == normalized.id }
            events.append(normalized)
            events.sort { $0.occurredAt < $1.occurredAt }
            events = Array(events.suffix(Self.maximumEntries))

            while !events.isEmpty {
                guard let data = try? JSONEncoder().encode(Envelope(version: 1, events: events)) else {
                    return false
                }
                if data.count <= Self.maximumEncodedBytes {
                    defaults.set(data, forKey: Self.storageKey)
                    return true
                }
                events.removeFirst()
            }
            return false
        }
        return result.value ?? false
    }

    func load() -> [HWKLanguageBrainEvent] {
        guard let data = defaults.data(forKey: Self.storageKey),
              Self.isValidPersistedData(data),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else {
            return []
        }
        return envelope.events
            .compactMap(normalized)
            .sorted { $0.occurredAt < $1.occurredAt }
            .suffix(Self.maximumEntries)
            .map { $0 }
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.languageEvents]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    @discardableResult
    func removeEvidence(for policy: HWKLanguageBrainPolicy) -> Int {
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.languageEvents]
        ) {
            let events = load()
            let remaining = events.filter { event in
                guard Self.sameToken(event.original, policy.source) else { return true }
                if policy.kind == .protectTerm { return false }
                return !Self.sameToken(event.replacement, policy.replacement)
            }
            let removedCount = events.count - remaining.count
            guard removedCount > 0 else { return 0 }
            guard !remaining.isEmpty else {
                defaults.removeObject(forKey: Self.storageKey)
                return removedCount
            }
            guard let data = try? JSONEncoder().encode(Envelope(version: 1, events: remaining)),
                  data.count <= Self.maximumEncodedBytes else {
                return 0
            }
            defaults.set(data, forKey: Self.storageKey)
            return removedCount
        }
        return result.value ?? 0
    }

    private func normalized(_ event: HWKLanguageBrainEvent) -> HWKLanguageBrainEvent? {
        let original = Self.clean(event.original, maximumLength: 96)
        let replacement = Self.clean(event.replacement, maximumLength: 180)
        let source = Self.clean(event.source, maximumLength: 64)
        guard !replacement.isEmpty else { return nil }
        if original.isEmpty {
            guard event.outcome == .accepted,
                  source.hasPrefix("suggestionBar") else { return nil }
        } else {
            guard original != replacement else { return nil }
        }
        return HWKLanguageBrainEvent(
            id: event.id,
            occurredAt: event.occurredAt,
            original: original,
            replacement: replacement,
            outcome: event.outcome,
            contextBefore: Self.clean(event.contextBefore, maximumLength: 1_500),
            source: source
        )
    }

    private static func clean(_ value: String, maximumLength: Int) -> String {
        let withoutControls = value.components(separatedBy: .controlCharacters).joined()
        return String(withoutControls.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
    }

    private static func sameToken(_ lhs: String, _ rhs: String) -> Bool {
        clean(lhs, maximumLength: 96).caseInsensitiveCompare(clean(rhs, maximumLength: 96)) == .orderedSame
    }

    private struct Envelope: Codable {
        let version: Int
        let events: [HWKLanguageBrainEvent]
    }
}

struct HWKLanguageBrainSnapshotStore {
    static let maximumEncodedBytes = 32 * 1_024

    private static let storageKey = "keyboard.languageBrain.snapshot.v1"
    private static let revisionKey = "keyboard.languageBrain.snapshot.revision"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidPersistedData(_ data: Data, revision: Int64) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              revision > 0,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.snapshot.revision == revision,
              envelope.snapshot.generatedAt.timeIntervalSince1970.isFinite,
              envelope.snapshot.policies.count <= HWKLanguageBrainValidator.maximumPolicies else {
            return false
        }
        return envelope.snapshot.policies.allSatisfy { policy in
            !policy.source.isEmpty
                && policy.source.count <= 96
                && policy.replacement.count <= 180
                && policy.intent.count <= 180
                && policy.decision.count <= 180
                && policy.confidence.isFinite
                && (0...1).contains(policy.confidence)
                && policy.evidenceCount >= HWKLanguageBrainValidator.minimumEvidence
                && policy.createdAt.timeIntervalSince1970.isFinite
        }
    }

    func load() -> HWKLanguageBrainSnapshot {
        guard let data = defaults.data(forKey: Self.storageKey),
              Self.isValidPersistedData(
                  data,
                  revision: Int64(defaults.integer(forKey: Self.revisionKey))
              ),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.snapshot.revision > 0,
              envelope.snapshot.revision == defaults.integer(forKey: Self.revisionKey),
              envelope.snapshot.policies.count <= HWKLanguageBrainValidator.maximumPolicies else {
            return .empty
        }
        return envelope.snapshot
    }

    func loadIfChanged(from current: HWKLanguageBrainSnapshot) -> HWKLanguageBrainSnapshot {
        let persistedRevision = defaults.integer(forKey: Self.revisionKey)
        guard persistedRevision != current.revision else { return current }
        return load()
    }

    @discardableResult
    func publish(_ snapshot: HWKLanguageBrainSnapshot) -> Bool {
        guard snapshot.revision > 0,
              snapshot.policies.count <= HWKLanguageBrainValidator.maximumPolicies,
              let data = try? JSONEncoder().encode(Envelope(version: 1, snapshot: snapshot)),
              data.count <= Self.maximumEncodedBytes else {
            return false
        }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.languageSnapshot]
        ) {
            defaults.set(data, forKey: Self.storageKey)
            defaults.set(snapshot.revision, forKey: Self.revisionKey)
            return true
        }
        return result.value ?? false
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.languageSnapshot]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.revisionKey)
        }
    }

    func replacePersistedDataForTesting(_ data: Data) {
        defaults.set(data, forKey: Self.storageKey)
    }

    private struct Envelope: Codable {
        let version: Int
        let snapshot: HWKLanguageBrainSnapshot
    }
}

enum HWKLearnedPhraseRelationship: String, Codable, CaseIterable, Equatable, Sendable {
    case contrast
    case consequence
    case cause
    case condition
    case addition
    case sequence

    fileprivate var explanationLabel: String {
        switch self {
        case .contrast: return "contrasting"
        case .consequence: return "cause-and-result"
        case .cause: return "causal"
        case .condition: return "conditional"
        case .addition: return "additive"
        case .sequence: return "sequential"
        }
    }

    var shortLabel: String {
        switch self {
        case .contrast: return "contrast"
        case .consequence: return "result"
        case .cause: return "cause"
        case .condition: return "condition"
        case .addition: return "addition"
        case .sequence: return "sequence"
        }
    }
}

enum HWKLearnedParagraphPosition: String, Codable, Equatable, Sendable {
    case secondSentence = "second"
    case thirdSentence = "third"
    case laterSentence = "later"
}

enum HWKLearnedParagraphIntent: String, Codable, Equatable, Sendable {
    case evidenceToConclusion
    case problemToNextStep
    case questionToAnswer
    case questionsToAnswer
    case stepsToNextAction
    case optionsToRecommendation
    case causeToAction
    case contrastToRecommendation
    case goalToPlan
    case conditionToAdvice
    case claimToSupport
    case uncertaintyToCaution

    var shortLabel: String {
        switch self {
        case .evidenceToConclusion: return "evidence → conclusion"
        case .problemToNextStep: return "problem → next step"
        case .questionToAnswer: return "question → answer"
        case .questionsToAnswer: return "questions → answer"
        case .stepsToNextAction: return "steps → next action"
        case .optionsToRecommendation: return "options → recommendation"
        case .causeToAction: return "cause → action"
        case .contrastToRecommendation: return "contrast → recommendation"
        case .goalToPlan: return "goal → plan"
        case .conditionToAdvice: return "condition → advice"
        case .claimToSupport: return "claim → support"
        case .uncertaintyToCaution: return "uncertainty → caution"
        }
    }

    var explanationLabel: String {
        switch self {
        case .evidenceToConclusion: return "evidence to a conclusion"
        case .problemToNextStep: return "a problem to a next step"
        case .questionToAnswer: return "a question to an answer"
        case .questionsToAnswer: return "questions to an answer"
        case .stepsToNextAction: return "steps to a next action"
        case .optionsToRecommendation: return "options to a recommendation"
        case .causeToAction: return "a cause to an action"
        case .contrastToRecommendation: return "a contrast to a recommendation"
        case .goalToPlan: return "a goal to a plan"
        case .conditionToAdvice: return "a condition to advice"
        case .claimToSupport: return "a claim to support"
        case .uncertaintyToCaution: return "uncertainty to caution"
        }
    }
}

struct HWKLearnedParagraphPlan: Equatable, Sendable {
    let position: HWKLearnedParagraphPosition
    let previousSentenceRole: String
    let intent: HWKLearnedParagraphIntent?
}

struct HWKLearnedPhraseSuggestion: Equatable, Sendable {
    let replacement: String
    let sourceText: String
    let observationCount: Int
    let contextWordCount: Int
    let relationship: HWKLearnedPhraseRelationship?
    let paragraphPlan: HWKLearnedParagraphPlan?
    let paragraphPlanFeedbackFingerprint: UInt64?
    let paragraphPlanNegativeFeedbackCount: Int
    let rationaleLabel: String?
    let explanation: String
}

/// Local, bounded phrase memory. It learns repeatedly typed continuations and
/// survives keyboard/app restarts. Typed text never leaves the App Group.
struct HWKPersistentPhraseLearner: @unchecked Sendable {
    static let maximumEntries = 384
    static let maximumEncodedBytes = 96 * 1_024
    static let minimumObservationCount = 2
    private static let emergingEntryReserve = 64
    private static let maximumDistinctGeneralizedContexts = 16
    private static let maximumParagraphPlanFeedbackReceipts = 16
    private static let paragraphPlanForgettingThreshold = 3
    private static let paragraphPlanRelearningEvidence = 2
    private static let paragraphPlanConflictMargin = 2
    private static let relationshipContextPrefix = "relationship|"
    private static let paragraphPlanContextPrefix = "paragraphPlan|"
    private static let englishParagraphStarterStopwords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "because", "but", "by",
        "for", "from", "had", "has", "have", "he", "her", "his", "i", "if",
        "in", "is", "it", "its", "of", "on", "or", "our", "she", "so", "that",
        "the", "their", "them", "then", "they", "this", "to", "was", "we", "were",
        "will", "with", "you", "your",
    ]
    private static let englishCodeStarterKeywords: Set<String> = [
        "class", "enum", "extension", "func", "import", "let", "protocol",
        "struct", "var",
    ]
    private static let englishEvidenceIntentWords: Set<String> = [
        "analysis", "audit", "audits", "calibration", "confirmed", "confirms",
        "data", "demonstrated", "evidence", "experiment", "experiments", "finding",
        "findings", "measurement", "measurements", "observed", "readings", "result",
        "results", "review", "reviewers", "sample", "samples", "sensor", "sensors",
        "study", "studies", "test", "tests", "trial", "trials", "verified",
    ]
    private static let englishProblemIntentWords: Set<String> = [
        "blocked", "broken", "bug", "bugs", "crash", "crashed", "crashes", "defect",
        "defects", "error", "errors", "failed", "failure", "failures", "issue",
        "issues", "missing", "prevented", "problem", "problems", "regression",
        "regressions", "risk", "risks", "stopped", "unsafe", "unstable",
    ]
    private static let englishStepOpeningIntentWords: Set<String> = [
        "begin", "first", "firstly", "initially", "start",
    ]
    private static let englishStepContinuationIntentWords: Set<String> = [
        "afterward", "afterwards", "finally", "next", "second", "secondly",
        "subsequently", "then", "third", "thirdly",
    ]
    private static let englishOptionIntentWords: Set<String> = [
        "alternative", "alternatives", "choice", "choices", "option", "options",
    ]
    private static let englishCauseSetupIntentWords: Set<String> = [
        "because", "caused", "causes", "causing", "due",
    ]
    private static let englishConsequenceIntentWords: Set<String> = [
        "consequently", "hence", "therefore", "thus",
    ]
    private static let englishContrastSetupIntentWords: Set<String> = [
        "although", "despite", "though", "whereas",
    ]
    private static let englishContrastResolutionIntentWords: Set<String> = [
        "however", "instead", "nevertheless", "yet",
    ]
    private static let englishGoalSetupIntentWords: Set<String> = [
        "aim", "aims", "goal", "goals", "objective", "objectives",
    ]
    private static let englishGoalCommitmentIntentWords: Set<String> = [
        "hope", "hopes", "intend", "intends", "want", "wants",
    ]
    private static let englishConditionSetupIntentWords: Set<String> = [
        "if", "provided", "when", "whenever",
    ]
    private static let englishConditionAdviceIntentWords: Set<String> = [
        "otherwise", "provided", "unless",
    ]
    private static let englishClaimSetupIntentWords: Set<String> = [
        "assertion", "claim", "claims", "position", "thesis",
    ]
    private static let englishClaimSupportIntentWords: Set<String> = [
        "example", "examples", "illustrates", "illustration", "support", "supports",
    ]
    private static let englishUncertaintySetupIntentWords: Set<String> = [
        "could", "may", "might", "uncertain", "unclear",
    ]
    private static let englishUncertaintyCautionIntentWords: Set<String> = [
        "maybe", "perhaps", "possibly", "uncertain", "unclear",
    ]
    private static let englishAnswerTargetWords: Set<String> = [
        "answer", "answers", "reply", "response", "solution",
    ]
    private static let englishNextActionTargetWords: Set<String> = [
        "action", "continue", "continues", "finally", "move", "next", "proceed",
        "step", "then",
    ]
    private static let englishRecommendationTargetWords: Set<String> = [
        "best", "choice", "choose", "prefer", "preferred", "recommend",
        "recommendation", "recommended", "select",
    ]
    private static let englishResponseTargetWords: Set<String> = [
        "response", "responses",
    ]
    private static let englishPlanTargetWords: Set<String> = [
        "advice", "approach", "plan", "plans", "strategy",
    ]
    private static let englishNoteTargetWords: Set<String> = [
        "caution", "cautious", "note", "support", "supporting",
    ]

    private static let englishRelationshipConnectors: [String: HWKLearnedPhraseRelationship] = [
        "although": .contrast,
        "but": .contrast,
        "however": .contrast,
        "instead": .contrast,
        "nevertheless": .contrast,
        "yet": .contrast,
        "consequently": .consequence,
        "so": .consequence,
        "therefore": .consequence,
        "thus": .consequence,
        "because": .cause,
        "since": .cause,
        "if": .condition,
        "otherwise": .condition,
        "unless": .condition,
        "additionally": .addition,
        "also": .addition,
        "furthermore": .addition,
        "moreover": .addition,
        "finally": .sequence,
        "meanwhile": .sequence,
        "next": .sequence,
        "then": .sequence,
    ]
    private static let englishMultiwordRelationshipConnectors: [RelationshipConnectorDefinition] = [
        RelationshipConnectorDefinition(phrase: "on the other hand", relationship: .contrast),
        RelationshipConnectorDefinition(phrase: "for that reason", relationship: .consequence),
        RelationshipConnectorDefinition(phrase: "because of that", relationship: .consequence),
        RelationshipConnectorDefinition(phrase: "as a result", relationship: .consequence),
        RelationshipConnectorDefinition(phrase: "in that case", relationship: .condition),
        RelationshipConnectorDefinition(phrase: "in addition", relationship: .addition),
        RelationshipConnectorDefinition(phrase: "after that", relationship: .sequence),
        RelationshipConnectorDefinition(phrase: "even so", relationship: .contrast),
    ]

    private static let storageKey = "keyboard.languageBrain.phrases.v1"
    private static let lock = NSLock()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.observations.count <= Self.maximumEntries,
              Set(envelope.observations.map(\.id)).count == envelope.observations.count else {
            return false
        }
        return envelope.observations.allSatisfy { observation in
            let generalizedEvidenceIsValid: Bool
            if observation.contextKey.hasPrefix(Self.relationshipContextPrefix) {
                let fingerprints = observation.evidenceFingerprints ?? []
                generalizedEvidenceIsValid = !fingerprints.isEmpty
                    && fingerprints.count <= Self.maximumDistinctGeneralizedContexts
                    && Set(fingerprints).count == fingerprints.count
                    && observation.count == fingerprints.count
                    && observation.paragraphIntent == nil
                    && Self.relationship(from: observation.contextKey) != nil
            } else if observation.contextKey.hasPrefix(Self.paragraphPlanContextPrefix) {
                let fingerprints = observation.evidenceFingerprints ?? []
                generalizedEvidenceIsValid = !fingerprints.isEmpty
                    && fingerprints.count <= Self.maximumDistinctGeneralizedContexts
                    && Set(fingerprints).count == fingerprints.count
                    && observation.count == fingerprints.count
                    && Self.paragraphPlanObservationIsValid(observation)
            } else {
                generalizedEvidenceIsValid = observation.evidenceFingerprints == nil
                    && observation.paragraphIntent == nil
            }
            let paragraphPlanFeedbackIsValid = Self.paragraphPlanFeedbackIsValid(
                observation
            )
            return !observation.language.isEmpty
                && observation.language.count <= 32
                && !observation.contextKey.isEmpty
                && observation.contextKey.count <= 128
                && !observation.continuationKey.isEmpty
                && observation.continuationKey.count <= 192
                && !observation.continuation.isEmpty
                && observation.continuation.count <= 192
                && (1...10_000).contains(observation.count)
                && observation.lastSeen.timeIntervalSince1970.isFinite
                && generalizedEvidenceIsValid
                && paragraphPlanFeedbackIsValid
        }
    }

    @discardableResult
    func recordCommittedContext(_ context: String, language: String) -> Bool {
        let languageKey = Self.normalizedLanguage(language)
        guard Self.isEligible(context),
              Self.hasPlausibleEnglishAgreement(context),
              languageKey != "en" || !Self.hasUnsafeEnglishFinalSentenceStarter(in: context) else {
            return false
        }

        let now = Date()
        var observations = [Observation]()

        let crossSentence = Self.crossSentenceObservations(
            in: context,
            language: languageKey,
            now: now
        )
        observations.append(contentsOf: crossSentence)
        observations.append(contentsOf: Self.paragraphPlanObservations(
            in: context,
            language: languageKey,
            now: now
        ))

        if let tokens = Self.trailingTokens(in: context), tokens.count >= 3 {
            for splitIndex in 1..<(tokens.count - 1) {
                let continuationCount = tokens.count - splitIndex
                guard (2...4).contains(continuationCount) else { continue }

                let continuationTokens = Array(tokens[splitIndex...])
                let normalizedContinuation = continuationTokens.map(\.normalized).joined(separator: " ")
                let surfaceContinuation = continuationTokens.map(\.surface).joined(separator: " ")

                for contextWordCount in 1...min(3, splitIndex) {
                    let contextStart = splitIndex - contextWordCount
                    let contextKey = tokens[contextStart..<splitIndex]
                        .map(\.normalized)
                        .joined(separator: " ")
                    observations.append(
                        Observation(
                            language: languageKey,
                            contextKey: contextKey,
                            continuationKey: normalizedContinuation,
                            continuation: surfaceContinuation,
                            count: 1,
                            lastSeen: now
                        )
                    )
                }
            }
        }

        guard !observations.isEmpty else { return false }

        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.learnedPhrases]
        ) {
            Self.lock.lock()
            defer { Self.lock.unlock() }

            var stored = Dictionary(uniqueKeysWithValues: loadUnlocked().map { ($0.id, $0) })
            for observation in observations {
                if var existing = stored[observation.id] {
                    if let newFingerprints = observation.evidenceFingerprints {
                        var fingerprints = existing.evidenceFingerprints ?? []
                        var addedDistinctEvidence = false
                        for fingerprint in newFingerprints where !fingerprints.contains(fingerprint) {
                            fingerprints.append(fingerprint)
                            addedDistinctEvidence = true
                        }
                        if fingerprints.count > Self.maximumDistinctGeneralizedContexts {
                            fingerprints.removeFirst(
                                fingerprints.count - Self.maximumDistinctGeneralizedContexts
                            )
                        }
                        existing.evidenceFingerprints = fingerprints
                        existing.count = fingerprints.count
                        if addedDistinctEvidence,
                           existing.paragraphPlanNegativeFeedbackCount != nil {
                            let recoveryEvidenceCount = min(
                                Self.paragraphPlanRelearningEvidence,
                                (existing.paragraphPlanRecoveryEvidenceCount ?? 0) + 1
                            )
                            if recoveryEvidenceCount
                                >= Self.paragraphPlanRelearningEvidence {
                                existing.paragraphPlanNegativeFeedbackCount = nil
                                existing.paragraphPlanRecoveryBaselineCount = nil
                                existing.paragraphPlanRecoveryEvidenceCount = nil
                            } else {
                                existing.paragraphPlanRecoveryEvidenceCount =
                                    recoveryEvidenceCount
                            }
                        }
                    } else {
                        existing.count = min(10_000, existing.count + 1)
                    }
                    existing.continuation = observation.continuation
                    existing.lastSeen = now
                    stored[observation.id] = existing
                } else {
                    stored[observation.id] = observation
                }
            }
            return persistUnlocked(Array(stored.values))
        }
        return result.value ?? false
    }

    func suggestions(
        for context: String,
        language: String,
        limit: Int
    ) -> [HWKLearnedPhraseSuggestion] {
        let languageKey = Self.normalizedLanguage(language)
        guard limit > 0,
              Self.isEligibleQuery(context),
              let query = Self.query(
                in: context,
                includeEnglishRelationships: languageKey == "en"
              ),
              !query.contextKeys.isEmpty else {
            return []
        }

        Self.lock.lock()
        let stored = loadUnlocked()
        Self.lock.unlock()

        let candidates = stored.compactMap { observation -> RankedSuggestion? in
            guard observation.language == languageKey,
                  let contextRank = query.contextKeys.firstIndex(of: observation.contextKey) else {
                return nil
            }
            let relationship = Self.relationship(from: observation.contextKey)
            let paragraphPlan = Self.paragraphPlan(
                from: observation.contextKey,
                intent: observation.paragraphIntent
            )
            guard paragraphPlan == nil
                    || paragraphPlan?.intent == query.paragraphIntent else {
                return nil
            }
            let isGeneralized = relationship != nil || paragraphPlan != nil
            let paragraphPlanNegativeFeedbackCount = paragraphPlan == nil
                ? 0
                : observation.paragraphPlanNegativeFeedbackCount ?? 0
            guard paragraphPlanNegativeFeedbackCount
                    < Self.paragraphPlanForgettingThreshold else {
                return nil
            }
            let requiredEvidence = isGeneralized
                ? 3
                : (contextRank == 0 ? Self.minimumObservationCount : 3)
            guard observation.count >= requiredEvidence else { return nil }
            let replacement: String
            let sourceText: String
            if let partialPrefix = query.partialRelationshipPrefix,
               let relationship {
                guard partialPrefix.relationships.contains(relationship),
                      let partialReplacement = Self.partialRelationshipReplacement(
                        observation.continuation,
                        for: partialPrefix
                      ) else {
                    return nil
                }
                replacement = partialReplacement
                sourceText = partialPrefix.sourceText
            } else {
                guard let firstWord = observation.continuationKey.split(separator: " ").first,
                      query.sourceText.isEmpty || firstWord.hasPrefix(query.sourceText.lowercased()) else {
                    return nil
                }
                replacement = observation.continuation
                sourceText = query.sourceText
            }
            let rationaleLabel: String?
            if let relationship {
                rationaleLabel = "\(relationship.shortLabel) · \(observation.count) contexts"
            } else if let paragraphPlan {
                let label = paragraphPlan.intent?.shortLabel ?? "paragraph pattern"
                rationaleLabel = paragraphPlanNegativeFeedbackCount > 0
                    ? "\(label) · cautious"
                    : "\(label) · \(observation.count) contexts"
            } else {
                rationaleLabel = nil
            }
            let confidenceCount = paragraphPlan == nil
                ? observation.count
                : max(
                    requiredEvidence,
                    observation.count - paragraphPlanNegativeFeedbackCount
                )
            return RankedSuggestion(
                suggestion: HWKLearnedPhraseSuggestion(
                    replacement: replacement,
                    sourceText: sourceText,
                    observationCount: observation.count,
                    contextWordCount: isGeneralized
                        ? 0
                        : observation.contextKey.split(separator: " ").count,
                    relationship: relationship,
                    paragraphPlan: paragraphPlan,
                    paragraphPlanFeedbackFingerprint: paragraphPlan.map { _ in
                        HWKAutobotEpisodeFingerprint.paragraphPlanFeedbackIdentity(
                            language: observation.language,
                            contextKey: observation.contextKey,
                            continuationKey: observation.continuationKey,
                            paragraphIntent: observation.paragraphIntent?.rawValue
                        )
                    },
                    paragraphPlanNegativeFeedbackCount:
                        paragraphPlanNegativeFeedbackCount,
                    rationaleLabel: rationaleLabel,
                    explanation: Self.explanation(
                        for: observation,
                        relationship: relationship,
                        paragraphPlan: paragraphPlan,
                        paragraphPlanNegativeFeedbackCount:
                            paragraphPlanNegativeFeedbackCount
                    )
                ),
                confidenceCount: confidenceCount,
                contextRank: contextRank,
                continuationWordCount: observation.continuationKey.split(separator: " ").count,
                lastSeen: observation.lastSeen
            )
        }
        let matching = Self.resolvingParagraphPlanConflict(in: candidates).sorted {
            let lhsGeneralizationRank = Self.generalizationRank(for: $0.suggestion)
            let rhsGeneralizationRank = Self.generalizationRank(for: $1.suggestion)
            if lhsGeneralizationRank != rhsGeneralizationRank {
                return lhsGeneralizationRank < rhsGeneralizationRank
            }
            if lhsGeneralizationRank == 0, $0.contextRank != $1.contextRank {
                return $0.contextRank < $1.contextRank
            }
            if $0.confidenceCount != $1.confidenceCount {
                return $0.confidenceCount > $1.confidenceCount
            }
            if $0.contextRank != $1.contextRank { return $0.contextRank < $1.contextRank }
            if $0.continuationWordCount != $1.continuationWordCount {
                return $0.continuationWordCount > $1.continuationWordCount
            }
            return $0.lastSeen > $1.lastSeen
        }

        var seen = Set<String>()
        return matching.compactMap { ranked in
            let key = ranked.suggestion.replacement.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return ranked.suggestion
        }
        .prefix(limit)
        .map { $0 }
    }

    @discardableResult
    func reconcileParagraphPlanFeedback(
        _ snapshot: HWKAutobotTypingEpisodeSnapshot
    ) -> Bool {
        let feedback = snapshot.episodes.compactMap { episode
            -> (episode: HWKAutobotTypingEpisode,
                candidate: HWKAutobotEpisodeCandidate,
                episodeFingerprint: UInt64)? in
            guard episode.language == .english,
                  episode.finalOutcome == .undo
                    || episode.finalOutcome == .backspace
                    || episode.finalOutcome == .retype,
                  let resolvedCandidateID = episode.resolvedCandidateID,
                  let candidate = episode.candidates.first(where: {
                      $0.id == resolvedCandidateID
                  }),
                  candidate.paragraphPlanFingerprint != nil else {
                return nil
            }
            return (
                episode,
                candidate,
                HWKAutobotEpisodeFingerprint.paragraphPlanFeedbackEpisode(
                    episode.id
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.episode.updatedAtMilliseconds
                != rhs.episode.updatedAtMilliseconds {
                return lhs.episode.updatedAtMilliseconds
                    < rhs.episode.updatedAtMilliseconds
            }
            return lhs.episodeFingerprint < rhs.episodeFingerprint
        }
        guard !feedback.isEmpty else { return false }

        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.learnedPhrases]
        ) {
            Self.lock.lock()
            defer { Self.lock.unlock() }

            var stored = loadUnlocked()
            var changed = false
            for item in feedback {
                guard let planFingerprint = item.candidate.paragraphPlanFingerprint else {
                    continue
                }
                let exactIndexes = stored.indices.filter { index in
                    let observation = stored[index]
                    return Self.paragraphPlan(
                        from: observation.contextKey,
                        intent: observation.paragraphIntent
                    ) != nil
                        && HWKAutobotEpisodeFingerprint.paragraphPlanFeedbackIdentity(
                            language: observation.language,
                            contextKey: observation.contextKey,
                            continuationKey: observation.continuationKey,
                            paragraphIntent: observation.paragraphIntent?.rawValue
                        ) == planFingerprint
                }
                guard exactIndexes.count == 1,
                      let exactIndex = exactIndexes.first else {
                    continue
                }
                let exact = stored[exactIndex]
                if let cursorTimestamp = exact.paragraphPlanFeedbackCursorTimestampMilliseconds,
                   let cursorFingerprint = exact.paragraphPlanFeedbackCursorEpisodeFingerprint,
                   item.episode.updatedAtMilliseconds < cursorTimestamp
                    || item.episode.updatedAtMilliseconds == cursorTimestamp
                        && item.episodeFingerprint <= cursorFingerprint {
                    continue
                }

                let exactWords = Self.normalizedPlanWords(exact.continuationKey)
                let familyIndexes = stored.indices.filter { index in
                    let observation = stored[index]
                    guard observation.language == exact.language,
                          observation.contextKey == exact.contextKey,
                          observation.paragraphIntent == exact.paragraphIntent,
                          Self.paragraphPlan(
                              from: observation.contextKey,
                              intent: observation.paragraphIntent
                          ) != nil else {
                        return false
                    }
                    let words = Self.normalizedPlanWords(observation.continuationKey)
                    return Self.isWordPrefix(words, of: exactWords)
                        || Self.isWordPrefix(exactWords, of: words)
                }
                let episodeWasAlreadyCounted = exact
                    .paragraphPlanSeenFeedbackEpisodeFingerprints?
                    .contains(item.episodeFingerprint) ?? false
                for index in familyIndexes {
                    var observation = stored[index]
                    observation.paragraphPlanFeedbackCursorTimestampMilliseconds =
                        item.episode.updatedAtMilliseconds
                    observation.paragraphPlanFeedbackCursorEpisodeFingerprint =
                        item.episodeFingerprint
                    var seen = observation
                        .paragraphPlanSeenFeedbackEpisodeFingerprints ?? []
                    if !seen.contains(item.episodeFingerprint) {
                        seen.append(item.episodeFingerprint)
                        if seen.count > Self.maximumParagraphPlanFeedbackReceipts {
                            seen.removeFirst(
                                seen.count - Self.maximumParagraphPlanFeedbackReceipts
                            )
                        }
                        observation.paragraphPlanSeenFeedbackEpisodeFingerprints = seen
                    }
                    if !episodeWasAlreadyCounted {
                        observation.paragraphPlanNegativeFeedbackCount = min(
                            Self.paragraphPlanForgettingThreshold,
                            (observation.paragraphPlanNegativeFeedbackCount ?? 0) + 1
                        )
                        observation.paragraphPlanRecoveryBaselineCount = observation.count
                        observation.paragraphPlanRecoveryEvidenceCount = 0
                    }
                    if observation != stored[index] {
                        stored[index] = observation
                        changed = true
                    }
                }
            }
            guard changed else { return false }
            return persistUnlocked(stored)
        }
        return result.value ?? false
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.learnedPhrases]
        ) {
            Self.lock.lock()
            defaults.removeObject(forKey: Self.storageKey)
            Self.lock.unlock()
        }
    }

    private func loadUnlocked() -> [Observation] {
        guard let data = defaults.data(forKey: Self.storageKey),
              Self.isValidPersistedData(data),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.observations.count <= Self.maximumEntries else {
            return []
        }
        return envelope.observations
    }

    private func persistUnlocked(_ observations: [Observation]) -> Bool {
        let learned = observations
            .filter { $0.count >= Self.minimumObservationCount }
            .sorted(by: Self.strongerObservation)
        var emerging = observations
            .filter { $0.count < Self.minimumObservationCount }
            .sorted { $0.lastSeen > $1.lastSeen }
        if emerging.count > Self.emergingEntryReserve {
            emerging = Array(emerging.prefix(Self.emergingEntryReserve))
        }

        let reservedLearnedCapacity = Self.maximumEntries - Self.emergingEntryReserve
        var retainedLearned = Array(learned.prefix(reservedLearnedCapacity))
        let unusedCapacity = Self.maximumEntries - retainedLearned.count - emerging.count
        if unusedCapacity > 0 {
            retainedLearned.append(
                contentsOf: learned.dropFirst(reservedLearnedCapacity).prefix(unusedCapacity)
            )
        }

        while !retainedLearned.isEmpty || !emerging.isEmpty {
            let bounded = retainedLearned + emerging
            guard let data = try? JSONEncoder().encode(Envelope(version: 1, observations: bounded)) else {
                return false
            }
            if data.count <= Self.maximumEncodedBytes {
                defaults.set(data, forKey: Self.storageKey)
                return true
            }
            if !retainedLearned.isEmpty {
                retainedLearned.removeLast()
            } else {
                emerging.removeLast()
            }
        }
        return false
    }

    private static func strongerObservation(_ lhs: Observation, _ rhs: Observation) -> Bool {
        if lhs.count != rhs.count { return lhs.count > rhs.count }
        return lhs.lastSeen > rhs.lastSeen
    }

    private static func generalizationRank(for suggestion: HWKLearnedPhraseSuggestion) -> Int {
        if suggestion.relationship != nil { return 1 }
        if suggestion.paragraphPlan != nil { return 2 }
        return 0
    }

    private static func resolvingParagraphPlanConflict(
        in candidates: [RankedSuggestion]
    ) -> [RankedSuggestion] {
        let plans = candidates.filter { $0.suggestion.paragraphPlan != nil }
        guard plans.count > 1 else { return candidates }

        let anchors = plans.filter { candidate in
            let candidateWords = normalizedPlanWords(candidate.suggestion.replacement)
            return !plans.contains { other in
                let otherWords = normalizedPlanWords(other.suggestion.replacement)
                return candidateWords != otherWords
                    && isWordPrefix(candidateWords, of: otherWords)
            }
        }
        let anchorWordLists = anchors.map {
            normalizedPlanWords($0.suggestion.replacement)
        }
        func anchorIndexes(for candidate: RankedSuggestion) -> [Int] {
            let candidateWords = normalizedPlanWords(candidate.suggestion.replacement)
            return anchorWordLists.indices.filter { index in
                let anchorWords = anchorWordLists[index]
                return isWordPrefix(candidateWords, of: anchorWords)
                    || isWordPrefix(anchorWords, of: candidateWords)
            }
        }

        let families = anchors.enumerated().compactMap { index, anchor -> ParagraphPlanFamily? in
            let anchorWords = normalizedPlanWords(anchor.suggestion.replacement)
            let members = plans.filter { candidate in
                let candidateWords = normalizedPlanWords(candidate.suggestion.replacement)
                return isWordPrefix(candidateWords, of: anchorWords)
                    || isWordPrefix(anchorWords, of: candidateWords)
            }
            let exclusiveMembers = members.filter {
                anchorIndexes(for: $0) == [index]
            }
            guard let strongest = exclusiveMembers
                .sorted(by: paragraphPlanCandidatePreferred)
                .first else {
                return nil
            }
            return ParagraphPlanFamily(
                anchor: anchor,
                members: members,
                strongest: strongest
            )
        }
        .sorted { lhs, rhs in
            if lhs.strongest.confidenceCount != rhs.strongest.confidenceCount {
                return lhs.strongest.confidenceCount
                    > rhs.strongest.confidenceCount
            }
            if lhs.strongest.continuationWordCount != rhs.strongest.continuationWordCount {
                return lhs.strongest.continuationWordCount
                    > rhs.strongest.continuationWordCount
            }
            return lhs.strongest.suggestion.replacement.lowercased()
                < rhs.strongest.suggestion.replacement.lowercased()
        }
        guard let winner = families.first else { return candidates }
        guard families.count > 1 else { return candidates }
        let runnerUp = families[1]
        let lead = winner.strongest.confidenceCount
            - runnerUp.strongest.confidenceCount
        guard lead >= paragraphPlanConflictMargin else {
            let sharedReplacements = Set(plans.filter {
                anchorIndexes(for: $0).count > 1
            }.map {
                $0.suggestion.replacement.lowercased()
            })
            return candidates.filter { candidate in
                candidate.suggestion.paragraphPlan == nil
                    || sharedReplacements.contains(
                        candidate.suggestion.replacement.lowercased()
                    )
            }
        }

        let winningReplacements = Set(winner.members.map {
            $0.suggestion.replacement.lowercased()
        })
        return candidates.filter { candidate in
            candidate.suggestion.paragraphPlan == nil
                || winningReplacements.contains(candidate.suggestion.replacement.lowercased())
        }
    }

    private static func paragraphPlanCandidatePreferred(
        _ lhs: RankedSuggestion,
        _ rhs: RankedSuggestion
    ) -> Bool {
        if lhs.confidenceCount != rhs.confidenceCount {
            return lhs.confidenceCount > rhs.confidenceCount
        }
        if lhs.continuationWordCount != rhs.continuationWordCount {
            return lhs.continuationWordCount > rhs.continuationWordCount
        }
        return lhs.suggestion.replacement.lowercased()
            < rhs.suggestion.replacement.lowercased()
    }

    private static func normalizedPlanWords(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func isWordPrefix(_ prefix: [String], of words: [String]) -> Bool {
        guard !prefix.isEmpty, prefix.count <= words.count else { return false }
        return zip(prefix, words).allSatisfy(==)
    }

    private static func normalizedLanguage(_ language: String) -> String {
        language
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() ?? "und"
    }

    private static func isEligible(_ context: String) -> Bool {
        guard !context.isEmpty,
              context.count <= 1_500,
              !context.contains("@"),
              !context.localizedCaseInsensitiveContains("://") else {
            return false
        }
        return !context.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
        }
    }

    private static func isEligibleQuery(_ context: String) -> Bool {
        !context.isEmpty
            && context.count <= 1_500
            && !context.contains("@")
            && !context.localizedCaseInsensitiveContains("://")
            && !context.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
                    && $0 != "\n" && $0 != "\r" && $0 != "\t"
            }
    }

    private static func hasPlausibleEnglishAgreement(_ context: String) -> Bool {
        let words = context.lowercased().split { !$0.isLetter }.map(String.init)
        guard !words.isEmpty else { return false }
        let forbiddenPairs: Set<String> = [
            "i is", "you is", "we is", "they is",
            "he are", "she are", "it are",
        ]
        for index in 1..<words.count {
            if words[index] == words[index - 1] { return false }
            if forbiddenPairs.contains(words[index - 1] + " " + words[index]) { return false }
        }
        return true
    }

    private static func hasUnsafeEnglishFinalSentenceStarter(in context: String) -> Bool {
        guard let finalSentence = completedSentences(in: currentParagraph(in: context)).last,
              let rawFirstChunk = finalSentence.body.split(whereSeparator: \.isWhitespace).first else {
            return false
        }
        if rawFirstChunk.contains(where: \.isNumber) { return true }
        guard let firstToken = token(rawFirstChunk) else { return false }
        return englishCodeStarterKeywords.contains(firstToken.normalized)
    }

    private static func crossSentenceObservations(
        in context: String,
        language: String,
        now: Date
    ) -> [Observation] {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let finalPunctuation = trimmed.last,
              finalPunctuation == "." || finalPunctuation == "!" || finalPunctuation == "?" else {
            return []
        }
        let withoutFinal = trimmed.dropLast()
        guard let priorBoundary = withoutFinal.lastIndex(where: {
            $0 == "." || $0 == "!" || $0 == "?"
        }) else { return [] }

        let previousSentence = withoutFinal[..<priorBoundary]
        let discourseRole = sentenceRole(for: withoutFinal[priorBoundary])
        let continuationStart = withoutFinal.index(after: priorBoundary)
        let continuationBody = withoutFinal[continuationStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let previousTokens = trailingTokens(in: String(previousSentence)),
              previousTokens.count >= 3 else { return [] }
        let continuationTokens = continuationBody.split(whereSeparator: \.isWhitespace).compactMap(token)
        guard (2...20).contains(continuationTokens.count) else { return [] }

        let maximumContextWords = min(6, previousTokens.count)
        var observations = (3...maximumContextWords).map { count in
            Observation(
                language: language,
                contextKey: discourseRole + "|" + previousTokens.suffix(count).map(\.normalized).joined(separator: " "),
                continuationKey: continuationTokens.map(\.normalized).joined(separator: " "),
                continuation: continuationBody + String(finalPunctuation),
                count: 1,
                lastSeen: now
            )
        }
        if language == "en",
           let connector = relationshipConnector(in: continuationBody) {
            let evidenceText = discourseRole + "|" + previousTokens
                .suffix(maximumContextWords)
                .map(\.normalized)
                .joined(separator: " ")
            observations.append(Observation(
                language: language,
                contextKey: relationshipContextKey(
                    discourseRole: discourseRole,
                    relationship: connector.relationship
                ),
                continuationKey: connector.surface.lowercased(),
                continuation: connector.surface,
                count: 1,
                lastSeen: now,
                evidenceFingerprints: [HWKAutobotEpisodeFingerprint.token(evidenceText)]
            ))
        }
        return observations
    }

    private static func paragraphPlanObservations(
        in context: String,
        language: String,
        now: Date
    ) -> [Observation] {
        guard language == "en" else { return [] }
        let paragraph = currentParagraph(in: context)
        guard hasOnlyLatinScriptLetters(paragraph) else { return [] }
        let sentences = completedSentences(in: paragraph)
        guard sentences.count >= 2,
              let target = sentences.last,
              relationshipConnector(in: target.body) == nil else {
            return []
        }

        let rawChunks = target.body.split(whereSeparator: \.isWhitespace)
        guard rawChunks.count >= 7 else { return [] }
        let maximumStarterWords = min(6, rawChunks.count - 2)
        guard maximumStarterWords >= 3 else { return [] }

        let position = paragraphPosition(forSentenceNumber: sentences.count)
        let previousSentenceRole = sentenceRole(for: sentences[sentences.count - 2].punctuation)
        let intentResolution = paragraphIntentResolution(for: sentences.dropLast())
        guard !intentResolution.isConflicted else { return [] }
        let paragraphIntent = intentResolution.intent
        guard paragraphIntent.map({ paragraphTargetSupports(intent: $0, target: target) }) != false else {
            return []
        }
        let openingTokens = sentences[0].body
            .split(whereSeparator: \.isWhitespace)
            .compactMap(token)
        guard openingTokens.count >= 3 else { return [] }
        let paragraphEvidence = openingTokens.map(\.normalized).joined(separator: " ")
        let evidenceFingerprint = HWKAutobotEpisodeFingerprint.paragraphPlanEvidence(
            paragraphPlanContextPrefix
                + position.rawValue + "|"
                + previousSentenceRole + "|"
                + (paragraphIntent?.rawValue ?? "structural") + "|"
                + paragraphEvidence
        )
        let contextKey = paragraphPlanContextKey(
            position: position,
            previousSentenceRole: previousSentenceRole
        )

        return (3...maximumStarterWords).compactMap { wordCount in
            let starterTokens = rawChunks.prefix(wordCount).compactMap(token)
            guard starterTokens.count == wordCount,
                  let first = starterTokens.first,
                  !englishCodeStarterKeywords.contains(first.normalized),
                  starterTokens.contains(where: {
                      $0.normalized.count >= 4
                          && !englishParagraphStarterStopwords.contains($0.normalized)
                  }) else {
                return nil
            }
            let continuation = starterTokens.map(\.surface).joined(separator: " ")
            guard continuation.count <= 64 else { return nil }
            return Observation(
                language: language,
                contextKey: contextKey,
                continuationKey: starterTokens.map(\.normalized).joined(separator: " "),
                continuation: continuation,
                count: 1,
                lastSeen: now,
                evidenceFingerprints: [evidenceFingerprint],
                paragraphIntent: paragraphIntent
            )
        }
    }

    private static func currentParagraph(in context: String) -> String {
        let normalized = context
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard let boundary = normalized.range(of: "\n\n", options: .backwards) else {
            return normalized
        }
        return String(normalized[boundary.upperBound...])
    }

    private static func completedSentences(in paragraph: String) -> [CompletedSentence] {
        var sentences = [CompletedSentence]()
        var sentenceStart = paragraph.startIndex
        var index = paragraph.startIndex
        while index < paragraph.endIndex {
            let punctuation = paragraph[index]
            guard punctuation == "." || punctuation == "!" || punctuation == "?" else {
                index = paragraph.index(after: index)
                continue
            }
            let next = paragraph.index(after: index)
            guard next == paragraph.endIndex || paragraph[next].isWhitespace else {
                index = next
                continue
            }
            let body = paragraph[sentenceStart..<index]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let wordCount = body.split(whereSeparator: \.isWhitespace).compactMap(token).count
            guard wordCount >= 3 else {
                index = next
                continue
            }
            sentences.append(CompletedSentence(body: body, punctuation: punctuation))
            sentenceStart = next
            index = next
        }
        return sentences
    }

    private static func paragraphPosition(
        forSentenceNumber sentenceNumber: Int
    ) -> HWKLearnedParagraphPosition {
        switch sentenceNumber {
        case 2: return .secondSentence
        case 3: return .thirdSentence
        default: return .laterSentence
        }
    }

    private enum ParagraphIntentResolution {
        case structural
        case semantic(HWKLearnedParagraphIntent)
        case conflicted

        var intent: HWKLearnedParagraphIntent? {
            guard case let .semantic(intent) = self else { return nil }
            return intent
        }

        var isConflicted: Bool {
            if case .conflicted = self { return true }
            return false
        }
    }

    private static func paragraphIntentResolution(
        for sentences: ArraySlice<CompletedSentence>
    ) -> ParagraphIntentResolution {
        let recent = Array(sentences.suffix(2))
        guard !recent.isEmpty else { return .structural }
        let wordSets = recent.map { sentence in
            Set(sentence.body.split(whereSeparator: \.isWhitespace).compactMap(token).map(\.normalized))
        }
        let stepOpeningOrContinuationWords = englishStepOpeningIntentWords
            .union(englishStepContinuationIntentWords)
        let competingCueWords = englishEvidenceIntentWords
            .union(englishProblemIntentWords)
            .union(stepOpeningOrContinuationWords)
            .union(englishOptionIntentWords)
            .union(englishCauseSetupIntentWords)
            .union(englishConsequenceIntentWords)
            .union(englishContrastSetupIntentWords)
            .union(englishContrastResolutionIntentWords)
            .union(englishGoalSetupIntentWords)
            .union(englishGoalCommitmentIntentWords)
            .union(englishConditionSetupIntentWords)
            .union(englishConditionAdviceIntentWords)
            .union(englishClaimSetupIntentWords)
            .union(englishClaimSupportIntentWords)
            .union(englishUncertaintySetupIntentWords)
            .union(englishUncertaintyCautionIntentWords)

        if recent.count == 1 {
            guard recent[0].punctuation == "?" else { return .structural }
            guard wordSets[0].isDisjoint(with: competingCueWords) else {
                return .conflicted
            }
            return .semantic(.questionToAnswer)
        }

        let evidenceSentenceCount = wordSets.filter {
            !$0.isDisjoint(with: englishEvidenceIntentWords)
        }.count
        let problemSentenceCount = wordSets.filter {
            !$0.isDisjoint(with: englishProblemIntentWords)
        }.count
        let firstStepMarkers = wordSets[0].intersection(stepOpeningOrContinuationWords)
        let secondStepMarkers = wordSets[1].intersection(englishStepContinuationIntentWords)
        let optionMarkers = wordSets.map { $0.intersection(englishOptionIntentWords) }
        let causeSetupMarkers = wordSets[0].intersection(englishCauseSetupIntentWords)
        let consequenceMarkers = wordSets[1].intersection(englishConsequenceIntentWords)
        let contrastSetupMarkers = wordSets[0].intersection(englishContrastSetupIntentWords)
        let contrastResolutionMarkers = wordSets[1].intersection(
            englishContrastResolutionIntentWords
        )
        let goalSetupMarkers = wordSets[0].intersection(englishGoalSetupIntentWords)
        let goalCommitmentMarkers = wordSets[1].intersection(
            englishGoalCommitmentIntentWords
        )
        let conditionSetupMarkers = wordSets[0].intersection(
            englishConditionSetupIntentWords
        )
        let conditionAdviceMarkers = wordSets[1].intersection(
            englishConditionAdviceIntentWords
        )
        let claimSetupMarkers = wordSets[0].intersection(englishClaimSetupIntentWords)
        let claimSupportMarkers = wordSets[1].intersection(englishClaimSupportIntentWords)
        let uncertaintySetupMarkers = wordSets[0].intersection(
            englishUncertaintySetupIntentWords
        )
        let uncertaintyCautionMarkers = wordSets[1].intersection(
            englishUncertaintyCautionIntentWords
        )

        var candidates = [HWKLearnedParagraphIntent]()
        if evidenceSentenceCount == 2 {
            candidates.append(.evidenceToConclusion)
        }
        if problemSentenceCount == 2 {
            candidates.append(.problemToNextStep)
        }
        if recent.allSatisfy({ $0.punctuation == "?" }),
           wordSets.allSatisfy({ $0.isDisjoint(with: competingCueWords) }) {
            candidates.append(.questionsToAnswer)
        }
        if !firstStepMarkers.isEmpty,
           !secondStepMarkers.isEmpty,
           firstStepMarkers.union(secondStepMarkers).count >= 2 {
            candidates.append(.stepsToNextAction)
        }
        if optionMarkers.allSatisfy({ !$0.isEmpty }),
           optionMarkers[0].union(optionMarkers[1]).count >= 2 {
            candidates.append(.optionsToRecommendation)
        }
        if !causeSetupMarkers.isEmpty, !consequenceMarkers.isEmpty {
            candidates.append(.causeToAction)
        }
        if !contrastSetupMarkers.isEmpty, !contrastResolutionMarkers.isEmpty {
            candidates.append(.contrastToRecommendation)
        }
        if !goalSetupMarkers.isEmpty, !goalCommitmentMarkers.isEmpty {
            candidates.append(.goalToPlan)
        }
        if !conditionSetupMarkers.isEmpty, !conditionAdviceMarkers.isEmpty {
            candidates.append(.conditionToAdvice)
        }
        if !claimSetupMarkers.isEmpty, !claimSupportMarkers.isEmpty {
            candidates.append(.claimToSupport)
        }
        if !uncertaintySetupMarkers.isEmpty, !uncertaintyCautionMarkers.isEmpty {
            candidates.append(.uncertaintyToCaution)
        }
        let hasAnyCauseCue = !causeSetupMarkers.isEmpty || !consequenceMarkers.isEmpty
        let hasAnyContrastCue = !contrastSetupMarkers.isEmpty || !contrastResolutionMarkers.isEmpty
        let hasAnyGoalCue = !goalSetupMarkers.isEmpty || !goalCommitmentMarkers.isEmpty
        let hasAnyConditionCue = !conditionSetupMarkers.isEmpty || !conditionAdviceMarkers.isEmpty
        let hasAnyClaimCue = !claimSetupMarkers.isEmpty || !claimSupportMarkers.isEmpty
        let hasAnyUncertaintyCue = !uncertaintySetupMarkers.isEmpty
            || !uncertaintyCautionMarkers.isEmpty
        if hasAnyCauseCue, hasAnyContrastCue { return .conflicted }
        if hasAnyGoalCue, hasAnyConditionCue { return .conflicted }
        if hasAnyClaimCue, hasAnyUncertaintyCue { return .conflicted }
        if candidates.count > 1 { return .conflicted }
        if let intent = candidates.first { return .semantic(intent) }

        let weakCueFamilies = [
            evidenceSentenceCount > 0,
            problemSentenceCount > 0,
            !firstStepMarkers.isEmpty || !secondStepMarkers.isEmpty,
            optionMarkers.contains(where: { !$0.isEmpty }),
            recent.contains(where: { $0.punctuation == "?" }),
            hasAnyCauseCue,
            hasAnyContrastCue,
            hasAnyGoalCue,
            hasAnyConditionCue,
            hasAnyClaimCue,
            hasAnyUncertaintyCue,
        ].filter { $0 }.count
        return weakCueFamilies > 1 ? .conflicted : .structural
    }

    private static func paragraphTargetSupports(
        intent: HWKLearnedParagraphIntent,
        target: CompletedSentence
    ) -> Bool {
        let targetWords = Set(target.body
            .split(whereSeparator: \.isWhitespace)
            .prefix(6)
            .compactMap(token)
            .map(\.normalized))
        switch intent {
        case .evidenceToConclusion, .problemToNextStep:
            return true
        case .questionToAnswer, .questionsToAnswer:
            return !targetWords.isDisjoint(with: englishAnswerTargetWords)
        case .stepsToNextAction:
            return !targetWords.isDisjoint(with: englishNextActionTargetWords)
        case .optionsToRecommendation:
            return !targetWords.isDisjoint(with: englishRecommendationTargetWords)
        case .causeToAction:
            return !targetWords.isDisjoint(
                with: englishNextActionTargetWords.union(englishResponseTargetWords)
            )
        case .contrastToRecommendation:
            return !targetWords.isDisjoint(
                with: englishRecommendationTargetWords.union(englishResponseTargetWords)
            )
        case .goalToPlan, .conditionToAdvice:
            return !targetWords.isDisjoint(with: englishPlanTargetWords)
        case .claimToSupport, .uncertaintyToCaution:
            return !targetWords.isDisjoint(with: englishNoteTargetWords)
        }
    }

    private static func paragraphPlanQuery(in context: String) -> HWKLearnedParagraphPlan? {
        let paragraph = currentParagraph(in: context)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasOnlyLatinScriptLetters(paragraph),
              let punctuation = paragraph.last,
              punctuation == "." || punctuation == "!" || punctuation == "?" else {
            return nil
        }
        let sentences = completedSentences(in: paragraph)
        guard let previous = sentences.last else { return nil }
        let intentResolution = paragraphIntentResolution(for: sentences[...])
        guard !intentResolution.isConflicted else { return nil }
        return HWKLearnedParagraphPlan(
            position: paragraphPosition(forSentenceNumber: sentences.count + 1),
            previousSentenceRole: sentenceRole(for: previous.punctuation),
            intent: intentResolution.intent
        )
    }

    private static func trailingTokens(in context: String) -> [Token]? {
        let tail: Substring
        if let boundary = context.lastIndex(where: { character in
            character == "." || character == "!" || character == "?" ||
                character == ";" || character == "\n" || character == "\r"
        }) {
            tail = context[context.index(after: boundary)...]
        } else {
            tail = context[...]
        }
        let tokens = tail.split(whereSeparator: \.isWhitespace).compactMap(token)
        return tokens.isEmpty ? nil : tokens
    }

    private static func query(
        in context: String,
        includeEnglishRelationships: Bool
    ) -> Query? {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let completedPunctuation = trimmed.last.flatMap { character in
            (character == "." || character == "!" || character == "?") ? character : nil
        }
        let completedSentenceBoundary = completedPunctuation != nil
        let partialRelationshipPrefix = includeEnglishRelationships
            ? partialRelationshipPrefix(in: context)
            : nil
        let relationshipPunctuation = completedPunctuation ?? partialRelationshipPrefix?.punctuation
        let queryContext: String
        if completedSentenceBoundary {
            queryContext = String(trimmed.dropLast())
        } else if let partialRelationshipPrefix {
            queryContext = partialRelationshipPrefix.contextBeforeBoundary
        } else {
            queryContext = context
        }
        guard let tokens = trailingTokens(in: queryContext) else { return nil }
        let endsAtBoundary = context.last?.isWhitespace == true
        let sourceText = partialRelationshipPrefix?.sourceText
            ?? ((endsAtBoundary || completedSentenceBoundary) ? "" : tokens.last?.surface ?? "")
        let completedTokens = (endsAtBoundary || completedSentenceBoundary || partialRelationshipPrefix != nil)
            ? tokens
            : Array(tokens.dropLast())
        guard !completedTokens.isEmpty else { return nil }

        var contextKeys = [String]()
        for count in stride(from: min(6, completedTokens.count), through: 1, by: -1) {
            let words = completedTokens.suffix(count).map(\.normalized).joined(separator: " ")
            contextKeys.append(relationshipPunctuation.map { sentenceRole(for: $0) + "|" + words } ?? words)
        }
        if includeEnglishRelationships, let relationshipPunctuation {
            let discourseRole = sentenceRole(for: relationshipPunctuation)
            let relationships = partialRelationshipPrefix?.relationships
                ?? HWKLearnedPhraseRelationship.allCases
            contextKeys.append(contentsOf: relationships.map {
                relationshipContextKey(
                    discourseRole: discourseRole,
                    relationship: $0
                )
            })
        }
        let paragraphPlan = includeEnglishRelationships
            ? paragraphPlanQuery(in: context)
            : nil
        if let paragraphPlan {
            contextKeys.append(paragraphPlanContextKey(
                position: paragraphPlan.position,
                previousSentenceRole: paragraphPlan.previousSentenceRole
            ))
        }
        return Query(
            sourceText: sourceText,
            contextKeys: contextKeys,
            partialRelationshipPrefix: partialRelationshipPrefix,
            paragraphIntent: paragraphPlan?.intent
        )
    }

    private static func partialRelationshipPrefix(in context: String) -> PartialRelationshipPrefix? {
        guard let punctuationIndex = context.lastIndex(where: {
            $0 == "." || $0 == "!" || $0 == "?"
        }) else {
            return nil
        }
        let punctuation = context[punctuationIndex]
        let afterPunctuation = context[context.index(after: punctuationIndex)...]
        guard let prefixStart = afterPunctuation.firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        let typedPrefix = String(afterPunctuation[prefixStart...])
        guard !typedPrefix.isEmpty,
              typedPrefix.count <= 48,
              !typedPrefix.contains(where: { $0.isNewline }) else {
            return nil
        }
        let normalizedPrefix = typedPrefix.lowercased()
        var relationships = [HWKLearnedPhraseRelationship]()
        for definition in englishMultiwordRelationshipConnectors
        where definition.phrase.hasPrefix(normalizedPrefix) {
            if !relationships.contains(definition.relationship) {
                relationships.append(definition.relationship)
            }
        }
        guard !relationships.isEmpty,
              let prefixTokens = trailingTokens(in: typedPrefix) else {
            return nil
        }
        let sourceText = typedPrefix.last?.isWhitespace == true
            ? ""
            : prefixTokens.last?.surface ?? ""
        return PartialRelationshipPrefix(
            punctuation: punctuation,
            contextBeforeBoundary: String(context[..<punctuationIndex]),
            typedPrefix: typedPrefix,
            normalizedPrefix: normalizedPrefix,
            sourceText: sourceText,
            relationships: relationships
        )
    }

    private static func partialRelationshipReplacement(
        _ learnedSurface: String,
        for prefix: PartialRelationshipPrefix
    ) -> String? {
        guard learnedSurface.lowercased().hasPrefix(prefix.normalizedPrefix) else {
            return nil
        }
        let replacementOffset = prefix.typedPrefix.count - prefix.sourceText.count
        guard replacementOffset >= 0,
              let replacementStart = learnedSurface.index(
                learnedSurface.startIndex,
                offsetBy: replacementOffset,
                limitedBy: learnedSurface.endIndex
              ) else {
            return nil
        }
        let replacement = String(learnedSurface[replacementStart...])
        return replacement.isEmpty ? nil : replacement
    }

    private static func relationshipConnector(in continuation: String) -> RelationshipConnector? {
        let trimmed = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowedRhythm = CharacterSet(charactersIn: ",;:—–-")
        let lowered = trimmed.lowercased()
        for definition in englishMultiwordRelationshipConnectors
        where lowered.hasPrefix(definition.phrase) {
            let phraseEnd = trimmed.index(trimmed.startIndex, offsetBy: definition.phrase.count)
            var surfaceEnd = phraseEnd
            if phraseEnd < trimmed.endIndex {
                let boundary = trimmed[phraseEnd]
                guard boundary.isWhitespace || boundary.unicodeScalars.allSatisfy(allowedRhythm.contains) else {
                    continue
                }
                while surfaceEnd < trimmed.endIndex,
                      trimmed[surfaceEnd].unicodeScalars.allSatisfy(allowedRhythm.contains) {
                    surfaceEnd = trimmed.index(after: surfaceEnd)
                }
            }
            return RelationshipConnector(
                relationship: definition.relationship,
                surface: String(trimmed[..<surfaceEnd])
            )
        }
        guard let firstChunk = trimmed.split(whereSeparator: \.isWhitespace).first,
              firstChunk.count <= 32 else {
            return nil
        }
        let word = firstChunk.prefix(while: \.isLetter)
        guard !word.isEmpty,
              let relationship = englishRelationshipConnectors[word.lowercased()] else {
            return nil
        }
        let rhythm = firstChunk.dropFirst(word.count)
        guard rhythm.unicodeScalars.allSatisfy(allowedRhythm.contains) else { return nil }
        return RelationshipConnector(
            relationship: relationship,
            surface: String(firstChunk)
        )
    }

    private static func relationshipContextKey(
        discourseRole: String,
        relationship: HWKLearnedPhraseRelationship
    ) -> String {
        relationshipContextPrefix + discourseRole + "|" + relationship.rawValue
    }

    private static func relationship(from contextKey: String) -> HWKLearnedPhraseRelationship? {
        guard contextKey.hasPrefix(relationshipContextPrefix) else { return nil }
        let components = contextKey.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3 else { return nil }
        return HWKLearnedPhraseRelationship(rawValue: String(components[2]))
    }

    private static func paragraphPlanContextKey(
        position: HWKLearnedParagraphPosition,
        previousSentenceRole: String
    ) -> String {
        paragraphPlanContextPrefix + position.rawValue + "|" + previousSentenceRole
    }

    private static func paragraphPlan(
        from contextKey: String,
        intent: HWKLearnedParagraphIntent? = nil
    ) -> HWKLearnedParagraphPlan? {
        guard contextKey.hasPrefix(paragraphPlanContextPrefix) else { return nil }
        let components = contextKey.split(separator: "|", omittingEmptySubsequences: false)
        guard components.count == 3,
              let position = HWKLearnedParagraphPosition(rawValue: String(components[1])) else {
            return nil
        }
        let previousSentenceRole = String(components[2])
        guard previousSentenceRole == "statement"
                || previousSentenceRole == "question"
                || previousSentenceRole == "exclamation" else {
            return nil
        }
        return HWKLearnedParagraphPlan(
            position: position,
            previousSentenceRole: previousSentenceRole,
            intent: intent
        )
    }

    private static func paragraphPlanObservationIsValid(_ observation: Observation) -> Bool {
        guard observation.language == "en",
              paragraphPlan(
                  from: observation.contextKey,
                  intent: observation.paragraphIntent
              ) != nil,
              observation.continuation.count <= 64,
              !observation.continuation.contains("@"),
              !observation.continuation.localizedCaseInsensitiveContains("://"),
              hasOnlyLatinScriptLetters(observation.continuation),
              !observation.continuation.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            return false
        }
        let rawChunks = observation.continuation.split(whereSeparator: \.isWhitespace)
        guard (3...6).contains(rawChunks.count),
              let rawFirstChunk = rawChunks.first,
              !rawFirstChunk.contains(where: \.isNumber) else {
            return false
        }
        let starterTokens = rawChunks.compactMap(token)
        guard starterTokens.count == rawChunks.count,
              starterTokens.map(\.surface).joined(separator: " ") == observation.continuation,
              starterTokens.map(\.normalized).joined(separator: " ")
                == observation.continuationKey,
              let first = starterTokens.first,
              !englishCodeStarterKeywords.contains(first.normalized),
              starterTokens.contains(where: {
                  $0.normalized.count >= 4
                      && !englishParagraphStarterStopwords.contains($0.normalized)
              }),
              relationshipConnector(in: observation.continuation) == nil else {
            return false
        }
        return true
    }

    private static func paragraphPlanFeedbackIsValid(_ observation: Observation) -> Bool {
        let isParagraphPlan = paragraphPlan(
            from: observation.contextKey,
            intent: observation.paragraphIntent
        ) != nil
        guard isParagraphPlan else {
            return observation.paragraphPlanNegativeFeedbackCount == nil
                && observation.paragraphPlanRecoveryBaselineCount == nil
                && observation.paragraphPlanRecoveryEvidenceCount == nil
                && observation.paragraphPlanSeenFeedbackEpisodeFingerprints == nil
                && observation.paragraphPlanFeedbackCursorTimestampMilliseconds == nil
                && observation.paragraphPlanFeedbackCursorEpisodeFingerprint == nil
        }

        switch (
            observation.paragraphPlanNegativeFeedbackCount,
            observation.paragraphPlanRecoveryBaselineCount,
            observation.paragraphPlanRecoveryEvidenceCount
        ) {
        case (nil, nil, nil):
            break
        case let (negativeCount?, recoveryBaseline?, recoveryEvidenceCount?):
            guard (1...Self.paragraphPlanForgettingThreshold).contains(negativeCount),
                  (1...observation.count).contains(recoveryBaseline),
                  (0..<Self.paragraphPlanRelearningEvidence).contains(
                      recoveryEvidenceCount
                  ) else {
                return false
            }
        default:
            return false
        }

        let seen = observation.paragraphPlanSeenFeedbackEpisodeFingerprints
        if let seen {
            guard !seen.isEmpty,
                  seen.count <= Self.maximumParagraphPlanFeedbackReceipts,
                  Set(seen).count == seen.count else {
                return false
            }
            if let negativeCount = observation.paragraphPlanNegativeFeedbackCount,
               seen.count < negativeCount {
                return false
            }
        }
        if observation.paragraphPlanNegativeFeedbackCount != nil, seen == nil {
            return false
        }
        switch (
            observation.paragraphPlanFeedbackCursorTimestampMilliseconds,
            observation.paragraphPlanFeedbackCursorEpisodeFingerprint
        ) {
        case (nil, nil):
            return seen == nil
        case let (timestamp?, fingerprint?):
            return timestamp >= 0 && seen?.contains(fingerprint) == true
        default:
            return false
        }
    }

    private static func hasOnlyLatinScriptLetters(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            guard CharacterSet.letters.contains(scalar) else { return true }
            switch scalar.value {
            case 0x0041...0x005A,
                 0x0061...0x007A,
                 0x00C0...0x024F,
                 0x1E00...0x1EFF:
                return true
            default:
                return false
            }
        }
    }

    private static func explanation(
        for observation: Observation,
        relationship: HWKLearnedPhraseRelationship?,
        paragraphPlan: HWKLearnedParagraphPlan?,
        paragraphPlanNegativeFeedbackCount: Int
    ) -> String {
        if let relationship {
            let components = observation.contextKey.split(separator: "|", omittingEmptySubsequences: false)
            let boundary = components.count > 1 ? String(components[1]) : "sentence"
            return "I learned a \(relationship.explanationLabel) relationship: you started \(observation.count) distinct \(boundary) continuations with “\(observation.continuation)”. This is a suggestion-only hypothesis."
        }
        if let paragraphPlan {
            let caution = paragraphPlanNegativeFeedbackCount > 0
                ? " I am treating it cautiously after \(paragraphPlanNegativeFeedbackCount) reversal\(paragraphPlanNegativeFeedbackCount == 1 ? "" : "s")."
                : ""
            if let intent = paragraphPlan.intent {
                return "I linked \(intent.explanationLabel): “\(observation.continuation)” started the \(paragraphPlan.position.rawValue) sentence in \(observation.count) distinct paragraphs. This is a suggestion-only paragraph hypothesis.\(caution)"
            }
            return "I noticed you used “\(observation.continuation)” to start the \(paragraphPlan.position.rawValue) sentence in \(observation.count) distinct paragraphs. This is a suggestion-only paragraph hypothesis.\(caution)"
        }
        let wordCount = observation.contextKey.split(separator: " ").count
        return "I remembered this continuation after \(wordCount) nearby words from \(observation.count) repeated examples."
    }

    private static func sentenceRole(for punctuation: Character) -> String {
        switch punctuation {
        case "?": return "question"
        case "!": return "exclamation"
        default: return "statement"
        }
    }

    private static func token(_ raw: Substring) -> Token? {
        let characters = Array(raw)
        let isAllowed: (Character) -> Bool = {
            $0.isLetter || $0 == "'" || $0 == "’" || $0 == "-"
        }
        guard let first = characters.firstIndex(where: { $0.isLetter }),
              let last = characters.lastIndex(where: { $0.isLetter }) else {
            return nil
        }
        let tokenCharacters = Array(characters[first...last])
        guard tokenCharacters.count <= 32,
              tokenCharacters.allSatisfy(isAllowed) else {
            return nil
        }
        let surface = String(tokenCharacters)
        return Token(surface: surface, normalized: surface.lowercased())
    }

    private struct Token {
        let surface: String
        let normalized: String
    }

    private struct CompletedSentence {
        let body: String
        let punctuation: Character
    }

    private struct Query {
        let sourceText: String
        let contextKeys: [String]
        let partialRelationshipPrefix: PartialRelationshipPrefix?
        let paragraphIntent: HWKLearnedParagraphIntent?
    }

    private struct PartialRelationshipPrefix {
        let punctuation: Character
        let contextBeforeBoundary: String
        let typedPrefix: String
        let normalizedPrefix: String
        let sourceText: String
        let relationships: [HWKLearnedPhraseRelationship]
    }

    private struct RankedSuggestion {
        let suggestion: HWKLearnedPhraseSuggestion
        let confidenceCount: Int
        let contextRank: Int
        let continuationWordCount: Int
        let lastSeen: Date
    }

    private struct ParagraphPlanFamily {
        let anchor: RankedSuggestion
        let members: [RankedSuggestion]
        let strongest: RankedSuggestion
    }

    private struct RelationshipConnector {
        let relationship: HWKLearnedPhraseRelationship
        let surface: String
    }

    private struct RelationshipConnectorDefinition {
        let phrase: String
        let relationship: HWKLearnedPhraseRelationship
    }

    private struct Observation: Codable, Equatable {
        let language: String
        let contextKey: String
        let continuationKey: String
        var continuation: String
        var count: Int
        var lastSeen: Date
        var evidenceFingerprints: [UInt64]? = nil
        var paragraphIntent: HWKLearnedParagraphIntent? = nil
        var paragraphPlanNegativeFeedbackCount: Int? = nil
        var paragraphPlanRecoveryBaselineCount: Int? = nil
        var paragraphPlanRecoveryEvidenceCount: Int? = nil
        var paragraphPlanSeenFeedbackEpisodeFingerprints: [UInt64]? = nil
        var paragraphPlanFeedbackCursorTimestampMilliseconds: Int64? = nil
        var paragraphPlanFeedbackCursorEpisodeFingerprint: UInt64? = nil

        var id: String {
            let base = language + "\u{1F}" + contextKey + "\u{1F}" + continuationKey
            guard let paragraphIntent else { return base }
            return base + "\u{1F}intent:" + paragraphIntent.rawValue
        }
    }

    private struct Envelope: Codable {
        let version: Int
        let observations: [Observation]
    }
}

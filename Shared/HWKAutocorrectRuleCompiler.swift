import Foundation

/// Natural-language autocorrect rule compiler.
///
/// The sentence-builder UI (and the optional on-device model wrapper in the
/// companion app) produce an `AutocorrectRuleDraft` — a small, structured
/// description of one rule. `HWKAutocorrectRuleCompiler` turns that draft into
/// the concrete `KeyboardAutocorrectLogicBlock` pipeline the correction engine
/// already knows how to run. No new runtime ML: the compiled blocks are
/// executed by the existing lightweight ranker.
///
/// This file is deliberately free of any `FoundationModels` / on-device-model
/// dependency so it stays safe in the keyboard extension (which globs `Shared`)
/// and fully unit-testable. The "smart" free-text path lives only in the
/// companion app (`HWKNaturalLanguageRuleModel`) and degrades to
/// `HWKAutocorrectRuleParser` everywhere else.

/// A structured, engine-agnostic description of a single autocorrect rule.
/// This is the contract between "how the rule was authored" (dropdown tokens,
/// free text, or the on-device model) and "how the engine runs it".
struct AutocorrectRuleDraft: Codable, Equatable {
    /// When the rule should act.
    enum Trigger: String, Codable, CaseIterable {
        /// A word that isn't in the dictionary (a likely typo).
        case typo
        /// The engine is unsure about the best candidate.
        case lowConfidence
        /// Every word.
        case anyWord
    }

    /// What the rule does when it triggers.
    enum Action: String, Codable, CaseIterable {
        /// Replace the typed word automatically.
        case correctAutomatically
        /// Offer a suggestion but never replace silently.
        case suggestOnly
        /// Leave the typed word untouched.
        case doNotChange
    }

    /// Which candidate source the rule leans on first.
    enum SourcePreference: String, Codable, CaseIterable {
        case savedWordsFirst
        case dictionaryFirst
        case balanced
    }

    /// Token categories a rule can protect from correction.
    enum ProtectedCategory: String, Codable, CaseIterable {
        case names
        case urls
        case code
        case allCaps
    }

    var trigger: Trigger
    var action: Action
    var sourcePreference: SourcePreference
    var protected: [ProtectedCategory]
    /// 0 = gentle (rarely acts), 1 = confident (acts readily).
    var strength: Double
    /// The original text the draft was authored from, kept for display/audit.
    var sourceText: String

    init(
        trigger: Trigger = .typo,
        action: Action = .correctAutomatically,
        sourcePreference: SourcePreference = .balanced,
        protected: [ProtectedCategory] = [],
        strength: Double = 0.85,
        sourceText: String = ""
    ) {
        self.trigger = trigger
        self.action = action
        self.sourcePreference = sourcePreference
        self.protected = protected
        self.strength = strength
        self.sourceText = sourceText
    }
}

enum HWKAutocorrectRuleCompiler {
    /// Lowest confidence we let an automatic-correction gate fall to.
    static let minimumThreshold: Double = 0.5
    /// "Do not change" rules clamp the gate at least this high so nothing slips through.
    static let protectiveThreshold: Double = 0.97

    /// Compile a single draft into an ordered, validated block pipeline.
    static func blocks(for draft: AutocorrectRuleDraft) -> [KeyboardAutocorrectLogicBlock] {
        var blocks: [KeyboardAutocorrectLogicBlock] = []

        // 1. Candidate sources, ordered by the user's preference.
        switch draft.sourcePreference {
        case .savedWordsFirst:
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .savedWords, rankPriority: 0))
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .dictionary, rankPriority: 0))
        case .dictionaryFirst:
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .dictionary, rankPriority: 0))
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .savedWords, rankPriority: 0))
        case .balanced:
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .savedWords, rankPriority: 0))
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .dictionary, rankPriority: 0))
        }

        // 2. Weighted ranker biased toward the preferred source.
        let savedWeight: Double
        switch draft.sourcePreference {
        case .savedWordsFirst: savedWeight = 0.7
        case .dictionaryFirst: savedWeight = 0.3
        case .balanced: savedWeight = 0.5
        }
        blocks.append(KeyboardAutocorrectLogicBlock(
            kind: .weightedRanker,
            rankPriority: 0,
            dictionaryWeight: 1.0 - savedWeight,
            savedWordsWeight: savedWeight
        ))

        // 3. Safety gate when the user wants categories protected, or always for
        //    "do not change" rules (those exist precisely to hold text back).
        if !draft.protected.isEmpty || draft.action == .doNotChange {
            blocks.append(KeyboardAutocorrectLogicBlock(kind: .safetyGate, rankPriority: 0))
        }

        // 4. Confidence gate + matching fallback derived from the action.
        let threshold = effectiveThreshold(for: draft)
        let gate = KeyboardAutocorrectLogicBlock(
            kind: .confidenceGate,
            rankPriority: 0,
            acceptanceThreshold: threshold
        )
        blocks.append(gate)

        let fallbackKind: KeyboardAutocorrectLogicBlockKind = (draft.action == .correctAutomatically)
            ? .strictFallback
            : .softFallback
        blocks.append(KeyboardAutocorrectLogicBlock(
            kind: fallbackKind,
            rankPriority: 0,
            fallbackEnabled: true,
            fallbackTargetID: gate.id
        ))

        return validated(blocks)
    }

    /// Resolve the acceptance threshold from strength, action, and trigger.
    static func effectiveThreshold(for draft: AutocorrectRuleDraft) -> Double {
        var threshold = clamp(draft.strength, lower: minimumThreshold, upper: 1.0)

        // Acting on low-confidence input means being willing to fire when less sure.
        if draft.trigger == .lowConfidence {
            threshold = clamp(threshold - 0.1, lower: minimumThreshold, upper: 1.0)
        }

        // "Do not change" must never auto-replace, so hold the gate very high.
        if draft.action == .doNotChange {
            threshold = max(threshold, protectiveThreshold)
        }

        return threshold
    }

    /// Normalize a freshly built pipeline: clamp numeric fields, collapse
    /// singleton block kinds, and renumber `rankPriority` sequentially so the
    /// result is a valid pipeline regardless of how the draft was authored.
    static func validated(_ blocks: [KeyboardAutocorrectLogicBlock]) -> [KeyboardAutocorrectLogicBlock] {
        let singletonKinds: Set<KeyboardAutocorrectLogicBlockKind> = [
            .weightedRanker, .confidenceGate, .safetyGate,
            .strictFallback, .softFallback,
        ]

        var seenSingletons: Set<KeyboardAutocorrectLogicBlockKind> = []
        var result: [KeyboardAutocorrectLogicBlock] = []

        for block in blocks {
            if singletonKinds.contains(block.kind) {
                guard !seenSingletons.contains(block.kind) else { continue }
                seenSingletons.insert(block.kind)
            }

            var normalized = block
            normalized.dictionaryWeight = clamp(block.dictionaryWeight, lower: 0.0, upper: 1.0)
            normalized.savedWordsWeight = clamp(block.savedWordsWeight, lower: 0.0, upper: 1.0)
            normalized.acceptanceThreshold = clamp(block.acceptanceThreshold, lower: 0.0, upper: 1.0)
            normalized.rankPriority = result.count
            result.append(normalized)
        }

        return result
    }

    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

/// Deterministic keyword parser. Always returns a valid draft. This is both the
/// fallback for devices without the on-device model and the unit-tested core of
/// the natural-language path.
enum HWKAutocorrectRuleParser {
    static func parse(_ text: String) -> AutocorrectRuleDraft {
        let lower = text.lowercased()
        func mentions(_ needles: String...) -> Bool {
            needles.contains { lower.contains($0) }
        }

        // Action — protective phrasing wins over "suggest" wins over the default.
        let action: AutocorrectRuleDraft.Action
        if mentions("don't change", "dont change", "do not change", "never change",
                    "never touch", "never correct", "never fix", "never autocorrect",
                    "don't correct", "dont correct", "don't fix", "dont fix",
                    "leave", "stop changing", "stop correcting", "don't touch", "dont touch") {
            action = .doNotChange
        } else if mentions("suggest", "don't replace", "dont replace", "show me", "offer", "without replacing") {
            action = .suggestOnly
        } else {
            action = .correctAutomatically
        }

        // Protected categories.
        var protected: [AutocorrectRuleDraft.ProtectedCategory] = []
        if mentions("name", "friend", "contact", "slang") { protected.append(.names) }
        if mentions("url", "link", "website", "address", "domain") { protected.append(.urls) }
        if mentions("code", "command", "variable", "snippet") { protected.append(.code) }
        if mentions("caps", "all caps", "uppercase", "acronym") { protected.append(.allCaps) }

        // Source preference.
        let sourcePreference: AutocorrectRuleDraft.SourcePreference
        if mentions("saved word", "my word", "my words", "shortcut", "slang", "personal") {
            sourcePreference = .savedWordsFirst
        } else if mentions("dictionary", "standard spelling", "proper spelling") {
            sourcePreference = .dictionaryFirst
        } else {
            sourcePreference = .balanced
        }

        // Strength.
        let strength: Double
        if mentions("aggressive", "confident", "always", "strongly", "definitely") {
            strength = 0.95
        } else if mentions("gentle", "careful", "rarely", "cautious", "only when sure", "conservative") {
            strength = 0.6
        } else {
            strength = 0.85
        }

        // Trigger.
        let trigger: AutocorrectRuleDraft.Trigger
        if mentions("every word", "everything", "all words", "any word") {
            trigger = .anyWord
        } else if mentions("unsure", "not sure", "low confidence", "guess") {
            trigger = .lowConfidence
        } else {
            trigger = .typo
        }

        return AutocorrectRuleDraft(
            trigger: trigger,
            action: action,
            sourcePreference: sourcePreference,
            protected: protected,
            strength: strength,
            sourceText: text
        )
    }
}

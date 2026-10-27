import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Companion-app-only natural-language rule compiler.
///
/// Turns a free-text instruction into a structured rule draft, using Apple's
/// on-device Foundation Models (iOS 26+) when available and falling back to a
/// small local compiler everywhere else.
///
/// This type lives ONLY in the companion app target and runs at config time —
/// when the user authors or edits a rule. It must never be referenced from the
/// keyboard extension: a `LanguageModelSession` on the per-keystroke path would
/// blow the extension's memory/latency budget. The runtime keeps using the
/// lightweight blocks produced by `HWKAutocorrectRuleCompiler`.
struct HWKNaturalLanguageRuleModel {
    /// How the draft was produced — surfaced so the UI can label model output
    /// and let the user confirm before it is applied.
    enum Source: Equatable {
        case onDeviceModel
        case deterministicFallback
    }

    enum Draft: Equatable {
        case autocorrect(AutocorrectRuleDraft)
        case customText(HWKCustomTextRule)
    }

    struct Result: Equatable {
        let draft: Draft
        let source: Source
    }

    /// Whether the on-device model is currently usable on this device.
    var isOnDeviceModelAvailable: Bool {
#if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return false }
        let model = SystemLanguageModel.default
        return model.isAvailable && model.supportsLocale(Locale.current)
#else
        return false
#endif
    }

    /// Compile free text into a rule draft. Always succeeds — the deterministic
    /// parser is the floor.
    func draft(from text: String) async -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(draft: .autocorrect(AutocorrectRuleDraft(sourceText: text)), source: .deterministicFallback)
        }

        if let customRule = Self.localCustomTextRule(from: trimmed) {
            return Result(draft: .customText(customRule), source: .deterministicFallback)
        }

#if canImport(FoundationModels)
        if #available(iOS 26.0, *), isOnDeviceModelAvailable,
           let generated = await generate(from: trimmed) {
            return Result(draft: generated, source: .onDeviceModel)
        }
#endif
        return Result(draft: .autocorrect(HWKAutocorrectRuleParser.parse(trimmed)), source: .deterministicFallback)
    }

    private static func localCustomTextRule(from text: String) -> HWKCustomTextRule? {
        LocalCustomTextRuleCompiler(sourceText: text).compile()
    }

    static func customTextRule(source: String, replacement: String) -> HWKCustomTextRule? {
        let source = source.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacement.components(separatedBy: .controlCharacters).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              !replacement.isEmpty,
              source.count <= 96,
              replacement.count <= 96,
              source != replacement,
              !source.contains("\""),
              !replacement.contains("\"") else {
            return nil
        }
        let instruction = source.contains(where: \.isWhitespace)
            ? "replace \"\(source)\" with \"\(replacement)\" in sentences"
            : "when word is \"\(source)\", suggest \"\(replacement)\""
        return localCustomTextRule(from: instruction)
    }

    static func customTextRuleSummary(_ rule: HWKCustomTextRule) -> String {
        if let pair = splitRuleName(rule.name, prefix: "Word: ") {
            return "When you type \"\(pair.source)\", suggest \"\(pair.replacement)\"."
        }
        if let pair = splitRuleName(rule.name, prefix: "Sentence replace: ") {
            return "Replace \"\(pair.source)\" with \"\(pair.replacement)\" in sentences."
        }
        if rule.name.hasPrefix("Sentence append: ") {
            let body = String(rule.name.dropFirst("Sentence append: ".count))
            if let range = body.range(of: " when ") {
                let suffix = String(body[..<range.lowerBound])
                let condition = String(body[range.upperBound...])
                return "When a sentence \(condition), append \"\(suffix)\"."
            }
            return "Append generated text to matching sentences."
        }

        switch rule.trigger {
        case .onSentenceEnd:
            return rule.name.isEmpty ? "Suggest text when a sentence ends." : rule.name
        case .onWordCommit:
            return rule.name.isEmpty ? "Suggest text when a word is committed." : rule.name
        case .onManualInvoke:
            return rule.name.isEmpty ? "Suggest text when run manually." : rule.name
        }
    }

    static func customTextRuleDetail(_ rule: HWKCustomTextRule) -> String {
        switch rule.trigger {
        case .onSentenceEnd:
            return "Runs when a sentence ends."
        case .onWordCommit:
            return "Runs when a word is committed."
        case .onManualInvoke:
            return "Runs when you run the rule manually."
        }
    }

    static func generatedCustomTextRules(
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        limit: Int = 8
    ) -> [HWKCustomTextRule] {
        generatedCustomTextRules(
            from: KeyboardSharedPreferences.rawTypedTextMLSamples(defaults: defaults),
            limit: limit
        )
    }

    static func generatedCustomTextRules(
        from samples: [KeyboardRawTypedTextMLSample],
        limit: Int = 8
    ) -> [HWKCustomTextRule] {
        let words = samples
            .map(\.rawText)
            .map { normalizedSampleWord($0) }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }

        var counts = [String: Int]()
        var surfacesByLowercase = [String: [String: Int]]()
        for word in words {
            counts[word, default: 0] += 1
            surfacesByLowercase[word.lowercased(), default: [:]][word, default: 0] += 1
        }

        var candidates = [(score: Int, source: String, replacement: String, reason: String)]()
        for (lowercase, surfaces) in surfacesByLowercase where surfaces.count > 1 {
            guard let preferred = preferredSurface(in: surfaces) else { continue }
            for source in surfaces.keys where source != preferred {
                candidates.append((
                    score: (counts[source] ?? 0) + (counts[preferred] ?? 0) + 20,
                    source: source,
                    replacement: preferred,
                    reason: "typed casing pattern for \(lowercase)"
                ))
            }
        }

        let knownCorrections = sampleBackedCorrectionPairs
        for (source, replacement) in knownCorrections {
            let sourceCount = counts[source] ?? 0
            guard sourceCount > 0 else { continue }
            let replacementSeen = counts[replacement] ?? 0
            candidates.append((
                score: sourceCount * 3 + replacementSeen + 10,
                source: source,
                replacement: replacement,
                reason: replacementSeen > 0 ? "typed correction pattern" : "local typo pattern"
            ))
        }

        var seenSources = Set<String>()
        return candidates
            .filter { $0.source.lowercased() != $0.replacement.lowercased() || $0.source != $0.replacement }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.source < $1.source
            }
            .compactMap { candidate -> HWKCustomTextRule? in
                let key = candidate.source.lowercased()
                guard !seenSources.contains(key) else { return nil }
                seenSources.insert(key)
                return localCustomTextRule(
                    from: "when word is \"\(candidate.source)\", suggest \"\(candidate.replacement)\""
                )
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func splitRuleName(_ name: String, prefix: String) -> (source: String, replacement: String)? {
        guard name.hasPrefix(prefix) else { return nil }
        let body = String(name.dropFirst(prefix.count))
        guard let range = body.range(of: " -> ") else { return nil }
        return (
            source: String(body[..<range.lowerBound]),
            replacement: String(body[range.upperBound...])
        )
    }

    private static func normalizedSampleWord(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:()[]{}\""))
    }

    private static func preferredSurface(in surfaces: [String: Int]) -> String? {
        surfaces.max { lhs, rhs in
            let lhsScore = surfacePreferenceScore(lhs.key, count: lhs.value)
            let rhsScore = surfacePreferenceScore(rhs.key, count: rhs.value)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            return lhs.key < rhs.key
        }?.key
    }

    private static func surfacePreferenceScore(_ word: String, count: Int) -> Int {
        var score = count
        if word.contains(where: { $0.isUppercase }) { score += 10 }
        if word.dropFirst().contains(where: { $0.isUppercase }) { score += 15 }
        if word.allSatisfy({ !$0.isLetter || $0.isUppercase }) { score += 8 }
        return score
    }

    private static let sampleBackedCorrectionPairs: [String: String] = [
        "teh": "the",
        "wierd": "weird",
        "adress": "address",
        "recieve": "receive",
        "definately": "definitely",
        "seperate": "separate",
        "occured": "occurred",
        "becuase": "because",
        "freind": "friend",
        "thier": "their",
        "dont": "don't",
        "cant": "can't",
        "wont": "won't",
        "im": "I'm",
        "ive": "I've",
        "idk": "I don't know",
        "brb": "be right back",
        "omw": "on my way",
        "rn": "right now",
        "u": "you",
        "ur": "your",
        "tho": "though",
        "bc": "because",
        "pls": "please",
        "ios": "iOS",
        "iphone": "iPhone",
        "swiftui": "SwiftUI",
        "xcode": "Xcode",
        "github": "GitHub"
    ]

    private struct LocalCustomTextRuleCompiler {
        let sourceText: String

        private struct Condition {
            let expression: HWKRuleExpr
            let summary: String
        }

        private var trimmed: String {
            sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private var normalized: String {
            trimmed.lowercased()
        }

        private var sentence: HWKRuleExpr { .context(.currentSentence) }
        private var lowerSentence: HWKRuleExpr { .str(.lower, [sentence]) }
        private var trimmedSentence: HWKRuleExpr { .str(.trim, [sentence]) }
        private var lowerTrimmedSentence: HWKRuleExpr { .str(.lower, [trimmedSentence]) }

        func compile() -> HWKCustomTextRule? {
            compileWordSuggestion()
                ?? compileSentenceReplacement()
                ?? compileSentenceAppend()
        }

        private func compileWordSuggestion() -> HWKCustomTextRule? {
            guard let pair = wordSuggestionPair(),
                  normalized.contains("word"),
                  normalized.contains("suggest") || normalized.contains("replace") else {
                return nil
            }

            let word = pair.source
            let suggestion = pair.replacement
            let condition = HWKRuleExpr.compare(
                .eq,
                .str(.lower, [.str(.trim, [.context(.currentWord)])]),
                .lit(.string(word.lowercased()))
            )
            return makeRule(
                name: "Word: \(word) -> \(suggestion)",
                trigger: .onWordCommit,
                statements: [
                    .ifElse(condition, [.emit(.suggest, .lit(.string(suggestion)))], [])
                ]
            )
        }

        private func compileSentenceReplacement() -> HWKCustomTextRule? {
            guard let pair = sentenceReplacementPair(),
                  normalized.contains("replace"),
                  normalized.contains("sentence") else {
                return nil
            }

            let source = pair.source
            let replacement = pair.replacement
            let replaced = HWKRuleExpr.str(
                .replace,
                [
                    sentence,
                    .lit(.string(regexPattern(forReplacing: source))),
                    .lit(.string(NSRegularExpression.escapedTemplate(for: replacement)))
                ]
            )
            let condition = HWKRuleExpr.compare(.neq, replaced, sentence)
            return makeRule(
                name: "Sentence replace: \(source) -> \(replacement)",
                trigger: .onSentenceEnd,
                statements: [
                    .ifElse(condition, [.emit(.suggest, replaced)], [])
                ]
            )
        }

        private func compileSentenceAppend() -> HWKCustomTextRule? {
            guard normalized.contains("sentence"),
                  normalized.contains("append") || normalized.contains("add") || normalized.contains("show") || normalized.contains("suggest") else {
                return nil
            }

            let quoted = quotedStrings()
            guard let suffix = quoted.first ?? normalizedAppendText(unquotedAppendText()),
                  let baseCondition = sentenceCondition(quoted: quoted) else {
                return nil
            }

            let notAlreadyPresent = HWKRuleExpr.not(
                .str(.endsWith, [trimmedSentence, .lit(.string(suffix))])
            )
            return makeRule(
                name: "Sentence append: \(suffix) when \(baseCondition.summary)",
                trigger: .onSentenceEnd,
                statements: [
                    .ifElse(
                        .and(baseCondition.expression, notAlreadyPresent),
                        [.emit(.suggest, .arith(.add, sentence, .lit(.string(suffix))))],
                        []
                    )
                ]
            )
        }

        private func sentenceCondition(quoted: [String]) -> Condition? {
            if normalized.contains("wh question") {
                let whWords = "^(what|where|when|who|whom|whose|why|which|how)\\b"
                return Condition(
                    expression: .str(.matches, [lowerSentence, .lit(.string(whWords))]),
                    summary: "starts with a WH question word"
                )
            }

            if normalized.contains("do not end with punctuation")
                || normalized.contains("does not end with punctuation")
                || normalized.contains("missing punctuation") {
                return Condition(
                    expression: .not(.str(.matches, [trimmedSentence, .lit(.string("[.!?;:]$"))])),
                    summary: "does not end with punctuation"
                )
            }

            guard let rawOperand = quoted.dropFirst().first ?? unquotedSentenceConditionOperand() else { return nil }
            let operand = rawOperand.lowercased()
            if normalized.contains("start with") || normalized.contains("starts with") {
                return Condition(
                    expression: .str(.startsWith, [lowerTrimmedSentence, .lit(.string(operand))]),
                    summary: "starts with \"\(rawOperand)\""
                )
            }
            if normalized.contains("contain") || normalized.contains("contains") {
                return Condition(
                    expression: .str(.contains, [lowerSentence, .lit(.string(operand))]),
                    summary: "contains \"\(rawOperand)\""
                )
            }
            if normalized.contains("end with") || normalized.contains("ends with") {
                return Condition(
                    expression: .str(.endsWith, [lowerTrimmedSentence, .lit(.string(operand))]),
                    summary: "ends with \"\(rawOperand)\""
                )
            }
            return nil
        }

        private func makeRule(
            name: String,
            trigger: HWKCustomTextRule.Trigger,
            statements: [HWKRuleStatement]
        ) -> HWKCustomTextRule {
            HWKCustomTextRule(
                name: name,
                sourceText: sourceText,
                trigger: trigger,
                presentation: .suggest,
                script: HWKRuleScript(statements)
            )
        }

        private func quotedStrings() -> [String] {
            guard let regex = try? NSRegularExpression(pattern: #""([^"]*)""#) else {
                return []
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            return regex.matches(in: trimmed, range: range).compactMap { match in
                guard match.numberOfRanges > 1,
                      let captured = Range(match.range(at: 1), in: trimmed) else {
                    return nil
                }
                return String(trimmed[captured])
            }
        }

        private func wordSuggestionPair() -> (source: String, replacement: String)? {
            let quoted = quotedStrings()
            if quoted.count >= 2 {
                return (quoted[0], quoted[1])
            }

            if let direct = firstPair(patterns: [
                #"(?i)\bword\s+(?:is|equals|=)\s+(.+?)\s*,?\s*(?:suggest|replace(?:\s+it)?\s+with|correct(?:\s+it)?\s+to|change(?:\s+it)?\s+to)\s+(.+?)\s*$"#
            ]) {
                return direct
            }

            if let reversed = firstPair(patterns: [
                #"(?i)\b(?:suggest|replace|correct(?:\s+to)?)\s+(.+?)\s+(?:when|if|for)\s+(?:the\s+)?word\s+(?:is|equals|=)\s+(.+?)\s*$"#
            ]) {
                return (reversed.replacement, reversed.source)
            }

            return nil
        }

        private func sentenceReplacementPair() -> (source: String, replacement: String)? {
            let quoted = quotedStrings()
            if quoted.count >= 2 {
                return (quoted[0], quoted[1])
            }

            return firstPair(patterns: [
                #"(?i)\breplace\s+(.+?)\s+with\s+(.+?)\s+(?:in|inside|for)\s+sentences?\b"#
            ])
        }

        private func firstPair(patterns: [String]) -> (source: String, replacement: String)? {
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                guard let match = regex.firstMatch(in: trimmed, range: range),
                      match.numberOfRanges > 2,
                      let firstRange = Range(match.range(at: 1), in: trimmed),
                      let secondRange = Range(match.range(at: 2), in: trimmed) else {
                    continue
                }

                let source = normalizedUnquotedText(String(trimmed[firstRange]))
                let replacement = normalizedUnquotedText(String(trimmed[secondRange]))
                if !source.isEmpty && !replacement.isEmpty {
                    return (source, replacement)
                }
            }
            return nil
        }

        private func unquotedAppendText() -> String? {
            firstCapture(
                pattern: #"(?i)^\s*(?:show|append|add|suggest)\s+(.+?)\s+(?:on|to|when|for)\s+sentences?\b"#,
                group: 1
            )
        }

        private func normalizedAppendText(_ text: String?) -> String? {
            guard let text else { return nil }
            let normalized = normalizedUnquotedText(text)
            switch normalized.lowercased() {
            case "question mark", "a question mark":
                return "?"
            case "period", "a period", "full stop", "a full stop":
                return "."
            case "exclamation mark", "an exclamation mark", "exclamation point", "an exclamation point":
                return "!"
            case "comma", "a comma":
                return ","
            case "colon", "a colon":
                return ":"
            case "semicolon", "a semicolon":
                return ";"
            default:
                return normalized.isEmpty ? nil : normalized
            }
        }

        private func unquotedSentenceConditionOperand() -> String? {
            let patterns = [
                #"(?i)\bstarts?\s+with\s+(.+?)\s*$"#,
                #"(?i)\bcontains?\s+(.+?)\s*$"#,
                #"(?i)\bends?\s+with\s+(.+?)\s*$"#
            ]

            for pattern in patterns {
                if let capture = firstCapture(pattern: pattern, group: 1) {
                    let normalized = normalizedUnquotedText(capture)
                    if !normalized.isEmpty { return normalized }
                }
            }
            return nil
        }

        private func firstCapture(pattern: String, group: Int) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return nil
            }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  group < match.numberOfRanges,
                  let captured = Range(match.range(at: group), in: trimmed) else {
                return nil
            }
            return String(trimmed[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func normalizedUnquotedText(_ text: String) -> String {
            var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
            while result.first == "\"" || result.first == "'" {
                result.removeFirst()
            }
            while result.last == "\"" || result.last == "'" || result.last == "," {
                result.removeLast()
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private func regexPattern(forReplacing source: String) -> String {
            let escaped = NSRegularExpression.escapedPattern(for: source)
            if source.range(of: #"^[A-Za-z0-9']+$"#, options: .regularExpression) != nil {
                return #"(?i)\b\#(escaped)\b"#
            }
            return escaped
        }
    }

#if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func generate(from text: String) async -> Draft? {
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(to: text, generating: GeneratedRule.self)
            return response.content.toDraft(sourceText: text)
        } catch {
            return nil
        }
    }

    private static let instructions = """
    You convert a user's plain-language keyboard preference into a structured rule. \
    If the user asks to add, append, show, or suggest text based on sentence context, \
    prefer a custom text rule. Use autocorrect fields only for spelling/correction preferences. \
    Choose the single closest option for each field. Strength is 0 (only correct when extremely sure) to 100 (correct eagerly).
    """

    /// Guided-generation schema. Stored as constrained strings/ints so the mapping
    /// to `AutocorrectRuleDraft` stays defensive and tolerant of unexpected output.
    @available(iOS 26.0, *)
    @Generable
    struct GeneratedRule {
        @Guide(description: "When the rule acts: typo, lowConfidence, or anyWord")
        var trigger: String
        @Guide(description: "What it does: correctAutomatically, suggestOnly, or doNotChange")
        var action: String
        @Guide(description: "Which source to prefer: savedWordsFirst, dictionaryFirst, or balanced")
        var sourcePreference: String
        @Guide(description: "Categories to never modify, any of: names, urls, code, allCaps")
        var protected: [String]
        @Guide(description: "How eagerly to act, 0 gentle to 100 confident")
        var strength: Int

        private func safeGeneratedAction(rawValue: String) -> AutocorrectRuleDraft.Action {
            AutocorrectRuleDraft.Action(rawValue: rawValue) ?? .suggestOnly
        }

        func toDraft(sourceText: String) -> Draft {
            if let customRule = HWKNaturalLanguageRuleModel.localCustomTextRule(from: sourceText) {
                return .customText(customRule)
            }

            return .autocorrect(
                AutocorrectRuleDraft(
                    trigger: AutocorrectRuleDraft.Trigger(rawValue: trigger) ?? .typo,
                    action: safeGeneratedAction(rawValue: action),
                    sourcePreference: AutocorrectRuleDraft.SourcePreference(rawValue: sourcePreference) ?? .balanced,
                    protected: protected.compactMap(AutocorrectRuleDraft.ProtectedCategory.init(rawValue:)),
                    strength: min(max(Double(strength) / 100.0, 0.0), 1.0),
                    sourceText: sourceText
                )
            )
        }
    }
#endif
}

import Foundation
#if canImport(CoreML)
import CoreML
#endif

/// Distinguishes how a typed word arrived so correction scoring can apply
/// input-path-specific signals. Touch taps carry spatial noise (a finger can
/// land on a neighboring key); hardware keypresses do not. The default
/// `.unspecified` preserves pre-existing behavior exactly (no spatial signal).
enum HWKInputModality: String, Equatable, Sendable {
    case unspecified
    case touch
    case hardware
}

struct HWKCorrectionRequest: Equatable {
    let typedWord: String
    let previousWord: String?
    let sentenceContext: HWKSentenceContext?
    let isSecureTextEntry: Bool
    let allowsModelContext: Bool
    let inputModality: HWKInputModality

    init(
        typedWord: String,
        previousWord: String? = nil,
        sentenceContext: HWKSentenceContext? = nil,
        isSecureTextEntry: Bool = false,
        allowsModelContext: Bool = true,
        inputModality: HWKInputModality = .unspecified
    ) {
        self.typedWord = typedWord
        self.previousWord = previousWord
        self.sentenceContext = sentenceContext
        self.isSecureTextEntry = isSecureTextEntry
        self.allowsModelContext = allowsModelContext
        self.inputModality = inputModality
    }
}

struct HWKCorrectionResult: Equatable {
    let original: String
    let replacement: String?
    let candidates: [HWKRankedCorrection]
    let reversible: Bool

    var correctedText: String {
        replacement ?? original
    }
}

protocol HWKCorrectionCandidateGenerating {
    func candidates(for word: String) -> [HWKCorrectionCandidate]
}

struct HWKCoreMLCorrectionCandidateGenerator: HWKCorrectionCandidateGenerating {
#if canImport(CoreML)
    private static let bundledModelName = "HWKAutocorrectRanker"
    private let model: MLModel?

    init(model: MLModel? = Self.loadBundledModel()) {
        self.model = model
    }

    private static func loadBundledModel(
        bundle: Bundle = .main,
        modelName: String = Self.bundledModelName
    ) -> MLModel? {
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "mlmodelc") else {
            return nil
        }

        let configuration = MLModelConfiguration()
        return try? MLModel(contentsOf: modelURL, configuration: configuration)
    }
#else
    init() {}
#endif

    func candidates(for word: String) -> [HWKCorrectionCandidate] {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedWord.isEmpty else { return [] }

#if canImport(CoreML)
        guard let model else { return [] }

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "text": normalizedWord,
                "typedWord": normalizedWord,
                "characterCount": MLFeatureValue(int64: Int64(normalizedWord.count))
            ])
            let output = try model.prediction(from: input)
            guard let rawSuggestion = output.featureValue(for: "suggestion")?.stringValue
                    ?? output.featureValue(for: "label")?.stringValue else {
                return []
            }
            let suggestion = rawSuggestion.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !suggestion.isEmpty else { return [] }

            let confidence = output.featureValue(for: "confidence")?.doubleValue ?? 0.85
            let distance = HWKCorrectionEngine.editDistance(normalizedWord, suggestion.lowercased(), maxDistance: 3)
            guard distance <= 3 else { return [] }

            return [
                HWKCorrectionCandidate(
                    text: suggestion,
                    editDistance: distance,
                    frequency: max(0.0, min(1.0, confidence)),
                    source: .coreML
                )
            ]
        } catch {
            return []
        }
#else
        return []
#endif
    }
}

struct HWKCorrectionEngine {
    private let lexicon: HWKLexiconStore
    private let ranker: HWKCandidateRanker
    private let nativeSpellChecker: HWKCorrectionCandidateGenerating?
    private let foundationModelAdapter: HWKCorrectionCandidateGenerating?
    private let coreMLCandidateGenerator: HWKCorrectionCandidateGenerating?
    private let minimumReplacementScore: Double
    private static let unambiguousApostropheOnlyCorrections: [String: String] = [
        "arent": "aren't",
        "cant": "can't",
        "couldnt": "couldn't",
        "didnt": "didn't",
        "doesnt": "doesn't",
        "dont": "don't",
        "hasnt": "hasn't",
        "havent": "haven't",
        "hes": "he's",
        "heres": "here's",
        "hows": "how's",
        "im": "i'm",
        "ive": "i've",
        "isnt": "isn't",
        "itll": "it'll",
        "shes": "she's",
        "shouldnt": "shouldn't",
        "thats": "that's",
        "theres": "there's",
        "theyre": "they're",
        "wasnt": "wasn't",
        "weve": "we've",
        "werent": "weren't",
        "whats": "what's",
        "wont": "won't",
        "wouldnt": "wouldn't",
        "youre": "you're",
        "youve": "you've",
    ]

    init(
        lexicon: HWKLexiconStore = HWKLexiconStore(),
        ranker: HWKCandidateRanker = HWKCandidateRanker(),
        nativeSpellChecker: HWKCorrectionCandidateGenerating? = nil,
        foundationModelAdapter: HWKCorrectionCandidateGenerating? = nil,
        coreMLCandidateGenerator: HWKCorrectionCandidateGenerating? = nil,
        minimumReplacementScore: Double = 0.15
    ) {
        self.lexicon = lexicon
        self.ranker = ranker
        self.nativeSpellChecker = nativeSpellChecker
        self.foundationModelAdapter = foundationModelAdapter
        self.coreMLCandidateGenerator = coreMLCandidateGenerator
        self.minimumReplacementScore = minimumReplacementScore
    }

    func correction(for request: HWKCorrectionRequest) -> HWKCorrectionResult {
        guard !request.isSecureTextEntry else {
            return HWKCorrectionResult(original: request.typedWord, replacement: nil, candidates: [], reversible: false)
        }

        let typed = request.typedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.count > 1 else {
            return HWKCorrectionResult(original: request.typedWord, replacement: nil, candidates: [], reversible: true)
        }
        guard !Self.isProtectedCorrectionToken(typed) else {
            return HWKCorrectionResult(original: request.typedWord, replacement: nil, candidates: [], reversible: true)
        }

        var generated = lexiconCandidates(for: typed)
        generated.append(contentsOf: nativeSpellChecker?.candidates(for: typed) ?? [])
        generated.append(contentsOf: coreMLCandidateGenerator?.candidates(for: typed) ?? [])

        if request.allowsModelContext {
            generated.append(contentsOf: foundationModelAdapter?.candidates(for: typed) ?? [])
        }

        let spatialBoosts = Self.touchSpatialBoosts(
            typed: typed,
            candidates: generated,
            modality: request.inputModality
        )
        let repeatBoosts = Self.hardwareRepeatBoosts(
            typed: typed,
            candidates: generated,
            modality: request.inputModality
        )
        // Touch yields only spatial boosts and hardware only repeat boosts, so the
        // maps never overlap in practice; merge defensively with max() regardless.
        let combinedBoosts = spatialBoosts.merging(repeatBoosts) { max($0, $1) }

        var ranked = ranker.rank(
            typed: typed,
            previousWord: request.previousWord,
            sentenceContext: request.sentenceContext,
            spatialBoosts: combinedBoosts,
            candidates: generated
        )
            .filter { candidate in
                candidate.score >= minimumReplacementScore &&
                candidate.text.lowercased() != typed.lowercased()
            }
        if !ranked.isEmpty,
           !ranked.contains(where: { $0.text.lowercased() == typed.lowercased() }) {
            ranked.append(
                HWKRankedCorrection(
                    text: typed,
                    score: 0,
                    source: .verbatimTyped
                )
            )
        }

        return HWKCorrectionResult(
            original: request.typedWord,
            replacement: nil,
            candidates: ranked,
            reversible: true
        )
    }

    private func lexiconCandidates(for word: String) -> [HWKCorrectionCandidate] {
        lexicon.correctionCandidates(for: word, maxEditDistance: 2)
    }

    static func isSafeAutocorrectionReplacement(original: String, replacement: String) -> Bool {
        let normalizedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedOriginal.isEmpty,
              !normalizedReplacement.isEmpty,
              normalizedOriginal != normalizedReplacement else {
            return false
        }

        let originalWithoutApostrophes = normalizedOriginal.replacingOccurrences(of: "'", with: "")
        let replacementWithoutApostrophes = normalizedReplacement.replacingOccurrences(of: "'", with: "")
        guard originalWithoutApostrophes == replacementWithoutApostrophes else {
            return true
        }

        if normalizedOriginal.contains("'") {
            return true
        }

        return Self.unambiguousApostropheOnlyCorrections[normalizedOriginal] == normalizedReplacement
    }

    static func isProtectedCorrectionToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("http://") ||
            lowercased.hasPrefix("https://") ||
            lowercased.hasPrefix("www.") ||
            trimmed.contains("@") ||
            trimmed.contains("/") ||
            trimmed.contains("\\") ||
            trimmed.contains(":") {
            return true
        }

        if trimmed.contains(".") || trimmed.contains("_") {
            return true
        }

        let hasLetter = trimmed.contains { $0.isLetter }
        let hasDigit = trimmed.contains { $0.isNumber }
        return hasLetter && hasDigit
    }

    // MARK: - Touch-only spatial scoring (M08)

    /// Score bonus added to a candidate that differs from the typed word by a
    /// single physically-adjacent key substitution. Applied only for touch
    /// input; intentionally small so it nudges near-ties rather than overriding
    /// strong corrections.
    static let touchSpatialBoostMagnitude = 0.5

    /// Builds the per-candidate spatial boost map. Returns an empty map for any
    /// non-touch modality so hardware and unspecified input rank identically to
    /// behavior before this feature existed.
    static func touchSpatialBoosts(
        typed: String,
        candidates: [HWKCorrectionCandidate],
        modality: HWKInputModality
    ) -> [String: Double] {
        guard modality == .touch else { return [:] }

        let normalizedTyped = typed.lowercased()
        var boosts = [String: Double]()
        for candidate in candidates {
            let normalizedCandidate = candidate.text.lowercased()
            guard isSingleAdjacentKeySubstitution(from: normalizedTyped, to: normalizedCandidate) else {
                continue
            }
            boosts[normalizedCandidate] = max(boosts[normalizedCandidate] ?? 0, touchSpatialBoostMagnitude)
        }
        return boosts
    }

    /// True when `candidate` is `typed` with exactly one character replaced by a
    /// QWERTY-adjacent key (same length, one differing position).
    static func isSingleAdjacentKeySubstitution(from typed: String, to candidate: String) -> Bool {
        let typedCharacters = Array(typed)
        let candidateCharacters = Array(candidate)
        guard typedCharacters.count == candidateCharacters.count, !typedCharacters.isEmpty else {
            return false
        }

        var differingIndex: Int?
        for index in typedCharacters.indices where typedCharacters[index] != candidateCharacters[index] {
            if differingIndex != nil { return false }
            differingIndex = index
        }

        guard let index = differingIndex else { return false }
        return areKeysAdjacent(typedCharacters[index], candidateCharacters[index])
    }

    static func areKeysAdjacent(_ lhs: Character, _ rhs: Character) -> Bool {
        guard let neighbors = qwertyAdjacency[lhs] else { return false }
        return neighbors.contains(rhs)
    }

    /// Diagonal-inclusive QWERTY neighbor sets (lowercase letters only). Mirrors
    /// the row/column adjacency used by the on-screen layout's neighbor logic but
    /// kept self-contained and dependency-free for the correction engine.
    static let qwertyAdjacency: [Character: Set<Character>] = [
        "q": ["w", "a", "s"],
        "w": ["q", "e", "a", "s", "d"],
        "e": ["w", "r", "s", "d", "f"],
        "r": ["e", "t", "d", "f", "g"],
        "t": ["r", "y", "f", "g", "h"],
        "y": ["t", "u", "g", "h", "j"],
        "u": ["y", "i", "h", "j", "k"],
        "i": ["u", "o", "j", "k", "l"],
        "o": ["i", "p", "k", "l"],
        "p": ["o", "l"],
        "a": ["q", "w", "s", "z"],
        "s": ["q", "w", "e", "a", "d", "z", "x"],
        "d": ["w", "e", "r", "s", "f", "x", "c"],
        "f": ["e", "r", "t", "d", "g", "c", "v"],
        "g": ["r", "t", "y", "f", "h", "v", "b"],
        "h": ["t", "y", "u", "g", "j", "b", "n"],
        "j": ["y", "u", "i", "h", "k", "n", "m"],
        "k": ["u", "i", "o", "j", "l", "m"],
        "l": ["i", "o", "p", "k"],
        "z": ["a", "s", "x"],
        "x": ["s", "d", "z", "c"],
        "c": ["d", "f", "x", "v"],
        "v": ["f", "g", "c", "b"],
        "b": ["g", "h", "v", "n"],
        "n": ["h", "j", "b", "m"],
        "m": ["j", "k", "n"],
    ]

    // MARK: - Hardware-only repeat handling (M35)

    /// Score bonus added to a candidate that is the repeat-collapsed form of the
    /// typed word. Applied only for hardware input, where a held key emits an
    /// auto-repeat run that is a hardware artifact rather than a touch slip or a
    /// genuine spelling. Touch input never receives this signal, keeping the two
    /// input paths separate.
    static let hardwareRepeatBoostMagnitude = 0.6

    static func hardwareRepeatBoosts(
        typed: String,
        candidates: [HWKCorrectionCandidate],
        modality: HWKInputModality
    ) -> [String: Double] {
        guard modality == .hardware else { return [:] }

        let variants = repeatCollapsedVariants(typed.lowercased())
        guard !variants.isEmpty else { return [:] }

        var boosts = [String: Double]()
        for candidate in candidates {
            let normalizedCandidate = candidate.text.lowercased()
            guard variants.contains(normalizedCandidate) else { continue }
            boosts[normalizedCandidate] = max(boosts[normalizedCandidate] ?? 0, hardwareRepeatBoostMagnitude)
        }
        return boosts
    }

    /// Collapsed forms of `word` produced by reducing every maximal run of 3+
    /// identical characters down to one and to two characters (English rarely
    /// uses 3+ identical letters in a row). Returns an empty set when no long run
    /// exists, so words without held-key artifacts are untouched.
    static func repeatCollapsedVariants(_ word: String) -> Set<String> {
        let characters = Array(word)
        guard !characters.isEmpty else { return [] }

        var hasLongRun = false
        var index = 0
        while index < characters.count {
            var end = index
            while end < characters.count, characters[end] == characters[index] { end += 1 }
            if end - index >= 3 { hasLongRun = true }
            index = end
        }
        guard hasLongRun else { return [] }

        func collapse(maximumRun: Int) -> String {
            var output = [Character]()
            var index = 0
            while index < characters.count {
                var end = index
                while end < characters.count, characters[end] == characters[index] { end += 1 }
                let keep = min(end - index, maximumRun)
                output.append(contentsOf: Array(repeating: characters[index], count: keep))
                index = end
            }
            return String(output)
        }

        var variants: Set<String> = [collapse(maximumRun: 1), collapse(maximumRun: 2)]
        variants.remove(word)
        return variants
    }

    static func editDistance(_ left: String, _ right: String, maxDistance: Int = Int.max) -> Int {
        let lhs = Array(left)
        let rhs = Array(right)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for lhsIndex in 1...lhs.count {
            var current = [lhsIndex] + Array(repeating: 0, count: rhs.count)
            var rowMinimum = current[0]

            for rhsIndex in 1...rhs.count {
                let substitutionCost = lhs[lhsIndex - 1] == rhs[rhsIndex - 1] ? 0 : 1
                current[rhsIndex] = min(
                    previous[rhsIndex] + 1,
                    current[rhsIndex - 1] + 1,
                    previous[rhsIndex - 1] + substitutionCost
                )
                rowMinimum = min(rowMinimum, current[rhsIndex])
            }

            if rowMinimum > maxDistance { return rowMinimum }
            previous = current
        }

        return previous[rhs.count]
    }
}

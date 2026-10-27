import Foundation
import NaturalLanguage

enum HWKClauseBoundary: String, Equatable, Sendable {
    case none
    case soft
    case hard
}

struct HWKSentenceContext: Equatable, Sendable {
    static let beforeCharacterLimit = 192
    static let afterCharacterLimit = 96
    static let tokenLimit = 3
    static let structureTokenLimit = 6

    let beforeTokens: [String]
    let structureTokens: [String]
    let currentToken: String
    let afterTokens: [String]
    let isSentenceStart: Bool
    let clauseBoundary: HWKClauseBoundary
    let language: String
    let modality: HWKInputModality
    let boundedCharacterCount: Int

    var previousToken: String? { beforeTokens.last }

    init(
        contextBeforeInput: String,
        contextAfterInput: String,
        currentToken: String,
        language: String,
        modality: HWKInputModality
    ) {
        let boundedBefore = String(contextBeforeInput.suffix(Self.beforeCharacterLimit))
        let boundedAfter = String(contextAfterInput.prefix(Self.afterCharacterLimit))
        let normalizedCurrent = currentToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix: String
        if !normalizedCurrent.isEmpty,
           boundedBefore.lowercased().hasSuffix(normalizedCurrent.lowercased()) {
            prefix = String(boundedBefore.dropLast(normalizedCurrent.count))
        } else {
            prefix = boundedBefore
        }

        let nearestBoundary = Self.lastBoundary(in: prefix)
        let activeClause = nearestBoundary.map {
            String(prefix[prefix.index(after: $0.index)...])
        } ?? prefix
        let hardBoundary = Self.lastHardBoundary(in: prefix)
        let activeSentence = hardBoundary.map {
            String(prefix[prefix.index(after: $0)...])
        } ?? prefix
        let sentenceTokens = Self.wordTokens(in: activeSentence)

        let clauseTokens = Self.wordTokens(in: activeClause)
        self.beforeTokens = Array(clauseTokens.suffix(Self.tokenLimit))
        self.structureTokens = Array(clauseTokens.suffix(Self.structureTokenLimit))
        self.currentToken = normalizedCurrent.lowercased()
        self.afterTokens = Array(Self.wordTokens(in: boundedAfter).prefix(Self.tokenLimit))
        self.isSentenceStart = sentenceTokens.isEmpty
        self.clauseBoundary = nearestBoundary?.kind ?? .none
        self.language = language
        self.modality = modality
        self.boundedCharacterCount = boundedBefore.count + boundedAfter.count
    }

    private static func wordTokens(in text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens = [String]()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).lowercased()
            if token.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) {
                tokens.append(token)
            }
            return true
        }
        return tokens
    }

    private static func lastBoundary(in text: String) -> (index: String.Index, kind: HWKClauseBoundary)? {
        for index in text.indices.reversed() {
            switch text[index] {
            case ".", "!", "?", "\n":
                return (index, .hard)
            case ",", ";", ":", "—", "–":
                return (index, .soft)
            default:
                continue
            }
        }
        return nil
    }

    private static func lastHardBoundary(in text: String) -> String.Index? {
        text.indices.reversed().first { index in
            switch text[index] {
            case ".", "!", "?", "\n":
                return true
            default:
                return false
            }
        }
    }
}

enum HWKRankingReason: String, Equatable, Hashable, Sendable {
    case sourceAgreement
    case subjectVerbAgreement
    case auxiliaryPredicateFit
    case followingContextFit
    case sentenceBoundaryReset
}

struct HWKSentenceStructureScore: Equatable, Sendable {
    let grammar: Double
    let structure: Double
    let reasonCodes: Set<HWKRankingReason>

    var total: Double { grammar + structure }

    static let neutral = HWKSentenceStructureScore(
        grammar: 0,
        structure: 0,
        reasonCodes: []
    )
}

enum HWKSentenceStructureScorer {
    private static let beForms: Set<String> = ["am", "is", "are", "was", "were", "be", "been", "being"]

    static func score(candidate: String, in context: HWKSentenceContext) -> HWKSentenceStructureScore {
        let language = context.language.lowercased()
        guard language == "und" || language == "en" || language.hasPrefix("en-") else {
            return .neutral
        }
        guard let candidateHead = candidate
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
            .first
            .map(String.init),
            !candidateHead.isEmpty else {
            return .neutral
        }

        var grammar = 0.0
        var structure = 0.0
        var reasons = Set<HWKRankingReason>()
        let previous = context.previousToken
        let next = context.afterTokens.first

        if let agreement = agreementScore(
            beforeTokens: context.structureTokens,
            candidate: candidateHead
        ) {
            grammar += agreement
            if agreement > 0 {
                reasons.insert(.subjectVerbAgreement)
            }
        }

        if previous == "there",
           let followingAgreement = agreementScore(
               beforeTokens: context.afterTokens,
               candidate: candidateHead
           ) {
            grammar += followingAgreement
            if followingAgreement > 0 {
                reasons.insert(.followingContextFit)
            }
        }

        if let next, next.hasSuffix("ing") {
            if beForms.contains(candidateHead) {
                structure += 0.24
                reasons.insert(.followingContextFit)
            } else {
                structure -= 0.18
            }
        }

        if let previous, beForms.contains(previous), candidateHead.hasSuffix("ing") {
            structure += 0.42
            reasons.insert(.auxiliaryPredicateFit)
        }

        return HWKSentenceStructureScore(
            grammar: grammar,
            structure: structure,
            reasonCodes: reasons
        )
    }

    private static func agreementScore(beforeTokens: [String], candidate: String) -> Double? {
        guard let subject = agreementHead(in: beforeTokens) else { return nil }
        let expected: Set<String>
        let incompatible: Set<String>
        switch subject {
        case "i":
            expected = ["am", "was", "have", "do"]
            incompatible = ["is", "are", "were", "has", "does"]
        case "you", "we", "they", "these", "those":
            expected = ["are", "were", "have", "do"]
            incompatible = ["am", "is", "was", "has", "does"]
        case "he", "she", "it", "this", "that":
            expected = ["is", "was", "has", "does"]
            incompatible = ["am", "are", "were", "have", "do"]
        case "one", "each", "every", "either", "neither":
            expected = ["is", "was", "has", "does"]
            incompatible = ["am", "are", "were", "have", "do"]
        case "many", "several", "both", "few":
            expected = ["are", "were", "have", "do"]
            incompatible = ["am", "is", "was", "has", "does"]
        default:
            let determiners: Set<String> = ["a", "an", "the", "each", "every", "one"]
            let hasDeterminer = beforeTokens.dropLast().contains { determiners.contains($0) }
            let hasPluralShape = isLikelyPlural(subject)
            guard hasDeterminer || hasPluralShape else { return nil }

            if hasPluralShape {
                expected = ["are", "were", "have", "do"]
                incompatible = ["am", "is", "was", "has", "does"]
            } else {
                expected = ["is", "was", "has", "does"]
                incompatible = ["am", "are", "were", "have", "do"]
            }
        }

        if expected.contains(candidate) { return 0.62 }
        if incompatible.contains(candidate) { return -0.48 }
        return nil
    }

    private static func isLikelyPlural(_ word: String) -> Bool {
        let irregularPlurals: Set<String> = [
            "children", "feet", "geese", "men", "mice", "people", "teeth", "women",
        ]
        if irregularPlurals.contains(word) { return true }

        let singularSForms: Set<String> = [
            "atlas", "bias", "chaos", "gas", "mathematics", "news", "physics", "series", "species",
        ]
        if singularSForms.contains(word) || word.hasSuffix("ss") || word.hasSuffix("us") || word.hasSuffix("is") {
            return false
        }

        return word.count > 2 && word.hasSuffix("s")
    }

    private static func agreementHead(in tokens: [String]) -> String? {
        guard let nearest = tokens.last else { return nil }

        if tokens.dropLast().last == "and" {
            return "they"
        }

        if let ofIndex = tokens.lastIndex(of: "of"),
           ofIndex > tokens.startIndex,
           tokens.distance(from: ofIndex, to: tokens.endIndex) <= 4 {
            return tokens[tokens.index(before: ofIndex)]
        }

        return nearest
    }
}

struct HWKCorrectionCandidate: Equatable {
    let text: String
    let editDistance: Int
    let frequency: Double
    let source: HWKCorrectionSource
}

enum HWKCorrectionSource: String, Equatable, Hashable, Sendable {
    case savedWords
    case lexicon
    case nativeSpellChecker
    case foundationModel
    case coreML
    case verbatimTyped
}

struct HWKCandidateEvidence: Equatable, Sendable {
    let source: HWKCorrectionSource
    let sourceScore: Double
    let editCost: Double
    let contextScore: Double
    let grammarScore: Double
    let structureScore: Double
    let spatialScore: Double
}

struct HWKRankedCorrection: Equatable {
    let text: String
    let score: Double
    let source: HWKCorrectionSource
    let evidence: [HWKCandidateEvidence]
    let reasonCodes: Set<HWKRankingReason>
    let decisionConfidence: Double?

    var sourceAgreementCount: Int {
        Set(evidence.map(\.source)).count
    }

    init(
        text: String,
        score: Double,
        source: HWKCorrectionSource,
        evidence: [HWKCandidateEvidence] = [],
        reasonCodes: Set<HWKRankingReason> = [],
        decisionConfidence: Double? = nil
    ) {
        self.text = text
        self.score = score
        self.source = source
        self.evidence = evidence
        self.reasonCodes = reasonCodes
        self.decisionConfidence = decisionConfidence
    }
}

struct HWKCandidateRanker {
    private let bigramModel: HWKBigramModel
    private let rankingMethod: KeyboardAutocorrectRankingMethod
    private let logicBlocks: [KeyboardAutocorrectLogicBlock]

    init(
        bigramModel: HWKBigramModel = HWKBigramModel(),
        rankingMethod: KeyboardAutocorrectRankingMethod = .balanced,
        logicBlocks: [KeyboardAutocorrectLogicBlock] = []
    ) {
        self.bigramModel = bigramModel
        self.rankingMethod = rankingMethod
        self.logicBlocks = logicBlocks
    }

    func rank(
        typed: String,
        previousWord: String?,
        sentenceContext: HWKSentenceContext? = nil,
        previousRailTexts: [String] = [],
        spatialBoosts: [String: Double] = [:],
        personalization: HWKFTRLPersonalizer? = nil,
        language: String = "und",
        modality: HWKPersonalizationInputModality = .touch,
        languageBrain: HWKLanguageBrainSnapshot? = nil,
        candidates: [HWKCorrectionCandidate]
    ) -> [HWKRankedCorrection] {
        let normalizedTyped = typed.lowercased()
        let effectivePreviousWord = sentenceContext == nil
            ? previousWord
            : sentenceContext?.previousToken
        let didResetStaleBoundary = sentenceContext != nil &&
            previousWord?.lowercased() != effectivePreviousWord?.lowercased()
        let previousRailBoosts = hysteresisBoosts(for: previousRailTexts)
        let languageBrainRuntime = languageBrain.map(HWKLanguageBrainRuntime.init(snapshot:))
        var bestByText: [String: HWKRankedCorrection] = [:]
        var evidenceByText: [String: [HWKCandidateEvidence]] = [:]
        var reasonsByText: [String: Set<HWKRankingReason>] = [:]

        for candidate in candidates {
            if languageBrainRuntime?.shouldSuppressReplacement(
                original: typed,
                replacement: candidate.text
            ) == true {
                continue
            }
            let normalizedCandidate = candidate.text.lowercased()
            let distancePenalty = Double(candidate.editDistance) * distancePenaltyWeight(for: candidate.source)
            let bigramScore = bigramModel.score(previous: effectivePreviousWord, candidate: normalizedCandidate)
            let identityBoost = normalizedCandidate == normalizedTyped ? 1.0 : 0
            let correctionBoost = correctionIntentBoost(
                typed: normalizedTyped,
                candidate: normalizedCandidate,
                source: candidate.source,
                editDistance: candidate.editDistance
            )
            let sentenceScore = sentenceContext.map {
                HWKSentenceStructureScorer.score(candidate: candidate.text, in: $0)
            } ?? .neutral
            let spatialScore = spatialBoosts[normalizedCandidate] ?? 0
            let score = score(
                for: candidate,
                bigramScore: bigramScore,
                identityBoost: identityBoost,
                correctionBoost: correctionBoost,
                distancePenalty: distancePenalty
            ) + sourceWeightBoost(for: candidate.source)
                + (previousRailBoosts[normalizedCandidate] ?? 0)
                + spatialScore
                + sentenceScore.total
                + personalizationAdjustment(
                    personalization,
                    language: language,
                    modality: modality,
                    candidate: candidate
                )
                + (languageBrainRuntime?.scoreAdjustment(
                    typed: typed,
                    candidate: candidate.text
                ) ?? 0)
            let evidence = HWKCandidateEvidence(
                source: candidate.source,
                sourceScore: candidate.frequency,
                editCost: distancePenalty,
                contextScore: bigramScore,
                grammarScore: sentenceScore.grammar,
                structureScore: sentenceScore.structure,
                spatialScore: spatialScore
            )
            evidenceByText[normalizedCandidate, default: []].append(evidence)
            reasonsByText[normalizedCandidate, default: []].formUnion(sentenceScore.reasonCodes)
            if didResetStaleBoundary {
                reasonsByText[normalizedCandidate, default: []].insert(.sentenceBoundaryReset)
            }
            let ranked = HWKRankedCorrection(
                text: candidate.text,
                score: score,
                source: candidate.source
            )

            if let existing = bestByText[normalizedCandidate], existing.score >= score {
                continue
            }
            bestByText[normalizedCandidate] = ranked
        }

        let fused = bestByText.map { normalizedCandidate, best -> HWKRankedCorrection in
            let evidence = evidenceByText[normalizedCandidate] ?? []
            let agreementCount = Set(evidence.map(\.source)).count
            let agreementBoost = agreementCount > 1
                ? min(0.30, Double(agreementCount - 1) * 0.12)
                : 0
            var reasons = reasonsByText[normalizedCandidate] ?? []
            if agreementCount > 1 {
                reasons.insert(.sourceAgreement)
            }
            return HWKRankedCorrection(
                text: best.text,
                score: best.score + agreementBoost,
                source: best.source,
                evidence: evidence,
                reasonCodes: reasons,
                decisionConfidence: nil
            )
        }
        let sorted = fused.sorted {
            if $0.score == $1.score { return $0.text < $1.text }
            return $0.score > $1.score
        }
        guard let threshold = acceptanceThreshold(), threshold > 0 else {
            return sorted
        }

        return sorted.filter { gateValue(for: $0.score) >= threshold }
    }

    private func hysteresisBoosts(for previousRailTexts: [String]) -> [String: Double] {
        var boosts = [String: Double]()
        for (index, text) in previousRailTexts.enumerated() {
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, boosts[normalized] == nil else { continue }
            boosts[normalized] = max(0.02, 0.06 - (Double(index) * 0.01))
        }
        return boosts
    }

    private func distancePenaltyWeight(for source: HWKCorrectionSource) -> Double {
        switch source {
        case .nativeSpellChecker:
            switch rankingMethod {
            case .balanced:
                return 0.25
            case .correctionFirst:
                return 0.18
            case .frequencyFirst:
                return 0.55
            }
        case .savedWords, .lexicon, .foundationModel, .coreML, .verbatimTyped:
            switch rankingMethod {
            case .balanced:
                return 0.35
            case .correctionFirst:
                return 0.3
            case .frequencyFirst:
                return 0.35
            }
        }
    }

    private func score(
        for candidate: HWKCorrectionCandidate,
        bigramScore: Double,
        identityBoost: Double,
        correctionBoost: Double,
        distancePenalty: Double
    ) -> Double {
        switch rankingMethod {
        case .balanced:
            return candidate.frequency + bigramScore + bonus(for: candidate.source) + identityBoost + correctionBoost - distancePenalty
        case .correctionFirst:
            return candidate.frequency +
                (bigramScore * 0.8) +
                bonus(for: candidate.source) +
                identityBoost +
                (correctionBoost * 1.4) -
                distancePenalty
        case .frequencyFirst:
            return candidate.frequency +
                (bigramScore * 0.35) +
                (bonus(for: candidate.source) * 0.2) +
                (identityBoost * 0.5) +
                (correctionBoost * 0.1) -
                distancePenalty
        }
    }

    private func bonus(for source: HWKCorrectionSource) -> Double {
        switch source {
        case .savedWords:
            return 0.06
        case .lexicon:
            return 0.05
        case .nativeSpellChecker:
            return 0.03
        case .foundationModel:
            return 0.01
        case .coreML:
            return 0.02
        case .verbatimTyped:
            return 0
        }
    }

    private func correctionIntentBoost(
        typed: String,
        candidate: String,
        source: HWKCorrectionSource,
        editDistance: Int
    ) -> Double {
        guard typed != candidate, editDistance > 0 else { return 0 }

        switch source {
        case .nativeSpellChecker, .foundationModel, .coreML:
            return 1.75
        case .savedWords, .lexicon, .verbatimTyped:
            return 0
        }
    }

    private func sourceWeightBoost(for source: HWKCorrectionSource) -> Double {
        guard let ranker = logicBlocks.first(where: { $0.kind == .weightedRanker }) else {
            return 0
        }

        switch source {
        case .savedWords:
            return ranker.savedWordsWeight
        case .lexicon:
            return ranker.dictionaryWeight
        case .nativeSpellChecker:
            return 0.2
        case .foundationModel:
            return 0.1
        case .coreML:
            return 0.15
        case .verbatimTyped:
            return 0
        }
    }

    private func acceptanceThreshold() -> Double? {
        logicBlocks
            .filter { $0.role == .gate }
            .map(\.acceptanceThreshold)
            .max()
    }

    private func gateValue(for score: Double) -> Double {
        min(max((score + 1.0) / 4.0, 0), 1)
    }

    private func personalizationAdjustment(
        _ personalization: HWKFTRLPersonalizer?,
        language: String,
        modality: HWKPersonalizationInputModality,
        candidate: HWKCorrectionCandidate
    ) -> Double {
        guard let personalization else { return 0 }
        let bucket: HWKConfidenceBucket = candidate.frequency >= 0.7 ? .high : candidate.frequency >= 0.35 ? .medium : .low
        let family: HWKCandidateSourceFamily
        switch candidate.source {
        case .lexicon, .savedWords, .verbatimTyped: family = .lexicon
        case .nativeSpellChecker: family = .native
        case .foundationModel, .coreML: family = .rule
        }
        return personalization.adjustment(for: .init(language: language, modality: modality, confidenceBucket: bucket, sourceFamily: family))
    }
}

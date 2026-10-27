import Foundation

enum HWKPersonalizationInputModality: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case touch
    case hardware
}

enum HWKConfidenceBucket: String, Codable, Sendable { case low, medium, high }
enum HWKCandidateSourceFamily: String, Codable, Sendable { case lexicon, rule, native }

struct HWKPersonalizationContext: Equatable, Sendable {
    var language: String
    var modality: HWKPersonalizationInputModality
    var confidenceBucket: HWKConfidenceBucket
    var sourceFamily: HWKCandidateSourceFamily
    var featureKeys: [String] {
        [
            "lang:" + language,
            "modality:" + modality.rawValue,
            "confidence:" + confidenceBucket.rawValue,
            "source:" + sourceFamily.rawValue,
        ]
    }
}

struct HWKFTRLPersonalizer: Codable, Equatable, Sendable {
    private var z: [String: Double] = [:]
    private var n: [String: Double] = [:]
    static let standard = HWKFTRLPersonalizer()
    var featureCount: Int { z.count }
    var featureKeys: [String] { Array(z.keys) }
    var isValid: Bool {
        z.count <= 64
            && n.count <= 64
            && Set(z.keys) == Set(n.keys)
            && z.allSatisfy { key, value in
                !key.isEmpty && key.count <= 128 && value.isFinite
            }
            && n.allSatisfy { key, value in
                !key.isEmpty && key.count <= 128 && value.isFinite && value >= 0
            }
    }

    mutating func observe(context: HWKPersonalizationContext, accepted: Bool) {
        let label = accepted ? 1.0 : 0.0
        let prediction = 1 / (1 + exp(-score(context: context)))
        let gradient = prediction - label
        for key in context.featureKeys.prefix(4) {
            guard z[key] != nil || z.count < 64 else { continue }
            let priorN = n[key] ?? 0
            let weight = weight(for: key)
            z[key, default: 0] += gradient
                - ((sqrt(priorN + gradient * gradient) - sqrt(priorN)) / 0.15) * weight
            n[key, default: 0] += gradient * gradient
        }
    }

    func adjustment(for context: HWKPersonalizationContext) -> Double {
        min(0.08, max(-0.08, score(context: context) * 0.04))
    }

    private func score(context: HWKPersonalizationContext) -> Double {
        context.featureKeys.reduce(0) { $0 + weight(for: $1) }
    }

    private func weight(for key: String) -> Double {
        let zi = z[key] ?? 0
        let ni = n[key] ?? 0
        return abs(zi) <= 0.5
            ? 0
            : -(zi - (zi < 0 ? -0.5 : 0.5)) / ((1 + sqrt(ni)) / 0.15 + 1)
    }
}

enum HWKPromotionDecision: Equatable { case hold, promote, rollback }

struct HWKChampionChallengerGate: Equatable {
    private var samples = 0
    private var championAccepts = 0
    private var challengerAccepts = 0
    private var championUndos = 0
    private var challengerUndos = 0

    mutating func observe(
        championAccepted: Bool,
        challengerAccepted: Bool,
        championUndone: Bool,
        challengerUndone: Bool
    ) {
        samples += 1
        championAccepts += championAccepted ? 1 : 0
        challengerAccepts += challengerAccepted ? 1 : 0
        championUndos += championUndone ? 1 : 0
        challengerUndos += challengerUndone ? 1 : 0
    }

    var decision: HWKPromotionDecision {
        guard samples >= 30 else { return .hold }
        if challengerUndos > championUndos { return .rollback }
        return Double(challengerAccepts - championAccepts) / Double(samples) >= 0.03
            ? .promote
            : .hold
    }
}

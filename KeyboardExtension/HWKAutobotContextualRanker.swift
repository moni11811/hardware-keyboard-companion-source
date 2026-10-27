import Foundation

struct HWKAutobotWordScore: Equatable, Sendable {
    let word: String
    let logProbability: Double
}

enum HWKAutobotContextualRanker {
    /// Conservative candidate-only adjustment. Never authorizes a text mutation.
    static func adjustment(for word: String, logits: [String: Double]) -> Double {
        let finite = logits.values.filter(\.isFinite)
        guard !finite.isEmpty, let value = logits[word.lowercased()], value.isFinite else { return 0 }
        let center = finite.reduce(0, +) / Double(finite.count)
        return min(0.25, max(-0.25, (value - center) * 0.10))
    }

    static func candidates(logits: [Float], tokenizer: HWKAutobotTokenizer, prefix: String, limit: Int = 24) throws -> [HWKAutobotWordScore] {
        guard logits.count == tokenizer.vocabulary.count, logits.allSatisfy(\.isFinite),
              let maximum = logits.dropFirst(4).max() else { throw HWKAutobotError.invalidOutput }
        // Special tokens never compete with actual words on the keyboard surface.
        let normalizer = Double(maximum) + log(logits.dropFirst(4).reduce(0.0) { $0 + exp(Double($1 - maximum)) })
        let normalizedPrefix = prefix.precomposedStringWithCanonicalMapping.lowercased().replacingOccurrences(of: "’", with: "'")
        return logits.indices.dropFirst(4).filter {
            let word = tokenizer.vocabulary[$0]
            return word.count <= 40 && word.hasPrefix(normalizedPrefix) && word != normalizedPrefix
        }.sorted {
            logits[$0] == logits[$1] ? $0 < $1 : logits[$0] > logits[$1]
        }.prefix(max(0, min(24, limit))).map {
            HWKAutobotWordScore(word: tokenizer.vocabulary[$0], logProbability: Double(logits[$0]) - normalizer)
        }
    }
}

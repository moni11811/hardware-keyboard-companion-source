import Foundation

/// Recalls phrases already present in the exposed field. Nothing is retained
/// between requests, and punctuation prevents phrases crossing sentence breaks.
enum HWKFieldPhrasePredictions {
    struct Candidate {
        let word: String
        let hasStrongContext: Bool
    }
    private struct Word {
        let text: String
        var normalized: String { text.lowercased() }
    }

    private static let functionWords: Set<String> = [
        "a", "an", "the", "to", "of", "in", "on", "at", "for", "and", "or", "is", "are", "was", "were", "be", "by", "with"
    ]

    static func candidates(before: String, after: String, isSensitive: Bool = false, limit: Int = 3) -> [String] {
        predictions(before: before, after: after, isSensitive: isSensitive, limit: limit).map(\.word)
    }

    static func predictions(before: String, after: String, isSensitive: Bool = false, limit: Int = 3) -> [Candidate] {
        guard !isSensitive, limit > 0, before.last?.isWhitespace == true,
              after.first.map(\.isWhitespace) ?? true else { return [] }
        let beforeWindow = bounded(before, suffix: true)
        let afterWindow = bounded(after, suffix: false)
        let preceding = sentences(beforeWindow)
        let following = sentences(afterWindow)
        guard let query = preceding.last, !query.isEmpty else { return [] }
        let left = Array(query.suffix(8)).map(\.normalized)
        let right = Array((following.first ?? []).prefix(2)).map(\.normalized)
        var matches = [String: (word: String, left: Int, right: Int, count: Int, order: Int)]()
        var order = 0
        for sentence in preceding + following {
            for index in sentence.indices.dropFirst() {
                order += 1
                let candidate = sentence[index]
                guard candidate.normalized != right.first else { continue }
                var leftCount = 0
                while leftCount < min(left.count, index),
                      left[left.count - leftCount - 1] == sentence[index - leftCount - 1].normalized {
                    leftCount += 1
                }
                guard leftCount > 0 else { continue }
                var rightCount = 0
                while rightCount < right.count, index + 1 + rightCount < sentence.count,
                      right[rightCount] == sentence[index + 1 + rightCount].normalized {
                    rightCount += 1
                }
                let key = candidate.normalized
                if let prior = matches[key] {
                    let stronger = leftCount * 3 + rightCount * 4 >= prior.left * 3 + prior.right * 4
                    matches[key] = (stronger ? candidate.text : prior.word,
                                    stronger ? leftCount : prior.left, stronger ? rightCount : prior.right,
                                    prior.count + 1, order)
                } else if matches.count < 64 {
                    matches[key] = (candidate.text, leftCount, rightCount, 1, order)
                }
            }
        }
        return matches.values.filter { match in
            match.right > 0 || match.count >= 2 ||
                left.suffix(match.left).contains(where: { !functionWords.contains($0) })
        }.sorted {
            let lhs = $0.left * 3 + $0.right * 4 + min($0.count, 3)
            let rhs = $1.left * 3 + $1.right * 4 + min($1.count, 3)
            return lhs == rhs ? $0.order > $1.order : lhs > rhs
        }.prefix(min(limit, 3)).map {
            Candidate(word: $0.word, hasStrongContext: $0.left >= 2 || $0.right > 0 || $0.count >= 2)
        }
    }

    private static func bounded(_ text: String, suffix: Bool) -> String {
        let byteWindow = suffix ? Array(text.utf8.suffix(8_192)) : Array(text.utf8.prefix(8_192))
        let decoded = String(decoding: byteWindow, as: UTF8.self)
        var result = suffix ? String(decoded.suffix(2_048)) : String(decoded.prefix(2_048))
        if result.utf8.count < text.utf8.count {
            result = suffix ? String(result.drop(while: { !$0.isWhitespace }))
                : String(result.reversed().drop(while: { !$0.isWhitespace }).reversed())
        }
        return result
    }

    private static func sentences(_ text: String) -> [[Word]] {
        let trim = CharacterSet(charactersIn: ".,!?;:()[]{}\"“”‘’")
        var result = [[Word]](), current = [Word]()
        for chunk in text.replacingOccurrences(of: "\n", with: " ; ").replacingOccurrences(of: "\r", with: " ; ").split(whereSeparator: \.isWhitespace) {
            let word = String(chunk).trimmingCharacters(in: trim)
            let isWord = (1...32).contains(word.count) && word.first?.isLetter == true && word.last?.isLetter == true &&
                word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }) &&
                (word == word.lowercased() || word == word.uppercased() || String(word.dropFirst()) == String(word.dropFirst()).lowercased())
            if isWord { current.append(Word(text: word)) }
            if !isWord || chunk.contains(where: { ".!?;:".contains($0) }) {
                result.append(current)
                current = []
            }
        }
        result.append(current)
        return result
    }
}

/// Transient candidates from the text the host exposes. Extraction does not
/// persist field contents; explicit acceptance follows normal learning controls.
enum HWKFieldWordCompletions {
    static let maximumContextCharactersPerSide = 2_048

    static func acceptsPrefix(
        before: String, after: String, prefix: String,
        lengthRange: ClosedRange<Int> = 2...20
    ) -> Bool {
        guard lengthRange.contains(prefix.count), prefix.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }),
              before.hasSuffix(prefix),
              after.first.map({ !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }) ?? true else { return false }
        let leading = before.dropLast(prefix.count).last
        return leading.map { $0.isWhitespace || "([{\"“‘".contains($0) } ?? true
    }

    static func candidates(before: String, after: String, prefix: String, isSensitive: Bool = false, limit: Int = 3) -> [String] {
        guard !isSensitive, limit > 0, acceptsPrefix(before: before, after: after, prefix: prefix) else { return [] }
        // Bound bytes as well as characters before examining host-provided text.
        let preceding = String(before.dropLast(prefix.count))
        var beforeWindow = String(String(decoding: preceding.utf8.suffix(8_192), as: UTF8.self).suffix(maximumContextCharactersPerSide))
        var afterWindow = String(String(decoding: after.utf8.prefix(8_192), as: UTF8.self).prefix(maximumContextCharactersPerSide))
        if beforeWindow.utf8.count < preceding.utf8.count {
            beforeWindow = String(beforeWindow.drop(while: { !$0.isWhitespace }))
        }
        if afterWindow.utf8.count < after.utf8.count {
            afterWindow = String(afterWindow.reversed().drop(while: { !$0.isWhitespace }).reversed())
        }
        let chunks = Array(beforeWindow.split(whereSeparator: \.isWhitespace).reversed()) + afterWindow.split(whereSeparator: \.isWhitespace)
        let punctuation = CharacterSet(charactersIn: ".,!?;:()[]{}\"“”‘’")
        let normalizedPrefix = prefix.lowercased()
        var matches = [String: (word: String, count: Int, order: Int)]()
        for (index, chunk) in chunks.enumerated() {
            let word = String(chunk).trimmingCharacters(in: punctuation)
            let normalized = word.lowercased()
            guard (3...32).contains(word.count), normalized != normalizedPrefix, normalized.hasPrefix(normalizedPrefix),
                  word.first?.isLetter == true, word.last?.isLetter == true,
                  word.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "’" }),
                  word == normalized || word == word.uppercased() || String(word.dropFirst()) == String(word.dropFirst()).lowercased() else { continue }
            if var existing = matches[normalized] {
                existing.count += 1
                matches[normalized] = existing
            } else if matches.count < 64 {
                matches[normalized] = (word, 1, index)
            }
        }
        return matches.values.sorted {
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.order < $1.order
        }.prefix(min(limit, 3)).map(\.word)
    }
}

struct HWKPredictionRequest: Equatable {
    let prefix: String
    let previousWord: String?
    let casingContext: HWKSmartCasingContext
    let isSecureTextEntry: Bool

    init(
        prefix: String,
        previousWord: String? = nil,
        casingContext: HWKSmartCasingContext,
        isSecureTextEntry: Bool = false
    ) {
        self.prefix = prefix
        self.previousWord = previousWord
        self.casingContext = casingContext
        self.isSecureTextEntry = isSecureTextEntry
    }
}

struct HWKPredictionCandidate: Equatable {
    let text: String
    let score: Double
}

struct HWKPredictionEngine {
    private let lexicon: HWKLexiconStore
    private let userDictionary: HWKUserDictionary
    private let bigramModel: HWKBigramModel
    private let smartCasing: HWKSmartCasing

    init(
        lexicon: HWKLexiconStore = HWKLexiconStore(),
        userDictionary: HWKUserDictionary = HWKUserDictionary(),
        bigramModel: HWKBigramModel = HWKBigramModel(),
        smartCasing: HWKSmartCasing = HWKSmartCasing()
    ) {
        self.lexicon = lexicon
        self.userDictionary = userDictionary
        self.bigramModel = bigramModel
        self.smartCasing = smartCasing
    }

    func predictions(for request: HWKPredictionRequest, limit: Int = 3) -> [HWKPredictionCandidate] {
        guard !request.isSecureTextEntry else { return [] }
        let prefix = request.prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty else { return [] }

        let casingMode = smartCasing.mode(for: request.casingContext)
        var scored: [String: HWKPredictionCandidate] = [:]

        for entry in lexicon.candidates(matching: prefix) {
            insert(entry.word, score: entry.frequency + bigramModel.score(previous: request.previousWord, candidate: entry.word), mode: casingMode, into: &scored)
        }

        for entry in userDictionary.entries(matching: prefix) {
            insert(entry.term, score: entry.weight + 0.2, mode: casingMode, into: &scored)
        }

        return scored.values.sorted {
            if $0.score == $1.score { return $0.text < $1.text }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private func insert(
        _ text: String,
        score: Double,
        mode: HWKCasingMode,
        into scored: inout [String: HWKPredictionCandidate]
    ) {
        let cased = smartCasing.apply(mode, to: text)
        let key = cased.lowercased()
        let candidate = HWKPredictionCandidate(text: cased, score: score)
        if let existing = scored[key], existing.score >= score {
            return
        }
        scored[key] = candidate
    }
}

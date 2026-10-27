import Foundation

enum HWKAutobotError: Error {
    case invalidVocabulary, invalidManifest, invalidOutput, unavailable, unqualified
}

struct HWKAutobotTokenizer: Sendable {
    static let contextLength = 128
    let vocabulary: [String]
    private let lookup: [String: Int32]
    private static let expression = try! NSRegularExpression(pattern: "[\\p{L}\\p{Nl}\\p{No}]+(?:'[\\p{L}\\p{Nl}\\p{No}]+)*|[.!?]|\\p{Nd}+")

    init(vocabulary: [String]) throws {
        guard Array(vocabulary.prefix(4)) == ["<pad>", "<unk>", "<bos>", "<eos>"],
              vocabulary.count <= 8192,
              Set(vocabulary).count == vocabulary.count,
              vocabulary.dropFirst(4).allSatisfy({ !$0.isEmpty && Self.tokens($0) == [$0] }) else {
            throw HWKAutobotError.invalidVocabulary
        }
        self.vocabulary = vocabulary
        lookup = Dictionary(uniqueKeysWithValues: vocabulary.enumerated().map { ($0.element, Int32($0.offset)) })
    }

    static func tokens(_ text: String) -> [String] {
        let normalized = text.precomposedStringWithCanonicalMapping.lowercased()
            .replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "‘", with: "'")
        return expression.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)).compactMap { match in
            guard let range = Range(match.range, in: normalized) else { return nil }
            let token = String(normalized[range])
            if [".", "!", "?"].contains(token) { return "<eos>" }
            if token.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) { return "<unk>" }
            return token
        }
    }

    func encode(_ text: String) -> [Int32] {
        let ids = Array(([Int32(2)] + Self.tokens(String(text.suffix(4096))).map { lookup[$0] ?? 1 }).suffix(Self.contextLength))
        return Array(repeating: 0, count: Self.contextLength - ids.count) + ids
    }

    func id(for word: String) -> Int? { lookup[word.lowercased()].map(Int.init) }
}

struct HWKAutobotContext: Equatable, Sendable {
    let before: String
    let after: String
    let document: String
    let hostGeneration: UInt64
    let language: String
    let prefix: String

    init(before: String, after: String, document: String, hostGeneration: UInt64, language: String) {
        self.before = String(before.suffix(4096))
        self.after = String(after.prefix(512))
        self.document = document
        self.hostGeneration = hostGeneration
        self.language = language
        prefix = String(self.before.reversed().prefix { $0.isLetter || $0 == "'" || $0 == "’" }.reversed())
    }

    var modelContext: String { String(before.dropLast(prefix.count)) }
}

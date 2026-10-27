import Foundation

/// Compact public-corpus counts. No user text or history is stored in this model.
struct HWKLocalContextModel {
    struct Prediction {
        let word: String
        let score: Double
    }
    private struct Entry {
        let word: Int
        let weight: Float
    }
    static let bundled: HWKLocalContextModel = {
        let bundles = [Bundle.main, Bundle(for: BundleToken.self)]
        for bundle in bundles {
            if let url = bundle.url(forResource: "HWKEnglishContext", withExtension: "tsv"),
               let text = try? String(contentsOf: url, encoding: .utf8) {
                return HWKLocalContextModel(table: text)
            }
        }
        return HWKLocalContextModel(table: "")
    }()
    private final class BundleToken {}
    private let words: [String]
    private let contexts: [String: [Entry]]
    var contextCount: Int { contexts.count }

    init(table: String) {
        var words = [String](), wordIDs = [String: Int](), contexts = [String: [Entry]]()
        for line in table.split(separator: "\n").prefix(24_001) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count == 3, let total = Float(fields[1]), total >= 3,
                  fields[0].split(separator: " ").count <= 3 else { continue }
            let entries = fields[2].split(separator: " ").prefix(6).compactMap { value -> Entry? in
                let pair = value.split(separator: ":")
                guard pair.count == 2, let count = Float(pair[1]), count > 0, count <= total else { return nil }
                let word = String(pair[0])
                guard Self.isWord(word) else { return nil }
                let id: Int
                if let existing = wordIDs[word] { id = existing } else {
                    id = words.count
                    wordIDs[word] = id
                    words.append(word)
                }
                return Entry(word: id, weight: count / (total + 5))
            }
            if !entries.isEmpty { contexts[String(fields[0])] = entries }
        }
        self.words = words
        self.contexts = contexts
    }

    func predictions(before: String, after: String = "", prefix: String = "", limit: Int = 6) -> [Prediction] {
        guard limit > 0, after.first.map({ !$0.isLetter && !$0.isNumber && $0 != "'" && $0 != "’" }) ?? true,
              prefix.isEmpty || (Self.isWord(prefix.lowercased().replacingOccurrences(of: "’", with: "'")) && before.hasSuffix(prefix)) else { return [] }
        let preceding = prefix.isEmpty ? before : String(before.dropLast(prefix.count))
        guard preceding.last?.isWhitespace == true else { return [] }
        // Byte bounding comes first, so a single very long grapheme stays bounded.
        var window = String(decoding: preceding.utf8.suffix(1_024), as: UTF8.self)
        if preceding.utf8.count > 1_024 { window = String(window.drop(while: { !$0.isWhitespace })) }
        window = window.replacingOccurrences(of: "\n", with: " ; ").replacingOccurrences(of: "\r", with: " ; ")
        var tokens = [String]()
        for chunk in window.split(whereSeparator: \.isWhitespace).reversed().prefix(3) {
            let raw = String(chunk)
            let word = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”()[]"))
                .replacingOccurrences(of: "’", with: "'").lowercased()
            guard Self.isWord(word), !raw.contains(where: { ".!?;:,/\\@=_<>`".contains($0) }),
                  raw == raw.lowercased() || raw == raw.uppercased() || String(raw.dropFirst()) == String(raw.dropFirst()).lowercased() else { break }
            tokens.insert(word, at: 0)
        }
        guard !tokens.isEmpty else { return [] }
        let normalizedPrefix = prefix.lowercased().replacingOccurrences(of: "’", with: "'")
        var scores = [Int: Double]()
        for length in 1...tokens.count {
            let key = tokens.suffix(length).joined(separator: " ")
            let weight = Double(1 << (length - 1))
            for entry in contexts[key] ?? [] where words[entry.word].hasPrefix(normalizedPrefix) && words[entry.word] != normalizedPrefix {
                scores[entry.word, default: 0] += Double(entry.weight) * weight
            }
        }
        var predictions = [Prediction]()
        for (wordID, score) in scores { predictions.append(Prediction(word: words[wordID], score: score)) }
        predictions.sort { lhs, rhs in
            if lhs.score == rhs.score { return lhs.word < rhs.word }
            return lhs.score > rhs.score
        }
        return Array(predictions.prefix(min(limit, 6)))
    }

    private static func isWord(_ word: String) -> Bool {
        (1...32).contains(word.utf8.count) && word.first?.isLetter == true && word.last?.isLetter == true &&
            word.utf8.allSatisfy { (97...122).contains($0) || $0 == 39 }
    }
}

import Foundation

struct HWKLexiconEntry: Equatable {
    var word: String
    var frequency: Double
}

struct HWKLexiconStore {
    static let bundled = HWKLexiconStore(entries: bundledEntries)

    var entries: [HWKLexiconEntry]
    private let entryIndexByWord: [String: UInt32]
    private let entriesByBigram: [UInt16: [UInt32]]
    // Postings refer to the shared corpus instead of retaining four extra copies of each entry.
    private let entriesByLength: [Int: [UInt32]]
    private let entriesByLengthAndFirstLetter: [String: [UInt32]]
    private let entriesByPrefix: [String: [UInt32]]

    init() {
        self = Self.bundled
    }

    init(entries: [HWKLexiconEntry]) {
        let normalizedEntries = Self.normalized(entries)
        self.entries = normalizedEntries
        self.entryIndexByWord = Dictionary(uniqueKeysWithValues: normalizedEntries.enumerated().map { ($0.element.word, UInt32($0.offset)) })
        var bigrams = [UInt16: [UInt32]]()
        var lengths = [Int: [UInt32]]()
        for (index, entry) in normalizedEntries.enumerated() {
            for key in Self.bigrams(in: entry.word) { bigrams[key, default: []].append(UInt32(index)) }
            lengths[entry.word.count, default: []].append(UInt32(index))
        }
        self.entriesByBigram = bigrams
        self.entriesByLength = lengths
        self.entriesByLengthAndFirstLetter = Self.lengthFirstLetterIndex(for: normalizedEntries)
        self.entriesByPrefix = Self.prefixIndex(for: normalizedEntries)
    }

    func candidates(matching signature: String) -> [HWKLexiconEntry] {
        let lowercasedSignature = Self.normalizedWord(signature)
        guard !lowercasedSignature.isEmpty else { return [] }

        let indexKey = Self.prefixKey(for: lowercasedSignature)
        guard let indices = entriesByPrefix[indexKey] else { return [] }
        return Array(indices.lazy
            .map { entries[Int($0)] }
            .filter { $0.word.hasPrefix(lowercasedSignature) }
            .prefix(200))
    }

    func correctionCandidates(for word: String, maxEditDistance: Int = 2) -> [HWKCorrectionCandidate] {
        let normalizedWord = Self.normalizedWord(word)
        guard normalizedWord.count > 1 else { return [] }

        let count = normalizedWord.count
        let minLength = max(2, count - maxEditDistance)
        let maxLength = count + maxEditDistance
        var matches: [HWKCorrectionCandidate] = []

        for length in minLength...maxLength {
            let lengthMatches = entriesByLength[length] ?? []
            let firstLetterMatches = Self.firstLetter(normalizedWord).flatMap {
                entriesByLengthAndFirstLetter[Self.lengthFirstLetterKey(length: length, firstLetter: $0)]
            } ?? []
            let searchEntries = firstLetterMatches.isEmpty ? lengthMatches : firstLetterMatches

            for index in searchEntries {
                let entry = entries[Int(index)]
                let distance = HWKCorrectionEngine.editDistance(normalizedWord, entry.word, maxDistance: maxEditDistance)
                guard distance <= maxEditDistance else { continue }
                matches.append(HWKCorrectionCandidate(
                    text: entry.word,
                    editDistance: distance,
                    frequency: entry.frequency,
                    source: .lexicon
                ))
            }
        }

        return matches
    }

    /// Bounded candidate lookup for the live suggestion bar, without scanning
    /// the dictionary or widening automatic replacement eligibility.
    func singleEditWords(for source: String) -> Set<String> {
        guard (3...20).contains(source.count),
              source.unicodeScalars.allSatisfy({ (97...122).contains($0.value) }) else { return [] }
        let characters = Array(source)
        var matches = Set<String>()
        func check(_ characters: [Character]) {
            let word = String(characters)
            if word != source, entryIndexByWord[word] != nil { matches.insert(word) }
        }
        for index in characters.indices {
            var edited = characters
            edited.remove(at: index)
            check(edited)
            for letter in "abcdefghijklmnopqrstuvwxyz" where letter != characters[index] {
                edited = characters
                edited[index] = letter
                check(edited)
            }
        }
        for index in 0...characters.count {
            for letter in "abcdefghijklmnopqrstuvwxyz" {
                var edited = characters
                edited.insert(letter, at: index)
                check(edited)
            }
        }
        return matches
    }

    func frequency(of word: String) -> Double {
        guard let index = entryIndexByWord[word] else { return 0 }
        return entries[Int(index)].frequency
    }

    /// The live rail examines at most 4,608 posting IDs and 192 fuzzy matches.
    /// Posting lists contain compact indices into the shared frequency-sorted corpus.
    func typingRepairCandidates(for source: String, limit: Int = 6) -> [HWKCorrectionCandidate] {
        guard limit > 0, (3...20).contains(source.count),
              source.utf8.allSatisfy({ (97...122).contains($0) }) else { return [] }
        let sourceBytes = Array(source.utf8)
        var indices = Set(singleEditWords(for: source).compactMap { entryIndexByWord[$0] })
        if source.count >= 6 {
            let grams = Self.bigrams(in: source).filter { entriesByBigram[$0] != nil }.sorted {
                let left = entriesByBigram[$0]?.count ?? 0, right = entriesByBigram[$1]?.count ?? 0
                return left == right ? $0 < $1 : left < right
            }
            var votes = [UInt32: Int]()
            for gram in grams.prefix(6) {
                for index in (entriesByBigram[gram] ?? []).prefix(768) {
                    let word = entries[Int(index)].word
                    guard abs(word.utf8.count - sourceBytes.count) <= 2 else { continue }
                    votes[index, default: 0] += 1
                }
            }
            let candidates = votes.sorted {
                if $0.value != $1.value { return $0.value > $1.value }
                return $0.key < $1.key
            }
            indices.formUnion(candidates.prefix(192).map(\.key))
        }
        return indices.compactMap { index -> HWKCorrectionCandidate? in
            let entry = entries[Int(index)]
            guard entry.word != source, entry.frequency >= 0.35 else { return nil }
            let distance = Self.boundedASCIIEditDistance(sourceBytes, Array(entry.word.utf8))
            guard distance <= 2 else { return nil }
            return HWKCorrectionCandidate(text: entry.word, editDistance: distance, frequency: entry.frequency, source: .lexicon)
        }.sorted {
            let left = $0.frequency * 2 - Double($0.editDistance) * 0.35
            let right = $1.frequency * 2 - Double($1.editDistance) * 0.35
            return left == right ? $0.text < $1.text : left > right
        }.prefix(min(limit, 8)).map { $0 }
    }

    private static func bigrams(in word: String) -> Set<UInt16> {
        let bytes = Array(word.utf8)
        guard (3...20).contains(bytes.count), bytes.allSatisfy({ (97...122).contains($0) }) else { return [] }
        return Set(zip(bytes, bytes.dropFirst()).map { UInt16($0) << 8 | UInt16($1) })
    }

    private static func boundedASCIIEditDistance(_ source: [UInt8], _ target: [UInt8]) -> Int {
        guard abs(source.count - target.count) <= 2 else { return 3 }
        var previous = Array(0...target.count)
        for row in 1...source.count {
            var current = Array(repeating: 3, count: target.count + 1)
            current[0] = row
            let lower = max(1, row - 2), upper = min(target.count, row + 2)
            guard lower <= upper else { return 3 }
            var best = 3
            for column in lower...upper {
                current[column] = min(previous[column] + 1, current[column - 1] + 1,
                                      previous[column - 1] + (source[row - 1] == target[column - 1] ? 0 : 1))
                best = min(best, current[column])
            }
            if best > 2 { return 3 }
            previous = current
        }
        return previous[target.count]
    }

    private static var bundledEntries: [HWKLexiconEntry] { loadBundledEntries() }

    private static func loadBundledEntries() -> [HWKLexiconEntry] {
        guard let url = lexiconResourceURL(),
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }

        return contents.split(whereSeparator: \.isNewline).compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t")
            guard columns.count == 2,
                  let frequency = Double(columns[1])
            else {
                return nil
            }
            return HWKLexiconEntry(word: String(columns[0]), frequency: frequency)
        }
    }

    private static func lexiconResourceURL() -> URL? {
        let bundles = [Bundle.main] + Bundle.allBundles + Bundle.allFrameworks
        for bundle in bundles {
            if let url = bundle.url(forResource: "HWKEnglishLexicon", withExtension: "tsv") {
                return url
            }
        }
        return nil
    }

    private static func normalized(_ entries: [HWKLexiconEntry]) -> [HWKLexiconEntry] {
        var bestByWord: [String: HWKLexiconEntry] = [:]
        for entry in entries {
            let word = normalizedWord(entry.word)
            guard isValidWord(word) else { continue }
            let frequency = min(max(entry.frequency, 0), 1)
            let normalizedEntry = HWKLexiconEntry(word: word, frequency: frequency)
            if let existing = bestByWord[word], existing.frequency >= frequency {
                continue
            }
            bestByWord[word] = normalizedEntry
        }

        return bestByWord.values.sorted {
            if $0.frequency == $1.frequency { return $0.word < $1.word }
            return $0.frequency > $1.frequency
        }
    }

    private static func prefixIndex(for entries: [HWKLexiconEntry]) -> [String: [UInt32]] {
        var index: [String: [UInt32]] = [:]
        for (offset, entry) in entries.enumerated() {
            let one = String(entry.word.prefix(1))
            let two = prefixKey(for: entry.word)
            index[one, default: []].append(UInt32(offset))
            index[two, default: []].append(UInt32(offset))
        }
        return index
    }

    private static func lengthFirstLetterIndex(for entries: [HWKLexiconEntry]) -> [String: [UInt32]] {
        var index: [String: [UInt32]] = [:]
        for (offset, entry) in entries.enumerated() {
            guard let firstLetter = firstLetter(entry.word) else { continue }
            index[lengthFirstLetterKey(length: entry.word.count, firstLetter: firstLetter), default: []].append(UInt32(offset))
        }
        return index
    }

    private static func lengthFirstLetterKey(length: Int, firstLetter: Character) -> String {
        "\(length):\(firstLetter)"
    }

    private static func firstLetter(_ word: String) -> Character? {
        word.first
    }

    private static func prefixKey(for word: String) -> String {
        String(word.prefix(min(2, word.count)))
    }

    private static func normalizedWord(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isValidWord(_ word: String) -> Bool {
        guard word.count >= 2, word.count <= 20 else { return false }
        return word.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 97 && scalar.value <= 122
        }
    }
}

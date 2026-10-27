import Foundation

struct HWKUserDictionaryEntry: Codable, Equatable {
    var term: String
    var weight: Double
    var updatedAt: Date
}

struct HWKUserDictionary: Codable, Equatable {
    var entries: [HWKUserDictionaryEntry]

    init(entries: [HWKUserDictionaryEntry] = []) {
        self.entries = Self.normalizedEntries(entries)
    }

    init(serializedData: Data) {
        let decoded = try? JSONDecoder().decode([HWKUserDictionaryEntry].self, from: serializedData)
        self.entries = Self.normalizedEntries(decoded ?? [])
    }

    init(serializedData: Data?) {
        if let data = serializedData, let decoded = try? JSONDecoder().decode([HWKUserDictionaryEntry].self, from: data) {
            self.entries = Self.normalizedEntries(decoded)
        } else {
            self.entries = []
        }
    }

    func serializedPayload() -> Data {
        (try? JSONEncoder().encode(entries)) ?? Data("[]".utf8)
    }

    func entries(matching prefix: String) -> [HWKUserDictionaryEntry] {
        let lowercasedPrefix = Self.normalizeTerm(prefix)
        return entries.filter { $0.term.lowercased().hasPrefix(lowercasedPrefix) }
    }

    func merged(with remote: HWKUserDictionary) -> HWKUserDictionary {
        HWKUserDictionary(entries: entries + remote.entries)
    }

    private static func normalizedEntries(_ source: [HWKUserDictionaryEntry]) -> [HWKUserDictionaryEntry] {
        var mergedByTerm: [String: HWKUserDictionaryEntry] = [:]

        for var entry in source {
            let normalized = normalizeTerm(entry.term)
            guard !normalized.isEmpty else { continue }
            entry.term = normalized
            let existing = mergedByTerm[normalized]
            if existing == nil || entry.updatedAt >= existing!.updatedAt {
                mergedByTerm[normalized] = entry
            }
        }

        return mergedByTerm.values.sorted {
            $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }
    }

    private static func normalizeTerm(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

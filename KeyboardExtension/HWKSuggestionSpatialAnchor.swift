import Foundation

struct HWKSuggestionSpatialCandidate: Equatable {
    let id: String
    let sourceText: String
    let replacement: String
    let fallbackSlot: Int
    let isAnchorable: Bool

    init(
        id: String,
        sourceText: String,
        replacement: String,
        fallbackSlot: Int,
        isAnchorable: Bool = true
    ) {
        self.id = id
        self.sourceText = sourceText
        self.replacement = replacement
        self.fallbackSlot = fallbackSlot
        self.isAnchorable = isAnchorable
    }
}

enum HWKSuggestionSpatialAnchor {
    static func assignments(
        candidates: [HWKSuggestionSpatialCandidate],
        rankedCandidateIDs: [String],
        slotCount: Int,
        keyRows: [[String]]
    ) -> [String?] {
        let resolvedSlotCount = max(slotCount, 1)
        var orderedCandidates = [HWKSuggestionSpatialCandidate]()
        var orderedCandidateIDs = Set<String>()

        for candidateID in rankedCandidateIDs {
            guard let candidate = candidates.first(where: { $0.id == candidateID }),
                  orderedCandidateIDs.insert(candidate.id).inserted else {
                continue
            }
            orderedCandidates.append(candidate)
        }
        for candidate in candidates where orderedCandidateIDs.insert(candidate.id).inserted {
            orderedCandidates.append(candidate)
        }

        var assignments = Array<String?>(repeating: nil, count: resolvedSlotCount)
        for candidate in orderedCandidates {
            let preferred = candidate.isAnchorable
                ? preferredSlot(
                    sourceText: candidate.sourceText,
                    replacement: candidate.replacement,
                    slotCount: resolvedSlotCount,
                    keyRows: keyRows
                )
                : nil
            let fallback = min(max(candidate.fallbackSlot, 0), resolvedSlotCount - 1)
            guard let slot = nearestOpenSlot(
                to: preferred ?? fallback,
                assignments: assignments
            ) else {
                break
            }
            assignments[slot] = candidate.id
        }
        return assignments
    }

    static func preferredSlot(
        sourceText: String,
        replacement: String,
        slotCount: Int,
        keyRows: [[String]]
    ) -> Int? {
        let resolvedSlotCount = max(slotCount, 1)
        guard let anchorKey = nextAnchorKey(
            sourceText: sourceText,
            replacement: replacement
        ), let horizontalPosition = horizontalPosition(
            for: anchorKey,
            keyRows: keyRows
        ) else {
            return nil
        }
        return min(Int(horizontalPosition * Double(resolvedSlotCount)), resolvedSlotCount - 1)
    }

    private static func nearestOpenSlot(
        to preferredSlot: Int,
        assignments: [String?]
    ) -> Int? {
        assignments.indices
            .filter { assignments[$0] == nil }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs - preferredSlot)
                let rhsDistance = abs(rhs - preferredSlot)
                if lhsDistance == rhsDistance { return lhs < rhs }
                return lhsDistance < rhsDistance
            }
    }

    private static func nextAnchorKey(
        sourceText: String,
        replacement: String
    ) -> String? {
        let sourceCharacters = Array(
            sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let replacementCharacters = Array(
            replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !replacementCharacters.isEmpty else { return nil }

        var sharedPrefixCount = 0
        while sharedPrefixCount < sourceCharacters.count,
              sharedPrefixCount < replacementCharacters.count,
              canonicalKey(String(sourceCharacters[sharedPrefixCount]), foldsDiacritics: false) ==
                canonicalKey(String(replacementCharacters[sharedPrefixCount]), foldsDiacritics: false) {
            sharedPrefixCount += 1
        }

        return replacementCharacters.dropFirst(sharedPrefixCount).lazy
            .map(String.init)
            .first(where: isAnchorableKey)
    }

    private static func horizontalPosition(
        for anchorKey: String,
        keyRows: [[String]]
    ) -> Double? {
        let rows = keyRows.filter { !$0.isEmpty }
        guard let maximumColumnCount = rows.map(\.count).max(), maximumColumnCount > 0 else {
            return nil
        }

        func position(foldsDiacritics: Bool) -> Double? {
            let target = canonicalKey(anchorKey, foldsDiacritics: foldsDiacritics)
            guard !target.isEmpty else { return nil }
            for row in rows {
                guard let index = row.firstIndex(where: {
                    canonicalKey($0, foldsDiacritics: foldsDiacritics) == target
                }) else {
                    continue
                }
                let leadingInset = Double(maximumColumnCount - row.count) / 2
                return (leadingInset + Double(index) + 0.5) / Double(maximumColumnCount)
            }
            return nil
        }

        return position(foldsDiacritics: false) ?? position(foldsDiacritics: true)
    }

    private static func canonicalKey(
        _ value: String,
        foldsDiacritics: Bool
    ) -> String {
        let options: String.CompareOptions = foldsDiacritics
            ? [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
            : [.caseInsensitive, .widthInsensitive]
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: options, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private static func isAnchorableKey(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }
    }
}

import SwiftUI
import UIKit

final class KeyboardSuggestionContentInvalidation: ObservableObject {
    @Published private(set) var revision: UInt64 = 0

    func invalidate() {
        revision &+= 1
    }
}

private struct KeyboardSuggestionContentScope<Content: View>: View {
    @ObservedObject var invalidation: KeyboardSuggestionContentInvalidation
    private let content: () -> Content

    init(
        invalidation: KeyboardSuggestionContentInvalidation,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.invalidation = invalidation
        self.content = content
    }

    var body: some View {
        content()
    }
}

private struct HWKGlideKeyLayoutPreferenceKey: PreferenceKey {
    static var defaultValue: [HWKGlideKey] = []

    static func reduce(
        value: inout [HWKGlideKey],
        nextValue: () -> [HWKGlideKey]
    ) {
        value.append(contentsOf: nextValue())
    }
}

private struct HWKSuggestionChipTextFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect],
        nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}

enum HWCKeyboardRowKind {
    case quickInsert
    case holdQuickInsert
    case toolbar
    case holdToolbar
    case symbolUtility
    case symbolTop
    case holdSymbolTop
    case symbolMiddle
    case holdSymbolMiddle
    case symbolBottom
    case holdSymbolBottom
    case trailingUtility
    case expandedTrailingUtility
    case expandedLetterTrailingUtility
    case letterUtility
    case letterBottomLeading
    case letterTop
    case holdLetterTop
    case letterMiddle
    case holdLetterMiddle
    case letterBottom
    case holdLetterBottom
}

private func trailingControlIdentity(row: HWCKeyboardRowKind, index: Int, value: String) -> String {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    switch row {
    case .trailingUtility:
        return "main-trailing-\(index)-\(normalizedValue)"
    case .expandedTrailingUtility:
        return "expanded-symbols-trailing-\(index)-\(normalizedValue)"
    case .expandedLetterTrailingUtility:
        return "expanded-abc-trailing-\(index)-\(normalizedValue)"
    default:
        return "trailing-\(index)-\(normalizedValue)"
    }
}

private struct TrailingControlRenderItem: Identifiable {
    let row: HWCKeyboardRowKind
    let index: Int
    let value: String

    var id: String {
        trailingControlIdentity(row: row, index: index, value: value)
    }
}

private func trailingControlItems(row: HWCKeyboardRowKind, values: [String]) -> [TrailingControlRenderItem] {
    values.enumerated().map { index, value in
        TrailingControlRenderItem(row: row, index: index, value: value)
    }
}

private func mainRowPrimaryTrailingControlItems(row: HWCKeyboardRowKind, values: [String]) -> [TrailingControlRenderItem] {
    guard row == .trailingUtility else { return [] }
    return Array(trailingControlItems(row: row, values: values).prefix(1))
}

private func fixedTrailingControlItems(row: HWCKeyboardRowKind, values: [String]) -> [TrailingControlRenderItem] {
    let items = trailingControlItems(row: row, values: values)
    guard row == .trailingUtility else { return items }
    return Array(items.dropFirst())
}

enum HWCExpandedBottomStripLayout {
    private static let regularControlSpan = 1
    private static let spaceControlSpan = 2

    static func controlSpans(for values: [String]) -> [Int] {
        values.map(controlSpan(for:))
    }

    static func controlSpan(for value: String) -> Int {
        guard let action = KeyboardSpecialKeyAction.resolved(from: value) else {
            return regularControlSpan
        }

        switch action {
        case .space:
            return spaceControlSpan
        default:
            return regularControlSpan
        }
    }

    static func unitWidth(
        availableWidth: CGFloat,
        spans: [Int],
        spacing: CGFloat
    ) -> CGFloat {
        let totalUnits = CGFloat(spans.reduce(0, +))
        guard totalUnits > 0 else { return 0 }

        let totalUnitSpacing = max(0, totalUnits - 1) * spacing
        return max(0, (availableWidth - totalUnitSpacing) / totalUnits)
    }

    static func controlWidth(span: Int, unitWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        (unitWidth * CGFloat(span)) + (spacing * CGFloat(max(span - 1, 0)))
    }
}

/// Computes exact storage offsets for newline-delimited rows and a bounded,
/// width-derived fallback for host soft wraps. UIKit exposes character offsets
/// but no host caret geometry to custom keyboards, so the fallback stays an
/// estimate and never claims pixel-exact host layout.
enum HWCVerticalCursorMovement {
    static func estimatedSoftWrapColumnCount(
        containerWidth: CGFloat,
        averageGraphemeWidth: CGFloat
    ) -> Int {
        let usableWidth = max(160, containerWidth - 96)
        let safeAverageWidth = max(1, averageGraphemeWidth)
        return min(64, max(12, Int(usableWidth / safeAverageWidth)))
    }

    static func characterOffset(
        for action: KeyboardSpecialKeyAction,
        contextBeforeInput before: String?,
        contextAfterInput after: String?,
        preferredColumn: Int? = nil,
        softWrapColumnEstimate: Int? = nil
    ) -> Int? {
        let softWrapColumnEstimate = softWrapColumnEstimate.flatMap {
            $0 > 0 ? $0 : nil
        }
        switch action {
        case .moveUp:
            guard let before else {
                return nil
            }
            let rows = before.components(separatedBy: "\n")
            guard let currentPrefix = rows.last else {
                return nil
            }
            if let softWrapColumnEstimate,
               currentPrefix.count >= softWrapColumnEstimate {
                return -currentPrefix.suffix(softWrapColumnEstimate).utf16.count
            }
            guard rows.count >= 2 else { return nil }
            let (previousLine, separatorWidth) = lineBeforeLF(
                rows[rows.count - 2]
            )
            let targetColumn = min(
                preferredColumn ?? currentPrefix.count,
                previousLine.count
            )
            let targetIndex = previousLine.index(
                previousLine.startIndex,
                offsetBy: targetColumn
            )
            let previousSuffix = previousLine[targetIndex...]
            return -(
                previousSuffix.utf16.count
                    + separatorWidth
                    + currentPrefix.utf16.count
            )

        case .moveDown:
            guard let before,
                  let after else {
                return nil
            }
            let rows = after.components(separatedBy: "\n")
            let (currentSuffix, separatorWidth) = lineBeforeLF(rows[0])
            if let softWrapColumnEstimate,
               currentSuffix.count >= softWrapColumnEstimate {
                return currentSuffix.prefix(softWrapColumnEstimate).utf16.count
            }
            guard rows.count >= 2 else { return nil }
            let currentColumn = preferredColumn ?? currentLinePrefix(in: before).count
            let (nextLine, _) = lineBeforeLF(rows[1])
            let targetColumn = min(currentColumn, nextLine.count)
            let targetIndex = nextLine.index(
                nextLine.startIndex,
                offsetBy: targetColumn
            )
            let targetPrefix = nextLine[..<targetIndex]
            return currentSuffix.utf16.count
                + separatorWidth
                + targetPrefix.utf16.count

        default:
            return nil
        }
    }

    static func currentColumn(
        contextBeforeInput before: String?,
        softWrapColumnEstimate: Int? = nil
    ) -> Int? {
        guard let before else { return nil }
        let logicalColumn = currentLinePrefix(in: before).count
        guard let softWrapColumnEstimate,
              softWrapColumnEstimate > 0,
              logicalColumn > softWrapColumnEstimate else {
            return logicalColumn
        }
        let wrappedColumn = logicalColumn % softWrapColumnEstimate
        return wrappedColumn == 0 ? softWrapColumnEstimate : wrappedColumn
    }

    private static func currentLinePrefix(in text: String) -> String {
        text.components(separatedBy: "\n").last ?? text
    }

    private static func lineBeforeLF(_ rawLine: String) -> (String, Int) {
        if rawLine.hasSuffix("\r") {
            return (String(rawLine.dropLast()), 2)
        }
        return (rawLine, 1)
    }
}

/// Keeps vertical repeats from resolving against the same stale host cursor and
/// retains the intended column when an adjacent logical line is shorter.
struct HWCVerticalCursorSession {
    private(set) var preferredColumn: Int?
    private(set) var isAwaitingHostSelectionChange = false

    mutating func begin(currentColumn: Int) -> Int? {
        guard !isAwaitingHostSelectionChange else { return nil }
        let resolvedColumn = preferredColumn ?? currentColumn
        preferredColumn = resolvedColumn
        isAwaitingHostSelectionChange = true
        return resolvedColumn
    }

    @discardableResult
    mutating func acknowledgeHostSelectionChange() -> Bool {
        let wasAwaiting = isAwaitingHostSelectionChange
        isAwaitingHostSelectionChange = false
        return wasAwaiting
    }

    mutating func reset() {
        preferredColumn = nil
        isAwaitingHostSelectionChange = false
    }
}

private enum ExpandedVisualBand {
    case top
    case middle
    case bottom
}

private struct QuickInsertRenderItem: Identifiable {
    enum Action {
        case text(String)
        case pair(open: String, close: String)
        case special(KeyboardSpecialKeyAction)
    }

    let id: String
    let sourceIndex: Int
    let label: String
    let action: Action
}

enum SuggestionRolodexFamily: Hashable {
    case completion(String)
    case prediction
    case correction(String)
}

enum SuggestionRolodexSourceFamily: Hashable {
    case previousWord
    case prefixCompletion
    case correction
    case saved
    case punctuation
    case action
}

extension KeyboardAutocorrectLogicLane {
    func chipColor(for suggestion: KeyboardSuggestionItem) -> KeyboardAutocorrectLogicChipColor {
        let ruleKinds: [KeyboardAutocorrectLogicBlockKind]
        switch suggestion.kind {
        case .completion where suggestion.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            ruleKinds = [.previousWordLane]
        case .completion:
            ruleKinds = [.highlightTypedWord, .dictionary, .completionLane]
        case .correction:
            ruleKinds = suggestion.customTextRuleID == nil
                ? [.correctionLane, .nativeSpellChecker, .coreML]
                : [.correctionLane, .customTextRule]
        case .replacement:
            ruleKinds = [.savedWords]
        case .saveWord:
            return .none
        }

        return blocks
            .sorted { lhs, rhs in
                if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.rankPriority < rhs.rankPriority
            }
            .first { ruleKinds.contains($0.kind) && $0.chipColor != .none }?
            .chipColor ?? .none
    }
}

struct SuggestionRolodexLane: Identifiable, Equatable {
    let id: Int
    let family: SuggestionRolodexFamily?
    var items: [KeyboardSuggestionItem]
    var selectedIndex: Int

    var selectedItem: KeyboardSuggestionItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    var alternativeCount: Int {
        selectedItem == nil ? 0 : max(0, items.count - 1)
    }

    var accessibilityHint: String {
        [
            selectedItem?.autobotRationale,
            alternativeCount > 0 ? "Touch and hold for \(alternativeCount) more suggestions." : nil,
        ].compactMap { $0 }.joined(separator: " ")
    }

    static let empty = SuggestionRolodexLane(
        id: -1,
        family: nil,
        items: [],
        selectedIndex: 0
    )

    static func family(for item: KeyboardSuggestionItem) -> SuggestionRolodexFamily {
        switch item.kind {
        case .completion where item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .prediction
        case .completion:
            return .completion(item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        case .correction, .replacement, .saveWord:
            return .correction(item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    static func sourceFamily(for item: KeyboardSuggestionItem) -> SuggestionRolodexSourceFamily {
        switch item.kind {
        case .completion where isStandalonePunctuation(item):
            return .punctuation
        case .completion where item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            return .previousWord
        case .completion:
            return .prefixCompletion
        case .correction, .replacement:
            return .correction
        case .saveWord:
            return .action
        }
    }

    static func lanes(from suggestions: [KeyboardSuggestionItem]) -> [SuggestionRolodexLane] {
        let uniqueSuggestions = uniqueSuggestions(suggestions)
        let visibleItems = Array(uniqueSuggestions.prefix(3))
        let visibleFamilies = visibleItems.map(Self.family(for:))
        let visibleFamilyCounts = visibleFamilies.reduce(into: [SuggestionRolodexFamily: Int]()) { counts, family in
            counts[family, default: 0] += 1
        }
        var visibleFamilyOrdinals = [SuggestionRolodexFamily: Int]()
        let lanes = visibleItems.enumerated().map { index, visibleItem in
            let family = family(for: visibleItem)
            let familyOrdinal = visibleFamilyOrdinals[family, default: 0]
            visibleFamilyOrdinals[family] = familyOrdinal + 1
            let laneItems = alternatives(
                for: family,
                familyOrdinal: familyOrdinal,
                visibleFamilyCount: max(visibleFamilyCounts[family] ?? 1, 1),
                in: uniqueSuggestions
            )
            let selectedIndex = laneItems.firstIndex(of: visibleItem) ?? 0

            return SuggestionRolodexLane(
                id: index,
                family: family,
                items: laneItems,
                selectedIndex: selectedIndex
            )
        }
        return lanes + Array(repeating: Self.empty, count: max(0, 3 - lanes.count))
    }

    static func lanes(
        from suggestions: [KeyboardSuggestionItem],
        logicLanes: [KeyboardAutocorrectLogicLane]
    ) -> [SuggestionRolodexLane] {
        let uniqueSuggestions = uniqueSuggestions(suggestions)
        let laneLogic = logicLanes
        let laneCount = max(laneLogic.count, 3)
        let resolvedLogic = (0..<laneCount).map { index in
            laneLogic.indices.contains(index) ? laneLogic[index] : KeyboardAutocorrectLogicLane.defaultLanes[index]
        }
        var usedKeys = Set<String>()
        var usedVisibleKeys = Set<String>()
        var usedSourceFamilies = Set<SuggestionRolodexSourceFamily>()
        var selectedItems = Array<KeyboardSuggestionItem?>(repeating: nil, count: laneCount)
        var candidateLists = Array(repeating: [KeyboardSuggestionItem](), count: laneCount)

        for index in 0..<laneCount {
            let logic = resolvedLogic[index]
            let preferredItems = logic.preferredItems(from: uniqueSuggestions)
            guard let visibleItem = firstUnusedItem(
                in: preferredItems,
                usedKeys: usedKeys,
                usedVisibleKeys: usedVisibleKeys,
                usedSourceFamilies: usedSourceFamilies
            ) else {
                candidateLists[index] = preferredItems
                continue
            }

            selectedItems[index] = visibleItem
            candidateLists[index] = preferredItems
            usedKeys.insert(uniqueKey(for: visibleItem))
            usedVisibleKeys.insert(visibleReplacementKey(for: visibleItem))
            usedSourceFamilies.insert(sourceFamily(for: visibleItem))
        }

        for index in 0..<laneCount where selectedItems[index] == nil {
            let logic = resolvedLogic[index]
            let fallbackItems = logic.fallbackItems(from: uniqueSuggestions)
            guard let visibleItem = firstUnusedItem(
                in: fallbackItems,
                usedKeys: usedKeys,
                usedVisibleKeys: usedVisibleKeys,
                usedSourceFamilies: usedSourceFamilies
            ) else {
                continue
            }

            selectedItems[index] = visibleItem
            candidateLists[index] = fallbackItems
            usedKeys.insert(uniqueKey(for: visibleItem))
            usedVisibleKeys.insert(visibleReplacementKey(for: visibleItem))
            usedSourceFamilies.insert(sourceFamily(for: visibleItem))
        }

        let lanes = (0..<laneCount).map { index -> SuggestionRolodexLane in
            let logic = laneLogic.indices.contains(index) ? laneLogic[index] : KeyboardAutocorrectLogicLane.defaultLanes[index]
            guard let visibleItem = selectedItems[index] else {
                return Self.empty.withID(index)
            }

            let family = family(for: visibleItem)
            let laneItems = alternatives(
                for: family,
                familyOrdinal: 0,
                visibleFamilyCount: 1,
                in: candidateLists[index].isEmpty ? logic.fallbackItems(from: uniqueSuggestions) : candidateLists[index]
            )
            let selectedIndex = laneItems.firstIndex(of: visibleItem) ?? 0
            return SuggestionRolodexLane(
                id: index,
                family: family,
                items: laneItems,
                selectedIndex: selectedIndex
            )
        }
        return lanes
    }

    private static func firstUnusedItem(
        in items: [KeyboardSuggestionItem],
        usedKeys: Set<String>,
        usedVisibleKeys: Set<String>,
        usedSourceFamilies: Set<SuggestionRolodexSourceFamily>
    ) -> KeyboardSuggestionItem? {
        let distinctSourceItem = items.first {
            !usedKeys.contains(uniqueKey(for: $0)) &&
            !usedVisibleKeys.contains(visibleReplacementKey(for: $0)) &&
            !usedSourceFamilies.contains(sourceFamily(for: $0))
        }
        if let distinctSourceItem {
            return distinctSourceItem
        }

        return items.first {
            !usedKeys.contains(uniqueKey(for: $0)) &&
            !usedVisibleKeys.contains(visibleReplacementKey(for: $0))
        }
    }

    private static func alternatives(
        for family: SuggestionRolodexFamily,
        familyOrdinal: Int,
        visibleFamilyCount: Int,
        in suggestions: [KeyboardSuggestionItem]
    ) -> [KeyboardSuggestionItem] {
        let familySuggestions = suggestions.filter { Self.family(for: $0) == family }
        guard visibleFamilyCount > 1 else { return familySuggestions }

        return familySuggestions.enumerated().compactMap { index, item in
            index % visibleFamilyCount == familyOrdinal ? item : nil
        }
    }

    fileprivate static func uniqueSuggestions(_ suggestions: [KeyboardSuggestionItem]) -> [KeyboardSuggestionItem] {
        var seen = Set<String>()
        return suggestions.filter { item in
            return seen.insert(uniqueKey(for: item)).inserted
        }
    }

    fileprivate static func uniqueKey(for item: KeyboardSuggestionItem) -> String {
        [
            item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.trailingSuffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(describing: item.kind),
        ].joined(separator: "|")
    }

    fileprivate static func visibleReplacementKey(for item: KeyboardSuggestionItem) -> String {
        [
            item.replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.trailingSuffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ].joined(separator: "|")
    }

    private static func isStandalonePunctuation(_ item: KeyboardSuggestionItem) -> Bool {
        item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        item.replacement.count == 1 &&
        item.replacement.allSatisfy { ".?!".contains($0) }
    }

    private func withID(_ id: Int) -> SuggestionRolodexLane {
        SuggestionRolodexLane(
            id: id,
            family: family,
            items: items,
            selectedIndex: selectedIndex
        )
    }
}

struct SuggestionRailPlacement: Identifiable, Equatable {
    let startLane: Int
    let laneSpan: Int
    let lane: SuggestionRolodexLane

    var id: String {
        "\(startLane):\(lane.id):\(lane.selectedItem?.id ?? "empty")"
    }

    func contains(physicalLane: Int) -> Bool {
        physicalLane >= startLane && physicalLane < startLane + laneSpan
    }
}

enum SuggestionRailWidthLayout {
    static func widths(
        totalWidth: CGFloat,
        laneSpans: [Int],
        activeIndex: Int?,
        activePreferredWidth: CGFloat?
    ) -> [CGFloat] {
        guard totalWidth > 0, !laneSpans.isEmpty else { return [] }
        let spans = laneSpans.map { max($0, 1) }
        let totalSpan = CGFloat(spans.reduce(0, +))
        let baseWidths = spans.map { totalWidth * CGFloat($0) / totalSpan }
        guard let activeIndex,
              baseWidths.indices.contains(activeIndex),
              let activePreferredWidth else {
            return baseWidths
        }

        let otherCount = baseWidths.count - 1
        guard otherCount > 0 else { return [totalWidth] }
        let minimumOtherWidth: CGFloat = 22
        let maximumActiveWidth = max(baseWidths[activeIndex], totalWidth - minimumOtherWidth * CGFloat(otherCount))
        let activeWidth = min(max(baseWidths[activeIndex], activePreferredWidth), maximumActiveWidth)
        let remainingWidth = totalWidth - activeWidth
        let otherBaseTotal = totalWidth - baseWidths[activeIndex]

        return baseWidths.indices.map { index in
            guard index != activeIndex else { return activeWidth }
            return otherBaseTotal > 0
                ? remainingWidth * baseWidths[index] / otherBaseTotal
                : remainingWidth / CGFloat(otherCount)
        }
    }
}

enum SuggestionRailLayout {
    private static let laneCount = 3

    static func placements(
        from lanes: [SuggestionRolodexLane],
        rankedSuggestions: [KeyboardSuggestionItem],
        slotCount: Int = laneCount,
        keyRows: [[String]] = []
    ) -> [SuggestionRailPlacement] {
        let resolvedSlotCount = max(slotCount, 1)
        if !keyRows.isEmpty {
            return spatialPlacements(
                from: lanes,
                rankedSuggestions: rankedSuggestions,
                slotCount: resolvedSlotCount,
                keyRows: keyRows
            )
        }
        if resolvedSlotCount != laneCount {
            return identityPlacements(from: lanes, slotCount: resolvedSlotCount)
        }

        return legacyThreeLanePlacements(
            from: lanes,
            rankedSuggestions: rankedSuggestions
        )
    }

    static func preferredSlot(
        for item: KeyboardSuggestionItem,
        slotCount: Int,
        keyRows: [[String]]
    ) -> Int? {
        guard item.kind != .saveWord else { return nil }
        return HWKSuggestionSpatialAnchor.preferredSlot(
            sourceText: item.sourceText,
            replacement: item.replacement,
            slotCount: slotCount,
            keyRows: keyRows
        )
    }

    private static func spatialPlacements(
        from lanes: [SuggestionRolodexLane],
        rankedSuggestions: [KeyboardSuggestionItem],
        slotCount: Int,
        keyRows: [[String]]
    ) -> [SuggestionRailPlacement] {
        let logicalLanes = Array(lanes.prefix(slotCount))
        let visibleLanes = logicalLanes.filter { $0.selectedItem != nil }

        if slotCount == laneCount,
           let primaryLane = primaryLane(in: visibleLanes, rankedSuggestions: rankedSuggestions),
           span(for: primaryLane.selectedItem) > 1 {
            return legacyThreeLanePlacements(
                from: lanes,
                rankedSuggestions: rankedSuggestions
            )
        }

        let spatialCandidateIDs = HWKSuggestionSpatialAnchor.assignments(
            candidates: visibleLanes.compactMap { lane in
                guard let item = lane.selectedItem else { return nil }
                return HWKSuggestionSpatialCandidate(
                    id: item.id,
                    sourceText: item.sourceText,
                    replacement: item.replacement,
                    fallbackSlot: lane.id,
                    isAnchorable: item.kind != .saveWord
                )
            },
            rankedCandidateIDs: rankedSuggestions.map(\.id),
            slotCount: slotCount,
            keyRows: keyRows
        )
        var assignments = Array<SuggestionRolodexLane?>(repeating: nil, count: slotCount)
        var assignedLaneIDs = Set<Int>()

        for (physicalLane, candidateID) in spatialCandidateIDs.enumerated() {
            guard let candidateID,
                  let lane = visibleLanes.first(where: { $0.selectedItem?.id == candidateID }) else {
                continue
            }
            assignments[physicalLane] = lane
            assignedLaneIDs.insert(lane.id)
        }

        func nearestOpenSlot(to preferredSlot: Int) -> Int? {
            assignments.indices
                .filter { assignments[$0] == nil }
                .min { lhs, rhs in
                    let lhsDistance = abs(lhs - preferredSlot)
                    let rhsDistance = abs(rhs - preferredSlot)
                    if lhsDistance == rhsDistance { return lhs < rhs }
                    return lhsDistance < rhsDistance
                }
        }

        for lane in logicalLanes where !assignedLaneIDs.contains(lane.id) {
            let preferred = min(max(lane.id, 0), slotCount - 1)
            guard let slot = nearestOpenSlot(to: preferred) else { break }
            assignments[slot] = lane
            assignedLaneIDs.insert(lane.id)
        }

        return assignments.indices.map { physicalLane in
            let lane = assignments[physicalLane] ?? SuggestionRolodexLane(
                id: physicalLane,
                family: nil,
                items: [],
                selectedIndex: 0
            )
            return SuggestionRailPlacement(
                startLane: physicalLane,
                laneSpan: 1,
                lane: lane
            )
        }
    }

    private static func identityPlacements(
        from lanes: [SuggestionRolodexLane],
        slotCount: Int
    ) -> [SuggestionRailPlacement] {
        (0..<slotCount).map { physicalLane in
            let lane = lanes.indices.contains(physicalLane)
                ? lanes[physicalLane]
                : SuggestionRolodexLane(
                    id: physicalLane,
                    family: nil,
                    items: [],
                    selectedIndex: 0
                )
            return SuggestionRailPlacement(
                startLane: physicalLane,
                laneSpan: 1,
                lane: lane
            )
        }
    }

    private static func legacyThreeLanePlacements(
        from lanes: [SuggestionRolodexLane],
        rankedSuggestions: [KeyboardSuggestionItem]
    ) -> [SuggestionRailPlacement] {
        let logicalLanes = Array(lanes.prefix(laneCount))
        let visibleLanes = logicalLanes.filter { $0.selectedItem != nil }
        guard !visibleLanes.isEmpty else { return [] }

        let primaryLane = primaryLane(
            in: visibleLanes,
            rankedSuggestions: rankedSuggestions
        ) ?? visibleLanes[0]
        let hasDistinctAlternative = visibleLanes.contains { lane in
            guard let item = lane.selectedItem, let primary = primaryLane.selectedItem else { return false }
            return visibleReplacementKey(for: item) != visibleReplacementKey(for: primary)
        }
        // Give phrases room without letting one phrase hide every other choice.
        let primarySpan = min(span(for: primaryLane.selectedItem), hasDistinctAlternative ? 2 : laneCount)
        var placements = [
            SuggestionRailPlacement(startLane: 0, laneSpan: primarySpan, lane: primaryLane)
        ]
        guard primarySpan < laneCount else { return placements }

        var usedLaneIDs: Set<Int> = [primaryLane.id]
        var usedReplacementKeys = Set<String>()
        if let item = primaryLane.selectedItem {
            usedReplacementKeys.insert(visibleReplacementKey(for: item))
        }

        var physicalLanes = Array<SuggestionRolodexLane?>(repeating: nil, count: laneCount)
        for physicalLane in primarySpan..<laneCount
            where primarySpan == 1 && logicalLanes.indices.contains(physicalLane) {
            let lane = logicalLanes[physicalLane]
            guard lane.id != primaryLane.id,
                  let item = lane.selectedItem,
                  usedReplacementKeys.insert(visibleReplacementKey(for: item)).inserted else {
                continue
            }
            physicalLanes[physicalLane] = lane
            usedLaneIDs.insert(lane.id)
        }

        let rankedVisibleLanes = rankedSuggestions.compactMap { rankedItem in
            visibleLanes.first { $0.selectedItem?.id == rankedItem.id }
        } + visibleLanes
        for physicalLane in primarySpan..<laneCount where physicalLanes[physicalLane] == nil {
            guard let lane = rankedVisibleLanes.first(where: { lane in
                guard !usedLaneIDs.contains(lane.id), let item = lane.selectedItem else { return false }
                return !usedReplacementKeys.contains(visibleReplacementKey(for: item))
            }), let item = lane.selectedItem else {
                continue
            }
            physicalLanes[physicalLane] = lane
            usedLaneIDs.insert(lane.id)
            usedReplacementKeys.insert(visibleReplacementKey(for: item))
        }

        placements.append(contentsOf: (primarySpan..<laneCount).compactMap { physicalLane in
            guard let lane = physicalLanes[physicalLane] else { return nil }
            return SuggestionRailPlacement(startLane: physicalLane, laneSpan: 1, lane: lane)
        })
        return placements
    }

    static func physicalSlots(
        from placements: [SuggestionRailPlacement]
    ) -> [KeyboardSuggestionItem?] {
        let inferredLaneCount = max(
            laneCount,
            placements.map { $0.startLane + $0.laneSpan }.max() ?? 0
        )
        return (0..<inferredLaneCount).map { physicalLane in
            placements.first { $0.contains(physicalLane: physicalLane) }?.lane.selectedItem
        }
    }

    static func logicalLaneID(
        forPhysicalLane physicalLane: Int,
        in placements: [SuggestionRailPlacement]
    ) -> Int? {
        placements.first { $0.contains(physicalLane: physicalLane) }?.lane.id
    }

    private static func span(for item: KeyboardSuggestionItem?) -> Int {
        guard let item,
              item.kind != .saveWord,
              !item.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.replacement.allSatisfy({ ".?!,;:".contains($0) }) else {
            return 1
        }
        return min(max(item.hypothesis.replacementWordCount, 1), laneCount)
    }

    private static func primaryLane(
        in visibleLanes: [SuggestionRolodexLane],
        rankedSuggestions: [KeyboardSuggestionItem]
    ) -> SuggestionRolodexLane? {
        rankedSuggestions.lazy.compactMap { rankedItem in
            visibleLanes.first { $0.selectedItem?.id == rankedItem.id }
        }.first ?? visibleLanes.first
    }

    private static func visibleReplacementKey(for item: KeyboardSuggestionItem) -> String {
        [
            item.replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            item.trailingSuffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
        ].joined(separator: "|")
    }
}

func autobotCandidateFingerprint(_ suggestion: KeyboardSuggestionItem) -> UInt64 {
    if let transition = HWKAutobotEnglishStyleClassifier.transition(
        source: suggestion.sourceText,
        replacement: suggestion.replacement
    ), transition.dimension == .letterCase {
        return HWKAutobotEpisodeFingerprint.englishStyleCandidate(
            id: suggestion.id,
            sourceFingerprint: transition.sourceFingerprint,
            replacementFingerprint: transition.replacementFingerprint
        )
    }
    return HWKAutobotEpisodeFingerprint.candidate(
        id: suggestion.id,
        source: suggestion.sourceText,
        replacement: suggestion.replacement
    )
}

extension HWKAutobotSuggestionSurface {
    static func capture(
        from suggestions: [KeyboardSuggestionItem],
        logicLanes: [KeyboardAutocorrectLogicLane],
        modelBindings: [UInt64: HWKAutobotSuggestionModelBinding] = [:]
    ) -> HWKAutobotSuggestionSurface? {
        guard supportedVisibleLaneCounts.contains(logicLanes.count) else { return nil }
        let lanes = SuggestionRolodexLane.lanes(
            from: suggestions,
            logicLanes: logicLanes
        )
        guard lanes.count == logicLanes.count else { return nil }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let configurationData = try? encoder.encode(logicLanes),
              let canonicalConfiguration = String(
                  data: configurationData,
                  encoding: .utf8
              ) else {
            return nil
        }
        let selectedItems = lanes.map(\.selectedItem)
        let selectedCandidateIDs = selectedItems.map {
            $0.map(autobotCandidateFingerprint)
        }
        let uniqueSuggestions = SuggestionRolodexLane.uniqueSuggestions(suggestions)
        let projectionCandidates = uniqueSuggestions.enumerated().compactMap {
            ordinal, suggestion -> HWKAutobotSuggestionProjectionCandidate? in
            guard let evidence = suggestion.autobotScoreEvidence else { return nil }
            let candidateID = autobotCandidateFingerprint(suggestion)
            let modelBinding = modelBindings[candidateID]
            guard evidence.modelAdjustmentEligible == (modelBinding != nil) else {
                return nil
            }
            var preferredLaneMask = UInt16(0)
            var allowedLaneMask = UInt16(0)
            for (laneIndex, logic) in logicLanes.enumerated() {
                let laneBit = UInt16(1 << laneIndex)
                if !logic.preferredItems(from: [suggestion]).isEmpty {
                    preferredLaneMask |= laneBit
                }
                if logic.allows(item: suggestion) {
                    allowedLaneMask |= laneBit
                }
            }
            let orderedEvidence = HWKAutobotSuggestionScoreEvidence(
                surfaceNeutralScore: evidence.surfaceNeutralScore,
                surfaceChampionDelta: evidence.surfaceChampionDelta,
                modelNeutralScore: evidence.modelNeutralScore,
                modelChampionDelta: evidence.modelChampionDelta,
                stableOrdinal: ordinal,
                modelAdjustmentEligible: evidence.modelAdjustmentEligible
            )
            return HWKAutobotSuggestionProjectionCandidate(
                candidateID: candidateID,
                uniqueKeyFingerprint:
                    HWKAutobotEpisodeFingerprint.suggestionSurfaceUniqueKey(
                        SuggestionRolodexLane.uniqueKey(for: suggestion)
                    ),
                visibleReplacementFingerprint:
                    HWKAutobotEpisodeFingerprint.suggestionSurfaceVisibleKey(
                        SuggestionRolodexLane.visibleReplacementKey(for: suggestion)
                    ),
                scoreEvidence: orderedEvidence,
                preferredLaneMask: preferredLaneMask,
                allowedLaneMask: allowedLaneMask,
                sourceFamily: autobotSurfaceSourceFamily(suggestion),
                kind: autobotSurfaceCandidateKind(suggestion),
                genericFallbackEligible: suggestion.customTextRuleID == nil,
                modelBinding: modelBinding
            )
        }
        let candidateEvidenceIsComplete =
            projectionCandidates.count == uniqueSuggestions.count &&
            !projectionCandidates.isEmpty
        let candidateTrace = candidateEvidenceIsComplete
            ? HWKAutobotSuggestionProjectionTrace(
                visibleLaneCount: logicLanes.count,
                candidates: projectionCandidates
            )
            : nil
        let projectionTrace = candidateTrace.flatMap { trace in
            trace.isValid && trace.replayedCandidateIDs() == selectedCandidateIDs
                ? trace
                : nil
        }
        let surface = HWKAutobotSuggestionSurface(
            visibleLaneCount: logicLanes.count,
            configurationFingerprint:
                HWKAutobotEpisodeFingerprint.suggestionSurfaceConfiguration(
                    canonicalConfiguration
                ),
            selectedCandidateIDs: selectedCandidateIDs,
            selectedCandidateKinds: selectedItems.map {
                $0.map(autobotSurfaceCandidateKind)
            },
            projectionTrace: projectionTrace
        )
        return surface.isValid ? surface : nil
    }
}

private func autobotSurfaceSourceFamily(
    _ suggestion: KeyboardSuggestionItem
) -> HWKAutobotSuggestionSurfaceSourceFamily {
    switch SuggestionRolodexLane.sourceFamily(for: suggestion) {
    case .previousWord:
        return .previousWord
    case .prefixCompletion:
        return .prefixCompletion
    case .correction:
        return .correction
    case .saved:
        return .saved
    case .punctuation:
        return .punctuation
    case .action:
        return .action
    }
}

private func autobotSurfaceCandidateKind(
    _ suggestion: KeyboardSuggestionItem
) -> HWKAutobotSuggestionSurfaceCandidateKind {
    switch suggestion.kind {
    case .completion:
        return .completion
    case .correction:
        return .correction
    case .replacement:
        return .replacement
    case .saveWord:
        return .saveWord
    }
}

fileprivate extension KeyboardAutocorrectLogicLane {
    func preferredItems(from suggestions: [KeyboardSuggestionItem]) -> [KeyboardSuggestionItem] {
        suggestions.filter { prefers(item: $0) }
    }

    func fallbackItems(from suggestions: [KeyboardSuggestionItem]) -> [KeyboardSuggestionItem] {
        let allowedItems = suggestions.filter { allows(item: $0) }
        guard allowedItems.isEmpty else { return allowedItems }
        // A lane-owned custom rule must never leak into a lane it wasn't assigned
        // to just because that lane came up empty - only untagged suggestions may
        // use this lane as a generic fallback.
        return suggestions.filter { $0.customTextRuleID == nil }
    }

    func allows(item: KeyboardSuggestionItem) -> Bool {
        let sourceKinds = Set(blocks.map(\.kind))
        if let customTextRuleID = item.customTextRuleID {
            return blocks.contains {
                $0.kind == .customTextRule && $0.customTextRuleID == customTextRuleID
            }
        }
        switch item.kind {
        case .completion:
            return sourceKinds.contains(.dictionary)
        case .correction:
            return sourceKinds.contains(.nativeSpellChecker) || sourceKinds.contains(.coreML)
        case .replacement:
            return sourceKinds.contains(.savedWords)
        case .saveWord:
            return sourceKinds.contains(.savedWords)
        }
    }

    private func prefers(item: KeyboardSuggestionItem) -> Bool {
        guard allows(item: item) else { return false }

        switch effectiveFamily {
        case .previousWord:
            return item.kind == .completion &&
                item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .correction:
            switch item.kind {
            case .correction, .replacement:
                return true
            case .completion, .saveWord:
                return false
            }
        case .completion:
            switch item.kind {
            case .completion:
                return !item.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .saveWord, .replacement:
                return true
            case .correction:
                return false
            }
        }
    }
}

enum HWCKeyboardDirectionalSwipeAxis: Equatable {
    case up
    case down
    case left
    case right
}

enum HWCKeyboardLaneWordGesturePolicy {
    static func landingColumnIndex(
        startLocation _: CGPoint,
        location: CGPoint,
        size: CGSize,
        slotCount: Int = 3
    ) -> Int? {
        HWCKeyboardLayoutMetrics.suggestionSlotIndex(
            for: location,
            size: size,
            slotCount: slotCount
        )
    }
}

struct SuggestionRationaleLayout: Equatable {
    let titleFontSize: CGFloat
    let rationaleFontSize: CGFloat
    let spacing: CGFloat
    let verticalPadding: CGFloat
    let estimatedContentHeight: CGFloat
}

struct SuggestionRationaleTextStack: View {
    let title: String
    let rationaleLabel: String?
    let titleFont: Font
    let rationaleFontSize: CGFloat
    let titleColor: Color
    let rationaleColor: Color
    let titleKerning: CGFloat
    let spacing: CGFloat
    let titleFrameLaneID: Int?
    let coordinateSpaceName: String?

    var body: some View {
        VStack(spacing: spacing) {
            Text(title)
                .font(titleFont)
                .kerning(titleKerning)
                .foregroundColor(titleColor)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .background(titleFrameReader)
            if let rationaleLabel {
                Text(rationaleLabel)
                    .font(.system(size: rationaleFontSize, weight: .medium))
                    .foregroundColor(rationaleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var titleFrameReader: some View {
        if let titleFrameLaneID, let coordinateSpaceName {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: HWKSuggestionChipTextFramePreferenceKey.self,
                    value: [titleFrameLaneID: proxy.frame(in: .named(coordinateSpaceName))]
                )
            }
        } else {
            Color.clear
        }
    }
}

enum HWCKeyboardLayoutMetrics {
    private static func baseInset(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool
    ) -> CGFloat {
        let extraInset: CGFloat = idiom == .pad ? 12 : 6
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return (verticalPadding(for: settings) * 2)
                + extraInset
                + topSuggestionStripHeight(for: settings, showsSuggestionStrip: showsSuggestionStrip)
        case .dark:
            return (verticalPadding(for: settings) * 2)
                + topSuggestionStripHeight(for: settings, showsSuggestionStrip: showsSuggestionStrip)
        }
    }

    static func rowSpacing(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 5
        case .dark:
            return 0
        }
    }

    static func panelSpacingFromToolbar(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 4
        case .dark:
            return 0
        }
    }

    static func horizontalPadding(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 6
        case .dark:
            return 0
        }
    }

    static func verticalPadding(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 8
        case .dark:
            return 0
        }
    }

    static func toolbarHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        CGFloat(KeyboardLayoutBounds.clampedToolbarHeight(settings.toolbarHeight))
    }

    static func topSuggestionStripHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        topSuggestionStripHeight(
            for: settings,
            showsSuggestionStrip: settings.showsSuggestionRail
        )
    }

    static func topSuggestionStripHeight(
        for settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool
    ) -> CGFloat {
        guard showsSuggestionStrip else { return 0 }
        return CGFloat(settings.suggestionRowHeight)
    }

    static func topSuggestionRailHorizontalInset(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return horizontalPadding(for: settings) + 10
        case .dark:
            return horizontalPadding(for: settings) + 14
        }
    }

    static func topSuggestionRailTopInset(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return 2
        case .dark:
            return 3
        }
    }

    static func suggestionLaneSplitPositions(for width: CGFloat) -> (firstEnd: CGFloat, secondEnd: CGFloat) {
        guard width > 0 else { return (0, 0) }

        let rfcColumnMidpoint = width * 0.35
        let ujnColumnMidpoint = width * 0.65
        return (rfcColumnMidpoint, ujnColumnMidpoint)
    }

    static func suggestionLaneIndex(for x: CGFloat, width: CGFloat) -> Int? {
        guard width > 0 else { return nil }

        let clampedX = min(max(x, 0), max(width - 1, 0))
        let splits = suggestionLaneSplitPositions(for: width)
        if clampedX < splits.firstEnd {
            return 0
        }
        if clampedX < splits.secondEnd {
            return 1
        }
        return 2
    }

    static func suggestionSlotIndex(for x: CGFloat, width: CGFloat, slotCount: Int) -> Int? {
        guard width > 0, slotCount > 0 else { return nil }
        guard slotCount != 3 else { return suggestionLaneIndex(for: x, width: width) }

        let clampedX = min(max(x, 0), max(width - 1, 0))
        return min(Int((clampedX / width) * CGFloat(slotCount)), slotCount - 1)
    }

    static func suggestionSlotIndex(for point: CGPoint, size: CGSize, slotCount: Int) -> Int? {
        guard size.width > 0, size.height > 0, slotCount > 0 else { return nil }
        return suggestionSlotIndex(for: point.x, width: size.width, slotCount: slotCount)
    }

    static func topSuggestionSlotMinimumHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        44
    }

    static func topSuggestionSlotClippedContentOffset(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        let slotHeight = topSuggestionSlotMinimumHeight(for: settings)
        let railHeight = topSuggestionStripHeight(for: settings, showsSuggestionStrip: true)
        return max(0, (slotHeight - railHeight) / 2)
    }

    static func topSuggestionSlotInteractionInsetY(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        topSuggestionSlotClippedContentOffset(for: settings)
    }

    static func suggestionRolodexChipTextOpticalAlignmentOffset(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        return topSuggestionSlotClippedContentOffset(for: settings)
    }

    static func darkThemeHorizontalNudge(
        for settings: KeyboardSettingsSnapshot,
        screenScale: CGFloat = UIScreen.main.scale
    ) -> CGFloat {
        guard settings.appTheme.usesDarkChrome else { return 0 }
        return 1.0 / screenScale
    }

    static func suggestionRolodexItemHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        settings.appTheme.usesDarkChrome ? 30 : 32
    }

    static func suggestionRationaleLayout(
        for settings: KeyboardSettingsSnapshot
    ) -> SuggestionRationaleLayout {
        let rowHeight = CGFloat(
            min(
                max(
                    settings.suggestionRowHeight,
                    KeyboardLayoutBounds.suggestionRowHeightRange.lowerBound
                ),
                KeyboardLayoutBounds.suggestionRowHeightRange.upperBound
            )
        )
        let spacing: CGFloat = 0
        let verticalPadding: CGFloat = 1
        let rationaleFontSize: CGFloat = rowHeight <= 30 ? 8 : 9
        let desiredTitleFontSize: CGFloat = settings.largeLegends ? 16 : 15
        let estimatedLineHeightScale: CGFloat = 1.2
        let maximumTitleFontSize = floor(
            ((rowHeight - (verticalPadding * 2) - spacing) / estimatedLineHeightScale)
                - rationaleFontSize
        )
        let titleFontSize = max(11, min(desiredTitleFontSize, maximumTitleFontSize))
        let estimatedContentHeight = ceil(
            ((titleFontSize + rationaleFontSize) * estimatedLineHeightScale)
                + spacing
                + (verticalPadding * 2)
        )
        return SuggestionRationaleLayout(
            titleFontSize: titleFontSize,
            rationaleFontSize: rationaleFontSize,
            spacing: spacing,
            verticalPadding: verticalPadding,
            estimatedContentHeight: estimatedContentHeight
        )
    }

    static func collapsedSuggestionStripHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return settings.largeLegends ? 12 : 10
        case .dark:
            return 12
        }
    }

    static func expandedKeyHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        CGFloat(KeyboardLayoutBounds.clampedExpandedKeyHeight(settings.expandedKeyHeight))
    }

    static func directionalKeySwipeMinimumTravel(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        max(88, expandedKeyHeight(for: settings) * 1.75)
    }

    static func directionalSwipeAxis(
        for translation: CGSize,
        minimumTravel: CGFloat
    ) -> HWCKeyboardDirectionalSwipeAxis? {
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        guard max(absX, absY) >= minimumTravel else { return nil }

        if absY >= absX {
            return translation.height < 0 ? .up : .down
        }
        return translation.width < 0 ? .left : .right
    }

    static func suggestionSwipeUpAxis(
        for translation: CGSize,
        minimumRise: CGFloat
    ) -> HWCKeyboardDirectionalSwipeAxis? {
        guard suggestionVerticalSwipeAxis(
            for: translation,
            minimumTravel: minimumRise
        ) == .up else {
            return nil
        }
        return .up
    }

    static func suggestionVerticalSwipeAxis(
        for translation: CGSize,
        minimumTravel: CGFloat
    ) -> HWCKeyboardDirectionalSwipeAxis? {
        let absX = abs(translation.width)
        let absY = abs(translation.height)
        guard absY >= minimumTravel else { return nil }
        guard absY >= absX * 0.6 else { return nil }
        return translation.height < 0 ? .up : .down
    }

    static func quickInsertHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        quickInsertHeight(for: settings, minimized: false)
    }

    static func quickInsertHeight(
        for settings: KeyboardSettingsSnapshot,
        minimized: Bool
    ) -> CGFloat {
        guard !minimized else { return 0 }

        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return max(30, expandedKeyHeight(for: settings) - 22)
        case .dark:
            return max(36, expandedKeyHeight(for: settings) - 12)
        }
    }

    static func collapsedQuickInsertHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return settings.largeLegends ? 12 : 10
        case .dark:
            return 12
        }
    }

    static func utilityRowHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        switch settings.appTheme {
        case .classic, .chameleon, .custom:
            return max(46, expandedKeyHeight(for: settings) - 2)
        case .dark:
            return max(54, expandedKeyHeight(for: settings))
        }
    }

    static func hiddenKeyboardHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool
    ) -> CGFloat {
        max(
            topSuggestionSlotMinimumHeight(for: settings),
            baseInset(
                for: idiom,
                settings: settings,
                showsSuggestionStrip: showsSuggestionStrip
            )
        )
    }

    static func collapsedHeight(for idiom: UIUserInterfaceIdiom, settings: KeyboardSettingsSnapshot) -> CGFloat {
        collapsedHeight(
            for: idiom,
            settings: settings,
            showsSuggestionStrip: settings.showsSuggestionRail
        )
    }

    static func collapsedHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool
    ) -> CGFloat {
        toolbarHeight(for: settings)
            + baseInset(
                for: idiom,
                settings: settings,
                showsSuggestionStrip: showsSuggestionStrip
            )
    }

    static func expandedHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot
    ) -> CGFloat {
        expandedHeight(
            for: idiom,
            settings: settings,
            showsSuggestionStrip: settings.showsSuggestionRail,
            quickInsertMinimized: false
        )
    }

    static func expandedHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool,
        quickInsertMinimized: Bool,
        additionalExpandedRows: Int = 0
    ) -> CGFloat {
        toolbarHeight(for: settings)
            + baseInset(
                for: idiom,
                settings: settings,
                showsSuggestionStrip: showsSuggestionStrip
            )
            + expandedPanelHeight(
                for: idiom,
                settings: settings,
                quickInsertMinimized: quickInsertMinimized,
                additionalExpandedRows: additionalExpandedRows
            )
    }

    static func expandedHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool,
        quickInsertMinimized: Bool,
        expandedRows: [KeyboardLayoutRow]
    ) -> CGFloat {
        toolbarHeight(for: settings)
            + baseInset(
                for: idiom,
                settings: settings,
                showsSuggestionStrip: showsSuggestionStrip
            )
            + expandedPanelHeight(
                for: idiom,
                settings: settings,
                quickInsertMinimized: quickInsertMinimized,
                expandedRows: expandedRows
            )
    }

    static func expandedPanelHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot
    ) -> CGFloat {
        expandedPanelHeight(
            for: idiom,
            settings: settings,
            quickInsertMinimized: false
        )
    }

    static func expandedPanelHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool,
        additionalExpandedRows: Int = 0
    ) -> CGFloat {
        expandedContentHeight(
            for: idiom,
            settings: settings,
            quickInsertMinimized: quickInsertMinimized,
            additionalExpandedRows: additionalExpandedRows
        ) + panelSpacingFromToolbar(for: settings)
    }

    static func expandedPanelHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool,
        expandedRows: [KeyboardLayoutRow]
    ) -> CGFloat {
        expandedContentHeight(
            for: idiom,
            settings: settings,
            quickInsertMinimized: quickInsertMinimized,
            expandedRows: expandedRows
        ) + panelSpacingFromToolbar(for: settings)
    }

    static func expandedContentHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot
    ) -> CGFloat {
        expandedContentHeight(
            for: idiom,
            settings: settings,
            quickInsertMinimized: false
        )
    }

    static func expandedContentHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool,
        additionalExpandedRows: Int = 0
    ) -> CGFloat {
        var rows = [CGFloat]()
        let showsQuickInsertRow = settings.showQuickInsertRow && !quickInsertMinimized

        if showsQuickInsertRow {
            rows.append(quickInsertHeight(for: settings, minimized: quickInsertMinimized))
        }

        rows.append(contentsOf: Array(repeating: expandedKeyHeight(for: settings), count: max(0, 3 + additionalExpandedRows)))

        let gaps = CGFloat(max(rows.count - 1, 0)) * rowSpacing(for: settings)
        let rowSeparators = CGFloat(max(rows.count - 1, 0)) * darkThemeRowSeparatorHeight(for: settings)
        let topSeparator = darkThemeTopSeparatorHeight(for: settings)
        return rows.reduce(0, +) + gaps + rowSeparators + topSeparator
    }

    static func expandedContentHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool,
        expandedRows: [KeyboardLayoutRow]
    ) -> CGFloat {
        var rows = [CGFloat]()
        let showsQuickInsertRow = settings.showQuickInsertRow && !quickInsertMinimized

        if showsQuickInsertRow {
            rows.append(quickInsertHeight(for: settings, minimized: quickInsertMinimized))
        }

        rows.append(contentsOf: expandedRows.map { expandedRowHeight(for: $0, settings: settings) })

        let gaps = CGFloat(max(rows.count - 1, 0)) * rowSpacing(for: settings)
        let rowSeparators = CGFloat(max(rows.count - 1, 0)) * darkThemeRowSeparatorHeight(for: settings)
        let topSeparator = darkThemeTopSeparatorHeight(for: settings)
        return rows.reduce(0, +) + gaps + rowSeparators + topSeparator
    }

    static func expandedRowHeight(
        for row: KeyboardLayoutRow,
        settings: KeyboardSettingsSnapshot
    ) -> CGFloat {
        let rowDefault = row.height ?? expandedKeyHeight(for: settings)
        let tallestKey = row.keys.compactMap(\.heightOverride).max() ?? rowDefault
        return max(rowDefault, tallestKey)
    }

    static func expandedKeyHeight(
        for key: KeyboardLayoutKey,
        row: KeyboardLayoutRow,
        settings: KeyboardSettingsSnapshot
    ) -> CGFloat {
        key.heightOverride ?? row.height ?? expandedKeyHeight(for: settings)
    }

    static func clipboardPanelHeight(
        for idiom: UIUserInterfaceIdiom,
        settings: KeyboardSettingsSnapshot,
        showsSuggestionStrip: Bool,
        quickInsertMinimized: Bool,
        expandedRows: [KeyboardLayoutRow]
    ) -> CGFloat {
        let activeExpandedHeight = expandedHeight(
            for: idiom,
            settings: settings,
            showsSuggestionStrip: showsSuggestionStrip,
            quickInsertMinimized: quickInsertMinimized,
            expandedRows: expandedRows
        )
        let minimumExpandedHeight = expandedHeight(
            for: idiom,
            settings: settings,
            showsSuggestionStrip: showsSuggestionStrip,
            quickInsertMinimized: quickInsertMinimized,
            additionalExpandedRows: 0
        )
        return max(activeExpandedHeight, minimumExpandedHeight)
    }

    static func expandedPanelBottomInset(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        verticalPadding(for: settings) + toolbarHeight(for: settings) + panelSpacingFromToolbar(for: settings)
    }

    static func darkThemeRowSeparatorHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        guard settings.appTheme.usesDarkChrome else { return 0 }
        return 3.0 / UIScreen.main.scale
    }

    static func darkThemeTopSeparatorHeight(for settings: KeyboardSettingsSnapshot) -> CGFloat {
        guard settings.appTheme.usesDarkChrome else { return 0 }
        return darkThemeRowSeparatorHeight(for: settings)
    }

    static func darkThemeExpandedLayerHeights(for settings: KeyboardSettingsSnapshot) -> [CGFloat] {
        darkThemeExpandedLayerHeights(for: settings, quickInsertMinimized: false)
    }

    static func darkThemeExpandedLayerHeights(
        for settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool
    ) -> [CGFloat] {
        guard settings.appTheme.usesDarkChrome else { return [] }
        let showsQuickInsertRow = settings.showQuickInsertRow && !quickInsertMinimized

        var heights = [
            expandedKeyHeight(for: settings) + darkThemeRowSeparatorHeight(for: settings),
            expandedKeyHeight(for: settings) + darkThemeRowSeparatorHeight(for: settings),
            expandedKeyHeight(for: settings) + darkThemeRowSeparatorHeight(for: settings),
        ]

        if showsQuickInsertRow {
            heights.append(
                quickInsertHeight(for: settings, minimized: quickInsertMinimized)
                    + darkThemeTopSeparatorHeight(for: settings)
            )
        } else if let topLayerIndex = heights.indices.last {
            heights[topLayerIndex] = expandedKeyHeight(for: settings) + darkThemeTopSeparatorHeight(for: settings)
        }

        return heights
    }

    static func darkThemeExpandedLayerHeights(
        for settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool,
        expandedRows: [KeyboardLayoutRow]
    ) -> [CGFloat] {
        guard settings.appTheme.usesDarkChrome else { return [] }
        let showsQuickInsertRow = settings.showQuickInsertRow && !quickInsertMinimized

        var heights = expandedRows.reversed().map {
            expandedRowHeight(for: $0, settings: settings) + darkThemeRowSeparatorHeight(for: settings)
        }

        if showsQuickInsertRow {
            heights.append(
                quickInsertHeight(for: settings, minimized: quickInsertMinimized)
                    + darkThemeTopSeparatorHeight(for: settings)
            )
        } else if let topLayerIndex = heights.indices.last, let topRow = expandedRows.first {
            heights[topLayerIndex] = expandedRowHeight(
                for: topRow,
                settings: settings
            ) + darkThemeTopSeparatorHeight(for: settings)
        }

        return heights
    }

    static func darkThemeExpandedPanelStageHeights(for settings: KeyboardSettingsSnapshot) -> [CGFloat] {
        darkThemeExpandedPanelStageHeights(for: settings, quickInsertMinimized: false)
    }

    static func darkThemeExpandedPanelStageHeights(
        for settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool
    ) -> [CGFloat] {
        var cumulative: CGFloat = 0

        return darkThemeExpandedLayerHeights(
            for: settings,
            quickInsertMinimized: quickInsertMinimized
        ).map { layerHeight in
            cumulative += layerHeight
            return cumulative
        }
    }

    static func darkThemeExpandedPanelStageHeights(
        for settings: KeyboardSettingsSnapshot,
        quickInsertMinimized: Bool,
        expandedRows: [KeyboardLayoutRow]
    ) -> [CGFloat] {
        var cumulative: CGFloat = 0

        return darkThemeExpandedLayerHeights(
            for: settings,
            quickInsertMinimized: quickInsertMinimized,
            expandedRows: expandedRows
        ).map { layerHeight in
            cumulative += layerHeight
            return cumulative
        }
    }
}

private extension UIColor {
    var bbSwiftUIColor: Color {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return Color(
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                opacity: Double(alpha)
            )
        }

        var white: CGFloat = 0
        if getWhite(&white, alpha: &alpha) {
            return Color(
                red: Double(white),
                green: Double(white),
                blue: Double(white),
                opacity: Double(alpha)
            )
        }

        return Color(red: 0, green: 0, blue: 0, opacity: 1)
    }
}

private struct KeyboardIsPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var keyboardIsPressed: Bool {
        get { self[KeyboardIsPressedKey.self] }
        set { self[KeyboardIsPressedKey.self] = newValue }
    }
}

private extension View {
    func keyboardPressedState(_ isPressed: Bool) -> some View {
        environment(\.keyboardIsPressed, isPressed)
    }
}

private struct KeyboardPressEffectModifier: ViewModifier {
    let theme: CompanionAppTheme
    let accent: Bool
    let suppressMotion: Bool
    let isPressed: Bool

    func body(content: Content) -> some View {
        let allowsMotion = isPressed && !suppressMotion

        content
            .scaleEffect(allowsMotion ? pressedScale : 1)
            .offset(y: allowsMotion ? pressedYOffset : 0)
            .opacity(allowsMotion ? 0.96 : 1)
            .brightness(isPressed ? pressedBrightness : 0)
            .saturation(isPressed ? 1.02 : 1)
            .overlay(
                pressOverlay
                    .opacity(isPressed ? pressedOverlayOpacity : 0)
                    .allowsHitTesting(false)
            )
            .animation(suppressMotion || isPressed ? nil : .easeOut(duration: 0.05), value: isPressed)
    }

    private var pressedScale: CGFloat {
        switch theme {
        case .classic, .chameleon, .custom:
            return accent ? 0.976 : 0.983
        case .dark:
            return accent ? 0.985 : 0.991
        }
    }

    private var pressedBrightness: Double {
        switch theme {
        case .classic, .chameleon, .custom:
            return accent ? -0.11 : -0.08
        case .dark:
            return -0.09
        }
    }

    private var pressedYOffset: CGFloat {
        switch theme {
        case .classic, .chameleon, .custom:
            return 1.0
        case .dark:
            return 0.4
        }
    }

    @ViewBuilder
    private var pressOverlay: some View {
        if theme.usesDarkChrome {
            Rectangle()
                .fill(Color.black)
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black)
        }
    }

    private var pressedOverlayOpacity: Double {
        switch theme {
        case .classic, .chameleon, .custom:
            return accent ? 0.18 : 0.14
        case .dark:
            return accent ? 0.34 : 0.28
        }
    }
}

private extension View {
    func keyboardPressEffect(
        theme: CompanionAppTheme,
        accent: Bool,
        suppressMotion: Bool,
        isPressed: Bool
    ) -> some View {
        modifier(
            KeyboardPressEffectModifier(
                theme: theme,
                accent: accent,
                suppressMotion: suppressMotion,
                isPressed: isPressed
            )
        )
    }
}

private struct KeyboardKeySurface: View {
    let theme: CompanionAppTheme
    let fillColor: Color
    let borderColor: Color
    let keyCornerRadius: CGFloat
    let keyStrokeWidth: CGFloat
    let darkThemeDividerColor: Color
    let darkThemeSeparatorWidth: CGFloat
    let darkThemeSeparatorInset: CGFloat
    let showsDarkThemeSeparator: Bool
    let shadowColor: Color
    let shadowRadius: CGFloat
    let shadowYOffset: CGFloat
    let pressedFillColor: Color?

    @Environment(\.keyboardIsPressed) private var keyboardIsPressed

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)

        if theme.usesDarkChrome {
            shape
                .fill(resolvedFillColor)
                .overlay(
                    Rectangle()
                        .fill(darkThemeDividerColor)
                        .frame(width: darkThemeSeparatorWidth)
                        .padding(.vertical, darkThemeSeparatorInset)
                        .opacity(showsDarkThemeSeparator ? 1 : 0),
                    alignment: .trailing
                )
        } else {
            shape
                .fill(resolvedFillColor)
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.05),
                                    Color.clear,
                                    Color.black.opacity(0.10),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    shape
                        .strokeBorder(borderColor, lineWidth: keyStrokeWidth)
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowYOffset)
        }
    }

    private var resolvedFillColor: Color {
        guard keyboardIsPressed, let pressedFillColor else { return fillColor }
        return pressedFillColor
    }
}

private struct KeyboardPressStyle: ButtonStyle {
    let theme: CompanionAppTheme
    let accent: Bool
    let suppressMotion: Bool
    let darkPressBorderColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .keyboardPressedState(configuration.isPressed)
            .keyboardPressEffect(
                theme: theme,
                accent: accent,
                suppressMotion: suppressMotion,
                isPressed: configuration.isPressed
            )
    }
}

private struct KeyboardDualActionButton<Content: View>: View {
    let theme: CompanionAppTheme
    let accent: Bool
    let suppressMotion: Bool
    let darkPressBorderColor: Color?
    let holdEnabled: Bool
    let holdDuration: TimeInterval
    let holdPreviewValue: String?
    let holdBeganAction: () -> Void
    let holdEndedAction: () -> Void
    let requiresHoldForSwipeUp: Bool
    let maximumDistance: CGFloat
    let interactionInsetX: CGFloat
    let interactionInsetY: CGFloat
    let interactionCornerRadius: CGFloat
    let touchDownAction: () -> Void
    let tapAction: () -> Void
    let holdAction: () -> Void
    let swipeUpAction: (() -> Void)?
    let swipeDownAction: (() -> Void)?
    let swipeLeftAction: (() -> Void)?
    let swipeRightAction: (() -> Void)?
    let shouldSuppressKeyCommit: () -> Bool
    let content: Content

    @State private var isPressing = false
    @State private var isTrackingTouch = false
    @State private var didTriggerHold = false
    @State private var interactionWasCancelled = false
    @State private var holdStartedAt: Date?
    @Environment(\.semiFoldKeyActionsSuppressed) private var shouldSuppressSemiFoldActions
    @Environment(\.semiFoldCancellationGeneration) private var semiFoldCancellationGeneration
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var touchDownFeedbackWorkItem: DispatchWorkItem?
    @State private var touchFeedbackSession = KeyboardTouchFeedbackSession()
    init(
        theme: CompanionAppTheme,
        accent: Bool,
        suppressMotion: Bool,
        darkPressBorderColor: Color? = nil,
        holdEnabled: Bool,
        holdDuration: TimeInterval,
        holdPreviewValue: String? = nil,
        holdBeganAction: @escaping () -> Void = {},
        holdEndedAction: @escaping () -> Void = {},
        requiresHoldForSwipeUp: Bool = false,
        maximumDistance: CGFloat = 44,
        interactionInsetX: CGFloat = 0,
        interactionInsetY: CGFloat = 0,
        interactionCornerRadius: CGFloat = 0,
        touchDownAction: @escaping () -> Void = {},
        tapAction: @escaping () -> Void,
        holdAction: @escaping () -> Void,
        swipeUpAction: (() -> Void)? = nil,
        swipeDownAction: (() -> Void)? = nil,
        swipeLeftAction: (() -> Void)? = nil,
        swipeRightAction: (() -> Void)? = nil,
        shouldSuppressKeyCommit: @escaping () -> Bool = { false },
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.accent = accent
        self.suppressMotion = suppressMotion
        self.darkPressBorderColor = darkPressBorderColor
        self.holdEnabled = holdEnabled
        self.holdDuration = holdDuration
        self.holdPreviewValue = holdPreviewValue
        self.holdBeganAction = holdBeganAction
        self.holdEndedAction = holdEndedAction
        self.requiresHoldForSwipeUp = requiresHoldForSwipeUp
        self.maximumDistance = maximumDistance
        self.interactionInsetX = interactionInsetX
        self.interactionInsetY = interactionInsetY
        self.interactionCornerRadius = interactionCornerRadius
        self.touchDownAction = touchDownAction
        self.tapAction = tapAction
        self.holdAction = holdAction
        self.swipeUpAction = swipeUpAction
        self.swipeDownAction = swipeDownAction
        self.swipeLeftAction = swipeLeftAction
        self.swipeRightAction = swipeRightAction
        self.shouldSuppressKeyCommit = shouldSuppressKeyCommit
        self.content = content()
    }

    var body: some View {
        content
            .overlay(alignment: .top) {
                holdPreview
            }
            .keyboardPressedState(isPressing)
            .keyboardPressEffect(
                theme: theme,
                accent: accent,
                suppressMotion: suppressMotion,
                isPressed: isPressing
            )
            .contentShape(
                KeyboardInteractionShape(
                    insetX: interactionInsetX,
                    insetY: interactionInsetY,
                    cornerRadius: interactionCornerRadius
                )
            )
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handlePressChanged(_:))
                    .onEnded(handlePressEnded(_:))
            )
            .onChange(of: semiFoldCancellationGeneration) { _, _ in cancelInteraction() }
            .accessibilityAddTraits(.isButton)
            .onDisappear {
                resetInteraction()
            }
    }

    @ViewBuilder
    private var holdPreview: some View {
        if didTriggerHold, let holdPreviewValue, !holdPreviewValue.isEmpty {
            Text(holdPreviewValue)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 12)
                .frame(minWidth: 42, minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                .offset(y: -42)
                .allowsHitTesting(false)
                .zIndex(1)
        }
    }

    private var isPressEffectActive: Bool {
        isPressing && !suppressMotion
    }

    private func handlePressChanged(_ value: DragGesture.Value) {
        guard !shouldSuppressSemiFoldActions() else { cancelInteraction(); return }
        if !isTrackingTouch {
            beginInteraction()
        }

        guard isTrackingTouch else { return }
        guard !interactionWasCancelled else { return }

        if shouldSuppressKeyCommit() && !canTriggerSwipeUp() {
            cancelInteraction()
            return
        }

        let distance = hypot(
            value.location.x - value.startLocation.x,
            value.location.y - value.startLocation.y
        )

        if configuredDirectionalSwipeAction(for: value.translation) != nil {
            return
        }

        guard distance <= maximumDistance else {
            cancelInteraction()
            return
        }
    }

    private func handlePressEnded(_ value: DragGesture.Value) {
        guard !shouldSuppressSemiFoldActions() else { cancelInteraction(); resetInteraction(); return }
        _ = forceHoldIfThresholdReached()
        let shouldTap = isTrackingTouch && !interactionWasCancelled && !didTriggerHold
        let shouldSwipeUp = isTrackingTouch && !interactionWasCancelled && canTriggerSwipeUp() && isSwipeUp(value.translation)
        let directionalAction = isTrackingTouch && !interactionWasCancelled
            ? configuredDirectionalSwipeAction(for: value.translation)
            : nil
        let shouldSuppressCommit = shouldSuppressKeyCommit()
        let needsTapFeedback = touchFeedbackSession.finish(
            acceptedTap: shouldTap && !shouldSwipeUp && directionalAction == nil && !shouldSuppressCommit
        )
        resetInteraction()

        if shouldSwipeUp {
            swipeUpAction?()
            return
        }

        if let directionalAction {
            directionalAction()
            return
        }

        if shouldSuppressCommit {
            return
        }

        guard shouldTap else { return }
        if needsTapFeedback { touchDownAction() }
        tapAction()
    }

    private func isSwipeUp(_ translation: CGSize) -> Bool {
        swipeUpAction != nil
            && HWCKeyboardLayoutMetrics.directionalSwipeAxis(
                for: translation,
                minimumTravel: 30
            ) == .up
    }

    private func configuredDirectionalSwipeAction(for translation: CGSize) -> (() -> Void)? {
        guard let axis = HWCKeyboardLayoutMetrics.directionalSwipeAxis(
            for: translation,
            minimumTravel: 30
        ) else { return nil }
        switch axis {
        case .up: return swipeUpAction
        case .down: return swipeDownAction
        case .left: return swipeLeftAction
        case .right: return swipeRightAction
        }
    }

    private func canTriggerSwipeUp() -> Bool {
        !requiresHoldForSwipeUp || didTriggerHold
    }

    private func beginInteraction() {
        interactionWasCancelled = false
        didTriggerHold = false
        isTrackingTouch = true
        isPressing = true
        touchFeedbackSession.begin()
        scheduleTouchDownFeedback()
        holdStartedAt = Date()
        scheduleHoldIfNeeded()
    }

    /// Renders the press before cold feedback. Accepted fast taps claim their
    /// pulse on release; cancelled touches and stale callbacks stay silent.
    private func scheduleTouchDownFeedback() {
        touchDownFeedbackWorkItem?.cancel()
        let generation = touchFeedbackSession.generation
        let workItem = DispatchWorkItem {
            guard isTrackingTouch, isPressing else { return }
            guard !shouldSuppressSemiFoldActions(),
                  touchFeedbackSession.claimScheduledFeedback(generation: generation) else { return }
            touchDownAction()
        }
        touchDownFeedbackWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleHoldIfNeeded() {
        guard holdEnabled else { return }

        let workItem = DispatchWorkItem {
            _ = triggerHoldIfPossible()
        }

        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: workItem)
    }

    private func forceHoldIfThresholdReached() -> Bool {
        guard holdEnabled, let holdStartedAt else { return false }
        guard Date().timeIntervalSince(holdStartedAt) >= holdDuration else { return false }
        return triggerHoldIfPossible()
    }

    private func triggerHoldIfPossible() -> Bool {
        guard !shouldSuppressSemiFoldActions() else { cancelInteraction(); return false }
        guard holdEnabled, isTrackingTouch, !interactionWasCancelled, !didTriggerHold else {
            return false
        }

        didTriggerHold = true
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdBeganAction()
        holdAction()
        return true
    }

    private func cancelInteraction() {
        interactionWasCancelled = true
        resetInteraction(preserveCancellation: true)
    }

    private func resetInteraction(preserveCancellation: Bool = false) {
        touchFeedbackSession.cancel()
        touchDownFeedbackWorkItem?.cancel()
        touchDownFeedbackWorkItem = nil
        holdWorkItem?.cancel()
        holdWorkItem = nil
        holdStartedAt = nil
        isTrackingTouch = false
        isPressing = false
        if didTriggerHold { holdEndedAction() }
        didTriggerHold = false

        if !preserveCancellation {
            interactionWasCancelled = false
        }
    }
}

private struct KeyboardInteractionShape: Shape {
    let insetX: CGFloat
    let insetY: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let resolvedRect = rect.insetBy(
            dx: min(insetX, rect.width / 2),
            dy: min(insetY, rect.height / 2)
        )

        guard resolvedRect.width > 0, resolvedRect.height > 0 else {
            return Rectangle().path(in: rect)
        }

        if cornerRadius > 0 {
            return RoundedRectangle(
                cornerRadius: max(0, cornerRadius - max(insetX, insetY)),
                style: .continuous
            )
            .path(in: resolvedRect)
        }

        return Rectangle().path(in: resolvedRect)
    }
}

private struct KeyboardRepeatButton<Content: View>: View {
    @Environment(\.semiFoldKeyActionsSuppressed) private var shouldSuppressSemiFoldActions
    @Environment(\.semiFoldCancellationGeneration) private var semiFoldCancellationGeneration
    let theme: CompanionAppTheme
    let accent: Bool
    let suppressMotion: Bool
    let darkPressBorderColor: Color?
    let repeatEnabled: Bool
    let initialDelay: TimeInterval
    let repeatInterval: TimeInterval
    let tapAction: () -> Void
    let holdStartAction: () -> Void
    let repeatAction: () -> Void
    let holdEndAction: () -> Void
    let shouldSuppressKeyCommit: () -> Bool
    let content: Content

    @State private var isPressing = false
    @State private var isTrackingTouch = false
    @State private var didTriggerRepeat = false
    @State private var interactionWasCancelled = false
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var repeatWorkItem: DispatchWorkItem?
    private let maximumDistance: CGFloat = 44

    init(
        theme: CompanionAppTheme,
        accent: Bool,
        suppressMotion: Bool,
        darkPressBorderColor: Color? = nil,
        repeatEnabled: Bool,
        initialDelay: TimeInterval,
        repeatInterval: TimeInterval,
        tapAction: @escaping () -> Void,
        holdStartAction: @escaping () -> Void,
        repeatAction: @escaping () -> Void,
        holdEndAction: @escaping () -> Void,
        shouldSuppressKeyCommit: @escaping () -> Bool = { false },
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.accent = accent
        self.suppressMotion = suppressMotion
        self.darkPressBorderColor = darkPressBorderColor
        self.repeatEnabled = repeatEnabled
        self.initialDelay = initialDelay
        self.repeatInterval = repeatInterval
        self.tapAction = tapAction
        self.holdStartAction = holdStartAction
        self.repeatAction = repeatAction
        self.holdEndAction = holdEndAction
        self.shouldSuppressKeyCommit = shouldSuppressKeyCommit
        self.content = content()
    }

    var body: some View {
        content
            .keyboardPressedState(isPressing)
            .keyboardPressEffect(
                theme: theme,
                accent: accent,
                suppressMotion: suppressMotion,
                isPressed: isPressing
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged(handlePressChanged(_:))
                    .onEnded(handlePressEnded(_:))
            )
            .onChange(of: semiFoldCancellationGeneration) { _, _ in cancelInteraction() }
            .accessibilityAddTraits(.isButton)
            .onDisappear {
                finishRepeatIfNeeded()
                resetInteraction()
            }
    }

    private var isPressEffectActive: Bool {
        isPressing && !suppressMotion
    }

    private func handlePressChanged(_ value: DragGesture.Value) {
        if !isTrackingTouch {
            beginInteraction()
        }

        guard isTrackingTouch else { return }
        guard !interactionWasCancelled else { return }

        if shouldSuppressKeyCommit() || shouldSuppressSemiFoldActions() {
            cancelInteraction()
            return
        }

        let distance = hypot(
            value.location.x - value.startLocation.x,
            value.location.y - value.startLocation.y
        )

        guard distance <= maximumDistance else {
            cancelInteraction()
            return
        }
    }

    private func handlePressEnded(_ value: DragGesture.Value) {
        let shouldTap = isTrackingTouch && !interactionWasCancelled && !didTriggerRepeat
        let shouldFinishRepeat = didTriggerRepeat
        let shouldSuppressCommit = shouldSuppressKeyCommit() || shouldSuppressSemiFoldActions()
        resetInteraction()

        if shouldFinishRepeat {
            holdEndAction()
        }

        guard shouldTap, !shouldSuppressCommit else { return }
        tapAction()
    }

    private func beginInteraction() {
        interactionWasCancelled = false
        didTriggerRepeat = false
        isTrackingTouch = true
        isPressing = true
        scheduleRepeatIfNeeded()
    }

    private func scheduleRepeatIfNeeded() {
        guard repeatEnabled else { return }

        let workItem = DispatchWorkItem {
            guard isTrackingTouch, !interactionWasCancelled, !didTriggerRepeat else { return }
            guard !shouldSuppressSemiFoldActions() else { cancelInteraction(); return }
            didTriggerRepeat = true
            holdStartAction()
            triggerRepeatStep()
        }

        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: workItem)
    }

    private func triggerRepeatStep() {
        guard !shouldSuppressSemiFoldActions() else { cancelInteraction(); return }
        guard isTrackingTouch, !interactionWasCancelled, didTriggerRepeat else { return }
        repeatAction()
        scheduleNextRepeat()
    }

    private func scheduleNextRepeat() {
        let workItem = DispatchWorkItem {
            guard isTrackingTouch, !interactionWasCancelled, didTriggerRepeat else { return }
            triggerRepeatStep()
        }

        repeatWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + repeatInterval, execute: workItem)
    }

    private func cancelInteraction() {
        let shouldFinishRepeat = didTriggerRepeat
        interactionWasCancelled = true
        resetInteraction(preserveCancellation: true)

        if shouldFinishRepeat {
            holdEndAction()
        }
    }

    private func finishRepeatIfNeeded() {
        guard didTriggerRepeat else { return }
        holdEndAction()
    }

    private func resetInteraction(preserveCancellation: Bool = false) {
        holdWorkItem?.cancel()
        repeatWorkItem?.cancel()
        holdWorkItem = nil
        repeatWorkItem = nil
        isTrackingTouch = false
        isPressing = false
        didTriggerRepeat = false

        if !preserveCancellation {
            interactionWasCancelled = false
        }
    }
}

private enum ExpandedPersistenceMode {
    case collapsed
    case oneShot
    case awaitingSecondAction
    case latched
}

fileprivate enum ToolbarIndicatorState {
    case off
    case primed
    case latched
}

private enum AccessoryHandlePlacement {
    case quickInsertRow
}

struct HWCKeyboardView: View {
    @ObservedObject var model: KeyboardViewModel
    @Environment(\.colorScheme) private var colorScheme
    private var keyboardIdiom: UIUserInterfaceIdiom { UIDevice.current.userInterfaceIdiom }
    private static let glideCoordinateSpace = "hwc-glide-keyboard-layout"

    var body: some View {
        GeometryReader { proxy in
            // Cap to the live host frame when it exists; Tapback relaunch can provide a compact host
            // before launch chrome is revealed, and stale stored height clips the top rows.
            let hostHeight = model.hostKeyboardHeight > 0 ? model.hostKeyboardHeight : proxy.size.height
            let liveHeight = proxy.size.height
            let resolvedHeight = liveHeight > 0 ? min(hostHeight, liveHeight) : hostHeight
            panelAwareKeyboardContent(in: CGSize(width: proxy.size.width, height: resolvedHeight))
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
        }
        .id(model.isClipboardPanelPresented ? "clipboard-panel-modal" : "keyboard-active")
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    @ViewBuilder
    private func panelAwareKeyboardContent(in size: CGSize) -> some View {
        if model.isClipboardPanelPresented {
            clipboardPanelModalContent(in: size)
        } else {
            ZStack {
                keyboardBackground
                if let title = model.edgeSwipeTitle {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityHidden(true)
                }
                keyboardContentBase(in: size)
                    .offset(x: model.edgeSwipeOffset)
                    .allowsHitTesting(!model.isEdgeSwipeActive)
                    .simultaneousGesture(lowerSuggestionSwipeGesture(in: size))
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
    }

    private func clipboardPanelModalContent(in size: CGSize) -> some View {
        ZStack(alignment: .bottom) {
            keyboardBackground
                .ignoresSafeArea()

            clipboardPanel
                .padding(.horizontal, HWCKeyboardLayoutMetrics.horizontalPadding(for: model.settings))
                .padding(.vertical, HWCKeyboardLayoutMetrics.verticalPadding(for: model.settings))
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(30)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
    }

    private func keyboardContentBase(in size: CGSize) -> some View {
        classicKeyboardContent
            .environment(\.semiFoldKeyActionsSuppressed, { model.semiFoldGestureClaimed })
            .environment(\.semiFoldCancellationGeneration, model.semiFoldSuppressionGeneration)
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: Self.glideCoordinateSpace)
            .contentShape(Rectangle())
            .onPreferenceChange(HWKGlideKeyLayoutPreferenceKey.self) { keys in
                model.glideKeyboardLayoutChangedHandler?(keys)
            }
            .onPreferenceChange(HWKSuggestionChipTextFramePreferenceKey.self) { frames in
                model.updateSuggestionRolodexChipTextFrames(frames)
            }
    }

    private var suppressKeyPressMotion: Bool {
        let policy = HWKReduceMotionPolicy(reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled)
        return !policy.allowsAnimation(for: .keyPress)
    }

    private var suppressNonEssentialMotion: Bool {
        let policy = HWKReduceMotionPolicy(reduceMotionEnabled: UIAccessibility.isReduceMotionEnabled)
        return !policy.allowsAnimation(for: .layoutTransition)
    }

    private var classicKeyboardContent: some View {
        ZStack(alignment: .bottom) {
            keyboardBackground
                .ignoresSafeArea()

            keyboardInteractiveLayer
                .allowsHitTesting(!model.isClipboardPanelPresented)
                .accessibilityHidden(model.isClipboardPanelPresented)

            if model.isClipboardPanelPresented {
                clipboardPanel
                    .padding(.horizontal, HWCKeyboardLayoutMetrics.horizontalPadding(for: model.settings))
                    .padding(.vertical, HWCKeyboardLayoutMetrics.verticalPadding(for: model.settings))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(30)
            }
        }
        .animation(suppressNonEssentialMotion ? nil : .easeInOut(duration: 0.18), value: model.settings.appTheme)
        .animation(suppressNonEssentialMotion ? nil : .easeInOut(duration: 0.16), value: model.settings.hideKeyboardEnabled)
        .animation(suppressNonEssentialMotion ? nil : .easeInOut(duration: 0.16), value: model.isClipboardPanelPresented)
    }

    private var keyboardInteractiveLayer: some View {
        ZStack(alignment: .bottom) {
            if reservesSuggestionRail {
                topSuggestionRailContainer
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .offset(x: darkThemeHorizontalNudge)
                .zIndex(model.expandedPanelInteractionElevated ? 0 : 2)
            }

            if !hidesKeyboardBody {
                classicExpandedPanel
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.top, reservedSuggestionRailContentInset)
                    .padding(.horizontal, HWCKeyboardLayoutMetrics.horizontalPadding(for: model.settings))
                    .padding(.bottom, HWCKeyboardLayoutMetrics.expandedPanelBottomInset(for: model.settings))
                    .offset(x: darkThemeHorizontalNudge)
                    .zIndex(model.expandedPanelInteractionElevated ? 3 : 0)
                    .allowsHitTesting(model.activeSuggestionRolodexLaneID == nil)

                classicActiveBottomStrip
                    .padding(.horizontal, HWCKeyboardLayoutMetrics.horizontalPadding(for: model.settings))
                    .padding(.vertical, HWCKeyboardLayoutMetrics.verticalPadding(for: model.settings))
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .offset(x: darkThemeHorizontalNudge)
                    .zIndex(1)
                    .allowsHitTesting(model.activeSuggestionRolodexLaneID == nil)
            }
        }
    }

    private var clipboardPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clipboard")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(keyLabelColor)
                    Text("\(model.clipboardPanelSnippets.count) saved")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(controlLabelColor.opacity(0.76))
                }

                Spacer(minLength: 8)

                clipboardPanelIconButton("arrow.clockwise", label: "Refresh clipboard") {
                    model.refreshClipboardPanelSnippets()
                }
                clipboardPanelIconButton("plus", label: "Add clipboard") {
                    model.addClipboardPanelSnippet()
                }
                .disabled(!model.isFullAccessAvailable)
                clipboardPanelIconButton("xmark", label: "Close clipboard") {
                    model.dismissClipboardPanel()
                }
            }

            if model.clipboardPanelSnippets.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No saved snippets")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(keyLabelColor)
                    Text("Use + to save the current clipboard.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(controlLabelColor.opacity(0.78))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(clipboardPanelCardFill)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(model.clipboardPanelSnippets.prefix(8))) { snippet in
                            clipboardPanelRow(snippet)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let status = model.clipboardPanelStatusText {
                Text(status)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(controlLabelColor.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            if !model.isFullAccessAvailable {
                Text("Full Access is needed only to save from Clipboard. Your pet and keyboard stay local.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(controlLabelColor.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(model.settings.appTheme.usesDarkChrome ? backgroundBaseColor.opacity(0.98) : backgroundBaseColor.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(keyBorderColor, lineWidth: 0.8)
                )
        )
        .accessibilityIdentifier("clipboard-panel")
    }

    private var clipboardPanelCardFill: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(model.settings.appTheme.usesDarkChrome ? Color.white.opacity(0.06) : Color.white.opacity(0.58))
    }

    private func clipboardPanelRow(_ snippet: HWKClipboardSnippet) -> some View {
        HStack(spacing: 8) {
            Button {
                model.applyClipboardPanelSnippet(snippet)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.label.isEmpty ? "Clipboard snippet" : snippet.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(keyLabelColor)
                        .lineLimit(1)
                    Text(snippet.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(controlLabelColor.opacity(0.78))
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            clipboardPanelIconButton("arrow.triangle.2.circlepath", label: "Update snippet") {
                model.updateClipboardPanelSnippet(snippet)
            }
            clipboardPanelIconButton("trash", label: "Delete snippet") {
                model.deleteClipboardPanelSnippet(snippet)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(clipboardPanelCardFill)
    }

    private func clipboardPanelIconButton(
        _ systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(controlLabelColor)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(model.settings.appTheme.usesDarkChrome ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var classicExpandedPanel: AnyView {
        AnyView(expandedPanel)
    }

    private var classicActiveBottomStrip: AnyView {
        AnyView(activeBottomStrip)
    }

    private var expandedPanel: some View {
        let panelHeight = HWCKeyboardLayoutMetrics.expandedContentHeight(
            for: keyboardIdiom,
            settings: model.settings,
            quickInsertMinimized: model.isQuickInsertRowMinimized,
            expandedRows: model.activeExpandedRows
        )
        let visibleHeight = currentExpandedPanelRevealHeight ?? (isExpandedPresentationActive ? panelHeight : 0)

        return ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    expandedPanelRows
                        .background(expandedPanelSurface)
                }

                if showsClassicQuickInsertHandleOverlay {
                    classicQuickInsertHandleOverlay
                        .padding(.top, 1)
                }
            }

            if showsQuickInsertRestoreHandle && model.settings.appTheme.usesDarkChrome {
                quickInsertRestoreHandle
            }
        }
            .frame(maxWidth: .infinity, alignment: .bottom)
            .frame(height: visibleHeight, alignment: .bottom)
            .clipped()
            .opacity(visibleHeight > 0 ? 1 : 0)
            .allowsHitTesting(allowsExpandedPanelHitTesting)
            .accessibilityHidden(!isExpandedPresentationActive)
    }

    private var allowsExpandedPanelHitTesting: Bool {
        return model.isExpanded && isExpandedPresentationActive
    }

    private var expandedPanelRows: AnyView {
        if model.settings.appTheme.usesDarkChrome {
            if model.isSemiFoldActive {
                return AnyView(darkThemeSplitExpandedPanel)
            }
            return AnyView(darkThemeExpandedCardStack)
        }

        return AnyView(classicDynamicExpandedPanel)
    }

    private var darkThemeSplitExpandedPanel: some View {
        let rows = model.activeExpandedRows
        return VStack(spacing: 0) {
            if showsExpandedQuickInsertRow {
                darkThemeAnimatedExpandedLayer(fromTop: 0, separatorTone: .top) {
                    quickInsertRow
                }
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                darkThemeAnimatedExpandedLayer(
                    fromTop: index + (showsExpandedQuickInsertRow ? 1 : 0),
                    separatorTone: index == 0 && !showsExpandedQuickInsertRow ? .top : .standard
                ) {
                    dynamicExpandedRow(row, rowIndex: index, rowCount: rows.count)
                }
            }
        }
    }

    private var classicDynamicExpandedPanel: some View {
        let rows = model.activeExpandedRows

        return VStack(spacing: HWCKeyboardLayoutMetrics.rowSpacing(for: model.settings)) {
            if showsExpandedQuickInsertRow {
                quickInsertRow
            }

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                dynamicExpandedRow(row, rowIndex: index, rowCount: rows.count)
            }
        }
    }

    private var classicLetterExpandedPanel: some View {
        VStack(spacing: HWCKeyboardLayoutMetrics.rowSpacing(for: model.settings)) {
            if showsExpandedQuickInsertRow {
                quickInsertRow
            }

            classicLetterRow(model.topRow, row: .letterTop)
                .padding(.horizontal, classicLetterTopInset)
            classicLetterRow(model.middleRow, row: .letterMiddle, horizontalInset: classicLetterMiddleInset)
            classicBottomLetterRow
        }
    }

    private func classicLetterRow(
        _ keys: [String],
        row: HWCKeyboardRowKind,
        horizontalInset: CGFloat = 0
    ) -> some View {
        GeometryReader { proxy in
            let widths = letterRowWidths(
                for: keys,
                row: row,
                availableWidth: max(0, proxy.size.width - (horizontalInset * 2)),
                spacing: keyRowSpacing
            )

            HStack(spacing: keyRowSpacing) {
                ForEach(keys.indices, id: \.self) { index in
                    keyButton(
                        keys[index],
                        row: row,
                        index: index,
                        band: row == .letterTop ? .top : .middle,
                        showsTrailingSeparator: false
                    )
                    .frame(width: widths[index])
                }
            }
            .padding(.horizontal, horizontalInset)
        }
        .frame(height: HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings))
    }

    private var classicBottomLetterRow: some View {
        GeometryReader { proxy in
            let sideInset = classicBottomLetterSideInset
            let deleteWidth = classicBottomLetterControlWidth(
                availableWidth: max(0, proxy.size.width - (sideInset * 2))
            )
            let letterWidths = letterRowWidths(
                for: model.bottomRow,
                row: .letterBottom,
                availableWidth: max(0, proxy.size.width - (sideInset * 2) - deleteWidth - keyRowSpacing),
                spacing: keyRowSpacing
            )

            HStack(spacing: keyRowSpacing) {
                bottomLetterLeadingKey(
                    model.letterBottomLeadingValue,
                    width: deleteWidth,
                    fillColor: fillColor(for: .bottom),
                    pressedFillColor: pressedFillColor(for: .bottom),
                    borderColor: keyBorderColor,
                    showsDarkThemeSeparator: false
                )
                ForEach(model.bottomRow.indices, id: \.self) { index in
                    keyButton(
                        model.bottomRow[index],
                        row: .letterBottom,
                        index: index,
                        band: .bottom,
                        showsTrailingSeparator: false
                    )
                    .frame(width: letterWidths[index])
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, sideInset)
        }
        .frame(height: HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings))
    }

    private func dynamicExpandedRow(
        _ layoutRow: KeyboardLayoutRow,
        rowIndex: Int,
        rowCount: Int
    ) -> some View {
        let renderRow = renderRowKind(for: layoutRow, rowIndex: rowIndex, rowCount: rowCount)
        let band = expandedBand(rowIndex: rowIndex, rowCount: rowCount)
        let keys = displayedKeys(for: layoutRow)
        let rowHeight = HWCKeyboardLayoutMetrics.expandedRowHeight(for: layoutRow, settings: model.settings)
        // Dark rows are edge-to-edge blocks. Classic's staggered outer padding
        // would turn the split halves into uneven, inset strips.
        let horizontalInset = model.settings.appTheme.usesDarkChrome ? 0 : dynamicHorizontalInset(for: renderRow)
        let includesLeadingControl = layoutRow.kind == .letterBottom && !model.isSymbolKeyboard
        let boundary: String? = model.isSymbolKeyboard ? nil
            : (renderRow == .letterTop ? "t" : renderRow == .letterMiddle ? "g" : renderRow == .letterBottom ? "v" : nil)
        let plan = KeyboardSemiFoldRowPlan(values: keys.map(\.tap),
                                           boundary: model.isSemiFoldActive ? boundary : nil,
                                           duplicateBoundary: renderRow != .letterTop)
        let placements = plan.sourceIndices.enumerated().map { offset, index in
            (id: keys[index].id.uuidString + (plan.sourceIndices[..<offset].contains(index) ? ".duplicate" : ""),
             sourceIndex: index)
        }

        return GeometryReader { proxy in
            let availableWidth = max(0, proxy.size.width - (horizontalInset * 2))
            let leadingWidth = includesLeadingControl
                ? classicBottomLetterControlWidth(availableWidth: availableWidth)
                : 0
            let keyAvailableWidth = max(
                0,
                availableWidth - leadingWidth - (includesLeadingControl ? keyRowSpacing : 0)
            )
            let widths = dynamicKeyWidths(
                for: keys,
                row: renderRow,
                availableWidth: keyAvailableWidth,
                spacing: keyRowSpacing
            )
            let layout = model.isSemiFoldActive
                ? AnyLayout(KeyboardSemiFoldRowLayout(gap: model.semiFoldGap, spacing: keyRowSpacing,
                                                      splitIndex: plan.leftCount + (includesLeadingControl ? 1 : 0)))
                : AnyLayout(HStackLayout(spacing: keyRowSpacing))

            layout {
                if includesLeadingControl {
                    bottomLetterLeadingKey(
                        model.letterBottomLeadingValue,
                        width: model.isSemiFoldActive ? nil : leadingWidth,
                        fillColor: fillColor(for: band),
                        pressedFillColor: pressedFillColor(for: band),
                        borderColor: keyBorderColor,
                        showsDarkThemeSeparator: model.settings.appTheme.usesDarkChrome,
                        darkThemeSeparatorInset: model.settings.appTheme.usesDarkChrome
                            ? darkThemeExpandedKeySeparatorInset
                            : nil
                    )
                }

                ForEach(placements, id: \.id) { placement in
                    let index = placement.sourceIndex
                    let key = keys[index]
                    dynamicKeyButton(
                        key,
                        actionKey: layoutRow.keys[index].tap,
                        row: renderRow,
                        index: index,
                        band: band,
                        showsTrailingSeparator: model.settings.appTheme.usesDarkChrome && index != keys.indices.last,
                        height: HWCKeyboardLayoutMetrics.expandedKeyHeight(
                            for: key,
                            row: layoutRow,
                            settings: model.settings
                        )
                    )
                    .frame(width: model.isSemiFoldActive ? nil : widths[index])
                    .layoutValue(key: KeyboardSemiFoldWeight.self,
                                 value: max(0.01, key.widthWeight) * letterKeyWidthSpan(for: key.tap, row: renderRow))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalInset)
        }
        .frame(height: rowHeight)
    }

    private func dynamicKeyButton(
        _ key: KeyboardLayoutKey,
        actionKey: String,
        row: HWCKeyboardRowKind,
        index: Int,
        band: ExpandedVisualBand,
        showsTrailingSeparator: Bool,
        height: CGFloat
    ) -> some View {
        actionAwareHardwareKeyButton(
            key: key.tap,
            actionKey: actionKey,
            row: row,
            holdValue: key.holdChoices.first ?? key.hold,
            holdChoices: key.holdChoices,
            holdKeyID: key.id
        ) {
            expandedKeyFace(
                key: key.tap,
                holdValue: key.holdChoices.first ?? key.hold,
                row: row,
                index: index,
                fontSize: expandedKeyLegendFontSize,
                fillColor: fillColor(for: band),
                borderColor: keyBorderColor,
                pressedFillColor: pressedFillColor(for: band),
                showsDarkThemeSeparator: showsTrailingSeparator,
                darkThemeSeparatorInset: model.settings.appTheme.usesDarkChrome
                    ? darkThemeExpandedKeySeparatorInset
                    : nil,
                height: height
            )
        }
        .disabled(key.tap.isEmpty)
        .opacity(key.tap.isEmpty ? 0.35 : 1.0)
        .frame(height: height)
    }

    private func displayedKeys(for row: KeyboardLayoutRow) -> [KeyboardLayoutKey] {
        guard !model.isSymbolKeyboard, model.isCapsShiftActive else { return row.keys }
        return row.keys.map { key in
            var nextKey = key
            nextKey.tap = key.tap.uppercased()
            return nextKey
        }
    }

    private func dynamicHorizontalInset(for row: HWCKeyboardRowKind) -> CGFloat {
        guard !model.isSymbolKeyboard else { return 0 }
        switch row {
        case .letterTop:
            return classicLetterTopInset
        case .letterMiddle:
            return classicLetterMiddleInset
        default:
            return 0
        }
    }

    private func expandedBand(rowIndex: Int, rowCount: Int) -> ExpandedVisualBand {
        if rowIndex <= 0 {
            return .top
        }
        if rowIndex >= rowCount - 1 {
            return .bottom
        }
        return .middle
    }

    private func renderRowKind(
        for row: KeyboardLayoutRow,
        rowIndex: Int,
        rowCount: Int
    ) -> HWCKeyboardRowKind {
        switch row.kind {
        case .symbolTop:
            return .symbolTop
        case .symbolMiddle:
            return .symbolMiddle
        case .symbolBottom:
            return .symbolBottom
        case .letterTop:
            return .letterTop
        case .letterMiddle:
            return .letterMiddle
        case .letterBottom:
            return .letterBottom
        default:
            if model.isSymbolKeyboard {
                if rowIndex <= 0 { return .symbolTop }
                return rowIndex >= rowCount - 1 ? .symbolBottom : .symbolMiddle
            }

            if rowIndex <= 0 { return .letterTop }
            return rowIndex >= rowCount - 1 ? .letterBottom : .letterMiddle
        }
    }

    private func dynamicKeyWidths(
        for keys: [KeyboardLayoutKey],
        row: HWCKeyboardRowKind,
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        let spans = keys.map { key in
            max(0.01, key.widthWeight) * letterKeyWidthSpan(for: key.tap, row: row)
        }
        let totalUnits = spans.reduce(CGFloat.zero, +)
        guard totalUnits > 0 else { return Array(repeating: 0, count: keys.count) }

        let totalSpacing = CGFloat(max(keys.count - 1, 0)) * spacing
        let unitWidth = max(0, (availableWidth - totalSpacing) / totalUnits)
        return spans.map { unitWidth * $0 }
    }

    private func letterRowWidths(
        for keys: [String],
        row: HWCKeyboardRowKind,
        availableWidth: CGFloat,
        spacing: CGFloat
    ) -> [CGFloat] {
        let spans = keys.map { letterKeyWidthSpan(for: $0, row: row) }
        let totalUnits = spans.reduce(CGFloat.zero, +)
        guard totalUnits > 0 else { return Array(repeating: 0, count: keys.count) }

        let totalSpacing = CGFloat(max(keys.count - 1, 0)) * spacing
        let unitWidth = max(0, (availableWidth - totalSpacing) / totalUnits)
        return spans.map { unitWidth * $0 }
    }

    private func letterKeyWidthSpan(for key: String, row: HWCKeyboardRowKind) -> CGFloat {
        guard (row == .letterMiddle || row == .letterBottom),
              !model.isSymbolKeyboard,
              KeyboardSpecialKeyAction.resolved(from: key) == .enter else {
            return 1
        }

        return 1.18
    }

    private var darkThemeExpandedCardStack: some View {
        ZStack(alignment: .bottom) {
            if showsExpandedQuickInsertRow {
                darkThemeAnimatedExpandedLayer(fromTop: 0, separatorTone: .top) {
                    quickInsertRow
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: 0))
                .zIndex(1)
            }

            if model.isSymbolKeyboard {
                darkThemeAnimatedExpandedLayer(
                    fromTop: showsExpandedQuickInsertRow ? 1 : 0,
                    separatorTone: showsExpandedQuickInsertRow ? .standard : .top
                ) {
                    symbolRow(model.topRow, row: .symbolTop, band: .top)
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: showsExpandedQuickInsertRow ? 1 : 0))
                .zIndex(2)

                darkThemeAnimatedExpandedLayer(fromTop: showsExpandedQuickInsertRow ? 2 : 1) {
                    symbolRow(model.middleRow, row: .symbolMiddle, band: .middle)
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: showsExpandedQuickInsertRow ? 2 : 1))
                .zIndex(3)

                darkThemeAnimatedExpandedLayer(fromTop: showsExpandedQuickInsertRow ? 3 : 2) {
                    symbolRow(model.bottomRow, row: .symbolBottom, band: .bottom)
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: showsExpandedQuickInsertRow ? 3 : 2))
                .zIndex(4)
            } else {
                darkThemeAnimatedExpandedLayer(
                    fromTop: showsExpandedQuickInsertRow ? 1 : 0,
                    separatorTone: showsExpandedQuickInsertRow ? .standard : .top
                ) {
                    darkThemeTopLetterRow
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: showsExpandedQuickInsertRow ? 1 : 0))
                .zIndex(2)

                darkThemeAnimatedExpandedLayer(fromTop: showsExpandedQuickInsertRow ? 2 : 1) {
                    darkThemeMiddleLetterRow
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: showsExpandedQuickInsertRow ? 2 : 1))
                .zIndex(3)

                darkThemeAnimatedExpandedLayer(fromTop: showsExpandedQuickInsertRow ? 3 : 2) {
                    darkThemeBottomLetterRow
                }
                .offset(y: darkThemeCardVerticalOffset(fromTop: showsExpandedQuickInsertRow ? 3 : 2))
                .zIndex(4)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: HWCKeyboardLayoutMetrics.expandedContentHeight(
                for: keyboardIdiom,
                settings: model.settings,
                quickInsertMinimized: model.isQuickInsertRowMinimized
            ),
            maxHeight: HWCKeyboardLayoutMetrics.expandedContentHeight(
                for: keyboardIdiom,
                settings: model.settings,
                quickInsertMinimized: model.isQuickInsertRowMinimized
            ),
            alignment: .bottom
        )
    }

    private var activeBottomStrip: AnyView {
        if model.settings.appTheme.usesDarkChrome {
            return AnyView(
                Group {
                    if model.isSemiFoldActive {
                        semiFoldBottomStrip
                    } else {
                        darkThemeActiveBottomStrip
                    }
                }
                    .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings), alignment: .bottom)
                    .clipped()
                    .background(collapsedStripSurface)
                    .overlay(darkThemeMainStripTopSeparator, alignment: .top)
            )
        } else if model.isSemiFoldActive {
            return AnyView(semiFoldBottomStrip)
        } else {
            return AnyView(
                ZStack(alignment: .bottom) {
                    collapsedStrip
                        .opacity(showsCollapsedBottomStrip ? 1 : 0)
                        .allowsHitTesting(showsCollapsedBottomStrip)

                    expandedBottomStrip
                        .opacity(showsExpandedBottomStrip ? 1 : 0)
                        .allowsHitTesting(showsExpandedBottomStrip)
                }
                .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings), alignment: .bottom)
                .clipped()
                .background(collapsedStripSurface)
            )
        }
    }

    private var isExpandedPresentationActive: Bool {
        if model.settings.appTheme.usesDarkChrome {
            return model.expansionRevealStage > 0
        }

        return model.isExpanded
    }

    private var showsCollapsedBottomStrip: Bool {
        if model.settings.appTheme.usesDarkChrome {
            return !model.isExpanded || model.expansionRevealStage < darkThemeExpandedRowCount
        }

        return !isExpandedPresentationActive
    }

    private var showsExpandedBottomStrip: Bool {
        if model.settings.appTheme.usesDarkChrome {
            return model.isExpanded && model.expansionRevealStage == darkThemeExpandedRowCount
        }

        return isExpandedPresentationActive
    }

    private var hasSuggestionStrip: Bool {
        model.settings.showsSuggestionRail && !model.suggestionStripItems.isEmpty
    }

    private var reservesSuggestionRail: Bool {
        model.settings.showsSuggestionRail
    }

    private var hidesKeyboardBody: Bool {
        model.settings.hideKeyboardEnabled
    }

    private var showsExpandedQuickInsertRow: Bool {
        model.settings.showQuickInsertRow && !model.isQuickInsertRowMinimized
    }

    private var showsQuickInsertRestoreHandle: Bool {
        model.settings.showQuickInsertRow
            && model.settings.showQuickInsertHandle
            && model.isQuickInsertRowMinimized
    }

    private var suggestionStripSlots: [KeyboardSuggestionItem?] {
        model.suggestionStripSlots
    }

    private var suggestionSwipeMinimumRise: CGFloat {
        model.settings.appTheme.usesDarkChrome ? 34 : 30
    }

    private var lowerSuggestionSwipeMinimumRise: CGFloat {
        26
    }

    private var suggestionSwipePreviewRise: CGFloat {
        10
    }

    private func lowerSuggestionSwipeGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !model.semiFoldGestureClaimed else { return }
                guard !model.isClipboardPanelPresented else { return }
                guard model.activeSuggestionRolodexLaneID == nil else {
                    model.suggestionSwipePreviewColumn = nil
                    model.updatePendingLowerSuggestionSwipeColumn(nil)
                    return
                }
                guard !model.shouldIgnoreLowerSuggestionSwipeForHold else {
                    model.clearLowerSuggestionSwipeForHoldOverride()
                    return
                }
                let previewColumn = previewLowerSuggestionSwipeColumn(for: value, in: size)
                model.suggestionSwipePreviewColumn = previewColumn
                model.updatePendingLowerSuggestionSwipeColumn(previewColumn)
                if previewColumn != nil {
                    model.beginDirectionalKeySwipeSuppression()
                } else if value.startLocation.y >= lowerSuggestionSwipeStartY(in: size) {
                    model.updateDirectionalKeySwipeSuppression(translation: value.translation)
                }
            }
            .onEnded { _ in
                guard !model.semiFoldGestureClaimed else { return }
                guard !model.isClipboardPanelPresented else { return }
                guard model.activeSuggestionRolodexLaneID == nil else {
                    model.suggestionSwipePreviewColumn = nil
                    model.updatePendingLowerSuggestionSwipeColumn(nil)
                    return
                }
                guard !model.shouldIgnoreLowerSuggestionSwipeForHold else {
                    model.clearLowerSuggestionSwipeForHoldOverride()
                    return
                }
                model.suggestionSwipePreviewColumn = nil
                model.updatePendingLowerSuggestionSwipeColumn(nil)
                model.finishDirectionalKeySwipeSuppression()
            }
    }

    private func suggestionSwipeGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                guard !model.isClipboardPanelPresented else { return }
                model.suggestionSwipePreviewColumn = previewSuggestionSwipeColumn(for: value, in: size)
            }
            .onEnded { value in
                guard !model.isClipboardPanelPresented else { return }
                defer {
                    model.suggestionSwipePreviewColumn = nil
                }

                guard let column = resolvedSuggestionSwipeColumn(for: value, in: size),
                      let suggestion = suggestionStripSlots[column],
                      let laneID = model.logicalSuggestionLaneID(forPhysicalLane: column) else {
                    return
                }

                model.commitSuggestionSwipeIfNeeded(laneID: laneID, fallback: suggestion)
            }
    }

    private func previewSuggestionSwipeColumn(
        for value: DragGesture.Value,
        in size: CGSize
    ) -> Int? {
        guard hasSuggestionStrip else { return nil }

        let translation = value.translation

        guard isLowerSuggestionSwipeUp(translation),
              let column = HWCKeyboardLaneWordGesturePolicy.landingColumnIndex(
                startLocation: value.startLocation,
                location: value.location,
                size: suggestionRailGestureSize(in: size),
                slotCount: model.settings.suggestionVisibleWordCount
              ),
              suggestionStripSlots[column] != nil else {
            return nil
        }

        return column
    }

    private func previewLowerSuggestionSwipeColumn(
        for value: DragGesture.Value,
        in size: CGSize
    ) -> Int? {
        guard value.startLocation.y >= lowerSuggestionSwipeStartY(in: size) else { return nil }

        let translation = value.translation

        guard lowerSuggestionSwipePreviewAxis(translation) != nil,
              let column = HWCKeyboardLaneWordGesturePolicy.landingColumnIndex(
                startLocation: value.startLocation,
                location: value.location,
                size: suggestionRailGestureSize(in: size),
                slotCount: model.settings.suggestionVisibleWordCount
              ),
              suggestionStripSlots[column] != nil else {
            return nil
        }

        return column
    }

    private func resolvedSuggestionSwipeColumn(
        for value: DragGesture.Value,
        in size: CGSize
    ) -> Int? {
        guard hasSuggestionStrip else { return nil }

        let translation = value.translation
        let maximumHorizontalDrift = max(44, size.width / 5.5)

        guard translation.height <= -suggestionSwipeMinimumRise,
              abs(translation.width) <= maximumHorizontalDrift || abs(translation.height) >= abs(translation.width) * 1.35,
              let column = suggestionSlotIndex(for: value.startLocation, in: size),
              suggestionStripSlots[column] != nil else {
            return nil
        }

        return column
    }

    private func resolvedLowerSuggestionSwipeColumn(
        for value: DragGesture.Value,
        in size: CGSize
    ) -> Int? {
        guard hasSuggestionStrip,
              value.startLocation.y >= lowerSuggestionSwipeStartY(in: size) else {
            return nil
        }

        let translation = value.translation

        guard lowerSuggestionSwipePreviewAxis(translation) != nil,
              let column = suggestionSlotIndex(for: value.location, in: size),
              suggestionStripSlots[column] != nil else {
            return nil
        }

        return column
    }

    private func isLowerSuggestionSwipeUp(_ translation: CGSize) -> Bool {
        lowerSuggestionSwipePreviewAxis(translation) == .up
    }

    private func lowerSuggestionSwipePreviewAxis(
        _ translation: CGSize
    ) -> HWCKeyboardDirectionalSwipeAxis? {
        guard let axis = HWCKeyboardLayoutMetrics.suggestionVerticalSwipeAxis(
            for: translation,
            minimumTravel: lowerSuggestionSwipeMinimumRise
        ) else {
            return nil
        }
        switch axis {
        case .up:
            return model.settings.suggestionSwipeUpAction == .off ? nil : .up
        case .down:
            return model.settings.suggestionSwipeDownAction == .rolodex ? .down : nil
        case .left, .right:
            return nil
        }
    }

    private func lowerSuggestionSwipeStartY(in size: CGSize) -> CGFloat {
        let railHeight = HWCKeyboardLayoutMetrics.topSuggestionStripHeight(
            for: model.settings,
            showsSuggestionStrip: true
        )
        return min(max(railHeight + 8, size.height * 0.18), max(size.height - 44, 0))
    }

    private func suggestionSlotIndex(for point: CGPoint, in size: CGSize) -> Int? {
        HWCKeyboardLayoutMetrics.suggestionSlotIndex(
            for: point,
            size: suggestionRailGestureSize(in: size),
            slotCount: model.settings.suggestionVisibleWordCount
        )
    }

    private func suggestionRailGestureSize(in size: CGSize) -> CGSize {
        CGSize(
            width: size.width,
            height: HWCKeyboardLayoutMetrics.topSuggestionStripHeight(
                for: model.settings,
                showsSuggestionStrip: true
            )
        )
    }

    private var topSuggestionRailHorizontalInset: CGFloat {
        HWCKeyboardLayoutMetrics.topSuggestionRailHorizontalInset(for: model.settings)
    }

    private var topSuggestionRailTopInset: CGFloat {
        HWCKeyboardLayoutMetrics.topSuggestionRailTopInset(for: model.settings)
    }

    private var reservedSuggestionRailContentInset: CGFloat {
        reservesSuggestionRail ? suggestionRolodexRailVisualHeight : 0
    }

    private var quickInsertRailShowsHandle: Bool {
        model.settings.appTheme.usesDarkChrome && model.settings.showQuickInsertHandle
    }

    private var showsClassicQuickInsertHandleOverlay: Bool {
        model.settings.appTheme == .classic
            && model.settings.showQuickInsertRow
            && model.settings.showQuickInsertHandle
    }

    private var quickInsertHandleAccessibilityLabel: String {
        model.isQuickInsertRowMinimized ? "Show shortcut row" : "Hide shortcut row"
    }

    private var classicQuickInsertHandleOverlay: some View {
        Button {
            model.toggleQuickInsertRowMinimized()
        } label: {
            accessoryHandleVisual(for: .quickInsertRow)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(
            width: accessoryHandleTapWidth(for: .quickInsertRow),
            height: accessoryHandleTapHeight(for: .quickInsertRow),
            alignment: .top
        )
        .accessibilityLabel(quickInsertHandleAccessibilityLabel)
    }

    private var topSuggestionRailContainer: some View {
        topSuggestionRailContainerContent
    }

    private var topSuggestionRailContainerContent: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                topSuggestionRailSurface
                    .frame(height: topSuggestionRailBaseHeight)
                    .offset(y: suggestionRolodexRailLift)
                    .allowsHitTesting(false)
                suggestionRailContent
                    .padding(.horizontal, topSuggestionRailHorizontalInset)
                    .padding(.top, topSuggestionRailTopInset)
                    .frame(height: suggestionRolodexRailVisualHeight, alignment: .top)
            }
            .frame(width: geometry.size.width, height: suggestionRolodexRailVisualHeight, alignment: .top)
        }
        .frame(
            height: suggestionRolodexRailVisualHeight,
            alignment: .top
        )
        .offset(y: -suggestionRolodexRailLift)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var topSuggestionRailBaseHeight: CGFloat {
        HWCKeyboardLayoutMetrics.topSuggestionStripHeight(
            for: model.settings,
            showsSuggestionStrip: true
        )
    }

    private var topSuggestionRailLift: CGFloat {
        HWCKeyboardLayoutMetrics.topSuggestionSlotClippedContentOffset(for: model.settings)
    }

    private var topSuggestionSlotInteractionInsetY: CGFloat {
        HWCKeyboardLayoutMetrics.topSuggestionSlotInteractionInsetY(for: model.settings)
    }

    private var suggestionRolodexRailVisualHeight: CGFloat {
        topSuggestionRailBaseHeight
    }

    private var suggestionRolodexRailLift: CGFloat {
        0
    }

    @ViewBuilder
    private var suggestionRailContent: some View {
        GeometryReader { geometry in
            KeyboardSuggestionContentScope(invalidation: model.suggestionContentInvalidation) {
                let placements = model.visibleSuggestionRailPlacements
                let activeIndex = model.activeSuggestionRolodexLaneID.flatMap { laneID in
                    placements.firstIndex { $0.lane.id == laneID }
                }
                let activePreferredWidth = model.activeSuggestionRolodexLane?.selectedItem.map(
                    suggestionRolodexPreferredWidth(for:)
                )
                let widths = SuggestionRailWidthLayout.widths(
                    totalWidth: geometry.size.width,
                    laneSpans: placements.map(\.laneSpan),
                    activeIndex: activeIndex,
                    activePreferredWidth: activePreferredWidth
                )
                HStack(spacing: 0) {
                    ForEach(Array(placements.enumerated()), id: \.element.startLane) { index, placement in
                        topSuggestionSlot(placement)
                            .frame(width: widths.indices.contains(index) ? widths[index] : 0)
                    }
                }
                .animation(suggestionChipChangeAnimation, value: activePreferredWidth)
                .opacity(hasSuggestionStrip ? 1 : 0)
                .offset(y: hasSuggestionStrip ? -topSuggestionRailLift : -(topSuggestionRailLift + 3))
                .animation(nil, value: hasSuggestionStrip)
                .allowsHitTesting(hasSuggestionStrip)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var suggestionChipChangeAnimation: Animation? {
        suppressNonEssentialMotion ? nil : .easeInOut(duration: 0.18)
    }

    private func suggestionRolodexPreferredWidth(for item: KeyboardSuggestionItem) -> CGFloat {
        let fontSize: CGFloat = model.settings.largeLegends ? 17 : 16
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        let textWidth = (item.title as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth + 32)
    }

    private var currentExpandedPanelRevealHeight: CGFloat? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        guard model.expansionRevealStage > 0 else { return 0 }
        return HWCKeyboardLayoutMetrics.expandedContentHeight(
            for: keyboardIdiom,
            settings: model.settings,
            quickInsertMinimized: model.isQuickInsertRowMinimized
        )
    }

    private var collapsedStrip: some View {
        HStack(spacing: toolbarSpacing) {
            if model.showsNextKeyboardKey {
                toolbarIconKey("globe", isEnabled: true, accessibilityLabel: "Next Keyboard") {
                    model.advanceToNextKeyboard()
                }
            }

            ForEach(model.toolbarValues.indices, id: \.self) { index in
                toolbarInsertKey(model.toolbarValues[index], index: index)
            }
            ForEach(mainRowPrimaryTrailingControlItems(row: .trailingUtility, values: model.trailingUtilityValues)) { item in
                toolbarValueKey(
                    item.value,
                    row: .trailingUtility
                )
                .id(trailingControlIdentity(row: .trailingUtility, index: item.index, value: item.value))
            }
            ForEach(fixedTrailingControlItems(row: .trailingUtility, values: model.trailingUtilityValues)) { item in
                toolbarValueKey(
                    item.value,
                    row: .trailingUtility
                )
                .id(trailingControlIdentity(row: .trailingUtility, index: item.index, value: item.value))
            }
        }
        .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
        .contentShape(Rectangle())
    }

    private var semiFoldBottomStrip: some View {
        let expanded = model.settings.appTheme.usesDarkChrome
            ? darkThemeBottomControlsAreExpanded : isExpandedPresentationActive
        let values = expanded ? (model.isSymbolKeyboard ? model.symbolUtilityValues : model.letterUtilityValues) : model.toolbarValues
        let row: HWCKeyboardRowKind = expanded ? (model.isSymbolKeyboard ? .symbolUtility : .letterUtility) : .toolbar
        let trailing = expanded ? model.activeExpandedTrailingUtilityValues : model.trailingUtilityValues
        let trailingRow: HWCKeyboardRowKind = expanded ? model.activeExpandedTrailingUtilityRow : .trailingUtility
        let space = values.first { KeyboardSpecialKeyAction.resolved(from: $0) == .space }
        let plan = KeyboardSemiFoldRowPlan(values: values, boundary: space?.lowercased(), duplicateBoundary: true,
                                          allowsTerminalDuplication: true)
        let splitIndex = space == nil ? nil : plan.leftCount + (model.showsNextKeyboardKey ? 1 : 0)
        return KeyboardSemiFoldRowLayout(gap: model.semiFoldGap, spacing: toolbarSpacing, splitIndex: splitIndex) {
            if model.showsNextKeyboardKey {
                toolbarIconKey("globe", accessibilityLabel: "Next Keyboard") { model.advanceToNextKeyboard() }
            }
            ForEach(plan.sourceIndices.indices, id: \.self) { position in
                let index = plan.sourceIndices[position]
                toolbarValueKey(values[index], row: row, holdValue: model.holdValue(for: row, index: index))
                    .layoutValue(key: KeyboardSemiFoldWeight.self,
                                 value: KeyboardSpecialKeyAction.resolved(from: values[index]) == .space
                                    ? (model.settings.appTheme.usesDarkChrome ? 3 : 2.5) : 1)
            }
            ForEach(trailingControlItems(row: trailingRow, values: trailing)) { item in
                toolbarValueKey(item.value, row: trailingRow)
                    .id(trailingControlIdentity(row: trailingRow, index: item.index, value: item.value))
            }
        }
        .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
        .background(collapsedStripSurface)
    }

    private var expandedBottomStrip: some View {
        GeometryReader { proxy in
            let spacing = toolbarSpacing
            let symbolUtilitySpans = HWCExpandedBottomStripLayout.controlSpans(for: model.symbolUtilityValues)
            let spans = classicExpandedBottomControlSpans
            let symbolUnitWidth = toolbarUnitWidth(
                availableWidth: proxy.size.width,
                spans: spans,
                spacing: spacing
            )
            let classicLetterFixedControlCount = CGFloat((model.showsNextKeyboardKey ? 1 : 0) + 4)
            let classicLetterTotalSpacing = spacing * classicLetterFixedControlCount
            let classicLetterControlWidth = max(
                34,
                min(
                    44,
                    (proxy.size.width - classicLetterTotalSpacing) / (classicLetterFixedControlCount + 3)
                )
            )
            let classicLetterSpaceWidth = max(
                0,
                proxy.size.width
                    - classicLetterTotalSpacing
                    - (classicLetterControlWidth * classicLetterFixedControlCount)
            )

            HStack(spacing: spacing) {
                if model.showsNextKeyboardKey {
                    toolbarIconKey("globe", isEnabled: true, accessibilityLabel: "Next Keyboard") {
                        model.advanceToNextKeyboard()
                    }
                    .frame(
                        width: model.isSymbolKeyboard
                            ? toolbarWidth(span: 1, unitWidth: symbolUnitWidth, spacing: spacing)
                            : classicLetterControlWidth
                    )
                }

                if model.isSymbolKeyboard {
                    ForEach(model.symbolUtilityValues.indices, id: \.self) { index in
                        toolbarValueKey(
                            model.symbolUtilityValues[index],
                            row: .symbolUtility
                        )
                        .frame(width: toolbarWidth(span: symbolUtilitySpans[index], unitWidth: symbolUnitWidth, spacing: spacing))
                    }

                    ForEach(trailingControlItems(row: .expandedTrailingUtility, values: model.expandedTrailingUtilityValues)) { item in
                        toolbarValueKey(
                            item.value,
                            row: .expandedTrailingUtility
                        )
                        .id(trailingControlIdentity(row: .expandedTrailingUtility, index: item.index, value: item.value))
                        .frame(width: toolbarWidth(span: 1, unitWidth: symbolUnitWidth, spacing: spacing))
                    }
                } else {
                    toolbarValueKey(
                        model.letterUtilityValues[0],
                        row: .letterUtility
                    )
                    .frame(width: classicLetterControlWidth)

                    toolbarValueKey(
                        model.letterUtilityValues[1],
                        row: .letterUtility
                    )
                    .frame(width: classicLetterControlWidth)

                    toolbarValueKey(
                        model.letterUtilityValues[2],
                        row: .letterUtility
                    )
                    .frame(width: classicLetterSpaceWidth)

                    ForEach(trailingControlItems(row: .expandedLetterTrailingUtility, values: model.expandedLetterTrailingUtilityValues)) { item in
                        toolbarValueKey(
                            item.value,
                            row: .expandedLetterTrailingUtility
                        )
                        .id(trailingControlIdentity(row: .expandedLetterTrailingUtility, index: item.index, value: item.value))
                        .frame(width: classicLetterControlWidth)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
        .contentShape(Rectangle())
    }

    private var darkThemeActiveBottomStrip: some View {
        HStack(spacing: 0) {
            let visibleTrailingValues = darkThemeBottomControlsAreExpanded ? model.activeExpandedTrailingUtilityValues : model.trailingUtilityValues
            let visibleTrailingRow = darkThemeBottomControlsAreExpanded ? model.activeExpandedTrailingUtilityRow : .trailingUtility

            if model.showsNextKeyboardKey {
                toolbarIconKey("globe", isEnabled: true, accessibilityLabel: "Next Keyboard") {
                    model.advanceToNextKeyboard()
                }
                .frame(width: darkThemeBottomLeadingWidth)
            }

            ZStack {
                HStack(spacing: 0) {
                    ForEach(model.toolbarValues.indices, id: \.self) { index in
                        toolbarInsertKey(model.toolbarValues[index], index: index)
                    }
                    ForEach(mainRowPrimaryTrailingControlItems(row: visibleTrailingRow, values: visibleTrailingValues)) { item in
                        toolbarValueKey(
                            item.value,
                            row: visibleTrailingRow
                        )
                        .id(trailingControlIdentity(row: visibleTrailingRow, index: item.index, value: item.value))
                    }
                }
                .opacity(darkThemeBottomControlsAreExpanded ? 0 : 1)
                .allowsHitTesting(!darkThemeBottomControlsAreExpanded)

                GeometryReader { proxy in
                    let spacing: CGFloat = 0
                    let letterControlUnitWidth = max(0, proxy.size.width / 5)
                    let symbolUtilitySpans = HWCExpandedBottomStripLayout.controlSpans(for: model.symbolUtilityValues)
                    let symbolUnitWidth = toolbarUnitWidth(
                        availableWidth: proxy.size.width,
                        spans: symbolUtilitySpans,
                        spacing: spacing
                    )

                    HStack(spacing: 0) {
                        if model.isSymbolKeyboard {
                            ForEach(model.symbolUtilityValues.indices, id: \.self) { index in
                                toolbarValueKey(
                                    model.symbolUtilityValues[index],
                                    row: .symbolUtility
                                )
                                .frame(width: toolbarWidth(span: symbolUtilitySpans[index], unitWidth: symbolUnitWidth, spacing: spacing))
                            }
                        } else {
                            toolbarValueKey(
                                model.letterUtilityValues[0],
                                row: .letterUtility
                            )
                            .frame(width: letterControlUnitWidth)

                            toolbarValueKey(
                                model.letterUtilityValues[1],
                                row: .letterUtility
                            )
                            .frame(width: letterControlUnitWidth)

                            toolbarValueKey(
                                model.letterUtilityValues[2],
                                row: .letterUtility
                            )
                            .frame(width: letterControlUnitWidth * 3)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                }
                .opacity(darkThemeBottomControlsAreExpanded ? 1 : 0)
                .allowsHitTesting(darkThemeBottomControlsAreExpanded)
            }
            .animation(nil, value: darkThemeBottomControlsAreExpanded)
            .frame(maxWidth: .infinity)
            .transaction { transaction in
                transaction.animation = nil
                transaction.disablesAnimations = true
            }

            ForEach(fixedTrailingControlItems(row: visibleTrailingRow, values: visibleTrailingValues)) { item in
                toolbarValueKey(
                    item.value,
                    row: visibleTrailingRow
                )
                .id(trailingControlIdentity(row: visibleTrailingRow, index: item.index, value: item.value))
                .frame(width: darkThemeBottomTrailingWidth)
            }
        }
        .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
        .contentShape(Rectangle())
    }

    private var darkThemeTopLetterRow: some View {
        darkThemeLetterRow(
            keys: darkThemeVisibleTopRow,
            row: .letterTop
        )
    }

    private var darkThemeMiddleLetterRow: some View {
        darkThemeLetterRow(
            keys: darkThemeVisibleMiddleRow,
            row: .letterMiddle
        )
    }

    private var darkThemeBottomLetterRow: some View {
        GeometryReader { proxy in
            let spans = darkThemeVisibleBottomRow.map { letterKeyWidthSpan(for: $0, row: .letterBottom) }
            let totalUnits = max(1, spans.reduce(CGFloat(1), +))
            let unitWidth = max(0, proxy.size.width / totalUnits)
            let deleteWidth = unitWidth
            let letterWidths = spans.map { unitWidth * $0 }

            HStack(spacing: 0) {
                bottomLetterLeadingKey(
                    model.letterBottomLeadingValue,
                    width: deleteWidth,
                    fillColor: darkThemeBottomLetterRowFill,
                    pressedFillColor: darkThemePressedFillColor(for: .letterBottom),
                    borderColor: keyBorderColor,
                    showsDarkThemeSeparator: true,
                    darkThemeSeparatorInset: darkThemeExpandedKeySeparatorInset
                )

                ForEach(darkThemeVisibleBottomRow.indices, id: \.self) { index in
                    darkThemeLetterKeyCell(
                        darkThemeVisibleBottomRow[index],
                        row: .letterBottom,
                        index: index,
                        fillColor: darkThemeFillColor(for: .letterBottom),
                        pressedFillColor: darkThemePressedFillColor(for: .letterBottom)
                    )
                        .frame(width: letterWidths[index])
                }
            }
        }
        .frame(height: HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings))
    }

    private func bottomLetterLeadingKey(
        _ value: String,
        width: CGFloat?,
        fillColor: Color,
        pressedFillColor: Color?,
        borderColor: Color,
        showsDarkThemeSeparator: Bool,
        darkThemeSeparatorInset: CGFloat? = nil
    ) -> some View {
        actionAwareHardwareKeyButton(
            key: value,
            row: .letterBottomLeading,
            holdValue: nil
        ) {
            expandedKeyFace(
                key: value,
                holdValue: nil,
                row: .letterBottomLeading,
                index: 0,
                fontSize: expandedKeyLegendFontSize,
                fillColor: fillColor,
                borderColor: borderColor,
                pressedFillColor: pressedFillColor,
                showsDarkThemeSeparator: showsDarkThemeSeparator,
                darkThemeSeparatorInset: darkThemeSeparatorInset
            )
        }
        .frame(width: width)
        .frame(height: HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings))
        .disabled(value.isEmpty)
        .opacity(value.isEmpty ? (model.settings.appTheme.usesDarkChrome ? 0.28 : 0.35) : 1)
        .accessibilityLabel("Bottom control")
    }

    private enum DarkThemeSeparatorTone {
        case standard
        case top
    }

    private var darkThemeVisibleTopRow: [String] {
        model.topRow
    }

    private var darkThemeVisibleMiddleRow: [String] {
        model.middleRow
    }

    private var darkThemeVisibleBottomRow: [String] {
        model.bottomRow
    }

    private var darkThemeToolbarHeight: CGFloat {
        HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings)
    }

    private var darkThemeBottomUtilityHeight: CGFloat {
        HWCKeyboardLayoutMetrics.utilityRowHeight(for: model.settings)
    }

    private var darkThemeBottomLeadingWidth: CGFloat {
        max(54, min(74, HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings) * 1.15))
    }

    private var darkThemeBottomTrailingWidth: CGFloat {
        max(58, min(82, HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings) * 1.22))
    }

    private var darkThemeBottomControlsAreExpanded: Bool {
        guard model.settings.appTheme.usesDarkChrome else { return isExpandedPresentationActive }
        return model.darkThemeBottomControlsExpanded
    }

    private func darkThemeLetterRowWidths(
        for keys: [String],
        row: HWCKeyboardRowKind,
        availableWidth: CGFloat
    ) -> [CGFloat] {
        let horizontalInset = dynamicHorizontalInset(for: row)
        let coreWidths = letterRowWidths(
            for: keys,
            row: row,
            availableWidth: max(0, availableWidth - (horizontalInset * 2)),
            spacing: 0
        )

        return coreWidths.enumerated().map { index, width in
            if index == keys.indices.first || index == keys.indices.last {
                return width + horizontalInset
            }
            return width
        }
    }

    private func darkThemeLetterRow(
        keys: [String],
        row: HWCKeyboardRowKind
    ) -> some View {
        GeometryReader { proxy in
            let widths = darkThemeLetterRowWidths(
                for: keys,
                row: row,
                availableWidth: proxy.size.width
            )

            HStack(spacing: 0) {
                ForEach(keys.indices, id: \.self) { index in
                    darkThemeLetterKeyCell(
                        keys[index],
                        row: row,
                        index: index,
                        fillColor: darkThemeFillColor(for: row),
                        pressedFillColor: darkThemePressedFillColor(for: row)
                    )
                        .frame(width: widths[index])
                }
            }
        }
        .frame(height: HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings))
    }

    private func darkThemeLetterKeyCell(
        _ key: String,
        row: HWCKeyboardRowKind,
        index: Int,
        fillColor: Color,
        pressedFillColor: Color?
    ) -> some View {
        let holdValue = model.holdValue(for: row, index: index)

        return actionAwareHardwareKeyButton(
            key: key,
            actionKey: model.canonicalLetterValue(for: row, index: index),
            row: row,
            holdValue: holdValue
        ) {
            hardwareLetterFace(
                key: key,
                holdValue: holdValue,
                row: row,
                index: index,
                fontSize: model.settings.largeLegends ? 39 : 35
            )
            .background(
                keySurface(
                    fillColor: fillColor,
                    borderColor: keyBorderColor,
                    pressedFillColor: pressedFillColor,
                    darkThemeSeparatorInset: darkThemeExpandedKeySeparatorInset,
                    showsDarkThemeSeparator: !key.isEmpty
                )
            )
        }
        .disabled(key.isEmpty)
        .opacity(key.isEmpty ? 0.28 : 1)
    }

    private func darkThemeToolbarSegment<Content: View>(
        action: @escaping () -> Void,
        accent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .trailing) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())

                Rectangle()
                    .fill(darkThemeDividerColor)
                    .frame(width: 1)
            }
        }
        .buttonStyle(
            KeyboardPressStyle(
                theme: model.settings.appTheme,
                accent: accent,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
            )
        )
        .frame(maxWidth: .infinity)
        .background(accent ? darkThemeToolbarSelectedFill : darkThemeToolbarFill)
    }

    private func darkThemeBottomControlKey(
        systemImage: String,
        width: CGFloat,
        action: (() -> Void)? = nil
    ) -> some View {
        Button(action: {
            action?()
        }) {
            ZStack(alignment: .trailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 33, weight: .regular))
                    .foregroundColor(keyLabelColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())

                Rectangle()
                    .fill(darkThemeDividerColor)
                    .frame(width: 1)
            }
        }
        .buttonStyle(
            KeyboardPressStyle(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
            )
        )
        .frame(width: width)
        .background(darkThemeBottomControlFill)
    }

    private func darkThemeUtilityCell<Content: View>(
        width: CGFloat? = nil,
        alignment: Alignment = .center,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .trailing) {
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    .padding(.horizontal, 14)
                    .contentShape(Rectangle())

                Rectangle()
                    .fill(darkThemeDividerColor)
                    .frame(width: 1)
            }
        }
        .buttonStyle(
            KeyboardPressStyle(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
            )
        )
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(width == nil ? darkThemeUtilityWideFill : darkThemeBottomControlFill)
    }

    private var darkThemeToolbarBackground: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                darkThemeBand(fill: darkThemeTopChromeFill, height: 11)
                darkThemeBand(fill: darkThemeToolbarFill, height: darkThemeToolbarHeight)
            }

            Rectangle()
                .fill(Color.black.opacity(0.34))
                .frame(height: 1)
        }
    }

    private func darkThemeBand(fill: Color, height: CGFloat) -> some View {
        Rectangle()
            .fill(fill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
    }

    private var quickInsertRow: some View {
        let items = quickInsertItems
        let layout = model.isSemiFoldActive
            ? AnyLayout(KeyboardSemiFoldRowLayout(gap: model.semiFoldGap, spacing: quickRowSpacing))
            : AnyLayout(HStackLayout(spacing: quickRowSpacing))

        return ZStack(alignment: .top) {
            quickInsertRailSurface

            layout {
                ForEach(items) { item in
                    quickKey(item.label, holdValue: model.holdValue(for: .quickInsert, index: item.sourceIndex)) {
                        if model.applyProtectedABCTouchOverrideIfNeeded() { return }

                        switch item.action {
                        case .text(let text):
                            model.performKey(text, from: .quickInsert)
                        case .pair(let open, let close):
                            model.insertPair(open: open, close: close)
                        case .special(let action):
                            model.performKey(action.storageToken, from: .quickInsert)
                        }
                    } onHold: { hold in
                        if model.applyProtectedABCTouchOverrideIfNeeded() { return }
                        model.insertHoldKey(hold, from: .quickInsert)
                    }
                }
            }

            if quickInsertRailShowsHandle {
                accessoryCollapseHandle(
                    placement: .quickInsertRow,
                    isMinimized: false,
                    accessibilityLabel: "Hide shortcut row"
                ) {
                    model.toggleQuickInsertRowMinimized()
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: HWCKeyboardLayoutMetrics.quickInsertHeight(
                for: model.settings,
                minimized: model.isQuickInsertRowMinimized
            )
        )
    }

    private var classicLetterMiddleInset: CGFloat {
        max(12, min(22, HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings) * 0.38))
    }

    private var classicLetterTopInset: CGFloat {
        max(4, min(10, HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings) * 0.16))
    }

    private var classicBottomLetterSideInset: CGFloat {
        max(8, min(16, HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings) * 0.22))
    }

    private func classicBottomLetterControlWidth(availableWidth: CGFloat) -> CGFloat {
        let letterCount = CGFloat(max(model.bottomRow.count, 1))
        let totalSpacing = keyRowSpacing * CGFloat(max(model.bottomRow.count + 1, 0))
        let unitWidth = max(0, (availableWidth - totalSpacing) / max(letterCount + 2.7, 1))
        return max(44, min(62, unitWidth * 1.35))
    }

    private func symbolRow(_ keys: [String], row: HWCKeyboardRowKind, band: ExpandedVisualBand) -> some View {
        HStack(spacing: keyRowSpacing) {
            ForEach(keys.indices, id: \.self) { index in
                keyButton(
                    keys[index],
                    row: row,
                    index: index,
                    band: band,
                    showsTrailingSeparator: index != keys.indices.last
                )
            }
        }
    }

    private func keyButton(
        _ key: String,
        row: HWCKeyboardRowKind,
        index: Int,
        band: ExpandedVisualBand,
        showsTrailingSeparator: Bool
    ) -> some View {
        let holdValue = model.holdValue(for: row, index: index)

        return actionAwareHardwareKeyButton(
            key: key,
            actionKey: model.canonicalLetterValue(for: row, index: index),
            row: row,
            holdValue: holdValue
        ) {
            expandedKeyFace(
                key: key,
                holdValue: holdValue,
                row: row,
                index: index,
                fontSize: expandedKeyLegendFontSize,
                fillColor: fillColor(for: band),
                borderColor: keyBorderColor,
                pressedFillColor: pressedFillColor(for: band),
                showsDarkThemeSeparator: showsTrailingSeparator,
                darkThemeSeparatorInset: model.settings.appTheme.usesDarkChrome
                    ? darkThemeExpandedKeySeparatorInset
                    : nil
            )
        }
        .disabled(key.isEmpty)
        .opacity(key.isEmpty ? 0.35 : 1.0)
    }

    private var expandedKeyLegendFontSize: CGFloat {
        model.settings.appTheme.usesDarkChrome
            ? (model.settings.largeLegends ? 38 : 34)
            : (model.settings.largeLegends ? 26 : 22)
    }

    @ViewBuilder
    private func expandedKeyFace(
        key: String,
        holdValue: String?,
        row: HWCKeyboardRowKind,
        index: Int,
        fontSize: CGFloat,
        fillColor: Color,
        borderColor: Color,
        pressedFillColor: Color?,
        showsDarkThemeSeparator: Bool,
        darkThemeSeparatorInset: CGFloat? = nil,
        height: CGFloat? = nil
    ) -> some View {
        let resolvedHeight = height ?? HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings)

        if KeyboardSpecialKeyAction.resolved(from: key) == .shift {
            expandedShiftKeyFace(
                showsDarkThemeSeparator: showsDarkThemeSeparator,
                darkThemeSeparatorInset: darkThemeSeparatorInset,
                height: resolvedHeight
            )
        } else {
            hardwareLetterFace(
                key: key,
                holdValue: holdValue,
                row: row,
                index: index,
                fontSize: fontSize
            )
            .frame(maxWidth: .infinity)
            .frame(height: resolvedHeight)
            .background(
                keySurface(
                    fillColor: fillColor,
                    borderColor: borderColor,
                    pressedFillColor: pressedFillColor,
                    darkThemeSeparatorInset: darkThemeSeparatorInset,
                    showsDarkThemeSeparator: showsDarkThemeSeparator
                )
            )
        }
    }

    private func expandedShiftKeyFace(
        showsDarkThemeSeparator: Bool,
        darkThemeSeparatorInset: CGFloat? = nil,
        height: CGFloat? = nil
    ) -> some View {
        let isActive = model.isCapsShiftActive
        let resolvedHeight = height ?? HWCKeyboardLayoutMetrics.expandedKeyHeight(for: model.settings)

        return toolbarShiftFace(isActive: isActive)
            .frame(maxWidth: .infinity)
            .frame(height: resolvedHeight)
            .background(
                keySurface(
                    fillColor: isActive ? toolbarCapsActiveFillColor : primaryKeyFillColor,
                    borderColor: isActive ? toolbarCapsActiveBorderColor : keyBorderColor,
                    pressedFillColor: isActive ? toolbarAccentPressedFillColor : toolbarPressedFillColor,
                    darkThemeSeparatorInset: darkThemeSeparatorInset,
                    showsDarkThemeSeparator: showsDarkThemeSeparator
                )
            )
            .overlay(toolbarIndicatorOverlay(state: model.capsIndicatorState), alignment: .top)
    }

    @ViewBuilder
    private func hardwareHoldKeyButton<Content: View>(
        key: String,
        row: HWCKeyboardRowKind,
        holdValue: String?,
        onTap: @escaping () -> Void,
        onHold: @escaping (String) -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if let holdValue, !holdValue.isEmpty {
            KeyboardDualActionButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                holdEnabled: true,
                holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                holdPreviewValue: nil,
                holdBeganAction: { model.beginHoldSwipeOverride() },
                holdEndedAction: { model.endHoldSwipeOverride() },
                requiresHoldForSwipeUp: false,
                touchDownAction: { model.performTouchDownFeedback() },
                tapAction: onTap,
                holdAction: { onHold(holdValue) },
                swipeUpAction: nil,
                shouldSuppressKeyCommit: { model.shouldSuppressKeyCommitForDirectionalSwipe }
            ) {
                content()
            }
        } else {
            KeyboardDualActionButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                holdEnabled: false,
                holdDuration: 0,
                touchDownAction: { model.performTouchDownFeedback() },
                tapAction: onTap,
                holdAction: {},
                shouldSuppressKeyCommit: { model.shouldSuppressKeyCommitForDirectionalSwipe }
            ) {
                content()
            }
        }
    }

    @ViewBuilder
    private func actionAwareHardwareKeyButton<Content: View>(
        key: String,
        actionKey: String? = nil,
        row: HWCKeyboardRowKind,
        holdValue: String?,
        holdChoices: [String] = [],
        holdKeyID: UUID? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let resolvedActionKey = actionKey ?? key
        if let specialAction = KeyboardSpecialKeyAction.resolved(from: resolvedActionKey) {
            hardwareSpecialActionButton(specialAction, row: row, content: content)
        } else {
            hardwareHoldKeyButton(
                key: key,
                row: row,
                holdValue: holdValue,
                onTap: {
                    model.performKey(
                        resolvedActionKey,
                        from: row,
                        shouldPlayFeedback: false
                    )
                },
                onHold: { hold in
                    if let holdKeyID, holdChoices.count > 1 {
                        model.insertNextHoldChoice(holdChoices, keyID: holdKeyID, from: row)
                    } else {
                        model.insertHoldKey(hold, from: row)
                    }
                },
                content: content
            )
            .background(glideKeyGeometryCapture(for: key, row: row))
        }
    }

    @ViewBuilder
    private func glideKeyGeometryCapture(for key: String, row: HWCKeyboardRowKind) -> some View {
        if let normalizedLabel = glideLabel(for: key, row: row) {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(Self.glideCoordinateSpace))
                let center = CGPoint(x: frame.midX, y: frame.midY)
                Color.clear.preference(
                    key: HWKGlideKeyLayoutPreferenceKey.self,
                    value: [
                        HWKGlideKey(
                            label: normalizedLabel,
                            center: CGPoint(x: center.x, y: center.y),
                            frame: frame
                        )
                    ]
                )
            }
        } else {
            EmptyView()
        }
    }

    private func glideLabel(for key: String, row: HWCKeyboardRowKind) -> String? {
        guard !isGlideBlockedRow(row) else { return nil }

        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.count == 1 else { return nil }
        guard let scalar = normalized.unicodeScalars.first,
              CharacterSet.letters.contains(scalar) || scalar == "'" else {
            return nil
        }

        return normalized
    }

    private func isGlideBlockedRow(_ row: HWCKeyboardRowKind) -> Bool {
        switch row {
        case .letterTop, .letterMiddle, .letterBottom:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func hardwareSpecialActionButton<Content: View>(
        _ action: KeyboardSpecialKeyAction,
        row: HWCKeyboardRowKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let preservingExpandedMenu = rowPreservesExpandedMenu(row)

        switch action {
        case .shift:
            KeyboardDualActionButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                holdEnabled: model.settings.capsHoldToLockEnabled,
                holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                holdBeganAction: { model.beginHoldSwipeOverride() },
                holdEndedAction: { model.endHoldSwipeOverride() },
                tapAction: { model.tapShiftKey(from: row) },
                holdAction: { model.holdShiftKey(from: row) },
                shouldSuppressKeyCommit: { model.shouldSuppressKeyCommitForDirectionalSwipe }
            ) {
                content()
            }
        case .menu:
            KeyboardDualActionButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                holdEnabled: model.settings.menuHoldToLatchEnabled,
                holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                holdBeganAction: { model.beginHoldSwipeOverride() },
                holdEndedAction: { model.endHoldSwipeOverride() },
                tapAction: { model.tapExpandedMenuKey() },
                holdAction: { model.holdExpandedMenuKey() },
                shouldSuppressKeyCommit: { model.shouldSuppressKeyCommitForDirectionalSwipe }
            ) {
                content()
            }
        case .deleteBackward:
            KeyboardRepeatButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                repeatEnabled: model.settings.deleteHoldEnabled,
                initialDelay: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                repeatInterval: 0.09,
                tapAction: {
                    if preservingExpandedMenu {
                        model.backKeepingMenu()
                    } else {
                        model.back()
                    }
                },
                holdStartAction: {
                    model.beginDeleteHold(preservingExpandedMenu: preservingExpandedMenu)
                },
                repeatAction: {
                    model.performDeleteHoldStep()
                },
                holdEndAction: {
                    model.endDeleteHold()
                },
                shouldSuppressKeyCommit: { model.shouldSuppressKeyCommitForDirectionalSwipe }
            ) {
                content()
            }
        case .deleteForward:
            KeyboardRepeatButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                repeatEnabled: model.settings.deleteHoldEnabled,
                initialDelay: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                repeatInterval: 0.09,
                tapAction: {
                    if preservingExpandedMenu {
                        model.deleteForwardPreservingExpandedMenu()
                    } else {
                        model.deleteForward()
                    }
                },
                holdStartAction: {},
                repeatAction: {
                    if preservingExpandedMenu {
                        model.deleteForwardPreservingExpandedMenu()
                    } else {
                        model.deleteForward()
                    }
                },
                holdEndAction: {},
                shouldSuppressKeyCommit: { model.shouldSuppressKeyCommitForDirectionalSwipe }
            ) {
                content()
            }
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            KeyboardRepeatButton(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
                repeatEnabled: true,
                initialDelay: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                repeatInterval: 0.09,
                tapAction: {
                    model.performKey(action.storageToken, from: row)
                },
                holdStartAction: {},
                repeatAction: {
                    model.performKey(action.storageToken, from: row)
                },
                holdEndAction: {},
                shouldSuppressKeyCommit: {
                    model.shouldSuppressKeyCommitForDirectionalSwipe
                }
            ) {
                content()
            }
        default:
            Button(action: {
                model.performKey(action.storageToken, from: row)
            }) {
                content()
            }
            .buttonStyle(
                KeyboardPressStyle(
                    theme: model.settings.appTheme,
                    accent: false,
                    suppressMotion: suppressKeyPressMotion,
                    darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
                )
            )
        }
    }

    private func hardwareLetterFace(
        key: String,
        holdValue: String?,
        row: HWCKeyboardRowKind,
        index: Int,
        fontSize: CGFloat
    ) -> some View {
        let legendAlignment = holdLegendAlignment(for: row, index: index)
        let primaryAlignment = primaryLegendAlignment(for: row, index: index)
        let usesHardwarePrimaryAlignment = shouldUseHardwarePrimaryAlignment(for: row)
        let primaryFontSize = usesHardwarePrimaryAlignment
            ? (fontSize * 0.8)
            : fontSize

        return Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                hardwarePrimaryLegend(
                    key: key,
                    fontSize: primaryFontSize,
                    usesHardwareAlignment: usesHardwarePrimaryAlignment
                )
                .padding(.horizontal, usesHardwarePrimaryAlignment ? primaryLegendHorizontalPadding : 0)
                .padding(.top, usesHardwarePrimaryAlignment ? primaryLegendTopPadding : 0)
                .offset(x: usesHardwarePrimaryAlignment ? primaryLegendHorizontalOffset(for: row, index: index) : 0)
                .offset(x: darkThemePrimaryLegendHorizontalOffset(for: row, index: index))
                .contentShape(Rectangle()),
                alignment: usesHardwarePrimaryAlignment ? primaryAlignment : .center
            )
            .overlay(
                Group {
                    if let holdValue, shouldShowHoldLegend(for: row) {
                        hardwareHoldLegend(holdValue, fontSize: fontSize)
                            .offset(x: holdLegendHorizontalOffset(for: row, index: index))
                    }
                },
                alignment: legendAlignment
            )
    }

    private func shouldShowHoldLegend(for row: HWCKeyboardRowKind) -> Bool {
        switch row {
        case .letterTop, .letterMiddle, .letterBottom:
            return !model.isSymbolKeyboard
        case .symbolTop, .symbolMiddle, .symbolBottom:
            return model.isSymbolKeyboard
        default:
            return false
        }
    }

    private func shouldUseHardwarePrimaryAlignment(for row: HWCKeyboardRowKind) -> Bool {
        guard !model.settings.appTheme.usesDarkChrome else { return false }

        switch row {
        case .letterTop, .letterMiddle, .letterBottom:
            return !model.isSymbolKeyboard
        default:
            return false
        }
    }

    private var primaryLegendHorizontalPadding: CGFloat {
        model.settings.appTheme.usesDarkChrome ? 12 : 10
    }

    private var primaryLegendTopPadding: CGFloat {
        model.settings.appTheme.usesDarkChrome ? 8 : 7
    }

    private func primaryLegendHorizontalOffset(for row: HWCKeyboardRowKind, index: Int) -> CGFloat {
        switch model.settings.appTheme {
        case .dark:
            return isMirroredHardwarePrimaryPosition(for: row, index: index) ? -2 : 0
        case .classic, .chameleon, .custom:
            if isLeadingHardwarePrimaryPosition(for: row, index: index) {
                return 2
            }
            return isMirroredHardwarePrimaryPosition(for: row, index: index) ? -2 : 0
        }
    }

    private func isLeadingHardwarePrimaryPosition(for row: HWCKeyboardRowKind, index: Int) -> Bool {
        switch row {
        case .letterTop, .letterMiddle:
            return index <= 4
        case .letterBottom:
            return index <= 3
        default:
            return false
        }
    }

    private func isMirroredHardwarePrimaryPosition(for row: HWCKeyboardRowKind, index: Int) -> Bool {
        switch row {
        case .letterTop, .letterMiddle:
            return index > 4
        case .letterBottom:
            return index > 3
        default:
            return false
        }
    }

    private func holdLegendHorizontalOffset(for row: HWCKeyboardRowKind, index: Int) -> CGFloat {
        guard model.settings.appTheme.usesDarkChrome else { return 0 }

        switch row {
        case .letterTop, .letterMiddle:
            return index <= 4 ? 2 : -2
        case .letterBottom:
            return index <= 3 ? 2 : -2
        case .symbolTop:
            return mirroredHoldLegendOffset(index: index, keyCount: model.topRow.count)
        case .symbolMiddle:
            return mirroredHoldLegendOffset(index: index, keyCount: model.middleRow.count)
        case .symbolBottom:
            return mirroredHoldLegendOffset(index: index, keyCount: model.bottomRow.count)
        default:
            return 0
        }
    }

    private func mirroredHoldLegendOffset(index: Int, keyCount: Int) -> CGFloat {
        let rightSideCount = (keyCount + 1) / 2
        return index < rightSideCount ? 2 : -2
    }

    private func darkThemePrimaryLegendHorizontalOffset(for row: HWCKeyboardRowKind, index: Int) -> CGFloat {
        guard model.settings.appTheme.usesDarkChrome else { return 0 }

        switch row {
        case .letterTop, .letterMiddle:
            return index <= 4 ? -3 : 5
        case .letterBottom:
            return index <= 3 ? -3 : 5
        default:
            return 0
        }
    }

    @ViewBuilder
    private func hardwarePrimaryLegend(
        key: String,
        fontSize: CGFloat,
        usesHardwareAlignment: Bool
    ) -> some View {
        let legendFrameHeight = max(20, fontSize + 4)
        let legendFrameWidth = usesHardwareAlignment ? primaryLegendBoxWidth(for: fontSize) : nil

        if let specialAction = KeyboardSpecialKeyAction.resolved(from: key) {
            if let iconName = hardwareSpecialActionIconName(for: specialAction) {
                Image(systemName: iconName)
                    .font(.system(size: max(13, fontSize * 0.62), weight: .semibold))
                    .foregroundColor(keyLabelColor)
                    .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
                    .accessibilityLabel(specialAction.shelfTitle)
            } else {
                Text(model.specialActionLegend(for: specialAction))
                    .font(.system(size: max(13, fontSize * 0.74), weight: .semibold))
                    .foregroundColor(keyLabelColor)
                    .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
            }
        } else if let customLayerVisual = customLayerDisplayVisual(for: key) {
            Image(systemName: customLayerVisual.icon)
                .font(.system(size: max(13, fontSize * 0.62), weight: .semibold))
                .foregroundColor(keyLabelColor)
                .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
                .accessibilityLabel(customLayerVisual.title)
        } else {
            let legend = HWKKeyLegendPresentation.resolve(key)
            let label = Text(legend.text)
                .font(
                    .system(
                        size: min(fontSize, CGFloat(legend.maximumFontSize)),
                        weight: usesHardwareAlignment ? .regular : .light
                    )
                )
                .foregroundColor(keyLabelColor)
                .lineLimit(legend.lineLimit)
                .minimumScaleFactor(legend.minimumScaleFactor)
                .multilineTextAlignment(.center)
                .allowsTightening(true)
                .accessibilityLabel(legend.accessibilityText)

            if legend.usesFullKeyWidth {
                label
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
            } else {
                label
                    .frame(width: legendFrameWidth, height: legendFrameHeight, alignment: .center)
            }
        }
    }

    private func customLayerDisplayVisual(for token: String) -> (icon: String, title: String)? {
        guard let id = KeyboardCustomLayer.id(fromStorageToken: token),
              model.isCustomLayerAuthorized(id),
              let layer = model.runtimeKeymap.customLayer(for: id) else {
            return nil
        }
        return (layer.iconSystemName, layer.title)
    }

    @ViewBuilder
    private func customLayerTokenFace(
        _ token: String,
        fontSize: CGFloat,
        weight: Font.Weight,
        color: Color
    ) -> some View {
        if let customLayerVisual = customLayerDisplayVisual(for: token) {
            Image(systemName: customLayerVisual.icon)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(color)
                .accessibilityLabel(customLayerVisual.title)
        } else {
            Text(token)
                .font(.system(size: fontSize, weight: weight))
                .foregroundColor(color)
        }
    }

    private func hardwareSpecialActionIconName(for action: KeyboardSpecialKeyAction) -> String? {
        switch action {
        case .moveLeft:
            return "arrow.left"
        case .moveRight:
            return "arrow.right"
        case .moveUp:
            return "arrow.up"
        case .moveDown:
            return "arrow.down"
        case .clipboard:
            return "tray.full"
        default:
            return nil
        }
    }

    private func hardwareHoldLegend(_ holdValue: String, fontSize: CGFloat) -> some View {
        Group {
            if let specialAction = KeyboardSpecialKeyAction.resolved(from: holdValue),
               let iconName = hardwareSpecialActionIconName(for: specialAction) {
                Image(systemName: iconName)
                    .font(.system(size: max(9, fontSize * 0.26), weight: .semibold))
                    .foregroundColor(controlLabelColor.opacity(0.94))
                    .accessibilityLabel(specialAction.shelfTitle)
            } else {
                customLayerTokenFace(
                    holdValue,
                    fontSize: max(9, fontSize * 0.26),
                    weight: .semibold,
                    color: controlLabelColor.opacity(0.94)
                )
            }
        }
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: holdLegendBoxWidth(for: fontSize), alignment: .center)
            .padding(.bottom, model.settings.appTheme.usesDarkChrome ? 5 : 4)
    }

    private func primaryLegendBoxWidth(for fontSize: CGFloat) -> CGFloat {
        let multiplier: CGFloat = model.settings.appTheme.usesDarkChrome ? 0.88 : 0.98
        return max(model.settings.appTheme.usesDarkChrome ? 26 : 22, fontSize * multiplier)
    }

    private func holdLegendBoxWidth(for fontSize: CGFloat) -> CGFloat {
        max(model.settings.appTheme.usesDarkChrome ? 18 : 16, fontSize * 0.44)
    }

    private func primaryLegendAlignment(for row: HWCKeyboardRowKind, index: Int) -> Alignment {
        switch row {
        case .letterTop:
            return index <= 4 ? .topTrailing : .topLeading
        case .letterMiddle:
            return index <= 4 ? .topTrailing : .topLeading
        case .letterBottom:
            return index <= 3 ? .topTrailing : .topLeading
        default:
            return .center
        }
    }

    private func holdLegendAlignment(for row: HWCKeyboardRowKind, index: Int) -> Alignment {
        switch row {
        case .letterTop:
            return index <= 4 ? .bottomTrailing : .bottomLeading
        case .letterMiddle:
            return index <= 4 ? .bottomTrailing : .bottomLeading
        case .letterBottom:
            return index <= 3 ? .bottomTrailing : .bottomLeading
        case .symbolTop:
            return mirroredHoldLegendAlignment(index: index, keyCount: model.topRow.count)
        case .symbolMiddle:
            return mirroredHoldLegendAlignment(index: index, keyCount: model.middleRow.count)
        case .symbolBottom:
            return mirroredHoldLegendAlignment(index: index, keyCount: model.bottomRow.count)
        default:
            return .bottomTrailing
        }
    }

    private func mirroredHoldLegendAlignment(index: Int, keyCount: Int) -> Alignment {
        let rightSideCount = (keyCount + 1) / 2
        return index < rightSideCount ? .bottomTrailing : .bottomLeading
    }

    private func compactKey(
        _ label: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: model.settings.largeLegends ? 12 : 11, weight: .semibold))
                }
                customLayerTokenFace(
                    label,
                    fontSize: model.settings.largeLegends ? 13 : 12,
                    weight: .medium,
                    color: controlLabelColor
                )
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(
                keySurface(
                    fillColor: secondaryKeyFillColor,
                    borderColor: keyBorderColor,
                    pressedFillColor: secondaryPressedFillColor
                )
            )
        }
        .buttonStyle(
            KeyboardPressStyle(
                theme: model.settings.appTheme,
                accent: false,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
            )
        )
    }

    private func quickKey(
        _ label: String,
        holdValue: String?,
        action: @escaping () -> Void,
        onHold: @escaping (String) -> Void
    ) -> some View {
        let resolvedHold = holdValue?.isEmpty == false ? holdValue : nil

        return KeyboardDualActionButton(
            theme: model.settings.appTheme,
            accent: false,
            suppressMotion: suppressKeyPressMotion,
            darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
            holdEnabled: resolvedHold != nil,
            holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
            maximumDistance: 32,
            interactionInsetX: 8,
            interactionInsetY: 4,
            interactionCornerRadius: keyCornerRadius,
            tapAction: action,
            holdAction: {
                guard let resolvedHold else { return }
                onHold(resolvedHold)
            }
        ) {
            customLayerTokenFace(
                label,
                fontSize: model.settings.appTheme.usesDarkChrome
                    ? (model.settings.largeLegends ? 17 : 15)
                    : (model.settings.largeLegends ? 13 : 12),
                weight: .medium,
                color: keyLabelColor
            )
            .frame(maxWidth: .infinity)
            .frame(height: HWCKeyboardLayoutMetrics.quickInsertHeight(for: model.settings))
            .background(
                keySurface(
                    fillColor: secondaryKeyFillColor,
                    borderColor: keyBorderColor,
                    pressedFillColor: secondaryPressedFillColor
                )
            )
        }
    }

    var suggestionRailFillColor: Color? {
        guard hasSuggestionStrip else { return nil }
        switch model.settings.appTheme {
        case .classic, .dark:
            return backgroundBaseColor
        case .chameleon, .custom:
            return nil
        }
    }

    private var topSuggestionRailSurface: AnyView {
        guard let fillColor = suggestionRailFillColor else {
            return AnyView(Color.clear)
        }
        return AnyView(Rectangle().fill(fillColor))
    }

    @ViewBuilder
    private var quickInsertRailSurface: some View {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            Color.clear
        case .dark:
            Rectangle()
                .fill(darkThemeQuickInsertRailFill)
        }
    }

    private var quickInsertRestoreHandle: some View {
        Button {
            model.toggleQuickInsertRowMinimized()
        } label: {
            accessoryHandleVisual(for: .quickInsertRow)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(
            width: accessoryHandleTapWidth(for: .quickInsertRow),
            height: accessoryHandleTapHeight(for: .quickInsertRow),
            alignment: .top
        )
        .offset(y: quickInsertRestoreHandleVerticalOffset)
        .accessibilityLabel("Show shortcut row")
    }

    private func accessoryCollapseHandle(
        placement: AccessoryHandlePlacement,
        isMinimized: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            accessoryHandleVisual(for: placement)
            .frame(
                maxWidth: isMinimized ? .infinity : accessoryHandleTapWidth(for: placement),
                maxHeight: isMinimized ? .infinity : accessoryHandleTapHeight(for: placement),
                alignment: .top
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
    }

    private func accessoryHandleVisual(for placement: AccessoryHandlePlacement) -> some View {
        RoundedRectangle(
            cornerRadius: accessoryHandleCornerRadius(for: placement),
            style: .continuous
        )
        .fill(accessoryHandleFillColor(for: placement))
        .frame(
            width: accessoryHandleWidth(for: placement),
            height: accessoryHandleHeight(for: placement)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: accessoryHandleCornerRadius(for: placement),
                style: .continuous
            )
            .stroke(
                accessoryHandleBorderColor(for: placement),
                lineWidth: accessoryHandleBorderWidth(for: placement)
            )
        )
        .offset(y: accessoryHandleVerticalOffset(for: placement))
    }

    private func specialKey(
        _ label: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let accentKey = isDarkAccentKey(label)
        let fillColor = accentKey ? darkThemeAccentKeyFillColor : specialKeyFillColor
        let borderColor = accentKey ? darkThemeAccentKeyBorderColor : specialKeyBorderColor
        let labelColor = accentKey ? activeControlLabelColor : controlLabelColor

        return Button(action: action) {
            VStack(spacing: 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(
                            .system(
                                size: model.settings.appTheme.usesDarkChrome
                                    ? (model.settings.largeLegends ? 19 : 17)
                                    : (model.settings.largeLegends ? 16 : 14),
                                weight: .regular
                            )
                        )
                }
                customLayerTokenFace(
                    label,
                    fontSize: model.settings.appTheme.usesDarkChrome
                        ? (model.settings.largeLegends ? 14 : 13)
                        : (model.settings.largeLegends ? 12 : 11),
                    weight: model.settings.appTheme.usesDarkChrome ? .regular : .medium,
                    color: labelColor
                )
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: HWCKeyboardLayoutMetrics.utilityRowHeight(for: model.settings))
            .background(
                keySurface(
                    fillColor: fillColor,
                    borderColor: borderColor,
                    pressedFillColor: accentKey ? toolbarAccentPressedFillColor : specialPressedFillColor
                )
            )
        }
        .buttonStyle(
            KeyboardPressStyle(
                theme: model.settings.appTheme,
                accent: model.settings.appTheme == .classic || accentKey,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
            )
        )
    }

    @ViewBuilder
    private var spaceBackground: some View {
        keySurface(
            fillColor: secondaryKeyFillColor,
            borderColor: keyBorderColor,
            pressedFillColor: secondaryPressedFillColor
        )
    }

    @ViewBuilder
    private var expandedPanelSurface: some View {
        Color.clear
    }

    @ViewBuilder
    private var collapsedStripSurface: some View {
        Color.clear
    }

    private var keyboardBackground: some View {
        ZStack {
            backgroundBaseColor

            if model.settings.appTheme == .classic {
                LinearGradient(
                    colors: [
                        paletteGlowColor.opacity(0.12),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else if model.settings.appTheme.usesDarkChrome {
                darkThemeBackgroundChrome
            }
        }
        .overlay(
            Rectangle()
                .fill(topSeparatorColor)
                .frame(height: separatorThickness),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .fill(bottomSeparatorColor)
                .frame(height: separatorThickness),
            alignment: .bottom
        )
    }

    private var keyLabelColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? Color.white
                : Color(red: 0.84, green: 0.84, blue: 0.86)
        case .dark:
            return Color.white.opacity(0.98)
        case .chameleon:
            return isChameleonDarkAppearance ? Color.white.opacity(0.98) : Color.black.opacity(0.92)
        case .custom:
            return customKeyLabelColor
        }
    }

    private var controlLabelColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? Color.white.opacity(0.94)
                : Color(red: 0.76, green: 0.77, blue: 0.79)
        case .dark:
            return Color(red: 0.68, green: 0.68, blue: 0.69)
        case .chameleon:
            return isChameleonDarkAppearance
                ? Color(red: 0.72, green: 0.72, blue: 0.74)
                : Color.black.opacity(0.58)
        case .custom:
            return customKeyLabelColor.opacity(0.72)
        }
    }

    private var activeControlLabelColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return Color.white
        case .dark:
            return Color.white.opacity(0.94)
        case .chameleon:
            return isChameleonDarkAppearance ? Color.white.opacity(0.94) : Color.black.opacity(0.94)
        case .custom:
            return customKeyLabelColor
        }
    }

    private var keyBorderColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? Color.white.opacity(0.36)
                : Color.white.opacity(0.10)
        case .dark:
            return Color(red: 0.27, green: 0.27, blue: 0.28)
        case .chameleon:
            return isChameleonDarkAppearance ? Color.white.opacity(0.10) : Color.black.opacity(0.10)
        case .custom:
            return customKeyBorderColor
        }
    }

    private var specialKeyBorderColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? paletteGlowColor.opacity(0.96)
                : palettePrimaryColor.opacity(0.72)
        case .dark:
            return Color(red: 0.20, green: 0.20, blue: 0.21)
        case .chameleon:
            return isChameleonDarkAppearance ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
        case .custom:
            return customKeyBorderColor.opacity(1.08)
        }
    }

    private var primaryKeyFillColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? Color(red: 0.08, green: 0.08, blue: 0.09)
                : Color(red: 0.18, green: 0.18, blue: 0.19)
        case .dark:
            return Color(red: 0.15, green: 0.15, blue: 0.16)
        case .chameleon:
            return chameleonKeyFillColor
        case .custom:
            return customKeyFillColor
        }
    }

    private var secondaryKeyFillColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? Color(red: 0.10, green: 0.10, blue: 0.11)
                : Color(red: 0.19, green: 0.19, blue: 0.20)
        case .dark:
            return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .chameleon:
            return chameleonSecondaryKeyFillColor
        case .custom:
            return customSecondaryKeyFillColor
        }
    }

    private var specialKeyFillColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return model.settings.highContrastKeys
                ? paletteSecondaryColor.opacity(0.42)
                : paletteSecondaryColor.opacity(0.26)
        case .dark:
            return Color(red: 0.09, green: 0.09, blue: 0.10)
        case .chameleon:
            return chameleonSpecialKeyFillColor
        case .custom:
            return customSpecialKeyFillColor
        }
    }

    private var backgroundBaseColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return Color(red: 0.09, green: 0.09, blue: 0.10)
        case .dark:
            return Color(red: 0.08, green: 0.08, blue: 0.09)
        case .chameleon:
            return chameleonBackgroundColor
        case .custom:
            return customBackgroundColor
        }
    }

    private var keyCornerRadius: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon:
            return 9
        case .dark:
            return 0
        case .custom:
            return CGFloat(model.settings.customKeyStyle.cornerRadius)
        }
    }

    private var keyStrokeWidth: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon:
            return model.settings.highContrastKeys ? 0.8 : 0
        case .dark:
            return 0.72
        case .custom:
            return max(0.35, CGFloat(model.settings.customKeyStyle.borderStrength) / 80)
        }
    }

    private var expandedPanelCornerRadius: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 10
        case .dark:
            return 0
        }
    }

    private var expandedPanelFillColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return .clear
        case .dark:
            return .clear
        }
    }

    private var expandedPanelBorderColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return .clear
        case .dark:
            return .clear
        }
    }

    private var expandedPanelBorderWidth: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 0
        case .dark:
            return 0.6
        }
    }

    private var expandedPanelHighlightColor: Color {
        .clear
    }

    private var expandedPanelHighlightHeight: CGFloat {
        0
    }

    private var separatorThickness: CGFloat {
        0
    }

    private var topSeparatorColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return .clear
        case .dark:
            return Color(red: 0.20, green: 0.20, blue: 0.21)
        }
    }

    private var bottomSeparatorColor: Color {
        switch model.settings.appTheme {
        case .classic:
            return Color.black.opacity(0.40)
        case .dark:
            return Color(red: 0.08, green: 0.08, blue: 0.09)
        case .chameleon:
            return isChameleonDarkAppearance ? Color.black.opacity(0.40) : Color.black.opacity(0.10)
        case .custom:
            return customIsLightSurface ? Color.black.opacity(0.10) : Color.black.opacity(0.40)
        }
    }

    private var palettePrimaryColor: Color {
        model.settings.accentPalette.primaryUIColor.bbSwiftUIColor
    }

    private var paletteSecondaryColor: Color {
        model.settings.accentPalette.secondaryUIColor.bbSwiftUIColor
    }

    private var paletteGlowColor: Color {
        model.settings.accentPalette.glowUIColor.bbSwiftUIColor
    }

    private var chameleonBackgroundColor: Color {
        chameleonSystemBackgroundColor
    }

    private var chameleonKeyFillColor: Color {
        chameleonSystemKeyFillColor
    }

    private var chameleonSecondaryKeyFillColor: Color {
        chameleonSystemSecondaryKeyFillColor
    }

    private var chameleonSpecialKeyFillColor: Color {
        chameleonSystemSpecialKeyFillColor
    }

    private var isChameleonDarkAppearance: Bool {
        switch model.hostKeyboardAppearance {
        case .dark:
            return true
        case .light:
            return false
        case .default:
            return isHostInterfaceStyleDark
        @unknown default:
            return isHostInterfaceStyleDark
        }
    }

    private var isHostInterfaceStyleDark: Bool {
        switch model.hostUserInterfaceStyle {
        case .light:
            return false
        case .dark:
            return true
        case .unspecified:
            return colorScheme == .dark
        @unknown default:
            return colorScheme == .dark
        }
    }

    private var chameleonSystemBackgroundColor: Color {
        isChameleonDarkAppearance
            ? Color(red: 0.07, green: 0.07, blue: 0.08)
            : Color(red: 0.82, green: 0.84, blue: 0.87)
    }

    private var chameleonSystemKeyFillColor: Color {
        isChameleonDarkAppearance
            ? Color(red: 0.19, green: 0.19, blue: 0.20)
            : Color.white
    }

    private var chameleonSystemSecondaryKeyFillColor: Color {
        isChameleonDarkAppearance
            ? Color(red: 0.14, green: 0.14, blue: 0.15)
            : Color(red: 0.68, green: 0.70, blue: 0.74)
    }

    private var chameleonSystemSpecialKeyFillColor: Color {
        isChameleonDarkAppearance
            ? Color(red: 0.12, green: 0.12, blue: 0.13)
            : Color(red: 0.68, green: 0.70, blue: 0.74)
    }

    private var customKeyFillColor: Color {
        switch model.settings.customKeyStyle.keyFill {
        case .graphite:
            return Color(red: 0.18, green: 0.18, blue: 0.19)
        case .ink:
            return Color(red: 0.09, green: 0.09, blue: 0.10)
        case .paper:
            return Color.white.opacity(0.95)
        case .accent:
            return palettePrimaryColor.opacity(0.82)
        case .adaptive:
            return customAdaptiveIsLightSurface
                ? Color.white
                : Color(red: 0.19, green: 0.19, blue: 0.20)
        }
    }

    private var customSecondaryKeyFillColor: Color {
        customIsLightSurface
            ? Color(red: 0.70, green: 0.72, blue: 0.76)
            : customKeyFillColor.opacity(0.82)
    }

    private var customSpecialKeyFillColor: Color {
        customIsLightSurface
            ? Color(red: 0.64, green: 0.66, blue: 0.70)
            : customKeyFillColor.opacity(0.72)
    }

    private var customBackgroundColor: Color {
        customIsLightSurface
            ? Color(red: 0.82, green: 0.84, blue: 0.87)
            : Color(red: 0.08, green: 0.08, blue: 0.09)
    }

    private var customKeyLabelColor: Color {
        let opacity = Double(model.settings.customKeyStyle.textBrightness) / 100
        return customIsLightSurface
            ? Color.black.opacity(opacity)
            : Color.white.opacity(opacity)
    }

    private var customKeyBorderColor: Color {
        let opacity = Double(model.settings.customKeyStyle.borderStrength) / 100
        return customIsLightSurface
            ? Color.black.opacity(opacity * 0.72)
            : Color.white.opacity(opacity)
    }

    private var customIsLightSurface: Bool {
        switch model.settings.customKeyStyle.keyFill {
        case .paper:
            return true
        case .adaptive:
            return customAdaptiveIsLightSurface
        case .graphite, .ink, .accent:
            return false
        }
    }

    private var customAdaptiveIsLightSurface: Bool {
        if model.settings.customKeyStyle.followsHostAppearance {
            return colorScheme != .dark
        }

        return !isChameleonDarkAppearance
    }

    private var darkThemeReferenceAccentColor: Color {
        palettePrimaryColor
    }

    private var darkThemeUniversalTapHighlightBorderColor: Color {
        darkThemeReferenceAccentColor
    }

    private var darkThemeHorizontalNudge: CGFloat {
        HWCKeyboardLayoutMetrics.darkThemeHorizontalNudge(for: model.settings)
    }

    private var keyShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: keyCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private func keySurface(
        fillColor: Color,
        borderColor: Color,
        pressedFillColor: Color? = nil,
        darkThemeSeparatorInset: CGFloat? = nil,
        showsDarkThemeSeparator: Bool = true
    ) -> some View {
        KeyboardKeySurface(
            theme: model.settings.appTheme,
            fillColor: fillColor,
            borderColor: borderColor,
            keyCornerRadius: keyCornerRadius,
            keyStrokeWidth: keyStrokeWidth,
            darkThemeDividerColor: darkThemeDividerColor,
            darkThemeSeparatorWidth: darkThemeSeparatorWidth,
            darkThemeSeparatorInset: darkThemeSeparatorInset ?? darkThemeExpandedKeySeparatorInset,
            showsDarkThemeSeparator: showsDarkThemeSeparator,
            shadowColor: keyShadowColor,
            shadowRadius: keyShadowRadius,
            shadowYOffset: keyShadowYOffset,
            pressedFillColor: pressedFillColor
        )
    }

    private var toolbarSpacing: CGFloat {
        switch model.settings.appTheme {
        case .dark:
            return 0
        case .custom:
            return CGFloat(model.settings.customKeyStyle.keyDistance)
        case .classic, .chameleon:
            return 4
        }
    }

    private var classicExpandedBottomControlSpans: [Int] {
        var spans = [Int]()

        if model.showsNextKeyboardKey {
            spans.append(1)
        }

        if model.isSymbolKeyboard {
            spans.append(contentsOf: HWCExpandedBottomStripLayout.controlSpans(for: model.symbolUtilityValues))
        } else {
            spans.append(contentsOf: [1, 1, 3])
        }

        spans.append(contentsOf: Array(repeating: 1, count: model.activeExpandedTrailingUtilityValues.count))
        return spans
    }

    private func toolbarUnitWidth(
        availableWidth: CGFloat,
        spans: [Int],
        spacing: CGFloat
    ) -> CGFloat {
        HWCExpandedBottomStripLayout.unitWidth(
            availableWidth: availableWidth,
            spans: spans,
            spacing: spacing
        )
    }

    private func toolbarWidth(span: Int, unitWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        HWCExpandedBottomStripLayout.controlWidth(
            span: span,
            unitWidth: unitWidth,
            spacing: spacing
        )
    }

    private var keyRowSpacing: CGFloat {
        switch model.settings.appTheme {
        case .dark:
            return 0
        case .custom:
            return CGFloat(model.settings.customKeyStyle.keyDistance)
        case .classic, .chameleon:
            return 5
        }
    }

    private var quickRowSpacing: CGFloat {
        switch model.settings.appTheme {
        case .dark:
            return 0
        case .custom:
            return CGFloat(model.settings.customKeyStyle.keyDistance)
        case .classic, .chameleon:
            return 8
        }
    }

    private var quickInsertItems: [QuickInsertRenderItem] {
        var items = [QuickInsertRenderItem]()

        for (index, value) in model.quickInsertValues.enumerated() {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let specialAction = KeyboardSpecialKeyAction.resolved(from: trimmed) {
                items.append(
                    QuickInsertRenderItem(
                        id: "\(index)-special",
                        sourceIndex: index,
                        label: specialAction.shelfTitle,
                        action: .special(specialAction)
                    )
                )
            } else if let pair = quickInsertPair(for: trimmed) {
                if model.settings.autoPairEnabled {
                    items.append(
                        QuickInsertRenderItem(
                            id: "\(index)-pair",
                            sourceIndex: index,
                            label: "\(pair.open) \(pair.close)",
                            action: .pair(open: pair.open, close: pair.close)
                        )
                    )
                } else {
                    items.append(
                        QuickInsertRenderItem(
                            id: "\(index)-open",
                            sourceIndex: index,
                            label: pair.open,
                            action: .text(pair.open)
                        )
                    )
                    items.append(
                        QuickInsertRenderItem(
                            id: "\(index)-close",
                            sourceIndex: index,
                            label: pair.close,
                            action: .text(pair.close)
                        )
                    )
                }
            } else {
                items.append(
                    QuickInsertRenderItem(
                        id: "\(index)-text",
                        sourceIndex: index,
                        label: trimmed,
                        action: .text(trimmed)
                    )
                )
            }
        }

        return items
    }

    private func quickInsertPair(for value: String) -> (open: String, close: String)? {
        let compact = value.replacingOccurrences(of: " ", with: "")

        switch compact {
        case "[]":
            return ("[", "]")
        case "()":
            return ("(", ")")
        case "{}":
            return ("{", "}")
        case "<>":
            return ("<", ">")
        default:
            return nil
        }
    }

    private var utilityRowSpacing: CGFloat {
        model.settings.appTheme.usesDarkChrome ? 0 : 5
    }

    private var toolbarSpaceLabel: String {
        model.settings.showControlLabels ? "Space" : ""
    }

    private var toolbarShiftLabel: String? {
        guard model.settings.showControlLabels else { return nil }
        return model.isCapsLocked ? "Caps" : "Shift"
    }

    private var toolbarReturnLabel: String? {
        model.settings.showControlLabels ? "Return" : nil
    }

    private var toolbarDeleteLabel: String? {
        model.settings.showControlLabels ? "Delete" : nil
    }

    private var toolbarControlLabelFontSize: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return model.settings.largeLegends ? 9 : 8
        case .dark:
            return model.settings.largeLegends ? 8 : 7
        }
    }

    private var toolbarControlVerticalSpacing: CGFloat {
        model.settings.appTheme.usesDarkChrome ? 1 : 0.5
    }

    private var toolbarShiftIconSize: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            if model.settings.showControlLabels {
                return model.settings.largeLegends ? 14 : 13
            }
            return model.settings.largeLegends ? 18 : 16
        case .dark:
            if model.settings.showControlLabels {
                return model.settings.largeLegends ? 14 : 13
            }
            return model.settings.largeLegends ? 17 : 15
        }
    }

    private var toolbarActionIconSize: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            if model.settings.showControlLabels {
                return model.settings.largeLegends ? 13 : 12
            }
            return model.settings.largeLegends ? 20 : 18
        case .dark:
            if model.settings.showControlLabels {
                return model.settings.largeLegends ? 13 : 12
            }
            return model.settings.largeLegends ? 20 : 18
        }
    }

    @ViewBuilder
    private func toolbarLabeledIcon(
        _ systemImage: String,
        label: String?,
        foregroundColor: Color,
        iconSize: CGFloat
    ) -> some View {
        if let label {
            VStack(spacing: toolbarControlVerticalSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundColor(foregroundColor)

                Text(label)
                    .font(.system(size: toolbarControlLabelFontSize, weight: .medium))
                    .foregroundColor(foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, model.settings.appTheme.usesDarkChrome ? 4 : 3)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundColor(foregroundColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toolbarTextKey(_ label: String, action: @escaping () -> Void) -> some View {
        toolbarKey(action: action) {
            customLayerTokenFace(
                label,
                fontSize: model.settings.largeLegends ? 21 : 19,
                weight: .regular,
                color: keyLabelColor
            )
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func topSuggestionSlot(
        _ placement: SuggestionRailPlacement
    ) -> some View {
        let lane = placement.lane
        let index = placement.startLane
        if let suggestion = lane.selectedItem {
            let isPreviewSelected = model.suggestionSwipePreviewColumn.map {
                placement.contains(physicalLane: $0)
            } ?? false
            let chipColor = topSuggestionChipColor(lane: lane, suggestion: suggestion)
            let accent = chipColor != .none

            if model.activeSuggestionRolodexLaneID == lane.id {
                suggestionRolodexChipControlSurface(
                    lane,
                    suggestion: suggestion,
                    isPreviewSelected: isPreviewSelected,
                    chipColor: chipColor,
                    accent: accent,
                    index: index
                )
            } else {
                KeyboardDualActionButton(
                    theme: model.settings.appTheme,
                    accent: accent,
                    suppressMotion: suppressKeyPressMotion,
                    holdEnabled: lane.items.count > 1,
                    holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                    maximumDistance: 36,
                    interactionInsetY: topSuggestionSlotInteractionInsetY,
                    tapAction: { model.tapSuggestionSlot(laneID: lane.id, fallback: suggestion) },
                    holdAction: { model.openSuggestionRolodex(laneID: lane.id) },
                    swipeUpAction: nil
                ) {
                    topSuggestionChipLabel(
                        suggestion: suggestion,
                        isPreviewSelected: isPreviewSelected,
                        chipColor: chipColor,
                        accent: accent,
                        laneID: lane.id
                    )
                }
                .frame(minHeight: HWCKeyboardLayoutMetrics.topSuggestionSlotMinimumHeight(for: model.settings))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(
                    KeyboardInteractionShape(
                        insetX: 0,
                        insetY: topSuggestionSlotInteractionInsetY,
                        cornerRadius: 0
                    )
                )
                .accessibilityLabel(
                    suggestion.kind == .saveWord
                        ? "Save \(suggestion.sourceText) to dictionary"
                        : "Suggestion \(suggestion.replacement)"
                )
                .accessibilityHint(lane.accessibilityHint)
                .accessibilityActions {
                    if lane.alternativeCount > 0 {
                        Button("More suggestions") {
                            model.openSuggestionRolodex(laneID: lane.id)
                        }
                    }
                }
            }
        } else {
            topSuggestionPlaceholder()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func topSuggestionChipColor(
        lane: SuggestionRolodexLane,
        suggestion: KeyboardSuggestionItem
    ) -> KeyboardAutocorrectLogicChipColor {
        model.settings.autocorrectLogicLanes
            .first { $0.id == lane.id }?
            .chipColor(for: suggestion) ?? .none
    }

    private func suggestionRolodexChipControlSurface(
        _ lane: SuggestionRolodexLane,
        suggestion: KeyboardSuggestionItem,
        isPreviewSelected: Bool,
        chipColor: KeyboardAutocorrectLogicChipColor,
        accent: Bool,
        index _: Int
    ) -> some View {
        let activeSuggestion = model.activeSuggestionRolodexLane?.selectedItem ?? suggestion
        return topSuggestionChipLabel(
            suggestion: suggestion,
            isPreviewSelected: isPreviewSelected,
            chipColor: chipColor,
            accent: accent,
            laneID: lane.id
        )
        .frame(minHeight: HWCKeyboardLayoutMetrics.topSuggestionSlotMinimumHeight(for: model.settings))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(
            KeyboardInteractionShape(
                insetX: 0,
                insetY: topSuggestionSlotInteractionInsetY,
                cornerRadius: 0
            )
        )
        .accessibilityLabel("Rolodex suggestion \(activeSuggestion.replacement)")
        .accessibilityHint(
            "Tap anywhere to close. Hold to select. \(activeSuggestion.autobotRationale ?? "")"
        )
    }

    private func topSuggestionChipLabel(
        suggestion: KeyboardSuggestionItem,
        isPreviewSelected: Bool,
        chipColor: KeyboardAutocorrectLogicChipColor,
        accent: Bool,
        laneID: Int
    ) -> some View {
        let isRolodexActive = model.activeSuggestionRolodexLaneID == laneID
        let displayedSuggestion = isRolodexActive
            ? model.activeSuggestionRolodexLane?.selectedItem ?? suggestion
            : suggestion
        let rationaleLayout = HWCKeyboardLayoutMetrics.suggestionRationaleLayout(
            for: model.settings
        )
        let hasRationale = displayedSuggestion.autobotRationaleLabel != nil
        return ZStack {
            if isRolodexActive,
               let activeLane = model.activeSuggestionRolodexLane {
                suggestionRolodexChipWheel(
                    for: activeLane,
                    chipColor: chipColor,
                    accent: accent,
                    isPreviewSelected: isPreviewSelected
                )
            } else {
                let foregroundColor = topSuggestionForegroundColor(
                    for: suggestion.kind,
                    isPreviewSelected: isPreviewSelected
                )
                SuggestionRationaleTextStack(
                    title: suggestion.title,
                    rationaleLabel: suggestion.autobotRationaleLabel,
                    titleFont: .system(
                        size: hasRationale
                            ? rationaleLayout.titleFontSize
                            : (model.settings.appTheme.usesDarkChrome
                                ? (model.settings.largeLegends ? 15 : 14)
                                : (model.settings.largeLegends ? 16 : 15)),
                        weight: (isPreviewSelected || accent) ? .semibold : .regular
                    ),
                    rationaleFontSize: rationaleLayout.rationaleFontSize,
                    titleColor: foregroundColor,
                    rationaleColor: foregroundColor.opacity(0.85),
                    titleKerning: model.settings.appTheme.usesDarkChrome ? 0.08 : 0.14,
                    spacing: rationaleLayout.spacing,
                    titleFrameLaneID: laneID,
                    coordinateSpaceName: Self.glideCoordinateSpace
                )
                .id(suggestion.id)
                // Typing replaces candidates every keypress. Fading the old
                // title out makes the rail visually trail the current prefix.
                .transition(.identity)
            }
        }
        .padding(.horizontal, model.settings.suggestionVisibleWordCount > 3 ? 3 : (isPreviewSelected ? 10 : 8))
        .padding(
            .vertical,
            hasRationale
                ? rationaleLayout.verticalPadding
                : (model.settings.appTheme.usesDarkChrome ? 4 : 3)
        )
        .background(
            Capsule(style: .continuous)
                .fill(
                    topSuggestionChipFillColor(
                        chipColor: chipColor,
                        isPreviewSelected: isPreviewSelected,
                        isRolodexActive: isRolodexActive
                    )
                )
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(
                    topSuggestionChipBorderColor(
                        chipColor: chipColor,
                        isPreviewSelected: isPreviewSelected,
                        isRolodexActive: isRolodexActive
                    ),
                    lineWidth: topSuggestionChipBorderWidth(
                        chipColor: chipColor,
                        isPreviewSelected: isPreviewSelected,
                        isRolodexActive: isRolodexActive
                    )
                )
        )
        .compositingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(nil, value: suggestion.id)
        .animation(suggestionChipChangeAnimation, value: model.activeSuggestionRolodexLane?.selectedIndex)
        .animation(
            .easeOut(duration: HWCKeyboardRolodexClick.pressAnimationDuration),
            value: model.suggestionRolodexVisualPhase
        )
    }

    @ViewBuilder
    private func suggestionRolodexChipWheel(
        for lane: SuggestionRolodexLane,
        chipColor: KeyboardAutocorrectLogicChipColor,
        accent _: Bool,
        isPreviewSelected _: Bool
    ) -> some View {
        if let item = lane.selectedItem {
            let rolodexSquishScale = rolodexSquishScale(for: model.suggestionRolodexDragOffset)
            let visualPhase = model.suggestionRolodexVisualPhase

            rolodexWordLabel(item, isSelected: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(x: rolodexSquishScale.width, y: rolodexSquishScale.height, anchor: .center)
                .scaleEffect(rolodexWordScale(for: model.suggestionRolodexVisualPhase), anchor: .center)
                .id(item.id)
                .transition(suggestionRolodexSquishTransition)
                .animation(
                    .easeOut(duration: HWCKeyboardRolodexClick.pressAnimationDuration),
                    value: visualPhase
                )
        } else {
            EmptyView()
        }
    }

    private var suggestionRolodexSquishTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.86, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 1.10, anchor: .center).combined(with: .opacity)
        )
    }

    @ViewBuilder
    private func rolodexWordLabel(
        _ item: KeyboardSuggestionItem,
        isSelected: Bool
    ) -> some View {
        let textColor = suggestionRolodexChipForegroundColor(for: item.kind, isSelected: isSelected)
        let rationaleLayout = HWCKeyboardLayoutMetrics.suggestionRationaleLayout(for: model.settings)
        let hasRationale = item.autobotRationaleLabel != nil
        let labelFont = hasRationale
            ? Font.system(size: rationaleLayout.titleFontSize, weight: isSelected ? .bold : .regular)
            : (isSelected
                ? Font.system(size: 16, weight: .bold)
                : Font.system(size: 13, weight: .regular))
        let baseLabel = SuggestionRationaleTextStack(
            title: item.title,
            rationaleLabel: item.autobotRationaleLabel,
            titleFont: labelFont,
            rationaleFontSize: rationaleLayout.rationaleFontSize,
            titleColor: textColor,
            rationaleColor: textColor.opacity(0.72),
            titleKerning: 0,
            spacing: rationaleLayout.spacing,
            titleFrameLaneID: nil,
            coordinateSpaceName: nil
        )

        if isSelected {
            baseLabel
                .padding(.horizontal, 10)
                .padding(.vertical, hasRationale ? 0 : 3)
                .accessibilityAddTraits(.isSelected)
        } else {
            baseLabel
        }
    }

    private func rolodexWordScale(for phase: SuggestionRolodexVisualPhase) -> CGFloat {
        switch phase {
        case .idle:
            return 1.04
        case .scrolling:
            return 1.0
        case .selecting:
            return 0.975
        case .selected:
            return 1.03
        }
    }

    private func rolodexSquishScale(for dragOffset: CGFloat) -> CGSize {
        let stepDistance = max(
            HWCKeyboardLayoutMetrics.suggestionRolodexItemHeight(for: model.settings) * 0.82,
            1
        )
        let progress = min(abs(dragOffset) / stepDistance, 1)
        let compression = progress * 0.08
        return CGSize(width: 1 + compression, height: 1 - compression)
    }

    private func suggestionRolodexChipForegroundColor(for kind: KeyboardSuggestionItem.Kind, isSelected: Bool) -> Color {
        _ = kind
        let keyLabelColorWithOpacity = keyLabelColor.opacity(isSelected ? 0.96 : 0.68)
        switch model.settings.appTheme {
        case .classic, .chameleon:
            return keyLabelColorWithOpacity
        case .custom:
            return keyLabelColorWithOpacity
        case .dark:
            return Color.white.opacity(isSelected ? 0.96 : 0.68)
        }
    }

    private func topSuggestionPlaceholder() -> some View {
        ZStack {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toolbarCommandKey(
        _ label: String,
        isActive: Bool = false,
        fontSize: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        toolbarKey(
            action: action,
            fillColor: isActive ? toolbarCommandActiveFillColor : nil,
            borderColor: isActive ? toolbarCommandActiveBorderColor : nil,
            accent: isActive
        ) {
            customLayerTokenFace(
                label,
                fontSize: fontSize ?? (
                    model.settings.appTheme.usesDarkChrome
                        ? (model.settings.largeLegends ? 13 : 12)
                        : (model.settings.largeLegends ? 15 : 13)
                ),
                weight: model.settings.appTheme.usesDarkChrome ? .regular : .medium,
                color: isActive ? activeControlLabelColor : controlLabelColor
            )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toolbarSpaceKey(action: @escaping () -> Void) -> some View {
        toolbarCommandKey(
            toolbarSpaceLabel,
            fontSize: model.settings.showControlLabels ? toolbarControlLabelFontSize + 1 : nil,
            action: action
        )
        .accessibilityLabel("Space")
    }

    private func toolbarCapsLockKey(
        isActive: Bool = false
    ) -> some View {
        toolbarGestureKey(
            tapAction: { model.tapCapsKey() },
            holdEnabled: model.settings.capsHoldToLockEnabled,
            holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
            holdBeganAction: { model.beginHoldSwipeOverride() },
            holdEndedAction: { model.endHoldSwipeOverride() },
            holdAction: { model.holdCapsKey() },
            indicatorState: model.capsIndicatorState,
            fillColor: isActive ? toolbarCapsActiveFillColor : nil,
            borderColor: isActive ? toolbarCapsActiveBorderColor : nil,
            accent: isActive
        ) {
            toolbarShiftFace(isActive: isActive)
        }
        .accessibilityLabel("Caps Lock")
    }

    private func toolbarShiftFace(isActive: Bool) -> some View {
        toolbarLabeledIcon(
            "chevron.up",
            label: toolbarShiftLabel,
            foregroundColor: toolbarCapsForegroundColor(isActive: isActive),
            iconSize: toolbarShiftIconSize
        )
    }

    private func toolbarReturnKey(action: @escaping () -> Void) -> some View {
        toolbarKey(action: action) {
            toolbarLabeledIcon(
                "return.left",
                label: toolbarReturnLabel,
                foregroundColor: controlLabelColor,
                iconSize: toolbarActionIconSize
            )
        }
        .accessibilityLabel("Return")
    }

    @ViewBuilder
    private func toolbarInsertKey(_ value: String, index: Int) -> some View {
        toolbarValueKey(
            value,
            row: .toolbar,
            holdValue: model.holdValue(for: .toolbar, index: index)
        )
    }

    private func toolbarIconKey(
        _ systemImage: String,
        isEnabled: Bool = true,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        toolbarKey(action: action) {
            Image(systemName: systemImage)
                .font(
                    .system(
                        size: model.settings.appTheme.usesDarkChrome
                            ? (model.settings.largeLegends ? 20 : 18)
                            : (model.settings.largeLegends ? 20 : 18),
                        weight: .regular
                    )
                )
            .foregroundColor(controlLabelColor)
            .opacity(isEnabled ? 1 : 0.45)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private func toolbarDeleteKey(preservingExpandedMenu: Bool) -> some View {
        toolbarRepeatKey(
            repeatEnabled: model.settings.deleteHoldEnabled,
            tapAction: {
                if preservingExpandedMenu {
                    model.backKeepingMenu()
                } else {
                    model.back()
                }
            },
            holdStartAction: {
                model.beginDeleteHold(preservingExpandedMenu: preservingExpandedMenu)
            },
            repeatAction: {
                model.performDeleteHoldStep()
            },
            holdEndAction: {
                model.endDeleteHold()
            }
        ) {
            toolbarLabeledIcon(
                model.settings.appTheme.usesDarkChrome ? "delete.backward.fill" : "delete.backward",
                label: toolbarDeleteLabel,
                foregroundColor: controlLabelColor,
                iconSize: toolbarActionIconSize
            )
        }
        .accessibilityLabel("Delete Backward")
    }

    private func toolbarForwardDeleteKey(preservingExpandedMenu: Bool) -> some View {
        toolbarRepeatKey(
            repeatEnabled: model.settings.deleteHoldEnabled,
            tapAction: {
                if preservingExpandedMenu {
                    model.deleteForwardPreservingExpandedMenu()
                } else {
                    model.deleteForward()
                }
            },
            holdStartAction: {},
            repeatAction: {
                if preservingExpandedMenu {
                    model.deleteForwardPreservingExpandedMenu()
                } else {
                    model.deleteForward()
                }
            },
            holdEndAction: {}
        ) {
            toolbarLabeledIcon(
                model.settings.appTheme.usesDarkChrome ? "delete.forward.fill" : "delete.forward",
                label: toolbarDeleteLabel,
                foregroundColor: controlLabelColor,
                iconSize: toolbarActionIconSize
            )
        }
        .accessibilityLabel("Delete Forward")
    }

    private func toolbarMenuKey(
        _ label: String,
        systemImage: String,
        isActive: Bool = false
    ) -> some View {
        return toolbarGestureKey(
            tapAction: { model.tapExpandedMenuKey() },
            holdEnabled: model.settings.menuHoldToLatchEnabled,
            holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
            holdBeganAction: { model.beginHoldSwipeOverride() },
            holdEndedAction: { model.endHoldSwipeOverride() },
            holdAction: { model.holdExpandedMenuKey() },
            indicatorState: model.menuIndicatorState,
            fillColor: isActive ? actionAccentFillColor : primaryKeyFillColor,
            borderColor: isActive ? actionAccentBorderColor : keyBorderColor,
            accent: isActive
        ) {
            Image(systemName: systemImage)
            .font(.system(size: toolbarShiftIconSize, weight: .regular))
            .foregroundColor(toolbarMenuForegroundColor(isActive: isActive))
            .frame(width: toolbarShiftIconSize, height: toolbarShiftIconSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(label)
    }

    private func toolbarGestureKey<Content: View>(
        tapAction: @escaping () -> Void,
        holdEnabled: Bool,
        holdDuration: TimeInterval,
        holdBeganAction: @escaping () -> Void = {},
        holdEndedAction: @escaping () -> Void = {},
        holdAction: @escaping () -> Void,
        indicatorState: ToolbarIndicatorState? = nil,
        fillColor: Color? = nil,
        borderColor: Color? = nil,
        accent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        KeyboardDualActionButton(
            theme: model.settings.appTheme,
            accent: accent,
            suppressMotion: suppressKeyPressMotion,
            darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
            holdEnabled: holdEnabled,
            holdDuration: holdDuration,
            holdBeganAction: holdBeganAction,
            holdEndedAction: holdEndedAction,
            tapAction: tapAction,
            holdAction: holdAction
        ) {
            content()
                .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
                .background(
                    keySurface(
                        fillColor: fillColor ?? primaryKeyFillColor,
                        borderColor: borderColor ?? keyBorderColor,
                        pressedFillColor: accent ? toolbarAccentPressedFillColor : toolbarPressedFillColor
                    )
                )
                .overlay(toolbarIndicatorOverlay(state: indicatorState), alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func toolbarValueKey(
        _ value: String,
        row: HWCKeyboardRowKind,
        holdValue: String? = nil
    ) -> some View {
        if let specialAction = KeyboardSpecialKeyAction.resolved(from: value) {
            toolbarSpecialActionKey(specialAction, row: row)
        } else {
            let resolvedHold = holdValue?.isEmpty == false ? holdValue : nil

            toolbarGestureKey(
                tapAction: {
                    guard !value.isEmpty else { return }
                    model.performKey(value, from: row)
                },
                holdEnabled: resolvedHold != nil,
                holdDuration: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
                holdAction: {
                    guard let resolvedHold else { return }
                    model.insertHoldKey(resolvedHold, from: row)
                }
            ) {
                toolbarAdaptiveLegend(
                    value.isEmpty ? " " : value,
                    fontSize: model.settings.appTheme.usesDarkChrome
                        ? (model.settings.largeLegends ? 21 : 18)
                        : (model.settings.largeLegends ? 21 : 19),
                    weight: .regular,
                    color: model.settings.appTheme.usesDarkChrome ? controlLabelColor : keyLabelColor
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(value.isEmpty ? 0.3 : 1.0)
            }
        }
    }

    @ViewBuilder
    private func toolbarAdaptiveLegend(
        _ value: String,
        fontSize: CGFloat,
        weight: Font.Weight,
        color: Color
    ) -> some View {
        if let customLayerVisual = customLayerDisplayVisual(for: value) {
            Image(systemName: customLayerVisual.icon)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(color)
                .accessibilityLabel(customLayerVisual.title)
        } else {
            let legend = HWKKeyLegendPresentation.resolve(value)

            Text(legend.text)
                .font(
                    .system(
                        size: min(fontSize, CGFloat(legend.maximumFontSize)),
                        weight: weight
                    )
                )
                .foregroundColor(color)
                .lineLimit(legend.lineLimit)
                .minimumScaleFactor(legend.minimumScaleFactor)
                .multilineTextAlignment(.center)
                .allowsTightening(true)
                .accessibilityLabel(legend.accessibilityText)
                .padding(.horizontal, legend.usesFullKeyWidth ? 3 : 0)
                .padding(.vertical, legend.lineLimit > 1 ? 2 : 0)
        }
    }

    @ViewBuilder
    private func toolbarSpecialActionKey(
        _ action: KeyboardSpecialKeyAction,
        row: HWCKeyboardRowKind
    ) -> some View {
        let preservingExpandedMenu = rowPreservesExpandedMenu(row)

        switch action {
        case .enter:
            toolbarReturnKey {
                model.performKey(action.storageToken, from: row)
            }
        case .shift:
            toolbarCapsLockKey(isActive: model.isCapsShiftActive)
        case .toggleLayer:
            toolbarTextKey(model.isSymbolKeyboard ? "ABC" : "123") {
                model.toggleSymbols()
            }
        case .toggleSymbolPage:
            toolbarTextKey(model.specialActionLegend(for: action)) {
                model.toggleSymbolPage()
            }
        case .space:
            toolbarSpaceKey {
                model.performKey(action.storageToken, from: row)
            }
        case .tab:
            toolbarCommandKey("Tab") {
                model.performKey(action.storageToken, from: row)
            }
        case .undo:
            toolbarIconKey("arrow.uturn.backward", isEnabled: true, accessibilityLabel: "Undo") {
                model.performKey(action.storageToken, from: row)
            }
        case .cut:
            toolbarIconKey("scissors", isEnabled: true, accessibilityLabel: "Cut") {
                model.performKey(action.storageToken, from: row)
            }
        case .copy:
            toolbarIconKey("doc.on.doc", isEnabled: true, accessibilityLabel: "Copy") {
                model.performKey(action.storageToken, from: row)
            }
        case .paste:
            toolbarIconKey("doc.on.clipboard", isEnabled: true, accessibilityLabel: "Paste") {
                model.performKey(action.storageToken, from: row)
            }
        case .clipboard:
            toolbarIconKey("tray.full", isEnabled: true, accessibilityLabel: "Clipboard") {
                model.performKey(action.storageToken, from: row)
            }
        case .redo:
            toolbarIconKey("arrow.uturn.forward", isEnabled: true, accessibilityLabel: "Redo") {
                model.performKey(action.storageToken, from: row)
            }
        case .deleteBackward:
            toolbarDeleteKey(preservingExpandedMenu: preservingExpandedMenu)
        case .deleteForward:
            toolbarForwardDeleteKey(preservingExpandedMenu: preservingExpandedMenu)
        case .moveLeft, .moveRight, .moveUp, .moveDown:
            toolbarRepeatKey(
                repeatEnabled: true,
                tapAction: { model.performKey(action.storageToken, from: row) },
                holdStartAction: {},
                repeatAction: { model.performKey(action.storageToken, from: row) },
                holdEndAction: {},
                shouldSuppressKeyCommit: {
                    model.shouldSuppressKeyCommitForDirectionalSwipe
                }
            ) {
                toolbarLabeledIcon(
                    cursorSystemImage(for: action),
                    label: cursorControlLabel(for: action),
                    foregroundColor: controlLabelColor,
                    iconSize: toolbarActionIconSize
                )
            }
            .accessibilityLabel("Move \(action.shelfTitle)")
        case .menu:
            toolbarMenuKey(
                model.isExpanded ? "Hide" : "More",
                systemImage: model.isExpanded ? "chevron.down" : "line.3.horizontal",
                isActive: model.isExpanded
            )
        case .nextKeyboard:
            toolbarIconKey("globe", isEnabled: true, accessibilityLabel: "Next Keyboard") {
                model.advanceToNextKeyboard()
            }
        }
    }

    private func cursorControlLabel(for action: KeyboardSpecialKeyAction) -> String? {
        guard model.settings.showControlLabels else { return nil }
        switch action {
        case .moveLeft:
            return "Left"
        case .moveRight:
            return "Right"
        case .moveUp:
            return "Up"
        case .moveDown:
            return "Down"
        default:
            return nil
        }
    }

    private func cursorSystemImage(for action: KeyboardSpecialKeyAction) -> String {
        switch action {
        case .moveLeft:
            return "arrow.left"
        case .moveRight:
            return "arrow.right"
        case .moveUp:
            return "arrow.up"
        case .moveDown:
            return "arrow.down"
        default:
            return "arrow.left"
        }
    }

    private func rowPreservesExpandedMenu(_ row: HWCKeyboardRowKind) -> Bool {
        switch row {
        case .symbolUtility, .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility,
             .letterUtility, .letterBottomLeading:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func toolbarIndicatorOverlay(state: ToolbarIndicatorState?) -> some View {
        if let state {
            toolbarIndicatorLight(state: state)
        }
    }

    private func toolbarRepeatKey<Content: View>(
        repeatEnabled: Bool,
        tapAction: @escaping () -> Void,
        holdStartAction: @escaping () -> Void,
        repeatAction: @escaping () -> Void,
        holdEndAction: @escaping () -> Void,
        shouldSuppressKeyCommit: @escaping () -> Bool = { false },
        fillColor: Color? = nil,
        borderColor: Color? = nil,
        accent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        KeyboardRepeatButton(
            theme: model.settings.appTheme,
            accent: accent,
            suppressMotion: suppressKeyPressMotion,
            darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor,
            repeatEnabled: repeatEnabled,
            initialDelay: TimeInterval(model.settings.keyHoldDurationMs) / 1000,
            repeatInterval: 0.09,
            tapAction: tapAction,
            holdStartAction: holdStartAction,
            repeatAction: repeatAction,
            holdEndAction: holdEndAction,
            shouldSuppressKeyCommit: shouldSuppressKeyCommit
        ) {
            content()
                .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
                .background(
                    keySurface(
                        fillColor: fillColor ?? primaryKeyFillColor,
                        borderColor: borderColor ?? keyBorderColor,
                        pressedFillColor: accent ? toolbarAccentPressedFillColor : toolbarPressedFillColor
                    )
                )
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func toolbarIndicatorLight(state: ToolbarIndicatorState) -> some View {
        if model.settings.appTheme.usesDarkChrome {
            RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: toolbarIndicatorFillColors(for: state),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0.9, style: .continuous)
                        .stroke(toolbarIndicatorBorderColor(for: state), lineWidth: 0.8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 0.45, style: .continuous)
                        .stroke(
                            Color.white.opacity(toolbarIndicatorHighlightOpacity(for: state) * 0.55),
                            lineWidth: 0.45
                        )
                        .padding(0.8)
                )
                .overlay(
                    Rectangle()
                        .fill(toolbarIndicatorCoreColor(for: state))
                        .frame(height: 1.2)
                        .opacity(toolbarIndicatorCoreOpacity(for: state))
                        .padding(.horizontal, 2.4)
                )
                .frame(width: 18, height: 4)
                .padding(.top, 2)
        } else {
            RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: toolbarIndicatorFillColors(for: state),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 2.4, style: .continuous)
                        .stroke(toolbarIndicatorBorderColor(for: state), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(toolbarIndicatorHighlightOpacity(for: state)),
                                    Color.white.opacity(0.02),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                        .fill(toolbarIndicatorCoreColor(for: state))
                        .frame(height: 2.2)
                        .blur(radius: state == .off ? 0 : 0.6)
                        .opacity(toolbarIndicatorCoreOpacity(for: state))
                        .padding(.horizontal, 4)
                )
                .frame(width: 18, height: 6)
                .padding(.top, 4)
                .shadow(
                    color: Color.black.opacity(0.28),
                    radius: 1.0,
                    x: 0,
                    y: 0.8
                )
                .shadow(
                    color: toolbarIndicatorGlowColor(for: state),
                    radius: toolbarIndicatorGlowRadius(for: state),
                    x: 0,
                    y: 0
                )
        }
    }

    private func toolbarIndicatorFillColors(for state: ToolbarIndicatorState) -> [Color] {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            switch state {
            case .off:
                return [
                    Color(red: 0.28, green: 0.30, blue: 0.33),
                    Color(red: 0.08, green: 0.09, blue: 0.10),
                ]
            case .primed:
                return [
                    palettePrimaryColor.opacity(0.95),
                    paletteSecondaryColor.opacity(0.84),
                ]
            case .latched:
                return [
                    paletteGlowColor.opacity(0.98),
                    palettePrimaryColor.opacity(0.88),
                ]
            }
        case .dark:
            switch state {
            case .off:
                return [
                    Color(red: 0.21, green: 0.22, blue: 0.23),
                    Color(red: 0.07, green: 0.08, blue: 0.09),
                ]
            case .primed:
                return [
                    darkThemeReferenceAccentColor.opacity(0.82),
                    Color(red: 0.08, green: 0.30, blue: 0.33),
                ]
            case .latched:
                return [
                    darkThemeReferenceAccentColor.opacity(0.98),
                    Color(red: 0.10, green: 0.45, blue: 0.50),
                ]
            }
        }
    }

    private func toolbarIndicatorBorderColor(for state: ToolbarIndicatorState) -> Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            switch state {
            case .off:
                return Color.black.opacity(0.56)
            case .primed:
                return paletteGlowColor.opacity(0.56)
            case .latched:
                return paletteGlowColor.opacity(0.88)
            }
        case .dark:
            switch state {
            case .off:
                return Color.black.opacity(0.72)
            case .primed:
                return darkThemeReferenceAccentColor.opacity(0.44)
            case .latched:
                return darkThemeReferenceAccentColor.opacity(0.86)
            }
        }
    }

    private func toolbarIndicatorHighlightOpacity(for state: ToolbarIndicatorState) -> Double {
        switch state {
        case .off:
            return model.settings.appTheme.usesDarkChrome ? 0.10 : 0.18
        case .primed:
            return model.settings.appTheme.usesDarkChrome ? 0.22 : 0.28
        case .latched:
            return model.settings.appTheme.usesDarkChrome ? 0.30 : 0.36
        }
    }

    private func toolbarIndicatorCoreColor(for state: ToolbarIndicatorState) -> Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            switch state {
            case .off:
                return Color.white.opacity(0.06)
            case .primed:
                return paletteGlowColor.opacity(0.72)
            case .latched:
                return Color.white.opacity(0.92)
            }
        case .dark:
            switch state {
            case .off:
                return Color.white.opacity(0.04)
            case .primed:
                return darkThemeReferenceAccentColor.opacity(0.78)
            case .latched:
                return Color.white.opacity(0.82)
            }
        }
    }

    private func toolbarIndicatorCoreOpacity(for state: ToolbarIndicatorState) -> Double {
        switch state {
        case .off:
            return 0.65
        case .primed:
            return 0.86
        case .latched:
            return 1
        }
    }

    private func toolbarIndicatorGlowColor(for state: ToolbarIndicatorState) -> Color {
        switch state {
        case .off:
            return .clear
        case .primed:
            return model.settings.appTheme.usesDarkChrome
                ? darkThemeReferenceAccentColor.opacity(0.24)
                : paletteGlowColor.opacity(0.22)
        case .latched:
            return model.settings.appTheme.usesDarkChrome
                ? darkThemeReferenceAccentColor.opacity(0.40)
                : paletteGlowColor.opacity(0.34)
        }
    }

    private func toolbarIndicatorGlowRadius(for state: ToolbarIndicatorState) -> CGFloat {
        switch state {
        case .off:
            return 0
        case .primed:
            return model.settings.appTheme.usesDarkChrome ? 3.0 : 3.4
        case .latched:
            return model.settings.appTheme.usesDarkChrome ? 4.8 : 5.2
        }
    }

    private func toolbarKey<Content: View>(
        action: @escaping () -> Void,
        fillColor: Color? = nil,
        borderColor: Color? = nil,
        accent: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(height: HWCKeyboardLayoutMetrics.toolbarHeight(for: model.settings))
                .background(
                    keySurface(
                        fillColor: fillColor ?? primaryKeyFillColor,
                        borderColor: borderColor ?? keyBorderColor,
                        pressedFillColor: accent ? toolbarAccentPressedFillColor : toolbarPressedFillColor
                    )
                )
        }
        .buttonStyle(
            KeyboardPressStyle(
                theme: model.settings.appTheme,
                accent: accent,
                suppressMotion: suppressKeyPressMotion,
                darkPressBorderColor: darkThemeUniversalTapHighlightBorderColor
            )
        )
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var actionAccentFillColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return paletteSecondaryColor.opacity(0.92)
        case .dark:
            return darkThemePressedKeyFillColor
        }
    }

    private var actionAccentBorderColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return paletteGlowColor.opacity(0.84)
        case .dark:
            return darkThemeDividerColor
        }
    }

    private var darkThemePressedKeyFillColor: Color {
        darkThemeToolbarSelectedFill
    }

    private var secondaryPressedFillColor: Color? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        return darkThemePressedKeyFillColor
    }

    private var toolbarPressedFillColor: Color? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        return darkThemePressedKeyFillColor
    }

    private var toolbarAccentPressedFillColor: Color? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        return darkThemePressedKeyFillColor
    }

    private var specialPressedFillColor: Color? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        return darkThemePressedKeyFillColor
    }

    private var toolbarCommandActiveFillColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return paletteSecondaryColor.opacity(0.78)
        case .dark:
            return darkThemeToolbarSelectedFill
        }
    }

    private var toolbarCommandActiveBorderColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return paletteGlowColor.opacity(0.84)
        case .dark:
            return darkThemeReferenceAccentColor.opacity(0.60)
        }
    }

    private var toolbarCapsActiveFillColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return toolbarCommandActiveFillColor
        case .dark:
            return toolbarCommandActiveFillColor
        }
    }

    private var toolbarCapsActiveBorderColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return toolbarCommandActiveBorderColor
        case .dark:
            return toolbarCommandActiveBorderColor
        }
    }

    private var collapsedStripCornerRadius: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 9
        case .dark:
            return 0
        }
    }

    private var collapsedStripFillColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color(red: 0.10, green: 0.10, blue: 0.11).opacity(0.96)
        case .dark:
            return .clear
        }
    }

    private var collapsedStripBorderColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return palettePrimaryColor.opacity(0.14)
        case .dark:
            return .clear
        }
    }

    private var collapsedStripBorderWidth: CGFloat {
        model.settings.appTheme.usesDarkChrome ? 0.6 : 0.8
    }

    private var collapsedStripShadowColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return Color.black.opacity(0.28)
        case .dark:
            return .clear
        }
    }

    private var collapsedStripShadowRadius: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 7
        case .dark:
            return 0
        }
    }

    private var collapsedStripShadowYOffset: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 2
        case .dark:
            return 0
        }
    }

    private var expandedPanelShadowColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return .clear
        case .dark:
            return .clear
        }
    }

    private var expandedPanelShadowRadius: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 0
        case .dark:
            return 0
        }
    }

    private var expandedPanelShadowYOffset: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 0
        case .dark:
            return 0
        }
    }

    private var keyHighlightColor: Color {
        model.settings.appTheme.usesDarkChrome
            ? .clear
            : .clear
    }

    private var keyHighlightHeight: CGFloat {
        0
    }

    private var keyShadowColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon:
            return Color.black.opacity(0.14)
        case .dark:
            return .clear
        case .custom:
            return Color.black.opacity(Double(model.settings.customKeyStyle.shadowDepth) * 0.045)
        }
    }

    private var keyShadowRadius: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon:
            return 2.2
        case .dark:
            return 0
        case .custom:
            return CGFloat(model.settings.customKeyStyle.shadowDepth)
        }
    }

    private var keyShadowYOffset: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon:
            return 1.2
        case .dark:
            return 0
        case .custom:
            return CGFloat(model.settings.customKeyStyle.shadowDepth) * 0.45
        }
    }

    private var darkThemeTopChromeFill: Color {
        Color(red: 0.04, green: 0.04, blue: 0.05)
    }

    private var darkThemeToolbarFill: Color {
        Color(red: 0.14, green: 0.14, blue: 0.15)
    }

    private var darkThemeQuickInsertRailFill: Color {
        Color(red: 0.16, green: 0.16, blue: 0.17)
    }

    private var darkThemeToolbarSelectedFill: Color {
        Color(red: 0.13, green: 0.13, blue: 0.14)
    }

    private var darkThemeTopRowFill: Color {
        Color(red: 0.17, green: 0.17, blue: 0.18)
    }

    private var darkThemeMiddleRowFill: Color {
        Color(red: 0.15, green: 0.15, blue: 0.16)
    }

    private var darkThemeBottomLetterRowFill: Color {
        Color(red: 0.13, green: 0.13, blue: 0.14)
    }

    private var darkThemeUtilityRowFill: Color {
        Color(red: 0.14, green: 0.14, blue: 0.15)
    }

    private var darkThemeBottomControlFill: Color {
        Color(red: 0.09, green: 0.09, blue: 0.10)
    }

    private var darkThemeUtilityWideFill: Color {
        Color(red: 0.15, green: 0.15, blue: 0.16)
    }

    private var darkThemeSeparatorBandFill: Color {
        Color(red: 0.26, green: 0.26, blue: 0.27)
    }

    private var darkThemeDividerColor: Color {
        Color(red: 0.25, green: 0.25, blue: 0.26)
    }

    private var darkThemePredictionTextColor: Color {
        Color(red: 0.88, green: 0.86, blue: 0.78)
    }

    private func accessoryHandleTapWidth(for placement: AccessoryHandlePlacement) -> CGFloat {
        switch (model.settings.appTheme, placement) {
        case (.classic, .quickInsertRow), (.chameleon, .quickInsertRow), (.custom, .quickInsertRow):
            return 40
        case (.dark, .quickInsertRow):
            return 46
        }
    }

    private func accessoryHandleTapHeight(for placement: AccessoryHandlePlacement) -> CGFloat {
        switch (model.settings.appTheme, placement) {
        case (.classic, .quickInsertRow), (.chameleon, .quickInsertRow), (.custom, .quickInsertRow):
            return 14
        case (.dark, .quickInsertRow):
            return 16
        }
    }

    private func accessoryHandleWidth(for placement: AccessoryHandlePlacement) -> CGFloat {
        switch (model.settings.appTheme, placement) {
        case (.classic, .quickInsertRow), (.chameleon, .quickInsertRow), (.custom, .quickInsertRow):
            return 24
        case (.dark, .quickInsertRow):
            return 26
        }
    }

    private func accessoryHandleHeight(for placement: AccessoryHandlePlacement) -> CGFloat {
        switch (model.settings.appTheme, placement) {
        case (.classic, _), (.chameleon, _), (.custom, _):
            return 5
        case (.dark, .quickInsertRow):
            return 4.5
        }
    }

    private func accessoryHandleCornerRadius(for placement: AccessoryHandlePlacement) -> CGFloat {
        accessoryHandleHeight(for: placement) / 2
    }

    private func accessoryHandleFillColor(for placement: AccessoryHandlePlacement) -> Color {
        switch (model.settings.appTheme, placement) {
        case (.classic, _), (.chameleon, _), (.custom, _):
            return Color.black.opacity(0.28)
        case (.dark, .quickInsertRow):
            return darkThemeTopSeparatorCenterColor.opacity(0.94)
        }
    }

    private func accessoryHandleBorderColor(for placement: AccessoryHandlePlacement) -> Color {
        switch (model.settings.appTheme, placement) {
        case (.classic, _), (.chameleon, _), (.custom, _):
            return Color.white.opacity(0.14)
        case (.dark, .quickInsertRow):
            return Color.black.opacity(0.34)
        }
    }

    private func accessoryHandleBorderWidth(for placement: AccessoryHandlePlacement) -> CGFloat {
        switch (model.settings.appTheme, placement) {
        case (.classic, _), (.chameleon, _), (.custom, _):
            return 0.6
        case (.dark, .quickInsertRow):
            return 0.35
        }
    }

    private func accessoryHandleVerticalOffset(for placement: AccessoryHandlePlacement) -> CGFloat {
        switch (model.settings.appTheme, placement) {
        case (.classic, _), (.chameleon, _), (.custom, _):
            return 2
        case (.dark, .quickInsertRow):
            return -1.5
        }
    }

    private var darkThemeExpandedRowCount: Int {
        showsExpandedQuickInsertRow ? 4 : 3
    }

    private var quickInsertRestoreHandleVerticalOffset: CGFloat {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return 2
        case .dark:
            return -1.5
        }
    }

    private var darkThemeRowSeparatorOuterThickness: CGFloat {
        1 / UIScreen.main.scale
    }

    private var darkThemeRowSeparatorCenterThickness: CGFloat {
        1 / UIScreen.main.scale
    }

    private var darkThemeRowSeparatorOuterColor: Color {
        Color.white.opacity(0.20)
    }

    private var darkThemeRowSeparatorCenterColor: Color {
        darkThemeDividerColor
    }

    private var darkThemeTopSeparatorOuterColor: Color {
        Color.white.opacity(0.28)
    }

    private var darkThemeTopSeparatorCenterColor: Color {
        Color(red: 0.40, green: 0.40, blue: 0.41)
    }

    private func darkThemeAnimatedExpandedLayer<Content: View>(
        fromTop index: Int,
        separatorTone: DarkThemeSeparatorTone = .standard,
        @ViewBuilder content: () -> Content
    ) -> some View {
        return VStack(spacing: 0) {
            darkThemeRowSeparator(tone: separatorTone)
            content()
        }
    }

    private func darkThemeCardVerticalOffset(fromTop index: Int) -> CGFloat {
        let layerHeights = HWCKeyboardLayoutMetrics.darkThemeExpandedLayerHeights(
            for: model.settings,
            quickInsertMinimized: model.isQuickInsertRowMinimized
        )
        let belowCount = max(layerHeights.count - 1 - index, 0)
        let stackedHeight = layerHeights.prefix(belowCount).reduce(CGFloat.zero, +)
        return -stackedHeight
    }

    private var darkThemeMainStripTopSeparator: some View {
        darkThemeRowSeparator(tone: .top)
    }

    private func darkThemeRowSeparator(tone: DarkThemeSeparatorTone = .standard) -> some View {
        let outerColor: Color
        let centerColor: Color

        switch tone {
        case .standard:
            outerColor = darkThemeRowSeparatorOuterColor
            centerColor = darkThemeRowSeparatorCenterColor
        case .top:
            outerColor = darkThemeTopSeparatorOuterColor
            centerColor = darkThemeTopSeparatorCenterColor
        }

        return VStack(spacing: 0) {
            Rectangle()
                .fill(outerColor)
                .frame(height: darkThemeRowSeparatorOuterThickness)

            Rectangle()
                .fill(centerColor)
                .frame(height: darkThemeRowSeparatorCenterThickness)

            Rectangle()
                .fill(outerColor)
                .frame(height: darkThemeRowSeparatorOuterThickness)
        }
        .frame(maxWidth: .infinity)
        .mask {
            HStack(spacing: model.isSemiFoldActive ? model.semiFoldGap : 0) {
                Rectangle()
                Rectangle()
            }
        }
        .allowsHitTesting(false)
    }

    private var darkThemeSeparatorWidth: CGFloat {
        1 / UIScreen.main.scale
    }

    private var darkThemeExpandedKeySeparatorInset: CGFloat {
        model.settings.largeLegends ? 10 : 8
    }

    private func fillColor(for band: ExpandedVisualBand) -> Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return primaryKeyFillColor
        case .dark:
            switch band {
            case .top:
                return darkThemeTopRowFill
            case .middle:
                return darkThemeMiddleRowFill
            case .bottom:
                return darkThemeBottomLetterRowFill
            }
        }
    }

    private func pressedFillColor(for band: ExpandedVisualBand) -> Color? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        return darkThemePressedKeyFillColor
    }

    private func darkThemeFillColor(for row: HWCKeyboardRowKind) -> Color {
        switch row {
        case .letterTop:
            return darkThemeTopRowFill
        case .letterMiddle:
            return darkThemeMiddleRowFill
        case .letterBottom:
            return darkThemeBottomLetterRowFill
        default:
            return primaryKeyFillColor
        }
    }

    private func darkThemePressedFillColor(for row: HWCKeyboardRowKind) -> Color? {
        guard model.settings.appTheme.usesDarkChrome else { return nil }
        return darkThemePressedKeyFillColor
    }

    private func toolbarMenuForegroundColor(isActive: Bool) -> Color {
        guard model.settings.appTheme.usesDarkChrome else {
            return isActive ? activeControlLabelColor : controlLabelColor
        }

        return isActive ? darkThemeReferenceAccentColor : controlLabelColor
    }

    private func toolbarCapsForegroundColor(isActive: Bool) -> Color {
        guard model.settings.appTheme.usesDarkChrome else {
            return isActive ? activeControlLabelColor : controlLabelColor
        }

        return isActive ? darkThemeReferenceAccentColor : controlLabelColor
    }

    private func topSuggestionForegroundColor(
        for kind: KeyboardSuggestionItem.Kind,
        isPreviewSelected: Bool = false
    ) -> Color {
        if isPreviewSelected {
            return activeControlLabelColor
        }

        guard kind != .completion else {
            return model.settings.appTheme.usesDarkChrome ? controlLabelColor : keyLabelColor
        }

        guard model.settings.appTheme.usesDarkChrome else {
            return activeControlLabelColor
        }

        return darkThemeReferenceAccentColor
    }

    private func topSuggestionChipFillColor(
        chipColor: KeyboardAutocorrectLogicChipColor,
        isPreviewSelected: Bool,
        isRolodexActive: Bool
    ) -> Color {
        if isRolodexActive {
            let accentColor = color(for: chipColor, fallback: previewAccentColor)
            switch model.suggestionRolodexVisualPhase {
            case .idle:
                return .clear
            case .scrolling:
                return accentColor.opacity(0.10)
            case .selecting:
                return accentColor.opacity(model.settings.appTheme.usesDarkChrome ? 0.24 : 0.20)
            case .selected:
                return accentColor.opacity(model.settings.appTheme.usesDarkChrome ? 0.42 : 0.36)
            }
        }

        if isPreviewSelected {
            return color(for: chipColor, fallback: previewAccentColor).opacity(0.22)
        }

        guard chipColor != .none else { return .clear }

        return color(for: chipColor, fallback: previewAccentColor).opacity(0.10)
    }

    private func topSuggestionChipBorderColor(
        chipColor: KeyboardAutocorrectLogicChipColor,
        isPreviewSelected: Bool,
        isRolodexActive: Bool
    ) -> Color {
        if isRolodexActive {
            let accentColor = color(for: chipColor, fallback: previewBorderColor)
            switch model.suggestionRolodexVisualPhase {
            case .idle:
                return .clear
            case .scrolling:
                return accentColor.opacity(model.settings.appTheme.usesDarkChrome ? 0.28 : 0.22)
            case .selecting:
                return accentColor.opacity(model.settings.appTheme.usesDarkChrome ? 0.46 : 0.38)
            case .selected:
                return accentColor.opacity(model.settings.appTheme.usesDarkChrome ? 0.68 : 0.58)
            }
        }

        if isPreviewSelected {
            return color(for: chipColor, fallback: previewBorderColor).opacity(0.70)
        }

        guard chipColor != .none else { return .clear }

        return color(for: chipColor, fallback: previewBorderColor)
            .opacity(model.settings.appTheme.usesDarkChrome ? 0.28 : 0.22)
    }

    private func topSuggestionChipBorderWidth(
        chipColor: KeyboardAutocorrectLogicChipColor,
        isPreviewSelected: Bool,
        isRolodexActive: Bool
    ) -> CGFloat {
        if isRolodexActive {
            return model.suggestionRolodexVisualPhase == .idle
                ? 0
                : (model.settings.appTheme.usesDarkChrome ? 0.6 : 0.7)
        }

        if isPreviewSelected {
            return model.settings.appTheme.usesDarkChrome ? 0.8 : 0.9
        }

        return chipColor != .none ? (model.settings.appTheme.usesDarkChrome ? 0.6 : 0.7) : 0
    }

    private var previewAccentColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return paletteSecondaryColor
        case .dark:
            return darkThemeReferenceAccentColor
        }
    }

    private var previewBorderColor: Color {
        switch model.settings.appTheme {
        case .classic, .chameleon, .custom:
            return paletteGlowColor
        case .dark:
            return darkThemeReferenceAccentColor
        }
    }

    private func color(
        for chipColor: KeyboardAutocorrectLogicChipColor,
        fallback: Color
    ) -> Color {
        switch chipColor {
        case .none:
            return fallback
        case .blue:
            return Color(red: 0.20, green: 0.48, blue: 1.0)
        case .green:
            return Color(red: 0.13, green: 0.72, blue: 0.42)
        case .orange:
            return Color(red: 1.0, green: 0.56, blue: 0.18)
        }
    }

    @ViewBuilder
    private var darkThemeBackgroundChrome: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(darkThemeTopChromeFill)
                .frame(height: 14)
            Rectangle()
                .fill(Color(red: 0.12, green: 0.12, blue: 0.13))
                .frame(height: 10)
            Spacer()
        }
    }

    private func isDarkAccentKey(_ label: String) -> Bool {
        false
    }

    private var darkThemeAccentKeyFillColor: Color {
        Color(red: 0.11, green: 0.16, blue: 0.20)
    }

    private var darkThemeAccentKeyBorderColor: Color {
        darkThemeReferenceAccentColor.opacity(0.88)
    }
}

enum SuggestionRolodexVisualPhase: Equatable {
    case idle
    case scrolling
    case selecting
    case selected
}

struct HWCKeyboardRolodexVisualTiming {
    static let selectedFlashDuration: TimeInterval = 0.12
}

final class KeyboardViewModel: ObservableObject {
    let suggestionContentInvalidation = KeyboardSuggestionContentInvalidation()
    @Published var isExpanded = false
    @Published var expansionRevealStage = 0
    @Published var darkThemeBottomControlsExpanded = false
    @Published var isSymbolKeyboard = true
    @Published var activeSymbolSurface: KeyboardRowSurface = .symbols1
    @Published var activeCustomLayerID: UUID?
    @Published private(set) var edgeSwipeOffset: CGFloat = 0
    @Published private(set) var edgeSwipeTitle: String?
    @Published private(set) var isEdgeSwipeActive = false
    private(set) var isEdgeSwipeAnimating = false
    private var edgeSwipeGeneration: UInt64 = 0
    private var edgeSwipeWorkItem: DispatchWorkItem?

    @Published var isAutoCapsActive = false
    @Published var isAutoCapsSuppressed = false
    private var softwareTextInsertionDepth = 0
    private var capsPrimeConsumptionPending = false
    private var automaticCapsSuppressionPending = false
    private var automaticCapsSessionGeneration: UInt64?
    @Published var isCapsPrimed = false
    @Published var isCapsLocked = false
    @Published var isHardwareShiftHeld = false
    @Published var isHardwareCapsLocked = false
    @Published var showsNextKeyboardKey = true
    @Published var returnKeyTitle = "return"
    @Published var settings = KeyboardSettingsSnapshot.default
    private var nextHoldChoiceIndexByKeyID: [UUID: Int] = [:]
    @Published var hostKeyboardAppearance: UIKeyboardAppearance = .default
    @Published var hostUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
    @Published var suggestionRailReserved = false
    /// Authoritative keyboard height resolved by the view controller. The SwiftUI root lays its
    /// content out at this height (bottom-anchored) instead of the transient GeometryReader size,
    /// so the keyboard never mis-lays-out (rail detaching from keys) during the launch slide-up.
    @Published var hostKeyboardHeight: CGFloat = 0
    @Published private(set) var isSemiFoldActive = false
    @Published private(set) var semiFoldAvailable = false
    @Published private(set) var semiFoldGap: CGFloat = 44
    private(set) var semiFoldGestureClaimed = false
    @Published private(set) var semiFoldSuppressionGeneration = 0
    private var automaticSemiFoldActive = false
    private var manualSplitOverride: Bool?

    func updateSemiFoldCapability(available: Bool, gap: CGFloat, automaticallySplit: Bool = false) {
        if semiFoldAvailable != available { semiFoldAvailable = available }
        if abs(semiFoldGap - gap) > 1 { semiFoldGap = gap }
        let automatic = available && automaticallySplit
        if automaticSemiFoldActive != automatic {
            automaticSemiFoldActive = automatic
            // A new fold posture resumes automatic behavior after a manual split or join.
            manualSplitOverride = nil
        }
        updateSplitLayout()
    }

    private func updateSplitLayout() {
        if !settings.semiFoldEnabled { manualSplitOverride = nil }
        let active = manualSplitOverride ?? automaticSemiFoldActive
        if isSemiFoldActive != active { isSemiFoldActive = active }
    }

    func beginSemiFoldGesture() {
        semiFoldSuppressionGeneration += 1
        semiFoldGestureClaimed = true
        cancelEdgeSwipe()
        dismissSuggestionRolodex()
    }

    func finishSemiFoldGesture(commit: Bool, joining: Bool) {
        if commit, settings.semiFoldEnabled {
            manualSplitOverride = !joining
            updateSplitLayout()
        }
        let generation = semiFoldSuppressionGeneration
        // SwiftUI must finish both cancelled key touches before another touch can commit.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.semiFoldSuppressionGeneration == generation else { return }
            self.semiFoldGestureClaimed = false
        }
    }
    var suggestionStripItems = [KeyboardSuggestionItem]()
    var suggestionRolodexLanes = SuggestionRolodexLane.lanes(from: [])
    private(set) var suggestionRailPlacements = [SuggestionRailPlacement]()
    private(set) var suggestionStripSlots = [KeyboardSuggestionItem?]()
    #if DEBUG
    private(set) var suggestionSpatialLayoutRebuildCount = 0
    #endif
    @Published var activeSuggestionRolodexLaneID: Int?
    @Published private var activeSuggestionRolodexSelectedIndexes = [Int: Int]()
    @Published var suggestionRolodexDragOffset: CGFloat = 0
    @Published private(set) var suggestionRolodexVisualPhase: SuggestionRolodexVisualPhase = .idle
    @Published var suggestionSwipePreviewColumn: Int? {
        didSet {
            if oldValue != nil && suggestionSwipePreviewColumn == nil {
                suggestionInteractionEndedHandler?()
            }
        }
    }
    @Published private(set) var isHoldSwipeOverrideActive = false
    private var holdSwipeOverrideActive = false
    private var suppressLowerSuggestionSwipeForHold = false
    @Published var isClipboardPanelPresented = false
    @Published var clipboardPanelSnippets = [HWKClipboardSnippet]()
    @Published var clipboardPanelStatusText: String?
    @Published var isFullAccessAvailable = false
    @Published var isQuickInsertRowMinimized = false
    private(set) var shouldSuppressKeyCommitForDirectionalSwipe = false
    private(set) var runtimeLayoutEnabled = true
    private(set) var runtimeKeymap = HWKRuntimeLayoutAdapter().keymap(for: .default)
    private let customLayerAuthorization: (UUID, KeyboardKeymap) -> Bool

    init(
        customLayerAuthorization: @escaping (UUID, KeyboardKeymap) -> Bool = { id, keymap in
            HWCAdditionalLayerEntitlementPolicy.canAccessLayer(id: id, in: keymap)
        }
    ) {
        self.customLayerAuthorization = customLayerAuthorization
    }

    private var expandedPersistenceMode: ExpandedPersistenceMode = .collapsed
    private var pendingMenuLatchWorkItem: DispatchWorkItem?
    private var suggestionRolodexDragStep = 0
    private var suggestionRolodexSelectedFlashWorkItem: DispatchWorkItem?
    private var suggestionRolodexLastDragTranslation: CGFloat?
    private var suggestionRolodexTouchExceededTapSlop = false
    private var suggestionRolodexRequiresFreshTap = false
    private var suggestionRolodexChipTextFrames = [Int: CGRect]()
    private var deleteHoldPreservesExpandedMenu = false
    private var isDeleteHoldActive = false
    private var directionalKeySwipeResetWorkItem: DispatchWorkItem?
    private var suggestionSwipeCommitResetWorkItem: DispatchWorkItem?
    private var suggestionSwipeCommitInFlight = false
    private var pendingLowerSuggestionSwipeColumn: Int?

    var insertTextHandler: ((String) -> Void)?
    var backHandler: (() -> Void)?
    var deleteForwardHandler: (() -> Void)?
    var editMenuActionHandler: ((KeyboardSpecialKeyAction) -> Void)?
    var beginDeleteHoldHandler: ((Bool) -> Void)?
    var performDeleteHoldStepHandler: (() -> Void)?
    var endDeleteHoldHandler: (() -> Void)?
    var advanceToNextKeyboardHandler: (() -> Void)?
    var offsetHandler: ((Int) -> Void)?
    var verticalCursorHandler: ((KeyboardSpecialKeyAction) -> Bool)?
    var insertPairHandler: ((String, String) -> Void)?
    var loadClipboardPanelSnippetsHandler: (() -> [HWKClipboardSnippet])?
    var addClipboardPanelSnippetHandler: (() -> HWKClipboardSnippet?)?
    var updateClipboardPanelSnippetHandler: ((HWKClipboardSnippet) -> HWKClipboardSnippet?)?
    var deleteClipboardPanelSnippetHandler: ((HWKClipboardSnippet) -> Void)?
    var applyClipboardPanelSnippetHandler: ((HWKClipboardSnippet) -> Void)?
    var refreshStateHandler: (() -> Void)?
    var expansionChangedHandler: ((Bool) -> Void)?
    var accessoryLayoutChangedHandler: (() -> Void)?
    var feedbackHandler: (() -> Void)?
    var prepareFeedbackHandler: (() -> Void)?
    var rolodexStepFeedbackHandler: (() -> Void)?
    var applySuggestionHandler: ((KeyboardSuggestionItem) -> Void)?
    var protectedABCTouchOverrideHandler: (() -> Bool)?
    var glideKeyboardLayoutChangedHandler: (([HWKGlideKey]) -> Void)?
    var suggestionRolodexVisibilityChangedHandler: ((Bool) -> Void)?
    var suggestionInteractionEndedHandler: (() -> Void)?
    var openCompanionAppHandler: (() -> Void)?
    var softwareEasterEggKeyHandler: ((HWCEasterEggSequenceDetector.Step) -> HWCEasterEggSequenceDetector.Observation)?

    var visibleSuggestionRailPlacements: [SuggestionRailPlacement] {
        suggestionRailPlacements
    }

    func logicalSuggestionLaneID(forPhysicalLane physicalLane: Int) -> Int? {
        return SuggestionRailLayout.logicalLaneID(
            forPhysicalLane: physicalLane,
            in: visibleSuggestionRailPlacements
        )
    }

    private var suggestionSpatialAnchorKeyRows: [[String]] {
        if let activeCustomLayerID,
           activeCustomLayer?.surface == .letters {
            let customRows = runtimeKeymap.customLayerRows(for: activeCustomLayerID)
                .filter { row in
                    switch row.kind {
                    case .letterTop, .letterMiddle, .letterBottom, .letterMain:
                        return true
                    default:
                        return false
                    }
                }
                .map { row in
                    row.keys.map(\.tap).filter {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                }
                .filter { !$0.isEmpty }
            if !customRows.isEmpty { return customRows }
        }

        return [
            visibleLetterRow(runtimeKeymap.letterTopRow, for: .letterTop),
            visibleLetterRow(runtimeKeymap.letterMiddleRow, for: .letterMiddle),
            visibleLetterRow(runtimeKeymap.letterBottomRow, for: .letterBottom),
        ].filter { !$0.isEmpty }
    }

    private func rebuildSuggestionSpatialLayout() {
        let requestedCount = KeyboardLayoutBounds.clampedSuggestionVisibleWordCount(
            settings.suggestionVisibleWordCount
        )
        let placements = SuggestionRailLayout.placements(
            from: suggestionRolodexLanes,
            rankedSuggestions: suggestionStripItems,
            slotCount: requestedCount,
            keyRows: suggestionSpatialAnchorKeyRows
        )
        suggestionRailPlacements = placements
        suggestionStripSlots = SuggestionRailLayout.physicalSlots(from: placements)
        #if DEBUG
        suggestionSpatialLayoutRebuildCount += 1
        #endif
    }

    private func rebuildSuggestionLanesAndSpatialLayout() {
        suggestionRolodexLanes = SuggestionRolodexLane.lanes(
            from: suggestionStripItems,
            logicLanes: Array(settings.autocorrectLogicLanes.prefix(settings.suggestionVisibleWordCount))
        )
        rebuildSuggestionSpatialLayout()
    }

    private func refreshCachedSuggestionLaneContents() {
        suggestionRailPlacements = suggestionRailPlacements.map { placement in
            guard let lane = suggestionRolodexLanes.first(where: { $0.id == placement.lane.id }) else {
                return placement
            }
            return SuggestionRailPlacement(
                startLane: placement.startLane,
                laneSpan: placement.laneSpan,
                lane: lane
            )
        }
        suggestionStripSlots = SuggestionRailLayout.physicalSlots(from: suggestionRailPlacements)
    }

    func adjacentVisibleSuggestionLaneID(from laneID: Int, offset: Int) -> Int? {
        let laneIDs = visibleSuggestionRailPlacements.map { $0.lane.id }
        guard let index = laneIDs.firstIndex(of: laneID) else { return laneIDs.first }
        let nextIndex = min(max(index + offset, 0), max(laneIDs.count - 1, 0))
        return laneIDs.indices.contains(nextIndex) ? laneIDs[nextIndex] : nil
    }

    var activeSuggestionRolodexLane: SuggestionRolodexLane? {
        guard let activeSuggestionRolodexLaneID else { return nil }
        guard var lane = suggestionRolodexLanes.first(where: { $0.id == activeSuggestionRolodexLaneID }) else {
            return nil
        }

        if let activeIndex = activeSuggestionRolodexSelectedIndexes[activeSuggestionRolodexLaneID],
           lane.items.indices.contains(activeIndex) {
            lane.selectedIndex = activeIndex
        }
        return lane
    }

    var activeSuggestionRolodexChipTextFrame: CGRect? {
        guard let activeSuggestionRolodexLaneID else { return nil }
        return suggestionRolodexChipTextFrames[activeSuggestionRolodexLaneID]
    }

    var shouldIgnoreLowerSuggestionSwipeForHold: Bool {
        isClipboardPanelPresented || holdSwipeOverrideActive || suppressLowerSuggestionSwipeForHold
    }

    var expandedPanelInteractionElevated: Bool {
        isHoldSwipeOverrideActive
    }

    func beginHoldSwipeOverride() {
        guard !isClipboardPanelPresented else { return }
        holdSwipeOverrideActive = true
        isHoldSwipeOverrideActive = true
        suppressLowerSuggestionSwipeForHold = true
        clearLowerSuggestionSwipeForHoldOverride()
    }

    func endHoldSwipeOverride() {
        holdSwipeOverrideActive = false
        isHoldSwipeOverrideActive = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.suppressLowerSuggestionSwipeForHold = false
        }
    }

    func clearLowerSuggestionSwipeForHoldOverride() {
        suggestionSwipePreviewColumn = nil
        pendingLowerSuggestionSwipeColumn = nil
        directionalKeySwipeResetWorkItem?.cancel()
        directionalKeySwipeResetWorkItem = nil
        if isClipboardPanelPresented {
            shouldSuppressKeyCommitForDirectionalSwipe = true
            return
        }
        shouldSuppressKeyCommitForDirectionalSwipe = false
    }

    func updateDirectionalKeySwipeSuppression(translation: CGSize) {
        guard !isClipboardPanelPresented, !isEdgeSwipeActive else {
            shouldSuppressKeyCommitForDirectionalSwipe = true
            return
        }
        let minimumTravel = HWCKeyboardLayoutMetrics.directionalKeySwipeMinimumTravel(for: settings)
        guard max(abs(translation.width), abs(translation.height)) >= minimumTravel else { return }

        beginDirectionalKeySwipeSuppression()
    }

    func beginDirectionalKeySwipeSuppression() {
        directionalKeySwipeResetWorkItem?.cancel()
        directionalKeySwipeResetWorkItem = nil
        guard !isClipboardPanelPresented, !isEdgeSwipeActive else {
            shouldSuppressKeyCommitForDirectionalSwipe = true
            return
        }
        shouldSuppressKeyCommitForDirectionalSwipe = true
        scheduleDirectionalKeySwipeSuppressionExpiry()
    }

    func claimDirectionalGestureSession() {
        directionalKeySwipeResetWorkItem?.cancel()
        directionalKeySwipeResetWorkItem = nil
        shouldSuppressKeyCommitForDirectionalSwipe = true
    }

    func finishDirectionalKeySwipeSuppression() {
        directionalKeySwipeResetWorkItem?.cancel()
        directionalKeySwipeResetWorkItem = nil
        guard !isClipboardPanelPresented, !isEdgeSwipeActive else {
            shouldSuppressKeyCommitForDirectionalSwipe = true
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.shouldSuppressKeyCommitForDirectionalSwipe = false
            self?.directionalKeySwipeResetWorkItem = nil
        }
        directionalKeySwipeResetWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    private func scheduleDirectionalKeySwipeSuppressionExpiry() {
        directionalKeySwipeResetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard self?.isClipboardPanelPresented != true else { return }
            self?.shouldSuppressKeyCommitForDirectionalSwipe = false
            self?.suggestionSwipePreviewColumn = nil
            self?.directionalKeySwipeResetWorkItem = nil
        }
        directionalKeySwipeResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: workItem)
    }

    func updatePendingLowerSuggestionSwipeColumn(_ column: Int?) {
        guard !isClipboardPanelPresented else {
            pendingLowerSuggestionSwipeColumn = nil
            return
        }
        pendingLowerSuggestionSwipeColumn = column
    }

    func commitPendingLowerSuggestionSwipeIfNeeded() -> Bool {
        guard !isClipboardPanelPresented else {
            pendingLowerSuggestionSwipeColumn = nil
            return false
        }
        guard let physicalColumn = pendingLowerSuggestionSwipeColumn,
              suggestionStripSlots.indices.contains(physicalColumn),
              let suggestion = suggestionStripSlots[physicalColumn],
              let laneID = logicalSuggestionLaneID(forPhysicalLane: physicalColumn) else {
            return false
        }

        pendingLowerSuggestionSwipeColumn = nil
        commitSuggestionSwipeIfNeeded(laneID: laneID, fallback: suggestion)
        return true
    }

    func commitLowerSuggestionSwipeFromKey(_ key: String) -> Bool {
        guard !isClipboardPanelPresented else { return false }
        guard settings.suggestionSwipeUpAction != .off else { return false }
        if commitPendingLowerSuggestionSwipeIfNeeded() {
            return true
        }

        guard let physicalLaneID = lowerSuggestionSwipeLaneID(
                for: key,
                slotCount: settings.suggestionVisibleWordCount
              ),
              suggestionStripSlots.indices.contains(physicalLaneID),
              let suggestion = suggestionStripSlots[physicalLaneID],
              let laneID = logicalSuggestionLaneID(forPhysicalLane: physicalLaneID) else {
            return false
        }

        commitSuggestionSwipeIfNeeded(laneID: laneID, fallback: suggestion)
        return true
    }

    private func lowerSuggestionSwipeLaneID(for key: String, slotCount: Int) -> Int? {
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let horizontalPosition: CGFloat
        switch normalized {
        case "q": horizontalPosition = 0.05
        case "w": horizontalPosition = 0.15
        case "e": horizontalPosition = 0.25
        case "r": horizontalPosition = 0.35
        case "t": horizontalPosition = 0.45
        case "y": horizontalPosition = 0.55
        case "u": horizontalPosition = 0.65
        case "i": horizontalPosition = 0.75
        case "o": horizontalPosition = 0.85
        case "p": horizontalPosition = 0.95
        case "a": horizontalPosition = 0.10
        case "s": horizontalPosition = 0.20
        case "d": horizontalPosition = 0.30
        case "f": horizontalPosition = 0.40
        case "g": horizontalPosition = 0.50
        case "h": horizontalPosition = 0.60
        case "j": horizontalPosition = 0.70
        case "k": horizontalPosition = 0.80
        case "l": horizontalPosition = 0.90
        case "z": horizontalPosition = 0.20
        case "x": horizontalPosition = 0.30
        case "c": horizontalPosition = 0.40
        case "v": horizontalPosition = 0.50
        case "b": horizontalPosition = 0.60
        case "n": horizontalPosition = 0.70
        case "m": horizontalPosition = 0.80
        default: return nil
        }
        let count = KeyboardLayoutBounds.clampedSuggestionVisibleWordCount(slotCount)
        return min(Int(horizontalPosition * CGFloat(count)), count - 1)
    }

    func commitSuggestionSwipeIfNeeded(laneID: Int, fallback: KeyboardSuggestionItem) {
        guard !isClipboardPanelPresented else { return }
        guard !suggestionSwipeCommitInFlight else { return }
        suggestionSwipeCommitInFlight = true
        performSuggestionSwipeUp(laneID: laneID, fallback: fallback)
        finishSuggestionSwipeCommitLatch()
    }

    private func finishSuggestionSwipeCommitLatch() {
        suggestionSwipeCommitResetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.suggestionSwipeCommitInFlight = false
            self?.suggestionSwipeCommitResetWorkItem = nil
        }
        suggestionSwipeCommitResetWorkItem = workItem
        DispatchQueue.main.async(execute: workItem)
    }

    func updateSuggestionRolodexChipTextFrames(_ frames: [Int: CGRect]) {
        suggestionRolodexChipTextFrames = frames
    }

    static func suggestionStripSlots(from suggestions: [KeyboardSuggestionItem]) -> [KeyboardSuggestionItem?] {
        let lanes = SuggestionRolodexLane.lanes(from: suggestions)
        let placements = SuggestionRailLayout.placements(
            from: lanes,
            rankedSuggestions: suggestions
        )
        return SuggestionRailLayout.physicalSlots(from: placements)
    }


    var activeExpandedRows: [KeyboardLayoutRow] {
        if let activeCustomLayerID,
           activeCustomLayer?.surface != .mainRow {
            return runtimeKeymap.customLayerRows(for: activeCustomLayerID)
                .filter(Self.isExpandedSurfaceRow)
                .compactMap(Self.runtimeVisibleRow)
        }

        let surface: KeyboardRowSurface = isSymbolKeyboard ? activeSymbolSurface : .letters
        return runtimeKeymap.rows(surface: surface, holdLayer: false)
            .filter(Self.isExpandedSurfaceRow)
            .compactMap(Self.runtimeVisibleRow)
    }

    private static func isExpandedSurfaceRow(_ row: KeyboardLayoutRow) -> Bool {
        switch row.kind {
        case .symbolTop, .symbolMiddle, .symbolBottom, .symbolMain,
             .letterTop, .letterMiddle, .letterBottom, .letterMain:
            return true
        default:
            return false
        }
    }

    private static func runtimeVisibleRow(_ row: KeyboardLayoutRow) -> KeyboardLayoutRow? {
        var nextRow = row
        nextRow.keys = row.keys.filter { key in
            !key.tap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return nextRow.keys.isEmpty ? nil : nextRow
    }

    private func values(for kind: KeyboardRowKind, surface: KeyboardRowSurface) -> [String] {
        runtimeKeymap.rows(surface: surface, holdLayer: false)
            .first(where: { $0.kind == kind })?
            .keys
            .map(\.tap)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? []
    }

    func canonicalLetterValue(
        for row: HWCKeyboardRowKind,
        index: Int
    ) -> String? {
        guard !isSymbolKeyboard else { return nil }

        let values: [String]
        switch row {
        case .letterTop:
            values = visibleLetterRow(runtimeKeymap.letterTopRow, for: row)
        case .letterMiddle:
            values = visibleLetterRow(runtimeKeymap.letterMiddleRow, for: row)
        case .letterBottom:
            values = visibleLetterRow(runtimeKeymap.letterBottomRow, for: row)
        default:
            return nil
        }

        guard values.indices.contains(index) else { return nil }
        return values[index]
    }

    var topRow: [String] {
        if isSymbolKeyboard {
            return values(for: .symbolTop, surface: activeSymbolSurface)
        }
        return displayedLetterRow(runtimeKeymap.letterTopRow, for: .letterTop)
    }

    var middleRow: [String] {
        if isSymbolKeyboard {
            return values(for: .symbolMiddle, surface: activeSymbolSurface)
        }
        return displayedLetterRow(runtimeKeymap.letterMiddleRow, for: .letterMiddle)
    }

    var bottomRow: [String] {
        if isSymbolKeyboard {
            return values(for: .symbolBottom, surface: activeSymbolSurface)
        }
        return displayedLetterRow(runtimeKeymap.letterBottomRow, for: .letterBottom)
    }

    var toolbarValues: [String] {
        if let row = activeMainRowCustomLayerToolbarRow {
            return normalizedRow(row.keys.map(\.tap), for: .toolbar)
        }
        return normalizedRow(runtimeKeymap.toolbarRow, for: .toolbar)
    }

    var quickInsertValues: [String] {
        normalizedRow(runtimeKeymap.quickInsertRow, for: .quickInsert)
    }

    var symbolUtilityValues: [String] {
        if activeCustomLayer?.surface == .symbols1,
           let customValues = activeCustomLayerUtilityValues {
            return normalizedRow(Array(customValues.prefix(activeCustomLayerUtilitySplitCount)), for: .symbolUtility)
        }
        return normalizedRow(runtimeKeymap.symbolUtilityRow, for: .symbolUtility)
    }

    var trailingUtilityValues: [String] {
        normalizedRow(runtimeKeymap.trailingUtilityRow, for: .trailingUtility)
    }

    var expandedTrailingUtilityValues: [String] {
        if activeCustomLayer?.surface == .symbols1,
           let customValues = activeCustomLayerUtilityValues {
            return normalizedRow(
                Array(customValues.dropFirst(activeCustomLayerUtilitySplitCount)),
                for: .expandedTrailingUtility
            )
        }
        return normalizedRow(runtimeKeymap.expandedTrailingUtilityRow, for: .expandedTrailingUtility)
    }

    var expandedLetterTrailingUtilityValues: [String] {
        if activeCustomLayer?.surface == .letters,
           let customValues = activeCustomLayerUtilityValues {
            return normalizedRow(
                Array(customValues.dropFirst(activeCustomLayerUtilitySplitCount)),
                for: .expandedLetterTrailingUtility
            )
        }
        return normalizedRow(runtimeKeymap.expandedLetterTrailingUtilityRow, for: .expandedLetterTrailingUtility)
    }

    var activeExpandedTrailingUtilityValues: [String] {
        if activeCustomLayer?.surface == .symbols1 {
            return expandedTrailingUtilityValues
        }
        if activeCustomLayer?.surface == .letters {
            return expandedLetterTrailingUtilityValues
        }
        return isSymbolKeyboard ? expandedTrailingUtilityValues : expandedLetterTrailingUtilityValues
    }

    fileprivate var activeExpandedTrailingUtilityRow: HWCKeyboardRowKind {
        if activeCustomLayer?.surface == .symbols1 {
            return .expandedTrailingUtility
        }
        if activeCustomLayer?.surface == .letters {
            return .expandedLetterTrailingUtility
        }
        return isSymbolKeyboard ? HWCKeyboardRowKind.expandedTrailingUtility : HWCKeyboardRowKind.expandedLetterTrailingUtility
    }

    var letterUtilityValues: [String] {
        if activeCustomLayer?.surface == .letters,
           let customValues = activeCustomLayerUtilityValues {
            return normalizedRow(Array(customValues.prefix(activeCustomLayerUtilitySplitCount)), for: .letterUtility)
        }
        return normalizedRow(runtimeKeymap.letterUtilityRow, for: .letterUtility)
    }

    var letterBottomLeadingValue: String {
        normalizedRow(runtimeKeymap.letterBottomLeadingRow, for: .letterBottomLeading).first ?? ""
    }

    private var activeCustomLayerUtilityValues: [String]? {
        guard let activeCustomLayerID,
              let row = runtimeKeymap.customLayerRows(for: activeCustomLayerID).first(where: {
                  $0.kind == .symbolUtility || $0.kind == .letterUtility
              }) else {
            return nil
        }
        return row.keys.map(\.tap)
    }

    private var activeCustomLayer: KeyboardCustomLayer? {
        guard let activeCustomLayerID else { return nil }
        return runtimeKeymap.customLayer(for: activeCustomLayerID)
    }

    private var activeMainRowCustomLayerToolbarRow: KeyboardLayoutRow? {
        guard activeCustomLayer?.surface == .mainRow,
              let activeCustomLayerID else { return nil }
        return runtimeKeymap.customLayerRows(for: activeCustomLayerID).first { $0.kind == .toolbar }
    }

    private var activeCustomLayerUtilitySplitCount: Int {
        switch activeCustomLayer?.surface {
        case .letters:
            return normalizedRow(runtimeKeymap.letterUtilityRow, for: .letterUtility).count
        case .symbols1, .symbols2:
            return normalizedRow(runtimeKeymap.symbolUtilityRow, for: .symbolUtility).count
        case .mainRow, .none:
            return 0
        }
    }

    fileprivate func holdValue(for row: HWCKeyboardRowKind, index: Int) -> String? {
        let values: [String]

        switch row {
        case .quickInsert:
            values = normalizedRow(runtimeKeymap.holdQuickInsertRow, for: .holdQuickInsert)
        case .toolbar:
            values = normalizedRow(runtimeKeymap.holdToolbarRow, for: .holdToolbar)
        case .symbolTop:
            values = normalizedRow(runtimeKeymap.holdSymbolTopRow, for: .holdSymbolTop)
        case .symbolMiddle:
            values = normalizedRow(runtimeKeymap.holdSymbolMiddleRow, for: .holdSymbolMiddle)
        case .symbolBottom:
            values = normalizedRow(runtimeKeymap.holdSymbolBottomRow, for: .holdSymbolBottom)
        case .symbolUtility:
            values = []
        case .letterTop:
            values = normalizedRow(runtimeKeymap.holdLetterTopRow, for: .holdLetterTop)
        case .letterMiddle:
            values = normalizedRow(runtimeKeymap.holdLetterMiddleRow, for: .holdLetterMiddle)
        case .letterBottom:
            values = normalizedRow(runtimeKeymap.holdLetterBottomRow, for: .holdLetterBottom)
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility,
             .letterUtility, .letterBottomLeading:
            values = []
        case .holdQuickInsert, .holdToolbar, .holdSymbolTop, .holdSymbolMiddle, .holdSymbolBottom,
             .holdLetterTop, .holdLetterMiddle, .holdLetterBottom:
            values = []
        }

        guard values.indices.contains(index) else { return nil }
        let value = values[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var isCapsShiftActive: Bool {
        isCapsLocked || isHardwareCapsLocked
            || (isCapsPrimed && !capsPrimeConsumptionPending)
            || isHardwareShiftHeld
            || effectiveAutomaticCapsActive
    }

    fileprivate var capsIndicatorState: ToolbarIndicatorState {
        if isCapsLocked || isHardwareCapsLocked {
            return .latched
        }

        return ((isCapsPrimed && !capsPrimeConsumptionPending)
            || isHardwareShiftHeld
            || effectiveAutomaticCapsActive) ? .primed : .off
    }

    fileprivate var menuIndicatorState: ToolbarIndicatorState {
        guard isExpanded else { return .off }

        switch expandedPersistenceMode {
        case .collapsed:
            return .off
        case .oneShot:
            return .off
        case .awaitingSecondAction:
            return .off
        case .latched:
            return .latched
        }
    }

    private func assignIfChanged<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<KeyboardViewModel, Value>,
        _ value: Value
    ) {
        guard self[keyPath: keyPath] != value else { return }
        self[keyPath: keyPath] = value
    }

    func applyLaunchVisualSettings(
        isSymbolKeyboard: Bool,
        showsNextKeyboardKey: Bool,
        returnKeyTitle: String,
        automaticCapsActive: Bool,
        settings: KeyboardSettingsSnapshot,
        isRuntimeLayoutEnabled: Bool
    ) {
        assignIfChanged(\.showsNextKeyboardKey, showsNextKeyboardKey)
        assignIfChanged(\.returnKeyTitle, returnKeyTitle)
        if self.settings != settings || runtimeLayoutEnabled != isRuntimeLayoutEnabled {
            cancelEdgeSwipe()
            runtimeKeymap = HWKRuntimeLayoutAdapter().keymap(
                for: settings,
                isRuntimeLayoutEnabled: isRuntimeLayoutEnabled
            )
            self.settings = settings
            updateSplitLayout()
            runtimeLayoutEnabled = isRuntimeLayoutEnabled
            if let activeCustomLayerID,
               runtimeKeymap.customLayer(for: activeCustomLayerID) == nil {
                self.activeCustomLayerID = nil
            }
            rebuildSuggestionLanesAndSpatialLayout()
        }
        if let activeCustomLayerID,
           !isCustomLayerAuthorized(activeCustomLayerID) {
            self.activeCustomLayerID = nil
        }
        assignIfChanged(\.isSymbolKeyboard, resolvedSymbolKeyboardState(for: isSymbolKeyboard))
        assignIfChanged(\.isAutoCapsActive, automaticCapsActive)
        if settings.hideKeyboardEnabled || !settings.showQuickInsertRow || !settings.showQuickInsertHandle {
            assignIfChanged(\.isQuickInsertRowMinimized, false)
        }
    }

    private func resolvedSymbolKeyboardState(for requestedState: Bool) -> Bool {
        switch activeCustomLayer?.surface {
        case .symbols1, .symbols2:
            return true
        case .letters:
            return false
        case .mainRow, .none:
            return requestedState
        }
    }

    func refresh(
        isSymbolKeyboard: Bool,
        showsNextKeyboardKey: Bool,
        returnKeyTitle: String,
        automaticCapsActive: Bool,
        automaticCapsSessionGeneration: UInt64 = 0,
        settings: KeyboardSettingsSnapshot,
        isRuntimeLayoutEnabled: Bool
    ) {
        if settings.showsSuggestionRail {
            assignIfChanged(\.suggestionRailReserved, true)
        } else {
            assignIfChanged(\.suggestionRailReserved, false)
        }
        assignIfChanged(\.showsNextKeyboardKey, showsNextKeyboardKey)
        assignIfChanged(\.returnKeyTitle, returnKeyTitle)
        if self.settings != settings || runtimeLayoutEnabled != isRuntimeLayoutEnabled {
            cancelEdgeSwipe()
            runtimeKeymap = HWKRuntimeLayoutAdapter().keymap(
                for: settings,
                isRuntimeLayoutEnabled: isRuntimeLayoutEnabled
            )
            self.settings = settings
            updateSplitLayout()
            runtimeLayoutEnabled = isRuntimeLayoutEnabled
            if let activeCustomLayerID,
               runtimeKeymap.customLayer(for: activeCustomLayerID) == nil {
                self.activeCustomLayerID = nil
            }
            rebuildSuggestionLanesAndSpatialLayout()
        }
        if let activeCustomLayerID,
           !isCustomLayerAuthorized(activeCustomLayerID) {
            self.activeCustomLayerID = nil
        }
        assignIfChanged(\.isSymbolKeyboard, resolvedSymbolKeyboardState(for: isSymbolKeyboard))
        if self.automaticCapsSessionGeneration != automaticCapsSessionGeneration {
            self.automaticCapsSessionGeneration = automaticCapsSessionGeneration
            assignIfChanged(\.isAutoCapsSuppressed, false)
        }
        assignIfChanged(\.isAutoCapsActive, automaticCapsActive)

        if settings.hideKeyboardEnabled || !settings.showQuickInsertRow || !settings.showQuickInsertHandle {
            assignIfChanged(\.isQuickInsertRowMinimized, false)
        }

        if !settings.showsSuggestionRail {
            assignIfChanged(\.suggestionRailReserved, false)
            if !suggestionStripItems.isEmpty || activeSuggestionRolodexLaneID != nil {
                clearSuggestionStripItems()
            }
        }

        if isSymbolKeyboard {
            assignIfChanged(\.isCapsPrimed, false)
        }

    }

    func beginLocalAutomaticCapsSession(generation: UInt64) {
        automaticCapsSessionGeneration = generation
        assignIfChanged(\.isAutoCapsSuppressed, false)
        assignIfChanged(\.isAutoCapsActive, true)
    }

    func toggleExpanded() {
        performFeedback()
        isExpanded ? collapseExpanded() : expandExpanded(using: .latched)
    }

    func toggleSymbols() {
        performFeedback()
        if activeCustomLayerID != nil {
            activeCustomLayerID = nil
            rebuildSuggestionSpatialLayout()
        }
        isSymbolKeyboard.toggle()
        if isSymbolKeyboard {
            activeSymbolSurface = .symbols1
            isCapsPrimed = false
        }
        refreshStateHandler?()
    }

    func toggleSymbolPage() {
        guard isSymbolKeyboard else { return }
        performFeedback()
        if activeCustomLayerID != nil {
            activeCustomLayerID = nil
            rebuildSuggestionSpatialLayout()
        }
        activeSymbolSurface = activeSymbolSurface == .symbols2 ? .symbols1 : .symbols2
        refreshStateHandler?()
    }

    func specialActionLegend(for action: KeyboardSpecialKeyAction) -> String {
        guard action == .toggleSymbolPage else { return action.legendSymbol }
        return activeSymbolSurface == .symbols2 ? "123" : "#+="
    }

    func insertNextHoldChoice(_ choices: [String], keyID: UUID, from row: HWCKeyboardRowKind) {
        let normalized = choices.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        let index = nextHoldChoiceIndexByKeyID[keyID, default: 0] % normalized.count
        nextHoldChoiceIndexByKeyID[keyID] = (index + 1) % normalized.count
        insertHoldKey(normalized[index], from: row)
    }

    func toggleCapsLock() {
        guard !isSymbolKeyboard else { return }
        performFeedback()
        isCapsLocked.toggle()
        isCapsPrimed = false
        isAutoCapsSuppressed = false
        refreshStateHandler?()
    }

    func tapCapsKey() {
        guard !isSymbolKeyboard else { return }

        performFeedback()

        if isCapsLocked {
            isCapsLocked = false
            isCapsPrimed = false
            isAutoCapsSuppressed = false
        } else if effectiveAutomaticCapsActive {
            isCapsPrimed = false
            isAutoCapsSuppressed = true
        } else if isCapsPrimed {
            isCapsPrimed = false
        } else {
            isAutoCapsSuppressed = false
            isCapsPrimed.toggle()
        }

        refreshStateHandler?()
    }

    func holdCapsKey() {
        guard !isSymbolKeyboard else { return }
        guard settings.capsHoldToLockEnabled else {
            tapCapsKey()
            return
        }

        guard !isCapsLocked else { return }

        performFeedback()
        isCapsPrimed = false
        isAutoCapsSuppressed = false
        isCapsLocked = true
        refreshStateHandler?()
    }

    func setHardwareShiftHeld(_ isHeld: Bool, shouldProvideFeedback: Bool) {
        guard isHardwareShiftHeld != isHeld else { return }

        isHardwareShiftHeld = isHeld
        refreshStateHandler?()
        performHardwareModifierFeedbackIfNeeded(shouldProvideFeedback)
    }

    func primeHardwareShiftForNextInput(shouldProvideFeedback: Bool) {
        guard !isSymbolKeyboard else { return }

        isHardwareShiftHeld = false
        isCapsPrimed = true
        isAutoCapsSuppressed = false
        refreshStateHandler?()
        performHardwareModifierFeedbackIfNeeded(shouldProvideFeedback)
    }

    func setHardwareCapsLocked(_ isLocked: Bool, shouldProvideFeedback: Bool) {
        guard isHardwareCapsLocked != isLocked else { return }

        isHardwareCapsLocked = isLocked
        isCapsPrimed = false
        isAutoCapsSuppressed = false
        refreshStateHandler?()
        performHardwareModifierFeedbackIfNeeded(shouldProvideFeedback)
    }

    func clearHardwareModifierState() {
        guard isHardwareShiftHeld || isHardwareCapsLocked else { return }
        isHardwareShiftHeld = false
        isHardwareCapsLocked = false
        refreshStateHandler?()
    }

    func consumeSoftwareCapsAfterHardwareTextInput(_ text: String) {
        guard shouldConsumeSoftwareCapsAfterHardwareTextInput(text) else { return }

        var didChange = false
        if isCapsPrimed {
            isCapsPrimed = false
            didChange = true
        }
        if effectiveAutomaticCapsActive {
            isAutoCapsSuppressed = true
            didChange = true
        }

        guard didChange else { return }
        refreshStateHandler?()
    }

    func tapExpandedMenuKey() {
        performFeedback()
        if isExpanded {
            collapseExpanded()
            return
        }

        expandExpanded(using: .oneShot)
    }

    func holdExpandedMenuKey() {
        guard settings.menuHoldToLatchEnabled else {
            tapExpandedMenuKey()
            return
        }

        performFeedback()

        if isExpanded {
            expandedPersistenceMode = .latched
            cancelPendingMenuLatch()
            refreshStateHandler?()
            return
        }

        expandExpanded(using: .latched)
    }

    func applyStartupExpandedState(_ isExpanded: Bool) {
        cancelPendingMenuLatch()
        self.isExpanded = isExpanded
        expandedPersistenceMode = isExpanded ? .oneShot : .collapsed
    }

    fileprivate func performKey(
        _ key: String,
        from row: HWCKeyboardRowKind,
        shouldPlayFeedback: Bool = true
    ) {
        guard !key.isEmpty else { return }
        guard !isClipboardPanelPresented else { return }
        _ = dismissSuggestionRolodexForFreshInput()
        if let layerID = KeyboardCustomLayer.id(fromStorageToken: key) {
            switchToCustomLayer(layerID)
            return
        }
        if let specialAction = KeyboardSpecialKeyAction.resolved(from: key) {
            let observation = observeSoftwareEasterEggStep(for: specialAction)
            if shouldConsumeSoftwareEasterEggObservation(observation) {
                return
            }
            performSpecialAction(specialAction, from: row)
            return
        }

        let observation = observeSoftwareEasterEggStep(forText: key)
        if shouldConsumeSoftwareEasterEggObservation(observation) {
            return
        }
        insertRemappedText(key, from: row, shouldPlayFeedback: shouldPlayFeedback)
    }

    func canActivateEdgeDestination(_ destination: KeyboardEdgeSwipeDestination, rowMode: Bool) -> Bool {
        guard destination != .off, !settings.hideKeyboardEnabled,
              destination.isAvailable(in: runtimeKeymap, rowMode: rowMode) else { return false }
        if let id = destination.customLayerID { return isCustomLayerAuthorized(id) }
        return true
    }

    @discardableResult
    func activateEdgeDestination(_ destination: KeyboardEdgeSwipeDestination, rowMode: Bool) -> Bool {
        guard canActivateEdgeDestination(destination, rowMode: rowMode) else { return false }
        if destination == .clipboard {
            presentClipboardPanel()
            return true
        }
        dismissSuggestionRolodex()
        performFeedback()
        let surface: KeyboardRowSurface
        if let id = destination.customLayerID, let layer = runtimeKeymap.customLayer(for: id) {
            activeCustomLayerID = id
            surface = layer.surface
        } else {
            guard let builtIn = KeyboardRowSurface(rawValue: destination.rawValue) else { return false }
            activeCustomLayerID = nil
            surface = builtIn
        }
        switch surface {
        case .mainRow:
            collapseExpanded(clearsCustomLayer: false)
        case .letters:
            isSymbolKeyboard = false
            // Preserve latched/one-shot state when changing an expanded layer.
            if !isExpanded { expandExpanded(using: .latched) }
        case .symbols1, .symbols2:
            activeSymbolSurface = surface
            isSymbolKeyboard = true
            isCapsPrimed = false
            if !isExpanded { expandExpanded(using: .latched) }
        }
        rebuildSuggestionSpatialLayout()
        refreshStateHandler?()
        return true
    }

    func previewEdgeSwipe(_ session: KeyboardEdgeSwipeSession, width: CGFloat) {
        guard !isEdgeSwipeAnimating else { return }
        isEdgeSwipeActive = true
        claimDirectionalGestureSession()
        edgeSwipeTitle = session.destination.title(in: runtimeKeymap)
        edgeSwipeOffset = session.edge.sign * min(max(0, session.translation.width * session.edge.sign), max(0, width))
    }

    func finishEdgeSwipe(_ session: KeyboardEdgeSwipeSession, width: CGFloat, reduceMotion: Bool) {
        guard session.shouldCommit,
              canActivateEdgeDestination(session.destination, rowMode: session.rowMode) else {
            cancelEdgeSwipe()
            return
        }
        guard !isEdgeSwipeAnimating else { return }
        if reduceMotion || session.destination == .clipboard {
            cancelEdgeSwipe()
            _ = activateEdgeDestination(session.destination, rowMode: session.rowMode)
            return
        }
        isEdgeSwipeActive = true
        isEdgeSwipeAnimating = true
        edgeSwipeGeneration &+= 1
        let generation = edgeSwipeGeneration
        withAnimation(.easeOut(duration: 0.10)) {
            edgeSwipeOffset = session.edge.sign * width
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.edgeSwipeGeneration == generation else { return }
            guard self.activateEdgeDestination(session.destination, rowMode: session.rowMode) else {
                self.cancelEdgeSwipe()
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { self.edgeSwipeOffset = -session.edge.sign * width }
            // Let the new layer lay out offscreen before bringing the same tree in.
            let incoming = DispatchWorkItem { [weak self] in
                guard let self, self.edgeSwipeGeneration == generation else { return }
                withAnimation(.easeOut(duration: 0.14)) { self.edgeSwipeOffset = 0 }
                let completion = DispatchWorkItem { [weak self] in
                    guard let self, self.edgeSwipeGeneration == generation else { return }
                    self.cancelEdgeSwipe()
                }
                self.edgeSwipeWorkItem = completion
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: completion)
            }
            self.edgeSwipeWorkItem = incoming
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.016, execute: incoming)
        }
        edgeSwipeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: work)
    }

    func cancelEdgeSwipe() {
        guard isEdgeSwipeActive || edgeSwipeWorkItem != nil else { return }
        edgeSwipeGeneration &+= 1
        edgeSwipeWorkItem?.cancel()
        edgeSwipeWorkItem = nil
        isEdgeSwipeAnimating = false
        isEdgeSwipeActive = false
        edgeSwipeTitle = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { edgeSwipeOffset = 0 }
        finishDirectionalKeySwipeSuppression()
    }

    private func switchToCustomLayer(_ id: UUID) {
        guard isCustomLayerAuthorized(id),
              let layer = runtimeKeymap.customLayer(for: id) else { return }
        performFeedback()
        activeCustomLayerID = id
        rebuildSuggestionSpatialLayout()

        switch layer.surface {
        case .mainRow:
            collapseExpanded(clearsCustomLayer: false)
        case .symbols1, .symbols2:
            activeSymbolSurface = layer.surface
            isSymbolKeyboard = true
            isCapsPrimed = false
            expandExpanded(using: .oneShot)
        case .letters:
            isSymbolKeyboard = false
            expandExpanded(using: .oneShot)
        }

        refreshStateHandler?()
    }

    fileprivate func isCustomLayerAuthorized(_ id: UUID) -> Bool {
        customLayerAuthorization(id, runtimeKeymap)
    }

    private func observeSoftwareEasterEggStep(for action: KeyboardSpecialKeyAction) -> HWCEasterEggSequenceDetector.Observation {
        switch action {
        case .moveLeft:
            return softwareEasterEggKeyHandler?(.left) ?? .ignored
        case .moveRight:
            return softwareEasterEggKeyHandler?(.right) ?? .ignored
        case .space:
            return softwareEasterEggKeyHandler?(.space) ?? .ignored
        default:
            return .ignored
        }
    }

    private func observeSoftwareEasterEggStep(forText text: String) -> HWCEasterEggSequenceDetector.Observation {
        switch text {
        case "/":
            return softwareEasterEggKeyHandler?(.slash) ?? .ignored
        case "\\":
            return softwareEasterEggKeyHandler?(.backslash) ?? .ignored
        default:
            return .ignored
        }
    }

    private func shouldConsumeSoftwareEasterEggObservation(_ observation: HWCEasterEggSequenceDetector.Observation) -> Bool {
        switch observation {
        case .triggered:
            return true
        case .matched(let progress):
            return progress >= 5
        case .ignored:
            return false
        }
    }

    fileprivate func insertHoldKey(_ key: String, from row: HWCKeyboardRowKind) {
        if let specialAction = KeyboardSpecialKeyAction.resolved(from: key) {
            switch specialAction {
            case .shift:
                holdShiftKey(from: row)
            case .menu:
                holdExpandedMenuKey()
            default:
                performKey(key, from: row)
            }
            return
        }

        performKey(key, from: row)
    }

    func insertRelayKey(_ key: String) {
        performKey(key, from: isSymbolKeyboard ? .symbolTop : .letterTop)
    }

    private func performSpecialAction(_ action: KeyboardSpecialKeyAction, from row: HWCKeyboardRowKind) {
        switch action {
        case .enter:
            insertRemappedText("\n", from: row)
        case .shift:
            tapShiftKey(from: row)
        case .toggleLayer:
            toggleSymbols()
        case .toggleSymbolPage:
            toggleSymbolPage()
        case .space:
            insertRemappedText(" ", from: row)
        case .tab:
            insertRemappedText("\t", from: row)
        case .undo:
            performFeedback()
            editMenuActionHandler?(action)
        case .cut:
            performFeedback()
            editMenuActionHandler?(action)
        case .copy:
            performFeedback()
            editMenuActionHandler?(action)
        case .paste:
            performFeedback()
            editMenuActionHandler?(action)
        case .clipboard:
            performFeedback()
            presentClipboardPanel()
        case .redo:
            performFeedback()
            editMenuActionHandler?(action)
        case .deleteBackward:
            preservesExpandedMenu(for: row) ? backKeepingMenu() : back()
        case .deleteForward:
            preservesExpandedMenu(for: row) ? deleteForwardPreservingExpandedMenu() : deleteForward()
        case .moveLeft:
            preservesExpandedMenu(for: row) ? offsetKeepingMenu(by: -1) : offset(by: -1)
        case .moveRight:
            preservesExpandedMenu(for: row) ? offsetKeepingMenu(by: 1) : offset(by: 1)
        case .moveUp, .moveDown:
            moveCursorVertically(
                action,
                keepingExpandedMenu: preservesExpandedMenu(for: row)
            )
        case .menu:
            tapExpandedMenuKey()
        case .nextKeyboard:
            advanceToNextKeyboard()
        }
    }

    fileprivate func tapShiftKey(from row: HWCKeyboardRowKind) {
        if isSymbolKeyboard {
            toggleSymbols()
            return
        }

        tapCapsKey()
    }

    fileprivate func holdShiftKey(from row: HWCKeyboardRowKind) {
        if isSymbolKeyboard {
            toggleSymbols()
            return
        }

        holdCapsKey()
    }

    private func insertRemappedText(
        _ text: String,
        from row: HWCKeyboardRowKind,
        shouldPlayFeedback: Bool = true
    ) {
        let resolvedText = shouldApplyCaps(to: row) && isCapsShiftActive ? text.uppercased() : text

        if row == .toolbar {
            insertToolbarValue(resolvedText, shouldPlayFeedback: shouldPlayFeedback)
        } else if preservesExpandedMenu(for: row) {
            insertTextPreservingExpandedMenu(resolvedText, shouldPlayFeedback: shouldPlayFeedback)
        } else {
            insertText(resolvedText, shouldPlayFeedback: shouldPlayFeedback)
        }
    }

    private func shouldApplyCaps(to row: HWCKeyboardRowKind) -> Bool {
        guard !isSymbolKeyboard else { return false }

        switch row {
        case .letterTop, .letterMiddle, .letterBottom, .letterUtility, .trailingUtility,
             .expandedTrailingUtility, .expandedLetterTrailingUtility, .letterBottomLeading:
            return true
        default:
            return false
        }
    }

    private func preservesExpandedMenu(for row: HWCKeyboardRowKind) -> Bool {
        switch row {
        case .symbolUtility, .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility,
             .letterUtility, .letterBottomLeading:
            return true
        default:
            return false
        }
    }

    func insertToolbarValue(_ value: String, shouldPlayFeedback: Bool = true) {
        guard !value.isEmpty else { return }
        if shouldPlayFeedback { performFeedback() }
        beginSoftwareTextInsertion()
        let didConsumeCaps = consumeSoftwareCapsBeforeInsertion(value)
        insertTextHandler?(value)
        let didConsumePostInput = consumePostInputState(
            insertedText: value,
            consumesCapsPrime: true,
            consumesExpandedMenu: false
        )
        let didPublishCaps = completeSoftwareTextInsertion()
        if didConsumePostInput || didConsumeCaps || didPublishCaps {
            refreshStateHandler?()
        }
    }

    func insertText(_ text: String, shouldPlayFeedback: Bool = true) {
        if shouldPlayFeedback { performFeedback() }
        beginSoftwareTextInsertion()
        let didConsumeCaps = consumeSoftwareCapsBeforeInsertion(text)
        insertTextHandler?(text)
        let didConsumePostInput = consumePostInputState(
            insertedText: text,
            consumesCapsPrime: true,
            consumesExpandedMenu: true
        )
        let didPublishCaps = completeSoftwareTextInsertion()
        if didConsumePostInput || didConsumeCaps || didPublishCaps {
            refreshStateHandler?()
        }
    }

    func insertTextPreservingExpandedMenu(_ text: String, shouldPlayFeedback: Bool = true) {
        if shouldPlayFeedback { performFeedback() }
        beginSoftwareTextInsertion()
        let didConsumeCaps = consumeSoftwareCapsBeforeInsertion(text)
        insertTextHandler?(text)
        let didConsumePostInput = consumePostInputState(
            insertedText: text,
            consumesCapsPrime: true,
            consumesExpandedMenu: false
        )
        let didPublishCaps = completeSoftwareTextInsertion()
        if didConsumePostInput || didConsumeCaps || didPublishCaps {
            refreshStateHandler?()
        }
    }

    func back() {
        performFeedback()
        backHandler?()
        _ = consumeExpandedMenuIfNeeded()
        refreshStateHandler?()
    }

    func backKeepingMenu() {
        performFeedback()
        backHandler?()
        refreshStateHandler?()
    }

    func deleteForward() {
        performFeedback()
        deleteForwardHandler?()
        _ = consumeExpandedMenuIfNeeded()
        refreshStateHandler?()
    }

    func deleteForwardPreservingExpandedMenu() {
        performFeedback()
        deleteForwardHandler?()
        refreshStateHandler?()
    }

    func beginDeleteHold(preservingExpandedMenu: Bool) {
        guard settings.deleteHoldEnabled else { return }

        isDeleteHoldActive = true
        deleteHoldPreservesExpandedMenu = preservingExpandedMenu
        performFeedback()
        beginDeleteHoldHandler?(preservingExpandedMenu)
        refreshStateHandler?()
    }

    func performDeleteHoldStep() {
        guard isDeleteHoldActive else { return }
        performDeleteHoldStepHandler?()
        refreshStateHandler?()
    }

    func endDeleteHold() {
        guard isDeleteHoldActive else { return }

        isDeleteHoldActive = false
        endDeleteHoldHandler?()

        if !deleteHoldPreservesExpandedMenu {
            _ = consumeExpandedMenuIfNeeded()
        }

        deleteHoldPreservesExpandedMenu = false
        refreshStateHandler?()
    }

    func line() {
        insertText("\n")
    }

    func lineKeepingMenu() {
        insertTextPreservingExpandedMenu("\n")
    }

    func advanceToNextKeyboard() {
        performFeedback()
        advanceToNextKeyboardHandler?()
    }

    func offset(by value: Int) {
        performFeedback()
        offsetHandler?(value)
        _ = consumeExpandedMenuIfNeeded()
    }

    func offsetKeepingMenu(by value: Int) {
        performFeedback()
        offsetHandler?(value)
    }

    func moveCursorVertically(
        _ action: KeyboardSpecialKeyAction,
        keepingExpandedMenu: Bool
    ) {
        guard verticalCursorHandler?(action) == true else { return }
        performFeedback()
        if !keepingExpandedMenu {
            _ = consumeExpandedMenuIfNeeded()
        }
    }

    func insertPair(open: String, close: String) {
        performFeedback()
        insertPairHandler?(open, close)
        _ = consumePostInputState(consumesCapsPrime: true, consumesExpandedMenu: true)
        refreshStateHandler?()
    }

    func applySuggestion(_ suggestion: KeyboardSuggestionItem) {
        _ = dismissSuggestionRolodexForFreshInput()
        performFeedback()
        applySuggestionHandler?(suggestion)
        refreshStateHandler?()
    }

    func applyProtectedABCTouchOverrideIfNeeded() -> Bool {
        guard protectedABCTouchOverrideHandler?() == true else { return false }

        performFeedback()
        _ = consumePostInputState(consumesCapsPrime: true, consumesExpandedMenu: true)
        refreshStateHandler?()
        return true
    }

    func setSuggestionStripItems(_ suggestions: [KeyboardSuggestionItem]) {
        let nextLanes = SuggestionRolodexLane.lanes(
            from: suggestions,
            logicLanes: Array(settings.autocorrectLogicLanes.prefix(settings.suggestionVisibleWordCount))
        )
        guard suggestions != suggestionStripItems || nextLanes != suggestionRolodexLanes else {
            return
        }
        suggestionContentInvalidation.invalidate()
        suggestionStripItems = suggestions
        suggestionRolodexLanes = nextLanes
        rebuildSuggestionSpatialLayout()

        if let activeSuggestionRolodexLaneID,
           let activeLane = suggestionRolodexLanes.first(where: { $0.id == activeSuggestionRolodexLaneID }),
           activeLane.selectedItem != nil {
            let activeIndex = activeSuggestionRolodexSelectedIndexes[activeSuggestionRolodexLaneID] ?? activeLane.selectedIndex
            var selectedIndexes = activeSuggestionRolodexSelectedIndexes
            selectedIndexes[activeSuggestionRolodexLaneID] = min(max(activeIndex, 0), max(activeLane.items.count - 1, 0))
            activeSuggestionRolodexSelectedIndexes = selectedIndexes
        } else if activeSuggestionRolodexLaneID != nil {
            dismissSuggestionRolodex()
        }
    }

    func clearSuggestionStripItems() {
        guard !suggestionStripItems.isEmpty ||
            suggestionRolodexLanes.contains(where: { $0.selectedItem != nil }) ||
            activeSuggestionRolodexLaneID != nil ||
            !activeSuggestionRolodexSelectedIndexes.isEmpty else {
            return
        }
        suggestionContentInvalidation.invalidate()
        suggestionStripItems = []
        suggestionRolodexLanes = SuggestionRolodexLane.lanes(
            from: [],
            logicLanes: Array(settings.autocorrectLogicLanes.prefix(settings.suggestionVisibleWordCount))
        )
        rebuildSuggestionSpatialLayout()
        dismissSuggestionRolodex()
    }

    func presentClipboardPanel() {
        dismissSuggestionRolodex()
        suggestionSwipePreviewColumn = nil
        pendingLowerSuggestionSwipeColumn = nil
        holdSwipeOverrideActive = false
        isHoldSwipeOverrideActive = false
        suppressLowerSuggestionSwipeForHold = false
        directionalKeySwipeResetWorkItem?.cancel()
        directionalKeySwipeResetWorkItem = nil
        shouldSuppressKeyCommitForDirectionalSwipe = true
        clipboardPanelStatusText = nil
        refreshClipboardPanelSnippets()
        isClipboardPanelPresented = true
        accessoryLayoutChangedHandler?()
    }

    func dismissClipboardPanel() {
        directionalKeySwipeResetWorkItem?.cancel()
        directionalKeySwipeResetWorkItem = nil
        shouldSuppressKeyCommitForDirectionalSwipe = false
        isClipboardPanelPresented = false
        clipboardPanelStatusText = nil
        accessoryLayoutChangedHandler?()
    }

    func refreshClipboardPanelSnippets() {
        clipboardPanelSnippets = sortedClipboardPanelSnippets(loadClipboardPanelSnippetsHandler?() ?? [])
    }

    func addClipboardPanelSnippet() {
        guard addClipboardPanelSnippetHandler?() != nil else {
            clipboardPanelStatusText = "Clipboard empty"
            refreshClipboardPanelSnippets()
            return
        }

        clipboardPanelStatusText = "Saved"
        refreshClipboardPanelSnippets()
    }

    func updateClipboardPanelSnippet(_ snippet: HWKClipboardSnippet) {
        guard updateClipboardPanelSnippetHandler?(snippet) != nil else {
            clipboardPanelStatusText = "Clipboard empty"
            refreshClipboardPanelSnippets()
            return
        }

        clipboardPanelStatusText = "Updated"
        refreshClipboardPanelSnippets()
    }

    func deleteClipboardPanelSnippet(_ snippet: HWKClipboardSnippet) {
        deleteClipboardPanelSnippetHandler?(snippet)
        clipboardPanelSnippets.removeAll { $0.id == snippet.id }
        clipboardPanelStatusText = "Deleted"
    }

    func applyClipboardPanelSnippet(_ snippet: HWKClipboardSnippet) {
        applyClipboardPanelSnippetHandler?(snippet)
        dismissClipboardPanel()
    }

    private func sortedClipboardPanelSnippets(_ snippets: [HWKClipboardSnippet]) -> [HWKClipboardSnippet] {
        snippets.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func tapSuggestionSlot(laneID: Int, fallback: KeyboardSuggestionItem) {
        guard !isClipboardPanelPresented else { return }
        if activeSuggestionRolodexLaneID == laneID {
            applyActiveRolodexSuggestion()
            return
        }
        guard isCurrentSuggestionAction(laneID: laneID, fallback: fallback) else { return }

        if activeSuggestionRolodexLaneID != nil {
            dismissSuggestionRolodex()
        }
        applySuggestion(fallback)
    }

    func performSuggestionSwipeUp(laneID: Int, fallback: KeyboardSuggestionItem) {
        guard !isClipboardPanelPresented else { return }
        switch settings.suggestionSwipeUpAction {
        case .rolodex:
            if activeSuggestionRolodexLaneID == laneID {
                applyActiveRolodexSuggestion()
                return
            }
            openSuggestionRolodex(laneID: laneID)
        case .laneWord:
            selectSuggestionLaneWord(laneID: laneID, fallback: fallback)
        case .off:
            break
        }
    }

    func selectSuggestionLaneWord(laneID: Int, fallback: KeyboardSuggestionItem) {
        guard !isClipboardPanelPresented else { return }
        guard suggestionRolodexLanes.contains(where: { $0.id == laneID }) else { return }
        if activeSuggestionRolodexLaneID == laneID,
           let activeSuggestion = activeSuggestionRolodexLane?.selectedItem {
            dismissSuggestionRolodex()
            applySuggestion(activeSuggestion)
            return
        }
        guard isCurrentSuggestionAction(laneID: laneID, fallback: fallback) else { return }
        if activeSuggestionRolodexLaneID != nil {
            dismissSuggestionRolodex()
        }
        applySuggestion(fallback)
    }

    private func isCurrentSuggestionAction(laneID: Int, fallback: KeyboardSuggestionItem) -> Bool {
        guard suggestionRolodexLanes.contains(where: { $0.id == laneID }) else { return false }
        // A slot retains its touch state across candidate refreshes. Reject an
        // obsolete insertion without rejecting reordering or metadata updates.
        return suggestionStripItems.contains { current in
            current.id == fallback.id && current.kind == fallback.kind &&
                current.sourceText == fallback.sourceText && current.replacement == fallback.replacement &&
                current.trailingSuffix == fallback.trailingSuffix && current.customTextRuleID == fallback.customTextRuleID &&
                current.hypothesis.intent == fallback.hypothesis.intent &&
                current.hypothesis.sourceText == fallback.hypothesis.sourceText &&
                current.hypothesis.replacement == fallback.hypothesis.replacement &&
                current.hypothesis.isModelGenerated == fallback.hypothesis.isModelGenerated
        }
    }

    func performSuggestionSwipeDown(laneID: Int?) {
        guard !isClipboardPanelPresented else { return }
        switch settings.suggestionSwipeDownAction {
        case .hideExpanded:
            guard isExpanded else { return }
            performFeedback()
            collapseExpanded()
            refreshStateHandler?()
        case .rolodex:
            guard let laneID else { return }
            openSuggestionRolodex(laneID: laneID)
        case .off:
            break
        }
    }

    func performSuggestionSwipeLeft() {
        guard !isClipboardPanelPresented else { return }
        guard settings.suggestionSwipeLeftDeleteEnabled else { return }
        back()
    }

    func performSuggestionSwipeRight() {
        guard !isClipboardPanelPresented else { return }
        guard settings.suggestionSwipeRightSpaceEnabled else { return }
        insertText(" ")
    }

    func openSuggestionRolodex(laneID: Int) {
        guard !isClipboardPanelPresented else { return }
        guard let lane = suggestionRolodexLanes.first(where: { $0.id == laneID }),
              lane.items.count > 1 else {
            return
        }

        performFeedback()
        var selectedIndexes = activeSuggestionRolodexSelectedIndexes
        selectedIndexes[laneID] = lane.selectedIndex
        activeSuggestionRolodexSelectedIndexes = selectedIndexes
        activeSuggestionRolodexLaneID = laneID
        suggestionRolodexDragOffset = 0
        suggestionRolodexSelectedFlashWorkItem?.cancel()
        suggestionRolodexSelectedFlashWorkItem = nil
        suggestionRolodexVisualPhase = .idle
        suggestionRolodexDragStep = 0
        suggestionRolodexLastDragTranslation = nil
        suggestionRolodexTouchExceededTapSlop = false
        suggestionRolodexRequiresFreshTap = false
        suggestionSwipePreviewColumn = nil
        suggestionRolodexVisibilityChangedHandler?(true)
    }

    @discardableResult
    func focusSuggestionRolodexForHardwareSelector(laneID: Int) -> Bool {
        guard !isClipboardPanelPresented else { return false }
        guard let lane = suggestionRolodexLanes.first(where: { $0.id == laneID }),
              !lane.items.isEmpty else {
            return false
        }
        if activeSuggestionRolodexLaneID == laneID { return true }

        performFeedback()
        var selectedIndexes = activeSuggestionRolodexSelectedIndexes
        selectedIndexes[laneID] = lane.selectedIndex
        activeSuggestionRolodexSelectedIndexes = selectedIndexes
        activeSuggestionRolodexLaneID = laneID
        suggestionRolodexDragOffset = 0
        suggestionRolodexSelectedFlashWorkItem?.cancel()
        suggestionRolodexSelectedFlashWorkItem = nil
        suggestionRolodexVisualPhase = .idle
        suggestionRolodexDragStep = 0
        suggestionRolodexLastDragTranslation = nil
        suggestionRolodexTouchExceededTapSlop = false
        suggestionRolodexRequiresFreshTap = false
        suggestionSwipePreviewColumn = nil
        suggestionRolodexVisibilityChangedHandler?(true)
        return true
    }

    func dismissSuggestionRolodex() {
        let wasActive = activeSuggestionRolodexLaneID != nil
        suggestionRolodexSelectedFlashWorkItem?.cancel()
        suggestionRolodexSelectedFlashWorkItem = nil
        activeSuggestionRolodexLaneID = nil
        activeSuggestionRolodexSelectedIndexes = [:]
        suggestionRolodexDragOffset = 0
        suggestionRolodexVisualPhase = .idle
        suggestionRolodexDragStep = 0
        suggestionRolodexLastDragTranslation = nil
        suggestionRolodexTouchExceededTapSlop = false
        suggestionRolodexRequiresFreshTap = false
        if wasActive {
            suggestionRolodexVisibilityChangedHandler?(false)
            suggestionInteractionEndedHandler?()
        }
    }

    func updateSuggestionRolodexDrag(_ translation: CGFloat) {
        guard !isClipboardPanelPresented else { return }
        guard let laneID = activeSuggestionRolodexLaneID else { return }

        if shouldIgnoreSuggestionRolodexRecognizerRestart(translation) {
            suggestionRolodexLastDragTranslation = translation
            suggestionRolodexDragOffset = 0
            return
        }

        if abs(translation) > suggestionRolodexTapSlop {
            suggestionRolodexTouchExceededTapSlop = true
            suggestionRolodexRequiresFreshTap = true
            setSuggestionRolodexVisualPhase(.scrolling)
        } else if suggestionRolodexLastDragTranslation == nil {
            suggestionRolodexTouchExceededTapSlop = false
            suggestionRolodexRequiresFreshTap = false
        }

        let stepDistance = suggestionRolodexStepDistance
        let downwardTranslation = max(translation, 0)
        let rawStep = Int((downwardTranslation / stepDistance).rounded(.towardZero))
        let step = max(rawStep, suggestionRolodexDragStep)
        if step != suggestionRolodexDragStep {
            rotateSuggestionRolodex(laneID: laneID, steps: step - suggestionRolodexDragStep)
            suggestionRolodexDragStep = step
        }

        suggestionRolodexDragOffset = max(0, downwardTranslation - (CGFloat(step) * stepDistance))
        suggestionRolodexLastDragTranslation = translation
    }

    func finishSuggestionRolodexDrag(laneID: Int, translation: CGFloat) {
        guard !isClipboardPanelPresented else { return }
        guard activeSuggestionRolodexLaneID == laneID else { return }
        let endedAfterDrag = suggestionRolodexTouchExceededTapSlop || abs(translation) > suggestionRolodexTapSlop
        suggestionRolodexDragOffset = 0
        suggestionRolodexDragStep = 0
        suggestionRolodexLastDragTranslation = nil
        suggestionRolodexTouchExceededTapSlop = endedAfterDrag
        suggestionRolodexRequiresFreshTap = endedAfterDrag
        setSuggestionRolodexVisualPhase(.idle)
    }

    func finishSuggestionRolodexTouch(
        laneID: Int,
        translation: CGSize,
        fallback _: KeyboardSuggestionItem
    ) {
        guard !isClipboardPanelPresented else { return }
        guard activeSuggestionRolodexLaneID == laneID else { return }

        if let offset = suggestionRolodexHorizontalLaneOffset(translation),
           let nextLaneID = adjacentVisibleSuggestionLaneID(from: laneID, offset: offset) {
            _ = focusSuggestionRolodexForHardwareSelector(laneID: nextLaneID)
            return
        }

        if isSuggestionRolodexSwipeUp(translation) {
            applyActiveRolodexSuggestion()
            return
        }

        if isSuggestionRolodexTap(translation) {
            applyActiveRolodexSuggestion()
            return
        }

        finishSuggestionRolodexDrag(laneID: laneID, translation: translation.height)
    }

    private func suggestionRolodexHorizontalLaneOffset(_ translation: CGSize) -> Int? {
        switch HWCKeyboardLayoutMetrics.directionalSwipeAxis(
            for: translation,
            minimumTravel: 30
        ) {
        case .left: return -1
        case .right: return 1
        case .up, .down, .none: return nil
        }
    }

    private func isSuggestionRolodexSwipeUp(_ translation: CGSize) -> Bool {
        let minimumRise: CGFloat = settings.appTheme.usesDarkChrome ? 34 : 30
        return translation.height <= -minimumRise
            && abs(translation.height) >= abs(translation.width) * 1.35
    }

    private var suggestionRolodexStepDistance: CGFloat {
        max(
            HWCKeyboardLayoutMetrics.suggestionRolodexItemHeight(for: settings) * 0.82,
            1
        )
    }

    private var suggestionRolodexTapSlop: CGFloat {
        7
    }

    private func isSuggestionRolodexTap(_ translation: CGSize) -> Bool {
        !suggestionRolodexRequiresFreshTap
            && !suggestionRolodexTouchExceededTapSlop
            && max(abs(translation.width), abs(translation.height)) <= suggestionRolodexTapSlop
    }

    private func shouldIgnoreSuggestionRolodexRecognizerRestart(_ translation: CGFloat) -> Bool {
        guard suggestionRolodexDragStep != 0,
              let lastTranslation = suggestionRolodexLastDragTranslation else {
            return false
        }

        return abs(translation) <= suggestionRolodexTapSlop
            && abs(lastTranslation) >= suggestionRolodexStepDistance * 0.8
    }

    func rotateSuggestionRolodex(laneID: Int, steps: Int) {
        guard !isClipboardPanelPresented else { return }
        guard steps != 0,
              let laneIndex = suggestionRolodexLanes.firstIndex(where: { $0.id == laneID }) else {
            return
        }

        let count = suggestionRolodexLanes[laneIndex].items.count
        guard count > 1 else { return }

        let currentIndex = activeSuggestionRolodexLaneID == laneID
            ? (activeSuggestionRolodexSelectedIndexes[laneID] ?? suggestionRolodexLanes[laneIndex].selectedIndex)
            : suggestionRolodexLanes[laneIndex].selectedIndex
        let nextIndex = ((currentIndex + steps) % count + count) % count
        guard nextIndex != currentIndex else { return }

        if activeSuggestionRolodexLaneID == laneID {
            performRolodexStepFeedback()
            var selectedIndexes = activeSuggestionRolodexSelectedIndexes
            selectedIndexes[laneID] = nextIndex
            activeSuggestionRolodexSelectedIndexes = selectedIndexes
        } else {
            performFeedback()
            var lanes = suggestionRolodexLanes
            lanes[laneIndex].selectedIndex = nextIndex
            suggestionContentInvalidation.invalidate()
            suggestionRolodexLanes = lanes
            refreshCachedSuggestionLaneContents()
        }
    }

    func applyActiveRolodexSuggestion() {
        guard !isClipboardPanelPresented else {
            dismissSuggestionRolodex()
            return
        }
        guard let suggestion = activeSuggestionRolodexLane?.selectedItem else {
            dismissSuggestionRolodex()
            return
        }
        guard suggestionRolodexVisualPhase != .selected else { return }

        suggestionRolodexSelectedFlashWorkItem?.cancel()
        suggestionRolodexVisualPhase = .selected
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.suggestionRolodexVisualPhase == .selected else { return }
            self.suggestionRolodexSelectedFlashWorkItem = nil
            self.dismissSuggestionRolodex()
            self.applySuggestion(suggestion)
        }
        suggestionRolodexSelectedFlashWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + HWCKeyboardRolodexVisualTiming.selectedFlashDuration,
            execute: workItem
        )
    }

    func setSuggestionRolodexVisualPhase(_ phase: SuggestionRolodexVisualPhase) {
        guard activeSuggestionRolodexLaneID != nil else {
            suggestionRolodexVisualPhase = .idle
            return
        }
        guard suggestionRolodexVisualPhase != .selected else { return }
        if phase == .selecting && suggestionRolodexVisualPhase != .selecting {
            prepareFeedback()
        }
        suggestionRolodexVisualPhase = phase
    }

    func toggleQuickInsertRowMinimized() {
        guard settings.showQuickInsertRow, settings.showQuickInsertHandle else { return }
        performFeedback()
        isQuickInsertRowMinimized.toggle()
        accessoryLayoutChangedHandler?()
    }

    private func performFeedback() {
        feedbackHandler?()
    }

    func performTouchDownFeedback() {
        performFeedback()
    }

    private func performHardwareModifierFeedbackIfNeeded(_ shouldProvideFeedback: Bool) {
        guard shouldProvideFeedback else { return }
        DispatchQueue.main.async { [feedbackHandler] in
            feedbackHandler?()
        }
    }

    func prepareFeedback() {
        prepareFeedbackHandler?()
    }

    private func performRolodexStepFeedback() {
        rolodexStepFeedbackHandler?()
    }

    private var effectiveAutomaticCapsActive: Bool {
        isAutoCapsActive && !isAutoCapsSuppressed && !automaticCapsSuppressionPending
    }

    private func beginSoftwareTextInsertion() {
        softwareTextInsertionDepth += 1
    }

    private func completeSoftwareTextInsertion() -> Bool {
        precondition(softwareTextInsertionDepth > 0)
        softwareTextInsertionDepth -= 1
        guard softwareTextInsertionDepth == 0 else { return false }

        var didPublish = false
        if capsPrimeConsumptionPending {
            capsPrimeConsumptionPending = false
            isCapsPrimed = false
            didPublish = true
        }
        if automaticCapsSuppressionPending {
            automaticCapsSuppressionPending = false
            isAutoCapsSuppressed = true
            didPublish = true
        }
        return didPublish
    }

    private func shouldConsumeSoftwareCapsAfterHardwareTextInput(_ text: String) -> Bool {
        guard !isSymbolKeyboard else { return false }
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return false }
        return CharacterSet.letters.contains(scalar)
    }

    private func displayedLetterRow(_ values: [String], for row: HWCKeyboardRowKind) -> [String] {
        let resolvedRow = visibleLetterRow(values, for: row)
        guard isCapsShiftActive else { return resolvedRow }
        return resolvedRow.map { $0.uppercased() }
    }

    private func visibleLetterRow(_ values: [String], for row: HWCKeyboardRowKind) -> [String] {
        normalizedRow(values, for: row).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func expandExpanded(using mode: ExpandedPersistenceMode) {
        if mode != .awaitingSecondAction {
            cancelPendingMenuLatch()
        }

        expandedPersistenceMode = mode

        guard !isExpanded else { return }

        isExpanded = true
        expansionChangedHandler?(true)
    }

    private func collapseExpanded(clearsCustomLayer: Bool = true) {
        cancelPendingMenuLatch()
        expandedPersistenceMode = .collapsed
        if clearsCustomLayer, activeCustomLayerID != nil {
            activeCustomLayerID = nil
            rebuildSuggestionSpatialLayout()
        }

        guard isExpanded else { return }

        isExpanded = false
        expansionChangedHandler?(false)
    }

    private func consumePostInputState(
        insertedText: String? = nil,
        consumesCapsPrime: Bool,
        consumesExpandedMenu: Bool
    ) -> Bool {
        var didChangeVisibleState = dismissSuggestionRolodexForFreshInput()

        if consumesCapsPrime {
            didChangeVisibleState = consumeSoftwareCapsBeforeInsertion(insertedText) || didChangeVisibleState
        }

        if consumesExpandedMenu {
            didChangeVisibleState = consumeExpandedMenuIfNeeded() || didChangeVisibleState
        }

        return didChangeVisibleState
    }

    private func consumeSoftwareCapsBeforeInsertion(_ insertedText: String?) -> Bool {
        var didChangeVisibleState = false

        if isCapsPrimed, !isCapsLocked, !capsPrimeConsumptionPending {
            if softwareTextInsertionDepth > 0 {
                capsPrimeConsumptionPending = true
            } else {
                isCapsPrimed = false
            }
            didChangeVisibleState = true
        }

        if shouldSuppressAutomaticCapsAfterInput(insertedText) {
            if softwareTextInsertionDepth > 0 {
                automaticCapsSuppressionPending = true
            } else {
                isAutoCapsSuppressed = true
            }
            didChangeVisibleState = true
        }

        return didChangeVisibleState
    }

    private func shouldSuppressAutomaticCapsAfterInput(_ insertedText: String?) -> Bool {
        guard effectiveAutomaticCapsActive else { return false }
        guard let insertedText else { return false }
        return insertedText.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    private func consumeExpandedMenuIfNeeded() -> Bool {
        switch expandedPersistenceMode {
        case .collapsed, .latched:
            return false
        case .oneShot:
            beginPendingMenuLatchWindow()
            return true
        case .awaitingSecondAction:
            cancelPendingMenuLatch()
            expandedPersistenceMode = .latched
            return true
        }
    }

    private func dismissSuggestionRolodexForFreshInput() -> Bool {
        guard activeSuggestionRolodexLaneID != nil else { return false }
        dismissSuggestionRolodex()
        return true
    }

    private func beginPendingMenuLatchWindow() {
        cancelPendingMenuLatch()
        expandedPersistenceMode = .awaitingSecondAction

        guard settings.menuTapLockWindowMs > 0 else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.expandedPersistenceMode == .awaitingSecondAction else { return }
            self.collapseExpanded()
            self.refreshStateHandler?()
        }

        pendingMenuLatchWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(settings.menuTapLockWindowMs),
            execute: workItem
        )
    }

    private func cancelPendingMenuLatch() {
        pendingMenuLatchWorkItem?.cancel()
        pendingMenuLatchWorkItem = nil
    }

    private func normalizedRow(_ values: [String], for row: HWCKeyboardRowKind) -> [String] {
        let targetCount: Int
        switch row {
        case .quickInsert:
            targetCount = KeyboardKeymap.defaultQuickInsertRow.count
        case .holdQuickInsert:
            targetCount = KeyboardKeymap.defaultQuickInsertRow.count
        case .toolbar:
            targetCount = KeyboardLayoutBounds.clampedToolbarCount(settings.toolbarKeyCount)
        case .holdToolbar:
            targetCount = KeyboardLayoutBounds.clampedToolbarCount(settings.toolbarKeyCount)
        case .symbolTop:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolTopRowKeyCount)
        case .holdSymbolTop:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolTopRowKeyCount)
        case .symbolMiddle:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolMiddleRowKeyCount)
        case .holdSymbolMiddle:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolMiddleRowKeyCount)
        case .symbolBottom:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolBottomRowKeyCount)
        case .holdSymbolBottom:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.symbolBottomRowKeyCount)
        case .symbolUtility:
            targetCount = KeyboardKeymap.defaultSymbolUtilityRow.count
        case .letterTop:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterTopRowKeyCount)
        case .holdLetterTop:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterTopRowKeyCount)
        case .letterMiddle:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterMiddleRowKeyCount)
        case .holdLetterMiddle:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterMiddleRowKeyCount)
        case .letterBottom:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterBottomRowKeyCount)
        case .holdLetterBottom:
            targetCount = KeyboardLayoutBounds.clampedExpandedCount(settings.letterBottomRowKeyCount)
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            targetCount = KeyboardKeymap.defaultTrailingUtilityRow.count
        case .letterUtility:
            targetCount = KeyboardKeymap.defaultLetterUtilityRow.count
        case .letterBottomLeading:
            targetCount = KeyboardKeymap.defaultLetterBottomLeadingRow.count
        }

        var normalized = Array(values.prefix(targetCount))
        while normalized.count < targetCount {
            normalized.append("")
        }
        return normalized
    }
}

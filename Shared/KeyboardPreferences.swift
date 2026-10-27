import Foundation
import UIKit

enum KeyboardLayoutBounds {
    static let toolbarHeightRange = 34...64
    static let expandedKeyHeightRange = 44...60
    static let suggestionVisibleWordCounts = [3, 6, 9]
    static let suggestionRowHeightRange = 28...44
    static let toolbarCountRange = 4...8
    static let expandedCountRange = 6...12
    static let holdActivationDurationRangeMs = 150...700
    static let rolodexSelectHoldDurationRangeMs = 150...700
    static let hardwareHoldTriggerRangeMs = 150...700
    static let menuTapLockWindowRangeMs = 0...700
    static let deleteHoldWordCountRange = 1...10
    static let maximumCustomKeyTextLength = 256

    static func clampedSuggestionVisibleWordCount(_ value: Int) -> Int {
        suggestionVisibleWordCounts.min { abs($0 - value) < abs($1 - value) } ?? 3
    }

    static let perKeyHeightRange: ClosedRange<CGFloat> = 32...72
    static let perKeyWidthWeightRange: ClosedRange<CGFloat> = 0.5...2.5
    static let maxRowsPerSurface = 6
    static let maxKeysPerRow = 14
    static let maxCustomLayers = 24
    static let maxKeyDimensionOverrides = maxRowsPerSurface * maxKeysPerRow * 6

    static func clampedPerKeyHeight(_ value: CGFloat) -> CGFloat {
        min(max(value, perKeyHeightRange.lowerBound), perKeyHeightRange.upperBound)
    }

    static func clampedPerKeyWidthWeight(_ value: CGFloat) -> CGFloat {
        min(max(value, perKeyWidthWeightRange.lowerBound), perKeyWidthWeightRange.upperBound)
    }

    static func clampedToolbarHeight(_ value: Int) -> Int {
        min(max(value, toolbarHeightRange.lowerBound), toolbarHeightRange.upperBound)
    }

    static func clampedExpandedKeyHeight(_ value: Int) -> Int {
        min(max(value, expandedKeyHeightRange.lowerBound), expandedKeyHeightRange.upperBound)
    }

    static func clampedToolbarCount(_ value: Int) -> Int {
        min(max(value, toolbarCountRange.lowerBound), toolbarCountRange.upperBound)
    }

    static func clampedExpandedCount(_ value: Int) -> Int {
        min(max(value, expandedCountRange.lowerBound), expandedCountRange.upperBound)
    }

    static func clampedHoldActivationDurationMs(_ value: Int) -> Int {
        min(max(value, holdActivationDurationRangeMs.lowerBound), holdActivationDurationRangeMs.upperBound)
    }

    static func clampedRolodexSelectHoldDurationMs(_ value: Int) -> Int {
        min(max(value, rolodexSelectHoldDurationRangeMs.lowerBound), rolodexSelectHoldDurationRangeMs.upperBound)
    }

    static func clampedHardwareHoldTriggerMs(_ value: Int) -> Int {
        min(max(value, hardwareHoldTriggerRangeMs.lowerBound), hardwareHoldTriggerRangeMs.upperBound)
    }

    static func clampedMenuTapLockWindowMs(_ value: Int) -> Int {
        min(max(value, menuTapLockWindowRangeMs.lowerBound), menuTapLockWindowRangeMs.upperBound)
    }

    static func clampedDeleteHoldWordCount(_ value: Int) -> Int {
        min(max(value, deleteHoldWordCountRange.lowerBound), deleteHoldWordCountRange.upperBound)
    }
}

enum KeyboardFeedbackLevel: String, CaseIterable, Identifiable {
    case light
    case medium
    case heavy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "Light"
        case .medium:
            return "Medium"
        case .heavy:
            return "Heavy"
        }
    }

    var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle {
        switch self {
        case .light:
            return .light
        case .medium:
            return .medium
        case .heavy:
            return .heavy
        }
    }

    var intensity: CGFloat {
        switch self {
        case .light:
            return 0.55
        case .medium:
            return 0.85
        case .heavy:
            return 1.0
        }
    }
}

enum KeyboardSuggestionSwipeUpAction: String, CaseIterable, Identifiable, Codable {
    case rolodex
    case laneWord
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rolodex:
            return "Rolodex"
        case .laneWord:
            return "Lane Word"
        case .off:
            return "Off"
        }
    }
}

enum KeyboardSuggestionSwipeDownAction: String, CaseIterable, Identifiable, Codable {
    case hideExpanded
    case rolodex
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hideExpanded:
            return "Hide Expanded"
        case .rolodex:
            return "Rolodex"
        case .off:
            return "Off"
        }
    }
}

enum KeyboardHardwareAutocorrectSelectorInitiationKey: String, CaseIterable, Identifiable, Codable {
    case option

    var id: String { rawValue }

    var title: String {
        switch self {
        case .option:
            return "Option + arrows"
        }
    }
}

enum KeyboardHardwareAutocorrectSelectorSelectionKey: String, CaseIterable, Identifiable, Codable {
    case enter
    case space

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enter:
            return "Enter"
        case .space:
            return "Space"
        }
    }
}

/// Physical Return either stays with the host (which may map it to Send) or is
/// deliberately intercepted for a newline. A custom keyboard cannot invoke a
/// host application's generic Send action itself.
enum KeyboardPhysicalReturnBehavior: String, CaseIterable, Identifiable, Codable {
    case passThroughToHost
    case forceLineBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passThroughToHost:
            return "Pass Through to Host"
        case .forceLineBreak:
            return "Force Line Break"
        }
    }

    var detail: String {
        switch self {
        case .passThroughToHost:
            return "Let the host handle Return, including Send where it maps Return to Send."
        case .forceLineBreak:
            return "Intercept physical Return and insert a newline."
        }
    }
}

enum KeyboardAutocorrectRankingMethod: String, CaseIterable, Identifiable, Codable {
    case balanced
    case correctionFirst
    case frequencyFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .correctionFirst:
            return "Correction"
        case .frequencyFirst:
            return "Frequency"
        }
    }
}

enum KeyboardAutocorrectLogicRecipe: String, CaseIterable, Identifiable, Codable {
    case balanced
    case savedWordsFirst
    case dictionaryFirst
    case strict
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .savedWordsFirst:
            return "Saved Words First"
        case .dictionaryFirst:
            return "Dictionary First"
        case .strict:
            return "Strict"
        case .custom:
            return "Custom"
        }
    }

    var detail: String {
        switch self {
        case .balanced:
            return "Use saved words and dictionary together."
        case .savedWordsFirst:
            return "Trust your saved words before the dictionary."
        case .dictionaryFirst:
            return "Prefer dictionary corrections before saved words."
        case .strict:
            return "Require higher confidence before suggesting."
        case .custom:
            return "Edit the rules yourself."
        }
    }
}

enum KeyboardAutocorrectLogicBlockKind: String, CaseIterable, Identifiable, Codable {
    case savedWords
    case dictionary
    case weightedRanker
    case nativeSpellChecker
    case coreML
    case confidenceGate
    case softFallback
    case strictFallback
    case safetyGate
    case highlightTypedWord
    case customTextRule
    case previousWordLane
    case correctionLane
    case completionLane

    var id: String { rawValue }

    var defaultRole: KeyboardAutocorrectLogicBlockRole {
        switch self {
        case .savedWords, .dictionary, .nativeSpellChecker, .coreML, .customTextRule:
            return .source
        case .weightedRanker:
            return .ranker
        case .confidenceGate, .safetyGate:
            return .gate
        case .softFallback, .strictFallback:
            return .fallback
        case .highlightTypedWord:
            return .presentation
        case .previousWordLane, .correctionLane, .completionLane:
            return .lane
        }
    }

    var laneFamily: KeyboardAutocorrectLogicLaneFamily? {
        switch self {
        case .previousWordLane:
            return .previousWord
        case .correctionLane:
            return .correction
        case .completionLane:
            return .completion
        default:
            return nil
        }
    }

    var title: String {
        switch self {
        case .savedWords:
            return "Saved Words"
        case .dictionary:
            return "Dictionary"
        case .weightedRanker:
            return "Weighted Ranker"
        case .nativeSpellChecker:
            return "Spell Check"
        case .coreML:
            return "CoreML"
        case .confidenceGate:
            return "Confidence Gate"
        case .softFallback:
            return "Soft Fallback"
        case .strictFallback:
            return "Strict Fallback"
        case .safetyGate:
            return "Safety Gate"
        case .highlightTypedWord:
            return "Highlight Typed Word"
        case .customTextRule:
            return "Custom Rule"
        case .previousWordLane:
            return "Previous Word Lane"
        case .correctionLane:
            return "Correction Lane"
        case .completionLane:
            return "Completion Lane"
        }
    }
}

enum KeyboardAutocorrectLogicBlockRole: String, CaseIterable, Identifiable, Codable {
    case source
    case ranker
    case gate
    case fallback
    case presentation
    case lane

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .ranker:
            return "Rank"
        case .gate:
            return "Gate"
        case .fallback:
            return "Fallback"
        case .presentation:
            return "Display"
        case .lane:
            return "Lane"
        }
    }
}

enum KeyboardAutocorrectLogicChipColor: String, CaseIterable, Identifiable, Codable {
    case none
    case blue
    case green
    case orange

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            return "None"
        case .blue:
            return "Blue"
        case .green:
            return "Green"
        case .orange:
            return "Orange"
        }
    }
}

struct KeyboardAutocorrectLogicBlock: Codable, Equatable, Identifiable {
    let id: UUID
    var kind: KeyboardAutocorrectLogicBlockKind
    var rankPriority: Int
    var fallbackEnabled: Bool
    var dictionaryWeight: Double
    var savedWordsWeight: Double
    var acceptanceThreshold: Double
    var fallbackTargetID: UUID?
    var chipColor: KeyboardAutocorrectLogicChipColor
    var customTextRuleID: UUID?

    var role: KeyboardAutocorrectLogicBlockRole {
        kind.defaultRole
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case rankPriority
        case fallbackEnabled
        case dictionaryWeight
        case savedWordsWeight
        case acceptanceThreshold
        case fallbackTargetID
        case chipColor
        case customTextRuleID
    }

    init(
        id: UUID = UUID(),
        kind: KeyboardAutocorrectLogicBlockKind,
        rankPriority: Int,
        fallbackEnabled: Bool = false,
        dictionaryWeight: Double = 0.5,
        savedWordsWeight: Double = 0.5,
        acceptanceThreshold: Double = 0.8,
        fallbackTargetID: UUID? = nil,
        chipColor: KeyboardAutocorrectLogicChipColor = .none,
        customTextRuleID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.rankPriority = rankPriority
        self.fallbackEnabled = fallbackEnabled
        self.dictionaryWeight = dictionaryWeight
        self.savedWordsWeight = savedWordsWeight
        self.acceptanceThreshold = acceptanceThreshold
        self.fallbackTargetID = fallbackTargetID
        self.chipColor = chipColor
        self.customTextRuleID = customTextRuleID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(KeyboardAutocorrectLogicBlockKind.self, forKey: .kind)
        rankPriority = try container.decode(Int.self, forKey: .rankPriority)
        fallbackEnabled = try container.decodeIfPresent(Bool.self, forKey: .fallbackEnabled) ?? false
        dictionaryWeight = try container.decodeIfPresent(Double.self, forKey: .dictionaryWeight) ?? 0.5
        savedWordsWeight = try container.decodeIfPresent(Double.self, forKey: .savedWordsWeight) ?? 0.5
        acceptanceThreshold = try container.decodeIfPresent(Double.self, forKey: .acceptanceThreshold) ?? 0.8
        fallbackTargetID = try container.decodeIfPresent(UUID.self, forKey: .fallbackTargetID)
        chipColor = try container.decodeIfPresent(KeyboardAutocorrectLogicChipColor.self, forKey: .chipColor) ?? .none
        customTextRuleID = try container.decodeIfPresent(UUID.self, forKey: .customTextRuleID)
    }

    static let defaultPipeline: [KeyboardAutocorrectLogicBlock] = [
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A1111111-1111-4111-8111-111111111111")!,
            kind: .savedWords,
            rankPriority: 0
        ),
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A2222222-2222-4222-8222-222222222222")!,
            kind: .dictionary,
            rankPriority: 1
        ),
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A3333333-3333-4333-8333-333333333333")!,
            kind: .weightedRanker,
            rankPriority: 2,
            dictionaryWeight: 0.55,
            savedWordsWeight: 0.45
        ),
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A4444444-4444-4444-8444-444444444444")!,
            kind: .nativeSpellChecker,
            rankPriority: 3
        ),
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A5555555-5555-4555-8555-555555555555")!,
            kind: .coreML,
            rankPriority: 4
        ),
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A6666666-6666-4666-8666-666666666666")!,
            kind: .confidenceGate,
            rankPriority: 5,
            acceptanceThreshold: 0.82
        ),
        KeyboardAutocorrectLogicBlock(
            id: UUID(uuidString: "A7777777-7777-4777-8777-777777777777")!,
            kind: .strictFallback,
            rankPriority: 6,
            fallbackEnabled: true,
            fallbackTargetID: UUID(uuidString: "A6666666-6666-4666-8666-666666666666")!
        ),
    ]
}

enum KeyboardAutocorrectLogicLaneFamily: String, Codable, CaseIterable, Identifiable {
    case previousWord
    case correction
    case completion

    var id: String { rawValue }
}

struct KeyboardAutocorrectLogicLane: Codable, Equatable, Identifiable {
    let id: Int
    var title: String
    var family: KeyboardAutocorrectLogicLaneFamily
    var reason: String
    var blocks: [KeyboardAutocorrectLogicBlock]

    static let laneCount = 9

    var effectiveFamily: KeyboardAutocorrectLogicLaneFamily {
        blocks
            .sorted { lhs, rhs in
                if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.rankPriority < rhs.rankPriority
            }
            .compactMap { $0.kind.laneFamily }
            .first ?? family
    }

    func replacingLaneIntent(with kind: KeyboardAutocorrectLogicBlockKind) -> KeyboardAutocorrectLogicLane {
        guard let laneFamily = kind.laneFamily else { return self }

        let shiftedBlocks = blocks
            .filter { $0.kind.laneFamily == nil }
            .sorted { lhs, rhs in
                if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.rankPriority < rhs.rankPriority
            }
            .enumerated()
            .map { index, block in
                KeyboardAutocorrectLogicBlock(
                    id: block.id,
                    kind: block.kind,
                    rankPriority: index + 1,
                    fallbackEnabled: block.fallbackEnabled,
                    dictionaryWeight: block.dictionaryWeight,
                    savedWordsWeight: block.savedWordsWeight,
                    acceptanceThreshold: block.acceptanceThreshold,
                    fallbackTargetID: block.fallbackTargetID,
                    chipColor: block.chipColor,
                    customTextRuleID: block.customTextRuleID
                )
            }

        return KeyboardAutocorrectLogicLane(
            id: id,
            title: Self.title(for: laneFamily),
            family: laneFamily,
            reason: Self.reason(for: laneFamily),
            blocks: [KeyboardAutocorrectLogicBlock(kind: kind, rankPriority: 0)] + shiftedBlocks
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case family
        case reason
        case blocks
        case highlightsTypedWord
    }

    init(
        id: Int,
        title: String,
        family: KeyboardAutocorrectLogicLaneFamily? = nil,
        reason: String? = nil,
        blocks: [KeyboardAutocorrectLogicBlock]
    ) {
        let template = Self.template(for: id)
        self.id = id
        self.title = title
        self.family = family ?? template.family
        self.reason = reason ?? template.reason
        self.blocks = blocks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(Int.self, forKey: .id)
        let template = Self.template(for: id)
        self.id = id
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? template.title
        self.family = try container.decodeIfPresent(KeyboardAutocorrectLogicLaneFamily.self, forKey: .family) ?? template.family
        self.reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? template.reason
        let decodedBlocks = try container.decodeIfPresent([KeyboardAutocorrectLogicBlock].self, forKey: .blocks) ?? template.blocks
        let legacyHighlight = try container.decodeIfPresent(Bool.self, forKey: .highlightsTypedWord) ?? false
        self.blocks = Self.blocks(decodedBlocks, applyingLegacyHighlight: legacyHighlight, laneID: id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(family, forKey: .family)
        try container.encode(reason, forKey: .reason)
        try container.encode(blocks, forKey: .blocks)
    }

    static let defaultLanes: [KeyboardAutocorrectLogicLane] = (0..<laneCount).map { index in
        let template = Self.template(for: index)
        return KeyboardAutocorrectLogicLane(
            id: index,
            title: template.title,
            family: template.family,
            reason: template.reason,
            blocks: template.blocks
        )
    }

    private static func template(for id: Int) -> (
        title: String,
        family: KeyboardAutocorrectLogicLaneFamily,
        reason: String,
        blocks: [KeyboardAutocorrectLogicBlock]
    ) {
        let base = baseTemplate(for: id % 3)
        let variant = id / 3

        let blocks = base.blocks.enumerated().map { index, sourceBlock in
            var block = sourceBlock
            switch (variant, base.family, block.kind) {
            case (1, .previousWord, .weightedRanker):
                block.dictionaryWeight = 0.6
                block.savedWordsWeight = 0.4
            case (2, .previousWord, .weightedRanker):
                block.dictionaryWeight = 0.3
                block.savedWordsWeight = 0.7
            case (1, .correction, .coreML):
                block.rankPriority = 1
            case (1, .correction, .nativeSpellChecker):
                block.rankPriority = 2
            case (2, .correction, .confidenceGate):
                block.acceptanceThreshold = 0.92
            case (1, .completion, .weightedRanker):
                block.dictionaryWeight = 0.7
                block.savedWordsWeight = 0.3
            case (2, .completion, .savedWords):
                block.rankPriority = 2
            case (2, .completion, .dictionary):
                block.rankPriority = 1
            default:
                block.rankPriority = index
            }
            return block
        }
        let titles = [
            "Context", "Best Fix", "Completion",
            "Dictionary", "Neural Fix", "Saved Words",
            "Phrase", "Careful Fix", "Fallback",
        ]
        return (
            titles.indices.contains(id) ? titles[id] : base.title,
            base.family,
            "Independent lane \(id + 1). \(base.reason)",
            blocks.sorted { lhs, rhs in
                if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.rankPriority < rhs.rankPriority
            }
        )
    }

    private static func baseTemplate(for familyIndex: Int) -> (
        title: String,
        family: KeyboardAutocorrectLogicLaneFamily,
        reason: String,
        blocks: [KeyboardAutocorrectLogicBlock]
    ) {
        switch familyIndex {
        case 0:
            return (
                "Previous Word",
                .previousWord,
                "Use the previous word/context prediction lane.",
                [
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "B1111111-1111-4111-8111-111111111111")!,
                        kind: .previousWordLane,
                        rankPriority: 0
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "B2222222-2222-4222-8222-222222222222")!,
                        kind: .dictionary,
                        rankPriority: 1
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "B3333333-3333-4333-8333-333333333333")!,
                        kind: .weightedRanker,
                        rankPriority: 2,
                        dictionaryWeight: 0.8,
                        savedWordsWeight: 0.2
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "B4444444-4444-4444-8444-444444444444")!,
                        kind: .highlightTypedWord,
                        rankPriority: 3
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "B5555555-5555-4555-8555-555555555555")!,
                        kind: .softFallback,
                        rankPriority: 4,
                        fallbackEnabled: true
                    ),
                ]
            )
        case 1:
            let gateID = UUID(uuidString: "C6666666-6666-4666-8666-666666666666")!
            return (
                "Correction",
                .correction,
                "Show correction candidates and why typed text changed.",
                [
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "C1111111-1111-4111-8111-111111111111")!,
                        kind: .correctionLane,
                        rankPriority: 0
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "C2222222-2222-4222-8222-222222222222")!,
                        kind: .nativeSpellChecker,
                        rankPriority: 1
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "C3333333-3333-4333-8333-333333333333")!,
                        kind: .coreML,
                        rankPriority: 2
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: gateID,
                        kind: .confidenceGate,
                        rankPriority: 3,
                        acceptanceThreshold: 0.82
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "C4444444-4444-4444-8444-444444444444")!,
                        kind: .highlightTypedWord,
                        rankPriority: 4
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "C5555555-5555-4555-8555-555555555555")!,
                        kind: .strictFallback,
                        rankPriority: 5,
                        fallbackEnabled: true,
                        fallbackTargetID: gateID
                    ),
                ]
            )
        default:
            return (
                "Completion",
                .completion,
                "Offer typed-prefix completions and saved words.",
                [
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "D1111111-1111-4111-8111-111111111111")!,
                        kind: .completionLane,
                        rankPriority: 0
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "D2222222-2222-4222-8222-222222222222")!,
                        kind: .savedWords,
                        rankPriority: 1
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "D3333333-3333-4333-8333-333333333333")!,
                        kind: .dictionary,
                        rankPriority: 2
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "D4444444-4444-4444-8444-444444444444")!,
                        kind: .weightedRanker,
                        rankPriority: 3,
                        dictionaryWeight: 0.45,
                        savedWordsWeight: 0.55
                    ),
                    KeyboardAutocorrectLogicBlock(
                        id: UUID(uuidString: "D5555555-5555-4555-8555-555555555555")!,
                        kind: .softFallback,
                        rankPriority: 4,
                        fallbackEnabled: true
                    ),
                ]
            )
        }
    }

    private static func blocks(
        _ blocks: [KeyboardAutocorrectLogicBlock],
        applyingLegacyHighlight highlightsTypedWord: Bool,
        laneID: Int
    ) -> [KeyboardAutocorrectLogicBlock] {
        guard highlightsTypedWord,
              !blocks.contains(where: { $0.kind == .highlightTypedWord }) else {
            return blocks
        }

        var result = blocks
        result.append(
            KeyboardAutocorrectLogicBlock(
                kind: .highlightTypedWord,
                rankPriority: result.count
            )
        )
        return result
    }

    private static func title(for family: KeyboardAutocorrectLogicLaneFamily) -> String {
        switch family {
        case .previousWord:
            return "Previous Word"
        case .correction:
            return "Correction"
        case .completion:
            return "Completion"
        }
    }

    private static func reason(for family: KeyboardAutocorrectLogicLaneFamily) -> String {
        switch family {
        case .previousWord:
            return "Use the previous word/context prediction lane."
        case .correction:
            return "Use the current typed word correction lane."
        case .completion:
            return "Use the completion/saved word lane."
        }
    }
}

enum CompanionAppTheme: String, CaseIterable, Identifiable {
    case classic
    case dark
    case chameleon
    case custom

    var id: String { rawValue }

    var usesDarkChrome: Bool {
        switch self {
        case .classic, .chameleon, .custom:
            return false
        case .dark:
            return true
        }
    }

    var title: String {
        switch self {
        case .classic:
            return "Default"
        case .dark:
            return "Dark"
        case .chameleon:
            return "Chameleon"
        case .custom:
            return "Custom"
        }
    }

    var summary: String {
        switch self {
        case .classic:
            return "A refined modern dark keyboard with cleaner spacing and softer chrome."
        case .dark:
            return "A tighter dark treatment with flatter rows and sharper structure."
        case .chameleon:
            return "A Default-style keyboard that follows the current app's light or dark keyboard appearance."
        case .custom:
            return "A key-by-key look you shape with direct controls."
        }
    }

    static func resolved(from rawValue: String?) -> CompanionAppTheme? {
        guard let rawValue else { return nil }

        if let theme = CompanionAppTheme(rawValue: rawValue) {
            return theme
        }

        switch rawValue {
        case KeyboardLegacyStoredValues.legacyDarkThemeAlias:
            return .dark
        case "liquidGlass":
            return .classic
        default:
            return nil
        }
    }
}

enum KeyboardCustomKeyFill: String, Codable, CaseIterable, Identifiable {
    case graphite
    case ink
    case paper
    case accent
    case adaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .graphite:
            return "Graphite"
        case .ink:
            return "Ink"
        case .paper:
            return "Paper"
        case .accent:
            return "Accent"
        case .adaptive:
            return "Adaptive"
        }
    }
}

struct KeyboardCustomKeyStyle: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case keyFill
        case textBrightness
        case borderStrength
        case cornerRadius
        case shadowDepth
        case keyDistance
        case followsHostAppearance
    }

    var keyFill: KeyboardCustomKeyFill = .graphite
    var textBrightness = 94
    var borderStrength = 10
    var cornerRadius = 9
    var shadowDepth = 2
    var keyDistance = 5
    var followsHostAppearance = false

    static let defaultStyle = KeyboardCustomKeyStyle()

    init(
        keyFill: KeyboardCustomKeyFill = .graphite,
        textBrightness: Int = 94,
        borderStrength: Int = 10,
        cornerRadius: Int = 9,
        shadowDepth: Int = 2,
        keyDistance: Int = 5,
        followsHostAppearance: Bool = false
    ) {
        self.keyFill = keyFill
        self.textBrightness = textBrightness
        self.borderStrength = borderStrength
        self.cornerRadius = cornerRadius
        self.shadowDepth = shadowDepth
        self.keyDistance = keyDistance
        self.followsHostAppearance = followsHostAppearance
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyFill = try container.decodeIfPresent(KeyboardCustomKeyFill.self, forKey: .keyFill) ?? .graphite
        textBrightness = try container.decodeIfPresent(Int.self, forKey: .textBrightness) ?? 94
        borderStrength = try container.decodeIfPresent(Int.self, forKey: .borderStrength) ?? 10
        cornerRadius = try container.decodeIfPresent(Int.self, forKey: .cornerRadius) ?? 9
        shadowDepth = try container.decodeIfPresent(Int.self, forKey: .shadowDepth) ?? 2
        keyDistance = try container.decodeIfPresent(Int.self, forKey: .keyDistance) ?? 5
        followsHostAppearance = try container.decodeIfPresent(Bool.self, forKey: .followsHostAppearance) ?? false
    }

    var normalized: KeyboardCustomKeyStyle {
        KeyboardCustomKeyStyle(
            keyFill: keyFill,
            textBrightness: min(max(textBrightness, 45), 100),
            borderStrength: min(max(borderStrength, 0), 100),
            cornerRadius: min(max(cornerRadius, 0), 14),
            shadowDepth: min(max(shadowDepth, 0), 8),
            keyDistance: min(max(keyDistance, 0), 10),
            followsHostAppearance: followsHostAppearance
        )
    }
}

enum KeyboardAccentTone: String, CaseIterable, Identifiable, Hashable {
    case blue
    case skyBlue
    case mint
    case yellow
    case amber
    case rose
    case purple
    case pink
    case white

    var id: String { rawValue }

    var sortIndex: Int {
        switch self {
        case .blue:
            return 0
        case .skyBlue:
            return 1
        case .mint:
            return 2
        case .yellow:
            return 3
        case .amber:
            return 4
        case .rose:
            return 5
        case .purple:
            return 6
        case .pink:
            return 7
        case .white:
            return 8
        }
    }

    var title: String {
        switch self {
        case .blue:
            return "Blue"
        case .skyBlue:
            return "Cyan"
        case .mint:
            return "Green"
        case .yellow:
            return "Yellow"
        case .amber:
            return "Orange"
        case .rose:
            return "Red"
        case .purple:
            return "Purple"
        case .pink:
            return "Pink"
        case .white:
            return "White"
        }
    }

    var shortTitle: String {
        switch self {
        case .skyBlue:
            return "Cyan"
        default:
            return title
        }
    }

    var primaryUIColor: UIColor {
        switch self {
        case .blue:
            return UIColor(red: 0.10, green: 0.45, blue: 0.95, alpha: 1)
        case .skyBlue:
            return UIColor(red: 0.00, green: 0.76, blue: 0.94, alpha: 1)
        case .mint:
            return UIColor(red: 0.15, green: 0.78, blue: 0.28, alpha: 1)
        case .yellow:
            return UIColor(red: 0.98, green: 0.84, blue: 0.12, alpha: 1)
        case .amber:
            return UIColor(red: 0.98, green: 0.50, blue: 0.12, alpha: 1)
        case .rose:
            return UIColor(red: 0.93, green: 0.18, blue: 0.20, alpha: 1)
        case .purple:
            return UIColor(red: 0.55, green: 0.31, blue: 0.96, alpha: 1)
        case .pink:
            return UIColor(red: 0.96, green: 0.25, blue: 0.63, alpha: 1)
        case .white:
            return UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1)
        }
    }

    var secondaryUIColor: UIColor {
        switch self {
        case .blue:
            return UIColor(red: 0.05, green: 0.20, blue: 0.55, alpha: 1)
        case .skyBlue:
            return UIColor(red: 0.00, green: 0.38, blue: 0.58, alpha: 1)
        case .mint:
            return UIColor(red: 0.07, green: 0.43, blue: 0.14, alpha: 1)
        case .yellow:
            return UIColor(red: 0.62, green: 0.48, blue: 0.03, alpha: 1)
        case .amber:
            return UIColor(red: 0.60, green: 0.24, blue: 0.04, alpha: 1)
        case .rose:
            return UIColor(red: 0.56, green: 0.06, blue: 0.08, alpha: 1)
        case .purple:
            return UIColor(red: 0.28, green: 0.11, blue: 0.60, alpha: 1)
        case .pink:
            return UIColor(red: 0.60, green: 0.08, blue: 0.33, alpha: 1)
        case .white:
            return UIColor(red: 0.42, green: 0.46, blue: 0.52, alpha: 1)
        }
    }

    var glowUIColor: UIColor {
        switch self {
        case .blue:
            return UIColor(red: 0.54, green: 0.80, blue: 1.0, alpha: 1)
        case .skyBlue:
            return UIColor(red: 0.60, green: 0.94, blue: 1.0, alpha: 1)
        case .mint:
            return UIColor(red: 0.60, green: 0.96, blue: 0.67, alpha: 1)
        case .yellow:
            return UIColor(red: 1.0, green: 0.95, blue: 0.58, alpha: 1)
        case .amber:
            return UIColor(red: 1.0, green: 0.78, blue: 0.46, alpha: 1)
        case .rose:
            return UIColor(red: 1.0, green: 0.60, blue: 0.62, alpha: 1)
        case .purple:
            return UIColor(red: 0.82, green: 0.70, blue: 1.0, alpha: 1)
        case .pink:
            return UIColor(red: 1.0, green: 0.70, blue: 0.84, alpha: 1)
        case .white:
            return UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1)
        }
    }
}

struct KeyboardAccentPalette: RawRepresentable, Hashable, Identifiable {
    private enum BlendProfile {
        case lead
        case depth
        case glow
    }

    private struct RGBA {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    let components: [KeyboardAccentTone]

    init(_ components: [KeyboardAccentTone]) {
        self.components = Self.orderedComponents(from: components)
    }

    init?(rawValue: String) {
        let parts = rawValue
            .split(separator: "+")
            .map { String($0) }
        let tones = parts.compactMap(KeyboardAccentTone.init(rawValue:))
        guard tones.count == parts.count else { return nil }

        let ordered = Self.orderedComponents(from: tones)
        guard (1...3).contains(ordered.count) else { return nil }
        components = ordered
    }

    var rawValue: String {
        components.map(\.rawValue).joined(separator: "+")
    }

    var id: String { rawValue }

    var isMixed: Bool {
        components.count > 1
    }

    var title: String {
        components.count == 1 ? components[0].title : components.map(\.shortTitle).joined(separator: " + ")
    }

    var statusTitle: String {
        title
    }

    var primaryUIColor: UIColor {
        blendedColor(
            from: components.map(\.primaryUIColor),
            weights: weights(for: .lead),
            saturationMultiplier: isMixed ? 1.12 : 1,
            brightnessMultiplier: isMixed ? 1.0 : 1,
            hueNudge: isMixed ? mixHueNudge : 0
        )
    }

    var secondaryUIColor: UIColor {
        blendedColor(
            from: components.map(\.secondaryUIColor),
            weights: weights(for: .depth),
            saturationMultiplier: isMixed ? 1.1 : 1,
            brightnessMultiplier: isMixed ? 0.86 : 1,
            hueNudge: isMixed ? -(mixHueNudge * 0.55) : 0
        )
    }

    var glowUIColor: UIColor {
        blendedColor(
            from: components.map(\.glowUIColor),
            weights: weights(for: .glow),
            saturationMultiplier: isMixed ? 0.98 : 1,
            brightnessMultiplier: isMixed ? 1.08 : 1,
            hueNudge: isMixed ? mixHueNudge * 0.25 : 0
        )
    }

    static let blue = KeyboardAccentPalette([.blue])
    static let skyBlue = KeyboardAccentPalette([.skyBlue])
    static let mint = KeyboardAccentPalette([.mint])
    static let yellow = KeyboardAccentPalette([.yellow])
    static let amber = KeyboardAccentPalette([.amber])
    static let rose = KeyboardAccentPalette([.rose])
    static let purple = KeyboardAccentPalette([.purple])
    static let pink = KeyboardAccentPalette([.pink])
    static let white = KeyboardAccentPalette([.white])

    static let basePresets: [KeyboardAccentPalette] = KeyboardAccentTone.allCases.map {
        KeyboardAccentPalette([$0])
    }

    func selectionIndex(of tone: KeyboardAccentTone) -> Int? {
        components.firstIndex(of: tone).map { $0 + 1 }
    }

    func toggling(_ tone: KeyboardAccentTone) -> KeyboardAccentPalette {
        var updated = components

        if let index = updated.firstIndex(of: tone) {
            if updated.count > 1 {
                updated.remove(at: index)
            }
            return KeyboardAccentPalette(updated)
        }

        if updated.count == 3 {
            updated.removeLast()
        }
        updated.append(tone)
        return KeyboardAccentPalette(updated)
    }

    private static func orderedComponents(from components: [KeyboardAccentTone]) -> [KeyboardAccentTone] {
        var ordered = [KeyboardAccentTone]()
        for tone in components where !ordered.contains(tone) {
            ordered.append(tone)
            if ordered.count == 3 {
                break
            }
        }
        return ordered.isEmpty ? [.blue] : ordered
    }

    private var mixHueNudge: CGFloat {
        let seed = components.enumerated().reduce(0) { partialResult, item in
            partialResult + ((item.offset + 1) * (item.element.sortIndex + 3) * 13)
        }
        let degrees = (seed % 29) - 14
        return CGFloat(degrees) / 360
    }

    private func weights(for profile: BlendProfile) -> [CGFloat] {
        switch (profile, components.count) {
        case (_, 0):
            return [1]
        case (_, 1):
            return [1]
        case (.lead, 2):
            return [0.72, 0.28]
        case (.depth, 2):
            return [0.36, 0.64]
        case (.glow, 2):
            return [0.44, 0.56]
        case (.lead, _):
            return [0.58, 0.28, 0.14]
        case (.depth, _):
            return [0.20, 0.33, 0.47]
        case (.glow, _):
            return [0.24, 0.31, 0.45]
        }
    }

    private func blendedColor(
        from colors: [UIColor],
        weights: [CGFloat],
        saturationMultiplier: CGFloat,
        brightnessMultiplier: CGFloat,
        hueNudge: CGFloat
    ) -> UIColor {
        let resolvedWeights = Array(weights.prefix(colors.count))
        let totalWeight = max(resolvedWeights.reduce(0, +), 0.001)
        let rgba = zip(colors, resolvedWeights).reduce(
            RGBA(red: 0, green: 0, blue: 0, alpha: 0)
        ) { partialResult, pair in
            let rgba = Self.rgba(from: pair.0)
            let weight = pair.1 / totalWeight
            return RGBA(
                red: partialResult.red + (rgba.red * weight),
                green: partialResult.green + (rgba.green * weight),
                blue: partialResult.blue + (rgba.blue * weight),
                alpha: partialResult.alpha + (rgba.alpha * weight)
            )
        }

        let color = UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        let nudgedColor = Self.nudgedHue(color, by: hueNudge)
        return Self.adjustedHSB(
            color: nudgedColor,
            saturationMultiplier: saturationMultiplier,
            brightnessMultiplier: brightnessMultiplier
        )
    }

    private static func rgba(from color: UIColor) -> RGBA {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return RGBA(red: red, green: green, blue: blue, alpha: alpha)
        }

        var white: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return RGBA(red: white, green: white, blue: white, alpha: alpha)
        }

        return RGBA(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    }

    private static func nudgedHue(_ color: UIColor, by amount: CGFloat) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }

        let wrappedHue = (hue + amount).truncatingRemainder(dividingBy: 1)
        return UIColor(
            hue: wrappedHue >= 0 ? wrappedHue : wrappedHue + 1,
            saturation: saturation,
            brightness: brightness,
            alpha: alpha
        )
    }

    private static func adjustedHSB(
        color: UIColor,
        saturationMultiplier: CGFloat,
        brightnessMultiplier: CGFloat
    ) -> UIColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            var white: CGFloat = 0
            guard color.getWhite(&white, alpha: &alpha) else { return color }
            return UIColor(
                white: min(max(white * brightnessMultiplier, 0), 1),
                alpha: alpha
            )
        }

        return UIColor(
            hue: hue,
            saturation: min(max(saturation * saturationMultiplier, 0), 1),
            brightness: min(max(brightness * brightnessMultiplier, 0), 1),
            alpha: alpha
        )
    }
}

enum KeyboardLayoutPreset: String, CaseIterable, Identifiable {
    case compact
    case coding
    case writing
    case web
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "Compact"
        case .coding:
            return "Coding"
        case .writing:
            return "Writing"
        case .web:
            return "Web"
        case .custom:
            return "Custom"
        }
    }

    static func resolved(from rawValue: String?) -> KeyboardLayoutPreset? {
        guard let rawValue else { return nil }

        if let preset = KeyboardLayoutPreset(rawValue: rawValue) {
            return preset
        }

        switch rawValue {
        case KeyboardLegacyStoredValues.legacyCompactPresetAlias:
            return .compact
        default:
            return nil
        }
    }
}

enum KeyboardLayoutLocale: String, CaseIterable, Identifiable, Codable {
    case enUS = "en-US"
    case frFR = "fr-FR"
    case deDE = "de-DE"
    case esES = "es-ES"
    case itIT = "it-IT"
    case ptPT = "pt-PT"
    case nlNL = "nl-NL"
    case svSE = "sv-SE"
    case ar = "ar"
    case he = "he"
    case th = "th"
    case hiDeva = "hi-Deva"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enUS:
            return "English (US)"
        case .frFR:
            return "French"
        case .deDE:
            return "German"
        case .esES:
            return "Spanish"
        case .itIT:
            return "Italian"
        case .ptPT:
            return "Portuguese"
        case .nlNL:
            return "Dutch"
        case .svSE:
            return "Swedish"
        case .ar:
            return "Arabic"
        case .he:
            return "Hebrew"
        case .th:
            return "Thai"
        case .hiDeva:
            return "Hindi (Devanagari)"
        }
    }

    var shortTitle: String {
        switch self {
        case .enUS:
            return "EN-US"
        case .frFR:
            return "FR"
        case .deDE:
            return "DE"
        case .esES:
            return "ES"
        case .itIT:
            return "IT"
        case .ptPT:
            return "PT"
        case .nlNL:
            return "NL"
        case .svSE:
            return "SV"
        case .ar:
            return "AR"
        case .he:
            return "HE"
        case .th:
            return "TH"
        case .hiDeva:
            return "HI"
        }
    }
}

private enum KeyboardLegacyStoredValues {
    // Preserve legacy stored values from older builds while treating the theme as "dark" everywhere else.
    static let legacyDarkThemeAlias = String(
        decoding: [98, 108, 97, 99, 107, 98, 101, 114, 114, 121],
        as: UTF8.self
    )
    static let legacyCompactPresetAlias = legacyDarkThemeAlias
}

enum KeyboardRuntimeLayoutRoute: String, Codable, Equatable {
    case runtimeLocale
    case storedKeymap
}

struct KeyboardKeymap: Codable, Equatable {
    static let defaultQuickInsertRow = ["[]", "()", "{}", ".com"]
    static let defaultLetterTopRow = ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"]
    static let defaultLetterMiddleRow = ["a", "s", "d", "f", "g", "h", "j", "k", "l"]
    static let defaultLetterBottomRow = [
        "z",
        "x",
        "c",
        "v",
        "b",
        "n",
        "m",
        KeyboardSpecialKeyAction.deleteBackward.storageToken
    ]
    static let compactHoldLetterTopRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    static let compactHoldLetterMiddleRow = ["@", "#", "$", "%", "&", "*", "(", ")", "_"]
    static let compactHoldLetterBottomRow = ["!", "?", ":", ";", "/", "\\", "-", ""]
    static let commonSymbolTopRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    static let commonSymbolMiddleRow = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]
    static let commonSymbolBottomRow = [".", ",", "?", "!", "'", "…"]
    static let commonHoldSymbolTopRow = ["¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹", "⁰"]
    static let commonHoldSymbolMiddleRow = ["–", "÷", "…", "·", "[", "]", "¢", "+", "©", "”"]
    static let commonHoldSymbolBottomRow = ["•", "<", "¿", "¡", "’", "`"]
    static let nativeSymbol2TopRow = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="]
    static let nativeSymbol2MiddleRow = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"]
    static let nativeSymbol2BottomRow = [".", ",", "?", "!", "'", "`"]
    static let nativeHoldSymbol2TopRow = ["⟦", "⟧", "⦃", "⦄", "№", "‰", "↑", "×", "±", "≠"]
    static let nativeHoldSymbol2MiddleRow = ["—", "∖", "¦", "≈", "≤", "≥", "¢", "₤", "元", "·"]
    static let nativeHoldSymbol2BottomRow = ["…", ";", "¿", "¡", "‘", "’"]
    static let codingSymbol2TopRow = ["&&", "||", "==", "!=", "<=", ">=", "=>", "->", "::", "??"]
    static let codingSymbol2MiddleRow = ["+=", "-=", "*=", "/=", "%=", "++", "--", "?.", "??=", "..."]
    static let codingSymbol2BottomRow = ["/*", "*/", "//", "\\n", "\\t", "${}", "<>", "[]", "{}", "()"]
    static let codingHoldSymbol2TopRow = ["&=", "|=", "===", "!==", "<", ">", "<=>", "<-", "::", "?:"]
    static let codingHoldSymbol2MiddleRow = ["<<=", ">>=", "**=", "//=", "%", "+=", "-=", "!.", "?:", "…"]
    static let codingHoldSymbol2BottomRow = ["/**", "**/", "///", "\\r", "    ", "\\()", "</>", "[ ]", "{ }", "( )"]
    static let writingSymbol2TopRow = ["“", "”", "‘", "’", "«", "»", "‹", "›", "—", "–"]
    static let writingSymbol2MiddleRow = ["…", "•", "·", "§", "¶", "©", "®", "™", "°", "№"]
    static let writingSymbol2BottomRow = ["¿", "¡", "†", "‡", "※", "✓", "★", "♥", "→", "←"]
    static let writingHoldSymbol2TopRow = ["„", "‟", "‚", "‛", "《", "》", "〈", "〉", "―", "‑"]
    static let writingHoldSymbol2MiddleRow = ["⋯", "◦", "∙", "℠", "℗", "ⓒ", "Ⓡ", "℠", "℃", "℅"]
    static let writingHoldSymbol2BottomRow = ["?", "!", "⁂", "⁕", "⁜", "☑", "☆", "♡", "⇒", "⇐"]
    static let webSymbol2TopRow = ["https://", "http://", "www.", ".com", ".org", ".net", ".io", ".ca", ".co", "@"]
    static let webSymbol2MiddleRow = ["/", "?", "&", "=", "#", "%", "+", "-", "_", ":"]
    static let webSymbol2BottomRow = ["<a>", "</a>", "<div>", "</div>", "<p>", "</p>", "&nbsp;", "&amp;", "&lt;", "&gt;"]
    static let webHoldSymbol2TopRow = ["wss://", "ws://", "ftp://", "localhost", ".edu", ".gov", ".uk", ".us", ".xyz", "mailto:"]
    static let webHoldSymbol2MiddleRow = ["\\", "¿", "&&", "==", "#id", "#top", "%20", "±", "—", ";"]
    static let webHoldSymbol2BottomRow = ["href=", "target=", "class=", "id=", "src=", "alt=", "&copy;", "&quot;", "&#60;", "&#62;"]
    static let codingHoldSymbolTopRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    static let codingHoldSymbolMiddleRow = ["[", "]", "{", "}", "<", ">", "^", "`", "~", "|"]
    static let codingHoldSymbolBottomRow = [".", ",", "_", "=", "+", "-", "*", "/", "\\", ""]
    static let writingHoldSymbolTopRow = ["[", "]", "{", "}", "<", ">", "^", "`", "~", "|"]
    static let writingHoldSymbolMiddleRow = [".", ",", "<", ">", "[", "]", "{", "}", "|", "~"]
    static let writingHoldSymbolBottomRow = ["_", "=", "+", "-", "*", "/", "\\", "%", "&", ""]
    static let webHoldSymbolTopRow = [".com", ".net", ".org", "www", "/", ".", "?", "&", "=", "#"]
    static let webHoldSymbolMiddleRow = ["-", "_", "@", "#", ":", "/", "?", "&", "=", "."]
    static let webHoldSymbolBottomRow = ["[", "]", "{", "}", "<", ">", "|", "~", "\\", ""]
    static let defaultSymbolUtilityRow = [
        KeyboardSpecialKeyAction.toggleLayer.storageToken,
        KeyboardSpecialKeyAction.toggleSymbolPage.storageToken,
        KeyboardSpecialKeyAction.tab.storageToken,
        KeyboardSpecialKeyAction.moveLeft.storageToken,
        KeyboardSpecialKeyAction.space.storageToken,
        KeyboardSpecialKeyAction.moveRight.storageToken,
        KeyboardSpecialKeyAction.enter.storageToken,
    ]
    static let defaultLetterUtilityRow = [
        KeyboardSpecialKeyAction.toggleLayer.storageToken,
        KeyboardSpecialKeyAction.deleteForward.storageToken,
        KeyboardSpecialKeyAction.space.storageToken,
    ]
    static let defaultTrailingUtilityRow = [
        KeyboardSpecialKeyAction.deleteBackward.storageToken,
        KeyboardSpecialKeyAction.menu.storageToken,
    ]
    static let defaultExpandedLetterTrailingUtilityRow = [
        KeyboardSpecialKeyAction.enter.storageToken,
        KeyboardSpecialKeyAction.menu.storageToken,
    ]
    static let defaultLetterBottomLeadingRow = [
        KeyboardSpecialKeyAction.shift.storageToken
    ]

    var schemaVersion: Int
    var rows: [KeyboardLayoutRow]
    var quickInsertRow: [String]
    var holdQuickInsertRow: [String]
    var toolbarRow: [String]
    var holdToolbarRow: [String]
    var symbolTopRow: [String]
    var holdSymbolTopRow: [String]
    var symbolMiddleRow: [String]
    var holdSymbolMiddleRow: [String]
    var symbolBottomRow: [String]
    var holdSymbolBottomRow: [String]
    var letterTopRow: [String]
    var holdLetterTopRow: [String]
    var letterMiddleRow: [String]
    var holdLetterMiddleRow: [String]
    var letterBottomRow: [String]
    var holdLetterBottomRow: [String]
    var symbolUtilityRow: [String]
    var letterUtilityRow: [String]
    var trailingUtilityRow: [String]
    var expandedTrailingUtilityRow: [String]
    var expandedLetterTrailingUtilityRow: [String]
    var letterBottomLeadingRow: [String]

    var customAddedRows: [KeyboardLayoutRow]
    var customLayers: [KeyboardCustomLayer]
    var keyDimensionOverrides: [String: KeyboardLayoutKeyDimensions]

    static let `default` = KeyboardKeymap.preset(.compact)

    init(
        quickInsertRow: [String] = KeyboardKeymap.defaultQuickInsertRow,
        holdQuickInsertRow: [String] = [],
        toolbarRow: [String],
        holdToolbarRow: [String] = [],
        symbolTopRow: [String],
        holdSymbolTopRow: [String] = [],
        symbolMiddleRow: [String],
        holdSymbolMiddleRow: [String] = [],
        symbolBottomRow: [String],
        holdSymbolBottomRow: [String] = [],
        letterTopRow: [String],
        holdLetterTopRow: [String] = [],
        letterMiddleRow: [String],
        holdLetterMiddleRow: [String] = [],
        letterBottomRow: [String],
        holdLetterBottomRow: [String] = [],
        symbolUtilityRow: [String] = KeyboardKeymap.defaultSymbolUtilityRow,
        letterUtilityRow: [String] = KeyboardKeymap.defaultLetterUtilityRow,
        trailingUtilityRow: [String] = KeyboardKeymap.defaultTrailingUtilityRow,
        expandedTrailingUtilityRow: [String] = KeyboardKeymap.defaultTrailingUtilityRow,
        expandedLetterTrailingUtilityRow: [String] = KeyboardKeymap.defaultExpandedLetterTrailingUtilityRow,
        letterBottomLeadingRow: [String] = KeyboardKeymap.defaultLetterBottomLeadingRow,
        customAddedRows: [KeyboardLayoutRow] = [],
        customLayers: [KeyboardCustomLayer] = [],
        keyDimensionOverrides: [String: KeyboardLayoutKeyDimensions] = [:],
        schemaVersion: Int = HWKLayoutSchemaVersion.current,
        rows: [KeyboardLayoutRow]? = nil
    ) {
        self.schemaVersion = HWKLayoutSchemaVersion.current
        self.quickInsertRow = quickInsertRow
        self.holdQuickInsertRow = holdQuickInsertRow
        self.toolbarRow = toolbarRow
        self.holdToolbarRow = holdToolbarRow
        self.symbolTopRow = symbolTopRow
        self.holdSymbolTopRow = holdSymbolTopRow
        self.symbolMiddleRow = symbolMiddleRow
        self.holdSymbolMiddleRow = holdSymbolMiddleRow
        self.symbolBottomRow = symbolBottomRow
        self.holdSymbolBottomRow = holdSymbolBottomRow
        self.letterTopRow = letterTopRow
        self.holdLetterTopRow = holdLetterTopRow
        self.letterMiddleRow = letterMiddleRow
        self.holdLetterMiddleRow = holdLetterMiddleRow
        self.letterBottomRow = letterBottomRow
        self.holdLetterBottomRow = holdLetterBottomRow
        self.symbolUtilityRow = symbolUtilityRow
        self.letterUtilityRow = letterUtilityRow
        self.trailingUtilityRow = trailingUtilityRow
        self.expandedTrailingUtilityRow = expandedTrailingUtilityRow
        self.expandedLetterTrailingUtilityRow = expandedLetterTrailingUtilityRow
        self.letterBottomLeadingRow = letterBottomLeadingRow
        self.customAddedRows = customAddedRows
        self.customLayers = []
        self.keyDimensionOverrides = keyDimensionOverrides
        self.rows = Self.normalizedRows(
            rows ?? Self.makeRowsFromLegacyFields(
                quickInsertRow: quickInsertRow,
                holdQuickInsertRow: holdQuickInsertRow,
                toolbarRow: toolbarRow,
                holdToolbarRow: holdToolbarRow,
                symbolTopRow: symbolTopRow,
                holdSymbolTopRow: holdSymbolTopRow,
                symbolMiddleRow: symbolMiddleRow,
                holdSymbolMiddleRow: holdSymbolMiddleRow,
                symbolBottomRow: symbolBottomRow,
                holdSymbolBottomRow: holdSymbolBottomRow,
                letterTopRow: letterTopRow,
                holdLetterTopRow: holdLetterTopRow,
                letterMiddleRow: letterMiddleRow,
                holdLetterMiddleRow: holdLetterMiddleRow,
                letterBottomRow: letterBottomRow,
                holdLetterBottomRow: holdLetterBottomRow,
                symbolUtilityRow: symbolUtilityRow,
                letterUtilityRow: letterUtilityRow,
                trailingUtilityRow: trailingUtilityRow,
                expandedTrailingUtilityRow: expandedTrailingUtilityRow,
                expandedLetterTrailingUtilityRow: expandedLetterTrailingUtilityRow,
                letterBottomLeadingRow: letterBottomLeadingRow,
                customAddedRows: customAddedRows,
                keyDimensionOverrides: keyDimensionOverrides
            )
        )
        self.customLayers = Self.normalizedCustomLayers(customLayers, rows: self.rows)
        self.rows = Self.rowsRemovingDiscardedCustomLayerRows(self.rows, layers: self.customLayers)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case rows
        case quickInsertRow
        case holdQuickInsertRow
        case toolbarRow
        case holdToolbarRow
        case symbolTopRow
        case holdSymbolTopRow
        case symbolMiddleRow
        case holdSymbolMiddleRow
        case symbolBottomRow
        case holdSymbolBottomRow
        case letterTopRow
        case holdLetterTopRow
        case letterMiddleRow
        case holdLetterMiddleRow
        case letterBottomRow
        case holdLetterBottomRow
        case symbolUtilityRow
        case letterUtilityRow
        case trailingUtilityRow
        case expandedTrailingUtilityRow
        case expandedLetterTrailingUtilityRow
        case letterBottomLeadingRow
        case customAddedRows
        case customLayers
        case keyDimensionOverrides
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedRows = try container.decodeIfPresent([KeyboardLayoutRow].self, forKey: .rows)
        schemaVersion = HWKLayoutSchemaVersion.current
        quickInsertRow = try container.decodeIfPresent([String].self, forKey: .quickInsertRow)
            ?? KeyboardKeymap.defaultQuickInsertRow
        holdQuickInsertRow = try container.decodeIfPresent([String].self, forKey: .holdQuickInsertRow) ?? []
        toolbarRow = try container.decodeIfPresent([String].self, forKey: .toolbarRow) ?? []
        holdToolbarRow = try container.decodeIfPresent([String].self, forKey: .holdToolbarRow) ?? []
        symbolTopRow = try container.decodeIfPresent([String].self, forKey: .symbolTopRow) ?? []
        holdSymbolTopRow = try container.decodeIfPresent([String].self, forKey: .holdSymbolTopRow) ?? []
        symbolMiddleRow = try container.decodeIfPresent([String].self, forKey: .symbolMiddleRow) ?? []
        holdSymbolMiddleRow = try container.decodeIfPresent([String].self, forKey: .holdSymbolMiddleRow) ?? []
        symbolBottomRow = try container.decodeIfPresent([String].self, forKey: .symbolBottomRow) ?? []
        holdSymbolBottomRow = try container.decodeIfPresent([String].self, forKey: .holdSymbolBottomRow) ?? []
        letterTopRow = try container.decodeIfPresent([String].self, forKey: .letterTopRow) ?? []
        holdLetterTopRow = try container.decodeIfPresent([String].self, forKey: .holdLetterTopRow) ?? []
        letterMiddleRow = try container.decodeIfPresent([String].self, forKey: .letterMiddleRow) ?? []
        holdLetterMiddleRow = try container.decodeIfPresent([String].self, forKey: .holdLetterMiddleRow) ?? []
        letterBottomRow = try container.decodeIfPresent([String].self, forKey: .letterBottomRow) ?? []
        holdLetterBottomRow = try container.decodeIfPresent([String].self, forKey: .holdLetterBottomRow) ?? []
        symbolUtilityRow = try container.decodeIfPresent([String].self, forKey: .symbolUtilityRow)
            ?? KeyboardKeymap.defaultSymbolUtilityRow
        letterUtilityRow = try container.decodeIfPresent([String].self, forKey: .letterUtilityRow)
            ?? KeyboardKeymap.defaultLetterUtilityRow
        let decodedTrailingUtilityRow = try container.decodeIfPresent([String].self, forKey: .trailingUtilityRow)
            ?? KeyboardKeymap.defaultTrailingUtilityRow
        trailingUtilityRow = decodedTrailingUtilityRow
        expandedTrailingUtilityRow = try container.decodeIfPresent([String].self, forKey: .expandedTrailingUtilityRow)
            ?? KeyboardKeymap.defaultTrailingUtilityRow
        expandedLetterTrailingUtilityRow = try container.decodeIfPresent(
            [String].self,
            forKey: .expandedLetterTrailingUtilityRow
        ) ?? KeyboardKeymap.defaultExpandedLetterTrailingUtilityRow
        letterBottomLeadingRow = try container.decodeIfPresent([String].self, forKey: .letterBottomLeadingRow)
            ?? KeyboardKeymap.defaultLetterBottomLeadingRow
        customAddedRows = Self.normalizedCustomRows(
            try container.decodeIfPresent([KeyboardLayoutRow].self, forKey: .customAddedRows) ?? []
        )
        let decodedCustomLayers = try container.decodeIfPresent(
            [KeyboardCustomLayer].self,
            forKey: .customLayers
        ) ?? []
        customLayers = []
        keyDimensionOverrides = Self.normalizedKeyDimensionOverrides(
            try container.decodeIfPresent(
                [String: KeyboardLayoutKeyDimensions].self,
                forKey: .keyDimensionOverrides
            ) ?? [:]
        )
        if let decodedRows, !decodedRows.isEmpty {
            var migratedRows = Self.normalizedRows(decodedRows)
            if !migratedRows.contains(where: { $0.customLayerID == nil && $0.surface == .symbols2 }) {
                migratedRows.append(contentsOf: Self.nativeSymbol2Rows(
                    symbolUtilityRow: symbolUtilityRow,
                    expandedTrailingUtilityRow: expandedTrailingUtilityRow,
                    keyDimensionOverrides: keyDimensionOverrides
                ))
            }
            migratedRows = Self.rowsEnsuringNativeSymbolPageActions(migratedRows)
            rows = Self.rowsAssigningCustomLayerIDs(
                migratedRows,
                layers: decodedCustomLayers
            )
            applyRowsToLegacyFields()
        } else {
            rows = Self.normalizedRows(
                Self.makeRowsFromLegacyFields(
                    quickInsertRow: quickInsertRow,
                    holdQuickInsertRow: holdQuickInsertRow,
                    toolbarRow: toolbarRow,
                    holdToolbarRow: holdToolbarRow,
                    symbolTopRow: symbolTopRow,
                    holdSymbolTopRow: holdSymbolTopRow,
                    symbolMiddleRow: symbolMiddleRow,
                    holdSymbolMiddleRow: holdSymbolMiddleRow,
                    symbolBottomRow: symbolBottomRow,
                    holdSymbolBottomRow: holdSymbolBottomRow,
                    letterTopRow: letterTopRow,
                    holdLetterTopRow: holdLetterTopRow,
                    letterMiddleRow: letterMiddleRow,
                    holdLetterMiddleRow: holdLetterMiddleRow,
                    letterBottomRow: letterBottomRow,
                    holdLetterBottomRow: holdLetterBottomRow,
                    symbolUtilityRow: symbolUtilityRow,
                    letterUtilityRow: letterUtilityRow,
                    trailingUtilityRow: trailingUtilityRow,
                    expandedTrailingUtilityRow: expandedTrailingUtilityRow,
                    expandedLetterTrailingUtilityRow: expandedLetterTrailingUtilityRow,
                    letterBottomLeadingRow: letterBottomLeadingRow,
                    customAddedRows: customAddedRows,
                    keyDimensionOverrides: keyDimensionOverrides
                )
            )
        }
        customLayers = Self.normalizedCustomLayers(decodedCustomLayers, rows: rows)
        rows = Self.rowsRemovingDiscardedCustomLayerRows(rows, layers: customLayers)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(HWKLayoutSchemaVersion.current, forKey: .schemaVersion)
        try container.encode(rowsSynchronizedFromLegacyFields(), forKey: .rows)
        try container.encode(quickInsertRow, forKey: .quickInsertRow)
        try container.encode(holdQuickInsertRow, forKey: .holdQuickInsertRow)
        try container.encode(toolbarRow, forKey: .toolbarRow)
        try container.encode(holdToolbarRow, forKey: .holdToolbarRow)
        try container.encode(symbolTopRow, forKey: .symbolTopRow)
        try container.encode(holdSymbolTopRow, forKey: .holdSymbolTopRow)
        try container.encode(symbolMiddleRow, forKey: .symbolMiddleRow)
        try container.encode(holdSymbolMiddleRow, forKey: .holdSymbolMiddleRow)
        try container.encode(symbolBottomRow, forKey: .symbolBottomRow)
        try container.encode(holdSymbolBottomRow, forKey: .holdSymbolBottomRow)
        try container.encode(letterTopRow, forKey: .letterTopRow)
        try container.encode(holdLetterTopRow, forKey: .holdLetterTopRow)
        try container.encode(letterMiddleRow, forKey: .letterMiddleRow)
        try container.encode(holdLetterMiddleRow, forKey: .holdLetterMiddleRow)
        try container.encode(letterBottomRow, forKey: .letterBottomRow)
        try container.encode(holdLetterBottomRow, forKey: .holdLetterBottomRow)
        try container.encode(symbolUtilityRow, forKey: .symbolUtilityRow)
        try container.encode(letterUtilityRow, forKey: .letterUtilityRow)
        try container.encode(trailingUtilityRow, forKey: .trailingUtilityRow)
        try container.encode(expandedTrailingUtilityRow, forKey: .expandedTrailingUtilityRow)
        try container.encode(expandedLetterTrailingUtilityRow, forKey: .expandedLetterTrailingUtilityRow)
        try container.encode(letterBottomLeadingRow, forKey: .letterBottomLeadingRow)
        if !customAddedRows.isEmpty {
            try container.encode(customAddedRows, forKey: .customAddedRows)
        }
        if !customLayers.isEmpty {
            try container.encode(customLayers, forKey: .customLayers)
        }
        if !keyDimensionOverrides.isEmpty {
            try container.encode(keyDimensionOverrides, forKey: .keyDimensionOverrides)
        }
    }

    static func preset(_ preset: KeyboardLayoutPreset) -> KeyboardKeymap {
        let baseKeymap: KeyboardKeymap
        switch preset {
        case .compact, .custom:
            baseKeymap = KeyboardKeymap(
                quickInsertRow: defaultQuickInsertRow,
                toolbarRow: [".com", ",", "'", "!", "?", ".", "@", "#"],
                symbolTopRow: commonSymbolTopRow,
                holdSymbolTopRow: commonHoldSymbolTopRow,
                symbolMiddleRow: commonSymbolMiddleRow,
                holdSymbolMiddleRow: commonHoldSymbolMiddleRow,
                symbolBottomRow: commonSymbolBottomRow,
                holdSymbolBottomRow: commonHoldSymbolBottomRow,
                letterTopRow: defaultLetterTopRow,
                holdLetterTopRow: compactHoldLetterTopRow,
                letterMiddleRow: defaultLetterMiddleRow,
                holdLetterMiddleRow: compactHoldLetterMiddleRow,
                letterBottomRow: defaultLetterBottomRow,
                holdLetterBottomRow: compactHoldLetterBottomRow,
                symbolUtilityRow: defaultSymbolUtilityRow,
                letterUtilityRow: defaultLetterUtilityRow,
                trailingUtilityRow: defaultTrailingUtilityRow,
                expandedTrailingUtilityRow: defaultTrailingUtilityRow,
                expandedLetterTrailingUtilityRow: defaultExpandedLetterTrailingUtilityRow,
                letterBottomLeadingRow: defaultLetterBottomLeadingRow
            )
        case .coding:
            baseKeymap = KeyboardKeymap(
                quickInsertRow: defaultQuickInsertRow,
                toolbarRow: ["{", "}", "[", "]", "(", ")", "<", ">"],
                symbolTopRow: ["{", "}", "[", "]", "(", ")", "<", ">", "/", "\\"],
                holdSymbolTopRow: codingHoldSymbolTopRow,
                symbolMiddleRow: ["@", "#", "$", "%", "&", "*", "_", "=", "+", "|"],
                holdSymbolMiddleRow: codingHoldSymbolMiddleRow,
                symbolBottomRow: ["!", "?", ":", ";", ".", ",", "-", "\"", "'", "~"],
                holdSymbolBottomRow: codingHoldSymbolBottomRow,
                letterTopRow: defaultLetterTopRow,
                holdLetterTopRow: ["{", "}", "[", "]", "(", ")", "<", ">", "/", "\\"],
                letterMiddleRow: defaultLetterMiddleRow,
                holdLetterMiddleRow: ["@", "#", "$", "%", "&", "*", "_", "=", "+", "|"],
                letterBottomRow: defaultLetterBottomRow,
                holdLetterBottomRow: ["!", "?", ":", ";", ".", ",", "-", "\""],
                symbolUtilityRow: defaultSymbolUtilityRow,
                letterUtilityRow: defaultLetterUtilityRow,
                trailingUtilityRow: defaultTrailingUtilityRow,
                expandedTrailingUtilityRow: defaultTrailingUtilityRow,
                expandedLetterTrailingUtilityRow: defaultExpandedLetterTrailingUtilityRow,
                letterBottomLeadingRow: defaultLetterBottomLeadingRow
            )
        case .writing:
            baseKeymap = KeyboardKeymap(
                quickInsertRow: defaultQuickInsertRow,
                toolbarRow: [".com", ",", "'", "\"", "!", "?", ":", ";"],
                symbolTopRow: commonSymbolTopRow,
                holdSymbolTopRow: writingHoldSymbolTopRow,
                symbolMiddleRow: [",", ".", "'", "\"", "!", "?", ":", ";", "-", "("],
                holdSymbolMiddleRow: writingHoldSymbolMiddleRow,
                symbolBottomRow: [")", "/", "&", "@", "#", "$", "%", "+", "=", "*"],
                holdSymbolBottomRow: writingHoldSymbolBottomRow,
                letterTopRow: defaultLetterTopRow,
                holdLetterTopRow: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                letterMiddleRow: defaultLetterMiddleRow,
                holdLetterMiddleRow: [",", ".", "'", "\"", "!", "?", ":", ";", "-", "("],
                letterBottomRow: defaultLetterBottomRow,
                holdLetterBottomRow: [")", "/", "&", "@", "#", "$", "%", "+"],
                symbolUtilityRow: defaultSymbolUtilityRow,
                letterUtilityRow: defaultLetterUtilityRow,
                trailingUtilityRow: defaultTrailingUtilityRow,
                expandedTrailingUtilityRow: defaultTrailingUtilityRow,
                expandedLetterTrailingUtilityRow: defaultExpandedLetterTrailingUtilityRow,
                letterBottomLeadingRow: defaultLetterBottomLeadingRow
            )
        case .web:
            baseKeymap = KeyboardKeymap(
                quickInsertRow: defaultQuickInsertRow,
                toolbarRow: [".com", "/", "-", "_", "@", "#", ".", "?"],
                symbolTopRow: ["@", "#", "/", ".", ":", "-", "_", "?", "&", "="],
                holdSymbolTopRow: webHoldSymbolTopRow,
                symbolMiddleRow: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                holdSymbolMiddleRow: webHoldSymbolMiddleRow,
                symbolBottomRow: [".com", ".net", ".org", "/", "-", "_", "@", "#", "?", "&"],
                holdSymbolBottomRow: webHoldSymbolBottomRow,
                letterTopRow: defaultLetterTopRow,
                holdLetterTopRow: ["@", "#", "/", ".", ":", "-", "_", "?", "&", "="],
                letterMiddleRow: defaultLetterMiddleRow,
                holdLetterMiddleRow: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
                letterBottomRow: defaultLetterBottomRow,
                holdLetterBottomRow: [".com", ".net", ".org", "/", "-", "_", "@", "#"],
                symbolUtilityRow: defaultSymbolUtilityRow,
                letterUtilityRow: defaultLetterUtilityRow,
                trailingUtilityRow: defaultTrailingUtilityRow,
                expandedTrailingUtilityRow: defaultTrailingUtilityRow,
                expandedLetterTrailingUtilityRow: defaultExpandedLetterTrailingUtilityRow,
                letterBottomLeadingRow: defaultLetterBottomLeadingRow
            )
        }

        var expandedKeymap = baseKeymap
        expandedKeymap.replacePresetSymbol2Content(for: preset)
        return expandedKeymap
    }
}

extension KeyboardKeymap {
    private static let protectedSingletonKinds: Set<KeyboardRowKind> = [
        .quickInsert,
        .toolbar,
        .symbolUtility,
        .letterUtility,
        .trailingUtility,
        .expandedTrailingUtility,
        .expandedLetterTrailingUtility,
        .letterBottomLeading
    ]
    private static let customLayerMaxKeysPerRow = KeyboardLayoutBounds.expandedCountRange.upperBound

    func rows(surface: KeyboardRowSurface, holdLayer: Bool) -> [KeyboardLayoutRow] {
        rows.filter { $0.customLayerID == nil && $0.surface == surface && $0.holdLayer == holdLayer }
    }

    func customLayerRows(for id: UUID?) -> [KeyboardLayoutRow] {
        guard let layer = customLayer(for: id) else { return [] }
        let rowsByID = Self.rowsByIDAllowingDuplicateIDs(rows)
        return layer.rowIDs.compactMap { rowID in
            guard let row = rowsByID[rowID] else { return nil }
            return row.customLayerID == layer.id || row.customLayerID == nil ? row : nil
        }
    }

    mutating func insertRow(_ row: KeyboardLayoutRow, after rowID: UUID?) {
        let surfaceRows = rows(surface: row.surface, holdLayer: row.holdLayer)
        let editableSurfaceRows = surfaceRows.filter { !Self.protectedSingletonKinds.contains($0.kind) }
        guard editableSurfaceRows.count < KeyboardLayoutBounds.maxRowsPerSurface else { return }
        if Self.protectedSingletonKinds.contains(row.kind),
           rows.contains(where: { $0.kind == row.kind && $0.surface == row.surface && $0.holdLayer == row.holdLayer }) {
            return
        }

        var nextRow = Self.normalizedRow(row)
        if nextRow.keys.isEmpty {
            nextRow.keys = [KeyboardLayoutKey(tap: "")]
        }

        if let rowID, let index = rows.firstIndex(where: { $0.id == rowID }) {
            rows.insert(nextRow, at: rows.index(after: index))
        } else if let lastSurfaceIndex = rows.indices.reversed().first(where: {
            rows[$0].surface == nextRow.surface && rows[$0].holdLayer == nextRow.holdLayer
        }) {
            rows.insert(nextRow, at: rows.index(after: lastSurfaceIndex))
        } else {
            rows.append(nextRow)
        }
        applyRowsToLegacyFields()
    }

    mutating func removeRow(id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let row = rows[index]
        if Self.protectedSingletonKinds.contains(row.kind) {
            return
        }

        rows.remove(at: index)
        applyRowsToLegacyFields()
    }

    mutating func moveRow(id: UUID, to index: Int, surface: KeyboardRowSurface) {
        guard let sourceIndex = rows.firstIndex(where: { $0.id == id }) else { return }
        var row = rows.remove(at: sourceIndex)
        row.surface = surface
        let matchingIndices = rows.indices.filter { rows[$0].surface == surface && rows[$0].holdLayer == row.holdLayer }
        let clampedIndex = min(max(index, 0), matchingIndices.count)
        if clampedIndex == matchingIndices.count {
            if let last = matchingIndices.last {
                rows.insert(row, at: rows.index(after: last))
            } else {
                rows.append(row)
            }
        } else {
            rows.insert(row, at: matchingIndices[clampedIndex])
        }
        applyRowsToLegacyFields()
    }

    mutating func replaceRows(_ nextRows: [KeyboardLayoutRow]) {
        rows = Self.normalizedRows(nextRows)
        applyRowsToLegacyFields()
    }

    mutating func applyPresetLayer(
        from template: KeyboardKeymap,
        to surface: KeyboardRowSurface,
        customLayerID: UUID?
    ) {
        let eligibleKinds = Self.presetEditableKinds(for: surface)
        let sourceRows = template.rows.filter {
            $0.customLayerID == nil && $0.surface == surface && eligibleKinds.contains($0.kind)
        }
        guard !sourceRows.isEmpty else { return }

        var nextRows = rows
        let targetIndices = nextRows.indices.filter { index in
            let row = nextRows[index]
            let ownsTarget = customLayerID.map { row.customLayerID == $0 }
                ?? (row.customLayerID == nil && row.surface == surface)
            return ownsTarget && eligibleKinds.contains(row.kind)
        }

        for index in targetIndices {
            guard let sourceRow = sourceRows.first(where: { $0.kind == nextRows[index].kind }) else {
                continue
            }
            nextRows[index].keys = Self.presetKeys(
                taps: sourceRow.keys.map(\.tap),
                holds: sourceRow.keys.map { $0.hold ?? "" },
                preserving: nextRows[index].keys
            )
        }

        replaceRows(nextRows)
    }

    private mutating func replacePresetSymbol2Content(for preset: KeyboardLayoutPreset) {
        let content = Self.presetSymbol2Content(for: preset)
        let rowsByKind: [(KeyboardRowKind, [String], [String])] = [
            (.symbolTop, content.taps[0], content.holds[0]),
            (.symbolMiddle, content.taps[1], content.holds[1]),
            (.symbolBottom, content.taps[2], content.holds[2]),
        ]
        var nextRows = rows

        for (kind, taps, holds) in rowsByKind {
            guard let index = nextRows.firstIndex(where: {
                $0.customLayerID == nil && $0.surface == .symbols2 && $0.kind == kind
            }) else { continue }
            nextRows[index].keys = Self.presetKeys(
                taps: taps,
                holds: holds,
                preserving: nextRows[index].keys
            )
        }

        rows = Self.normalizedRows(nextRows)
    }

    private static func presetEditableKinds(for surface: KeyboardRowSurface) -> Set<KeyboardRowKind> {
        switch surface {
        case .mainRow:
            return [.quickInsert, .toolbar]
        case .symbols1, .symbols2:
            return [.symbolTop, .symbolMiddle, .symbolBottom]
        case .letters:
            return [.letterTop, .letterMiddle, .letterBottom]
        }
    }

    private static func presetKeys(
        taps: [String],
        holds: [String],
        preserving existing: [KeyboardLayoutKey]
    ) -> [KeyboardLayoutKey] {
        let count = min(max(taps.count, holds.count), KeyboardLayoutBounds.maxKeysPerRow)
        return (0..<count).map { index in
            let oldKey = existing.indices.contains(index) ? existing[index] : nil
            let tap = taps.indices.contains(index) ? taps[index] : ""
            let hold = holds.indices.contains(index) ? holds[index] : ""
            return KeyboardLayoutKey(
                id: oldKey?.id ?? UUID(),
                tap: tap,
                hold: hold.isEmpty ? nil : hold,
                widthWeight: oldKey?.widthWeight ?? 1,
                heightOverride: oldKey?.heightOverride
            )
        }
    }

    private static func presetSymbol2Content(
        for preset: KeyboardLayoutPreset
    ) -> (taps: [[String]], holds: [[String]]) {
        switch preset {
        case .compact, .custom:
            return (
                [nativeSymbol2TopRow, nativeSymbol2MiddleRow, nativeSymbol2BottomRow],
                [nativeHoldSymbol2TopRow, nativeHoldSymbol2MiddleRow, nativeHoldSymbol2BottomRow]
            )
        case .coding:
            return (
                [codingSymbol2TopRow, codingSymbol2MiddleRow, codingSymbol2BottomRow],
                [codingHoldSymbol2TopRow, codingHoldSymbol2MiddleRow, codingHoldSymbol2BottomRow]
            )
        case .writing:
            return (
                [writingSymbol2TopRow, writingSymbol2MiddleRow, writingSymbol2BottomRow],
                [writingHoldSymbol2TopRow, writingHoldSymbol2MiddleRow, writingHoldSymbol2BottomRow]
            )
        case .web:
            return (
                [webSymbol2TopRow, webSymbol2MiddleRow, webSymbol2BottomRow],
                [webHoldSymbol2TopRow, webHoldSymbol2MiddleRow, webHoldSymbol2BottomRow]
            )
        }
    }

    mutating func setKeyDimensions(
        rowID: UUID,
        keyID: UUID,
        widthWeight: CGFloat,
        heightOverride: CGFloat?
    ) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowID }),
              let keyIndex = rows[rowIndex].keys.firstIndex(where: { $0.id == keyID }) else {
            return
        }

        rows[rowIndex].keys[keyIndex].widthWeight = KeyboardLayoutBounds.clampedPerKeyWidthWeight(widthWeight)
        rows[rowIndex].keys[keyIndex].heightOverride = heightOverride.map(KeyboardLayoutBounds.clampedPerKeyHeight)
        applyRowsToLegacyFields()
    }

    func keyDimensions(
        surface: KeyboardRowSurface,
        kind: KeyboardRowKind,
        holdLayer: Bool,
        slotIndex: Int
    ) -> KeyboardLayoutKeyDimensions {
        let key = KeyboardLayoutDimensionKey.legacyKey(
            surface: surface,
            kind: kind,
            holdLayer: holdLayer,
            slotIndex: slotIndex
        )
        return keyDimensionOverrides[key] ?? .identity
    }

    mutating func setLegacyKeyDimensions(
        surface: KeyboardRowSurface,
        kind: KeyboardRowKind,
        holdLayer: Bool,
        slotIndex: Int,
        dimensions: KeyboardLayoutKeyDimensions
    ) {
        let key = KeyboardLayoutDimensionKey.legacyKey(
            surface: surface,
            kind: kind,
            holdLayer: holdLayer,
            slotIndex: slotIndex
        )
        if dimensions == .identity {
            keyDimensionOverrides.removeValue(forKey: key)
        } else {
            keyDimensionOverrides[key] = dimensions
        }
    }

    mutating func setCustomKeyDimensions(
        rowID: UUID,
        keyID: UUID,
        dimensions: KeyboardLayoutKeyDimensions
    ) {
        let key = KeyboardLayoutDimensionKey.customKey(rowID: rowID, keyID: keyID)
        if dimensions == .identity {
            keyDimensionOverrides.removeValue(forKey: key)
        } else {
            keyDimensionOverrides[key] = dimensions
        }
    }

    mutating func insertCustomRow(_ row: KeyboardLayoutRow) {
        insertRow(row, after: nil)
    }

    mutating func removeCustomRow(id: UUID) {
        removeRow(id: id)
        removeCustomRowDimensions(rowID: id)
    }

    mutating func removeCustomRowDimensions(rowID: UUID) {
        let prefix = "custom:\(rowID.uuidString):"
        keyDimensionOverrides = keyDimensionOverrides.filter { !$0.key.hasPrefix(prefix) }
    }

    mutating func removeCustomKeyDimensions(rowID: UUID, keyID: UUID) {
        keyDimensionOverrides.removeValue(forKey: KeyboardLayoutDimensionKey.customKey(rowID: rowID, keyID: keyID))
    }

    @discardableResult
    mutating func addCustomLayer(
        surface: KeyboardRowSurface,
        title: String? = nil,
        iconSystemName: String = KeyboardCustomLayer.defaultIconSystemName
    ) -> KeyboardCustomLayer {
        let targetSurface = surface
        let layerID = UUID()
        let sourceRows = customLayerSourceRows(surface: targetSurface)
        let clonedRows = sourceRows.map { sourceRow -> KeyboardLayoutRow in
            var row = sourceRow
            row.id = UUID()
            row.customLayerID = layerID
            let blanksPrimaryKeys = Self.isCustomLayerPrimaryRow(sourceRow)
            row.keys = sourceRow.keys.prefix(Self.customLayerMaxKeysPerRow).map { key in
                KeyboardLayoutKey(
                    tap: blanksPrimaryKeys ? "" : key.tap,
                    hold: blanksPrimaryKeys ? nil : key.hold,
                    widthWeight: key.widthWeight,
                    heightOverride: key.heightOverride
                )
            }
            while row.keys.count < KeyboardLayoutBounds.expandedCountRange.lowerBound {
                row.keys.append(KeyboardLayoutKey(tap: "", hold: nil))
            }
            return Self.normalizedRow(row)
        }
        rows.append(contentsOf: clonedRows)
        let layer = KeyboardCustomLayer(
            id: layerID,
            title: title ?? "Layer \(customLayers.count + 1)",
            iconSystemName: iconSystemName,
            surface: targetSurface,
            rowIDs: clonedRows.map(\.id)
        )
        customLayers = Self.normalizedCustomLayers(customLayers + [layer], rows: rows)
        return customLayers.first(where: { $0.id == layer.id }) ?? layer
    }

    private func customLayerSourceRows(surface: KeyboardRowSurface) -> [KeyboardLayoutRow] {
        let targetSurface = surface
        let primaryKinds: [KeyboardRowKind]
        let utilityKind: KeyboardRowKind?
        let trailingKind: KeyboardRowKind?

        switch surface {
        case .mainRow:
            primaryKinds = [.toolbar]
            utilityKind = nil
            trailingKind = nil
        case .symbols1, .symbols2:
            primaryKinds = [.symbolTop, .symbolMiddle, .symbolBottom]
            utilityKind = .symbolUtility
            trailingKind = .expandedTrailingUtility
        case .letters:
            primaryKinds = [.letterTop, .letterMiddle, .letterBottom]
            utilityKind = .letterUtility
            trailingKind = .expandedLetterTrailingUtility
        }

        let primaryRows = primaryKinds.compactMap { customLayerSourceRow(kind: $0, surface: targetSurface) }

        guard let utilityKind,
              var utilityRow = customLayerSourceRow(
                kind: utilityKind,
                surface: targetSurface
              ) else {
            return primaryRows
        }

        if let trailingKind,
           let trailingRow = customLayerSourceRow(
            kind: trailingKind,
            surface: targetSurface
           ) {
            utilityRow.keys.append(contentsOf: trailingRow.keys)
        }
        utilityRow.keys = Array(utilityRow.keys.prefix(Self.customLayerMaxKeysPerRow))
        return primaryRows + [utilityRow]
    }

    private func customLayerSourceRow(kind: KeyboardRowKind, surface: KeyboardRowSurface) -> KeyboardLayoutRow? {
        rows.first {
            $0.customLayerID == nil &&
                $0.kind == kind &&
                $0.surface == surface &&
            !$0.holdLayer
        }
    }

    private static func isCustomLayerPrimaryRow(_ row: KeyboardLayoutRow) -> Bool {
        row.kind == .toolbar ||
            row.kind == .symbolTop ||
            row.kind == .symbolMiddle ||
            row.kind == .symbolBottom ||
            row.kind == .letterTop ||
            row.kind == .letterMiddle ||
            row.kind == .letterBottom
    }

    mutating func renameCustomLayer(id: UUID, title: String) {
        guard let index = customLayers.firstIndex(where: { $0.id == id }) else { return }
        customLayers[index].title = KeyboardCustomLayer.normalizedTitle(title)
        customLayers = Self.normalizedCustomLayers(customLayers, rows: rows)
    }

    mutating func updateCustomLayerIcon(id: UUID, systemName: String) {
        guard let index = customLayers.firstIndex(where: { $0.id == id }) else { return }
        customLayers[index].iconSystemName = KeyboardCustomLayer.normalizedIconName(systemName)
        customLayers = Self.normalizedCustomLayers(customLayers, rows: rows)
    }

    mutating func convertCustomLayer(id: UUID, to style: KeyboardCustomLayerStyle) {
        guard let layerIndex = customLayers.firstIndex(where: { $0.id == id }) else { return }
        let currentLayer = customLayers[layerIndex]
        guard currentLayer.style != style else { return }

        let existingKeys = customLayerRows(for: id).flatMap(\.keys)
        for row in customLayerRows(for: id) {
            removeCustomRowDimensions(rowID: row.id)
        }
        rows.removeAll { $0.customLayerID == id }

        let targetSurface: KeyboardRowSurface = style == .row ? .mainRow : .symbols1
        var keyCursor = 0
        let convertedRows = customLayerSourceRows(surface: targetSurface).map { sourceRow -> KeyboardLayoutRow in
            var row = sourceRow
            row.id = UUID()
            row.customLayerID = id
            row.surface = targetSurface
            row.keys = sourceRow.keys.prefix(Self.customLayerMaxKeysPerRow).map { sourceKey in
                defer { keyCursor += 1 }
                guard existingKeys.indices.contains(keyCursor) else {
                    return KeyboardLayoutKey(
                        tap: Self.isCustomLayerPrimaryRow(sourceRow) ? "" : sourceKey.tap,
                        hold: Self.isCustomLayerPrimaryRow(sourceRow) ? nil : sourceKey.hold,
                        widthWeight: sourceKey.widthWeight,
                        heightOverride: sourceKey.heightOverride
                    )
                }
                let existing = existingKeys[keyCursor]
                return KeyboardLayoutKey(
                    tap: existing.tap,
                    hold: existing.hold,
                    holdChoices: existing.holdChoices,
                    widthWeight: existing.widthWeight,
                    heightOverride: existing.heightOverride
                )
            }
            while row.keys.count < KeyboardLayoutBounds.expandedCountRange.lowerBound {
                row.keys.append(KeyboardLayoutKey(tap: "", hold: nil))
            }
            return Self.normalizedRow(row)
        }
        rows.append(contentsOf: convertedRows)
        customLayers[layerIndex] = KeyboardCustomLayer(
            id: currentLayer.id,
            title: currentLayer.title,
            iconSystemName: currentLayer.iconSystemName,
            surface: targetSurface,
            rowIDs: convertedRows.map(\.id)
        )
        customLayers = Self.normalizedCustomLayers(customLayers, rows: rows)
    }

    mutating func deleteCustomLayer(id: UUID) {
        guard let layer = customLayers.first(where: { $0.id == id }) else { return }
        for row in customLayerRows(for: layer.id) {
            removeCustomRow(id: row.id)
        }
        customLayers.removeAll { $0.id == id }
        rows.removeAll { $0.customLayerID == layer.id }
        customLayers = Self.normalizedCustomLayers(customLayers, rows: rows)
    }

    func customLayer(for id: UUID?) -> KeyboardCustomLayer? {
        guard let id else { return nil }
        return customLayers.first { $0.id == id }
    }

    func transferDocument(
        surface: KeyboardRowSurface,
        title: String
    ) throws -> HWKKeymapTransferDocument {
        let editableKinds: [KeyboardRowKind]
        switch surface {
        case .mainRow:
            editableKinds = [.toolbar]
        case .symbols1, .symbols2:
            editableKinds = [.symbolTop, .symbolMiddle, .symbolBottom, .symbolMain]
        case .letters:
            editableKinds = [.letterTop, .letterMiddle, .letterBottom, .letterMain]
        }

        let transferRows = rows.filter { row in
            row.customLayerID == nil &&
                row.surface == surface &&
                !row.holdLayer
        }.map { row in
            Self.transferAdapterRow(
                from: row,
                isContent: editableKinds.contains(row.kind.tapVariant)
            )
        }
        let kind: HWKKeymapTransferDocument.LayerKind = surface == .mainRow ? .mainRow : .expanded
        return try HWKKeymapTransferAdapter.document(
            title: title,
            kind: kind,
            rows: transferRows
        )
    }

    func transferDocument(forCustomLayerID id: UUID) throws -> HWKKeymapTransferDocument {
        guard let layer = customLayer(for: id) else {
            throw HWKKeymapTransferError.exportFailed
        }

        let editableKinds: [KeyboardRowKind]
        switch layer.surface {
        case .mainRow:
            editableKinds = [.toolbar]
        case .symbols1, .symbols2:
            editableKinds = [.symbolTop, .symbolMiddle, .symbolBottom]
        case .letters:
            editableKinds = [.letterTop, .letterMiddle, .letterBottom]
        }

        let transferRows = customLayerRows(for: layer.id).map { row in
            Self.transferAdapterRow(
                from: row,
                isContent: editableKinds.contains(row.kind.tapVariant)
            )
        }
        return try HWKKeymapTransferAdapter.document(
            title: layer.title,
            kind: layer.style == .row ? .mainRow : .expanded,
            rows: transferRows
        )
    }

    private static func transferAdapterRow(
        from row: KeyboardLayoutRow,
        isContent: Bool
    ) -> HWKKeymapTransferAdapter.Row {
        HWKKeymapTransferAdapter.Row(
            role: isContent ? .content : .appOwned,
            keys: row.keys.map { key in
                HWKKeymapTransferDocument.Key(
                    tap: key.tap,
                    holdChoices: key.holdChoices
                )
            }
        )
    }

    @discardableResult
    mutating func importTransferDocument(_ document: HWKKeymapTransferDocument) throws -> KeyboardCustomLayer {
        try document.validate()

        var next = self
        let surface: KeyboardRowSurface = document.kind == .mainRow ? .mainRow : .symbols1
        let layer = next.addCustomLayer(
            surface: surface,
            title: next.uniqueTransferLayerTitle(document.title)
        )
        let editableKinds: [KeyboardRowKind] = document.kind == .mainRow
            ? [.toolbar]
            : [.symbolTop, .symbolMiddle, .symbolBottom]
        let editableRows = next.customLayerRows(for: layer.id).filter { editableKinds.contains($0.kind) }
        guard editableRows.count == document.rows.count else {
            throw HWKKeymapTransferError.importFailed
        }

        for (targetRow, transferredKeys) in zip(editableRows, document.rows) {
            guard let rowIndex = next.rows.firstIndex(where: { $0.id == targetRow.id }) else {
                throw HWKKeymapTransferError.importFailed
            }
            next.rows[rowIndex].keys = transferredKeys.map { transferredKey in
                KeyboardLayoutKey(
                    tap: transferredKey.tap,
                    hold: transferredKey.holdChoices.first,
                    holdChoices: transferredKey.holdChoices
                )
            }
        }

        guard let imported = next.customLayer(for: layer.id) else {
            throw HWKKeymapTransferError.importFailed
        }
        self = next
        return imported
    }

    mutating func applyTransferDocument(
        _ document: HWKKeymapTransferDocument,
        to surface: KeyboardRowSurface,
        customLayerID: UUID?
    ) throws {
        try document.validate()
        switch document.kind {
        case .mainRow:
            guard surface == .mainRow else {
                throw HWKKeymapTransferError.invalidRowCount
            }
        case .expanded:
            guard surface != .mainRow else {
                throw HWKKeymapTransferError.invalidRowCount
            }
        }
        if let customLayerID,
           let layer = customLayer(for: customLayerID) {
            let expectedStyle: KeyboardCustomLayerStyle = document.kind == .mainRow
                ? .row
                : .expanded
            guard layer.style == expectedStyle else {
                throw HWKKeymapTransferError.invalidRowCount
            }
        }

        let eligibleKinds = Self.presetEditableKinds(for: surface)
        let targetIndices = rows.indices.filter { index in
            let row = rows[index]
            let ownsTarget = customLayerID.map { row.customLayerID == $0 }
                ?? (row.customLayerID == nil && row.surface == surface)
            return ownsTarget && eligibleKinds.contains(row.kind)
        }
        guard targetIndices.count == document.rows.count else {
            throw HWKKeymapTransferError.importFailed
        }

        var nextRows = rows
        for (rowIndex, transferredKeys) in zip(targetIndices, document.rows) {
            let existingKeys = nextRows[rowIndex].keys
            nextRows[rowIndex].keys = transferredKeys.enumerated().map { offset, transferred in
                let existing = existingKeys.indices.contains(offset) ? existingKeys[offset] : nil
                return KeyboardLayoutKey(
                    id: existing?.id ?? UUID(),
                    tap: transferred.tap,
                    hold: transferred.holdChoices.first,
                    holdChoices: transferred.holdChoices,
                    widthWeight: existing?.widthWeight ?? 1,
                    heightOverride: existing?.heightOverride
                )
            }
        }
        rows = Self.normalizedRows(nextRows)
        applyRowsToLegacyFields()
    }

    private func uniqueTransferLayerTitle(_ requestedTitle: String) -> String {
        let base = KeyboardCustomLayer.normalizedTitle(requestedTitle)
        let existingTitles = Set(customLayers.map { $0.title.lowercased() })
        guard existingTitles.contains(base.lowercased()) else { return base }

        for number in 2...(KeyboardLayoutBounds.maxCustomLayers + 1) {
            let suffix = " \(number)"
            let prefixCount = max(1, 24 - suffix.count)
            let candidate = String(base.prefix(prefixCount)) + suffix
            if !existingTitles.contains(candidate.lowercased()) {
                return candidate
            }
        }
        return String(base.prefix(19)) + " Copy"
    }

    /// Dynamic schema view used by the editor and renderer.
    var dynamicRows: [KeyboardLayoutRow] {
        return rows
    }

    private func synthesizedLegacyRows(surface: KeyboardRowSurface) -> [KeyboardLayoutRow] {
        switch surface {
        case .mainRow:
            return [
                buildLegacyRow(.mainRow, .quickInsert, holdLayer: false, slots: quickInsertRow),
                buildLegacyRow(.mainRow, .quickInsert, holdLayer: true, slots: holdQuickInsertRow),
                buildLegacyRow(.mainRow, .toolbar, holdLayer: false, slots: toolbarRow),
                buildLegacyRow(.mainRow, .toolbar, holdLayer: true, slots: holdToolbarRow),
            ]
        case .symbols1:
            return [
                buildLegacyRow(.symbols1, .symbolMain, holdLayer: false, slots: symbolTopRow),
                buildLegacyRow(.symbols1, .symbolMain, holdLayer: true, slots: holdSymbolTopRow),
                buildLegacyRow(.symbols1, .symbolMain, holdLayer: false, slots: symbolMiddleRow),
                buildLegacyRow(.symbols1, .symbolMain, holdLayer: true, slots: holdSymbolMiddleRow),
                buildLegacyRow(.symbols1, .symbolMain, holdLayer: false, slots: symbolBottomRow),
                buildLegacyRow(.symbols1, .symbolMain, holdLayer: true, slots: holdSymbolBottomRow),
            ]
        case .symbols2:
            return [
                buildLegacyRow(.symbols2, .symbolMain, holdLayer: false, slots: Self.nativeSymbol2TopRow),
                buildLegacyRow(.symbols2, .symbolMain, holdLayer: true, slots: Self.nativeHoldSymbol2TopRow),
                buildLegacyRow(.symbols2, .symbolMain, holdLayer: false, slots: Self.nativeSymbol2MiddleRow),
                buildLegacyRow(.symbols2, .symbolMain, holdLayer: true, slots: Self.nativeHoldSymbol2MiddleRow),
                buildLegacyRow(.symbols2, .symbolMain, holdLayer: false, slots: Self.nativeSymbol2BottomRow),
                buildLegacyRow(.symbols2, .symbolMain, holdLayer: true, slots: Self.nativeHoldSymbol2BottomRow),
            ]
        case .letters:
            return [
                buildLegacyRow(.letters, .letterMain, holdLayer: false, slots: letterTopRow),
                buildLegacyRow(.letters, .letterMain, holdLayer: true, slots: holdLetterTopRow),
                buildLegacyRow(.letters, .letterMain, holdLayer: false, slots: letterMiddleRow),
                buildLegacyRow(.letters, .letterMain, holdLayer: true, slots: holdLetterMiddleRow),
                buildLegacyRow(.letters, .letterMain, holdLayer: false, slots: letterBottomRow),
                buildLegacyRow(.letters, .letterMain, holdLayer: true, slots: holdLetterBottomRow),
            ]
        }
    }

    private func buildLegacyRow(
        _ surface: KeyboardRowSurface,
        _ kind: KeyboardRowKind,
        holdLayer: Bool,
        slots: [String]
    ) -> KeyboardLayoutRow {
        let keys: [KeyboardLayoutKey] = slots.enumerated().map { index, value in
            let dims = keyDimensions(surface: surface, kind: kind, holdLayer: holdLayer, slotIndex: index)
            return KeyboardLayoutKey(
                tap: holdLayer ? "" : value,
                hold: holdLayer ? value : nil,
                widthWeight: dims.widthWeight,
                heightOverride: dims.heightOverride
            )
        }
        return KeyboardLayoutRow(
            kind: kind,
            surface: surface,
            holdLayer: holdLayer,
            keys: keys
        )
    }

    private mutating func applyRowsToLegacyFields() {
        quickInsertRow = Self.taps(for: .quickInsert, surface: .mainRow, rows: rows) ?? quickInsertRow
        holdQuickInsertRow = Self.holds(for: .quickInsert, surface: .mainRow, rows: rows) ?? holdQuickInsertRow
        toolbarRow = Self.taps(for: .toolbar, surface: .mainRow, rows: rows) ?? toolbarRow
        holdToolbarRow = Self.holds(for: .toolbar, surface: .mainRow, rows: rows) ?? holdToolbarRow
        symbolTopRow = Self.taps(for: .symbolTop, surface: .symbols1, rows: rows)
            ?? Self.tapsForMainRow(surface: .symbols1, rows: rows, offset: 0)
            ?? symbolTopRow
        holdSymbolTopRow = Self.holds(for: .symbolTop, surface: .symbols1, rows: rows)
            ?? Self.holdsForMainRow(surface: .symbols1, rows: rows, offset: 0)
            ?? holdSymbolTopRow
        symbolMiddleRow = Self.taps(for: .symbolMiddle, surface: .symbols1, rows: rows)
            ?? Self.tapsForMainRow(surface: .symbols1, rows: rows, offset: 1)
            ?? symbolMiddleRow
        holdSymbolMiddleRow = Self.holds(for: .symbolMiddle, surface: .symbols1, rows: rows)
            ?? Self.holdsForMainRow(surface: .symbols1, rows: rows, offset: 1)
            ?? holdSymbolMiddleRow
        symbolBottomRow = Self.taps(for: .symbolBottom, surface: .symbols1, rows: rows)
            ?? Self.tapsForMainRow(surface: .symbols1, rows: rows, offset: 2)
            ?? symbolBottomRow
        holdSymbolBottomRow = Self.holds(for: .symbolBottom, surface: .symbols1, rows: rows)
            ?? Self.holdsForMainRow(surface: .symbols1, rows: rows, offset: 2)
            ?? holdSymbolBottomRow
        letterTopRow = Self.taps(for: .letterTop, surface: .letters, rows: rows)
            ?? Self.tapsForMainRow(surface: .letters, rows: rows, offset: 0)
            ?? letterTopRow
        holdLetterTopRow = Self.holds(for: .letterTop, surface: .letters, rows: rows)
            ?? Self.holdsForMainRow(surface: .letters, rows: rows, offset: 0)
            ?? holdLetterTopRow
        letterMiddleRow = Self.taps(for: .letterMiddle, surface: .letters, rows: rows)
            ?? Self.tapsForMainRow(surface: .letters, rows: rows, offset: 1)
            ?? letterMiddleRow
        holdLetterMiddleRow = Self.holds(for: .letterMiddle, surface: .letters, rows: rows)
            ?? Self.holdsForMainRow(surface: .letters, rows: rows, offset: 1)
            ?? holdLetterMiddleRow
        letterBottomRow = Self.taps(for: .letterBottom, surface: .letters, rows: rows)
            ?? Self.tapsForMainRow(surface: .letters, rows: rows, offset: 2)
            ?? letterBottomRow
        holdLetterBottomRow = Self.holds(for: .letterBottom, surface: .letters, rows: rows)
            ?? Self.holdsForMainRow(surface: .letters, rows: rows, offset: 2)
            ?? holdLetterBottomRow
        symbolUtilityRow = Self.taps(for: .symbolUtility, surface: .symbols1, rows: rows)
            ?? Self.taps(for: .symbolUtility, surface: .mainRow, rows: rows)
            ?? symbolUtilityRow
        letterUtilityRow = Self.taps(for: .letterUtility, surface: .letters, rows: rows) ?? letterUtilityRow
        trailingUtilityRow = Self.taps(for: .trailingUtility, surface: .mainRow, rows: rows) ?? trailingUtilityRow
        expandedTrailingUtilityRow = Self.taps(for: .expandedTrailingUtility, surface: .symbols1, rows: rows)
            ?? expandedTrailingUtilityRow
        expandedLetterTrailingUtilityRow = Self.taps(
            for: .expandedLetterTrailingUtility,
            surface: .letters,
            rows: rows
        ) ?? expandedLetterTrailingUtilityRow
        letterBottomLeadingRow = Self.taps(for: .letterBottomLeading, surface: .letters, rows: rows)
            ?? letterBottomLeadingRow
        customAddedRows = rows.filter {
            $0.customLayerID == nil && ($0.kind == .symbolMain || $0.kind == .letterMain)
        }
        customLayers = Self.normalizedCustomLayers(customLayers, rows: rows)
    }

    private static func taps(for kind: KeyboardRowKind, surface: KeyboardRowSurface, rows: [KeyboardLayoutRow]) -> [String]? {
        rows.first {
            $0.customLayerID == nil && $0.kind == kind && $0.surface == surface && !$0.holdLayer
        }?.keys.map(\.tap)
    }

    private static func holds(for kind: KeyboardRowKind, surface: KeyboardRowSurface, rows: [KeyboardLayoutRow]) -> [String]? {
        rows.first {
            $0.customLayerID == nil && $0.kind == kind && $0.surface == surface && !$0.holdLayer
        }?.keys.map { $0.hold ?? "" }
    }

    private static func tapsForMainRow(surface: KeyboardRowSurface, rows: [KeyboardLayoutRow], offset: Int) -> [String]? {
        let kind: KeyboardRowKind = surface == .symbols1 ? .symbolMain : .letterMain
        let matches = rows.filter {
            $0.customLayerID == nil && $0.kind == kind && $0.surface == surface && !$0.holdLayer
        }
        guard matches.indices.contains(offset) else { return nil }
        return matches[offset].keys.map(\.tap)
    }

    private static func holdsForMainRow(surface: KeyboardRowSurface, rows: [KeyboardLayoutRow], offset: Int) -> [String]? {
        let kind: KeyboardRowKind = surface == .symbols1 ? .symbolMain : .letterMain
        let matches = rows.filter {
            $0.customLayerID == nil && $0.kind == kind && $0.surface == surface && !$0.holdLayer
        }
        guard matches.indices.contains(offset) else { return nil }
        return matches[offset].keys.map { $0.hold ?? "" }
    }

    private static func makeRowsFromLegacyFields(
        quickInsertRow: [String],
        holdQuickInsertRow: [String],
        toolbarRow: [String],
        holdToolbarRow: [String],
        symbolTopRow: [String],
        holdSymbolTopRow: [String],
        symbolMiddleRow: [String],
        holdSymbolMiddleRow: [String],
        symbolBottomRow: [String],
        holdSymbolBottomRow: [String],
        letterTopRow: [String],
        holdLetterTopRow: [String],
        letterMiddleRow: [String],
        holdLetterMiddleRow: [String],
        letterBottomRow: [String],
        holdLetterBottomRow: [String],
        symbolUtilityRow: [String],
        letterUtilityRow: [String],
        trailingUtilityRow: [String],
        expandedTrailingUtilityRow: [String],
        expandedLetterTrailingUtilityRow: [String],
        letterBottomLeadingRow: [String],
        customAddedRows: [KeyboardLayoutRow],
        keyDimensionOverrides: [String: KeyboardLayoutKeyDimensions]
    ) -> [KeyboardLayoutRow] {
        var result = [
            makeRow(.mainRow, .quickInsert, taps: quickInsertRow, holds: holdQuickInsertRow, overrides: keyDimensionOverrides),
            makeRow(.mainRow, .toolbar, taps: toolbarRow, holds: holdToolbarRow, overrides: keyDimensionOverrides),
            makeRow(.mainRow, .trailingUtility, taps: trailingUtilityRow, overrides: keyDimensionOverrides),
            makeRow(.symbols1, .symbolTop, taps: symbolTopRow, holds: holdSymbolTopRow, overrides: keyDimensionOverrides),
            makeRow(.symbols1, .symbolMiddle, taps: symbolMiddleRow, holds: holdSymbolMiddleRow, overrides: keyDimensionOverrides),
            makeRow(.symbols1, .symbolBottom, taps: symbolBottomRow, holds: holdSymbolBottomRow, overrides: keyDimensionOverrides),
            makeRow(.symbols1, .symbolUtility, taps: symbolUtilityRow, overrides: keyDimensionOverrides),
            makeRow(.symbols1, .expandedTrailingUtility, taps: expandedTrailingUtilityRow, overrides: keyDimensionOverrides),
            makeRow(.letters, .letterTop, taps: letterTopRow, holds: holdLetterTopRow, overrides: keyDimensionOverrides),
            makeRow(.letters, .letterMiddle, taps: letterMiddleRow, holds: holdLetterMiddleRow, overrides: keyDimensionOverrides),
            makeRow(.letters, .letterBottom, taps: letterBottomRow, holds: holdLetterBottomRow, overrides: keyDimensionOverrides),
            makeRow(.letters, .letterUtility, taps: letterUtilityRow, overrides: keyDimensionOverrides),
            makeRow(.letters, .letterBottomLeading, taps: letterBottomLeadingRow, overrides: keyDimensionOverrides),
            makeRow(.letters, .expandedLetterTrailingUtility, taps: expandedLetterTrailingUtilityRow, overrides: keyDimensionOverrides)
        ].compactMap { $0 }
        result.append(contentsOf: nativeSymbol2Rows(
            symbolUtilityRow: symbolUtilityRow,
            expandedTrailingUtilityRow: expandedTrailingUtilityRow,
            keyDimensionOverrides: keyDimensionOverrides
        ))
        result.append(contentsOf: customAddedRows.map(normalizedRow))
        return result
    }

    private static func nativeSymbol2Rows(
        symbolUtilityRow: [String],
        expandedTrailingUtilityRow: [String],
        keyDimensionOverrides: [String: KeyboardLayoutKeyDimensions]
    ) -> [KeyboardLayoutRow] {
        [
            makeRow(.symbols2, .symbolTop, taps: nativeSymbol2TopRow, holds: nativeHoldSymbol2TopRow, overrides: keyDimensionOverrides),
            makeRow(.symbols2, .symbolMiddle, taps: nativeSymbol2MiddleRow, holds: nativeHoldSymbol2MiddleRow, overrides: keyDimensionOverrides),
            makeRow(.symbols2, .symbolBottom, taps: nativeSymbol2BottomRow, holds: nativeHoldSymbol2BottomRow, overrides: keyDimensionOverrides),
            makeRow(.symbols2, .symbolUtility, taps: symbolUtilityRow, overrides: keyDimensionOverrides),
            makeRow(.symbols2, .expandedTrailingUtility, taps: expandedTrailingUtilityRow, overrides: keyDimensionOverrides),
        ].compactMap { $0 }
    }

    private static func rowsEnsuringNativeSymbolPageActions(
        _ rows: [KeyboardLayoutRow]
    ) -> [KeyboardLayoutRow] {
        rows.map { row in
            guard row.customLayerID == nil,
                  (row.surface == .symbols1 || row.surface == .symbols2),
                  row.kind == .symbolUtility else { return row }
            var nextRow = row
            let layerToken = KeyboardSpecialKeyAction.toggleLayer.storageToken
            let pageToken = KeyboardSpecialKeyAction.toggleSymbolPage.storageToken
            if !nextRow.keys.contains(where: { $0.tap == layerToken }) {
                nextRow.keys.insert(
                    KeyboardLayoutKey(id: stableID("migration:\(row.surface.rawValue):layer"), tap: layerToken),
                    at: 0
                )
            }
            if !nextRow.keys.contains(where: { $0.tap == pageToken }) {
                let layerIndex = nextRow.keys.firstIndex(where: { $0.tap == layerToken }) ?? 0
                nextRow.keys.insert(
                    KeyboardLayoutKey(id: stableID("migration:\(row.surface.rawValue):symbolPage"), tap: pageToken),
                    at: min(layerIndex + 1, nextRow.keys.count)
                )
            }
            nextRow.keys = Array(nextRow.keys.prefix(KeyboardLayoutBounds.maxKeysPerRow))
            return nextRow
        }
    }

    private static func makeRow(
        _ surface: KeyboardRowSurface,
        _ kind: KeyboardRowKind,
        taps: [String],
        holds: [String] = [],
        overrides: [String: KeyboardLayoutKeyDimensions]
    ) -> KeyboardLayoutRow? {
        let count = min(max(taps.count, holds.count), KeyboardLayoutBounds.maxKeysPerRow)
        guard count > 0 else { return nil }
        let rowSeed = "row:\(surface.rawValue):\(kind.rawValue):tap"
        let keys = (0..<count).map { index -> KeyboardLayoutKey in
            let tap = taps.indices.contains(index) ? taps[index] : ""
            let hold = holds.indices.contains(index) ? holds[index] : ""
            let override = overrides[
                KeyboardLayoutDimensionKey.legacyKey(
                    surface: surface,
                    kind: kind,
                    holdLayer: false,
                    slotIndex: index
                )
            ] ?? .identity
            return KeyboardLayoutKey(
                id: stableID("\(rowSeed):key:\(index)"),
                tap: tap,
                hold: hold.isEmpty ? nil : hold,
                widthWeight: override.widthWeight,
                heightOverride: override.heightOverride
            )
        }
        return KeyboardLayoutRow(
            id: stableID(rowSeed),
            kind: kind,
            surface: surface,
            holdLayer: false,
            keys: keys
        )
    }

    private static func normalizedRows(_ rows: [KeyboardLayoutRow]) -> [KeyboardLayoutRow] {
        var editableCounts: [KeyboardLayoutRowLimitKey: Int] = [:]
        var protectedRows = Set<KeyboardLayoutProtectedRowKey>()
        var seenRowIDs = Set<UUID>()
        var result: [KeyboardLayoutRow] = []

        for row in rows {
            let limitKey = KeyboardLayoutRowLimitKey(row)
            if protectedSingletonKinds.contains(row.kind) {
                let protectedKey = KeyboardLayoutProtectedRowKey(row)
                guard protectedRows.insert(protectedKey).inserted else { continue }
            } else {
                guard editableCounts[limitKey, default: 0] < KeyboardLayoutBounds.maxRowsPerSurface else { continue }
                editableCounts[limitKey, default: 0] += 1
            }

            var nextRow = normalizedRow(row)
            nextRow.id = uniqueID(nextRow.id, seen: &seenRowIDs)
            result.append(nextRow)
        }

        return result
    }

    private static func normalizedCustomRows(_ rows: [KeyboardLayoutRow]) -> [KeyboardLayoutRow] {
        normalizedRows(
            rows.filter {
                $0.customLayerID == nil && ($0.kind == .symbolMain || $0.kind == .letterMain)
            }
        )
    }

    private static func normalizedCustomLayers(
        _ layers: [KeyboardCustomLayer],
        rows: [KeyboardLayoutRow]
    ) -> [KeyboardCustomLayer] {
        var seen = Set<UUID>()
        var result = [KeyboardCustomLayer]()
        let rowsByID = rowsByIDAllowingDuplicateIDs(rows)

        for layer in layers {
            guard result.count < KeyboardLayoutBounds.maxCustomLayers else { break }
            guard seen.insert(layer.id).inserted else {
                continue
            }
            let rowIDs = KeyboardCustomLayer.normalizedRowIDs(
                layer.rowIDs.filter { rowsByID[$0] != nil }
            )
            guard !rowIDs.isEmpty else { continue }
            result.append(
                KeyboardCustomLayer(
                    id: layer.id,
                    title: layer.title,
                    iconSystemName: layer.iconSystemName,
                    surface: layer.surface,
                    rowIDs: rowIDs
                )
            )
        }

        return result
    }

    private static func rowsRemovingDiscardedCustomLayerRows(
        _ rows: [KeyboardLayoutRow],
        layers: [KeyboardCustomLayer]
    ) -> [KeyboardLayoutRow] {
        let retainedLayerIDs = Set(layers.map(\.id))
        return rows.filter { row in
            guard let customLayerID = row.customLayerID else { return true }
            return retainedLayerIDs.contains(customLayerID)
        }
    }

    private static func rowsByIDAllowingDuplicateIDs(_ rows: [KeyboardLayoutRow]) -> [UUID: KeyboardLayoutRow] {
        var rowsByID: [UUID: KeyboardLayoutRow] = [:]
        for row in rows where rowsByID[row.id] == nil {
            rowsByID[row.id] = row
        }
        return rowsByID
    }

    private static func rowsAssigningCustomLayerIDs(
        _ rows: [KeyboardLayoutRow],
        layers: [KeyboardCustomLayer]
    ) -> [KeyboardLayoutRow] {
        var layerIDsByRowID: [UUID: UUID] = [:]
        for layer in layers {
            for rowID in layer.rowIDs {
                layerIDsByRowID[rowID] = layer.id
            }
        }

        return rows.map { row in
            guard let layerID = layerIDsByRowID[row.id] else { return row }
            var nextRow = row
            nextRow.customLayerID = layerID
            return nextRow
        }
    }

    private static func normalizedKeyDimensionOverrides(
        _ overrides: [String: KeyboardLayoutKeyDimensions]
    ) -> [String: KeyboardLayoutKeyDimensions] {
        var result: [String: KeyboardLayoutKeyDimensions] = [:]
        for key in overrides.keys.sorted().prefix(KeyboardLayoutBounds.maxKeyDimensionOverrides) {
            guard let dimensions = overrides[key] else { continue }
            result[key] = KeyboardLayoutKeyDimensions(
                widthWeight: dimensions.widthWeight,
                heightOverride: dimensions.heightOverride
            )
        }
        return result
    }

    private static func normalizedRow(_ row: KeyboardLayoutRow) -> KeyboardLayoutRow {
        var normalized = row
        let maxKeys = normalized.customLayerID == nil
            ? KeyboardLayoutBounds.maxKeysPerRow
            : Self.customLayerMaxKeysPerRow
        var seenKeyIDs = Set<UUID>()
        normalized.keys = Array(normalized.keys.prefix(maxKeys)).map { key in
            var nextKey = key
            nextKey.id = uniqueID(nextKey.id, seen: &seenKeyIDs)
            nextKey.widthWeight = KeyboardLayoutBounds.clampedPerKeyWidthWeight(key.widthWeight)
            nextKey.heightOverride = key.heightOverride.map(KeyboardLayoutBounds.clampedPerKeyHeight)
            return nextKey
        }
        normalized.height = normalized.height.map(KeyboardLayoutBounds.clampedPerKeyHeight)
        return normalized
    }

    private static func uniqueID(_ id: UUID, seen: inout Set<UUID>) -> UUID {
        if seen.insert(id).inserted {
            return id
        }

        var replacement = UUID()
        while !seen.insert(replacement).inserted {
            replacement = UUID()
        }
        return replacement
    }

    fileprivate func rowsSynchronizedFromLegacyFields() -> [KeyboardLayoutRow] {
        let rebuilt = Self.makeRowsFromLegacyFields(
            quickInsertRow: quickInsertRow,
            holdQuickInsertRow: holdQuickInsertRow,
            toolbarRow: toolbarRow,
            holdToolbarRow: holdToolbarRow,
            symbolTopRow: symbolTopRow,
            holdSymbolTopRow: holdSymbolTopRow,
            symbolMiddleRow: symbolMiddleRow,
            holdSymbolMiddleRow: holdSymbolMiddleRow,
            symbolBottomRow: symbolBottomRow,
            holdSymbolBottomRow: holdSymbolBottomRow,
            letterTopRow: letterTopRow,
            holdLetterTopRow: holdLetterTopRow,
            letterMiddleRow: letterMiddleRow,
            holdLetterMiddleRow: holdLetterMiddleRow,
            letterBottomRow: letterBottomRow,
            holdLetterBottomRow: holdLetterBottomRow,
            symbolUtilityRow: symbolUtilityRow,
            letterUtilityRow: letterUtilityRow,
            trailingUtilityRow: trailingUtilityRow,
            expandedTrailingUtilityRow: expandedTrailingUtilityRow,
            expandedLetterTrailingUtilityRow: expandedLetterTrailingUtilityRow,
            letterBottomLeadingRow: letterBottomLeadingRow,
            customAddedRows: customAddedRows,
            keyDimensionOverrides: keyDimensionOverrides
        )
        let customLayerRows = rows
            .filter { $0.customLayerID != nil }
            .map(Self.normalizedRow)
        return Self.copyDimensions(from: rows, into: rebuilt + customLayerRows)
    }

    private static func copyDimensions(
        from sourceRows: [KeyboardLayoutRow],
        into targetRows: [KeyboardLayoutRow]
    ) -> [KeyboardLayoutRow] {
        let sourceByID = firstWinsDictionary(sourceRows.map { ($0.id, $0) })
        return targetRows.map { targetRow in
            guard let sourceRow = sourceByID[targetRow.id] else { return normalizedRow(targetRow) }

            var nextRow = targetRow
            nextRow.height = sourceRow.height ?? targetRow.height

            let sourceKeysByID = firstWinsDictionary(sourceRow.keys.map { ($0.id, $0) })
            nextRow.keys = nextRow.keys.map { targetKey in
                guard let sourceKey = sourceKeysByID[targetKey.id] else { return targetKey }

                var nextKey = targetKey
                nextKey.widthWeight = sourceKey.widthWeight
                nextKey.heightOverride = sourceKey.heightOverride
                return nextKey
            }

            return normalizedRow(nextRow)
        }
    }

    private static func firstWinsDictionary<Key: Hashable, Value>(_ pairs: [(Key, Value)]) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs where result[key] == nil {
            result[key] = value
        }
        return result
    }

    private struct KeyboardLayoutRowLimitKey: Hashable {
        let surface: KeyboardRowSurface
        let holdLayer: Bool
        let customLayerID: UUID?

        init(_ row: KeyboardLayoutRow) {
            surface = row.surface
            holdLayer = row.holdLayer
            customLayerID = row.customLayerID
        }
    }

    private struct KeyboardLayoutProtectedRowKey: Hashable {
        let surface: KeyboardRowSurface
        let kind: KeyboardRowKind
        let holdLayer: Bool
        let customLayerID: UUID?

        init(_ row: KeyboardLayoutRow) {
            surface = row.surface
            kind = row.kind
            holdLayer = row.holdLayer
            customLayerID = row.customLayerID
        }
    }

    private static func stableID(_ seed: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", hash & 0x0000_FFFF_FFFF_FFFF))!
    }
}

enum KeyboardSpecialKeyAction: CaseIterable {
    case enter
    case shift
    case toggleLayer
    case toggleSymbolPage
    case space
    case tab
    case undo
    case cut
    case copy
    case paste
    case clipboard
    case redo
    case deleteBackward
    case deleteForward
    case moveLeft
    case moveRight
    case moveUp
    case moveDown
    case menu
    case nextKeyboard

    var storageToken: String {
        switch self {
        case .enter:
            return "@enter"
        case .shift:
            return "@shift"
        case .toggleLayer:
            return "@layer"
        case .toggleSymbolPage:
            return "@symbolpage"
        case .space:
            return "@space"
        case .tab:
            return "@tab"
        case .undo:
            return "@undo"
        case .cut:
            return "@cut"
        case .copy:
            return "@copy"
        case .paste:
            return "@paste"
        case .clipboard:
            return "@clipboard"
        case .redo:
            return "@redo"
        case .deleteBackward:
            return "@delete"
        case .deleteForward:
            return "@fwddel"
        case .moveLeft:
            return "@left"
        case .moveRight:
            return "@right"
        case .moveUp:
            return "@up"
        case .moveDown:
            return "@down"
        case .menu:
            return "@menu"
        case .nextKeyboard:
            return "@globe"
        }
    }

    static func resolved(from value: String) -> KeyboardSpecialKeyAction? {
        switch normalizedLookupToken(from: value) {
        case "enter", "return":
            return .enter
        case "shift", "caps", "capslock", "alphashift":
            return .shift
        case "layer", "symbols", "togglelayer", "toggle", "123", "abc", "123abc", "abc123":
            return .toggleLayer
        case "symbolpage", "togglesymbolpage", "sym1", "sym2", "#+=":
            return .toggleSymbolPage
        case "space", "spacebar":
            return .space
        case "tab":
            return .tab
        case "undo":
            return .undo
        case "cut":
            return .cut
        case "copy":
            return .copy
        case "paste":
            return .paste
        case "clipboard", "clips", "snippets", "clip":
            return .clipboard
        case "redo":
            return .redo
        case "delete", "deletebackward", "backwarddelete", "backspace", "back", "bksp", "deleteleft":
            return .deleteBackward
        case "fwddel", "fwddelete", "forwarddelete", "forwarddel", "deleteforward", "deletefwd", "fdel":
            return .deleteForward
        case "left", "arrowleft", "cursorleft", "moveleft":
            return .moveLeft
        case "right", "arrowright", "cursorright", "moveright":
            return .moveRight
        case "up", "arrowup", "cursorup", "moveup", "previousline", "lineup":
            return .moveUp
        case "down", "arrowdown", "cursordown", "movedown", "nextline", "linedown":
            return .moveDown
        case "menu", "more", "expand", "morekey":
            return .menu
        case "globe", "nextkeyboard", "nextkb", "nextinput", "keyboardnext":
            return .nextKeyboard
        default:
            return nil
        }
    }

    private static func normalizedLookupToken(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    var shelfTitle: String {
        switch self {
        case .enter:
            return "Return"
        case .shift:
            return "Shift"
        case .toggleLayer:
            return "123 / ABC"
        case .toggleSymbolPage:
            return "SYM1 / SYM2"
        case .space:
            return "Space"
        case .tab:
            return "Tab"
        case .undo:
            return "Undo"
        case .cut:
            return "Cut"
        case .copy:
            return "Copy"
        case .paste:
            return "Paste"
        case .clipboard:
            return "Clipboard"
        case .redo:
            return "Redo"
        case .deleteBackward:
            return "Backspace"
        case .deleteForward:
            return "Fwd Delete"
        case .moveLeft:
            return "Left"
        case .moveRight:
            return "Right"
        case .moveUp:
            return "Previous Line"
        case .moveDown:
            return "Next Line"
        case .menu:
            return "More"
        case .nextKeyboard:
            return "Globe"
        }
    }

    var legendSymbol: String {
        switch self {
        case .enter:
            return "↵"
        case .shift:
            return "⇧"
        case .toggleLayer:
            return "123"
        case .toggleSymbolPage:
            return "#+="
        case .space:
            return "␣"
        case .tab:
            return "⇥"
        case .undo:
            return "↶"
        case .cut:
            return "✂"
        case .copy:
            return "⧉"
        case .paste:
            return "▣"
        case .clipboard:
            return "CLP"
        case .redo:
            return "↷"
        case .deleteBackward:
            return "⌫"
        case .deleteForward:
            return "⌦"
        case .moveLeft:
            return "←"
        case .moveRight:
            return "→"
        case .moveUp:
            return "↑"
        case .moveDown:
            return "↓"
        case .menu:
            return "≡"
        case .nextKeyboard:
            return "GLB"
        }
    }
}

struct KeyboardLaunchTraceEntry: Codable, Equatable, Sendable {
    let phase: String
    let elapsedMS: Double
    let width: Double
    let height: Double
    let hostReady: Bool
    let surfaceVisible: Bool
    let timestamp: Double
    var processIdentifier: Int32? = nil
    var physicalFootprintBytes: UInt64? = nil
    var workDurationMS: Double? = nil
    var sampleCount: UInt32? = nil
    var contextUTF8Count: Int? = nil
}

struct KeyboardRawTypedTextMLSample: Codable, Equatable {
    let rawText: String
    let previousRawText: String?
    let boundary: String
    let timestamp: Double
}

enum KeyboardSharedPreferences {
    static let appGroupIdentifier = "group.dev.moni11811.hwkbcompanion"
    static let settingsDidChangeNotification = "dev.moni11811.hwkbcompanion.settings-did-change"
    static let betaHardwareRelayDefaultsRepairFloorBuild = 130
    static let keyboardLaunchTraceLimit = 64
    static let keymapDataByteLimit = 256 * 1_024
    private static let customDictionaryWordLimit = 1_024
    private static let adaptiveUnigramCountLimit = 384
    private static let adaptiveBigramCountLimit = 768
    private static let rawTypedTextMLSampleLimit = 256
    private static let rawTypedTextMLTextLimit = 256
    private static let rawTypedTextMLBoundaryLimit = 8

    enum Key {
        static let appTheme = "app.theme"
        static let accentPalette = "app.accentPalette"
        static let customKeyStyle = "app.customKeyStyle"
        static let vibrationEnabled = "keyboard.vibrationEnabled"
        static let feedbackLevel = "keyboard.feedbackLevel"
        static let autoPairEnabled = "keyboard.autoPairEnabled"
        static let startExpanded = "keyboard.startExpanded"
        static let defaultSymbolLayer = "keyboard.defaultSymbolLayer"
        static let showQuickInsertRow = "keyboard.showQuickInsertRow"
        static let hideKeyboardEnabled = "keyboard.hideKeyboardEnabled"
        static let highContrastKeys = "keyboard.highContrastKeys"
        static let largeLegends = "keyboard.largeLegends"
        static let showControlLabels = "keyboard.showControlLabels"
        static let capitalizeFirstLetterEnabled = "keyboard.capitalizeFirstLetterEnabled"
        static let doubleSpacePeriodEnabled = "keyboard.doubleSpacePeriodEnabled"
        static let autocorrectEnabled = "keyboard.autocorrectEnabled"
        static let autocompleteEnabled = "keyboard.autocompleteEnabled"
        static let clickToFixEnabled = "keyboard.clickToFixEnabled"
        static let autocorrectRankingMethod = "keyboard.autocorrectRankingMethod"
        static let autocorrectLogicRecipe = "keyboard.autocorrectLogicRecipe"
        static let autocorrectLogicBlocks = "keyboard.autocorrectLogicBlocks"
        static let autocorrectLogicLanes = "keyboard.autocorrectLogicLanes"
        static let customTextRules = "keyboard.customTextRules"
        static let edgeSwipeConfiguration = "keyboard.edgeSwipeConfiguration"
        static let semiFoldEnabled = "keyboard.semiFoldEnabled"
        static let suggestionSwipeUpAction = "keyboard.suggestionSwipeUpAction"
        static let suggestionSwipeDownAction = "keyboard.suggestionSwipeDownAction"
        static let suggestionSwipeLeftDeleteEnabled = "keyboard.suggestionSwipeLeftDeleteEnabled"
        static let suggestionSwipeRightSpaceEnabled = "keyboard.suggestionSwipeRightSpaceEnabled"
        static let suggestionHoldForRolodexEnabled = "keyboard.suggestionHoldForRolodexEnabled"
        static let hardwareAutocorrectSelectorEnabled = "keyboard.hardwareAutocorrectSelectorEnabled"
        static let hardwareAutocorrectSelectorInitiationKey = "keyboard.hardwareAutocorrectSelectorInitiationKey"
        static let hardwareAutocorrectSelectorSelectionKey = "keyboard.hardwareAutocorrectSelectorSelectionKey"
        static let physicalReturnBehavior = "keyboard.physicalReturnBehavior"
        static let showQuickInsertHandle = "keyboard.showQuickInsertHandle"
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        static let signalRelayEnabled = "keyboard.signalRelayEnabled"
        static let signalRelayEmitKeyUp = "keyboard.signalRelayEmitKeyUp"
        static let signalRelayPriorityMode = "keyboard.signalRelayPriorityMode"
        static let signalRelaySessionPersist = "keyboard.signalRelaySessionPersist"
        static let signalRelayBetaDefaultsRepairedBuild = "keyboard.signalRelayBetaDefaultsRepairedBuild"
        static let signalRelayHoldTriggerMs = "keyboard.signalRelayHoldTriggerMs"
        static let hardwarePremiumAccessUnlocked = "keyboard.hardwarePremiumAccessUnlocked"
        #endif
        static let keyboardReloadRequestedAt = "keyboard.reloadRequestedAt"
        static let capsHoldToLockEnabled = "keyboard.capsHoldToLockEnabled"
        static let capsHoldDurationMs = "keyboard.capsHoldDurationMs"
        static let menuHoldToLatchEnabled = "keyboard.menuHoldToLatchEnabled"
        static let menuHoldDurationMs = "keyboard.menuHoldDurationMs"
        static let keyHoldDurationMs = "keyboard.keyHoldDurationMs"
        static let rolodexSelectHoldDurationMs = "keyboard.rolodexSelectHoldDurationMs"
        static let menuTapLockWindowMs = "keyboard.menuTapLockWindowMs"
        static let deleteHoldEnabled = "keyboard.deleteHoldEnabled"
        static let deleteHoldWordsBeforeSentence = "keyboard.deleteHoldWordsBeforeSentence"
        static let layoutPreset = "keyboard.layoutPreset"
        static let layoutLocale = "keyboard.layoutLocale"
        static let runtimeLayoutRoute = "keyboard.runtimeLayoutRoute"
        static let toolbarHeight = "keyboard.toolbarHeight"
        static let expandedKeyHeight = "keyboard.expandedKeyHeight"
        static let suggestionVisibleWordCount = "keyboard.suggestionVisibleWordCount"
        static let suggestionRowHeight = "keyboard.suggestionRowHeight"
        static let toolbarKeyCount = "keyboard.toolbarKeyCount"
        static let symbolTopRowKeyCount = "keyboard.symbolTopRowKeyCount"
        static let symbolMiddleRowKeyCount = "keyboard.symbolMiddleRowKeyCount"
        static let symbolBottomRowKeyCount = "keyboard.symbolBottomRowKeyCount"
        static let letterTopRowKeyCount = "keyboard.letterTopRowKeyCount"
        static let letterMiddleRowKeyCount = "keyboard.letterMiddleRowKeyCount"
        static let letterBottomRowKeyCount = "keyboard.letterBottomRowKeyCount"
        static let keymapData = "keyboard.keymapData"
        static let customDictionaryWords = "keyboard.customDictionaryWords"
        static let adaptiveUnigramCounts = "keyboard.adaptiveUnigramCounts"
        static let adaptiveBigramCounts = "keyboard.adaptiveBigramCounts"
        static let rawTypedTextMLSamples = "keyboard.rawTypedTextMLSamples"
        static let stableUserBucket = "keyboard.stableUserBucket"
        static let remoteConfig = "keyboard.remoteConfig"
        static let remoteConfigFetchedAt = "keyboard.remoteConfigFetchedAt"
        static let inputKernelFallbackDisabled = "keyboard.inputKernelFallbackDisabled"
        static let predictionDisabled = "keyboard.predictionDisabled"
        static let glideDisabled = "keyboard.glideDisabled"
        static let clipboardDisabled = "keyboard.clipboardDisabled"
        static let saveClipboardSettingsWithLiveKeyboard = "keyboard.saveClipboardSettingsWithLiveKeyboard"
        static let settingsiCloudSyncEnabled = "settings.iCloudSyncEnabled"
        static let keyboardLastSeenAt = "keyboard.lastSeenAt"
        static let keyboardFullAccessEnabled = "keyboard.fullAccessEnabled"
        static let keyboardFullAccessCheckedAt = "keyboard.fullAccessCheckedAt"
        static let keyboardLaunchTraceEntries = "keyboard.launchTraceEntries"
        static let settingsMigratedAt = "keyboard.settingsMigratedAt"
        static let companionSetupCompletedAt = "companion.setupCompletedAt"
    }

    private static let storageKeys: [String] = {
        var keys = [
            Key.appTheme,
            Key.accentPalette,
            Key.customKeyStyle,
            Key.vibrationEnabled,
            Key.feedbackLevel,
            Key.autoPairEnabled,
            Key.startExpanded,
            Key.defaultSymbolLayer,
            Key.showQuickInsertRow,
            Key.hideKeyboardEnabled,
            Key.highContrastKeys,
            Key.largeLegends,
            Key.showControlLabels,
            Key.capitalizeFirstLetterEnabled,
            Key.doubleSpacePeriodEnabled,
            Key.autocorrectEnabled,
        Key.autocompleteEnabled,
        Key.clickToFixEnabled,
        Key.autocorrectRankingMethod,
        Key.autocorrectLogicRecipe,
        Key.autocorrectLogicBlocks,
        Key.customTextRules,
            Key.edgeSwipeConfiguration,
            Key.semiFoldEnabled,
            Key.suggestionSwipeUpAction,
            Key.suggestionSwipeDownAction,
            Key.suggestionSwipeLeftDeleteEnabled,
            Key.suggestionSwipeRightSpaceEnabled,
            Key.suggestionHoldForRolodexEnabled,
            Key.hardwareAutocorrectSelectorEnabled,
            Key.hardwareAutocorrectSelectorInitiationKey,
            Key.hardwareAutocorrectSelectorSelectionKey,
            Key.physicalReturnBehavior,
            Key.showQuickInsertHandle,
        ]
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        keys.append(contentsOf: [
            Key.signalRelayEnabled,
            Key.signalRelayEmitKeyUp,
            Key.signalRelayPriorityMode,
            Key.signalRelaySessionPersist,
            Key.signalRelayBetaDefaultsRepairedBuild,
            Key.signalRelayHoldTriggerMs,
            Key.hardwarePremiumAccessUnlocked,
        ])
        #endif
        keys.append(contentsOf: [
            Key.capsHoldToLockEnabled,
            Key.capsHoldDurationMs,
            Key.menuHoldToLatchEnabled,
            Key.menuHoldDurationMs,
            Key.keyHoldDurationMs,
            Key.rolodexSelectHoldDurationMs,
            Key.menuTapLockWindowMs,
            Key.deleteHoldEnabled,
            Key.deleteHoldWordsBeforeSentence,
            Key.layoutPreset,
            Key.layoutLocale,
            Key.toolbarHeight,
            Key.expandedKeyHeight,
            Key.toolbarKeyCount,
            Key.symbolTopRowKeyCount,
            Key.symbolMiddleRowKeyCount,
            Key.symbolBottomRowKeyCount,
            Key.letterTopRowKeyCount,
            Key.letterMiddleRowKeyCount,
            Key.letterBottomRowKeyCount,
            Key.keymapData,
            Key.stableUserBucket,
            Key.remoteConfig,
            Key.remoteConfigFetchedAt,
            Key.inputKernelFallbackDisabled,
            Key.predictionDisabled,
            Key.glideDisabled,
            Key.clipboardDisabled,
            Key.saveClipboardSettingsWithLiveKeyboard,
            Key.customDictionaryWords,
            Key.adaptiveUnigramCounts,
            Key.adaptiveBigramCounts,
            Key.rawTypedTextMLSamples,
        ])
        return keys
    }()

    static func currentBundleBuildNumberString(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
    }

    static func betaHardwareRelayDefaultsNeedsRepair(
        repairedBuildValue: Any?,
        currentBuild: String = currentBundleBuildNumberString(),
        isBeta: Bool = HWCBuildFlavor.hardwarePurchaseGateRepairEnabled
    ) -> Bool {
        guard isBeta else { return false }

        guard let currentBuildNumber = buildNumber(from: currentBuild) else {
            return repairedBuildValue == nil
        }

        guard currentBuildNumber >= betaHardwareRelayDefaultsRepairFloorBuild else {
            return repairedBuildValue == nil
        }

        guard let repairedBuildNumber = buildNumber(from: repairedBuildValue) else {
            return true
        }

        return repairedBuildNumber < betaHardwareRelayDefaultsRepairFloorBuild
    }

    private static func buildNumber(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let number = value as? Int {
            return number
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    static let obsoleteKeys = [
        "keyboard.smartSuggestionsEnabled",
        "keyboard.showSuggestionRow",
    ]

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    static var isSharedContainerAvailable: Bool {
        UserDefaults(suiteName: appGroupIdentifier) != nil
    }

    static func sync() {
        guard UserDefaults(suiteName: appGroupIdentifier) != nil else { return }
        CFPreferencesAppSynchronize(appGroupIdentifier as CFString)
    }

    static func migrateLegacyDefaultsIfNeeded() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }
        migrateLegacyDefaultsIfNeeded(sharedDefaults: sharedDefaults, legacyDefaults: .standard)
    }

    static func migrateLegacyDefaultsIfNeeded(
        sharedDefaults: UserDefaults,
        legacyDefaults: UserDefaults
    ) {
        guard !hasStoredSettings(in: sharedDefaults) else { return }
        guard hasStoredSettings(in: legacyDefaults) else { return }

        let legacySnapshot = KeyboardSettingsSnapshot.load(from: legacyDefaults)
        legacySnapshot.persist(to: sharedDefaults, notify: false)
        migrateLegacySuggestionLearning(from: legacyDefaults, to: sharedDefaults)
        sharedDefaults.set(Date().timeIntervalSince1970, forKey: Key.settingsMigratedAt)
        sync()
    }

    static func postSettingsDidChangeNotification() {
        let name = CFNotificationName(settingsDidChangeNotification as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }

    static func keyboardLaunchTrace(defaults: UserDefaults = Self.defaults) -> [KeyboardLaunchTraceEntry] {
        guard let data = defaults.data(forKey: Key.keyboardLaunchTraceEntries),
              let entries = try? JSONDecoder().decode([KeyboardLaunchTraceEntry].self, from: data) else {
            return []
        }
        return entries
    }

    static func recordKeyboardLaunchTrace(
        _ entry: KeyboardLaunchTraceEntry,
        defaults: UserDefaults = Self.defaults
    ) {
        var entries = keyboardLaunchTrace(defaults: defaults)
        entries.append(entry)
        entries = Array(entries.suffix(keyboardLaunchTraceLimit))
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Key.keyboardLaunchTraceEntries)
        sync()
    }

    static func clearKeyboardLaunchTrace(defaults: UserDefaults = Self.defaults) {
        defaults.removeObject(forKey: Key.keyboardLaunchTraceEntries)
        sync()
    }

    @discardableResult
    static func requestKeyboardReload(
        defaults: UserDefaults = Self.defaults,
        timestamp: Double = Date().timeIntervalSince1970
    ) -> Double {
        defaults.set(timestamp, forKey: Key.keyboardReloadRequestedAt)
        sync()
        postSettingsDidChangeNotification()
        return timestamp
    }

    static func keyboardReloadRequestedAt(defaults: UserDefaults = Self.defaults) -> Double? {
        guard let value = defaults.object(forKey: Key.keyboardReloadRequestedAt) as? Double else {
            return nil
        }
        return value
    }

    static func clearConsumedKeyboardReloadRequest(
        timestamp: Double,
        defaults: UserDefaults = Self.defaults
    ) {
        guard keyboardReloadRequestedAt(defaults: defaults) == timestamp else {
            return
        }
        defaults.removeObject(forKey: Key.keyboardReloadRequestedAt)
        sync()
    }

    static func customDictionaryWords() -> Set<String> {
        let storedWords = defaults.array(forKey: Key.customDictionaryWords) as? [String] ?? []
        let normalizedWords = normalizedCustomDictionaryWords(storedWords)
        if normalizedWords.count != storedWords.count || normalizedWords != storedWords {
            HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                storeIDs: [.customDictionary]
            ) {
                defaults.set(normalizedWords, forKey: Key.customDictionaryWords)
            }
        }
        return Set(normalizedWords)
    }

    static func customDictionaryWordsSnapshot() -> Set<String> {
        customDictionaryWordsSnapshot(from: defaults)
    }

    static func customDictionaryWordsSnapshot(from defaults: UserDefaults) -> Set<String> {
        let storedWords = defaults.array(forKey: Key.customDictionaryWords) as? [String] ?? []
        return Set(normalizedCustomDictionaryWords(storedWords))
    }

    @discardableResult
    static func addCustomDictionaryWord(_ word: String) -> Bool {
        guard let normalizedWord = normalizedCustomDictionaryWord(word) else {
            return false
        }

        var words = customDictionaryWords()
        let inserted = words.insert(normalizedWord).inserted
        guard inserted else { return false }

        saveCustomDictionaryWords(words)
        return true
    }

    static func saveCustomDictionaryWords(_ words: Set<String>) {
        let normalizedWords = normalizedCustomDictionaryWords(Array(words))

        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.customDictionary]
        ) {
            defaults.set(normalizedWords, forKey: Key.customDictionaryWords)
        }
        sync()
        postSettingsDidChangeNotification()
    }

    static func clearSuggestionLearningData(
        defaults: UserDefaults = Self.defaults,
        notify: Bool = true
    ) {
        _ = HWKAutobotLearnerManifestStore(defaults: defaults).resetAllLearning()
        sync()

        if notify {
            postSettingsDidChangeNotification()
        }
    }

    static func rawTypedTextMLSamples(
        defaults: UserDefaults = Self.defaults
    ) -> [KeyboardRawTypedTextMLSample] {
        guard let data = defaults.data(forKey: Key.rawTypedTextMLSamples) else {
            return []
        }
        guard let decoded = try? JSONDecoder().decode([KeyboardRawTypedTextMLSample].self, from: data),
              isValidRawTypedTextMLSamplesData(data) else {
            defaults.removeObject(forKey: Key.rawTypedTextMLSamples)
            return []
        }

        let repaired = normalizedRawTypedTextMLSamples(decoded)
        if repaired != decoded {
            persistRawTypedTextMLSamples(repaired, defaults: defaults)
        }
        return repaired
    }

    static func isValidRawTypedTextMLSamplesData(_ data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode(
            [KeyboardRawTypedTextMLSample].self,
            from: data
        ),
        decoded.count <= rawTypedTextMLSampleLimit else {
            return false
        }
        return normalizedRawTypedTextMLSamples(decoded) == decoded
    }

    static func recordRawTypedTextMLSample(
        rawText: String,
        previousRawText: String?,
        boundary: String,
        defaults: UserDefaults = Self.defaults,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        guard let sample = normalizedRawTypedTextMLSample(
            rawText: rawText,
            previousRawText: previousRawText,
            boundary: boundary,
            timestamp: timestamp
        ) else {
            return
        }

        var samples = rawTypedTextMLSamples(defaults: defaults)
        samples.append(sample)
        persistRawTypedTextMLSamples(
            Array(samples.suffix(rawTypedTextMLSampleLimit)),
            defaults: defaults
        )
    }

    static func adaptiveAutocompleteSuggestions(
        prefix: String,
        previousWord: String?,
        limit: Int = 4
    ) -> [String] {
        guard let normalizedPrefix = normalizedCustomDictionaryWord(prefix) else {
            return []
        }

        let unigramCounts = adaptiveCounts(forKey: Key.adaptiveUnigramCounts)
        let bigramCounts = adaptiveCounts(forKey: Key.adaptiveBigramCounts)
        var scoredWords = [String: Double]()

        for (word, count) in unigramCounts where word.hasPrefix(normalizedPrefix) && word != normalizedPrefix {
            scoredWords[word, default: 0] += Double(count) * 1.8
        }

        if let normalizedPreviousWord = previousWord.flatMap(normalizedCustomDictionaryWord) {
            let bigramPrefix = "\(normalizedPreviousWord)\t"
            for (bigramKey, count) in bigramCounts where bigramKey.hasPrefix(bigramPrefix) {
                let candidate = String(bigramKey.dropFirst(bigramPrefix.count))
                guard candidate.hasPrefix(normalizedPrefix),
                      candidate != normalizedPrefix else {
                    continue
                }

                scoredWords[candidate, default: 0] += Double(count) * 4.6
            }
        }

        return scoredWords
            .sorted { lhs, rhs in
                if abs(lhs.value - rhs.value) > 0.0001 {
                    return lhs.value > rhs.value
                }
                if lhs.key.count != rhs.key.count {
                    return lhs.key.count < rhs.key.count
                }
                return lhs.key < rhs.key
            }
            .prefix(limit)
            .map(\.key)
    }

    static func adaptiveNextWordSuggestions(
        previousWord: String?,
        limit: Int = 4
    ) -> [String] {
        guard let normalizedPreviousWord = previousWord.flatMap(normalizedCustomDictionaryWord) else {
            return []
        }

        let bigramPrefix = "\(normalizedPreviousWord)\t"
        let bigramCounts = adaptiveCounts(forKey: Key.adaptiveBigramCounts)

        return bigramCounts
            .compactMap { key, count -> (String, Int)? in
                guard key.hasPrefix(bigramPrefix) else { return nil }
                let candidate = String(key.dropFirst(bigramPrefix.count))
                guard normalizedCustomDictionaryWord(candidate) != nil else { return nil }
                return (candidate, count)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                if lhs.0.count != rhs.0.count {
                    return lhs.0.count < rhs.0.count
                }
                return lhs.0 < rhs.0
            }
            .prefix(limit)
            .map(\.0)
    }

    static func recordAdaptiveCommittedWord(_ word: String, previousWord: String?) {
        guard let normalizedWord = normalizedCustomDictionaryWord(word) else { return }
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.adaptiveUnigrams, .adaptiveBigrams]
        ) {
            var unigramCounts = adaptiveCounts(forKey: Key.adaptiveUnigramCounts)
            unigramCounts[normalizedWord] = min(255, (unigramCounts[normalizedWord] ?? 0) + 1)
            defaults.set(
                trimmedAdaptiveCounts(unigramCounts, limit: adaptiveUnigramCountLimit),
                forKey: Key.adaptiveUnigramCounts
            )

            if let normalizedPreviousWord = previousWord.flatMap(normalizedCustomDictionaryWord) {
                let bigramKey = "\(normalizedPreviousWord)\t\(normalizedWord)"
                var bigramCounts = adaptiveCounts(forKey: Key.adaptiveBigramCounts)
                bigramCounts[bigramKey] = min(255, (bigramCounts[bigramKey] ?? 0) + 1)
                defaults.set(
                    trimmedAdaptiveCounts(bigramCounts, limit: adaptiveBigramCountLimit),
                    forKey: Key.adaptiveBigramCounts
                )
            }
        }
    }

    private static func normalizedRawTypedTextMLSamples(
        _ samples: [KeyboardRawTypedTextMLSample]
    ) -> [KeyboardRawTypedTextMLSample] {
        let normalized = samples.compactMap {
            normalizedRawTypedTextMLSample(
                rawText: $0.rawText,
                previousRawText: $0.previousRawText,
                boundary: $0.boundary,
                timestamp: $0.timestamp
            )
        }
        return Array(normalized.suffix(rawTypedTextMLSampleLimit))
    }

    private static func normalizedRawTypedTextMLSample(
        rawText: String,
        previousRawText: String?,
        boundary: String,
        timestamp: Double
    ) -> KeyboardRawTypedTextMLSample? {
        guard timestamp.isFinite,
              timestamp >= 0,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return KeyboardRawTypedTextMLSample(
            rawText: cappedRawTypedTextMLString(rawText, limit: rawTypedTextMLTextLimit),
            previousRawText: previousRawText.flatMap {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : cappedRawTypedTextMLString($0, limit: rawTypedTextMLTextLimit)
            },
            boundary: cappedRawTypedTextMLString(boundary, limit: rawTypedTextMLBoundaryLimit),
            timestamp: timestamp
        )
    }

    private static func cappedRawTypedTextMLString(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(limit))
    }

    private static func persistRawTypedTextMLSamples(
        _ samples: [KeyboardRawTypedTextMLSample],
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.rawTypedSamples]
        ) {
            defaults.set(data, forKey: Key.rawTypedTextMLSamples)
        }
        sync()
    }

    private static func normalizedCustomDictionaryWord(_ word: String) -> String? {
        let trimmed = word
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard trimmed.count >= 2,
              trimmed.count <= 24,
              trimmed.first?.isLetter == true,
              trimmed.last?.isLetter == true,
              trimmed.allSatisfy({ $0.isLetter || $0 == "'" }) else {
            return nil
        }

        return trimmed
    }

    private static func normalizedCustomDictionaryWords(_ words: [String]) -> [String] {
        let sortedWords = Array(Set(words.compactMap(normalizedCustomDictionaryWord))).sorted()
        return Array(sortedWords.prefix(customDictionaryWordLimit))
    }

    private static func adaptiveCounts(forKey key: String) -> [String: Int] {
        let rawCounts = defaults.dictionary(forKey: key) ?? [:]
        var counts = [String: Int]()

        for (rawKey, rawValue) in rawCounts {
            guard let count = rawValue as? NSNumber else { continue }
            counts[rawKey] = count.intValue
        }

        if let limit = adaptiveCountLimit(forKey: key), counts.count > limit {
            let trimmedCounts = trimmedAdaptiveCounts(counts, limit: limit)
            let storeID: HWKAutobotLearnerStoreID = key == Key.adaptiveUnigramCounts
                ? .adaptiveUnigrams
                : .adaptiveBigrams
            HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                storeIDs: [storeID]
            ) {
                defaults.set(trimmedCounts, forKey: key)
            }
            return trimmedCounts
        }

        return counts
    }

    private static func adaptiveCountLimit(forKey key: String) -> Int? {
        switch key {
        case Key.adaptiveUnigramCounts:
            return adaptiveUnigramCountLimit
        case Key.adaptiveBigramCounts:
            return adaptiveBigramCountLimit
        default:
            return nil
        }
    }

    private static func trimmedAdaptiveCounts(_ counts: [String: Int], limit: Int) -> [String: Int] {
        guard counts.count > limit else { return counts }

        let rankedEntries = counts.sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }

        var trimmed = [String: Int]()
        for entry in rankedEntries.prefix(limit) {
            trimmed[entry.key] = entry.value
        }

        return trimmed
    }

    static func markKeyboardSeenNow() {
        markKeyboardSeen(at: Date())
    }

    static func markKeyboardSeen(at date: Date) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.keyboardLastSeenAt)
        sync()
    }

    static func recordKeyboardAccessState(isEnabled: Bool, at date: Date = Date()) {
        defaults.set(isEnabled, forKey: Key.keyboardFullAccessEnabled)
        defaults.set(date.timeIntervalSince1970, forKey: Key.keyboardFullAccessCheckedAt)
        defaults.set(date.timeIntervalSince1970, forKey: Key.keyboardLastSeenAt)
        sync()
    }

    static func keyboardFullAccessState() -> (isEnabled: Bool, checkedAt: Date)? {
        guard defaults.object(forKey: Key.keyboardFullAccessEnabled) != nil,
              let timestamp = defaults.object(forKey: Key.keyboardFullAccessCheckedAt) as? Double else {
            return nil
        }
        return (defaults.bool(forKey: Key.keyboardFullAccessEnabled), Date(timeIntervalSince1970: timestamp))
    }

    static func markCompanionSetupCompleted() {
        defaults.set(Date().timeIntervalSince1970, forKey: Key.companionSetupCompletedAt)
        sync()
        postSettingsDidChangeNotification()
    }

    static var isCompanionSetupCompleted: Bool {
        defaults.object(forKey: Key.companionSetupCompletedAt) != nil
    }

    static func lastKeyboardSeenAt() -> Date? {
        guard let timestamp = defaults.object(forKey: Key.keyboardLastSeenAt) as? Double else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    static func lastMigrationAt() -> Date? {
        guard let timestamp = defaults.object(forKey: Key.settingsMigratedAt) as? Double else {
            return nil
        }

        return Date(timeIntervalSince1970: timestamp)
    }

    static func hasStoredSettings(in defaults: UserDefaults) -> Bool {
        storageKeys.contains { defaults.object(forKey: $0) != nil }
    }

    private static func migrateLegacySuggestionLearning(
        from legacyDefaults: UserDefaults,
        to sharedDefaults: UserDefaults
    ) {
        let words = legacyDefaults.array(forKey: Key.customDictionaryWords) as? [String] ?? []
        let normalizedWords = normalizedCustomDictionaryWords(words)
        if !normalizedWords.isEmpty {
            sharedDefaults.set(normalizedWords, forKey: Key.customDictionaryWords)
        }

        let legacyUnigramCounts = adaptiveCounts(from: legacyDefaults, key: Key.adaptiveUnigramCounts)
        if !legacyUnigramCounts.isEmpty {
            sharedDefaults.set(
                trimmedAdaptiveCounts(legacyUnigramCounts, limit: adaptiveUnigramCountLimit),
                forKey: Key.adaptiveUnigramCounts
            )
        }

        let legacyBigramCounts = adaptiveCounts(from: legacyDefaults, key: Key.adaptiveBigramCounts)
        if !legacyBigramCounts.isEmpty {
            sharedDefaults.set(
                trimmedAdaptiveCounts(legacyBigramCounts, limit: adaptiveBigramCountLimit),
                forKey: Key.adaptiveBigramCounts
            )
        }
    }

    private static func adaptiveCounts(
        from defaults: UserDefaults,
        key: String
    ) -> [String: Int] {
        let rawCounts = defaults.dictionary(forKey: key) ?? [:]
        var counts = [String: Int]()

        for (rawKey, rawValue) in rawCounts {
            if let count = rawValue as? NSNumber {
                counts[rawKey] = count.intValue
            }
        }

        return counts
    }
}

struct KeyboardSettingsSnapshot: Equatable {
    var appTheme: CompanionAppTheme = .classic
    var accentPalette: KeyboardAccentPalette = .blue
    var customKeyStyle: KeyboardCustomKeyStyle = .defaultStyle
    var vibrationEnabled = true
    var feedbackLevel: KeyboardFeedbackLevel = .medium
    var autoPairEnabled = false
    var startExpanded = true
    var defaultSymbolLayer = false
    var showQuickInsertRow = false
    var hideKeyboardEnabled = false
    var highContrastKeys = false
    var largeLegends = false
    var showControlLabels = false
    var capitalizeFirstLetterEnabled = true
    var doubleSpacePeriodEnabled = false
    var autocorrectEnabled = true
    var autocompleteEnabled = true
    var clickToFixEnabled = true
    var autocorrectRankingMethod: KeyboardAutocorrectRankingMethod = .balanced
    var autocorrectLogicRecipe: KeyboardAutocorrectLogicRecipe = .balanced
    var autocorrectLogicBlocks: [KeyboardAutocorrectLogicBlock] = KeyboardAutocorrectLogicBlock.defaultPipeline
    var autocorrectLogicLanes: [KeyboardAutocorrectLogicLane] = KeyboardAutocorrectLogicLane.defaultLanes
    var customTextRules: [HWKCustomTextRule] = []
    var edgeSwipeConfiguration = KeyboardEdgeSwipeConfiguration()
    var semiFoldEnabled = false
    var suggestionSwipeUpAction: KeyboardSuggestionSwipeUpAction = .laneWord
    var suggestionSwipeDownAction: KeyboardSuggestionSwipeDownAction = .off
    var suggestionSwipeLeftDeleteEnabled = false
    var suggestionSwipeRightSpaceEnabled = false
    var suggestionHoldForRolodexEnabled = true
    var hardwareAutocorrectSelectorEnabled = false
    var hardwareAutocorrectSelectorInitiationKey: KeyboardHardwareAutocorrectSelectorInitiationKey = .option
    var hardwareAutocorrectSelectorSelectionKey: KeyboardHardwareAutocorrectSelectorSelectionKey = .enter
    var physicalReturnBehavior: KeyboardPhysicalReturnBehavior = .passThroughToHost
    var showQuickInsertHandle = false
    #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
    var signalRelayEnabled = HWCBuildFlavor.hardwareRelayDefaultsEnabled
    var signalRelayEmitKeyUp = true
    var signalRelayPriorityMode = false
    var signalRelaySessionPersist = false
    var signalRelayHoldTriggerMs = 360
    var hardwarePremiumAccessUnlocked = HWCBuildFlavor.autoUnlockPaidFeatures
    #endif
    var capsHoldToLockEnabled = true
    var capsHoldDurationMs = 200
    var menuHoldToLatchEnabled = true
    var menuHoldDurationMs = 200
    var keyHoldDurationMs = 200
    var rolodexSelectHoldDurationMs = 260
    var menuTapLockWindowMs = 0
    var deleteHoldEnabled = true
    var deleteHoldWordsBeforeSentence = 5
    var layoutPreset: KeyboardLayoutPreset = .compact
    var layoutLocale: KeyboardLayoutLocale = .enUS
    var runtimeLayoutRoute: KeyboardRuntimeLayoutRoute = .runtimeLocale
    var toolbarHeight = 52
    var expandedKeyHeight = 52
    var suggestionVisibleWordCount = 3
    var suggestionRowHeight = 32
    var toolbarKeyCount = 8
    var symbolTopRowKeyCount = 10
    var symbolMiddleRowKeyCount = 10
    var symbolBottomRowKeyCount = 10
    var letterTopRowKeyCount = 10
    var letterMiddleRowKeyCount = 9
    var letterBottomRowKeyCount = 8
    var keymap: KeyboardKeymap = .default
    var stableUserBucket = 100
    var remoteConfig: HWKRemoteConfig = .safeDefault
    var remoteConfigFetchedAt: Date?
    var inputKernelFallbackDisabled = false
    var predictionDisabled = false
    var glideDisabled = false
    var clipboardDisabled = false
    var saveClipboardSettingsWithLiveKeyboard = true

    static let `default` = KeyboardSettingsSnapshot()
    static let protectedABCLayerSignature = ProtectedABCLayerMap.signature
    static let legacyProtectedABCLayerSignatures = ProtectedABCLayerMap.legacyCompatibleSignatures

    var activeProtectedABCLayerSignature: ProtectedABCLayerSignature? {
        guard layoutLocale == .enUS else {
            return nil
        }

        let signature = Self.protectedABCLayerSignature

        guard letterTopRowKeyCount == signature.topRow.count,
              letterMiddleRowKeyCount == signature.middleRow.count,
              letterBottomRowKeyCount == signature.bottomRow.count else {
            return nil
        }

        let currentTop = ProtectedABCLayerMap.normalizedRow(keymap.letterTopRow, targetCount: letterTopRowKeyCount)
        let currentMiddle = ProtectedABCLayerMap.normalizedRow(
            keymap.letterMiddleRow,
            targetCount: letterMiddleRowKeyCount
        )
        let currentBottom = ProtectedABCLayerMap.normalizedRow(
            keymap.letterBottomRow,
            targetCount: letterBottomRowKeyCount
        )

        let matchesCurrentSignature =
            currentTop == signature.topRow &&
            currentMiddle == signature.middleRow &&
            currentBottom == signature.bottomRow
        let matchesLegacySignature = Self.legacyProtectedABCLayerSignatures.contains {
            currentTop == $0.topRow &&
            currentMiddle == $0.middleRow &&
            currentBottom == $0.bottomRow
        }

        guard matchesCurrentSignature || matchesLegacySignature else {
            return nil
        }

        return signature
    }

    var showsSuggestionRail: Bool {
        autocompleteEnabled || autocorrectEnabled || clickToFixEnabled
    }

    var hasProtectedABCLayer: Bool {
        activeProtectedABCLayerSignature != nil
    }

    static func disableLiveClipboardSavingAfterPastePermissionFailure(
        in defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) {
        var snapshot = Self.load(from: defaults)
        guard snapshot.saveClipboardSettingsWithLiveKeyboard else { return }
        snapshot.saveClipboardSettingsWithLiveKeyboard = false
        snapshot.persist(to: defaults, notify: true)
    }

    static func load() -> KeyboardSettingsSnapshot {
        KeyboardSharedPreferences.migrateLegacyDefaultsIfNeeded()
        KeyboardSharedPreferences.sync()
        return normalizedSnapshot(from: KeyboardSharedPreferences.defaults, persistIfNeeded: true)
    }

    /// Refresh-only read. Launch remains the owner of migration and normalization repair.
    static func loadForExtensionRefresh() -> KeyboardSettingsSnapshot {
        KeyboardSharedPreferences.sync()
        return loadForExtensionRefresh(from: KeyboardSharedPreferences.defaults)
    }

    static func loadForExtensionRefresh(from defaults: UserDefaults) -> KeyboardSettingsSnapshot {
        normalizedSnapshot(from: defaults, persistIfNeeded: false)
    }

    static func load(from defaults: UserDefaults) -> KeyboardSettingsSnapshot {
        normalizedSnapshot(from: defaults, persistIfNeeded: true)
    }

    private static func read(from defaults: UserDefaults) -> KeyboardSettingsSnapshot {
        var snapshot = KeyboardSettingsSnapshot.default

        if defaults.object(forKey: KeyboardSharedPreferences.Key.vibrationEnabled) != nil {
            snapshot.vibrationEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.vibrationEnabled)
        }
        if let appTheme = CompanionAppTheme.resolved(
            from: defaults.string(forKey: KeyboardSharedPreferences.Key.appTheme)
        ) {
            snapshot.appTheme = appTheme
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.accentPalette),
           let accentPalette = KeyboardAccentPalette(rawValue: rawValue) {
            snapshot.accentPalette = accentPalette
        }
        if let customKeyStyleData = defaults.data(forKey: KeyboardSharedPreferences.Key.customKeyStyle),
           let customKeyStyle = try? JSONDecoder().decode(KeyboardCustomKeyStyle.self, from: customKeyStyleData) {
            snapshot.customKeyStyle = customKeyStyle.normalized
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.feedbackLevel),
           let level = KeyboardFeedbackLevel(rawValue: rawValue) {
            snapshot.feedbackLevel = level
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.autoPairEnabled) != nil {
            snapshot.autoPairEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.autoPairEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.startExpanded) != nil {
            snapshot.startExpanded = defaults.bool(forKey: KeyboardSharedPreferences.Key.startExpanded)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.defaultSymbolLayer) != nil {
            snapshot.defaultSymbolLayer = defaults.bool(forKey: KeyboardSharedPreferences.Key.defaultSymbolLayer)
        }
        snapshot.showQuickInsertRow = false
        if defaults.object(forKey: KeyboardSharedPreferences.Key.hideKeyboardEnabled) != nil {
            snapshot.hideKeyboardEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.hideKeyboardEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.highContrastKeys) != nil {
            snapshot.highContrastKeys = defaults.bool(forKey: KeyboardSharedPreferences.Key.highContrastKeys)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.largeLegends) != nil {
            snapshot.largeLegends = defaults.bool(forKey: KeyboardSharedPreferences.Key.largeLegends)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.showControlLabels) != nil {
            snapshot.showControlLabels = defaults.bool(forKey: KeyboardSharedPreferences.Key.showControlLabels)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.capitalizeFirstLetterEnabled) != nil {
            snapshot.capitalizeFirstLetterEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.capitalizeFirstLetterEnabled
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.doubleSpacePeriodEnabled) != nil {
            snapshot.doubleSpacePeriodEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.doubleSpacePeriodEnabled
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.autocorrectEnabled) != nil {
            snapshot.autocorrectEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.autocorrectEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.autocompleteEnabled) != nil {
            snapshot.autocompleteEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.autocompleteEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.clickToFixEnabled) != nil {
            snapshot.clickToFixEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.clickToFixEnabled)
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.autocorrectRankingMethod),
           let method = KeyboardAutocorrectRankingMethod(rawValue: rawValue) {
            snapshot.autocorrectRankingMethod = method
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.autocorrectLogicRecipe),
           let recipe = KeyboardAutocorrectLogicRecipe(rawValue: rawValue) {
            snapshot.autocorrectLogicRecipe = recipe
        }
        if let data = defaults.data(forKey: KeyboardSharedPreferences.Key.autocorrectLogicBlocks),
           let blocks = try? JSONDecoder().decode([KeyboardAutocorrectLogicBlock].self, from: data) {
            snapshot.autocorrectLogicBlocks = Self.normalizedAutocorrectLogicBlocks(blocks)
        }
        if let data = defaults.data(forKey: KeyboardSharedPreferences.Key.autocorrectLogicLanes),
           let lanes = try? JSONDecoder().decode([KeyboardAutocorrectLogicLane].self, from: data) {
            snapshot.autocorrectLogicLanes = Self.normalizedAutocorrectLogicLanes(lanes)
        } else {
            snapshot.autocorrectLogicLanes = KeyboardAutocorrectLogicLane.defaultLanes
        }
        if let data = defaults.data(forKey: KeyboardSharedPreferences.Key.customTextRules),
           let rules = try? JSONDecoder().decode([HWKCustomTextRule].self, from: data) {
            snapshot.customTextRules = rules
        }
        snapshot.semiFoldEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.semiFoldEnabled)
        if let data = defaults.data(forKey: KeyboardSharedPreferences.Key.edgeSwipeConfiguration),
           let configuration = try? JSONDecoder().decode(KeyboardEdgeSwipeConfiguration.self, from: data) {
            snapshot.edgeSwipeConfiguration = configuration
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.suggestionSwipeUpAction),
           let action = KeyboardSuggestionSwipeUpAction(rawValue: rawValue) {
            snapshot.suggestionSwipeUpAction = action
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.suggestionSwipeDownAction),
           let action = KeyboardSuggestionSwipeDownAction(rawValue: rawValue) {
            snapshot.suggestionSwipeDownAction = action
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.suggestionSwipeLeftDeleteEnabled) != nil {
            snapshot.suggestionSwipeLeftDeleteEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.suggestionSwipeLeftDeleteEnabled
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.suggestionSwipeRightSpaceEnabled) != nil {
            snapshot.suggestionSwipeRightSpaceEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.suggestionSwipeRightSpaceEnabled
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.suggestionHoldForRolodexEnabled) != nil {
            snapshot.suggestionHoldForRolodexEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.suggestionHoldForRolodexEnabled
            )
        }
        snapshot.suggestionHoldForRolodexEnabled = true
        if defaults.object(forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorEnabled) != nil {
            snapshot.hardwareAutocorrectSelectorEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorEnabled
            )
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorInitiationKey) {
            snapshot.hardwareAutocorrectSelectorInitiationKey =
                KeyboardHardwareAutocorrectSelectorInitiationKey(rawValue: rawValue) ?? .option
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorSelectionKey),
           let selectionKey = KeyboardHardwareAutocorrectSelectorSelectionKey(rawValue: rawValue) {
            snapshot.hardwareAutocorrectSelectorSelectionKey = selectionKey
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.physicalReturnBehavior),
           let behavior = KeyboardPhysicalReturnBehavior(rawValue: rawValue) {
            snapshot.physicalReturnBehavior = behavior
        }
        snapshot.showQuickInsertHandle = false
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        if defaults.object(forKey: KeyboardSharedPreferences.Key.signalRelayEnabled) != nil {
            snapshot.signalRelayEnabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.signalRelayEnabled
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.signalRelayEmitKeyUp) != nil {
            snapshot.signalRelayEmitKeyUp = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.signalRelayEmitKeyUp
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.signalRelayPriorityMode) != nil {
            snapshot.signalRelayPriorityMode = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.signalRelayPriorityMode
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.signalRelaySessionPersist) != nil {
            snapshot.signalRelaySessionPersist = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.signalRelaySessionPersist
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.signalRelayHoldTriggerMs) != nil {
            snapshot.signalRelayHoldTriggerMs = KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.signalRelayHoldTriggerMs)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.hardwarePremiumAccessUnlocked) != nil {
            snapshot.hardwarePremiumAccessUnlocked = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.hardwarePremiumAccessUnlocked
            )
        }
        #endif
        if defaults.object(forKey: KeyboardSharedPreferences.Key.capsHoldToLockEnabled) != nil {
            snapshot.capsHoldToLockEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.capsHoldToLockEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.capsHoldDurationMs) != nil {
            snapshot.capsHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.capsHoldDurationMs)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.menuHoldToLatchEnabled) != nil {
            snapshot.menuHoldToLatchEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.menuHoldToLatchEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.menuHoldDurationMs) != nil {
            snapshot.menuHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.menuHoldDurationMs)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.keyHoldDurationMs) != nil {
            snapshot.keyHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.keyHoldDurationMs)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.rolodexSelectHoldDurationMs) != nil {
            snapshot.rolodexSelectHoldDurationMs = KeyboardLayoutBounds.clampedRolodexSelectHoldDurationMs(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.rolodexSelectHoldDurationMs)
            )
        }
        snapshot.capsHoldDurationMs = snapshot.keyHoldDurationMs
        snapshot.menuHoldDurationMs = snapshot.keyHoldDurationMs
        if defaults.object(forKey: KeyboardSharedPreferences.Key.menuTapLockWindowMs) != nil {
            snapshot.menuTapLockWindowMs = KeyboardLayoutBounds.clampedMenuTapLockWindowMs(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.menuTapLockWindowMs)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.deleteHoldEnabled) != nil {
            snapshot.deleteHoldEnabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.deleteHoldEnabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.deleteHoldWordsBeforeSentence) != nil {
            snapshot.deleteHoldWordsBeforeSentence = KeyboardLayoutBounds.clampedDeleteHoldWordCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.deleteHoldWordsBeforeSentence)
            )
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.layoutPreset),
           let preset = KeyboardLayoutPreset.resolved(from: rawValue) {
            snapshot.layoutPreset = preset
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.layoutLocale),
           let locale = KeyboardLayoutLocale(rawValue: rawValue) {
            snapshot.layoutLocale = locale
        }
        if let rawValue = defaults.string(forKey: KeyboardSharedPreferences.Key.runtimeLayoutRoute),
           let route = KeyboardRuntimeLayoutRoute(rawValue: rawValue) {
            snapshot.runtimeLayoutRoute = route
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.toolbarHeight) != nil {
            snapshot.toolbarHeight = KeyboardLayoutBounds.clampedToolbarHeight(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.toolbarHeight)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.expandedKeyHeight) != nil {
            snapshot.expandedKeyHeight = KeyboardLayoutBounds.clampedExpandedKeyHeight(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.expandedKeyHeight)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.suggestionVisibleWordCount) != nil {
            snapshot.suggestionVisibleWordCount = KeyboardLayoutBounds.clampedSuggestionVisibleWordCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.suggestionVisibleWordCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.suggestionRowHeight) != nil {
            snapshot.suggestionRowHeight = min(
                max(defaults.integer(forKey: KeyboardSharedPreferences.Key.suggestionRowHeight), KeyboardLayoutBounds.suggestionRowHeightRange.lowerBound),
                KeyboardLayoutBounds.suggestionRowHeightRange.upperBound
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.toolbarKeyCount) != nil {
            snapshot.toolbarKeyCount = KeyboardLayoutBounds.clampedToolbarCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.toolbarKeyCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.symbolTopRowKeyCount) != nil {
            snapshot.symbolTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.symbolTopRowKeyCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.symbolMiddleRowKeyCount) != nil {
            snapshot.symbolMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.symbolMiddleRowKeyCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.symbolBottomRowKeyCount) != nil {
            snapshot.symbolBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.symbolBottomRowKeyCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.letterTopRowKeyCount) != nil {
            snapshot.letterTopRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.letterTopRowKeyCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.letterMiddleRowKeyCount) != nil {
            snapshot.letterMiddleRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.letterMiddleRowKeyCount)
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.letterBottomRowKeyCount) != nil {
            snapshot.letterBottomRowKeyCount = KeyboardLayoutBounds.clampedExpandedCount(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.letterBottomRowKeyCount)
            )
        }
        if let keymapData = defaults.data(forKey: KeyboardSharedPreferences.Key.keymapData) {
            if keymapData.count > KeyboardSharedPreferences.keymapDataByteLimit {
                defaults.removeObject(forKey: KeyboardSharedPreferences.Key.keymapData)
                snapshot.keymap = KeyboardKeymap.preset(snapshot.layoutPreset)
            } else if let keymap = try? JSONDecoder().decode(KeyboardKeymap.self, from: keymapData) {
                snapshot.keymap = keymap
            } else {
                defaults.removeObject(forKey: KeyboardSharedPreferences.Key.keymapData)
                snapshot.keymap = KeyboardKeymap.preset(snapshot.layoutPreset)
            }
        } else {
            snapshot.keymap = KeyboardKeymap.preset(snapshot.layoutPreset)
        }
        defaults.removeObject(forKey: "keyboard.hardwareKeymapData")
        if defaults.object(forKey: KeyboardSharedPreferences.Key.stableUserBucket) != nil {
            snapshot.stableUserBucket = normalizedStableUserBucket(
                defaults.integer(forKey: KeyboardSharedPreferences.Key.stableUserBucket)
            )
        }
        if let remoteConfigData = defaults.data(forKey: KeyboardSharedPreferences.Key.remoteConfig) {
            snapshot.remoteConfig = HWKRemoteConfigDecoder().decode(remoteConfigData)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.remoteConfigFetchedAt) != nil {
            snapshot.remoteConfigFetchedAt = Date(
                timeIntervalSince1970: defaults.double(
                    forKey: KeyboardSharedPreferences.Key.remoteConfigFetchedAt
                )
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.inputKernelFallbackDisabled) != nil {
            snapshot.inputKernelFallbackDisabled = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.inputKernelFallbackDisabled
            )
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.predictionDisabled) != nil {
            snapshot.predictionDisabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.predictionDisabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.glideDisabled) != nil {
            snapshot.glideDisabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.glideDisabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.clipboardDisabled) != nil {
            snapshot.clipboardDisabled = defaults.bool(forKey: KeyboardSharedPreferences.Key.clipboardDisabled)
        }
        if defaults.object(forKey: KeyboardSharedPreferences.Key.saveClipboardSettingsWithLiveKeyboard) != nil {
            snapshot.saveClipboardSettingsWithLiveKeyboard = defaults.bool(
                forKey: KeyboardSharedPreferences.Key.saveClipboardSettingsWithLiveKeyboard
            )
        }

        return snapshot
    }

    private static func normalizedStableUserBucket(_ value: Int) -> Int {
        guard value >= 0 && value < 100 else {
            return 100
        }

        return value
    }

    private static func normalizedAutocorrectLogicBlocks(
        _ blocks: [KeyboardAutocorrectLogicBlock]
    ) -> [KeyboardAutocorrectLogicBlock] {
        let source = (blocks.isEmpty ? KeyboardAutocorrectLogicBlock.defaultPipeline : blocks)
            .sorted { lhs, rhs in
                if lhs.rankPriority == rhs.rankPriority { return lhs.kind.rawValue < rhs.kind.rawValue }
                return lhs.rankPriority < rhs.rankPriority
            }
        return Array(source.prefix(12)).enumerated().map { index, block in
            KeyboardAutocorrectLogicBlock(
                id: block.id,
                kind: block.kind,
                rankPriority: index,
                fallbackEnabled: block.fallbackEnabled || block.role == .fallback,
                dictionaryWeight: min(max(block.dictionaryWeight, 0), 1),
                savedWordsWeight: min(max(block.savedWordsWeight, 0), 1),
                acceptanceThreshold: min(max(block.acceptanceThreshold, 0), 1),
                fallbackTargetID: block.fallbackTargetID,
                chipColor: block.chipColor
            )
        }
    }

    private static func normalizedAutocorrectLogicLaneBlocks(
        _ blocks: [KeyboardAutocorrectLogicBlock],
        family: KeyboardAutocorrectLogicLaneFamily
    ) -> [KeyboardAutocorrectLogicBlock] {
        guard !blocks.contains(where: { $0.kind.laneFamily != nil }) else {
            return blocks
        }

        let intentKind: KeyboardAutocorrectLogicBlockKind
        switch family {
        case .previousWord:
            intentKind = .previousWordLane
        case .correction:
            intentKind = .correctionLane
        case .completion:
            intentKind = .completionLane
        }

        let shiftedBlocks = blocks.map { block in
            KeyboardAutocorrectLogicBlock(
                id: block.id,
                kind: block.kind,
                rankPriority: block.rankPriority + 1,
                fallbackEnabled: block.fallbackEnabled,
                dictionaryWeight: block.dictionaryWeight,
                savedWordsWeight: block.savedWordsWeight,
                acceptanceThreshold: block.acceptanceThreshold,
                fallbackTargetID: block.fallbackTargetID,
                chipColor: block.chipColor
            )
        }
        return normalizedAutocorrectLogicBlocks(
            [KeyboardAutocorrectLogicBlock(kind: intentKind, rankPriority: 0)] + shiftedBlocks
        )
    }

    private static func normalizedAutocorrectLogicLanes(
        _ lanes: [KeyboardAutocorrectLogicLane]
    ) -> [KeyboardAutocorrectLogicLane] {
        let source = lanes.isEmpty ? KeyboardAutocorrectLogicLane.defaultLanes : lanes
        let flattenedDefaultKinds = KeyboardAutocorrectLogicBlock.defaultPipeline.map(\.kind)
        let isFlattenedDefaultRuleSet = (0..<KeyboardAutocorrectLogicLane.laneCount).allSatisfy { index in
            let lane = source.first { $0.id == index } ??
                (source.indices.contains(index) ? source[index] : KeyboardAutocorrectLogicLane.defaultLanes[index])
            return !lane.blocks.contains { $0.kind.laneFamily != nil } &&
                normalizedAutocorrectLogicBlocks(lane.blocks).map(\.kind) == flattenedDefaultKinds
        }
        if isFlattenedDefaultRuleSet {
            return KeyboardAutocorrectLogicLane.defaultLanes
        }

        let normalized = (0..<KeyboardAutocorrectLogicLane.laneCount).map { index in
            let lane = source.first { $0.id == index } ??
                (source.indices.contains(index) ? source[index] : KeyboardAutocorrectLogicLane.defaultLanes[index])
            let defaultLane = KeyboardAutocorrectLogicLane.defaultLanes[index]
            let trimmedTitle = lane.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedReason = lane.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            let obsoleteDefaultTitles = [
                "Previous Word", "Correction", "Completion",
                "Previous Word 2", "Correction 2", "Completion 2",
                "Previous Word 3", "Correction 3", "Completion 3",
            ]
            let usesObsoleteDefaultTitle = obsoleteDefaultTitles.indices.contains(index)
                && trimmedTitle == obsoleteDefaultTitles[index]
            return KeyboardAutocorrectLogicLane(
                id: index,
                title: trimmedTitle.isEmpty || usesObsoleteDefaultTitle ? defaultLane.title : trimmedTitle,
                family: lane.family,
                reason: trimmedReason.isEmpty ? defaultLane.reason : trimmedReason,
                blocks: normalizedAutocorrectLogicLaneBlocks(
                    normalizedAutocorrectLogicBlocks(lane.blocks),
                    family: lane.family
                )
            )
        }
        return normalized
    }

    private static func normalizedSnapshot(
        from defaults: UserDefaults,
        persistIfNeeded: Bool
    ) -> KeyboardSettingsSnapshot {
        var snapshot = read(from: defaults)

        let storedTheme = defaults.string(forKey: KeyboardSharedPreferences.Key.appTheme)
        let storedAccentPalette = defaults.string(forKey: KeyboardSharedPreferences.Key.accentPalette)
        let hasStoredSettings = KeyboardSharedPreferences.hasStoredSettings(in: defaults)

        let normalizedTheme =
            CompanionAppTheme.resolved(from: storedTheme)
            ?? inferredThemeForMissingStoredTheme(snapshot, hasStoredSettings: hasStoredSettings)
        let normalizedAccentPalette = KeyboardAccentPalette(rawValue: storedAccentPalette ?? "") ?? snapshot.accentPalette
        let needsStableBucketSeed =
            defaults.object(forKey: KeyboardSharedPreferences.Key.stableUserBucket) == nil ||
            !(0..<100).contains(snapshot.stableUserBucket)

        let needsThemeNormalization =
            storedTheme != normalizedTheme.rawValue &&
            (storedTheme != nil || hasStoredSettings)
        let needsAccentNormalization = storedAccentPalette != nil && storedAccentPalette != normalizedAccentPalette.rawValue

        if needsThemeNormalization {
            snapshot.appTheme = normalizedTheme
        }

        if needsAccentNormalization {
            snapshot.accentPalette = normalizedAccentPalette
        }

        if needsStableBucketSeed {
            snapshot.stableUserBucket = Int.random(in: 0..<100)
        }

        let repairedPresetSnapshot = repairedCompactPresetSnapshotIfNeeded(snapshot)
        let needsPresetRepair = repairedPresetSnapshot != snapshot
        snapshot = repairedPresetSnapshot

        let repairedABCSnapshot = repairedABCLayerIfNeeded(snapshot)
        let needsABCRepair = repairedABCSnapshot != snapshot
        snapshot = repairedABCSnapshot

        let repairedSymbolHoldSnapshot = repairedSymbolHoldRowsIfNeeded(snapshot)
        let needsSymbolHoldRepair = repairedSymbolHoldSnapshot != snapshot
        snapshot = repairedSymbolHoldSnapshot

        let betaRelayRepair = betaHardwareRelayDefaultsSnapshotIfNeeded(snapshot, defaults: defaults)
        let needsBetaRelayDefaultsRepair = betaRelayRepair.repaired
        snapshot = betaRelayRepair.snapshot

        let strippedInternalSnapshot = strippedInternalHardwareSnapshotIfNeeded(snapshot)
        let needsInternalHardwareStrip = strippedInternalSnapshot != snapshot
        snapshot = strippedInternalSnapshot

        let normalizedEdgeSwipes = snapshot.edgeSwipeConfiguration.normalized(for: snapshot.keymap)
        let needsEdgeSwipeConfigurationRepair = normalizedEdgeSwipes != snapshot.edgeSwipeConfiguration
        snapshot.edgeSwipeConfiguration = normalizedEdgeSwipes

        let needsUnifiedHoldDurationRepair = unifiedHoldDurationPersistRepairNeeded(
            snapshot,
            defaults: defaults,
            hasStoredSettings: hasStoredSettings
        )

        if persistIfNeeded &&
            (
                needsThemeNormalization ||
                needsAccentNormalization ||
                needsStableBucketSeed ||
                needsPresetRepair ||
                needsABCRepair ||
                needsSymbolHoldRepair ||
                needsBetaRelayDefaultsRepair ||
                needsInternalHardwareStrip ||
                needsEdgeSwipeConfigurationRepair ||
                needsUnifiedHoldDurationRepair
            ) {
            snapshot.persist(to: defaults, notify: needsUnifiedHoldDurationRepair)
            markBetaHardwareRelayDefaultsRepairedIfNeeded(defaults, repaired: needsBetaRelayDefaultsRepair)
        }

        return snapshot
    }

    private static func unifiedHoldDurationPersistRepairNeeded(
        _ snapshot: KeyboardSettingsSnapshot,
        defaults: UserDefaults,
        hasStoredSettings: Bool
    ) -> Bool {
        guard hasStoredSettings else { return false }

        let expectedDuration = KeyboardLayoutBounds.clampedHoldActivationDurationMs(snapshot.keyHoldDurationMs)
        let durationKeys = [
            KeyboardSharedPreferences.Key.keyHoldDurationMs,
            KeyboardSharedPreferences.Key.capsHoldDurationMs,
            KeyboardSharedPreferences.Key.menuHoldDurationMs,
        ]
        return durationKeys.contains { key in
            guard defaults.object(forKey: key) != nil else { return true }
            return KeyboardLayoutBounds.clampedHoldActivationDurationMs(defaults.integer(forKey: key)) != expectedDuration
        }
    }

    private static func betaHardwareRelayDefaultsSnapshotIfNeeded(
        _ snapshot: KeyboardSettingsSnapshot,
        defaults: UserDefaults
    ) -> (snapshot: KeyboardSettingsSnapshot, repaired: Bool) {
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        guard HWCBuildFlavor.hardwarePurchaseGateRepairEnabled else {
            return (snapshot, false)
        }
        let currentBuild = KeyboardSharedPreferences.currentBundleBuildNumberString()
        guard KeyboardSharedPreferences.betaHardwareRelayDefaultsNeedsRepair(
            repairedBuildValue: defaults.object(forKey: KeyboardSharedPreferences.Key.signalRelayBetaDefaultsRepairedBuild),
            currentBuild: currentBuild,
            isBeta: HWCBuildFlavor.hardwarePurchaseGateRepairEnabled
        ) else {
            return (snapshot, false)
        }

        var snapshot = snapshot
        snapshot.signalRelayEnabled = false
        snapshot.signalRelayEmitKeyUp = true
        snapshot.signalRelayPriorityMode = false
        snapshot.signalRelaySessionPersist = false
        snapshot.hardwarePremiumAccessUnlocked = HWCBuildFlavor.autoUnlockPaidFeatures
        snapshot.signalRelayHoldTriggerMs = KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(
            snapshot.signalRelayHoldTriggerMs
        )
        return (snapshot, true)
        #else
        return (snapshot, false)
        #endif
    }

    private static func markBetaHardwareRelayDefaultsRepairedIfNeeded(
        _ defaults: UserDefaults,
        repaired: Bool
    ) {
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        guard repaired else { return }
        defaults.set(
            KeyboardSharedPreferences.currentBundleBuildNumberString(),
            forKey: KeyboardSharedPreferences.Key.signalRelayBetaDefaultsRepairedBuild
        )
        #endif
    }

    private static func inferredThemeForMissingStoredTheme(
        _ snapshot: KeyboardSettingsSnapshot,
        hasStoredSettings: Bool
    ) -> CompanionAppTheme {
        guard hasStoredSettings else {
            return .classic
        }

        if snapshot.layoutPreset == .compact {
            return .dark
        }

        let compactPresetKeymap = KeyboardKeymap.preset(.compact)
        let matchesCompactPreset =
            snapshot.layoutPreset == .custom &&
            snapshot.keymap == compactPresetKeymap &&
            snapshot.toolbarKeyCount == 8 &&
            snapshot.symbolTopRowKeyCount == 10 &&
            snapshot.symbolMiddleRowKeyCount == 10 &&
            snapshot.symbolBottomRowKeyCount == 10 &&
            snapshot.letterTopRowKeyCount == 10 &&
            snapshot.letterMiddleRowKeyCount == 9 &&
            snapshot.letterBottomRowKeyCount == 8

        return matchesCompactPreset ? .dark : .classic
    }

    private static func repairedCompactPresetSnapshotIfNeeded(
        _ snapshot: KeyboardSettingsSnapshot
    ) -> KeyboardSettingsSnapshot {
        guard snapshot.layoutPreset == .compact else {
            return snapshot
        }

        let presetKeymap = KeyboardKeymap.preset(.compact)
        let expectedToolbarCount = 8
        let expectedExpandedCounts = (top: 10, middle: 10, bottom: 10)
        let expectedLetterCounts = (top: 10, middle: 9, bottom: 8)

        let needsRepair =
            snapshot.toolbarKeyCount != expectedToolbarCount ||
            snapshot.symbolTopRowKeyCount != expectedExpandedCounts.top ||
            snapshot.symbolMiddleRowKeyCount != expectedExpandedCounts.middle ||
            snapshot.symbolBottomRowKeyCount != expectedExpandedCounts.bottom ||
            snapshot.letterTopRowKeyCount != expectedLetterCounts.top ||
            snapshot.letterMiddleRowKeyCount != expectedLetterCounts.middle ||
            snapshot.letterBottomRowKeyCount != expectedLetterCounts.bottom ||
            snapshot.keymap != presetKeymap

        guard needsRepair else {
            return snapshot
        }

        var repaired = snapshot
        repaired.toolbarKeyCount = expectedToolbarCount
        repaired.symbolTopRowKeyCount = expectedExpandedCounts.top
        repaired.symbolMiddleRowKeyCount = expectedExpandedCounts.middle
        repaired.symbolBottomRowKeyCount = expectedExpandedCounts.bottom
        repaired.letterTopRowKeyCount = expectedLetterCounts.top
        repaired.letterMiddleRowKeyCount = expectedLetterCounts.middle
        repaired.letterBottomRowKeyCount = expectedLetterCounts.bottom
        repaired.keymap = presetKeymap
        return repaired
    }

    private static func repairedSymbolHoldRowsIfNeeded(
        _ snapshot: KeyboardSettingsSnapshot
    ) -> KeyboardSettingsSnapshot {
        var keymap = snapshot.keymap
        var repaired = false

        repairMissingSymbolHoldRow(
            &keymap.holdSymbolTopRow,
            fallback: KeyboardKeymap.commonHoldSymbolTopRow,
            repairsOldNumberRow: false,
            repaired: &repaired
        )
        repairMissingSymbolHoldRow(
            &keymap.holdSymbolMiddleRow,
            fallback: KeyboardKeymap.commonHoldSymbolMiddleRow,
            repairsOldNumberRow: true,
            repaired: &repaired
        )
        repairMissingSymbolHoldRow(
            &keymap.holdSymbolBottomRow,
            fallback: KeyboardKeymap.commonHoldSymbolBottomRow,
            repairsOldNumberRow: false,
            repaired: &repaired
        )

        guard repaired else { return snapshot }

        var next = snapshot
        keymap.rows = keymap.rowsSynchronizedFromLegacyFields()
        next.keymap = keymap
        return next
    }

    private static func repairMissingSymbolHoldRow(
        _ row: inout [String],
        fallback: [String],
        repairsOldNumberRow: Bool,
        repaired: inout Bool
    ) {
        let oldNumberHoldRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        guard row.allSatisfy({ $0.isEmpty }) || (repairsOldNumberRow && row == oldNumberHoldRow) else { return }

        row = fallback
        repaired = true
    }

    private static func repairedABCLayerIfNeeded(
        _ snapshot: KeyboardSettingsSnapshot
    ) -> KeyboardSettingsSnapshot {
        guard let preset = abcRepairPreset(for: snapshot) else {
            return snapshot
        }

        let presetKeymap = KeyboardKeymap.preset(preset)
        var repaired = snapshot
        let targetCounts = (
            top: KeyboardLayoutBounds.clampedExpandedCount(snapshot.letterTopRowKeyCount),
            middle: KeyboardLayoutBounds.clampedExpandedCount(snapshot.letterMiddleRowKeyCount),
            bottom: KeyboardLayoutBounds.clampedExpandedCount(snapshot.letterBottomRowKeyCount)
        )

        if snapshot.hasProtectedABCLayer {
            repaired.keymap.letterTopRow = repairedProtectedABCRow(
                current: repaired.keymap.letterTopRow,
                preset: presetKeymap.letterTopRow,
                row: .letterTop,
                targetCount: targetCounts.top
            )
            repaired.keymap.letterMiddleRow = repairedProtectedABCRow(
                current: repaired.keymap.letterMiddleRow,
                preset: presetKeymap.letterMiddleRow,
                row: .letterMiddle,
                targetCount: targetCounts.middle
            )
            repaired.keymap.letterBottomRow = repairedProtectedABCRow(
                current: repaired.keymap.letterBottomRow,
                preset: presetKeymap.letterBottomRow,
                row: .letterBottom,
                targetCount: targetCounts.bottom
            )
            repaired.keymap.holdLetterTopRow = repairedProtectedABCRow(
                current: repaired.keymap.holdLetterTopRow,
                preset: presetKeymap.holdLetterTopRow,
                row: .letterTop,
                targetCount: targetCounts.top
            )
            repaired.keymap.holdLetterMiddleRow = repairedProtectedABCRow(
                current: repaired.keymap.holdLetterMiddleRow,
                preset: presetKeymap.holdLetterMiddleRow,
                row: .letterMiddle,
                targetCount: targetCounts.middle
            )
            repaired.keymap.holdLetterBottomRow = repairedProtectedABCRow(
                current: repaired.keymap.holdLetterBottomRow,
                preset: presetKeymap.holdLetterBottomRow,
                row: .letterBottom,
                targetCount: targetCounts.bottom
            )
            return repaired
        }

        if editableRowIsEffectivelyEmpty(repaired.keymap.letterTopRow, targetCount: targetCounts.top) {
            repaired.keymap.letterTopRow = normalizedEditableRow(presetKeymap.letterTopRow, targetCount: targetCounts.top)
        }
        if editableRowIsEffectivelyEmpty(repaired.keymap.letterMiddleRow, targetCount: targetCounts.middle) {
            repaired.keymap.letterMiddleRow = normalizedEditableRow(
                presetKeymap.letterMiddleRow,
                targetCount: targetCounts.middle
            )
        }
        if editableRowIsEffectivelyEmpty(repaired.keymap.letterBottomRow, targetCount: targetCounts.bottom) {
            repaired.keymap.letterBottomRow = normalizedEditableRow(
                presetKeymap.letterBottomRow,
                targetCount: targetCounts.bottom
            )
        }

        if let repairedTopHold = repairedHoldRowIfNeeded(
            tapRow: repaired.keymap.letterTopRow,
            holdRow: repaired.keymap.holdLetterTopRow,
            presetTapRow: presetKeymap.letterTopRow,
            presetHoldRow: presetKeymap.holdLetterTopRow,
            targetCount: targetCounts.top
        ) {
            repaired.keymap.holdLetterTopRow = repairedTopHold
        }
        if let repairedMiddleHold = repairedHoldRowIfNeeded(
            tapRow: repaired.keymap.letterMiddleRow,
            holdRow: repaired.keymap.holdLetterMiddleRow,
            presetTapRow: presetKeymap.letterMiddleRow,
            presetHoldRow: presetKeymap.holdLetterMiddleRow,
            targetCount: targetCounts.middle
        ) {
            repaired.keymap.holdLetterMiddleRow = repairedMiddleHold
        }
        if let repairedBottomHold = repairedHoldRowIfNeeded(
            tapRow: repaired.keymap.letterBottomRow,
            holdRow: repaired.keymap.holdLetterBottomRow,
            presetTapRow: presetKeymap.letterBottomRow,
            presetHoldRow: presetKeymap.holdLetterBottomRow,
            targetCount: targetCounts.bottom
        ) {
            repaired.keymap.holdLetterBottomRow = repairedBottomHold
        }

        return repaired
    }

    private static func repairedProtectedABCRow(
        current: [String],
        preset: [String],
        row: KeyboardRowKind,
        targetCount: Int
    ) -> [String] {
        var repaired = normalizedEditableRow(current, targetCount: targetCount)
        let presetRow = normalizedEditableRow(preset, targetCount: targetCount)
        for index in ProtectedABCLayerMap.lockedSlotIndexes(for: row) where repaired.indices.contains(index) {
            repaired[index] = presetRow.indices.contains(index) ? presetRow[index] : ""
        }
        return repaired
    }

    private static func abcRepairPreset(for snapshot: KeyboardSettingsSnapshot) -> KeyboardLayoutPreset? {
        if snapshot.layoutPreset != .custom {
            return snapshot.layoutPreset
        }

        return snapshot.hasProtectedABCLayer ? .compact : nil
    }

    private static func strippedInternalHardwareSnapshotIfNeeded(
        _ snapshot: KeyboardSettingsSnapshot
    ) -> KeyboardSettingsSnapshot {
        guard !HWCBuildFlavor.readerRetired else { return snapshot }
        #if HWC_INTERNAL_BUILD
        guard !HWCBuildFlavor.supportsHardwareDebugTools else {
            return snapshot
        }

        let defaultSnapshot = KeyboardSettingsSnapshot.default
        let needsStrip =
            snapshot.signalRelayEnabled != defaultSnapshot.signalRelayEnabled ||
            snapshot.signalRelayEmitKeyUp != defaultSnapshot.signalRelayEmitKeyUp ||
            snapshot.signalRelayPriorityMode != defaultSnapshot.signalRelayPriorityMode ||
            snapshot.signalRelaySessionPersist != defaultSnapshot.signalRelaySessionPersist ||
            snapshot.signalRelayHoldTriggerMs != defaultSnapshot.signalRelayHoldTriggerMs

        guard needsStrip else {
            return snapshot
        }

        var stripped = snapshot
        stripped.signalRelayEnabled = defaultSnapshot.signalRelayEnabled
        stripped.signalRelayEmitKeyUp = defaultSnapshot.signalRelayEmitKeyUp
        stripped.signalRelayPriorityMode = defaultSnapshot.signalRelayPriorityMode
        stripped.signalRelaySessionPersist = defaultSnapshot.signalRelaySessionPersist
        stripped.signalRelayHoldTriggerMs = defaultSnapshot.signalRelayHoldTriggerMs
        return stripped
        #else
        return snapshot
        #endif
    }

    private static func repairedHoldRowIfNeeded(
        tapRow: [String],
        holdRow: [String],
        presetTapRow: [String],
        presetHoldRow: [String],
        targetCount: Int
    ) -> [String]? {
        guard editableRowIsEffectivelyEmpty(holdRow, targetCount: targetCount) else {
            return nil
        }

        let normalizedTapRow = normalizedEditableRow(tapRow, targetCount: targetCount)
        let normalizedPresetTapRow = normalizedEditableRow(presetTapRow, targetCount: targetCount)
        guard normalizedTapRow == normalizedPresetTapRow else {
            return nil
        }

        return normalizedEditableRow(presetHoldRow, targetCount: targetCount)
    }

    private static func normalizedEditableRow(_ values: [String], targetCount: Int) -> [String] {
        let clampedCount = max(0, targetCount)
        var normalized = Array(values.prefix(clampedCount)).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while normalized.count < clampedCount {
            normalized.append("")
        }
        return normalized
    }

    private static func editableRowIsEffectivelyEmpty(_ values: [String], targetCount: Int) -> Bool {
        normalizedEditableRow(values, targetCount: targetCount).allSatisfy(\.isEmpty)
    }

    func persist(to defaults: UserDefaults = KeyboardSharedPreferences.defaults, notify: Bool = true) {
        let unifiedHoldDurationMs = KeyboardLayoutBounds.clampedHoldActivationDurationMs(keyHoldDurationMs)
        var normalized = KeyboardSettingsSnapshot(
            appTheme: appTheme,
            accentPalette: accentPalette,
            customKeyStyle: customKeyStyle.normalized,
            vibrationEnabled: vibrationEnabled,
            feedbackLevel: feedbackLevel,
            autoPairEnabled: autoPairEnabled,
            startExpanded: startExpanded,
            defaultSymbolLayer: defaultSymbolLayer,
            showQuickInsertRow: showQuickInsertRow,
            hideKeyboardEnabled: hideKeyboardEnabled,
            highContrastKeys: highContrastKeys,
            largeLegends: largeLegends,
            showControlLabels: showControlLabels,
            capitalizeFirstLetterEnabled: capitalizeFirstLetterEnabled,
            doubleSpacePeriodEnabled: doubleSpacePeriodEnabled,
            autocorrectEnabled: autocorrectEnabled,
            autocompleteEnabled: autocompleteEnabled,
            clickToFixEnabled: clickToFixEnabled,
            autocorrectRankingMethod: autocorrectRankingMethod,
            autocorrectLogicRecipe: autocorrectLogicRecipe,
            autocorrectLogicBlocks: Self.normalizedAutocorrectLogicBlocks(autocorrectLogicBlocks),
            autocorrectLogicLanes: Self.normalizedAutocorrectLogicLanes(autocorrectLogicLanes),
            customTextRules: customTextRules,
            edgeSwipeConfiguration: edgeSwipeConfiguration.normalized(for: keymap),
            semiFoldEnabled: semiFoldEnabled,
            suggestionSwipeUpAction: suggestionSwipeUpAction,
            suggestionSwipeDownAction: suggestionSwipeDownAction,
            suggestionSwipeLeftDeleteEnabled: suggestionSwipeLeftDeleteEnabled,
            suggestionSwipeRightSpaceEnabled: suggestionSwipeRightSpaceEnabled,
            suggestionHoldForRolodexEnabled: true,
            hardwareAutocorrectSelectorEnabled: hardwareAutocorrectSelectorEnabled,
            hardwareAutocorrectSelectorInitiationKey: hardwareAutocorrectSelectorInitiationKey,
            hardwareAutocorrectSelectorSelectionKey: hardwareAutocorrectSelectorSelectionKey,
            physicalReturnBehavior: physicalReturnBehavior,
            showQuickInsertHandle: showQuickInsertHandle,
            capsHoldToLockEnabled: capsHoldToLockEnabled,
            capsHoldDurationMs: unifiedHoldDurationMs,
            menuHoldToLatchEnabled: menuHoldToLatchEnabled,
            menuHoldDurationMs: unifiedHoldDurationMs,
            keyHoldDurationMs: unifiedHoldDurationMs,
            rolodexSelectHoldDurationMs: KeyboardLayoutBounds.clampedRolodexSelectHoldDurationMs(
                rolodexSelectHoldDurationMs
            ),
            menuTapLockWindowMs: KeyboardLayoutBounds.clampedMenuTapLockWindowMs(menuTapLockWindowMs),
            deleteHoldEnabled: deleteHoldEnabled,
            deleteHoldWordsBeforeSentence: KeyboardLayoutBounds.clampedDeleteHoldWordCount(
                deleteHoldWordsBeforeSentence
            ),
            layoutPreset: layoutPreset,
            layoutLocale: layoutLocale,
            runtimeLayoutRoute: runtimeLayoutRoute,
            toolbarHeight: KeyboardLayoutBounds.clampedToolbarHeight(toolbarHeight),
            expandedKeyHeight: KeyboardLayoutBounds.clampedExpandedKeyHeight(expandedKeyHeight),
            suggestionVisibleWordCount: KeyboardLayoutBounds.clampedSuggestionVisibleWordCount(suggestionVisibleWordCount),
            suggestionRowHeight: min(max(suggestionRowHeight, KeyboardLayoutBounds.suggestionRowHeightRange.lowerBound), KeyboardLayoutBounds.suggestionRowHeightRange.upperBound),
            toolbarKeyCount: KeyboardLayoutBounds.clampedToolbarCount(toolbarKeyCount),
            symbolTopRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(symbolTopRowKeyCount),
            symbolMiddleRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(symbolMiddleRowKeyCount),
            symbolBottomRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(symbolBottomRowKeyCount),
            letterTopRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(letterTopRowKeyCount),
            letterMiddleRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(letterMiddleRowKeyCount),
            letterBottomRowKeyCount: KeyboardLayoutBounds.clampedExpandedCount(letterBottomRowKeyCount),
            keymap: keymap,
            inputKernelFallbackDisabled: inputKernelFallbackDisabled,
            predictionDisabled: predictionDisabled,
            glideDisabled: glideDisabled,
            clipboardDisabled: clipboardDisabled,
            saveClipboardSettingsWithLiveKeyboard: saveClipboardSettingsWithLiveKeyboard
        )
        normalized.stableUserBucket = Self.normalizedStableUserBucket(stableUserBucket)
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        normalized.signalRelayEnabled = signalRelayEnabled
        normalized.signalRelayEmitKeyUp = signalRelayEmitKeyUp
        normalized.signalRelayPriorityMode = signalRelayPriorityMode
        normalized.signalRelaySessionPersist = signalRelaySessionPersist
        normalized.signalRelayHoldTriggerMs = KeyboardLayoutBounds.clampedHardwareHoldTriggerMs(signalRelayHoldTriggerMs)
        normalized.hardwarePremiumAccessUnlocked = hardwarePremiumAccessUnlocked
        #endif

        let existingSnapshot = Self.normalizedSnapshot(from: defaults, persistIfNeeded: false)
        let missingStableBucket = defaults.object(forKey: KeyboardSharedPreferences.Key.stableUserBucket) == nil
        let needsUnifiedHoldDurationRepair = Self.unifiedHoldDurationPersistRepairNeeded(
            normalized,
            defaults: defaults,
            hasStoredSettings: KeyboardSharedPreferences.hasStoredSettings(in: defaults)
        )
        let storedEdgeSwipes = defaults.data(forKey: KeyboardSharedPreferences.Key.edgeSwipeConfiguration)
            .flatMap { try? JSONDecoder().decode(KeyboardEdgeSwipeConfiguration.self, from: $0) }
        let needsEdgeSwipeConfigurationRepair = storedEdgeSwipes != nil && storedEdgeSwipes != normalized.edgeSwipeConfiguration
        guard existingSnapshot != normalized || missingStableBucket || needsUnifiedHoldDurationRepair || needsEdgeSwipeConfigurationRepair else { return }

        defaults.set(normalized.appTheme.rawValue, forKey: KeyboardSharedPreferences.Key.appTheme)
        defaults.set(normalized.accentPalette.rawValue, forKey: KeyboardSharedPreferences.Key.accentPalette)
        defaults.set(try? JSONEncoder().encode(normalized.customKeyStyle), forKey: KeyboardSharedPreferences.Key.customKeyStyle)
        defaults.set(normalized.vibrationEnabled, forKey: KeyboardSharedPreferences.Key.vibrationEnabled)
        defaults.set(normalized.feedbackLevel.rawValue, forKey: KeyboardSharedPreferences.Key.feedbackLevel)
        defaults.set(normalized.autoPairEnabled, forKey: KeyboardSharedPreferences.Key.autoPairEnabled)
        defaults.set(normalized.startExpanded, forKey: KeyboardSharedPreferences.Key.startExpanded)
        defaults.set(normalized.defaultSymbolLayer, forKey: KeyboardSharedPreferences.Key.defaultSymbolLayer)
        defaults.set(normalized.showQuickInsertRow, forKey: KeyboardSharedPreferences.Key.showQuickInsertRow)
        defaults.set(normalized.hideKeyboardEnabled, forKey: KeyboardSharedPreferences.Key.hideKeyboardEnabled)
        defaults.set(normalized.highContrastKeys, forKey: KeyboardSharedPreferences.Key.highContrastKeys)
        defaults.set(normalized.largeLegends, forKey: KeyboardSharedPreferences.Key.largeLegends)
        defaults.set(normalized.showControlLabels, forKey: KeyboardSharedPreferences.Key.showControlLabels)
        defaults.set(
            normalized.capitalizeFirstLetterEnabled,
            forKey: KeyboardSharedPreferences.Key.capitalizeFirstLetterEnabled
        )
        defaults.set(
            normalized.doubleSpacePeriodEnabled,
            forKey: KeyboardSharedPreferences.Key.doubleSpacePeriodEnabled
        )
        defaults.set(try? JSONEncoder().encode(normalized.edgeSwipeConfiguration),
                     forKey: KeyboardSharedPreferences.Key.edgeSwipeConfiguration)
        defaults.set(normalized.semiFoldEnabled, forKey: KeyboardSharedPreferences.Key.semiFoldEnabled)
        defaults.set(normalized.autocorrectEnabled, forKey: KeyboardSharedPreferences.Key.autocorrectEnabled)
        defaults.set(normalized.autocompleteEnabled, forKey: KeyboardSharedPreferences.Key.autocompleteEnabled)
        defaults.set(normalized.clickToFixEnabled, forKey: KeyboardSharedPreferences.Key.clickToFixEnabled)
        defaults.set(
            normalized.autocorrectRankingMethod.rawValue,
            forKey: KeyboardSharedPreferences.Key.autocorrectRankingMethod
        )
        defaults.set(
            normalized.autocorrectLogicRecipe.rawValue,
            forKey: KeyboardSharedPreferences.Key.autocorrectLogicRecipe
        )
        defaults.set(
            try? JSONEncoder().encode(normalized.autocorrectLogicBlocks),
            forKey: KeyboardSharedPreferences.Key.autocorrectLogicBlocks
        )
        defaults.set(
            try? JSONEncoder().encode(normalized.autocorrectLogicLanes),
            forKey: KeyboardSharedPreferences.Key.autocorrectLogicLanes
        )
        defaults.set(
            try? JSONEncoder().encode(normalized.customTextRules),
            forKey: KeyboardSharedPreferences.Key.customTextRules
        )
        defaults.set(
            normalized.suggestionSwipeUpAction.rawValue,
            forKey: KeyboardSharedPreferences.Key.suggestionSwipeUpAction
        )
        defaults.set(
            normalized.suggestionSwipeDownAction.rawValue,
            forKey: KeyboardSharedPreferences.Key.suggestionSwipeDownAction
        )
        defaults.set(
            normalized.suggestionSwipeLeftDeleteEnabled,
            forKey: KeyboardSharedPreferences.Key.suggestionSwipeLeftDeleteEnabled
        )
        defaults.set(
            normalized.suggestionSwipeRightSpaceEnabled,
            forKey: KeyboardSharedPreferences.Key.suggestionSwipeRightSpaceEnabled
        )
        defaults.set(
            normalized.suggestionHoldForRolodexEnabled,
            forKey: KeyboardSharedPreferences.Key.suggestionHoldForRolodexEnabled
        )
        defaults.set(
            normalized.hardwareAutocorrectSelectorEnabled,
            forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorEnabled
        )
        defaults.set(
            normalized.hardwareAutocorrectSelectorInitiationKey.rawValue,
            forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorInitiationKey
        )
        defaults.set(
            normalized.hardwareAutocorrectSelectorSelectionKey.rawValue,
            forKey: KeyboardSharedPreferences.Key.hardwareAutocorrectSelectorSelectionKey
        )
        defaults.set(
            normalized.physicalReturnBehavior.rawValue,
            forKey: KeyboardSharedPreferences.Key.physicalReturnBehavior
        )
        defaults.set(
            normalized.showQuickInsertHandle,
            forKey: KeyboardSharedPreferences.Key.showQuickInsertHandle
        )
        defaults.set(
            normalized.inputKernelFallbackDisabled,
            forKey: KeyboardSharedPreferences.Key.inputKernelFallbackDisabled
        )
        defaults.set(normalized.predictionDisabled, forKey: KeyboardSharedPreferences.Key.predictionDisabled)
        defaults.set(normalized.glideDisabled, forKey: KeyboardSharedPreferences.Key.glideDisabled)
        defaults.set(normalized.clipboardDisabled, forKey: KeyboardSharedPreferences.Key.clipboardDisabled)
        defaults.set(
            normalized.saveClipboardSettingsWithLiveKeyboard,
            forKey: KeyboardSharedPreferences.Key.saveClipboardSettingsWithLiveKeyboard
        )
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        defaults.set(
            normalized.signalRelayEnabled,
            forKey: KeyboardSharedPreferences.Key.signalRelayEnabled
        )
        defaults.set(
            normalized.signalRelayEmitKeyUp,
            forKey: KeyboardSharedPreferences.Key.signalRelayEmitKeyUp
        )
        defaults.set(
            normalized.signalRelayPriorityMode,
            forKey: KeyboardSharedPreferences.Key.signalRelayPriorityMode
        )
        defaults.set(
            normalized.signalRelaySessionPersist,
            forKey: KeyboardSharedPreferences.Key.signalRelaySessionPersist
        )
        defaults.set(
            normalized.signalRelayHoldTriggerMs,
            forKey: KeyboardSharedPreferences.Key.signalRelayHoldTriggerMs
        )
        defaults.set(
            normalized.hardwarePremiumAccessUnlocked,
            forKey: KeyboardSharedPreferences.Key.hardwarePremiumAccessUnlocked
        )
        #endif
        defaults.set(normalized.capsHoldToLockEnabled, forKey: KeyboardSharedPreferences.Key.capsHoldToLockEnabled)
        defaults.set(normalized.capsHoldDurationMs, forKey: KeyboardSharedPreferences.Key.capsHoldDurationMs)
        defaults.set(normalized.menuHoldToLatchEnabled, forKey: KeyboardSharedPreferences.Key.menuHoldToLatchEnabled)
        defaults.set(normalized.menuHoldDurationMs, forKey: KeyboardSharedPreferences.Key.menuHoldDurationMs)
        defaults.set(normalized.keyHoldDurationMs, forKey: KeyboardSharedPreferences.Key.keyHoldDurationMs)
        defaults.set(
            normalized.rolodexSelectHoldDurationMs,
            forKey: KeyboardSharedPreferences.Key.rolodexSelectHoldDurationMs
        )
        defaults.set(normalized.menuTapLockWindowMs, forKey: KeyboardSharedPreferences.Key.menuTapLockWindowMs)
        defaults.set(normalized.deleteHoldEnabled, forKey: KeyboardSharedPreferences.Key.deleteHoldEnabled)
        defaults.set(
            normalized.deleteHoldWordsBeforeSentence,
            forKey: KeyboardSharedPreferences.Key.deleteHoldWordsBeforeSentence
        )
        defaults.set(normalized.layoutPreset.rawValue, forKey: KeyboardSharedPreferences.Key.layoutPreset)
        defaults.set(normalized.layoutLocale.rawValue, forKey: KeyboardSharedPreferences.Key.layoutLocale)
        defaults.set(normalized.runtimeLayoutRoute.rawValue, forKey: KeyboardSharedPreferences.Key.runtimeLayoutRoute)
        defaults.set(normalized.toolbarHeight, forKey: KeyboardSharedPreferences.Key.toolbarHeight)
        defaults.set(
            normalized.expandedKeyHeight,
            forKey: KeyboardSharedPreferences.Key.expandedKeyHeight
        )
        defaults.set(
            normalized.suggestionVisibleWordCount,
            forKey: KeyboardSharedPreferences.Key.suggestionVisibleWordCount
        )
        defaults.set(normalized.suggestionRowHeight, forKey: KeyboardSharedPreferences.Key.suggestionRowHeight)
        defaults.set(normalized.toolbarKeyCount, forKey: KeyboardSharedPreferences.Key.toolbarKeyCount)
        defaults.set(normalized.symbolTopRowKeyCount, forKey: KeyboardSharedPreferences.Key.symbolTopRowKeyCount)
        defaults.set(normalized.symbolMiddleRowKeyCount, forKey: KeyboardSharedPreferences.Key.symbolMiddleRowKeyCount)
        defaults.set(normalized.symbolBottomRowKeyCount, forKey: KeyboardSharedPreferences.Key.symbolBottomRowKeyCount)
        defaults.set(normalized.letterTopRowKeyCount, forKey: KeyboardSharedPreferences.Key.letterTopRowKeyCount)
        defaults.set(normalized.letterMiddleRowKeyCount, forKey: KeyboardSharedPreferences.Key.letterMiddleRowKeyCount)
        defaults.set(normalized.letterBottomRowKeyCount, forKey: KeyboardSharedPreferences.Key.letterBottomRowKeyCount)
        defaults.set(try? JSONEncoder().encode(normalized.keymap), forKey: KeyboardSharedPreferences.Key.keymapData)
        defaults.removeObject(forKey: "keyboard.hardwareKeymapData")
        defaults.set(normalized.stableUserBucket, forKey: KeyboardSharedPreferences.Key.stableUserBucket)
        KeyboardSharedPreferences.obsoleteKeys.forEach { defaults.removeObject(forKey: $0) }
        KeyboardSharedPreferences.sync()
        if notify {
            KeyboardSharedPreferences.postSettingsDidChangeNotification()
        }
    }
}

struct ProtectedABCLayerSignature: Equatable {
    let topRow: [String]
    let middleRow: [String]
    let bottomRow: [String]
}

struct ProtectedABCLayerMap {
    static let defaultLetters = "qwertyuiopasdfghjklzxcvbnm"
    private static let defaultLetterValues = Set(defaultLetters.map { String($0) })
    private static let protectedTopLetters = Array("qwertyuiop").map(String.init)
    private static let protectedMiddleLetters = Array("asdfghjkl").map(String.init)
    private static let protectedBottomLetters = Array("zxcvbnm").map(String.init)
    static let topRow = KeyboardKeymap.defaultLetterTopRow.map(normalizedValue)
    static let middleRow = KeyboardKeymap.defaultLetterMiddleRow.map(normalizedValue)
    static let bottomRow = KeyboardKeymap.defaultLetterBottomRow.map(normalizedValue)
    static let signature = ProtectedABCLayerSignature(
        topRow: topRow,
        middleRow: middleRow,
        bottomRow: bottomRow
    )
    static let legacyCompatibleSignatures = [
        ProtectedABCLayerSignature(
            topRow: KeyboardKeymap.defaultLetterTopRow.map(normalizedValue),
            middleRow: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "enter"].map(normalizedValue),
            bottomRow: ["z", "x", "c", "v", "b", "n", "m", ",", ":"].map(normalizedValue)
        ),
        ProtectedABCLayerSignature(
            topRow: KeyboardKeymap.defaultLetterTopRow.map(normalizedValue),
            middleRow: ["a", "s", "d", "f", "g", "h", "j", "k", "l", ":"].map(normalizedValue),
            bottomRow: ["z", "x", "c", "v", "b", "n", "m", ",", "."].map(normalizedValue)
        )
    ]
    static let lockedSlotIndexesByRow: [KeyboardRowKind: Set<Int>] = [
        .letterTop: Set(protectedTopLetters.indices),
        .letterMiddle: Set(protectedMiddleLetters.indices),
        .letterBottom: Set(protectedBottomLetters.indices),
    ]

    static func lockedSlotIndexes(for row: KeyboardRowKind) -> Set<Int> {
        lockedSlotIndexesByRow[row.tapVariant] ?? []
    }

    static func defaultRow(for row: KeyboardRowKind) -> [String]? {
        switch row.tapVariant {
        case .letterTop:
            return topRow
        case .letterMiddle:
            return middleRow
        case .letterBottom:
            return bottomRow
        default:
            return nil
        }
    }

    static func normalizedRow(_ values: [String], targetCount: Int) -> [String] {
        let clampedCount = max(0, targetCount)
        var normalized = Array(values.prefix(clampedCount)).map(normalizedValue)
        while normalized.count < clampedCount {
            normalized.append("")
        }
        return normalized
    }

    static func normalizedValue(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 1,
              defaultLetterValues.contains(trimmed) else {
            return ""
        }
        return trimmed
    }
}

enum KeyboardFeedbackEngine {
    // Companion settings previews have no keyboard host. Keyboard controllers own their player.
    private static let previewPlayer = KeyboardFeedbackPlayer()

    static func prepare(using settings: KeyboardSettingsSnapshot) {
        previewPlayer.prepare(using: settings)
    }

    static func play(using settings: KeyboardSettingsSnapshot) {
        previewPlayer.play(using: settings)
    }

    static func playRolodexStep(using settings: KeyboardSettingsSnapshot) {
        previewPlayer.playRolodexStep(using: settings)
    }
}

/// Owns feedback for one presentation host; a keyboard must not reuse another host's generator.
final class KeyboardFeedbackPlayer {
    typealias GeneratorFactory = (UIImpactFeedbackGenerator.FeedbackStyle, UIView?) -> UIImpactFeedbackGenerator
    private let makeGenerator: GeneratorFactory
    private weak var boundView: UIView?
    private weak var boundWindow: UIWindow?
    private var generators = [Int: UIImpactFeedbackGenerator]()

    init(makeGenerator: @escaping GeneratorFactory = { style, view in
        if #available(iOS 17.5, *), let view {
            return UIImpactFeedbackGenerator(style: style, view: view)
        }
        return UIImpactFeedbackGenerator(style: style)
    }) {
        self.makeGenerator = makeGenerator
    }

    func reset() {
        if #available(iOS 17.5, *) {
            for generator in generators.values {
                generator.view?.removeInteraction(generator)
            }
        }
        generators.removeAll()
        boundView = nil
        boundWindow = nil
    }

    private func generator(for style: UIImpactFeedbackGenerator.FeedbackStyle, in view: UIView?) -> UIImpactFeedbackGenerator {
        if boundView !== view || boundWindow !== view?.window {
            reset()
            boundView = view
            boundWindow = view?.window
        }
        if let existing = generators[style.rawValue] { return existing }
        let generator = makeGenerator(style, view)
        generators[style.rawValue] = generator
        return generator
    }

    func prepare(using settings: KeyboardSettingsSnapshot, in view: UIView? = nil) {
        guard settings.vibrationEnabled else { return }
        generator(for: settings.feedbackLevel.feedbackStyle, in: view).prepare()
    }

    func play(using settings: KeyboardSettingsSnapshot, in view: UIView? = nil) {
        guard settings.vibrationEnabled else { return }
        let generator = generator(for: settings.feedbackLevel.feedbackStyle, in: view)
        generator.impactOccurred(intensity: settings.feedbackLevel.intensity)
        generator.prepare()
    }

    func playRolodexStep(using settings: KeyboardSettingsSnapshot, in view: UIView? = nil) {
        guard settings.vibrationEnabled else { return }
        let generator = generator(for: .heavy, in: view)
        generator.impactOccurred(intensity: 1.0)
        generator.prepare()
    }
}

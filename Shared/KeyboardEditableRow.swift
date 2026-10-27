import CoreGraphics
import Foundation

// New dynamic row model.
enum KeyboardRowKind: String, Codable, CaseIterable, Identifiable {
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
    case symbolMain
    case symbolHold
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
    case letterMain
    case letterHold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quickInsert:
            return "Top Row"
        case .holdQuickInsert:
            return "Top Row Hold"
        case .toolbar:
            return "Top Row"
        case .holdToolbar:
            return "Top Row Hold"
        case .symbolUtility:
            return "Symbols Utility"
        case .symbolTop:
            return "Symbols Row 1"
        case .holdSymbolTop:
            return "Symbols Hold Row 1"
        case .symbolMiddle:
            return "Symbols Row 2"
        case .holdSymbolMiddle:
            return "Symbols Hold Row 2"
        case .symbolBottom:
            return "Symbols Row 3"
        case .holdSymbolBottom:
            return "Symbols Hold Row 3"
        case .symbolMain:
            return "Symbols Row"
        case .symbolHold:
            return "Symbols Hold"
        case .trailingUtility:
            return "Main Row Key 1"
        case .expandedTrailingUtility:
            return "Expanded Symbols Key 1"
        case .expandedLetterTrailingUtility:
            return "Expanded ABC Key 1"
        case .letterUtility:
            return "ABC Utility"
        case .letterBottomLeading:
            return "ABC Lead Key"
        case .letterTop:
            return "ABC Row 1"
        case .holdLetterTop:
            return "ABC Hold Row 1"
        case .letterMiddle:
            return "ABC Row 2"
        case .holdLetterMiddle:
            return "ABC Hold Row 2"
        case .letterBottom:
            return "ABC Row 3"
        case .holdLetterBottom:
            return "ABC Hold Row 3"
        case .letterMain:
            return "ABC Row"
        case .letterHold:
            return "ABC Hold"
        }
    }

    var isABCLetterRow: Bool {
        switch self {
        case .letterTop, .holdLetterTop, .letterMiddle, .holdLetterMiddle, .letterBottom, .holdLetterBottom,
            .letterMain, .letterHold:
            return true
        default:
            return false
        }
    }

    var isHoldRow: Bool {
        switch self {
        case .holdQuickInsert, .holdToolbar, .holdSymbolTop, .holdSymbolMiddle, .holdSymbolBottom,
             .holdLetterTop, .holdLetterMiddle, .holdLetterBottom,
             .symbolHold, .letterHold:
            return true
        default:
            return false
        }
    }

    var supportsHoldCustomization: Bool {
        switch self.tapVariant {
        case .quickInsert, .toolbar, .symbolTop, .symbolMiddle, .symbolBottom, .letterTop, .letterMiddle, .letterBottom:
            return true
        case .symbolUtility, .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility,
             .letterUtility, .letterBottomLeading, .symbolMain, .letterMain, .symbolHold, .letterHold,
             .holdQuickInsert, .holdToolbar, .holdSymbolTop, .holdSymbolMiddle, .holdSymbolBottom,
             .holdLetterTop, .holdLetterMiddle, .holdLetterBottom:
            return false
        }
    }

    var tapVariant: KeyboardRowKind {
        switch self {
        case .quickInsert, .holdQuickInsert:
            return .quickInsert
        case .toolbar, .holdToolbar:
            return .toolbar
        case .symbolUtility:
            return .symbolUtility
        case .symbolTop, .holdSymbolTop:
            return .symbolTop
        case .symbolMiddle, .holdSymbolMiddle:
            return .symbolMiddle
        case .symbolBottom, .holdSymbolBottom:
            return .symbolBottom
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return .trailingUtility
        case .letterUtility:
            return .letterUtility
        case .letterBottomLeading:
            return .letterBottomLeading
        case .letterTop, .holdLetterTop:
            return .letterTop
        case .letterMiddle, .holdLetterMiddle:
            return .letterMiddle
        case .letterBottom, .holdLetterBottom:
            return .letterBottom
        case .symbolMain, .symbolHold:
            return .symbolMain
        case .letterMain, .letterHold:
            return .letterMain
        }
    }

    var holdVariant: KeyboardRowKind {
        switch self {
        case .quickInsert, .holdQuickInsert:
            return .holdQuickInsert
        case .toolbar, .holdToolbar:
            return .holdToolbar
        case .symbolUtility:
            return .symbolUtility
        case .symbolTop, .holdSymbolTop:
            return .holdSymbolTop
        case .symbolMiddle, .holdSymbolMiddle:
            return .holdSymbolMiddle
        case .symbolBottom, .holdSymbolBottom:
            return .holdSymbolBottom
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return .trailingUtility
        case .letterUtility:
            return .letterUtility
        case .letterBottomLeading:
            return .letterBottomLeading
        case .letterTop, .holdLetterTop:
            return .holdLetterTop
        case .letterMiddle, .holdLetterMiddle:
            return .holdLetterMiddle
        case .letterBottom, .holdLetterBottom:
            return .holdLetterBottom
        case .symbolMain, .symbolHold:
            return .symbolHold
        case .letterMain, .letterHold:
            return .letterHold
        }
    }

    var surface: KeyboardRowSurface {
        switch self {
        case .quickInsert, .holdQuickInsert, .toolbar, .holdToolbar, .trailingUtility,
             .expandedTrailingUtility, .expandedLetterTrailingUtility, .letterUtility, .letterBottomLeading,
             .symbolUtility, .symbolMain, .symbolHold:
            return .mainRow
        case .symbolTop, .holdSymbolTop, .symbolMiddle, .holdSymbolMiddle, .symbolBottom, .holdSymbolBottom:
            return .symbols1
        case .letterTop, .holdLetterTop, .letterMiddle, .holdLetterMiddle, .letterBottom, .holdLetterBottom,
             .letterMain, .letterHold:
            return .letters
        }
    }
}

@available(*, deprecated, message: "Use KeyboardLayoutRow.id")
typealias KeyboardEditableRow = KeyboardRowKind

enum KeyboardRowSurface: String, Codable, CaseIterable, Equatable, Identifiable {
    case mainRow
    case symbols1
    case symbols2
    case letters

    var id: String { rawValue }

    @available(*, deprecated, renamed: "symbols1")
    static var symbols: Self { .symbols1 }

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "symbols":
            self = .symbols1
        default:
            guard let surface = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown keyboard row surface: \(value)"
                )
            }
            self = surface
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct KeyboardLayoutKey: Codable, Equatable, Identifiable {
    var id: UUID
    var tap: String
    var hold: String?
    var holdChoices: [String]
    var widthWeight: CGFloat
    var heightOverride: CGFloat?

    init(
        id: UUID = UUID(),
        tap: String,
        hold: String? = nil,
        holdChoices: [String] = [],
        widthWeight: CGFloat = 1.0,
        heightOverride: CGFloat? = nil
    ) {
        self.id = id
        self.tap = tap
        let normalizedChoices = Self.normalizedHoldChoices(
            holdChoices.isEmpty ? Self.choices(from: hold) : holdChoices
        )
        self.holdChoices = normalizedChoices
        self.hold = hold ?? normalizedChoices.first
        self.widthWeight = KeyboardLayoutBounds.clampedPerKeyWidthWeight(widthWeight)
        self.heightOverride = heightOverride.map(KeyboardLayoutBounds.clampedPerKeyHeight)
    }

    private enum CodingKeys: String, CodingKey {
        case id, tap, hold, holdChoices, widthWeight, heightOverride
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedHold = try container.decodeIfPresent(String.self, forKey: .hold)
        let decodedChoices = try container.decodeIfPresent([String].self, forKey: .holdChoices) ?? []
        self.init(
            id: try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            tap: try container.decodeIfPresent(String.self, forKey: .tap) ?? "",
            hold: decodedHold,
            holdChoices: decodedChoices,
            widthWeight: try container.decodeIfPresent(CGFloat.self, forKey: .widthWeight) ?? 1,
            heightOverride: try container.decodeIfPresent(CGFloat.self, forKey: .heightOverride)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(tap, forKey: .tap)
        try container.encodeIfPresent(hold, forKey: .hold)
        try container.encode(holdChoices, forKey: .holdChoices)
        try container.encode(widthWeight, forKey: .widthWeight)
        try container.encodeIfPresent(heightOverride, forKey: .heightOverride)
    }

    private static func normalizedHoldChoices(_ choices: [String]) -> [String] {
        var seen = Set<String>()
        return choices.compactMap { choice in
            let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private static func choices(from hold: String?) -> [String] {
        guard let hold, hold.contains("|") else { return hold.map { [$0] } ?? [] }
        return hold.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
    }

    mutating func setHoldInput(_ input: String?) {
        let trimmed = input?.trimmingCharacters(in: .whitespacesAndNewlines)
        hold = trimmed?.isEmpty == false ? trimmed : nil
        holdChoices = Self.normalizedHoldChoices(Self.choices(from: hold))
    }
}

struct KeyboardLayoutRow: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: KeyboardRowKind
    var surface: KeyboardRowSurface
    var holdLayer: Bool
    var customLayerID: UUID?
    var keys: [KeyboardLayoutKey]
    var height: CGFloat?

    init(
        id: UUID = UUID(),
        kind: KeyboardRowKind,
        surface: KeyboardRowSurface,
        holdLayer: Bool,
        customLayerID: UUID? = nil,
        keys: [KeyboardLayoutKey],
        height: CGFloat? = nil
    ) {
        self.id = id
        self.kind = kind
        self.surface = surface
        self.holdLayer = holdLayer
        self.customLayerID = customLayerID
        self.keys = keys
        self.height = height
    }
}

enum KeyboardCustomLayerStyle: String, Codable, CaseIterable, Identifiable {
    case row
    case expanded

    var id: String { rawValue }
    var title: String { self == .row ? "ROW" : "Expanded" }
}

struct KeyboardCustomLayer: Codable, Equatable, Identifiable {
    static let storageTokenPrefix = "@layer:"
    static let defaultIconSystemName = "square.stack.3d.up"
    static let iconSystemNames = [
        "square.stack.3d.up",
        "curlybraces",
        "command",
        "number",
        "textformat",
        "keyboard",
        "sparkles",
        "bolt",
    ]

    var id: UUID
    var title: String
    var iconSystemName: String
    var surface: KeyboardRowSurface
    var rowIDs: [UUID]
    var style: KeyboardCustomLayerStyle {
        surface == .mainRow ? .row : .expanded
    }
    var storageToken: String {
        Self.storageToken(for: id)
    }

    static func storageToken(for id: UUID) -> String {
        storageTokenPrefix + id.uuidString
    }

    static func id(fromStorageToken token: String) -> UUID? {
        guard token.hasPrefix(storageTokenPrefix) else { return nil }
        return UUID(uuidString: String(token.dropFirst(storageTokenPrefix.count)))
    }

    init(
        id: UUID = UUID(),
        title: String,
        iconSystemName: String = KeyboardCustomLayer.defaultIconSystemName,
        surface: KeyboardRowSurface,
        rowIDs: [UUID]
    ) {
        self.id = id
        self.title = Self.normalizedTitle(title)
        self.iconSystemName = Self.normalizedIconName(iconSystemName)
        self.surface = surface
        self.rowIDs = Self.normalizedRowIDs(rowIDs)
    }

    var normalized: KeyboardCustomLayer {
        KeyboardCustomLayer(
            id: id,
            title: title,
            iconSystemName: iconSystemName,
            surface: surface,
            rowIDs: rowIDs
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case iconSystemName
        case surface
        case rowIDs
        case rowID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        let decodedTitle = try container.decodeIfPresent(String.self, forKey: .title) ?? "Layer"
        let decodedIcon = try container.decodeIfPresent(String.self, forKey: .iconSystemName)
            ?? KeyboardCustomLayer.defaultIconSystemName
        let decodedSurface = try container.decodeIfPresent(KeyboardRowSurface.self, forKey: .surface) ?? .symbols1
        let decodedRowIDs = try container.decodeIfPresent([UUID].self, forKey: .rowIDs)
            ?? container.decodeIfPresent(UUID.self, forKey: .rowID).map { [$0] }
            ?? []

        self.init(
            id: decodedID,
            title: decodedTitle,
            iconSystemName: decodedIcon,
            surface: decodedSurface,
            rowIDs: decodedRowIDs
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(iconSystemName, forKey: .iconSystemName)
        try container.encode(surface, forKey: .surface)
        try container.encode(rowIDs, forKey: .rowIDs)
    }

    static func normalizedTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Layer" }
        return String(trimmed.prefix(24))
    }

    static func normalizedIconName(_ iconSystemName: String) -> String {
        iconSystemNames.contains(iconSystemName) ? iconSystemName : defaultIconSystemName
    }

    static func normalizedRowIDs(_ rowIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return rowIDs.filter { seen.insert($0).inserted }
    }
}

struct KeyboardLayoutKeyDimensions: Codable, Equatable {
    var widthWeight: CGFloat
    var heightOverride: CGFloat?

    init(widthWeight: CGFloat = 1.0, heightOverride: CGFloat? = nil) {
        self.widthWeight = KeyboardLayoutBounds.clampedPerKeyWidthWeight(widthWeight)
        self.heightOverride = heightOverride.map(KeyboardLayoutBounds.clampedPerKeyHeight)
    }

    static let identity = KeyboardLayoutKeyDimensions()
}

enum KeyboardLayoutDimensionKey {
    static func legacyKey(
        surface: KeyboardRowSurface,
        kind: KeyboardRowKind,
        holdLayer: Bool,
        slotIndex: Int
    ) -> String {
        let layer = holdLayer ? "hold" : "tap"
        return "legacy:\(surface.rawValue):\(kind.rawValue):\(layer):\(slotIndex)"
    }

    static func customKey(rowID: UUID, keyID: UUID) -> String {
        "custom:\(rowID.uuidString):\(keyID.uuidString)"
    }
}

extension KeyboardKeymap {
    static func makeDefaultDynamic() -> [KeyboardLayoutRow] {
        let compact = KeyboardKeymap.preset(.compact)
        return [
            KeyboardLayoutRow(
                kind: .quickInsert,
                surface: .mainRow,
                holdLayer: false,
                keys: compact.quickInsertRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .toolbar,
                surface: .mainRow,
                holdLayer: false,
                keys: compact.toolbarRow.map { KeyboardLayoutKey(tap: $0) },
                height: 52
            ),
            KeyboardLayoutRow(
                kind: .symbolTop,
                surface: .symbols1,
                holdLayer: false,
                keys: compact.symbolTopRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .symbolMiddle,
                surface: .symbols1,
                holdLayer: false,
                keys: compact.symbolMiddleRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .symbolBottom,
                surface: .symbols1,
                holdLayer: false,
                keys: compact.symbolBottomRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .letterTop,
                surface: .letters,
                holdLayer: false,
                keys: compact.letterTopRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .letterMiddle,
                surface: .letters,
                holdLayer: false,
                keys: compact.letterMiddleRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .letterBottom,
                surface: .letters,
                holdLayer: false,
                keys: compact.letterBottomRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .symbolUtility,
                surface: .mainRow,
                holdLayer: false,
                keys: compact.symbolUtilityRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .letterUtility,
                surface: .letters,
                holdLayer: false,
                keys: compact.letterUtilityRow.map { KeyboardLayoutKey(tap: $0) }
            ),
            KeyboardLayoutRow(
                kind: .trailingUtility,
                surface: .mainRow,
                holdLayer: false,
                keys: compact.trailingUtilityRow.map { KeyboardLayoutKey(tap: $0) }
            )
        ]
    }
}

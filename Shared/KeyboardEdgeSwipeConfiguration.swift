import Foundation

/// Stable identities survive layer renames and never depend on display titles.
struct KeyboardEdgeSwipeDestination: RawRepresentable, Codable, Hashable, Identifiable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    var id: String { rawValue }
    static let off = Self(rawValue: "off")
    static let clipboard = Self(rawValue: "clipboard")
    static let mainRow = Self(rawValue: "mainRow")
    static let letters = Self(rawValue: "letters")
    static let symbols1 = Self(rawValue: "symbols1")
    static let symbols2 = Self(rawValue: "symbols2")
    static let builtInLayers: [Self] = [.mainRow, .letters, .symbols1, .symbols2]

    static func custom(_ id: UUID) -> Self {
        Self(rawValue: KeyboardCustomLayer.storageToken(for: id))
    }
    var customLayerID: UUID? { KeyboardCustomLayer.id(fromStorageToken: rawValue) }
    var isLayer: Bool { Self.builtInLayers.contains(self) || customLayerID != nil }

    func isAvailable(in keymap: KeyboardKeymap, rowMode: Bool) -> Bool {
        if self == .off || self == .clipboard { return true }
        if let id = customLayerID, let layer = keymap.customLayer(for: id) {
            return !rowMode || layer.style == .row
        }
        return !rowMode && Self.builtInLayers.contains(self)
    }

    func title(in keymap: KeyboardKeymap) -> String {
        switch self {
        case .off: return "Off"
        case .clipboard: return "Clipboard"
        case .mainRow: return "Main"
        case .letters: return "ABC"
        case .symbols1: return "SYM 1"
        case .symbols2: return "SYM 2"
        default: return keymap.customLayer(for: customLayerID)?.title ?? "Unavailable layer"
        }
    }
}

enum KeyboardSwipeEdge: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var sign: CGFloat { self == .left ? 1 : -1 }
    var title: String { self == .left ? "Left edge" : "Right edge" }
}

struct KeyboardEdgeSwipeConfiguration: Codable, Equatable {
    var expandedLeft: KeyboardEdgeSwipeDestination = .off
    var expandedRight: KeyboardEdgeSwipeDestination = .clipboard
    var rowLeft: KeyboardEdgeSwipeDestination = .off
    var rowRight: KeyboardEdgeSwipeDestination = .clipboard

    subscript(edge: KeyboardSwipeEdge, rowMode: Bool) -> KeyboardEdgeSwipeDestination {
        get { rowMode ? (edge == .left ? rowLeft : rowRight) : (edge == .left ? expandedLeft : expandedRight) }
        set {
            if rowMode {
                if edge == .left { rowLeft = newValue } else { rowRight = newValue }
            } else {
                if edge == .left { expandedLeft = newValue } else { expandedRight = newValue }
            }
        }
    }

    func normalized(for keymap: KeyboardKeymap) -> Self {
        var result = self
        for rowMode in [false, true] {
            var layers = Set<KeyboardEdgeSwipeDestination>()
            for edge in KeyboardSwipeEdge.allCases {
                var target = result[edge, rowMode]
                if let id = target.customLayerID { target = .custom(id) }
                if !target.isAvailable(in: keymap, rowMode: rowMode)
                    || (target != .off && !layers.insert(target).inserted) {
                    target = .off
                }
                result[edge, rowMode] = target
            }
        }
        return result
    }
}

/// Shared by runtime recognition and regression tests. Only inward horizontal
/// intent claims a session; the final displacement decides whether it commits.
struct KeyboardEdgeSwipeSession: Equatable {
    let edge: KeyboardSwipeEdge
    let destination: KeyboardEdgeSwipeDestination
    let rowMode: Bool
    private(set) var claimed = false
    private(set) var translation: CGSize = .zero

    static func edge(at start: CGPoint, size: CGSize, railHeight: CGFloat) -> KeyboardSwipeEdge? {
        guard size.width >= 68, size.height > 0,
              start.y >= max(0, railHeight), start.y <= size.height,
              start.x >= 0, start.x <= size.width else { return nil }
        if start.x <= 34 { return .left }
        if start.x >= size.width - 34 { return .right }
        return nil
    }

    mutating func update(_ translation: CGSize) {
        self.translation = translation
        if translation.width * edge.sign >= 18,
           abs(translation.width) >= abs(translation.height) * 1.35 {
            claimed = true
        }
    }

    var shouldCommit: Bool {
        claimed && translation.width * edge.sign >= 48
            && abs(translation.width) >= abs(translation.height) * 1.35
    }
}

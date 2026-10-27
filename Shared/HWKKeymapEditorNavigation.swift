import Foundation

enum HWKKeymapEditorActionMode: Equatable {
    case tap
    case hold
}

enum HWKKeymapEditorExpandedLayer: Equatable {
    case symbols
    case letters
}

enum HWKKeymapEditorSurface: Equatable {
    case mainRow
    case symbols
    case letters
}

struct HWKKeymapEditorNavigation {
    struct Selection: Equatable {
        var mode: HWKKeymapEditorActionMode
        var row: KeyboardRowKind
    }

    static func rowAfterChangingActionMode(
        to mode: HWKKeymapEditorActionMode,
        currentRow: KeyboardRowKind,
        expandedLayer: HWKKeymapEditorExpandedLayer?
    ) -> Selection {
        let baseRow = tapRowPreservingLayerKeyOne(currentRow)

        switch mode {
        case .tap:
            return Selection(mode: .tap, row: baseRow)
        case .hold:
            if baseRow.supportsHoldCustomization {
                return Selection(mode: .hold, row: baseRow.holdVariant)
            }

            guard let expandedLayer else {
                return Selection(mode: .tap, row: baseRow)
            }

            let fallbackBaseRow: KeyboardRowKind = expandedLayer == .symbols ? .symbolTop : .letterTop
            return Selection(mode: .hold, row: fallbackBaseRow.holdVariant)
        }
    }

    static func rowAfterSelectingRenderedKey(
        _ row: KeyboardRowKind,
        currentMode: HWKKeymapEditorActionMode
    ) -> Selection {
        selection(forTapRow: tapRowPreservingLayerKeyOne(row), requestedMode: currentMode)
    }

    static func rowAfterChangingSurface(
        to surface: HWKKeymapEditorSurface,
        currentRow: KeyboardRowKind,
        currentMode: HWKKeymapEditorActionMode
    ) -> Selection {
        let currentTapRow = tapRowPreservingLayerKeyOne(currentRow)
        let targetTapRow: KeyboardRowKind

        switch surface {
        case .mainRow:
            targetTapRow = isLayerKeyOne(currentTapRow) ? .trailingUtility : .toolbar
        case .symbols:
            targetTapRow = expandedRow(for: .symbols, currentTapRow: currentTapRow)
        case .letters:
            targetTapRow = expandedRow(for: .letters, currentTapRow: currentTapRow)
        }

        return selection(forTapRow: targetTapRow, requestedMode: currentMode)
    }

    private static func selection(
        forTapRow row: KeyboardRowKind,
        requestedMode: HWKKeymapEditorActionMode
    ) -> Selection {
        if requestedMode == .hold, row.supportsHoldCustomization {
            return Selection(mode: .hold, row: row.holdVariant)
        }
        return Selection(mode: .tap, row: row)
    }

    private static func expandedRow(
        for layer: HWKKeymapEditorExpandedLayer,
        currentTapRow: KeyboardRowKind
    ) -> KeyboardRowKind {
        switch currentTapRow {
        case .quickInsert:
            return .quickInsert
        case .toolbar, .symbolUtility, .letterUtility:
            return layer == .symbols ? .symbolUtility : .letterUtility
        case .symbolTop, .letterTop:
            return layer == .symbols ? .symbolTop : .letterTop
        case .symbolMiddle, .letterMiddle:
            return layer == .symbols ? .symbolMiddle : .letterMiddle
        case .symbolBottom, .letterBottom:
            return layer == .symbols ? .symbolBottom : .letterBottom
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return layer == .symbols ? .expandedTrailingUtility : .expandedLetterTrailingUtility
        case .letterBottomLeading:
            return layer == .symbols ? .symbolBottom : .letterBottomLeading
        default:
            return layer == .symbols ? .symbolTop : .letterTop
        }
    }

    private static func tapRowPreservingLayerKeyOne(_ row: KeyboardRowKind) -> KeyboardRowKind {
        switch row {
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return row
        default:
            return row.tapVariant
        }
    }

    private static func isLayerKeyOne(_ row: KeyboardRowKind) -> Bool {
        switch row {
        case .trailingUtility, .expandedTrailingUtility, .expandedLetterTrailingUtility:
            return true
        default:
            return false
        }
    }
}

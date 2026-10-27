import CoreGraphics
import Foundation

struct HWKRuntimeLayoutAdapter {
    func keymap(
        for settings: KeyboardSettingsSnapshot,
        isRuntimeLayoutEnabled: Bool = true
    ) -> KeyboardKeymap {
        guard isRuntimeLayoutEnabled,
              settings.layoutPreset == .compact,
              settings.runtimeLayoutRoute == .runtimeLocale else {
            return settings.keymap
        }

        let engine = HWKLayoutEngine()
        let resolvedLayout: HWKResolvedLayout
        if settings.layoutLocale == .enUS {
            resolvedLayout = engine.fallback()
        } else {
            resolvedLayout = (try? engine.bundled(locale: settings.layoutLocale.rawValue)) ?? engine.fallback()
        }

        return keymap(from: resolvedLayout, fallback: settings.keymap)
    }

    func keymap(from resolvedLayout: HWKResolvedLayout, fallback: KeyboardKeymap) -> KeyboardKeymap {
        keymap(from: HWKLayoutCompositor().compose(resolvedLayout), fallback: fallback)
    }

    func keymap(from layers: [HWKRenderLayer], fallback: KeyboardKeymap) -> KeyboardKeymap {
        let fallbackCustomLayerRows = fallback.rows.filter { $0.customLayerID != nil }
        let rows = mergeDimensionOverrides(
            into: dynamicRows(from: layers, fallback: fallback) + fallbackCustomLayerRows,
            from: fallback.rows
        )
        let customRows = rows.filter { $0.kind == .symbolMain || $0.kind == .letterMain }

        return KeyboardKeymap(
            quickInsertRow: values(in: layers, layerID: .quickInsert, rowID: "quickInsert", fallback: fallback.quickInsertRow),
            holdQuickInsertRow: holds(in: layers, layerID: .quickInsert, rowID: "quickInsert", fallback: fallback.holdQuickInsertRow),
            toolbarRow: values(in: layers, layerID: .toolbar, rowID: "toolbar", fallback: fallback.toolbarRow),
            holdToolbarRow: holds(in: layers, layerID: .toolbar, rowID: "toolbar", fallback: fallback.holdToolbarRow),
            symbolTopRow: values(in: layers, layerID: .symbols, rowID: "symbolTop", fallback: fallback.symbolTopRow),
            holdSymbolTopRow: holds(in: layers, layerID: .symbols, rowID: "symbolTop", fallback: fallback.holdSymbolTopRow),
            symbolMiddleRow: values(in: layers, layerID: .symbols, rowID: "symbolMiddle", fallback: fallback.symbolMiddleRow),
            holdSymbolMiddleRow: holds(in: layers, layerID: .symbols, rowID: "symbolMiddle", fallback: fallback.holdSymbolMiddleRow),
            symbolBottomRow: values(in: layers, layerID: .symbols, rowID: "symbolBottom", fallback: fallback.symbolBottomRow),
            holdSymbolBottomRow: holds(in: layers, layerID: .symbols, rowID: "symbolBottom", fallback: fallback.holdSymbolBottomRow),
            letterTopRow: values(in: layers, layerID: .letters, rowID: "letterTop", fallback: fallback.letterTopRow),
            holdLetterTopRow: holds(in: layers, layerID: .letters, rowID: "letterTop", fallback: fallback.holdLetterTopRow),
            letterMiddleRow: values(in: layers, layerID: .letters, rowID: "letterMiddle", fallback: fallback.letterMiddleRow),
            holdLetterMiddleRow: holds(in: layers, layerID: .letters, rowID: "letterMiddle", fallback: fallback.holdLetterMiddleRow),
            letterBottomRow: values(in: layers, layerID: .letters, rowID: "letterBottom", fallback: fallback.letterBottomRow),
            holdLetterBottomRow: holds(in: layers, layerID: .letters, rowID: "letterBottom", fallback: fallback.holdLetterBottomRow),
            symbolUtilityRow: fallback.symbolUtilityRow,
            letterUtilityRow: fallback.letterUtilityRow,
            trailingUtilityRow: fallback.trailingUtilityRow,
            expandedTrailingUtilityRow: fallback.expandedTrailingUtilityRow,
            expandedLetterTrailingUtilityRow: fallback.expandedLetterTrailingUtilityRow,
            letterBottomLeadingRow: fallback.letterBottomLeadingRow,
            customAddedRows: customRows,
            customLayers: fallback.customLayers,
            keyDimensionOverrides: fallback.keyDimensionOverrides,
            rows: rows
        )
    }

    private func dynamicRows(from layers: [HWKRenderLayer], fallback: KeyboardKeymap) -> [KeyboardLayoutRow] {
        let mainRows = [
            dynamicRow(
                in: layers,
                layerID: .quickInsert,
                surface: .mainRow,
                rowID: "quickInsert",
                kind: .quickInsert,
                fallbackRow: fallbackRow(in: fallback, surface: .mainRow, kind: .quickInsert),
                fallbackKeymap: fallback
            ),
            dynamicRow(
                in: layers,
                layerID: .toolbar,
                surface: .mainRow,
                rowID: "toolbar",
                kind: .toolbar,
                fallbackRow: fallbackRow(in: fallback, surface: .mainRow, kind: .toolbar),
                fallbackKeymap: fallback
            ),
            fallbackRow(in: fallback, surface: .mainRow, kind: .trailingUtility)
        ].compactMap { $0 }

        let symbolRows = dynamicRows(
            in: layers,
            layerID: .symbols,
            surface: .symbols1,
            knownKinds: [
                "symbolTop": .symbolTop,
                "symbolMiddle": .symbolMiddle,
                "symbolBottom": .symbolBottom
            ],
            genericKind: .symbolMain,
            fallbackKeymap: fallback
        ) + [
            fallbackRow(in: fallback, surface: .symbols1, kind: .symbolUtility),
            fallbackRow(in: fallback, surface: .symbols1, kind: .expandedTrailingUtility)
        ].compactMap { $0 }

        let letterRows = dynamicRows(
            in: layers,
            layerID: .letters,
            surface: .letters,
            knownKinds: [
                "letterTop": .letterTop,
                "letterMiddle": .letterMiddle,
                "letterBottom": .letterBottom
            ],
            genericKind: .letterMain,
            fallbackKeymap: fallback
        ) + [
            fallbackRow(in: fallback, surface: .letters, kind: .letterUtility),
            fallbackRow(in: fallback, surface: .letters, kind: .letterBottomLeading),
            fallbackRow(in: fallback, surface: .letters, kind: .expandedLetterTrailingUtility)
        ].compactMap { $0 }

        return mainRows + symbolRows + letterRows
    }

    private func dynamicRows(
        in layers: [HWKRenderLayer],
        layerID: HWKLayoutLayerID,
        surface: KeyboardRowSurface,
        knownKinds: [String: KeyboardRowKind],
        genericKind: KeyboardRowKind,
        fallbackKeymap: KeyboardKeymap
    ) -> [KeyboardLayoutRow] {
        layers.first { $0.id == layerID }?.rows.map { renderRow in
            dynamicRow(
                renderRow,
                layerID: layerID,
                surface: surface,
                kind: knownKinds[renderRow.id] ?? genericKind,
                fallbackKeymap: fallbackKeymap
            )
        } ?? []
    }

    private func dynamicRow(
        in layers: [HWKRenderLayer],
        layerID: HWKLayoutLayerID,
        surface: KeyboardRowSurface,
        rowID: String,
        kind: KeyboardRowKind,
        fallbackRow: KeyboardLayoutRow?,
        fallbackKeymap: KeyboardKeymap
    ) -> KeyboardLayoutRow? {
        guard let renderRow = row(in: layers, layerID: layerID, rowID: rowID) else {
            return fallbackRow
        }

        return dynamicRow(renderRow, layerID: layerID, surface: surface, kind: kind, fallbackKeymap: fallbackKeymap)
    }

    private func dynamicRow(
        _ renderRow: HWKRenderRow,
        layerID: HWKLayoutLayerID,
        surface: KeyboardRowSurface,
        kind: KeyboardRowKind,
        fallbackKeymap: KeyboardKeymap
    ) -> KeyboardLayoutRow {
        KeyboardLayoutRow(
            id: stableID("runtime:\(layerID.rawValue):\(renderRow.id):row"),
            kind: kind,
            surface: surface,
            holdLayer: false,
            keys: renderRow.keys.enumerated().map { index, renderKey in
                let legacyDimensions = fallbackKeymap.keyDimensions(
                    surface: surface,
                    kind: kind,
                    holdLayer: false,
                    slotIndex: index
                )
                return KeyboardLayoutKey(
                    id: stableID("runtime:\(layerID.rawValue):\(renderRow.id):key:\(renderKey.id)"),
                    tap: renderKey.output ?? renderKey.label,
                    hold: renderKey.hold?.isEmpty == false ? renderKey.hold : nil,
                    widthWeight: legacyDimensions.widthWeight == KeyboardLayoutKeyDimensions.identity.widthWeight
                        ? CGFloat(renderKey.width)
                        : legacyDimensions.widthWeight,
                    heightOverride: legacyDimensions.heightOverride
                )
            }
        )
    }

    private func fallbackRow(
        in keymap: KeyboardKeymap,
        surface: KeyboardRowSurface,
        kind: KeyboardRowKind
    ) -> KeyboardLayoutRow? {
        keymap.rows.first { $0.surface == surface && $0.kind == kind && !$0.holdLayer }
    }

    private func mergeDimensionOverrides(
        into rows: [KeyboardLayoutRow],
        from sourceRows: [KeyboardLayoutRow]
    ) -> [KeyboardLayoutRow] {
        let sourceRowsByID = firstWinsDictionary(sourceRows.map { ($0.id, $0) })
        let sourceRowsByKind: [RuntimeMergeRowKey: KeyboardLayoutRow] = firstWinsDictionary(
            sourceRows.compactMap { row in
                guard row.kind != .symbolMain && row.kind != .letterMain else { return nil }
                return (RuntimeMergeRowKey(row), row)
            }
        )

        return rows.map { row in
            guard let source = sourceRowsByID[row.id] ?? sourceRowsByKind[RuntimeMergeRowKey(row)] else {
                return row
            }
            var nextRow = row
            nextRow.height = source.height ?? nextRow.height

            let sourceKeysByID = firstWinsDictionary(source.keys.map { ($0.id, $0) })
            nextRow.keys = row.keys.enumerated().map { index, key in
                guard let sourceKey = sourceKeysByID[key.id] else { return key }
                var nextKey = key
                nextKey.widthWeight = sourceKey.widthWeight
                nextKey.heightOverride = sourceKey.heightOverride
                return nextKey
            }

            if source.id != row.id {
                nextRow.keys = zip(row.keys.indices, row.keys).map { index, key in
                    guard index < source.keys.count else { return key }
                    let sourceKey = source.keys[index]
                    guard hasDimensionOverride(sourceKey) else { return key }
                    var nextKey = key
                    nextKey.widthWeight = sourceKey.widthWeight
                    nextKey.heightOverride = sourceKey.heightOverride
                    return nextKey
                }
            }

            return nextRow
        }
    }

    private func hasDimensionOverride(_ key: KeyboardLayoutKey) -> Bool {
        key.widthWeight != KeyboardLayoutKeyDimensions.identity.widthWeight || key.heightOverride != nil
    }

    private func firstWinsDictionary<Key: Hashable, Value>(_ pairs: [(Key, Value)]) -> [Key: Value] {
        var result: [Key: Value] = [:]
        for (key, value) in pairs where result[key] == nil {
            result[key] = value
        }
        return result
    }

    private func isCompactRuntimeBase(_ keymap: KeyboardKeymap) -> Bool {
        let compact = KeyboardKeymap.preset(.compact)
        return keymap.customAddedRows.isEmpty &&
            keymap.quickInsertRow == compact.quickInsertRow &&
            keymap.holdQuickInsertRow == compact.holdQuickInsertRow &&
            keymap.toolbarRow == compact.toolbarRow &&
            keymap.holdToolbarRow == compact.holdToolbarRow &&
            keymap.symbolTopRow == compact.symbolTopRow &&
            keymap.holdSymbolTopRow == compact.holdSymbolTopRow &&
            keymap.symbolMiddleRow == compact.symbolMiddleRow &&
            keymap.holdSymbolMiddleRow == compact.holdSymbolMiddleRow &&
            keymap.symbolBottomRow == compact.symbolBottomRow &&
            keymap.holdSymbolBottomRow == compact.holdSymbolBottomRow &&
            keymap.letterTopRow == compact.letterTopRow &&
            keymap.holdLetterTopRow == compact.holdLetterTopRow &&
            keymap.letterMiddleRow == compact.letterMiddleRow &&
            keymap.holdLetterMiddleRow == compact.holdLetterMiddleRow &&
            keymap.letterBottomRow == compact.letterBottomRow &&
            keymap.holdLetterBottomRow == compact.holdLetterBottomRow &&
            keymap.symbolUtilityRow == compact.symbolUtilityRow &&
            keymap.letterUtilityRow == compact.letterUtilityRow &&
            keymap.trailingUtilityRow == compact.trailingUtilityRow &&
            keymap.expandedTrailingUtilityRow == compact.expandedTrailingUtilityRow &&
            keymap.expandedLetterTrailingUtilityRow == compact.expandedLetterTrailingUtilityRow &&
            keymap.letterBottomLeadingRow == compact.letterBottomLeadingRow
    }

    private struct RuntimeMergeRowKey: Hashable {
        let surface: KeyboardRowSurface
        let kind: KeyboardRowKind
        let holdLayer: Bool

        init(_ row: KeyboardLayoutRow) {
            surface = row.surface
            kind = row.kind
            holdLayer = row.holdLayer
        }
    }

    private func values(
        in layers: [HWKRenderLayer],
        layerID: HWKLayoutLayerID,
        rowID: String,
        fallback: [String]
    ) -> [String] {
        guard let row = row(in: layers, layerID: layerID, rowID: rowID) else {
            return fallback
        }

        return row.keys.map { $0.output ?? $0.label }
    }

    private func holds(
        in layers: [HWKRenderLayer],
        layerID: HWKLayoutLayerID,
        rowID: String,
        fallback: [String]
    ) -> [String] {
        guard let row = row(in: layers, layerID: layerID, rowID: rowID) else {
            return fallback
        }

        let values = row.keys.map { $0.hold ?? "" }
        return values.contains { !$0.isEmpty } ? values : fallback
    }

    private func row(
        in layers: [HWKRenderLayer],
        layerID: HWKLayoutLayerID,
        rowID: String
    ) -> HWKRenderRow? {
        layers.first { $0.id == layerID }?.rows.first { $0.id == rowID }
    }

    private func stableID(_ seed: String) -> UUID {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", hash & 0x0000_FFFF_FFFF_FFFF))!
    }
}

import Foundation

struct HWKRenderKey: Equatable {
    var id: String
    var label: String
    var output: String?
    var role: HWKLayoutKeyRole
    var width: Double
    var hold: String?
    var accessibilityLabel: String
}

struct HWKRenderRow: Equatable {
    var id: String
    var keys: [HWKRenderKey]
}

struct HWKRenderLayer: Equatable {
    var id: HWKLayoutLayerID
    var rows: [HWKRenderRow]
}

struct HWKLayoutCompositor {
    func compose(_ resolvedLayout: HWKResolvedLayout) -> [HWKRenderLayer] {
        resolvedLayout.descriptor.layers.map { layer in
            HWKRenderLayer(
                id: layer.id,
                rows: layer.rows.map { row in
                    HWKRenderRow(
                        id: row.id,
                        keys: row.keys.map(renderKey)
                    )
                }
            )
        }
    }

    private func renderKey(_ key: HWKLayoutKeyDescriptor) -> HWKRenderKey {
        HWKRenderKey(
            id: key.id,
            label: key.label,
            output: key.output,
            role: key.role,
            width: key.width ?? 1,
            hold: key.hold,
            accessibilityLabel: key.accessibilityLabel ?? key.label
        )
    }
}


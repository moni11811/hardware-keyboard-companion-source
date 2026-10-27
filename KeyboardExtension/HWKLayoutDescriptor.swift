import Foundation

enum HWKLayoutDirection: String, Codable {
    case leftToRight
    case rightToLeft
}

enum HWKLayoutLayerID: String, Codable {
    case quickInsert
    case toolbar
    case letters
    case symbols
}

enum HWKLayoutKeyRole: String, Codable {
    case character
    case action
    case spacer
}

struct HWKLayoutDescriptor: Codable, Equatable {
    var schemaVersion: Int
    var locale: String
    var script: String
    var direction: HWKLayoutDirection
    var layers: [HWKLayoutLayerDescriptor]
    var geometry: HWKLayoutGeometry
}

struct HWKLayoutGeometry: Codable, Equatable {
    var keyHeight: Double?
    var rowSpacing: Double?
    var keySpacing: Double?
}

struct HWKLayoutLayerDescriptor: Codable, Equatable {
    var id: HWKLayoutLayerID
    var rows: [HWKLayoutRowDescriptor]
}

struct HWKLayoutRowDescriptor: Codable, Equatable {
    var id: String
    var keys: [HWKLayoutKeyDescriptor]
}

struct HWKLayoutKeyDescriptor: Codable, Equatable {
    var id: String
    var label: String
    var output: String?
    var role: HWKLayoutKeyRole
    var width: Double?
    var hold: String?
    var accessibilityLabel: String?
}

extension HWKLayoutDescriptor {
    static func compactEnglishUS() -> HWKLayoutDescriptor {
        let keymap = KeyboardKeymap.preset(.compact)
        return HWKLayoutDescriptor(
            schemaVersion: HWKLayoutSchemaVersion.current,
            locale: "en-US",
            script: "Latn",
            direction: .leftToRight,
            layers: [
                HWKLayoutLayerDescriptor(
                    id: .quickInsert,
                    rows: [
                        .row(id: "quickInsert", values: keymap.quickInsertRow, holds: keymap.holdQuickInsertRow),
                    ]
                ),
                HWKLayoutLayerDescriptor(
                    id: .toolbar,
                    rows: [
                        .row(id: "toolbar", values: keymap.toolbarRow, holds: keymap.holdToolbarRow),
                    ]
                ),
                HWKLayoutLayerDescriptor(
                    id: .letters,
                    rows: [
                        .row(id: "letterTop", values: keymap.letterTopRow, holds: keymap.holdLetterTopRow),
                        .row(id: "letterMiddle", values: keymap.letterMiddleRow, holds: keymap.holdLetterMiddleRow),
                        .row(
                            id: "letterBottom",
                            values: keymap.letterBottomRow,
                            holds: keymap.holdLetterBottomRow,
                            actionLabels: ["enter"]
                        ),
                    ]
                ),
                HWKLayoutLayerDescriptor(
                    id: .symbols,
                    rows: [
                        .row(id: "symbolTop", values: keymap.symbolTopRow, holds: keymap.holdSymbolTopRow),
                        .row(id: "symbolMiddle", values: keymap.symbolMiddleRow, holds: keymap.holdSymbolMiddleRow),
                        .row(id: "symbolBottom", values: keymap.symbolBottomRow, holds: keymap.holdSymbolBottomRow),
                    ]
                ),
            ],
            geometry: HWKLayoutGeometry(keyHeight: nil, rowSpacing: nil, keySpacing: nil)
        )
    }
}

extension HWKLayoutRowDescriptor {
    static func row(
        id: String,
        values: [String],
        holds: [String],
        actionLabels: Set<String> = []
    ) -> HWKLayoutRowDescriptor {
        HWKLayoutRowDescriptor(
            id: id,
            keys: values.enumerated().map { index, value in
                let isAction = value.hasPrefix("@") || actionLabels.contains(value)
                return HWKLayoutKeyDescriptor(
                    id: "\(id).\(index)",
                    label: value,
                    output: isAction ? nil : value,
                    role: isAction ? .action : .character,
                    width: nil,
                    hold: index < holds.count && !holds[index].isEmpty ? holds[index] : nil,
                    accessibilityLabel: nil
                )
            }
        )
    }
}

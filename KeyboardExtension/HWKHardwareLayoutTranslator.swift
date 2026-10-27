import Foundation
import UIKit

struct HWKHardwareLayoutTranslator {
    private let layoutEngine: HWKLayoutEngine

    init(layoutEngine: HWKLayoutEngine = HWKLayoutEngine()) {
        self.layoutEngine = layoutEngine
    }

    func translatedText(
        for keyCode: UIKeyboardHIDUsage,
        layoutLocale: KeyboardLayoutLocale,
        autodetectedLayoutLocale: String? = nil
    ) -> String? {
        guard let slot = Self.physicalUSLetterSlot[keyCode] else {
            return nil
        }

        return translatedText(
            for: slot,
            layoutLocale: layoutLocale,
            autodetectedLayoutLocale: autodetectedLayoutLocale
        )
    }

    func preferredText(
        for keyCode: UIKeyboardHIDUsage,
        characters: String?,
        layoutLocale: KeyboardLayoutLocale,
        autodetectedLayoutLocale: String? = nil
    ) -> String? {
        let translated = translatedText(
            for: keyCode,
            layoutLocale: layoutLocale,
            autodetectedLayoutLocale: autodetectedLayoutLocale
        )
        if layoutLocale == .enUS {
            return characters ?? translated
        }
        return translated ?? characters
    }

    private func translatedText(
        for slot: PhysicalLetterSlot,
        layoutLocale: KeyboardLayoutLocale,
        autodetectedLayoutLocale: String?
    ) -> String? {
        let resolvedLayout: HWKResolvedLayout
        if let descriptor = resolvedDescriptor(
            for: layoutLocale,
            autodetectedLayoutLocale: autodetectedLayoutLocale
        ) {
            resolvedLayout = (try? layoutEngine.resolve(descriptor)) ?? layoutEngine.fallback()
        } else {
            resolvedLayout = layoutEngine.fallback()
        }
        return letterText(from: resolvedLayout, at: slot)
    }

    private func resolvedDescriptor(
        for layoutLocale: KeyboardLayoutLocale,
        autodetectedLayoutLocale: String?
    ) -> HWKLayoutDescriptor? {
        if layoutLocale == .enUS,
           let autodetected = autodetectedLayoutLocale.flatMap(Self.autodetectedDescriptor(locale:)) {
            return autodetected
        }

        return HWKEuropeanLayoutCatalog.descriptor(locale: layoutLocale.rawValue)
            ?? HWKScriptLayoutCatalog.descriptor(locale: layoutLocale.rawValue)
    }

    private func letterText(from layout: HWKResolvedLayout, at slot: PhysicalLetterSlot) -> String? {
        guard let rows = layout.rowsByLayer[.letters],
              rows.indices.contains(slot.row) else {
            return nil
        }

        let keys = rows[slot.row].keys
        guard keys.indices.contains(slot.column) else { return nil }
        let key = keys[slot.column]
        guard key.role == .character else { return nil }

        let text = key.output ?? key.label
        let scalarSet = CharacterSet.letters
        guard text.unicodeScalars.allSatisfy({ scalarSet.contains($0) }) else {
            return nil
        }
        return text
    }

    private struct PhysicalLetterSlot {
        let row: Int
        let column: Int
    }

    private static func autodetectedDescriptor(locale: String) -> HWKLayoutDescriptor? {
        switch locale.lowercased() {
        case "en-us-dvorak", "dvorak":
            return descriptor(locale: "en-US-Dvorak", top: ["'", ",", ".", "p", "y", "f", "g", "c", "r", "l"], middle: "aoeuidhtns", bottom: [";", "q", "j", "k", "x", "b", "m", "w", "v", "z"])
        case "en-us-colemak", "colemak":
            return descriptor(locale: "en-US-Colemak", top: ["q", "w", "f", "p", "g", "j", "l", "u", "y", ";"], middle: "arstdhneio", bottom: "zxcvbkm")
        default:
            return nil
        }
    }

    private static func descriptor(
        locale: String,
        top: [String],
        middle: String,
        bottom: String
    ) -> HWKLayoutDescriptor {
        descriptor(locale: locale, top: top, middle: middle.map(String.init), bottom: bottom.map(String.init))
    }

    private static func descriptor(
        locale: String,
        top: [String],
        middle: String,
        bottom: [String]
    ) -> HWKLayoutDescriptor {
        descriptor(locale: locale, top: top, middle: middle.map(String.init), bottom: bottom)
    }

    private static func descriptor(
        locale: String,
        top: [String],
        middle: [String],
        bottom: [String]
    ) -> HWKLayoutDescriptor {
        HWKLayoutDescriptor(
            schemaVersion: HWKLayoutSchemaVersion.current,
            locale: locale,
            script: "Latn",
            direction: .leftToRight,
            layers: [
                HWKLayoutLayerDescriptor(id: .quickInsert, rows: [
                    .row(id: "quickInsert", values: ["[]", "()", "{}", ".com"], holds: []),
                ]),
                HWKLayoutLayerDescriptor(id: .toolbar, rows: [
                    .row(id: "toolbar", values: [".com", ",", "'", "!", "?", ".", "@", "#"], holds: []),
                ]),
                HWKLayoutLayerDescriptor(id: .letters, rows: [
                    .row(id: "letterTop", values: top, holds: []),
                    .row(id: "letterMiddle", values: middle, holds: []),
                    .row(id: "letterBottom", values: bottom + ["enter"], holds: [], actionLabels: ["enter"]),
                ]),
                HWKLayoutLayerDescriptor(id: .symbols, rows: [
                    .row(id: "symbolTop", values: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"], holds: []),
                    .row(id: "symbolMiddle", values: ["@", "#", "$", "%", "&", "*", "(", ")", "_", "="], holds: []),
                    .row(id: "symbolBottom", values: ["!", "?", ":", ";", "/", "\\", "-", "+", "\"", "'"], holds: []),
                ]),
            ],
            geometry: HWKLayoutGeometry(keyHeight: nil, rowSpacing: nil, keySpacing: nil)
        )
    }

    private static let physicalUSLetterSlot: [UIKeyboardHIDUsage: PhysicalLetterSlot] = [
        .keyboardQ: PhysicalLetterSlot(row: 0, column: 0),
        .keyboardW: PhysicalLetterSlot(row: 0, column: 1),
        .keyboardE: PhysicalLetterSlot(row: 0, column: 2),
        .keyboardR: PhysicalLetterSlot(row: 0, column: 3),
        .keyboardT: PhysicalLetterSlot(row: 0, column: 4),
        .keyboardY: PhysicalLetterSlot(row: 0, column: 5),
        .keyboardU: PhysicalLetterSlot(row: 0, column: 6),
        .keyboardI: PhysicalLetterSlot(row: 0, column: 7),
        .keyboardO: PhysicalLetterSlot(row: 0, column: 8),
        .keyboardP: PhysicalLetterSlot(row: 0, column: 9),
        .keyboardA: PhysicalLetterSlot(row: 1, column: 0),
        .keyboardS: PhysicalLetterSlot(row: 1, column: 1),
        .keyboardD: PhysicalLetterSlot(row: 1, column: 2),
        .keyboardF: PhysicalLetterSlot(row: 1, column: 3),
        .keyboardG: PhysicalLetterSlot(row: 1, column: 4),
        .keyboardH: PhysicalLetterSlot(row: 1, column: 5),
        .keyboardJ: PhysicalLetterSlot(row: 1, column: 6),
        .keyboardK: PhysicalLetterSlot(row: 1, column: 7),
        .keyboardL: PhysicalLetterSlot(row: 1, column: 8),
        .keyboardSemicolon: PhysicalLetterSlot(row: 1, column: 9),
        .keyboardQuote: PhysicalLetterSlot(row: 1, column: 10),
        .keyboardZ: PhysicalLetterSlot(row: 2, column: 0),
        .keyboardX: PhysicalLetterSlot(row: 2, column: 1),
        .keyboardC: PhysicalLetterSlot(row: 2, column: 2),
        .keyboardV: PhysicalLetterSlot(row: 2, column: 3),
        .keyboardB: PhysicalLetterSlot(row: 2, column: 4),
        .keyboardN: PhysicalLetterSlot(row: 2, column: 5),
        .keyboardM: PhysicalLetterSlot(row: 2, column: 6),
        .keyboardComma: PhysicalLetterSlot(row: 2, column: 7),
        .keyboardPeriod: PhysicalLetterSlot(row: 2, column: 8),
        .keyboardSlash: PhysicalLetterSlot(row: 2, column: 9)
    ]
}

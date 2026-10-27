import Foundation

enum HWKEuropeanLayoutCatalog {
    static let supportedLocales = [
        "fr-FR",
        "de-DE",
        "es-ES",
        "it-IT",
        "pt-PT",
        "nl-NL",
        "sv-SE",
    ]

    static func descriptor(locale: String) -> HWKLayoutDescriptor? {
        switch locale {
        case "fr-FR":
            return descriptor(locale: locale, top: "azertyuiop", middle: "qsdfghjklm", bottom: "wxcvbn")
        case "de-DE":
            return descriptor(locale: locale, top: "qwertzuiop", middle: "asdfghjkl", bottom: "yxcvbnm")
        case "es-ES":
            return descriptor(locale: locale, top: "qwertyuiop", middle: "asdfghjklñ", bottom: "zxcvbnm")
        case "it-IT":
            return descriptor(locale: locale, top: "qwertyuiop", middle: "asdfghjklòà", bottom: "zxcvbnm")
        case "pt-PT":
            return descriptor(locale: locale, top: "qwertyuiop", middle: "asdfghjklç", bottom: "zxcvbnm")
        case "nl-NL":
            return descriptor(locale: locale, top: "qwertyuiop", middle: "asdfghjkl", bottom: "zxcvbnm")
        case "sv-SE":
            return descriptor(locale: locale, top: "qwertyuiop", middle: "asdfghjklö", bottom: "zxcvbnmä")
        default:
            return nil
        }
    }

    static func allDescriptors() -> [HWKLayoutDescriptor] {
        supportedLocales.compactMap(descriptor(locale:))
    }

    private static func descriptor(
        locale: String,
        top: String,
        middle: String,
        bottom: String
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
                    .row(id: "letterTop", values: top.map(String.init), holds: numberHolds(count: top.count)),
                    .row(id: "letterMiddle", values: middle.map(String.init), holds: localeHolds(locale: locale, row: .middle, count: middle.count)),
                    .row(id: "letterBottom", values: bottom.map(String.init) + ["enter"], holds: localeHolds(locale: locale, row: .bottom, count: bottom.count) + [""], actionLabels: ["enter"]),
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

    private enum LetterRow {
        case middle
        case bottom
    }

    private static func numberHolds(count: Int) -> [String] {
        Array(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].prefix(count))
    }

    private static func localeHolds(locale: String, row: LetterRow, count: Int) -> [String] {
        let values: [String]
        switch (locale, row) {
        case ("fr-FR", .middle):
            values = ["à", "â", "é", "è", "ê", "ë", "î", "ï", "ô", "ù"]
        case ("de-DE", .middle):
            values = ["ä", "ö", "ü", "ß", "€", "§", "´", "`", "^"]
        case ("es-ES", .middle):
            values = ["á", "é", "í", "ó", "ú", "ü", "ñ", "¿", "¡", "€"]
        case ("it-IT", .middle):
            values = ["à", "è", "é", "ì", "ò", "ù", "€", "'", "’"]
        case ("pt-PT", .middle):
            values = ["á", "à", "â", "ã", "é", "ê", "í", "ó", "õ", "ú"]
        case ("nl-NL", .middle):
            values = ["á", "é", "ë", "ï", "í", "ó", "ö", "ú", "ü"]
        case ("sv-SE", .middle):
            values = ["å", "ä", "ö", "é", "è", "ü", "€", "-", "'"]
        case ("fr-FR", .bottom):
            values = ["ç", "œ", "æ", "€", "-", "'", "’"]
        case ("de-DE", .bottom):
            values = ["ä", "ö", "ü", "€", "-", "'", "’"]
        case ("es-ES", .bottom):
            values = ["ñ", "ç", "€", "-", "'", "’", "¿"]
        case ("it-IT", .bottom):
            values = ["à", "è", "ì", "ò", "ù", "€", "-"]
        case ("pt-PT", .bottom):
            values = ["ç", "ã", "õ", "€", "-", "'", "’"]
        case ("nl-NL", .bottom):
            values = ["ij", "€", "-", "'", "’", "ë", "ï"]
        case ("sv-SE", .bottom):
            values = ["å", "ä", "ö", "é", "€", "-", "'", "’"]
        default:
            values = []
        }

        if values.count >= count {
            return Array(values.prefix(count))
        }
        return values + Array(repeating: "", count: count - values.count)
    }
}

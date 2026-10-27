import Foundation

enum HWKScriptLayoutCatalog {
    static let supportedLocales = [
        "ar",
        "he",
        "th",
        "hi-Deva",
    ]

    static func descriptor(locale: String) -> HWKLayoutDescriptor? {
        switch locale {
        case "ar":
            return descriptor(
                locale: locale,
                script: "Arab",
                direction: .rightToLeft,
                top: ["ض", "ص", "ث", "ق", "ف", "غ", "ع", "ه", "خ", "ح"],
                middle: ["ش", "س", "ي", "ب", "ل", "ا", "ت", "ن", "م", "ك"],
                bottom: ["ظ", "ط", "ذ", "د", "ز", "ر", "و", "ة"]
            )
        case "he":
            return descriptor(
                locale: locale,
                script: "Hebr",
                direction: .rightToLeft,
                top: ["ק", "ר", "א", "ט", "ו", "ן", "ם", "פ", "/", "'"],
                middle: ["ש", "ד", "ג", "כ", "ע", "י", "ח", "ל", "ך", "ף"],
                bottom: ["ז", "ס", "ב", "ה", "נ", "מ", "צ", "ת"]
            )
        case "th":
            return descriptor(
                locale: locale,
                script: "Thai",
                direction: .leftToRight,
                top: ["ๆ", "ไ", "ำ", "พ", "ะ", "ั", "ี", "ร", "น", "ย"],
                middle: ["ฟ", "ห", "ก", "ด", "เ", "้", "่", "า", "ส", "ว"],
                bottom: ["ผ", "ป", "แ", "อ", "ิ", "ื", "ท", "ม"]
            )
        case "hi-Deva":
            return descriptor(
                locale: locale,
                script: "Deva",
                direction: .leftToRight,
                top: ["ौ", "ै", "ा", "ी", "ू", "ब", "ह", "ग", "द", "ज"],
                middle: ["ो", "े", "्", "ि", "ु", "प", "र", "क", "त", "च"],
                bottom: ["ॉ", "ं", "म", "न", "व", "ल", "स", "य"]
            )
        default:
            return nil
        }
    }

    static func allDescriptors() -> [HWKLayoutDescriptor] {
        supportedLocales.compactMap(descriptor(locale:))
    }

    private static func descriptor(
        locale: String,
        script: String,
        direction: HWKLayoutDirection,
        top: [String],
        middle: [String],
        bottom: [String]
    ) -> HWKLayoutDescriptor {
        HWKLayoutDescriptor(
            schemaVersion: HWKLayoutSchemaVersion.current,
            locale: locale,
            script: script,
            direction: direction,
            layers: [
                HWKLayoutLayerDescriptor(id: .quickInsert, rows: [
                    .row(id: "quickInsert", values: ["[]", "()", "{}", ".com"], holds: []),
                ]),
                HWKLayoutLayerDescriptor(id: .toolbar, rows: [
                    .row(id: "toolbar", values: [".com", ",", "'", "!", "?", ".", "@", "#"], holds: []),
                ]),
                HWKLayoutLayerDescriptor(id: .letters, rows: [
                    .row(id: "letterTop", values: top, holds: numberHolds(count: top.count)),
                    .row(id: "letterMiddle", values: middle, holds: scriptHolds(count: middle.count)),
                    .row(
                        id: "letterBottom",
                        values: bottom + ["enter"],
                        holds: scriptHolds(count: bottom.count) + [""],
                        actionLabels: ["enter"]
                    ),
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

    private static func numberHolds(count: Int) -> [String] {
        Array(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"].prefix(count))
    }

    private static func scriptHolds(count: Int) -> [String] {
        Array(repeating: "", count: count)
    }
}

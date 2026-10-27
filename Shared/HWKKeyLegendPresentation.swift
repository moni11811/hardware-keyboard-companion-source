import Foundation

struct HWKKeyLegendPresentation: Equatable, Sendable {
    enum Density: Equatable, Sendable {
        case glyph
        case word
        case phrase
        case sentence
        case compactSentence
    }

    let text: String
    let accessibilityText: String
    let density: Density
    let lineLimit: Int
    let maximumFontSize: Double
    let minimumScaleFactor: Double
    let usesFullKeyWidth: Bool

    static func resolve(_ rawValue: String) -> HWKKeyLegendPresentation {
        let normalized = rawValue
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let text = normalized.isEmpty ? " " : normalized
        let hasMultipleWords = text.contains(" ")

        if !hasMultipleWords, text.count <= 2 {
            return HWKKeyLegendPresentation(
                text: text,
                accessibilityText: text,
                density: .glyph,
                lineLimit: 1,
                maximumFontSize: 44,
                minimumScaleFactor: 1,
                usesFullKeyWidth: false
            )
        }

        if !hasMultipleWords, text.count <= 12 {
            return HWKKeyLegendPresentation(
                text: text,
                accessibilityText: text,
                density: .word,
                lineLimit: 1,
                maximumFontSize: 16,
                minimumScaleFactor: 0.62,
                usesFullKeyWidth: true
            )
        }

        if text.count <= 22 {
            return HWKKeyLegendPresentation(
                text: text,
                accessibilityText: text,
                density: .phrase,
                lineLimit: 2,
                maximumFontSize: 11,
                minimumScaleFactor: 0.72,
                usesFullKeyWidth: true
            )
        }

        if text.count <= 34 {
            return HWKKeyLegendPresentation(
                text: text,
                accessibilityText: text,
                density: .sentence,
                lineLimit: 3,
                maximumFontSize: 9.5,
                minimumScaleFactor: 0.68,
                usesFullKeyWidth: true
            )
        }

        return HWKKeyLegendPresentation(
            text: compactSentencePreview(text),
            accessibilityText: text,
            density: .compactSentence,
            lineLimit: 3,
            maximumFontSize: 9,
            minimumScaleFactor: 0.72,
            usesFullKeyWidth: true
        )
    }

    private static func compactSentencePreview(_ sentence: String) -> String {
        let words = sentence.split(separator: " ").map(String.init)
        guard words.count > 2 else {
            return sentence
        }

        let leading = edgePhrase(from: words, reversed: false)
        let trailing = edgePhrase(from: words, reversed: true)
        return "\(leading)\n⋯\n\(trailing)"
    }

    private static func edgePhrase(from words: [String], reversed: Bool) -> String {
        let candidates = reversed ? Array(words.reversed()) : words
        var selected: [String] = []

        for word in candidates {
            let proposed = (selected + [word]).joined(separator: " ")
            guard proposed.count <= 14 || selected.isEmpty else { break }
            selected.append(word)
        }

        if reversed {
            selected.reverse()
        }
        return selected.joined(separator: " ")
    }
}

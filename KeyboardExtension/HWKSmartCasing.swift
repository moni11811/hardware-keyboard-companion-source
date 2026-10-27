import Foundation
import UIKit

enum HWKCasingMode: Equatable {
    case preserve
    case lowercase
    case capitalizeFirst
    case uppercase
}

struct HWKSmartCasingContext: Equatable {
    let precedingText: String
    let keyboardType: UIKeyboardType
    let autocapitalizationType: UITextAutocapitalizationType
    let isSecureTextEntry: Bool

    init(
        precedingText: String,
        keyboardType: UIKeyboardType = .default,
        autocapitalizationType: UITextAutocapitalizationType = .sentences,
        isSecureTextEntry: Bool = false
    ) {
        self.precedingText = precedingText
        self.keyboardType = keyboardType
        self.autocapitalizationType = autocapitalizationType
        self.isSecureTextEntry = isSecureTextEntry
    }
}

struct HWKSmartCasing {
    static func shouldCapitalizeSentence(after text: String?) -> Bool {
        guard let text else { return true }
        guard !text.isEmpty else { return true }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }

        if text.last?.isNewline == true {
            return true
        }

        var index = text.endIndex
        var sawWhitespaceAfterBoundary = false
        while index > text.startIndex {
            let previousIndex = text.index(before: index)
            let character = text[previousIndex]

            if character.isNewline {
                return true
            }

            if character.isWhitespace {
                sawWhitespaceAfterBoundary = true
                index = previousIndex
                continue
            }

            if isSentencePrefixCharacter(character) {
                index = previousIndex
                continue
            }

            guard isSentenceBoundary(character) else { return false }
            if character == "." {
                return sawWhitespaceAfterBoundary || shouldCapitalizeAfterUnspacedPeriod(
                    in: text,
                    boundaryAt: previousIndex
                )
            }
            return true
        }

        return true
    }

    func mode(for context: HWKSmartCasingContext) -> HWKCasingMode {
        guard !context.isSecureTextEntry else { return .preserve }

        switch context.keyboardType {
        case .emailAddress, .URL:
            return .lowercase
        default:
            break
        }

        switch context.autocapitalizationType {
        case .none:
            return .preserve
        case .allCharacters:
            return .uppercase
        case .words:
            return shouldCapitalizeWord(after: context.precedingText) ? .capitalizeFirst : .preserve
        case .sentences:
            return Self.shouldCapitalizeSentence(after: context.precedingText) ? .capitalizeFirst : .preserve
        @unknown default:
            return .preserve
        }
    }

    func apply(_ mode: HWKCasingMode, to candidate: String) -> String {
        switch mode {
        case .preserve:
            return candidate
        case .lowercase:
            return candidate.lowercased()
        case .capitalizeFirst:
            guard let first = candidate.first else { return candidate }
            return first.uppercased() + candidate.dropFirst()
        case .uppercase:
            return candidate.uppercased()
        }
    }

    private func shouldCapitalizeWord(after text: String) -> Bool {
        guard let last = text.last else { return true }
        return last.isWhitespace || last.isNewline
    }

    private static func isSentencePrefixCharacter(_ character: Character) -> Bool {
        "\"'()[]{}<>“”‘’".contains(character)
    }

    private static func isSentenceBoundary(_ character: Character) -> Bool {
        character == "." || character == "!" || character == "?"
    }

    private static func shouldCapitalizeAfterUnspacedPeriod(
        in text: String,
        boundaryAt boundaryIndex: String.Index
    ) -> Bool {
        let beforeBoundary = text[..<boundaryIndex]
        guard let previousCharacter = beforeBoundary.last,
              !previousCharacter.isNumber,
              previousCharacter != "." else {
            return false
        }

        let token = beforeBoundary
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .last
            .map(String.init) ?? ""
        let normalizedToken = token
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'()[]{}<>“”‘’"))
            .lowercased()

        guard normalizedToken.count > 1,
              !normalizedToken.contains("."),
              normalizedToken != "www" else {
            return false
        }

        let commonAbbreviations: Set<String> = [
            "dr", "mr", "mrs", "ms", "prof", "sr", "jr", "st", "vs", "etc",
        ]
        return !commonAbbreviations.contains(normalizedToken)
    }
}

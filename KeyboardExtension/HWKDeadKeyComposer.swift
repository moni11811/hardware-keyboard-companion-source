import Foundation
import UIKit

enum HWKDeadKey: String, Codable, CaseIterable {
    case acute
    case grave
    case circumflex
    case diaeresis
    case tilde
    case cedilla

    var mark: String {
        switch self {
        case .acute:
            return "\u{0301}"
        case .grave:
            return "\u{0300}"
        case .circumflex:
            return "\u{0302}"
        case .diaeresis:
            return "\u{0308}"
        case .tilde:
            return "\u{0303}"
        case .cedilla:
            return "\u{0327}"
        }
    }

    var spacingMark: String {
        switch self {
        case .acute:
            return "´"
        case .grave:
            return "`"
        case .circumflex:
            return "^"
        case .diaeresis:
            return "¨"
        case .tilde:
            return "~"
        case .cedilla:
            return "¸"
        }
    }

    init?(inputToken: String) {
        switch inputToken {
        case "´":
            self = .acute
        case "`":
            self = .grave
        case "^":
            self = .circumflex
        case "¨":
            self = .diaeresis
        case "~":
            self = .tilde
        case "¸":
            self = .cedilla
        default:
            return nil
        }
    }

    init?(hardwareOptionKeyCode: UIKeyboardHIDUsage) {
        switch hardwareOptionKeyCode {
        case .keyboardE:
            self = .acute
        case .keyboardGraveAccentAndTilde:
            self = .grave
        case .keyboardI:
            self = .circumflex
        case .keyboardU:
            self = .diaeresis
        case .keyboardN:
            self = .tilde
        case .keyboardC:
            self = .cedilla
        default:
            return nil
        }
    }
}

enum HWKDeadKeyComposeResult: Equatable {
    case pending(String)
    case commit(String)
}

struct HWKDeadKeyComposer {
    private(set) var pendingDeadKey: HWKDeadKey?

    var hasPendingDeadKey: Bool {
        pendingDeadKey != nil
    }

    mutating func press(deadKey: HWKDeadKey) -> HWKDeadKeyComposeResult {
        if let pendingDeadKey {
            let committed = pendingDeadKey.spacingMark + deadKey.spacingMark
            self.pendingDeadKey = nil
            return .commit(committed)
        }

        pendingDeadKey = deadKey
        return .pending(deadKey.spacingMark)
    }

    mutating func input(_ text: String) -> HWKDeadKeyComposeResult {
        guard let deadKey = pendingDeadKey else {
            return .commit(text)
        }

        pendingDeadKey = nil

        if text == " " {
            return .commit(deadKey.spacingMark)
        }

        guard text.count == 1 else {
            return .commit(deadKey.spacingMark + text)
        }

        let decomposed = text + deadKey.mark
        let composed = HWKNormalization.nfc(decomposed)
        guard !composed.unicodeScalars.elementsEqual(decomposed.unicodeScalars) else {
            return .commit(deadKey.spacingMark + text)
        }

        return .commit(composed)
    }

    mutating func backspace() -> Bool {
        guard pendingDeadKey != nil else { return false }
        pendingDeadKey = nil
        return true
    }
}

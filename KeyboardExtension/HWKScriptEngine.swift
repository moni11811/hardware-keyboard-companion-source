import Foundation

enum HWKScript: String, Codable, Equatable {
    case latin
    case arabic
    case hebrew
    case thai
    case devanagari
    case unknown
}

struct HWKScriptEngine {
    func script(for text: String) -> HWKScript {
        guard let scalar = text.unicodeScalars.first else { return .unknown }
        return script(for: scalar)
    }

    func dominantScript(for text: String) -> HWKScript {
        var counts = [HWKScript: Int]()
        for scalar in text.unicodeScalars {
            let script = script(for: scalar)
            guard script != .unknown else { continue }
            counts[script, default: 0] += 1
        }
        return counts.max { lhs, rhs in lhs.value < rhs.value }?.key ?? .unknown
    }

    private func script(for scalar: UnicodeScalar) -> HWKScript {
        switch scalar.value {
        case 0x0000...0x024F:
            return CharacterSet.letters.contains(scalar) ? .latin : .unknown
        case 0x0590...0x05FF:
            return .hebrew
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
            return .arabic
        case 0x0900...0x097F:
            return .devanagari
        case 0x0E00...0x0E7F:
            return .thai
        default:
            return .unknown
        }
    }

    func direction(for script: HWKScript) -> HWKTextDirection {
        switch script {
        case .arabic, .hebrew:
            return .rightToLeft
        case .latin, .thai, .devanagari:
            return .leftToRight
        case .unknown:
            return .neutral
        }
    }
}

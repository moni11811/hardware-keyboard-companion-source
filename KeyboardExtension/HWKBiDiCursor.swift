import Foundation

enum HWKTextDirection: String, Codable, Equatable {
    case leftToRight
    case rightToLeft
    case neutral
}

struct HWKBiDiCursor {
    func baseDirection(for text: String) -> HWKTextDirection {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x0590...0x08FF).contains(value) {
                return .rightToLeft
            }
            if CharacterSet.letters.contains(scalar) {
                return .leftToRight
            }
        }
        return .neutral
    }

    func visualOffset(logicalOffset: Int, direction: HWKTextDirection) -> Int {
        direction == .rightToLeft ? -logicalOffset : logicalOffset
    }
}


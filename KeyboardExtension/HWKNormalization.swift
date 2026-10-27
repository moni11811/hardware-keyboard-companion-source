import Foundation

enum HWKNormalization {
    static func nfc(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
    }
}


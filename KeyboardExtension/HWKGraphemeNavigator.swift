import Foundation

struct HWKGraphemeNavigator {
    func deleteBackward(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var copy = text
        copy.removeLast()
        return copy
    }

    func deleteForward(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var copy = text
        copy.removeFirst()
        return copy
    }

    func clusters(in text: String) -> [String] {
        text.map(String.init)
    }
}


import Foundation

struct HWKPreeditBuffer: Equatable {
    var text = ""

    var isEmpty: Bool {
        text.isEmpty
    }

    mutating func set(_ value: String) {
        text = value
    }

    mutating func clear() {
        text = ""
    }
}


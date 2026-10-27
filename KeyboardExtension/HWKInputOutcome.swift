import Foundation

enum HWKInputSideEffect: Equatable {
    case updateSuggestions
    case refreshLayout
    case feedback
    case recordHardwareEvent
    case forwardUnhandled
}

enum HWKTextMutation: Equatable {
    case insert(String)
    case deleteBackward(count: Int)
    case deleteForward(count: Int)
    case moveCursor(offset: Int)
    case setMarkedText(String)
    case unmarkText
}

struct HWKInputOutcome: Equatable {
    var consumed: Bool
    var textMutations: [HWKTextMutation]
    var sideEffects: [HWKInputSideEffect]

    static let ignored = HWKInputOutcome(consumed: false, textMutations: [], sideEffects: [])

    static func consume(
        _ mutations: [HWKTextMutation],
        sideEffects: [HWKInputSideEffect] = []
    ) -> HWKInputOutcome {
        HWKInputOutcome(consumed: true, textMutations: mutations, sideEffects: sideEffects)
    }
}


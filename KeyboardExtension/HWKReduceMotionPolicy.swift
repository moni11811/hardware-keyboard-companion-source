import Foundation

enum HWKMotionIntent: Equatable {
    case keyPress
    case layoutTransition
    case decorative
}

struct HWKReduceMotionPolicy {
    let reduceMotionEnabled: Bool

    func allowsAnimation(for intent: HWKMotionIntent) -> Bool {
        guard reduceMotionEnabled else { return true }

        switch intent {
        case .keyPress:
            return true
        case .layoutTransition, .decorative:
            return false
        }
    }
}

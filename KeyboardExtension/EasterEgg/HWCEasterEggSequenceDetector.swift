import UIKit

final class HWCEasterEggSequenceDetector {
    static let maxGap: TimeInterval = 0.5

    enum Step: Equatable {
        case left
        case right
        case slash
        case backslash
        case space
    }

    enum Observation: Equatable {
        case ignored
        case matched(progress: Int)
        case triggered
    }

    private static let pattern: [Step] = [.left, .right, .left, .right, .slash, .backslash, .space]

    private var index = 0
    private var lastAt: Date?

    func observe(key: UIKey, isRepeat: Bool = false, at now: Date = Date()) -> Bool {
        observeResult(key: key, isRepeat: isRepeat, at: now) == .triggered
    }

    func observe(keyCode: UIKeyboardHIDUsage, charactersIgnoringModifiers: String?, isRepeat: Bool = false, at now: Date = Date()) -> Bool {
        observeResult(
            keyCode: keyCode,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isRepeat: isRepeat,
            at: now
        ) == .triggered
    }

    func observeResult(key: UIKey, isRepeat: Bool = false, at now: Date = Date()) -> Observation {
        observeResult(
            keyCode: key.keyCode,
            charactersIgnoringModifiers: key.charactersIgnoringModifiers,
            isRepeat: isRepeat,
            at: now
        )
    }

    func observeResult(
        keyCode: UIKeyboardHIDUsage,
        charactersIgnoringModifiers: String?,
        isRepeat: Bool = false,
        at now: Date = Date()
    ) -> Observation {
        guard !isRepeat else { return .ignored }
        guard !Self.isModifierOnlyKeyCode(keyCode) else { return .ignored }
        guard let step = Self.step(for: keyCode, charactersIgnoringModifiers: charactersIgnoringModifiers) else {
            reset()
            return .ignored
        }

        return observeResolvedStep(step, at: now)
    }

    func observeResult(step: Step, isRepeat: Bool = false, at now: Date = Date()) -> Observation {
        guard !isRepeat else { return .ignored }
        return observeResolvedStep(step, at: now)
    }

    private func observeResolvedStep(_ step: Step, at now: Date) -> Observation {
        if let lastAt, now.timeIntervalSince(lastAt) > Self.maxGap {
            reset()
        }

        if step == Self.pattern[index] {
            index += 1
            lastAt = now
            if index == Self.pattern.count {
                reset()
                return .triggered
            }
            return .matched(progress: index)
        }

        reset()
        guard step == Self.pattern[0] else { return .ignored }
        index = 1
        lastAt = now
        return .matched(progress: index)
    }

    func reset() {
        index = 0
        lastAt = nil
    }

    private static func step(for keyCode: UIKeyboardHIDUsage, charactersIgnoringModifiers: String?) -> Step? {
        if charactersIgnoringModifiers == "/" {
            return .slash
        }
        if charactersIgnoringModifiers == "\\" {
            return .backslash
        }

        switch keyCode {
        case .keyboardLeftArrow:
            return .left
        case .keyboardRightArrow:
            return .right
        case .keyboardSpacebar:
            return .space
        default:
            return nil
        }
    }

    private static func isModifierOnlyKeyCode(_ keyCode: UIKeyboardHIDUsage) -> Bool {
        switch keyCode {
        case .keyboardLeftShift, .keyboardRightShift,
             .keyboardLeftControl, .keyboardRightControl,
             .keyboardLeftAlt, .keyboardRightAlt,
             .keyboardLeftGUI, .keyboardRightGUI,
             .keyboardCapsLock, .keyboardLockingCapsLock:
            return true
        default:
            return false
        }
    }
}

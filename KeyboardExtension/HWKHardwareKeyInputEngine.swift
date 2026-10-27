import UIKit

typealias HWKHardwareKeyModifier = KeyModifier

struct HWKHardwareKeyInput {
    enum Phase: Equatable {
        case down
        case up
        case cancel
    }

    let phase: Phase
    let keyCode: Int
    let characters: String?
    let charactersIgnoringModifiers: String?
    let modifierFlags: UIKeyModifierFlags
    let isRepeat: Bool

    init(
        phase: Phase,
        keyCode: Int,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifierFlags: UIKeyModifierFlags,
        isRepeat: Bool = false
    ) {
        self.phase = phase
        self.keyCode = keyCode
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.modifierFlags = modifierFlags
        self.isRepeat = isRepeat
    }
}

struct HWKHardwareKeyCapturePayload: Equatable {
    let keyCode: Int
    let characters: String?
    let charactersIgnoringModifiers: String?
    let modifiers: Set<HWKHardwareKeyModifier>
}

enum HWKHardwareKeyOutput: Equatable {
    case keyDown(HWKHardwareKeyCapturePayload)
    case keyUp(HWKHardwareKeyCapturePayload)
    case modifier(HWKHardwareKeyModifier, isActive: Bool)
}

enum HWKHardwareHID {
    static func usage(from keyCode: Int) -> UIKeyboardHIDUsage? {
        UIKeyboardHIDUsage(rawValue: keyCode)
    }

    static func isSystemCommandModifier(_ modifier: HWKHardwareKeyModifier) -> Bool {
        switch modifier {
        case .command, .control, .option:
            return true
        case .shift, .capsLock, .numericPad, .alphaShift:
            return false
        }
    }
}

struct HWKHardwareKeyInputEngine {
    private var activeKeys = [Int: HWKHardwareKeyCapturePayload]()
    private var activeModifierKeys = [Int: HWKHardwareKeyModifier]()
    private var activeCapsLockKeyCodes = Set<Int>()
    private var capsLocked = false
    private var ignoreAlphaShiftUntilCleared = false

    var activeModifiers: Set<HWKHardwareKeyModifier> {
        Set(activeModifierKeys.values).union(capsLocked ? [.capsLock] : [])
    }

    mutating func handle(_ input: HWKHardwareKeyInput) -> [HWKHardwareKeyOutput] {
        guard let usage = HWKHardwareHID.usage(from: input.keyCode) else {
            return handlePrintable(input)
        }

        if let modifier = Self.modifier(for: usage) {
            return handleModifier(input, usage: usage, modifier: modifier)
        }

        if input.phase == .down {
            var outputs = syncLatchedCaps(from: input.modifierFlags)
            outputs.append(contentsOf: syncLevelModifiers(from: input.modifierFlags))
            outputs.append(contentsOf: handlePrintable(input))
            return outputs
        }
        return handlePrintable(input)
    }

    static func modifier(for usage: UIKeyboardHIDUsage) -> HWKHardwareKeyModifier? {
        switch usage {
        case .keyboardLeftShift, .keyboardRightShift:
            return .shift
        case .keyboardCapsLock, .keyboardLockingCapsLock:
            return .capsLock
        case .keyboardLeftControl, .keyboardRightControl:
            return .control
        case .keyboardLeftAlt, .keyboardRightAlt:
            return .option
        case .keyboardLeftGUI, .keyboardRightGUI:
            return .command
        default:
            return nil
        }
    }

    private mutating func handleModifier(
        _ input: HWKHardwareKeyInput,
        usage: UIKeyboardHIDUsage,
        modifier: HWKHardwareKeyModifier
    ) -> [HWKHardwareKeyOutput] {
        if modifier == .capsLock {
            switch input.phase {
            case .down:
                guard !activeCapsLockKeyCodes.contains(input.keyCode) || !input.isRepeat else { return [] }
                activeCapsLockKeyCodes.insert(input.keyCode)
                let nextCapsLocked = !capsLocked
                ignoreAlphaShiftUntilCleared = !nextCapsLocked && input.modifierFlags.contains(.alphaShift)
                guard capsLocked != nextCapsLocked else { return [] }
                capsLocked = nextCapsLocked
                return [.modifier(.capsLock, isActive: capsLocked)]
            case .up:
                activeCapsLockKeyCodes.remove(input.keyCode)
                return []
            case .cancel:
                activeCapsLockKeyCodes.remove(input.keyCode)
                let wasLocked = capsLocked
                capsLocked = false
                ignoreAlphaShiftUntilCleared = wasLocked
                return wasLocked ? [.modifier(.capsLock, isActive: false)] : []
            }
        }

        switch input.phase {
        case .down:
            let wasActive = activeModifierKeys.values.contains(modifier)
            activeModifierKeys[input.keyCode] = modifier
            return wasActive ? [] : [.modifier(modifier, isActive: true)]
        case .up, .cancel:
            let wasActive = activeModifierKeys.values.contains(modifier)
            activeModifierKeys.removeValue(forKey: input.keyCode)
            let isActive = activeModifierKeys.values.contains(modifier)
            guard wasActive, !isActive else { return [] }
            return [.modifier(modifier, isActive: false)]
        }
    }

    private mutating func handlePrintable(_ input: HWKHardwareKeyInput) -> [HWKHardwareKeyOutput] {
        switch input.phase {
        case .down:
            let previous = activeKeys[input.keyCode]
            let payload = HWKHardwareKeyCapturePayload(
                keyCode: input.keyCode,
                characters: input.characters,
                charactersIgnoringModifiers: input.charactersIgnoringModifiers,
                modifiers: activeModifiers
            )
            activeKeys[input.keyCode] = payload
            if let previous, !input.isRepeat {
                let releasePayload = HWKHardwareKeyCapturePayload(
                    keyCode: input.keyCode,
                    characters: nil,
                    charactersIgnoringModifiers: nil,
                    modifiers: previous.modifiers
                )
                return [.keyUp(releasePayload), .keyDown(payload)]
            }
            return [.keyDown(payload)]
        case .up, .cancel:
            let previous = activeKeys.removeValue(forKey: input.keyCode)
            let payload = HWKHardwareKeyCapturePayload(
                keyCode: input.keyCode,
                characters: nil,
                charactersIgnoringModifiers: nil,
                modifiers: previous?.modifiers ?? activeModifiers
            )
            return [.keyUp(payload)]
        }
    }

    private mutating func syncLevelModifiers(from flags: UIKeyModifierFlags) -> [HWKHardwareKeyOutput] {
        let previousModifiers = activeLevelModifiers
        activeModifierKeys = activeModifierKeys.filter { keyCode, modifier in
            switch modifier {
            case .shift:
                return flags.contains(.shift)
            case .control:
                return flags.contains(.control)
            case .option:
                return flags.contains(.alternate)
            case .command:
                return flags.contains(.command)
            case .capsLock, .alphaShift, .numericPad:
                return true
            }
        }

        if flags.contains(.shift), !activeModifierKeys.values.contains(.shift) {
            activeModifierKeys[Int(UIKeyboardHIDUsage.keyboardLeftShift.rawValue)] = .shift
        }
        if flags.contains(.control), !activeModifierKeys.values.contains(.control) {
            activeModifierKeys[Int(UIKeyboardHIDUsage.keyboardLeftControl.rawValue)] = .control
        }
        if flags.contains(.alternate), !activeModifierKeys.values.contains(.option) {
            activeModifierKeys[Int(UIKeyboardHIDUsage.keyboardLeftAlt.rawValue)] = .option
        }
        if flags.contains(.command), !activeModifierKeys.values.contains(.command) {
            activeModifierKeys[Int(UIKeyboardHIDUsage.keyboardLeftGUI.rawValue)] = .command
        }

        let currentModifiers = activeLevelModifiers
        return Self.levelModifierOrder.compactMap { modifier in
            if previousModifiers.contains(modifier), !currentModifiers.contains(modifier) {
                return .modifier(modifier, isActive: false)
            }
            if !previousModifiers.contains(modifier), currentModifiers.contains(modifier) {
                return .modifier(modifier, isActive: true)
            }
            return nil
        }
    }

    private mutating func syncLatchedCaps(from flags: UIKeyModifierFlags) -> [HWKHardwareKeyOutput] {
        let previousCapsLocked = capsLocked
        if ignoreAlphaShiftUntilCleared {
            guard !flags.contains(.alphaShift) else { return [] }
            ignoreAlphaShiftUntilCleared = false
        }
        capsLocked = flags.contains(.alphaShift)
        guard previousCapsLocked != capsLocked else { return [] }
        return [.modifier(.capsLock, isActive: capsLocked)]
    }

    private var activeLevelModifiers: Set<HWKHardwareKeyModifier> {
        Set(activeModifierKeys.values)
    }

    private static let levelModifierOrder: [HWKHardwareKeyModifier] = [
        .shift,
        .control,
        .option,
        .command
    ]
}

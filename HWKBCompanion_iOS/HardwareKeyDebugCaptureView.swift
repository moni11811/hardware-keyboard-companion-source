#if HWC_INTERNAL_BUILD
import SwiftUI
import UIKit

struct KeyDebugCaptureBridge: UIViewRepresentable {
    let isEnabled: Bool
    let emitKeyUp: Bool
    let onEvent: (KeyEvent) -> Void

    func makeUIView(context: Context) -> KeyDebugCaptureView {
        let view = KeyDebugCaptureView()
        view.onEvent = onEvent
        view.emitKeyUp = emitKeyUp
        view.isCaptureEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: KeyDebugCaptureView, context: Context) {
        uiView.onEvent = onEvent
        uiView.emitKeyUp = emitKeyUp
        uiView.isCaptureEnabled = isEnabled
        uiView.refreshCaptureState()
    }
}

final class KeyDebugCaptureView: UIView {
    var onEvent: ((KeyEvent) -> Void)?
    var emitKeyUp = true
    var isCaptureEnabled = false {
        didSet {
            if !isCaptureEnabled {
                lastObservedModifierFlags = []
            }
            refreshCaptureState()
        }
    }
    private var lastObservedModifierFlags: UIKeyModifierFlags = []

    override var canBecomeFirstResponder: Bool {
        isCaptureEnabled
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshCaptureState()
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        refreshCaptureState()
    }

    func refreshCaptureState() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard window != nil else { return }

            if isCaptureEnabled {
                if !isFirstResponder {
                    becomeFirstResponder()
                }
            } else if isFirstResponder {
                resignFirstResponder()
            }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = processPresses(presses, phase: .down, event: event)
        guard !unhandledPresses.isEmpty else { return }
        super.pressesBegan(unhandledPresses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = processPresses(presses, phase: .up, event: event)
        guard !unhandledPresses.isEmpty else { return }
        super.pressesEnded(unhandledPresses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = processPresses(presses, phase: .up, event: event)
        guard !unhandledPresses.isEmpty else { return }
        super.pressesCancelled(unhandledPresses, with: event)
    }

    private func processPresses(
        _ presses: Set<UIPress>,
        phase: KeyPhase,
        event: UIPressesEvent?
    ) -> Set<UIPress> {
        guard isCaptureEnabled else { return presses }

        syncModifierStateIfNeeded(with: presses, fallbackFlags: event?.modifierFlags)

        var unhandledPresses = Set<UIPress>()

        for press in presses {
            guard let key = press.key else {
                unhandledPresses.insert(press)
                continue
            }

            if phase == .up && !emitKeyUp {
                continue
            }

            onEvent?(
                KeyEvent(
                    source: .appDebug,
                    phase: phase,
                    characters: normalizedHardwareCharacters(key.characters),
                    charactersIgnoringModifiers: normalizedHardwareCharacters(key.charactersIgnoringModifiers),
                    keyCode: Int(key.keyCode.rawValue),
                    modifiers: hardwareModifiers(from: key.modifierFlags),
                    isRepeat: false
                )
            )
        }

        return unhandledPresses
    }

    private func syncModifierStateIfNeeded(
        with presses: Set<UIPress>,
        fallbackFlags: UIKeyModifierFlags?
    ) {
        let currentFlags = fallbackFlags ?? presses.reduce(into: UIKeyModifierFlags()) { result, press in
            result.formUnion(press.key?.modifierFlags ?? [])
        }
        let previousFlags = lastObservedModifierFlags
        lastObservedModifierFlags = currentFlags

        let previousShiftHeld = previousFlags.contains(.shift)
        let currentShiftHeld = currentFlags.contains(.shift)
        guard previousShiftHeld != currentShiftHeld else { return }

        let hasExplicitShiftPress = presses.contains { press in
            guard let key = press.key else { return false }
            return key.keyCode == .keyboardLeftShift || key.keyCode == .keyboardRightShift
        }
        guard !hasExplicitShiftPress else { return }

        if !currentShiftHeld && !emitKeyUp {
            return
        }

        onEvent?(
            KeyEvent(
                source: .appDebug,
                phase: currentShiftHeld ? .down : .up,
                characters: "⇧",
                charactersIgnoringModifiers: "⇧",
                modifiers: currentShiftHeld ? [.shift] : [],
                isRepeat: false
            )
        )
    }

    private func normalizedHardwareCharacters(_ characters: String?) -> String? {
        guard let characters, !characters.isEmpty else { return nil }
        return characters
    }

    private func hardwareModifiers(from flags: UIKeyModifierFlags) -> Set<KeyModifier> {
        var modifiers = Set<KeyModifier>()

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.alternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.alphaShift) {
            modifiers.insert(.capsLock)
            modifiers.insert(.alphaShift)
        }
        if flags.contains(.numericPad) {
            modifiers.insert(.numericPad)
        }

        return modifiers
    }
}
#endif

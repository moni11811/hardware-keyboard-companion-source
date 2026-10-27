import Foundation

final class HWKKernel {
    private let telemetry: HWKTelemetryRecording
    private var textEngine = HWKTextEngine()
    private var deadKeysEnabled = true

    init(telemetry: HWKTelemetryRecording = HWKOSLogTelemetryRecorder(), deadKeysEnabled: Bool = true) {
        self.telemetry = telemetry
        self.deadKeysEnabled = deadKeysEnabled
    }

    func setDeadKeysEnabled(_ isEnabled: Bool) {
        guard deadKeysEnabled != isEnabled else { return }
        deadKeysEnabled = isEnabled
        if !isEnabled {
            textEngine = HWKTextEngine()
        }
    }

    func resetCompositionState() {
        textEngine = HWKTextEngine()
    }

    func handle(_ event: HWKInputEvent) -> HWKInputOutcome {
        telemetry.record(.begin(for: event))
        let outcome = resolve(event)
        telemetry.record(.end(for: event, outcome: outcome))
        return outcome
    }

    private func resolve(_ event: HWKInputEvent) -> HWKInputOutcome {
        if case .modifierOnly = event.kind {
            return HWKInputOutcome(consumed: false, textMutations: [], sideEffects: [.recordHardwareEvent])
        }

        guard event.phase == .down else {
            return .ignored
        }

        if deadKeysEnabled {
            switch event.kind {
            case .character(let text) where !text.isEmpty && event.source != .softwareKey:
                if let deadKey = HWKDeadKey(inputToken: text) {
                    return textEngine.handle(
                        HWKInputEvent(
                            source: event.source,
                            kind: .deadKey(deadKey),
                            keyCode: event.keyCode,
                            characters: text,
                            modifierState: event.modifierState,
                            phase: event.phase
                        )
                    )
                }

                if textEngine.hasPendingPreedit {
                    return textEngine.handle(
                        HWKInputEvent(
                            source: event.source,
                            kind: .character(text),
                            keyCode: event.keyCode,
                            characters: text,
                            modifierState: event.modifierState,
                            phase: event.phase
                        )
                    )
                }
            case .deleteBackward where textEngine.hasPendingPreedit:
                return textEngine.handle(
                    HWKInputEvent(
                        source: event.source,
                        kind: .deleteBackward,
                        keyCode: event.keyCode,
                        characters: event.characters,
                        modifierState: event.modifierState,
                        phase: event.phase
                    )
                )
            default:
                break
            }
        }

        switch event.kind {
        case .character(let text):
            guard !text.isEmpty else { return .ignored }
            return .consume([.insert(text)], sideEffects: [.updateSuggestions, .feedback])
        case .deadKey:
            return HWKInputOutcome(consumed: false, textMutations: [], sideEffects: [.forwardUnhandled])
        case .deleteBackward:
            return .consume([.deleteBackward(count: 1)], sideEffects: [.updateSuggestions, .feedback])
        case .deleteForward:
            return .consume([.deleteForward(count: 1)], sideEffects: [.updateSuggestions, .feedback])
        case .returnKey:
            return .consume([.insert("\n")], sideEffects: [.updateSuggestions, .feedback])
        case .tab:
            return .consume([.insert("\t")], sideEffects: [.updateSuggestions, .feedback])
        case .cursor(let offset):
            return .consume([.moveCursor(offset: offset)], sideEffects: [.feedback])
        case .modifierOnly:
            return .ignored
        case .escape, .layoutCommand, .unknown:
            return HWKInputOutcome(consumed: false, textMutations: [], sideEffects: [.forwardUnhandled])
        }
    }
}

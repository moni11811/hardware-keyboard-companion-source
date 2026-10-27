import Foundation

struct HWKTextEngine {
    private var deadKeyComposer = HWKDeadKeyComposer()
    private var preeditBuffer = HWKPreeditBuffer()

    var hasPendingPreedit: Bool {
        deadKeyComposer.hasPendingDeadKey
    }

    mutating func press(deadKey: HWKDeadKey) -> HWKDeadKeyComposeResult {
        let result = deadKeyComposer.press(deadKey: deadKey)
        if case .pending(let text) = result {
            preeditBuffer.set(text)
        }
        return result
    }

    mutating func input(_ text: String) -> HWKDeadKeyComposeResult {
        let result = deadKeyComposer.input(text)
        preeditBuffer.clear()
        return result
    }

    mutating func backspaceConsumesPreedit() -> Bool {
        guard deadKeyComposer.backspace() else { return false }
        preeditBuffer.clear()
        return true
    }

    mutating func handle(_ event: HWKInputEvent) -> HWKInputOutcome {
        guard event.phase == .down else { return .ignored }

        switch event.kind {
        case .deadKey(let deadKey):
            let result = press(deadKey: deadKey)
            switch result {
            case .pending(let text):
                return .consume([.setMarkedText(text)], sideEffects: [.feedback])
            case .commit(let committed):
                return .consume([.unmarkText, .insert(committed)], sideEffects: [.updateSuggestions, .feedback])
            }
        case .character(let text):
            let result = input(text)
            guard case .commit(let committed) = result else { return .ignored }
            return .consume([.unmarkText, .insert(committed)], sideEffects: [.updateSuggestions, .feedback])
        case .deleteBackward:
            if backspaceConsumesPreedit() {
                return .consume([.unmarkText], sideEffects: [.updateSuggestions, .feedback])
            }
            return HWKKernel().handle(event)
        default:
            return HWKKernel().handle(event)
        }
    }
}

enum HWKSoftwareInputAction: Equatable {
    case protectedInsert(String)
    case apply(HWKTextMutation)
}

final class HWKSoftwareInputPipeline {
    private let kernel: HWKKernel
    private var textEngine: HWKTextEngine
    private var deadKeysEnabled: Bool
    private var kernelEnabled: Bool

    var hasPendingPreedit: Bool {
        textEngine.hasPendingPreedit
    }

    init(
        kernel: HWKKernel = HWKKernel(),
        textEngine: HWKTextEngine = HWKTextEngine(),
        deadKeysEnabled: Bool = true,
        kernelEnabled: Bool = true
    ) {
        self.kernel = kernel
        self.textEngine = textEngine
        self.deadKeysEnabled = deadKeysEnabled
        self.kernelEnabled = kernelEnabled
    }

    func actions(for text: String) -> [HWKSoftwareInputAction] {
        guard !text.isEmpty else { return [] }

        if deadKeysEnabled, let deadKey = HWKDeadKey(inputToken: text) {
            let outcome = textEngine.handle(
                HWKInputEvent(
                    source: .softwareKey,
                    kind: .deadKey(deadKey),
                    characters: text
                )
            )
            return textActions(for: outcome)
        }

        if deadKeysEnabled, textEngine.hasPendingPreedit {
            let outcome = textEngine.handle(
                HWKInputEvent(
                    source: .softwareKey,
                    kind: .character(text),
                    characters: text
                )
            )
            return textActions(for: outcome)
        }

        guard kernelEnabled else { return [.protectedInsert(text)] }

        return actions(
            for: kernel.handle(
                HWKInputEvent(
                    source: .softwareKey,
                    kind: .character(text),
                    characters: text
                )
            )
        )
    }

    func actionsForBackspace() -> [HWKSoftwareInputAction] {
        let outcome: HWKInputOutcome
        if deadKeysEnabled, textEngine.hasPendingPreedit {
            outcome = textEngine.handle(HWKInputEvent(source: .softwareKey, kind: .deleteBackward))
        } else if kernelEnabled {
            outcome = kernel.handle(HWKInputEvent(source: .softwareKey, kind: .deleteBackward))
        } else {
            return [.apply(.deleteBackward(count: 1))]
        }
        return textActions(for: outcome)
    }

    func actionsForDeleteForward() -> [HWKSoftwareInputAction] {
        guard kernelEnabled else { return [.apply(.deleteForward(count: 1))] }

        return textActions(
            for: kernel.handle(HWKInputEvent(source: .softwareKey, kind: .deleteForward))
        )
    }

    func outcome(for event: HWKInputEvent) -> HWKInputOutcome {
        if deadKeysEnabled {
            switch event.kind {
            case .deadKey:
                return textEngine.handle(event)
            case .character where textEngine.hasPendingPreedit:
                return textEngine.handle(event)
            case .deleteBackward where textEngine.hasPendingPreedit:
                return textEngine.handle(event)
            default:
                break
            }
        }
        guard kernelEnabled else { return .ignored }
        return kernel.handle(event)
    }

    func setKernelEnabled(_ isEnabled: Bool) {
        kernelEnabled = isEnabled
    }

    func setDeadKeysEnabled(_ isEnabled: Bool) {
        let becameDisabled = deadKeysEnabled && !isEnabled
        deadKeysEnabled = isEnabled
        if becameDisabled {
            textEngine = HWKTextEngine()
        }
    }

    func resetCompositionState() {
        textEngine = HWKTextEngine()
    }

    func actions(for outcome: HWKInputOutcome) -> [HWKSoftwareInputAction] {
        guard outcome.consumed else { return [] }

        if outcome.textMutations.count == 1,
           case .insert(let text) = outcome.textMutations[0] {
            return actionsForKernelInsert(text)
        }

        return outcome.textMutations.map { mutation in
            switch mutation {
            case .insert(let text):
                return .protectedInsert(text)
            case .deleteBackward, .deleteForward, .moveCursor, .setMarkedText, .unmarkText:
                return .apply(mutation)
            }
        }
    }

    private func actionsForKernelInsert(_ text: String) -> [HWKSoftwareInputAction] {
        if deadKeysEnabled, let deadKey = HWKDeadKey(inputToken: text) {
            let outcome = textEngine.handle(
                HWKInputEvent(
                    source: .softwareKey,
                    kind: .deadKey(deadKey),
                    characters: text
                )
            )
            return textActions(for: outcome)
        }

        if deadKeysEnabled, textEngine.hasPendingPreedit {
            let outcome = textEngine.handle(
                HWKInputEvent(
                    source: .softwareKey,
                    kind: .character(text),
                    characters: text
                )
            )
            return textActions(for: outcome)
        }

        return [.protectedInsert(text)]
    }

    private func textActions(for outcome: HWKInputOutcome) -> [HWKSoftwareInputAction] {
        guard outcome.consumed else { return [] }
        return outcome.textMutations.map { .apply($0) }
    }
}

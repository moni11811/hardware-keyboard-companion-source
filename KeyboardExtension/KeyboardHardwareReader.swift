import UIKit
import os
import GameController

#if HWC_HARDWARE_CAPTURE || HWC_HARDWARE_CAPTURE
protocol KeyboardHardwareReader: AnyObject {
    var isFirstResponder: Bool { get }
    var isGameControllerKeyboardPresent: Bool { get }
    var onPressesBegan: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)? { get set }
    var onPressesChanged: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)? { get set }
    var onPressesEnded: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)? { get set }
    var onPressesCancelled: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)? { get set }
    var onGameControllerKeyChanged: ((GCKeyCode, Bool, HWKModifierSource) -> Void)? { get set }
    var onGameControllerDisconnected: (() -> Void)? { get set }
    var onGameControllerSelectorKeyEdge: ((GCKeyCode, Bool) -> Void)? { get set }
    var keyCommandsProvider: (() -> [UIKeyCommand]?)? { get set }
    var didReceiveAnyPress: Bool { get }

    func setSelectorKeyPolling(_ enabled: Bool)
    func install(in hostView: UIView)
    func currentHardwareModifierSnapshot() -> UIKeyModifierFlags?
    func scheduleStateUpdate(
        delay: TimeInterval,
        shouldArm: @escaping () -> Bool,
        didUpdateState: @escaping () -> Void
    )
    func cancelPendingUpdate()
    func resign()
    func shutdown()
}

final class RelayKeyboardHardwareReader: KeyboardHardwareReader {
    var onPressesBegan: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var onPressesChanged: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var onPressesEnded: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var onPressesCancelled: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var onGameControllerKeyChanged: ((GCKeyCode, Bool, HWKModifierSource) -> Void)?
    var onGameControllerDisconnected: (() -> Void)?
    var onGameControllerSelectorKeyEdge: ((GCKeyCode, Bool) -> Void)?
    var keyCommandsProvider: (() -> [UIKeyCommand]?)?

    var didReceiveAnyPress: Bool {
        didReceivePress
    }

    func setSelectorKeyPolling(_ enabled: Bool) {
        gameControllerProbe.pollsSelectorKeys = enabled
    }

    private weak var hostView: UIView?
    private var responderView: RelayResponderView?
    private var pendingStateUpdate: DispatchWorkItem?
    private let gameControllerProbe = HardwareKeyboardGameControllerProbe()
    #if HWC_INTERNAL_BUILD
    private let hardwareDiagnosticPersistenceCoordinator =
        LiveHardwareDiagnosticPersistenceCoordinator.shared
    #endif
    private var didReceivePress = false

    var isFirstResponder: Bool {
        responderView?.isFirstResponder == true
    }

    var isGameControllerKeyboardPresent: Bool {
        gameControllerProbe.isKeyboardPresent
    }

    func install(in hostView: UIView) {
        guard responderView == nil else { return }

        let responderView = RelayResponderView(frame: .zero)
        responderView.translatesAutoresizingMaskIntoConstraints = false
        responderView.backgroundColor = .clear
        responderView.alpha = 0.01
        responderView.isAccessibilityElement = false
        responderView.isUserInteractionEnabled = false
        responderView.pressesBeganHandler = { [weak self] presses, event in
            self?.recordPressArrival(presses)
            return self?.onPressesBegan?(presses, event) ?? presses
        }
        responderView.pressesChangedHandler = { [weak self] presses, event in
            self?.recordPressArrival(presses)
            return self?.onPressesChanged?(presses, event) ?? presses
        }
        responderView.pressesEndedHandler = { [weak self] presses, event in
            self?.recordPressArrival(presses)
            return self?.onPressesEnded?(presses, event) ?? presses
        }
        responderView.pressesCancelledHandler = { [weak self] presses, event in
            self?.recordPressArrival(presses)
            return self?.onPressesCancelled?(presses, event) ?? presses
        }
        responderView.keyCommandsHandler = { [weak self] in
            self?.keyCommandsProvider?()
        }

        hostView.addSubview(responderView)
        NSLayoutConstraint.activate([
            responderView.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            responderView.topAnchor.constraint(equalTo: hostView.topAnchor),
            responderView.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            responderView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])

        self.hostView = hostView
        self.responderView = responderView
        gameControllerProbe.onKeyChanged = { [weak self] keyCode, pressed, source in
            self?.onGameControllerKeyChanged?(keyCode, pressed, source)
        }
        gameControllerProbe.onDisconnect = { [weak self] in
            self?.onGameControllerDisconnected?()
        }
        gameControllerProbe.onSelectorKeyEdge = { [weak self] keyCode, pressed in
            self?.onGameControllerSelectorKeyEdge?(keyCode, pressed)
        }
        gameControllerProbe.start()
    }

    func currentHardwareModifierSnapshot() -> UIKeyModifierFlags? {
        let snapshot = gameControllerProbe.currentModifierSnapshot()
        #if HWC_INTERNAL_BUILD
        recordRelayResponderLiveness(
            becomeFirstResponderResult: isFirstResponder,
            polledModifierSnapshot: gameControllerProbe.polledModifierSnapshot()
        )
        #endif
        return snapshot
    }

    func scheduleStateUpdate(
        delay: TimeInterval = 0.18,
        shouldArm: @escaping () -> Bool,
        didUpdateState: @escaping () -> Void
    ) {
        cancelPendingUpdate()
        gameControllerProbe.refresh()

        guard shouldArm() else {
            updateResponderState(shouldArm: shouldArm, didUpdateState: didUpdateState)
            return
        }

        updateResponderState(shouldArm: shouldArm, didUpdateState: didUpdateState)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStateUpdate = nil
            guard !self.isFirstResponder else { return }
            self.updateResponderState(shouldArm: shouldArm, didUpdateState: didUpdateState)
        }

        pendingStateUpdate = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingUpdate() {
        pendingStateUpdate?.cancel()
        pendingStateUpdate = nil
    }

    func resign() {
        responderView?.resignFirstResponder()
    }

    func shutdown() {
        cancelPendingUpdate()
        gameControllerProbe.stop()
        onGameControllerDisconnected = nil
        resign()
        responderView?.removeFromSuperview()
        responderView = nil
        hostView = nil
    }

    private func recordPressArrival(_ presses: Set<UIPress>) {
        guard !presses.isEmpty else { return }
        didReceivePress = true
    }

    private func updateResponderState(
        shouldArm: @escaping () -> Bool,
        didUpdateState: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let hostView = self.hostView,
                  let responderView = self.responderView else {
                return
            }

            guard shouldArm(),
                  hostView.window != nil,
                  responderView.window != nil else {
                if responderView.isFirstResponder {
                    responderView.resignFirstResponder()
                    #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
                    KeyDiagStore.incrementReliabilityCounter(.firstResponderLoss)
                    HWKTelemetry.recordHardwareReliabilityCounter(.firstResponderLoss, total: KeyDiagStore.getCounters().value(for: .firstResponderLoss))
                    #endif
                    #if HWC_INTERNAL_BUILD
                    HardwareReaderLog.debug("first responder lost")
                    #endif
                }
                #if HWC_INTERNAL_BUILD
                self.recordRelayResponderLiveness(
                    becomeFirstResponderResult: false,
                    polledModifierSnapshot: gameControllerProbe.polledModifierSnapshot()
                )
                #endif
                didUpdateState()
                return
            }

            let becomeFirstResponderResult: Bool
            if !responderView.isFirstResponder {
                becomeFirstResponderResult = responderView.becomeFirstResponder()
            } else {
                becomeFirstResponderResult = true
            }

            var focusSystemAvailable = false
            if #available(iOS 15.0, *) {
                if let focusSystem = UIFocusSystem.focusSystem(for: responderView) {
                    focusSystemAvailable = true
                    focusSystem.requestFocusUpdate(to: responderView)
                }
            }

            #if HWC_INTERNAL_BUILD
            self.recordRelayResponderLiveness(
                becomeFirstResponderResult: becomeFirstResponderResult,
                polledModifierSnapshot: gameControllerProbe.polledModifierSnapshot(),
                hostViewSize: hostView.bounds.size,
                canBecomeFocused: responderView.canBecomeFocused,
                focusSystemAvailable: focusSystemAvailable
            )
            HardwareReaderLog.debug("responder refresh firstResponder=\(responderView.isFirstResponder)")
            #endif
            didUpdateState()
        }
    }

    #if HWC_INTERNAL_BUILD
    private func recordRelayResponderLiveness(
        becomeFirstResponderResult: Bool,
        polledModifierSnapshot: RelayResponderPolledModifierSnapshot,
        hostViewSize: CGSize = .zero,
        canBecomeFocused: Bool = false,
        focusSystemAvailable: Bool = false
    ) {
        hardwareDiagnosticPersistenceCoordinator.recordRelayResponderLiveness(
            RelayResponderLivenessRecord(
                becomeFirstResponderResult: becomeFirstResponderResult,
                isFirstResponder: responderView?.isFirstResponder == true,
                didReceivePress: didReceivePress,
                isGameControllerKeyboardPresent: gameControllerProbe.isKeyboardPresent,
                polledModifierSnapshot: polledModifierSnapshot,
                hostViewWidth: Double(hostViewSize.width),
                hostViewHeight: Double(hostViewSize.height),
                canBecomeFocused: canBecomeFocused,
                focusSystemAvailable: focusSystemAvailable
            )
        )
    }
    #endif
}

final class RelayResponderView: UIView {
    var pressesBeganHandler: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var pressesChangedHandler: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var pressesEndedHandler: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var pressesCancelledHandler: ((Set<UIPress>, UIPressesEvent?) -> Set<UIPress>)?
    var keyCommandsHandler: (() -> [UIKeyCommand]?)?

    override var canBecomeFirstResponder: Bool {
        window != nil
    }

    override var canBecomeFocused: Bool {
        window != nil
    }

    override var keyCommands: [UIKeyCommand]? {
        keyCommandsHandler?()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = pressesBeganHandler?(presses, event) ?? presses
        guard !unhandledPresses.isEmpty else { return }
        super.pressesBegan(unhandledPresses, with: event)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = pressesChangedHandler?(presses, event) ?? presses
        guard !unhandledPresses.isEmpty else { return }
        super.pressesChanged(unhandledPresses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = pressesEndedHandler?(presses, event) ?? presses
        guard !unhandledPresses.isEmpty else { return }
        super.pressesEnded(unhandledPresses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = pressesCancelledHandler?(presses, event) ?? presses
        guard !unhandledPresses.isEmpty else { return }
        super.pressesCancelled(unhandledPresses, with: event)
    }
}

final class HardwareKeyboardGameControllerProbe {
    private var keyboardInput: GCKeyboardInput?
    private var connectObserver: NSObjectProtocol?
    private var disconnectObserver: NSObjectProtocol?
    private var sceneLifecycleObservers = [NSObjectProtocol]()
    private var retryTimer: Timer?
    private var modifierSnapshotTimer: Timer?
    private let captureQueue = DispatchQueue(
        label: "dev.moni11811.hwkbcompanion.game-controller-capture",
        qos: .userInteractive
    )
    private let attachmentGenerationLock = NSLock()
    private var attachmentGeneration: UInt64 = 0
    private let modifierSnapshotPollInterval: TimeInterval = 0.05
    private static let polledSelectorKeyCodes: [GCKeyCode] = [
        .upArrow, .downArrow, .leftArrow, .rightArrow,
        .returnOrEnter, .keypadEnter, .spacebar, .escape,
    ]
    private var polledSelectorPressedKeys = Set<Int>()
    private var liveStateCanReleaseMissingKeys = false

    private struct KnownKeySample {
        let anyKeyPressed: Bool
        let sourceTimestamp: TimeInterval
        let pressedModifierKeys: [GCKeyCode]
        let pressedSelectorKeys: Set<Int>

        var knownPressedCount: Int {
            pressedModifierKeys.count + pressedSelectorKeys.count
        }
    }
    var pollsSelectorKeys = false
    var onSelectorKeyEdge: ((GCKeyCode, Bool) -> Void)?
    private let modifierState = HardwareGameControllerModifierState()
    private var isStarted = false
    #if HWC_INTERNAL_BUILD
    private var lastReportedGameControllerAvailability: Bool?
    #endif
    var onKeyChanged: ((GCKeyCode, Bool, HWKModifierSource) -> Void)?
    var onDisconnect: (() -> Void)?

    var isKeyboardPresent: Bool {
        keyboardInput != nil || GCKeyboard.coalesced?.keyboardInput != nil
    }

    #if HWC_INTERNAL_BUILD
    func polledModifierSnapshot() -> RelayResponderPolledModifierSnapshot {
        guard let liveInput = keyboardInput ?? GCKeyboard.coalesced?.keyboardInput else {
            return .empty
        }
        let input = liveInput

        var names = [String]()
        var codes = [Int]()
        func append(name: String, keyCode: GCKeyCode) {
            names.append(name)
            codes.append(Int(keyCode.rawValue))
        }

        if input.button(forKeyCode: .leftShift)?.isPressed == true {
            append(name: "leftShift", keyCode: .leftShift)
        }
        if input.button(forKeyCode: .rightShift)?.isPressed == true {
            append(name: "rightShift", keyCode: .rightShift)
        }
        if input.button(forKeyCode: .capsLock)?.isPressed == true {
            append(name: "capsLock", keyCode: .capsLock)
        }
        if input.button(forKeyCode: .leftAlt)?.isPressed == true {
            append(name: "leftAlt", keyCode: .leftAlt)
        }
        if input.button(forKeyCode: .leftControl)?.isPressed == true {
            append(name: "leftControl", keyCode: .leftControl)
        }
        if input.button(forKeyCode: .leftGUI)?.isPressed == true {
            append(name: "leftGUI", keyCode: .leftGUI)
        }

        return RelayResponderPolledModifierSnapshot(
            keyNames: names,
            keyCodes: codes
        )
    }
    #endif

    func start() {
        guard !isStarted else {
            refresh()
            return
        }

        isStarted = true
        registerKeyboardNotifications()
        registerSceneServiceLifecycleNotifications()
        refresh()
        scheduleRetryIfNeeded()
    }

    func refresh() {
        guard let input = GCKeyboard.coalesced?.keyboardInput else {
            detachKeyboardInput(publishReleasedModifiers: true, notifyDisconnect: true)
            #if HWC_INTERNAL_BUILD
            recordGameControllerAvailabilityDiagnostic(isAttached: false)
            #endif
            scheduleRetryIfNeeded()
            #if HWC_INTERNAL_BUILD
            HardwareReaderLog.debug("gc keyboard unavailable")
            #endif
            return
        }

        let isNewInput = input !== keyboardInput
        let generation: UInt64
        if isNewInput {
            detachKeyboardInput(publishReleasedModifiers: true, notifyDisconnect: true)
            input.device?.handlerQueue = captureQueue
            keyboardInput = input
            generation = advanceAttachmentGeneration()
        } else if keyboardInput == nil {
            keyboardInput = input
            generation = advanceAttachmentGeneration()
        } else {
            generation = currentAttachmentGeneration()
        }

        installValueDidChangeHandler(on: input, generation: generation)
        installKeyChangedHandler(on: input, generation: generation)
        publishCachedModifierState(wake: .attach)
        startModifierSnapshotPollingIfNeeded()
        #if HWC_INTERNAL_BUILD
        recordGameControllerAvailabilityDiagnostic(isAttached: true)
        #endif

        guard isNewInput else {
            return
        }

        retryTimer?.invalidate()
        retryTimer = nil
        #if HWC_INTERNAL_BUILD
        HardwareReaderLog.debug("gc keyboard attached")
        #endif
    }

    func stop() {
        isStarted = false
        retryTimer?.invalidate()
        retryTimer = nil
        stopModifierSnapshotPolling()
        #if HWC_INTERNAL_BUILD
        lastReportedGameControllerAvailability = nil
        #endif
        unregisterSceneServiceLifecycleNotifications()
        unregisterKeyboardNotifications()
        detachKeyboardInput(publishReleasedModifiers: false)
        onKeyChanged = nil
        onDisconnect = nil
    }

    private func registerKeyboardNotifications() {
        guard connectObserver == nil, disconnectObserver == nil else { return }

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            #if HWC_INTERNAL_BUILD
            HardwareReaderLog.debug("gc keyboard connect")
            #endif
            self?.refresh()
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            #if HWC_INTERNAL_BUILD
            HardwareReaderLog.debug("gc keyboard disconnect")
            #endif
            self?.detachKeyboardInput(publishReleasedModifiers: true, notifyDisconnect: true)
            self?.scheduleRetryIfNeeded()
        }
    }

    private func unregisterKeyboardNotifications() {
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
        }
        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
        }
        connectObserver = nil
        disconnectObserver = nil
    }

    private func registerSceneServiceLifecycleNotifications() {
        guard sceneLifecycleObservers.isEmpty else { return }

        let sceneRefreshNotifications: [Notification.Name] = [
            UIScene.didActivateNotification,
            UIScene.willEnterForegroundNotification,
        ]

        sceneLifecycleObservers = sceneRefreshNotifications.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, self.isStarted else { return }
                #if HWC_INTERNAL_BUILD
                HardwareReaderLog.debug("gc scene-service lifecycle refresh")
                #endif
                self.refresh()
            }
        }
    }

    private func unregisterSceneServiceLifecycleNotifications() {
        sceneLifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        sceneLifecycleObservers.removeAll()
    }

    private func scheduleRetryIfNeeded() {
        guard isStarted, keyboardInput == nil, retryTimer == nil else { return }

        retryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func startModifierSnapshotPollingIfNeeded() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startModifierSnapshotPollingIfNeeded()
            }
            return
        }

        guard isStarted, keyboardInput != nil, modifierSnapshotTimer == nil else { return }
        modifierSnapshotTimer = Timer.scheduledTimer(withTimeInterval: modifierSnapshotPollInterval, repeats: true) { [weak self] _ in
            self?.publishCachedModifierState()
        }
        modifierSnapshotTimer?.tolerance = modifierSnapshotPollInterval / 2
    }

    private func stopModifierSnapshotPolling() {
        modifierSnapshotTimer?.invalidate()
        modifierSnapshotTimer = nil
    }

    private func detachKeyboardInput(
        publishReleasedModifiers: Bool,
        notifyDisconnect: Bool = false
    ) {
        let hadKeyboardInput = keyboardInput != nil
        _ = advanceAttachmentGeneration()
        keyboardInput?.keyChangedHandler = nil
        keyboardInput?.valueDidChangeHandler = nil
        keyboardInput = nil
        stopModifierSnapshotPolling()
        polledSelectorPressedKeys = []
        liveStateCanReleaseMissingKeys = false
        let releasedKeys = modifierState.detach()
        if publishReleasedModifiers {
            publishModifierEvents(
                releasedKeys.map { ($0, false) },
                modifierSource: .gameControllerSnapshot
            )
        }
        if notifyDisconnect, hadKeyboardInput {
            publishDisconnect()
        }
    }

    private func pollSelectorKeyEdgesIfNeeded(
        pressedKeys: Set<Int>,
        anyKeyPressed: Bool,
        allowsMissingKeyReleases: Bool
    ) -> (edgeCount: Int, pressedCount: Int) {
        guard pollsSelectorKeys else { return (0, 0) }
        let keyCodesByRawValue = Dictionary(
            uniqueKeysWithValues: Self.polledSelectorKeyCodes.map { (Int($0.rawValue), $0) }
        )
        let reconciliation = HWKKnownKeySnapshotReconciler.reconcile(
            trackedKeys: Self.polledSelectorKeyCodes.map { Int($0.rawValue) },
            previouslyPressed: polledSelectorPressedKeys,
            snapshotPressed: pressedKeys,
            isAnyKeyPressed: anyKeyPressed,
            allowsMissingKeyReleases: allowsMissingKeyReleases
        )
        polledSelectorPressedKeys = reconciliation.pressedKeys

        for edge in reconciliation.edges {
            guard let keyCode = keyCodesByRawValue[edge.key] else { continue }
            #if HWC_INTERNAL_BUILD
            if edge.isPressed {
                recordGameControllerKeyDiagnostic(keyCode: keyCode, pressed: true)
            }
            #endif
            onSelectorKeyEdge?(keyCode, edge.isPressed)
        }
        return (reconciliation.edges.count, reconciliation.pressedKeys.count)
    }

    private func currentPressedModifierKeys(
        from input: GCKeyboardInput,
        anyKeyPressed: Bool? = nil
    ) -> [GCKeyCode] {
        guard anyKeyPressed ?? input.isAnyKeyPressed else { return [] }
        return HardwareGameControllerModifierKey.all.compactMap { modifierKey -> GCKeyCode? in
            input.button(forKeyCode: modifierKey.keyCode)?.isPressed == true ? modifierKey.keyCode : nil
        }
    }

    private func knownKeySample(from input: GCKeyboardInput) -> KnownKeySample {
        let anyKeyPressed = input.isAnyKeyPressed
        let pressedSelectorKeys = Set(
            Self.polledSelectorKeyCodes.compactMap { keyCode -> Int? in
                input.button(forKeyCode: keyCode)?.isPressed == true
                    ? Int(keyCode.rawValue)
                    : nil
            }
        )
        return KnownKeySample(
            anyKeyPressed: anyKeyPressed,
            sourceTimestamp: input.lastEventTimestamp,
            pressedModifierKeys: currentPressedModifierKeys(
                from: input,
                anyKeyPressed: anyKeyPressed
            ),
            pressedSelectorKeys: pressedSelectorKeys
        )
    }

    private func publishCurrentModifierState(from input: GCKeyboardInput) {
        let anyKeyPressed = input.isAnyKeyPressed
        let pressedModifierKeys = currentPressedModifierKeys(
            from: input,
            anyKeyPressed: anyKeyPressed
        )
        if !pressedModifierKeys.isEmpty {
            liveStateCanReleaseMissingKeys = true
        }
        publishModifierEvents(
            modifierState.replacePressedKeys(
                pressedModifierKeys,
                anyKeyPressed: anyKeyPressed,
                allowsMissingKeyReleases: liveStateCanReleaseMissingKeys
            ),
            modifierSource: .gameControllerSnapshot
        )
    }

    private func publishCachedModifierState() {
        publishCachedModifierState(wake: .poll)
    }

    private func publishCachedModifierState(wake: HWKGameControllerSnapshotWake) {
        guard let input = keyboardInput else { return }
        let generation = currentAttachmentGeneration()
        captureQueue.async { [weak self, weak input] in
            guard let self, let input else { return }
            self.captureAndPublish(input, generation: generation, wake: wake)
        }
    }

    private func refreshCurrentModifierStateFromCachedInput() -> [(GCKeyCode, Bool)] {
        guard let keyboardInput else { return [] }
        let snapshot = keyboardInput.capture()
        let anyKeyPressed = snapshot.isAnyKeyPressed
        let pressedModifierKeys = currentPressedModifierKeys(
            from: snapshot,
            anyKeyPressed: anyKeyPressed
        )
        if !pressedModifierKeys.isEmpty {
            liveStateCanReleaseMissingKeys = true
        }
        return modifierState.replacePressedKeys(
            pressedModifierKeys,
            anyKeyPressed: anyKeyPressed,
            allowsMissingKeyReleases: liveStateCanReleaseMissingKeys
        )
    }

    func currentModifierSnapshot() -> UIKeyModifierFlags? {
        publishModifierEvents(
            refreshCurrentModifierStateFromCachedInput(),
            modifierSource: .gameControllerSnapshot
        )
        return modifierState.snapshot()
    }

    private func installValueDidChangeHandler(on input: GCKeyboardInput, generation: UInt64) {
        input.valueDidChangeHandler = { [weak self, weak input] _, _ in
            guard let self, let input else { return }
            self.captureAndPublish(input, generation: generation, wake: .valueChanged)
        }
    }

    private func installKeyChangedHandler(on input: GCKeyboardInput, generation: UInt64) {
        input.keyChangedHandler = { [weak self] input, _, keyCode, pressed in
            self?.captureAndPublish(
                input,
                generation: generation,
                wake: .keyChanged,
                keyChange: (keyCode, pressed)
            )
        }
    }

    private func captureAndPublish(
        _ input: GCKeyboardInput,
        generation: UInt64,
        wake: HWKGameControllerSnapshotWake,
        keyChange: (GCKeyCode, Bool)? = nil
    ) {
        let liveSample = knownKeySample(from: input)
        let snapshot = input.capture()
        let capturedSample = knownKeySample(from: snapshot)
        guard isCurrentAttachment(generation) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrentAttachment(generation) else { return }
            self.applyKnownKeySamples(
                live: liveSample,
                captured: capturedSample,
                wake: wake
            )
            if let keyChange {
                self.handleKeyChanged(
                    keyCode: keyChange.0,
                    pressed: keyChange.1,
                    modifierSource: .gameControllerDelta
                )
            }
        }
    }

    private func applyKnownKeySamples(
        live: KnownKeySample,
        captured: KnownKeySample,
        wake: HWKGameControllerSnapshotWake
    ) {
        if live.knownPressedCount > 0 {
            liveStateCanReleaseMissingKeys = true
        }
        let modifierEvents = modifierState.replacePressedKeys(
            live.pressedModifierKeys,
            anyKeyPressed: live.anyKeyPressed,
            allowsMissingKeyReleases: liveStateCanReleaseMissingKeys
        )
        publishModifierEvents(
            modifierEvents,
            modifierSource: .gameControllerSnapshot
        )
        let selectorResult = pollSelectorKeyEdgesIfNeeded(
            pressedKeys: live.pressedSelectorKeys,
            anyKeyPressed: live.anyKeyPressed,
            allowsMissingKeyReleases: liveStateCanReleaseMissingKeys
        )
        #if HWC_INTERNAL_BUILD
        HWKGameControllerSnapshotProbeStore.record(
            wake: wake,
            sourceTimestamp: captured.sourceTimestamp,
            isAnyKeyPressed: captured.anyKeyPressed,
            knownPressedCount: captured.knownPressedCount,
            liveSourceTimestamp: live.sourceTimestamp,
            liveIsAnyKeyPressed: live.anyKeyPressed,
            liveKnownPressedCount: live.knownPressedCount,
            edgeCount: modifierEvents.count + selectorResult.edgeCount
        )
        HardwareReaderLog.debug(
            "gc state wake=\(wake.rawValue) liveAny=\(live.anyKeyPressed) capturedAny=\(captured.anyKeyPressed) liveTimestamp=\(live.sourceTimestamp) capturedTimestamp=\(captured.sourceTimestamp)"
        )
        #endif
    }

    private func advanceAttachmentGeneration() -> UInt64 {
        attachmentGenerationLock.lock()
        defer { attachmentGenerationLock.unlock() }
        attachmentGeneration &+= 1
        return attachmentGeneration
    }

    private func currentAttachmentGeneration() -> UInt64 {
        attachmentGenerationLock.lock()
        defer { attachmentGenerationLock.unlock() }
        return attachmentGeneration
    }

    private func isCurrentAttachment(_ generation: UInt64) -> Bool {
        currentAttachmentGeneration() == generation
    }

    private func handleKeyChanged(
        keyCode: GCKeyCode,
        pressed: Bool,
        modifierSource: HWKModifierSource
    ) {
        if HardwareGameControllerModifierKey.isTracked(keyCode) {
            guard modifierState.setPressed(pressed, for: keyCode) else {
                return
            }
        }

        publishKeyChanged(keyCode: keyCode, pressed: pressed, modifierSource: modifierSource)
        #if HWC_INTERNAL_BUILD
        recordGameControllerKeyDiagnostic(keyCode: keyCode, pressed: pressed)
        HardwareReaderLog.debug("gc key key=\(String(describing: keyCode)) pressed=\(pressed) source=\(modifierSource.rawValue)")
        #endif
    }

    #if HWC_INTERNAL_BUILD
    private func recordGameControllerAvailabilityDiagnostic(isAttached: Bool) {
        guard lastReportedGameControllerAvailability != isAttached else { return }
        lastReportedGameControllerAvailability = isAttached
        KeyDiagStore.append(
            component: .keyboard,
            code: isAttached ? .gameControllerAttached : .gameControllerUnavailable,
            flags: isAttached ? 1 : 0
        )
    }

    private func recordGameControllerKeyDiagnostic(keyCode: GCKeyCode, pressed: Bool) {
        KeyDiagStore.append(
            component: .keyboard,
            code: .gameControllerKeyChanged,
            flags: pressed ? 1 : 0,
            keyCode: Int(keyCode.rawValue)
        )
    }
    #endif

    private func publishModifierEvents(
        _ events: [(GCKeyCode, Bool)],
        modifierSource: HWKModifierSource
    ) {
        for event in events {
            publishKeyChanged(
                keyCode: event.0,
                pressed: event.1,
                modifierSource: modifierSource
            )
        }
    }

    private func publishKeyChanged(
        keyCode: GCKeyCode,
        pressed: Bool,
        modifierSource: HWKModifierSource
    ) {
        if Thread.isMainThread {
            onKeyChanged?(keyCode, pressed, modifierSource)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onKeyChanged?(keyCode, pressed, modifierSource)
        }
    }

    private func publishDisconnect() {
        if Thread.isMainThread {
            onDisconnect?()
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }
}

private struct HardwareGameControllerModifierKey {
    let keyCode: GCKeyCode
    let flags: UIKeyModifierFlags

    static let all: [HardwareGameControllerModifierKey] = [
        .init(keyCode: .leftShift, flags: .shift),
        .init(keyCode: .rightShift, flags: .shift),
        .init(keyCode: .leftGUI, flags: .command),
        .init(keyCode: .rightGUI, flags: .command),
        .init(keyCode: .leftAlt, flags: .alternate),
        .init(keyCode: .rightAlt, flags: .alternate),
        .init(keyCode: .leftControl, flags: .control),
        .init(keyCode: .rightControl, flags: .control),
        .init(keyCode: .capsLock, flags: .alphaShift),
    ]

    static func isTracked(_ keyCode: GCKeyCode) -> Bool {
        all.contains { $0.keyCode == keyCode }
    }
}

private final class HardwareGameControllerModifierState {
    private var lock = os_unfair_lock_s()
    private var isAttached = false
    private var pressedRawKeyCodes = Set<Int>()
    private var cachedFlags: UIKeyModifierFlags = []

    func snapshot() -> UIKeyModifierFlags? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return isAttached ? cachedFlags : nil
    }

    @discardableResult
    func setPressed(_ isPressed: Bool, for keyCode: GCKeyCode) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        isAttached = true
        let rawKeyCode = Int(keyCode.rawValue)
        let changed: Bool
        if isPressed {
            changed = pressedRawKeyCodes.insert(rawKeyCode).inserted
        } else {
            changed = pressedRawKeyCodes.remove(rawKeyCode) != nil
        }
        rebuildCachedFlags()
        return changed
    }

    func replacePressedKeys(
        _ pressedKeys: [GCKeyCode],
        anyKeyPressed: Bool = true,
        allowsMissingKeyReleases: Bool = false
    ) -> [(GCKeyCode, Bool)] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let keyCodesByRawValue = Dictionary(
            uniqueKeysWithValues: HardwareGameControllerModifierKey.all.map {
                (Int($0.keyCode.rawValue), $0.keyCode)
            }
        )
        let reconciliation = HWKKnownKeySnapshotReconciler.reconcile(
            trackedKeys: HardwareGameControllerModifierKey.all.map { Int($0.keyCode.rawValue) },
            previouslyPressed: pressedRawKeyCodes,
            snapshotPressed: Set(pressedKeys.map { Int($0.rawValue) }),
            isAnyKeyPressed: anyKeyPressed,
            allowsMissingKeyReleases: allowsMissingKeyReleases
        )
        isAttached = true
        pressedRawKeyCodes = reconciliation.pressedKeys
        rebuildCachedFlags()

        return reconciliation.edges.compactMap { edge in
            guard let keyCode = keyCodesByRawValue[edge.key] else { return nil }
            return (keyCode, edge.isPressed)
        }
    }

    func detach() -> [GCKeyCode] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let releasedKeys = HardwareGameControllerModifierKey.all.compactMap { modifierKey -> GCKeyCode? in
            pressedRawKeyCodes.contains(Int(modifierKey.keyCode.rawValue)) ? modifierKey.keyCode : nil
        }
        isAttached = false
        pressedRawKeyCodes.removeAll(keepingCapacity: true)
        cachedFlags = []
        return releasedKeys
    }

    private func rebuildCachedFlags() {
        cachedFlags = []
        for modifierKey in HardwareGameControllerModifierKey.all
        where pressedRawKeyCodes.contains(Int(modifierKey.keyCode.rawValue)) {
            cachedFlags.formUnion(modifierKey.flags)
        }
    }
}

struct HardwareRecentEventCache {
    private let capacity: Int
    private let retentionInterval: TimeInterval
    private var datesBySignature = [String: Date]()
    private var orderedSignatures = [String]()

    init(capacity: Int = 64, retentionInterval: TimeInterval = 0.2) {
        self.capacity = capacity
        self.retentionInterval = retentionInterval
    }

    mutating func insert(_ signature: String, at date: Date = Date()) {
        prune(relativeTo: date)

        if datesBySignature[signature] == nil {
            orderedSignatures.append(signature)
        }
        datesBySignature[signature] = date
        trimToCapacity()
    }

    mutating func contains(_ signature: String, within interval: TimeInterval, at date: Date = Date()) -> Bool {
        prune(relativeTo: date)

        guard let previousDate = datesBySignature[signature] else {
            return false
        }

        return date.timeIntervalSince(previousDate) < interval
    }

    mutating func date(for signature: String, at date: Date = Date()) -> Date? {
        prune(relativeTo: date)
        return datesBySignature[signature]
    }

    mutating func remove(_ signature: String) {
        datesBySignature.removeValue(forKey: signature)
        orderedSignatures.removeAll { $0 == signature }
    }

    mutating func removeAll(where shouldRemove: (String) -> Bool) {
        guard !datesBySignature.isEmpty else { return }
        for signature in orderedSignatures where shouldRemove(signature) {
            datesBySignature.removeValue(forKey: signature)
        }
        orderedSignatures.removeAll(where: shouldRemove)
    }

    mutating func prune(relativeTo date: Date = Date()) {
        guard !datesBySignature.isEmpty else { return }

        var retainedSignatures = [String]()
        retainedSignatures.reserveCapacity(orderedSignatures.count)

        for signature in orderedSignatures {
            guard let previousDate = datesBySignature[signature] else {
                continue
            }

            if date.timeIntervalSince(previousDate) >= retentionInterval {
                datesBySignature.removeValue(forKey: signature)
                continue
            }

            retainedSignatures.append(signature)
        }

        orderedSignatures = retainedSignatures
    }

    mutating func removeAll() {
        datesBySignature.removeAll(keepingCapacity: true)
        orderedSignatures.removeAll(keepingCapacity: true)
    }

    private mutating func trimToCapacity() {
        while orderedSignatures.count > capacity, let oldest = orderedSignatures.first {
            orderedSignatures.removeFirst()
            datesBySignature.removeValue(forKey: oldest)
        }
    }
}

final class LockedHardwareModifierState {
    private var lock = os_unfair_lock_s()
    private var flags: UIKeyModifierFlags = []

    func load() -> UIKeyModifierFlags {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return flags
    }

    @discardableResult
    func replace(with nextFlags: UIKeyModifierFlags) -> UIKeyModifierFlags {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        let previousFlags = flags
        flags = nextFlags
        return previousFlags
    }

    @discardableResult
    func update(_ transform: (UIKeyModifierFlags) -> UIKeyModifierFlags) -> UIKeyModifierFlags {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        flags = transform(flags)
        return flags
    }

    func reset() {
        _ = replace(with: [])
    }
}

#if HWC_INTERNAL_BUILD
enum HardwareReaderLog {
    private static let logger = Logger(
        subsystem: "dev.moni11811.hwkbcompanion",
        category: "keyboard.hardware"
    )

    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}
#endif
#endif

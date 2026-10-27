import Combine
import Foundation
import UIKit

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
#if HWC_INTERNAL_BUILD && HWC_HARDWARE_CAPTURE

enum CaptureHealthStatus {
    case active
    case noFocus
    case keyboardNotActive
    case noEventsRecently
    case unknown

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .noFocus: return "No Focus"
        case .keyboardNotActive: return "Keyboard Not Active"
        case .noEventsRecently: return "No Events Recently"
        case .unknown: return "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .noFocus: return .orange
        case .keyboardNotActive: return .red
        case .noEventsRecently: return .yellow
        case .unknown: return .gray
        }
    }
}

import SwiftUI

/// Owns the Darwin callback context for the companion process lifetime.
/// Running monitors subscribe locally through weak tokens on main.
private final class KeyMonitorDarwinRelay: @unchecked Sendable {
    static let shared = KeyMonitorDarwinRelay()
    static let localNotification = Notification.Name(
        "dev.moni11811.hwc.hardware-ring-relay"
    )

    private init() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let relay = Unmanaged<KeyMonitorDarwinRelay>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                relay.deliver()
            },
            KeyEventRing.darwinNotification as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func deliver() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Self.localNotification,
                object: nil
            )
        }
    }
}

private final class KeyMonitorDarwinSubscriptionToken: @unchecked Sendable {
    weak var monitor: KeyMonitor?

    init(monitor: KeyMonitor) {
        self.monitor = monitor
    }
}

final class KeyMonitor: ObservableObject {
    private static let sessionRetentionInterval: TimeInterval = 3 * 60
    private static let retentionCheckInterval: TimeInterval = 30
    private static let staleEventThreshold: TimeInterval = 10.0

    @Published private(set) var events = [KeyEvent]()
    @Published private(set) var counters = HardwareEventCounters()
    @Published private(set) var healthStatus: CaptureHealthStatus = .unknown
    @Published private(set) var lastEventAge: TimeInterval?

    private var isRunning = false
    private var sharedRingObserverToken: NSObjectProtocol?
    private lazy var darwinSubscriptionToken =
        KeyMonitorDarwinSubscriptionToken(monitor: self)
    private var backgroundNotificationToken: NSObjectProtocol?
    private var shouldReplaceEventsOnNextDrain = false
    private var retentionTimer: Timer?
    private var healthCheckTimer: Timer?
    private let hardwareLabRecorder = HardwareLabHostVisibleRecorder(exportStore: HardwareLabExportStore())

    init() {
        backgroundNotificationToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleDidEnterBackground()
        }
        updateCounters()
    }

    deinit {
        stop()

        if let backgroundNotificationToken {
            NotificationCenter.default.removeObserver(backgroundNotificationToken)
        }
    }

    func start() {
        trimExpiredEvents()

        let settings = KeyboardSettingsSnapshot.load()

        if !settings.signalRelaySessionPersist {
            clear()
        } else if !events.isEmpty {
            shouldReplaceEventsOnNextDrain = true
        }

        if isRunning {
            drainSharedRing()
            return
        }

        isRunning = true
        startRetentionTimer()
        startHealthCheckTimer()
        registerForSharedRingNotifications()
        drainSharedRing()
    }

    func stop() {
        guard isRunning else { return }

        isRunning = false
        stopRetentionTimer()
        stopHealthCheckTimer()
        unregisterForSharedRingNotifications()
    }

    func clear() {
        shouldReplaceEventsOnNextDrain = false
        hardwareLabRecorder.clear()
        KeyEventRing.clear()

        updateEventsOnMain {
            self.events = []
        }
    }

    func discardEvents(from source: KeyEventSource) {
        updateEventsOnMain {
            self.events.removeAll { $0.source == source }
        }
    }

    func copySessionJSON() -> String? {
        guard KeySessionRelay.isEnabled else { return nil }
        let chronologicalEvents = retainedSessionEvents(from: events).sorted { $0.timestamp < $1.timestamp }
        return KeyEventRing.prettyPrintedJSON(for: chronologicalEvents)
    }

    func recordHardwareLabTextChange(
        event: KeyEvent,
        expectedTextDelta: String,
        previousText: String,
        currentText: String,
        sourceLane: String? = nil,
        observedAt: Date = Date()
    ) {
        guard KeySessionRelay.isEnabled else { return }

        hardwareLabRecorder.record(
            event: event,
            expectedTextDelta: expectedTextDelta,
            previousText: previousText,
            currentText: currentText,
            sourceLane: sourceLane,
            observedAt: observedAt
        )
    }

    func copyHardwareLabJSON(seed: Int? = nil) -> String? {
        guard KeySessionRelay.isEnabled else { return nil }
        return hardwareLabRecorder.persistLatestPayload(seed: seed)
    }

    func recordDebugEvent(_ event: KeyEvent) {
        guard KeySessionRelay.isEnabled else { return }
        guard isRunning else { return }

        DispatchQueue.main.async {
            self.appendEvents([event])
        }
    }

    private func handleDidEnterBackground() {
        guard !KeyboardSettingsSnapshot.load().signalRelaySessionPersist else { return }
        clear()
    }

    private func startHealthCheckTimer() {
        guard healthCheckTimer == nil else { return }

        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateHealthStatus()
        }
    }

    private func stopHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    private func updateCounters() {
        counters = KeyDiagStore.getCounters()
    }

    private func updateHealthStatus() {
        updateCounters()

        let settings = KeyboardSettingsSnapshot.load()

        if !settings.signalRelayEnabled {
            healthStatus = .keyboardNotActive
            lastEventAge = nil
            return
        }

        if let newestTimestamp = events.first?.timestamp {
            let age = Date().timeIntervalSince(newestTimestamp)
            lastEventAge = age

            if age < Self.staleEventThreshold {
                healthStatus = .active
            } else {
                healthStatus = .noEventsRecently
            }
        } else {
            healthStatus = .noFocus
            lastEventAge = nil
        }
    }

    private func startRetentionTimer() {
        guard retentionTimer == nil else { return }

        retentionTimer = Timer.scheduledTimer(withTimeInterval: Self.retentionCheckInterval, repeats: true) { [weak self] _ in
            self?.trimExpiredEvents()
        }
    }

    private func stopRetentionTimer() {
        retentionTimer?.invalidate()
        retentionTimer = nil
    }

    private func registerForSharedRingNotifications() {
        guard sharedRingObserverToken == nil else { return }

        let refreshToken = darwinSubscriptionToken
        sharedRingObserverToken = NotificationCenter.default.addObserver(
            forName: KeyMonitorDarwinRelay.localNotification,
            object: nil,
            queue: .main
        ) { _ in
            refreshToken.monitor?.drainSharedRing()
        }
        // Register the process-lifetime Darwin context only after this local
        // subscriber exists, so immediate delivery cannot miss the monitor.
        _ = KeyMonitorDarwinRelay.shared
    }

    private func unregisterForSharedRingNotifications() {
        guard let observer = sharedRingObserverToken else { return }

        NotificationCenter.default.removeObserver(
            observer,
            name: KeyMonitorDarwinRelay.localNotification,
            object: nil
        )
        sharedRingObserverToken = nil
    }

    private func drainSharedRing() {
        guard isRunning else { return }

        let drainedEvents = KeyEventRing.drain()
        guard !drainedEvents.isEmpty else { return }

        DispatchQueue.main.async {
            self.appendEvents(drainedEvents)
            self.updateHealthStatus()
        }
    }

    private func appendEvents(_ incomingEvents: [KeyEvent]) {
        guard !incomingEvents.isEmpty else { return }

        if shouldReplaceEventsOnNextDrain {
            events = []
            shouldReplaceEventsOnNextDrain = false
        }

        var mergedEvents = retainedSessionEvents(from: events + incomingEvents)
        mergedEvents.sort { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                if lhs.sequence != 0 && rhs.sequence != 0 {
                    return lhs.sequence > rhs.sequence
                }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.timestamp > rhs.timestamp
        }

        if mergedEvents.isEmpty {
            events = []
            KeyEventRing.clear()
            return
        }

        if mergedEvents.count > KeyEventRing.capacity {
            mergedEvents.removeSubrange(KeyEventRing.capacity...)
        }

        events = mergedEvents
    }

    private func trimExpiredEvents(referenceDate: Date = Date()) {
        updateEventsOnMain {
            let retainedEvents = self.retainedSessionEvents(from: self.events, referenceDate: referenceDate)
            guard retainedEvents.count != self.events.count else { return }

            self.events = retainedEvents
            self.shouldReplaceEventsOnNextDrain = retainedEvents.isEmpty ? false : self.shouldReplaceEventsOnNextDrain
            if retainedEvents.isEmpty {
                KeyEventRing.clear()
            }
        }
    }

    private func retainedSessionEvents(
        from sourceEvents: [KeyEvent],
        referenceDate: Date = Date()
    ) -> [KeyEvent] {
        sourceEvents.filter { referenceDate.timeIntervalSince($0.timestamp) < Self.sessionRetentionInterval }
    }

    private func updateEventsOnMain(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}
#else
final class KeyMonitor: ObservableObject {
    @Published private(set) var events = [KeyEvent]()

    func start() {}

    func stop() {}

    func clear() {
        events = []
    }

    func discardEvents(from source: KeyEventSource) {}

    func copySessionJSON() -> String? { nil }

    func recordHardwareLabTextChange(
        event: KeyEvent,
        expectedTextDelta: String,
        previousText: String,
        currentText: String,
        sourceLane: String? = nil,
        observedAt: Date = Date()
    ) {}

    func copyHardwareLabJSON(seed: Int? = nil) -> String? { nil }

    func recordDebugEvent(_ event: KeyEvent) {}
}
#endif
#endif

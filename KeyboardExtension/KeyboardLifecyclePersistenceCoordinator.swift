import Foundation

#if (HWC_INTERNAL_BUILD || DEBUG) && canImport(UIKit)
/// Bounded, serial diagnostic persistence. A slow preferences flush never queues
/// one disk write per key, and pending runtime samples retain their worst values.
final class KeyboardTracePersistenceCoordinator: @unchecked Sendable {
    static let live = KeyboardTracePersistenceCoordinator { entry in
        KeyboardSharedPreferences.recordKeyboardLaunchTrace(entry)
    }

    private let persist: @Sendable (KeyboardLaunchTraceEntry) -> Void
    private let queue = DispatchQueue(label: "dev.moni11811.hwc.keyboard-trace", qos: .utility)
    private let lock = NSLock()
    private let writes = DispatchGroup()
    private var pending = [KeyboardLaunchTraceEntry]()
    private var draining = false

    init(persist: @escaping @Sendable (KeyboardLaunchTraceEntry) -> Void) {
        self.persist = persist
    }

    func record(_ entry: KeyboardLaunchTraceEntry) {
        lock.lock()
        if let index = pending.firstIndex(where: {
               $0.phase == entry.phase && $0.processIdentifier == entry.processIdentifier
           }) {
            let previous = pending[index]
            var merged = entry
            if entry.phase == "runtimeSample" {
                merged.workDurationMS = max(previous.workDurationMS ?? 0, entry.workDurationMS ?? 0)
                merged.contextUTF8Count = max(previous.contextUTF8Count ?? 0, entry.contextUTF8Count ?? 0)
                merged.sampleCount = UInt32(min(UInt64(previous.sampleCount ?? 0) + UInt64(entry.sampleCount ?? 0), UInt64(UInt32.max)))
            }
            if entry.phase == "runtimeSample" || entry.phase == "memoryWarning",
               previous.physicalFootprintBytes != nil || entry.physicalFootprintBytes != nil {
                merged.physicalFootprintBytes = max(previous.physicalFootprintBytes ?? 0, entry.physicalFootprintBytes ?? 0)
            }
            // The replacement describes the newest event. Move it to the tail
            // so an intervening disappear/reappear boundary stays chronological.
            pending.remove(at: index)
            pending.append(merged)
        } else {
            pending.append(entry)
            if pending.count > 8 {
                let discard = pending.firstIndex { $0.phase == "runtimeSample" }
                    ?? pending.firstIndex { $0.phase != "memoryWarning" } ?? 0
                pending.remove(at: discard)
            }
        }
        let shouldSchedule = !draining
        if shouldSchedule {
            draining = true
            writes.enter()
        }
        lock.unlock()
        if shouldSchedule {
            queue.async { [self] in drain() }
        }
    }

    func waitUntilDrained(timeout: TimeInterval) -> Bool {
        writes.wait(timeout: .now() + timeout) == .success
    }

    private func drain() {
        defer { writes.leave() }
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                draining = false
                lock.unlock()
                return
            }
            let entry = pending.removeFirst()
            lock.unlock()
            persist(entry)
        }
    }
}
#endif

/// Storage boundary for keyboard visibility and Full Access liveness markers.
protocol KeyboardLifecyclePersisting: Sendable {
    func recordAccessState(isEnabled: Bool, at date: Date)
    func markSeen(at date: Date)
}

struct LiveKeyboardLifecyclePersistence: KeyboardLifecyclePersisting {
    func recordAccessState(isEnabled: Bool, at date: Date) {
        KeyboardSharedPreferences.recordKeyboardAccessState(
            isEnabled: isEnabled,
            at: date
        )
    }

    func markSeen(at date: Date) {
        KeyboardSharedPreferences.markKeyboardSeen(at: date)
    }
}

/// Keeps App Group lifecycle markers ordered and off UIKit lifecycle/typing calls.
///
/// Live instances share one serial executor because UIKit can briefly own more
/// than one keyboard controller. Timestamps are captured by the caller before
/// enqueueing; controller teardown never waits for persistence.
final class KeyboardLifecyclePersistenceCoordinator: @unchecked Sendable {
    private static let livePersistenceQueue = DispatchQueue(
        label: "dev.moni11811.hwc.keyboard-lifecycle-persistence",
        qos: .utility
    )

    private let persistence: any KeyboardLifecyclePersisting
    private let queue: DispatchQueue
    private let pendingWrites = DispatchGroup()

    init(
        persistence: any KeyboardLifecyclePersisting = LiveKeyboardLifecyclePersistence(),
        queue: DispatchQueue? = nil
    ) {
        self.persistence = persistence
        self.queue = queue ?? Self.livePersistenceQueue
    }

    func recordAccessState(isEnabled: Bool, at date: Date = Date()) {
        enqueue { [persistence] in
            persistence.recordAccessState(isEnabled: isEnabled, at: date)
        }
    }

    func markSeen(at date: Date = Date()) {
        enqueue { [persistence] in
            persistence.markSeen(at: date)
        }
    }

    @discardableResult
    func waitUntilDrained(timeout: TimeInterval) -> Bool {
        pendingWrites.wait(timeout: .now() + timeout) == .success
    }

    private func enqueue(_ write: @escaping @Sendable () -> Void) {
        pendingWrites.enter()
        queue.async { [pendingWrites] in
            defer { pendingWrites.leave() }
            write()
        }
    }
}

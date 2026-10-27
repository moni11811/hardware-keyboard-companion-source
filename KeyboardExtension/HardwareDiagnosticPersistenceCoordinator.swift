import Foundation

private enum HardwareDiagnosticPersistenceExecutor {
    static let liveQueue = DispatchQueue(
        label: "dev.moni11811.hwc.hardware-diagnostic-persistence",
        qos: .utility
    )
}

/// Keeps App Group diagnostic writes off keyboard callbacks and modifier polling.
///
/// These stores expose only the newest diagnostic snapshot. A single pending
/// value per store is therefore enough: input arriving during a slow flush
/// replaces stale pending work instead of growing an unbounded queue.
final class HardwareDiagnosticPersistenceCoordinator<
    RelayRecord: Sendable,
    ReconstructionRecord: Sendable
>: @unchecked Sendable {
    private let persistRelayResponderLiveness: @Sendable (RelayRecord) -> Void
    private let persistHardwareReconstructionBatch: @Sendable (ReconstructionRecord) -> Void
    private let queue: DispatchQueue
    private let pendingWrites = DispatchGroup()
    private let stateLock = NSLock()
    private var pendingRelayResponderLiveness: RelayRecord?
    private var pendingHardwareReconstructionBatch: ReconstructionRecord?
    private var drainScheduled = false

    init(
        persistRelayResponderLiveness: @escaping @Sendable (RelayRecord) -> Void,
        persistHardwareReconstructionBatch: @escaping @Sendable (ReconstructionRecord) -> Void,
        queue: DispatchQueue? = nil
    ) {
        self.persistRelayResponderLiveness = persistRelayResponderLiveness
        self.persistHardwareReconstructionBatch = persistHardwareReconstructionBatch
        self.queue = queue ?? HardwareDiagnosticPersistenceExecutor.liveQueue
    }

    func recordRelayResponderLiveness(_ record: RelayRecord) {
        var shouldScheduleDrain = false
        stateLock.lock()
        pendingRelayResponderLiveness = record
        if !drainScheduled {
            drainScheduled = true
            pendingWrites.enter()
            shouldScheduleDrain = true
        }
        stateLock.unlock()

        if shouldScheduleDrain {
            queue.async { [self] in
                drainPendingWrites()
            }
        }
    }

    func recordHardwareReconstructionBatch(_ record: ReconstructionRecord) {
        var shouldScheduleDrain = false
        stateLock.lock()
        pendingHardwareReconstructionBatch = record
        if !drainScheduled {
            drainScheduled = true
            pendingWrites.enter()
            shouldScheduleDrain = true
        }
        stateLock.unlock()

        if shouldScheduleDrain {
            queue.async { [self] in
                drainPendingWrites()
            }
        }
    }

    @discardableResult
    func waitUntilDrained(timeout: TimeInterval) -> Bool {
        pendingWrites.wait(timeout: .now() + timeout) == .success
    }

    private func drainPendingWrites() {
        defer { pendingWrites.leave() }

        while true {
            stateLock.lock()
            let relayResponderLiveness = pendingRelayResponderLiveness
            let hardwareReconstructionBatch = pendingHardwareReconstructionBatch
            pendingRelayResponderLiveness = nil
            pendingHardwareReconstructionBatch = nil

            guard relayResponderLiveness != nil || hardwareReconstructionBatch != nil else {
                drainScheduled = false
                stateLock.unlock()
                return
            }
            stateLock.unlock()

            if let relayResponderLiveness {
                persistRelayResponderLiveness(relayResponderLiveness)
            }
            if let hardwareReconstructionBatch {
                persistHardwareReconstructionBatch(hardwareReconstructionBatch)
            }
        }
    }
}

#if HWC_INTERNAL_BUILD
enum LiveHardwareDiagnosticPersistenceCoordinator {
    static let shared = HardwareDiagnosticPersistenceCoordinator<
        RelayResponderLivenessRecord,
        HardwareReconstructionBatchRecord
    >(
        persistRelayResponderLiveness: { record in
            RelayResponderLivenessStore.update(record)
        },
        persistHardwareReconstructionBatch: { record in
            HardwareReconstructionBatchStore.update(record)
        }
    )
}
#endif

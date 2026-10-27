import Foundation

/// Storage boundary for encoded motor-calibration snapshots.
protocol MotorCalibrationPersisting: Sendable {
    func persist(_ data: Data)
}

struct LiveMotorCalibrationPersistence: MotorCalibrationPersisting {
    func persist(_ data: Data) {
        HWKMotorCalibrationStore.persist(data)
    }
}

/// Keeps motor-calibration persistence ordered and off UIKit lifecycle calls.
///
/// Live instances share one serial executor because UIKit can briefly own more
/// than one keyboard controller. Submitted blocks retain their snapshot and
/// persistence dependency; controller teardown never needs to wait for them.
final class MotorCalibrationPersistenceCoordinator: @unchecked Sendable {
    private static let livePersistenceQueue = DispatchQueue(
        label: "dev.moni11811.hwc.motor-calibration-persistence",
        qos: .background
    )

    private let persistence: any MotorCalibrationPersisting
    private let queue: DispatchQueue
    private let pendingWrites = DispatchGroup()

    init(
        persistence: any MotorCalibrationPersisting = LiveMotorCalibrationPersistence(),
        queue: DispatchQueue? = nil
    ) {
        self.persistence = persistence
        self.queue = queue ?? Self.livePersistenceQueue
    }

    func enqueue(_ data: Data) {
        pendingWrites.enter()
        queue.async { [pendingWrites, persistence] in
            defer { pendingWrites.leave() }
            persistence.persist(data)
        }
    }

    @discardableResult
    func waitUntilDrained(timeout: TimeInterval) -> Bool {
        pendingWrites.wait(timeout: .now() + timeout) == .success
    }
}

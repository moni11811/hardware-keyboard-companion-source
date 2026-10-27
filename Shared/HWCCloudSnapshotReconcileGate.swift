import Foundation

enum HWCCloudSnapshotHistoryLoadState: Equatable {
    case idle, waiting, loading, loaded, failed

    var isPending: Bool { self == .waiting || self == .loading }
}

/// In-memory, payload-free timing state for backup UI diagnostics. It never
/// persists content, filenames, identifiers, or cloud metadata.
struct HWCCloudSnapshotOperationActivity: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case running
        case overdue
        case finished
        case failed
    }

    private(set) var phase: Phase = .idle
    private var startedAt: TimeInterval?
    private var finishedAt: TimeInterval?

    mutating func begin(at time: TimeInterval = Date().timeIntervalSince1970) {
        phase = .running
        startedAt = time
        finishedAt = nil
    }

    mutating func markOverdue(at time: TimeInterval = Date().timeIntervalSince1970) {
        guard startedAt != nil, finishedAt == nil else { return }
        _ = time
        phase = .overdue
    }

    mutating func finish(at time: TimeInterval = Date().timeIntervalSince1970) {
        guard startedAt != nil else { return }
        finishedAt = time
        phase = .finished
    }

    mutating func fail(at time: TimeInterval = Date().timeIntervalSince1970) {
        guard startedAt != nil else { return }
        finishedAt = time
        phase = .failed
    }

    func elapsed(at time: TimeInterval = Date().timeIntervalSince1970) -> TimeInterval {
        guard let startedAt else { return 0 }
        return max(0, (finishedAt ?? time) - startedAt)
    }

    var summary: String {
        let seconds = Int(elapsed().rounded())
        switch phase {
        case .idle:
            return "No operation recorded."
        case .running:
            return "Running for \(seconds) seconds."
        case .overdue:
            return "Running longer than expected: \(seconds) seconds."
        case .finished:
            return "Last operation finished in \(seconds) seconds."
        case .failed:
            return "Last attempt did not complete successfully (\(seconds) seconds)."
        }
    }
}

/// Owns the single active reconcile attempt and remembers one coalesced retry.
/// Every terminal service result, including a transport timeout, must finish the
/// gate before the controller applies its visible state.
struct HWCCloudSnapshotReconcileGate: Sendable {
    private(set) var isReconciling = false
    private var retryRequested = false

    mutating func request(isHistoryLoading: Bool = false) -> Bool {
        guard !isReconciling, !isHistoryLoading else {
            retryRequested = true
            return false
        }
        isReconciling = true
        return true
    }

    /// Coalesce backup requests made while the history reader owns the lane.
    mutating func resumeAfterHistory() -> Bool {
        guard !isReconciling, retryRequested else { return false }
        retryRequested = false
        return true
    }

    /// Releases the active attempt and returns whether one retry was queued.
    mutating func finish() -> Bool {
        guard isReconciling else { return false }
        isReconciling = false
        defer { retryRequested = false }
        return retryRequested
    }
}

import Foundation

/// Serializes Recovery history queries around snapshot reconciliation. A
/// request is never discarded merely because a commit or prior query is active.
struct HWCCloudSnapshotHistoryRefreshQueue {
    private var hasBeenRequested = false
    private var refreshPending = false
    private var queryIsInFlight = false

    mutating func request(isReconciling: Bool) -> Bool {
        hasBeenRequested = true
        refreshPending = true
        return beginIfPossible(isReconciling: isReconciling)
    }

    mutating func synchronized(isReconciling: Bool) -> Bool {
        reconcileDidFinish(isReconciling: isReconciling)
    }

    /// Re-evaluates history after any terminal reconcile result. Recovery must
    /// already have been opened, and an active history query remains serial.
    mutating func reconcileDidFinish(isReconciling: Bool) -> Bool {
        guard hasBeenRequested else { return false }
        refreshPending = true
        return beginIfPossible(isReconciling: isReconciling)
    }

    mutating func queryDidFinish(isReconciling: Bool) -> Bool {
        queryIsInFlight = false
        return beginIfPossible(isReconciling: isReconciling)
    }

    private mutating func beginIfPossible(isReconciling: Bool) -> Bool {
        guard !isReconciling,
              !queryIsInFlight,
              refreshPending else {
            return false
        }
        refreshPending = false
        queryIsInFlight = true
        return true
    }
}

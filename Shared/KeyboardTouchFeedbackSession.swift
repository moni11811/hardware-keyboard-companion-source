/// Coordinates deferred touch-down feedback and the fallback for a tap that finishes first.
struct KeyboardTouchFeedbackSession {
    private(set) var generation = 0
    private var active = false
    private var delivered = false

    mutating func begin() {
        generation += 1
        active = true
        delivered = false
    }

    mutating func claimScheduledFeedback(generation: Int) -> Bool {
        guard active, self.generation == generation, !delivered else { return false }
        delivered = true
        return true
    }

    mutating func finish(acceptedTap: Bool) -> Bool {
        let needsFeedback = active && acceptedTap && !delivered
        active = false
        return needsFeedback
    }

    mutating func cancel() { active = false }
}

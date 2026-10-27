import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Does not delay ordinary thumb taps. Once outward/inward intent is claimed, it owns both touches.
final class KeyboardSemiFoldGestureRecognizer: UIGestureRecognizer {
    var canStart: (CGPoint, CGPoint) -> Bool = { _, _ in false }
    var isJoining: () -> Bool = { false }
    var onClaim: () -> Void = {}
    var onFinish: (Bool, Bool) -> Void = { _, _ in }
    private var tracked = Set<UITouch>()
    private var pair: (UITouch, UITouch)?
    private var session: KeyboardSemiFoldSession?
    private var didClaim = false
    private var invalidated = false
    private var firstFingerEnded = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        tracked.formUnion(touches)
        if firstFingerEnded { invalidated = true }
        guard tracked.count <= 2 else {
            invalidated = true
            if !didClaim { state = .failed }
            return
        }
        guard tracked.count == 2, pair == nil, let view else { return }
        let ordered = tracked.sorted { $0.location(in: view).x < $1.location(in: view).x }
        let left = ordered[0].location(in: view), right = ordered[1].location(in: view)
        guard canStart(left, right),
              let session = KeyboardSemiFoldSession(left: left, right: right, joining: isJoining()) else {
            state = .failed
            return
        }
        pair = (ordered[0], ordered[1])
        self.session = session
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard !invalidated, !firstFingerEnded, let pair, var session, let view else { return }
        session.update(left: pair.0.location(in: view), right: pair.1.location(in: view))
        self.session = session
        if session.claimed, !didClaim {
            didClaim = true
            onClaim()
            state = .began
        } else if didClaim {
            state = .changed
        }
        if session.rejected {
            invalidated = true
            if !didClaim { state = .failed }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        // Evaluate the final positions before the first finger leaves. Never reuse stale positions.
        if pair != nil, tracked.count == 2 { touchesMoved(touches, with: event) }
        firstFingerEnded = true
        tracked.subtract(touches)
        guard tracked.isEmpty else { return }
        finish(cancelled: false)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        invalidated = true
        tracked.subtract(touches)
        if tracked.isEmpty { finish(cancelled: true) }
    }

    private func finish(cancelled: Bool) {
        if didClaim {
            onFinish(!cancelled && !invalidated && session?.shouldCommit == true, session?.joining == true)
            didClaim = false
            state = cancelled ? .cancelled : .ended
        } else {
            state = .failed
        }
    }

    override func reset() {
        if didClaim { onFinish(false, session?.joining == true) }
        tracked.removeAll()
        pair = nil
        session = nil
        didClaim = false
        invalidated = false
        firstFingerEnded = false
        super.reset()
    }
}

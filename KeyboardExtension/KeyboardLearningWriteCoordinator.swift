import Foundation

/// Storage interface for keyboard learning. Implementations own persistence;
/// the coordinator owns execution order and keeps writes off the typing path.
protocol KeyboardLearningPersisting: Sendable {
    func recordCommittedContext(_ context: String, language: String)
    func recordRawTypedText(_ rawText: String, previousRawText: String?, boundary: String)
    func recordAdaptiveCommittedWord(_ word: String, previousWord: String?)
    func recordAcceptedSuggestion(_ request: KeyboardAcceptedSuggestionLearning)
    func recordRejectedAutocorrection(_ request: KeyboardRejectedAutocorrectionLearning)
}

struct KeyboardAcceptedSuggestionLearning: Sendable {
    let personalizationContext: HWKPersonalizationContext
    let languageBrainEvent: HWKLanguageBrainEvent
}

struct KeyboardRejectedAutocorrectionLearning: Sendable {
    let rejectionFingerprint: String
    let rejectedAt: Date
    let languageBrainEvent: HWKLanguageBrainEvent?
}

struct LiveKeyboardLearningPersistence: KeyboardLearningPersisting {
    func recordCommittedContext(_ context: String, language: String) {
        _ = HWKPersistentPhraseLearner().recordCommittedContext(context, language: language)
    }

    func recordRawTypedText(
        _ rawText: String,
        previousRawText: String?,
        boundary: String
    ) {
        KeyboardSharedPreferences.recordRawTypedTextMLSample(
            rawText: rawText,
            previousRawText: previousRawText,
            boundary: boundary
        )
    }

    func recordAdaptiveCommittedWord(_ word: String, previousWord: String?) {
        KeyboardSharedPreferences.recordAdaptiveCommittedWord(word, previousWord: previousWord)
    }

    func recordAcceptedSuggestion(_ request: KeyboardAcceptedSuggestionLearning) {
        _ = HWKAutocorrectionPersonalizationStore().observe(
            context: request.personalizationContext,
            accepted: true
        )
        _ = HWKLanguageBrainEventStore().record(request.languageBrainEvent)
    }

    func recordRejectedAutocorrection(_ request: KeyboardRejectedAutocorrectionLearning) {
        HWKAutocorrectionRejectionStore().record(
            fingerprint: request.rejectionFingerprint,
            at: request.rejectedAt
        )
        if let languageBrainEvent = request.languageBrainEvent {
            _ = HWKLanguageBrainEventStore().record(languageBrainEvent)
        }
    }
}

/// Owns ordered, off-main persistence for learning events emitted by the keyboard.
///
/// UserDefaults-backed learners use read-modify-write transactions. All live
/// coordinator instances share one serial executor, preventing overlapping
/// mutations when UIKit temporarily owns more than one keyboard controller.
final class KeyboardLearningWriteCoordinator: @unchecked Sendable {
    /// Learning is opportunistic. Never let persistence backlog compete without bound
    /// with keyboard input, suggestions, or feedback.
    static let maximumPendingWriteCount = 32
    private static let maximumWritesPerDrain = 8

    private static let livePersistenceQueue = DispatchQueue(
        label: "dev.moni11811.hwc.keyboard-learning-writes",
        qos: .utility
    )
    private static let liveExecutor = WriteExecutor(queue: livePersistenceQueue)

    private let executor: WriteExecutor
    private let persistence: any KeyboardLearningPersisting
    private let pendingWrites = DispatchGroup()

    /// Orders immutable runtime reads after every learning write already submitted.
    /// Call only from a background queue; the keyboard main thread never waits here.
    static func withOrderedPersistenceRead<Value: Sendable>(
        _ read: @Sendable () -> Value
    ) -> Value {
        livePersistenceQueue.sync(execute: read)
    }

    init(
        persistence: any KeyboardLearningPersisting = LiveKeyboardLearningPersistence(),
        queue: DispatchQueue? = nil
    ) {
        self.persistence = persistence
        executor = queue.map(WriteExecutor.init(queue:)) ?? Self.liveExecutor
    }

    func recordCommittedContext(_ context: String, language: String) {
        enqueue { [persistence] in
            persistence.recordCommittedContext(context, language: language)
        }
    }

    func recordRawTypedText(
        _ rawText: String,
        previousRawText: String?,
        boundary: String
    ) {
        enqueue { [persistence] in
            persistence.recordRawTypedText(
                rawText,
                previousRawText: previousRawText,
                boundary: boundary
            )
        }
    }

    func recordAdaptiveCommittedWord(_ word: String, previousWord: String?) {
        enqueue { [persistence] in
            persistence.recordAdaptiveCommittedWord(word, previousWord: previousWord)
        }
    }

    func recordAcceptedSuggestion(_ request: KeyboardAcceptedSuggestionLearning) {
        enqueue { [persistence] in
            persistence.recordAcceptedSuggestion(request)
        }
    }

    func recordRejectedAutocorrection(_ request: KeyboardRejectedAutocorrectionLearning) {
        enqueue { [persistence] in
            persistence.recordRejectedAutocorrection(request)
        }
    }

    @discardableResult
    func waitUntilDrained(timeout: TimeInterval) -> Bool {
        pendingWrites.wait(timeout: .now() + timeout) == .success
    }

    private func enqueue(_ write: @escaping @Sendable () -> Void) {
        pendingWrites.enter()
        executor.enqueue(
            write,
            completion: { [pendingWrites] in
                pendingWrites.leave()
            }
        )
    }

    private final class WriteExecutor: @unchecked Sendable {
        private struct PendingWrite: Sendable {
            let perform: @Sendable () -> Void
            let complete: @Sendable () -> Void
        }

        private let queue: DispatchQueue
        private let pendingLock = NSLock()
        private var queuedWrites = [PendingWrite]()
        private var drainScheduled = false

        init(queue: DispatchQueue) {
            self.queue = queue
        }

        func enqueue(
            _ write: @escaping @Sendable () -> Void,
            completion: @escaping @Sendable () -> Void
        ) {
            let pendingWrite = PendingWrite(perform: write, complete: completion)
            var droppedWrite: PendingWrite?
            var shouldScheduleDrain = false

            pendingLock.lock()
            if queuedWrites.count >= KeyboardLearningWriteCoordinator.maximumPendingWriteCount {
                droppedWrite = queuedWrites.removeFirst()
            }
            queuedWrites.append(pendingWrite)
            if !drainScheduled {
                drainScheduled = true
                shouldScheduleDrain = true
            }
            pendingLock.unlock()

            droppedWrite?.complete()
            if shouldScheduleDrain {
                queue.async { [self] in
                    drainBatch()
                }
            }
        }

        private func drainBatch() {
            var drainedCount = 0
            while drainedCount < KeyboardLearningWriteCoordinator.maximumWritesPerDrain {
                pendingLock.lock()
                guard !queuedWrites.isEmpty else {
                    drainScheduled = false
                    pendingLock.unlock()
                    return
                }
                let write = queuedWrites.removeFirst()
                pendingLock.unlock()

                write.perform()
                write.complete()
                drainedCount += 1
            }

            pendingLock.lock()
            if queuedWrites.isEmpty {
                drainScheduled = false
                pendingLock.unlock()
                return
            }
            pendingLock.unlock()

            // Yield after a small batch so ordered reads cannot sit behind an
            // entire messaging session's learning history.
            queue.async { [self] in
                drainBatch()
            }
        }
    }
}

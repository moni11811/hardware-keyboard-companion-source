import Foundation

struct KeyboardAdaptiveAutocompleteWorkRequest: Equatable, Sendable {
    let signature: String
    let prefix: String?
    let previousWord: String?
    let predictsNextWord: Bool
    let contextBeforeInput: String
    let activeLanguage: String
}

struct KeyboardAdaptiveAutocompleteWorkResult: Sendable {
    let suggestions: [String]
    let learnedPhraseSuggestions: [HWKLearnedPhraseSuggestion]
}

protocol KeyboardAdaptiveAutocompleteLoading: Sendable {
    func load(
        _ request: KeyboardAdaptiveAutocompleteWorkRequest
    ) -> KeyboardAdaptiveAutocompleteWorkResult
}

struct LiveKeyboardAdaptiveAutocompleteLoader: KeyboardAdaptiveAutocompleteLoading {
    func load(
        _ request: KeyboardAdaptiveAutocompleteWorkRequest
    ) -> KeyboardAdaptiveAutocompleteWorkResult {
        let wordSuggestions: [String]
        if request.predictsNextWord {
            wordSuggestions = KeyboardSharedPreferences.adaptiveNextWordSuggestions(
                previousWord: request.previousWord,
                limit: 3
            )
        } else {
            wordSuggestions = KeyboardSharedPreferences.adaptiveAutocompleteSuggestions(
                prefix: request.prefix ?? "",
                previousWord: request.previousWord,
                limit: 3
            )
        }
        let learnedPhraseSuggestions = HWKPersistentPhraseLearner().suggestions(
            for: request.contextBeforeInput,
            language: request.activeLanguage,
            limit: 3
        )
        var seen = Set<String>()
        let suggestions = (
            learnedPhraseSuggestions.map(\.replacement) + wordSuggestions
        ).filter {
            seen.insert($0.lowercased()).inserted
        }
        return KeyboardAdaptiveAutocompleteWorkResult(
            suggestions: suggestions,
            learnedPhraseSuggestions: learnedPhraseSuggestions
        )
    }
}

/// Runs at most one adaptive lookup and retains only the newest pending request.
/// Cancellation of a Swift task cannot interrupt synchronous App Group reads,
/// so coalescing must happen before those reads begin.
final class KeyboardAdaptiveAutocompleteCoordinator: @unchecked Sendable {
    typealias Completion = @Sendable (
        KeyboardAdaptiveAutocompleteWorkRequest,
        KeyboardAdaptiveAutocompleteWorkResult
    ) -> Void

    private static let liveQueue = DispatchQueue(
        label: "dev.moni11811.hwc.keyboard-adaptive-autocomplete",
        qos: .utility
    )
    private static let liveExecutor = WorkExecutor(queue: liveQueue)

    private let ownerID = UUID()
    private let loader: any KeyboardAdaptiveAutocompleteLoading
    private let executor: WorkExecutor

    init(
        loader: any KeyboardAdaptiveAutocompleteLoading =
            LiveKeyboardAdaptiveAutocompleteLoader(),
        queue: DispatchQueue? = nil
    ) {
        self.loader = loader
        executor = queue.map(WorkExecutor.init(queue:)) ?? Self.liveExecutor
    }

    deinit {
        executor.cancelPending(ownerID: ownerID)
    }

    func request(
        _ request: KeyboardAdaptiveAutocompleteWorkRequest,
        completion: @escaping Completion
    ) {
        executor.enqueue(
            ownerID: ownerID,
            perform: { [loader] in
                loader.load(request)
            },
            completion: { result in
                completion(request, result)
            }
        )
    }

    func cancelPending() {
        executor.cancelPending(ownerID: ownerID)
    }

    private final class WorkExecutor: @unchecked Sendable {
        private struct Work: Sendable {
            let ownerID: UUID
            let perform: @Sendable () -> KeyboardAdaptiveAutocompleteWorkResult
            let completion: @Sendable (KeyboardAdaptiveAutocompleteWorkResult) -> Void
        }

        private let queue: DispatchQueue
        private let lock = NSLock()
        private var pendingWorkByOwner = [UUID: Work]()
        private var pendingOwnerOrder = [UUID]()
        private var drainScheduled = false

        init(queue: DispatchQueue) {
            self.queue = queue
        }

        func enqueue(
            ownerID: UUID,
            perform: @escaping @Sendable () -> KeyboardAdaptiveAutocompleteWorkResult,
            completion: @escaping @Sendable (KeyboardAdaptiveAutocompleteWorkResult) -> Void
        ) {
            lock.lock()
            if pendingWorkByOwner[ownerID] == nil {
                pendingOwnerOrder.append(ownerID)
            }
            pendingWorkByOwner[ownerID] = Work(
                ownerID: ownerID,
                perform: perform,
                completion: completion
            )
            guard !drainScheduled else {
                lock.unlock()
                return
            }
            drainScheduled = true
            lock.unlock()

            queue.async { [self] in
                drain()
            }
        }

        func cancelPending(ownerID: UUID) {
            lock.lock()
            if pendingWorkByOwner.removeValue(forKey: ownerID) != nil {
                pendingOwnerOrder.removeAll { $0 == ownerID }
            }
            lock.unlock()
        }

        private func drain() {
            while true {
                lock.lock()
                var work: Work?
                while work == nil, !pendingOwnerOrder.isEmpty {
                    let ownerID = pendingOwnerOrder.removeFirst()
                    work = pendingWorkByOwner.removeValue(forKey: ownerID)
                }
                guard let work else {
                    drainScheduled = false
                    lock.unlock()
                    return
                }
                lock.unlock()

                work.completion(work.perform())
            }
        }
    }
}

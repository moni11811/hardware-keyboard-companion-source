import Foundation

/// Keeps CloudKit repair fan-out bounded while preserving deterministic order.
/// CloudKit may reject a large operation dynamically, so a limit error splits
/// only that batch; every other error stops before the visible head can advance.
enum HWCCloudSnapshotOperationBatcher {
    static let maximumRecordsPerOperation = 64
    static let maximumAssetRecordsPerOperation = 8
    static let maximumEncodedAssetBytesPerOperation = 4 * 1_024 * 1_024

    static func batches<Element>(
        _ elements: [Element],
        maximumCount: Int = maximumRecordsPerOperation
    ) -> [[Element]] {
        precondition(maximumCount > 0)
        guard !elements.isEmpty else { return [] }
        return stride(from: 0, to: elements.count, by: maximumCount).map {
            Array(elements[$0..<min($0 + maximumCount, elements.count)])
        }
    }

    static func performBatches<Element>(
        _ elements: [Element],
        maximumCount: Int = maximumRecordsPerOperation,
        shouldSplit: (Error) -> Bool,
        operation: ([Element]) async throws -> Void
    ) async throws {
        for batch in batches(elements, maximumCount: maximumCount) {
            try await performBatch(
                batch,
                shouldSplit: shouldSplit,
                operation: operation
            )
        }
    }

    /// CKAsset records are bounded by encoded bytes as well as count. An item
    /// larger than the preferred aggregate limit remains intact in its own
    /// retryable batch; immutable envelope bytes are never split or dropped.
    static func weightedBatches<Element>(
        _ elements: [Element],
        maximumCount: Int = maximumAssetRecordsPerOperation,
        maximumWeight: Int = maximumEncodedAssetBytesPerOperation,
        weight: (Element) throws -> Int
    ) rethrows -> [[Element]] {
        precondition(maximumCount > 0)
        precondition(maximumWeight > 0)
        var result: [[Element]] = []
        var current: [Element] = []
        var currentWeight = 0

        for element in elements {
            let elementWeight = try weight(element)
            precondition(elementWeight >= 0)
            let exceedsCount = current.count >= maximumCount
            let exceedsWeight = elementWeight > maximumWeight - currentWeight
            if !current.isEmpty, exceedsCount || exceedsWeight {
                result.append(current)
                current = []
                currentWeight = 0
            }

            current.append(element)
            currentWeight += elementWeight
            if current.count >= maximumCount || currentWeight >= maximumWeight {
                result.append(current)
                current = []
                currentWeight = 0
            }
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    static func performWeightedBatches<Element>(
        _ elements: [Element],
        maximumCount: Int = maximumAssetRecordsPerOperation,
        maximumWeight: Int = maximumEncodedAssetBytesPerOperation,
        weight: (Element) throws -> Int,
        shouldSplit: (Error) -> Bool,
        operation: ([Element]) async throws -> Void
    ) async throws {
        for batch in try weightedBatches(
            elements,
            maximumCount: maximumCount,
            maximumWeight: maximumWeight,
            weight: weight
        ) {
            try await performBatch(
                batch,
                shouldSplit: shouldSplit,
                operation: operation
            )
        }
    }

    static func firstMatchingError<Value>(
        in results: [Result<Value, Error>],
        matching predicate: (Error) -> Bool
    ) -> Error? {
        for result in results {
            guard case .failure(let error) = result else { continue }
            if predicate(error) { return error }
        }
        return nil
    }

    private static func performBatch<Element>(
        _ batch: [Element],
        shouldSplit: (Error) -> Bool,
        operation: ([Element]) async throws -> Void
    ) async throws {
        do {
            try await operation(batch)
        } catch {
            guard batch.count > 1, shouldSplit(error) else { throw error }
            let midpoint = batch.count / 2
            try await performBatch(
                Array(batch[..<midpoint]),
                shouldSplit: shouldSplit,
                operation: operation
            )
            try await performBatch(
                Array(batch[midpoint...]),
                shouldSplit: shouldSplit,
                operation: operation
            )
        }
    }
}

/// Resolves an async callback once. A timeout wins atomically, cancels the
/// underlying operation, and makes any late CloudKit callback a no-op.
final class HWCCloudSnapshotOperationWatchdog<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Value) -> Void)?
    private var timeoutTimer: DispatchSourceTimer?
    private let timeoutValue: () -> Value
    private var onTimeout: (() -> Void)?

    init(
        timeoutInterval: TimeInterval,
        timeoutValue: @escaping () -> Value,
        onTimeout: @escaping () -> Void = {},
        queue: DispatchQueue = .global(qos: .utility),
        completion: @escaping (Value) -> Void
    ) {
        precondition(timeoutInterval > 0)
        self.timeoutValue = timeoutValue
        self.onTimeout = onTimeout
        self.completion = completion
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timeoutTimer = timer
        timer.setEventHandler { [self] in
            resolveTimeout()
        }
        timer.schedule(deadline: .now() + timeoutInterval)
        timer.activate()
    }

    @discardableResult
    func resolve(_ value: Value) -> Bool {
        lock.lock()
        guard let completion else {
            lock.unlock()
            return false
        }
        self.completion = nil
        let timeoutTimer = self.timeoutTimer
        self.timeoutTimer = nil
        self.onTimeout = nil
        lock.unlock()

        timeoutTimer?.setEventHandler {}
        timeoutTimer?.cancel()
        completion(value)
        return true
    }

    private func resolveTimeout() {
        lock.lock()
        guard let completion else {
            lock.unlock()
            return
        }
        self.completion = nil
        let timeoutTimer = self.timeoutTimer
        self.timeoutTimer = nil
        var onTimeout = self.onTimeout
        self.onTimeout = nil
        lock.unlock()

        timeoutTimer?.setEventHandler {}
        timeoutTimer?.cancel()
        onTimeout?()
        onTimeout = nil
        completion(timeoutValue())
    }
}

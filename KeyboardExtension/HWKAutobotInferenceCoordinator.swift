import Foundation

/// Synchronous Core ML cannot be interrupted. Coalesce before work, invalidate before publication.
final class HWKAutobotInferenceCoordinator: @unchecked Sendable {
    typealias Completion = (HWKAutobotContext, HWKAutobotModelResult?) -> Void
    private struct Work {
        let context: HWKAutobotContext
        let words: [String]
        let generation: UInt64
        let completion: Completion
    }
    private static let liveQueue = DispatchQueue(label: "dev.moni11811.hwc.autobot-context", qos: .utility)
    private let queue: DispatchQueue
    private let lock = NSLock()
    private let provider: HWKAutobotPredicting
    private let now: () -> TimeInterval
    private let usefulnessBudget: TimeInterval
    private var pending: Work?
    private var running = false
    private var unloadRequested = false
    private var generation: UInt64 = 0
    private var presentation: UInt64 = 0
    private var blockedPresentation: UInt64?
    private var blockedUntil: TimeInterval = 0
    private var failures = 0

    init(provider: HWKAutobotPredicting = HWKAutobotLanguageModel(), queue: DispatchQueue? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }, usefulnessBudget: TimeInterval = 0.120) {
        self.provider = provider
        self.queue = queue ?? Self.liveQueue
        self.now = now
        self.usefulnessBudget = usefulnessBudget
    }

    func beginPresentation() {
        lock.lock(); defer { lock.unlock() }
        presentation &+= 1
        failures = 0
    }

    @discardableResult
    func request(_ context: HWKAutobotContext, candidateWords: [String] = [], completion: @escaping Completion) -> Bool {
        lock.lock()
        guard blockedPresentation != presentation, now() >= blockedUntil else { lock.unlock(); return false }
        generation &+= 1
        pending = Work(context: context, words: Array(candidateWords.prefix(24)), generation: generation, completion: completion)
        startLocked()
        lock.unlock()
        return true
    }

    func cancel(unload: Bool = true) {
        lock.lock()
        generation &+= 1
        pending = nil
        unloadRequested = unloadRequested || unload
        if unloadRequested { startLocked() }
        lock.unlock()
    }

    func memoryWarning() {
        lock.lock()
        generation &+= 1
        pending = nil
        blockedPresentation = presentation
        blockedUntil = now() + 30
        unloadRequested = true
        startLocked()
        lock.unlock()
    }

    private func startLocked() {
        guard !running else { return }
        running = true
        queue.async { [self] in drain() }
    }

    private func drain() {
        while true {
            lock.lock()
            let shouldUnload = unloadRequested
            unloadRequested = false
            let work = pending
            pending = nil
            if !shouldUnload && work == nil { running = false; lock.unlock(); return }
            lock.unlock()
            if shouldUnload { autoreleasepool { provider.unload() } }
            guard let work else { continue }
            let started = now()
            var result = autoreleasepool { try? provider.predict(context: work.context, candidateWords: work.words) }
            if now() - started > usefulnessBudget { result = nil }
            lock.lock()
            let current = generation == work.generation
            if current {
                failures = result == nil ? failures + 1 : 0
                if failures >= 3 { blockedPresentation = presentation; unloadRequested = true }
            }
            lock.unlock()
            guard current else { continue }
            let deliveredResult = result
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let current = self.generation == work.generation
                self.lock.unlock()
                if current { work.completion(work.context, deliveredResult) }
            }
        }
    }
}

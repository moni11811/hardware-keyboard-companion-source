import Foundation

struct AutobotEpisodeCandidateMemory: Equatable, Sendable {
    let source: String
    let replacement: String
    let timestampMilliseconds: Int64
}

struct AutobotEpisodePersistenceRequest: @unchecked Sendable {
    enum Kind: Equatable, Sendable {
        case persist
        case reconcile
    }

    let kind: Kind
    let coordinator: HWKAutobotLiveEpisodeCoordinator?
    let snapshot: HWKAutobotTypingEpisodeSnapshot
    let candidateMemory: AutobotEpisodeCandidateMemory?
    let timestampMilliseconds: Int64
    let expectedResetEpoch: String

    static func persist(
        coordinator: HWKAutobotLiveEpisodeCoordinator,
        snapshot: HWKAutobotTypingEpisodeSnapshot,
        candidateMemory: AutobotEpisodeCandidateMemory?,
        timestampMilliseconds: Int64,
        expectedResetEpoch: String
    ) -> Self {
        Self(
            kind: .persist,
            coordinator: coordinator,
            snapshot: snapshot,
            candidateMemory: candidateMemory,
            timestampMilliseconds: timestampMilliseconds,
            expectedResetEpoch: expectedResetEpoch
        )
    }

    static func reconcile(
        snapshot: HWKAutobotTypingEpisodeSnapshot,
        timestampMilliseconds: Int64,
        expectedResetEpoch: String
    ) -> Self {
        Self(
            kind: .reconcile,
            coordinator: nil,
            snapshot: snapshot,
            candidateMemory: nil,
            timestampMilliseconds: timestampMilliseconds,
            expectedResetEpoch: expectedResetEpoch
        )
    }
}

struct AutobotEpisodePersistenceOutcome: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case committed
        case skippedStaleEpoch
        case failed
    }

    let status: Status
    let shouldReloadChampion: Bool
    let championCreditModel: HWKAutobotEpisodeCreditModel?

    static func committed(
        shouldReloadChampion: Bool,
        championCreditModel: HWKAutobotEpisodeCreditModel? = nil
    ) -> Self {
        Self(
            status: .committed,
            shouldReloadChampion: shouldReloadChampion,
            championCreditModel: shouldReloadChampion ? championCreditModel : nil
        )
    }

    static let skippedStaleEpoch = Self(
        status: .skippedStaleEpoch,
        shouldReloadChampion: false,
        championCreditModel: nil
    )
    static let failed = Self(
        status: .failed,
        shouldReloadChampion: false,
        championCreditModel: nil
    )
}

struct AutobotEpisodeLoadOutcome: @unchecked Sendable {
    enum Status: Equatable, Sendable {
        case loaded
        case skippedStaleEpoch
    }

    let status: Status
    let coordinator: HWKAutobotLiveEpisodeCoordinator?

    static func loaded(_ coordinator: HWKAutobotLiveEpisodeCoordinator) -> Self {
        Self(status: .loaded, coordinator: coordinator)
    }

    static let skippedStaleEpoch = Self(
        status: .skippedStaleEpoch,
        coordinator: nil
    )
}

protocol AutobotEpisodePersistenceExecuting: Sendable {
    func loadTypingEpisodes(
        expectedResetEpoch: String
    ) -> AutobotEpisodeLoadOutcome

    func execute(
        _ request: AutobotEpisodePersistenceRequest
    ) -> AutobotEpisodePersistenceOutcome
}

/// One FIFO boundary for extension-side episode saves and settings catch-up.
///
/// All live instances share the same serial queue. The controller hands off
/// immutable value snapshots; UIKit and protected-layer state never cross it.
final class AutobotEpisodePersistenceCoordinator: @unchecked Sendable {
    private static let livePersistenceQueue = DispatchQueue(
        label: "dev.moni11811.hwc.autobot-episode-persistence",
        qos: .utility
    )

    private let executor: any AutobotEpisodePersistenceExecuting
    private let queue: DispatchQueue
    private let pendingWrites = DispatchGroup()

    init(
        executor: any AutobotEpisodePersistenceExecuting,
        queue: DispatchQueue? = nil
    ) {
        self.executor = executor
        self.queue = queue ?? Self.livePersistenceQueue
    }

    func load(
        expectedResetEpoch: String,
        completion: @escaping @Sendable (AutobotEpisodeLoadOutcome) -> Void
    ) {
        pendingWrites.enter()
        queue.async { [executor, pendingWrites] in
            defer { pendingWrites.leave() }
            completion(
                executor.loadTypingEpisodes(
                    expectedResetEpoch: expectedResetEpoch
                )
            )
        }
    }

    func enqueue(
        _ request: AutobotEpisodePersistenceRequest,
        completion: @escaping @Sendable (AutobotEpisodePersistenceOutcome) -> Void = { _ in }
    ) {
        pendingWrites.enter()
        queue.async { [executor, pendingWrites] in
            defer { pendingWrites.leave() }
            completion(executor.execute(request))
        }
    }

    @discardableResult
    func waitUntilDrained(timeout: TimeInterval) -> Bool {
        pendingWrites.wait(timeout: .now() + timeout) == .success
    }
}

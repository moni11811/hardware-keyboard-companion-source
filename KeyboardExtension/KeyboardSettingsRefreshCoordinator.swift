import Foundation

struct KeyboardAutocorrectionRuntimeSnapshot: Sendable {
    let personalizer: HWKFTRLPersonalizer
    let championCreditModel: HWKAutobotEpisodeCreditModel
    let languageBrain: HWKLanguageBrainSnapshot
    let rejectedAutocorrectionFingerprints: Set<String>

    static let empty = KeyboardAutocorrectionRuntimeSnapshot(
        personalizer: .standard,
        championCreditModel: HWKAutobotEpisodeCreditModel(),
        languageBrain: .empty,
        rejectedAutocorrectionFingerprints: []
    )
}

struct KeyboardSettingsRefreshSnapshot: @unchecked Sendable {
    let settings: KeyboardSettingsSnapshot
    let customDictionaryWords: Set<String>
    let autocorrectionRuntime: KeyboardAutocorrectionRuntimeSnapshot
}

protocol KeyboardSettingsRefreshLoading: Sendable {
    func load() -> KeyboardSettingsRefreshSnapshot
}

/// Coalesces settings reloads while keeping App Group reads off the typing thread.
final class KeyboardSettingsRefreshCoordinator: @unchecked Sendable {
    typealias Completion = @Sendable (UInt64, KeyboardSettingsRefreshSnapshot) -> Void

    private struct Request: @unchecked Sendable {
        let generation: UInt64
        let completion: Completion
    }

    private static let liveRefreshQueue = DispatchQueue(
        label: "dev.moni11811.hwc.keyboard-settings-refresh",
        qos: .userInitiated
    )

    private let loader: any KeyboardSettingsRefreshLoading
    private let queue: DispatchQueue
    private let stateLock = NSLock()
    private var pendingRequest: Request?
    private var drainScheduled = false

    init(
        loader: any KeyboardSettingsRefreshLoading,
        queue: DispatchQueue? = nil
    ) {
        self.loader = loader
        self.queue = queue ?? Self.liveRefreshQueue
    }

    func request(
        generation: UInt64,
        completion: @escaping Completion
    ) {
        stateLock.lock()
        pendingRequest = Request(generation: generation, completion: completion)
        guard !drainScheduled else {
            stateLock.unlock()
            return
        }
        drainScheduled = true
        stateLock.unlock()

        queue.async { [self] in
            drain()
        }
    }

    private func drain() {
        while true {
            stateLock.lock()
            guard let request = pendingRequest else {
                drainScheduled = false
                stateLock.unlock()
                return
            }
            pendingRequest = nil
            stateLock.unlock()

            request.completion(request.generation, loader.load())
        }
    }
}

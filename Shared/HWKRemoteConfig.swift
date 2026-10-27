import Foundation

enum HWKRemoteFlag: String, Codable, CaseIterable {
    case hwkKernel
    case gcModifierSource
    case jsonLayouts
    case deadKeys
    case complexScripts
    case glideTyping
    case autocorrectV2
    case predictionsV2
    case contextualAutobot
    case encryptedClipboard
    case hardwareReaderPublic
}

struct HWKRemoteConfig: Codable, Equatable {
    var rolloutPercent: Int
    var enabledFlags: Set<HWKRemoteFlag>
    var disabledFlags: Set<HWKRemoteFlag>
    var minimumBuild: Int

    static let safeDefault = HWKRemoteConfig(
        rolloutPercent: 0,
        enabledFlags: [],
        disabledFlags: Set(HWKRemoteFlag.allCases),
        minimumBuild: 0
    )

    func isEnabled(_ flag: HWKRemoteFlag) -> Bool {
        enabledFlags.contains(flag) && !disabledFlags.contains(flag)
    }

    func isEligible(stableUserBucket: Int, currentBuildNumber: Int? = nil) -> Bool {
        guard stableUserBucket >= 0 && stableUserBucket < max(0, min(rolloutPercent, 100)) else {
            return false
        }

        guard minimumBuild > 0, let currentBuildNumber else {
            return true
        }

        return currentBuildNumber >= minimumBuild
    }

    var normalized: HWKRemoteConfig {
        HWKRemoteConfig(
            rolloutPercent: max(0, min(rolloutPercent, 100)),
            enabledFlags: enabledFlags,
            disabledFlags: disabledFlags,
            minimumBuild: max(0, minimumBuild)
        )
    }
}

struct HWKRemoteConfigDecoder {
    func decode(_ data: Data) -> HWKRemoteConfig {
        decodeIfValid(data) ?? .safeDefault
    }

    func decodeIfValid(_ data: Data) -> HWKRemoteConfig? {
        do {
            return try JSONDecoder().decode(HWKRemoteConfig.self, from: data).normalized
        } catch {
            return nil
        }
    }
}

enum HWKRemoteConfigUpdateStatus: Equatable {
    case applied
    case rejected
}

struct HWKRemoteConfigUpdate: Equatable {
    let status: HWKRemoteConfigUpdateStatus
    let config: HWKRemoteConfig
}

enum HWKRemoteConfigRefreshStatus: Equatable {
    case applied
    case rejected
    case skipped
}

struct HWKRemoteConfigRefreshResult: Equatable {
    let status: HWKRemoteConfigRefreshStatus
    let config: HWKRemoteConfig
}

struct HWKRemoteConfigStore {
    var defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    func current() -> HWKRemoteConfig {
        guard let data = defaults.data(forKey: KeyboardSharedPreferences.Key.remoteConfig) else {
            return .safeDefault
        }
        return HWKRemoteConfigDecoder().decodeIfValid(data) ?? .safeDefault
    }

    @discardableResult
    func applyFetchedData(
        _ data: Data,
        fetchedAt: Date = Date(),
        notify: Bool = true
    ) -> HWKRemoteConfigUpdate {
        guard let config = HWKRemoteConfigDecoder().decodeIfValid(data),
              let encoded = try? JSONEncoder().encode(config) else {
            return HWKRemoteConfigUpdate(status: .rejected, config: current())
        }

        defaults.set(encoded, forKey: KeyboardSharedPreferences.Key.remoteConfig)
        defaults.set(
            fetchedAt.timeIntervalSince1970,
            forKey: KeyboardSharedPreferences.Key.remoteConfigFetchedAt
        )
        KeyboardSharedPreferences.sync()
        if notify {
            KeyboardSharedPreferences.postSettingsDidChangeNotification()
        }
        return HWKRemoteConfigUpdate(status: .applied, config: config)
    }
}

struct HWKRemoteConfigRefreshCoordinator {
    var store: HWKRemoteConfigStore
    var minimumInterval: TimeInterval
    var now: () -> Date
    var fetchData: () async throws -> Data

    init(
        store: HWKRemoteConfigStore = HWKRemoteConfigStore(),
        minimumInterval: TimeInterval = 60 * 60,
        now: @escaping () -> Date = { Date() },
        fetchData: @escaping () async throws -> Data
    ) {
        self.store = store
        self.minimumInterval = minimumInterval
        self.now = now
        self.fetchData = fetchData
    }

    func refresh(force: Bool = false, notify: Bool = true) async -> HWKRemoteConfigRefreshResult {
        let current = store.current()
        if !force,
           let lastFetchedAt = lastFetchedAt(),
           now().timeIntervalSince(lastFetchedAt) < minimumInterval {
            return HWKRemoteConfigRefreshResult(status: .skipped, config: current)
        }

        do {
            let data = try await fetchData()
            let update = store.applyFetchedData(data, fetchedAt: now(), notify: notify)
            let status: HWKRemoteConfigRefreshStatus = update.status == .applied ? .applied : .rejected
            return HWKRemoteConfigRefreshResult(status: status, config: update.config)
        } catch {
            return HWKRemoteConfigRefreshResult(status: .rejected, config: current)
        }
    }

    private func lastFetchedAt() -> Date? {
        guard store.defaults.object(forKey: KeyboardSharedPreferences.Key.remoteConfigFetchedAt) != nil else {
            return nil
        }

        return Date(
            timeIntervalSince1970: store.defaults.double(forKey: KeyboardSharedPreferences.Key.remoteConfigFetchedAt)
        )
    }
}

enum HWKRemoteConfigFetchError: Error {
    case invalidResponse
    case httpStatus(Int)
    case emptyBody
}

extension HWKRemoteConfigRefreshCoordinator {
    static let companionRemoteConfigURLKey = "HWCRemoteConfigURL"

    static func configuredForCompanionApp(
        bundle: Bundle = .main,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) -> HWKRemoteConfigRefreshCoordinator? {
        guard let rawURL = bundle.object(forInfoDictionaryKey: companionRemoteConfigURLKey) as? String else {
            return nil
        }

        let trimmedURL = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty,
              let url = URL(string: trimmedURL),
              url.scheme?.lowercased() == "https" else {
            return nil
        }

        return HWKRemoteConfigRefreshCoordinator(
            store: HWKRemoteConfigStore(defaults: defaults),
            fetchData: {
                try await fetchData(from: url)
            }
        )
    }

    static func fetchData(from url: URL, session: URLSession = .shared) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: url) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: HWKRemoteConfigFetchError.invalidResponse)
                    return
                }

                guard (200..<300).contains(httpResponse.statusCode) else {
                    continuation.resume(throwing: HWKRemoteConfigFetchError.httpStatus(httpResponse.statusCode))
                    return
                }

                guard let data, !data.isEmpty else {
                    continuation.resume(throwing: HWKRemoteConfigFetchError.emptyBody)
                    return
                }

                continuation.resume(returning: data)
            }
            task.resume()
        }
    }
}

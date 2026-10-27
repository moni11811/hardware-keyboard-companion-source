import Foundation

struct HWKRefreshThrottle {
    private(set) var lastSignature: String?
    private(set) var lastRefreshAt: Date = .distantPast

    mutating func shouldRefresh(
        signature: String,
        now: Date = Date(),
        minInterval: TimeInterval
    ) -> Bool {
        guard lastSignature == signature,
              now.timeIntervalSince(lastRefreshAt) < minInterval else {
            lastSignature = signature
            lastRefreshAt = now
            return true
        }
        return false
    }

    mutating func reset() {
        lastSignature = nil
        lastRefreshAt = .distantPast
    }
}

enum HWKFeatureFlags {
    struct Snapshot: Equatable {
        let config: HWKRemoteConfig
        let stableUserBucket: Int
        let currentBuildNumber: Int
        let inputKernelFallbackDisabled: Bool
        let predictionDisabled: Bool
        let glideDisabled: Bool
        let clipboardDisabled: Bool

        func isEnabled(_ flag: HWKRemoteFlag) -> Bool {
            guard config.isEligible(stableUserBucket: stableUserBucket, currentBuildNumber: currentBuildNumber),
                  config.isEnabled(flag) else {
                return false
            }

            switch flag {
            case .predictionsV2:
                return !predictionDisabled
            case .contextualAutobot:
                return !predictionDisabled && isEnabled(.predictionsV2)
            case .hwkKernel:
                return !inputKernelFallbackDisabled
            case .glideTyping:
                return !glideDisabled
            case .encryptedClipboard:
                return !clipboardDisabled
            default:
                return true
            }
        }

        var jsonLayoutsEnabled: Bool {
            isEnabled(.jsonLayouts)
        }

        var deadKeysEnabled: Bool {
            isEnabled(.deadKeys)
        }

        var complexScriptsEnabled: Bool {
            isEnabled(.complexScripts)
        }

        var hardwareReaderPublicEnabled: Bool {
            isEnabled(.hardwareReaderPublic)
        }
    }

    static func snapshot(
        config: HWKRemoteConfig = .safeDefault,
        stableUserBucket: Int = 100,
        currentBuildNumber: Int = .max,
        inputKernelFallbackDisabled: Bool = false,
        predictionDisabled: Bool = false,
        glideDisabled: Bool = false,
        clipboardDisabled: Bool = false
    ) -> Snapshot {
        Snapshot(
            config: config,
            stableUserBucket: stableUserBucket,
            currentBuildNumber: currentBuildNumber,
            inputKernelFallbackDisabled: inputKernelFallbackDisabled,
            predictionDisabled: predictionDisabled,
            glideDisabled: glideDisabled,
            clipboardDisabled: clipboardDisabled
        )
    }

    static func snapshot(settings: KeyboardSettingsSnapshot, currentBuildNumber: Int = .max) -> Snapshot {
        snapshot(
            config: settings.remoteConfig,
            stableUserBucket: settings.stableUserBucket,
            currentBuildNumber: currentBuildNumber,
            inputKernelFallbackDisabled: settings.inputKernelFallbackDisabled,
            predictionDisabled: settings.predictionDisabled,
            glideDisabled: settings.glideDisabled,
            clipboardDisabled: settings.clipboardDisabled
        )
    }

    static func snapshot(
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        currentBuildNumber: Int? = nil
    ) -> Snapshot {
        snapshot(
            settings: KeyboardSettingsSnapshot.load(from: defaults),
            currentBuildNumber: currentBuildNumber ?? currentBundleBuildNumber()
        )
    }

    static func isEnabled(
        _ flag: HWKRemoteFlag,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults,
        currentBuildNumber: Int? = nil
    ) -> Bool {
        snapshot(defaults: defaults, currentBuildNumber: currentBuildNumber).isEnabled(flag)
    }

    static func currentBundleBuildNumber(bundle: Bundle = .main) -> Int {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return 0
        }

        return Int(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static var kernelEnabled: Bool {
        isEnabled(.hwkKernel)
    }

    static var gameControllerModifierSourceEnabled: Bool {
        isEnabled(.gcModifierSource)
    }

    static var autocorrectV2Enabled: Bool {
        isEnabled(.autocorrectV2)
    }

    static var predictionV2Enabled: Bool {
        isEnabled(.predictionsV2)
    }

    static var multilingualClipboardEnabled: Bool {
        isEnabled(.encryptedClipboard)
    }

    static var accessibilityAuditEnabled: Bool {
#if DEBUG
        false
#else
        false
#endif
    }
}

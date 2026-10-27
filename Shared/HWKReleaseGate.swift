import Foundation

enum HWKReleaseStage: String, Codable, CaseIterable {
    case dogfood
    case testFlight
    case production
}

struct HWKReleaseGateIssue: Equatable {
    let code: String
    let message: String
}

struct HWKReleaseGateInput: Equatable {
    var stage: HWKReleaseStage
    var config: HWKRemoteConfig
    var crashRate: Double
    var p95KeyLatencyMS: Double
    var productionBuildHasInternalDebugFlag: Bool
    var uploadGuardPassed: Bool
    var currentBuildNumber: Int = .max
}

struct HWKReleaseGate {
    func issues(for input: HWKReleaseGateInput) -> [HWKReleaseGateIssue] {
        var issues: [HWKReleaseGateIssue] = []

        if !input.uploadGuardPassed {
            issues.append(HWKReleaseGateIssue(code: "uploadGuard", message: "ASC upload guard must pass."))
        }

        if input.productionBuildHasInternalDebugFlag {
            issues.append(HWKReleaseGateIssue(code: "internalDebug", message: "Production build must not include internal debug flags."))
        }

        if input.crashRate > 0.01 {
            issues.append(HWKReleaseGateIssue(code: "crashRate", message: "Crash rate above rollout budget."))
        }

        if input.p95KeyLatencyMS > 16 {
            issues.append(HWKReleaseGateIssue(code: "latency", message: "Key P95 latency above frame budget."))
        }

        if input.config.minimumBuild > 0 && input.currentBuildNumber < input.config.minimumBuild {
            issues.append(HWKReleaseGateIssue(code: "minimumBuild", message: "Current build is below remote config minimum."))
        }

        return issues
    }
}

enum HWCKeyboardLaunchHost: String, CaseIterable, Equatable, Hashable {
    case spotlight
    case appLibrary = "app-library"
    case messages
    case safari

    static let defaultLaunchHosts: [HWCKeyboardLaunchHost] = [
        .spotlight,
        .appLibrary,
        .messages,
        .safari,
    ]
}

struct HWCKeyboardLaunchVisualFrameSample: Equatable {
    let host: HWCKeyboardLaunchHost
    let elapsedMS: Int
    let width: Int
    let height: Int
    let keyboardHeight: Int
    let realKeyboardPixelPermille: Int
    let staleLaunchSurfaceSignature: Bool
    let appPaintedLaunchSurfaceSignature: Bool

    init(
        host: HWCKeyboardLaunchHost,
        elapsedMS: Int,
        width: Int,
        height: Int,
        keyboardHeight: Int,
        realKeyboardPixelPermille: Int,
        staleLaunchSurfaceSignature: Bool,
        appPaintedLaunchSurfaceSignature: Bool = false
    ) {
        self.host = host
        self.elapsedMS = elapsedMS
        self.width = width
        self.height = height
        self.keyboardHeight = keyboardHeight
        self.realKeyboardPixelPermille = realKeyboardPixelPermille
        self.staleLaunchSurfaceSignature = staleLaunchSurfaceSignature
        self.appPaintedLaunchSurfaceSignature = appPaintedLaunchSurfaceSignature
    }
}

struct HWCKeyboardLaunchStableCommitSample: Equatable {
    let host: HWCKeyboardLaunchHost
    let elapsedMS: Int
    let surfaceVisible: Bool
}

struct HWCKeyboardLaunchVisualGateResult: Equatable {
    let requiredHostIDs: [String]
    let passedHostIDs: [String]
    let blockedReasonIDs: [String]

    var isGreen: Bool {
        blockedReasonIDs.isEmpty && passedHostIDs == requiredHostIDs
    }
}

struct HWCKeyboardLaunchVisualGate: Equatable {
    let requiredHosts: [HWCKeyboardLaunchHost]
    let firstFrameDeadlineMS: Int
    let stableCommitDeadlineMS: Int
    let minimumRealKeyboardPixelPermille: Int
    let maximumKeyboardHeightDelta: Int

    init(
        requiredHosts: [HWCKeyboardLaunchHost] = HWCKeyboardLaunchHost.defaultLaunchHosts,
        firstFrameDeadlineMS: Int = 300,
        stableCommitDeadlineMS: Int = 700,
        minimumRealKeyboardPixelPermille: Int = 650,
        maximumKeyboardHeightDelta: Int = 24
    ) {
        self.requiredHosts = requiredHosts
        self.firstFrameDeadlineMS = firstFrameDeadlineMS
        self.stableCommitDeadlineMS = stableCommitDeadlineMS
        self.minimumRealKeyboardPixelPermille = minimumRealKeyboardPixelPermille
        self.maximumKeyboardHeightDelta = maximumKeyboardHeightDelta
    }

    func evaluate(
        frameSamples: [HWCKeyboardLaunchVisualFrameSample],
        stableCommits: [HWCKeyboardLaunchStableCommitSample]
    ) -> HWCKeyboardLaunchVisualGateResult {
        var passedHostIDs: [String] = []
        var blockedReasonIDs: [String] = []

        for host in requiredHosts {
            let hostID = host.rawValue
            let hostFrames = frameSamples
                .filter { $0.host == host }
                .sorted { $0.elapsedMS < $1.elapsedMS }
            let hostCommits = stableCommits
                .filter { $0.host == host }
                .sorted { $0.elapsedMS < $1.elapsedMS }
            let issueCountBeforeHost = blockedReasonIDs.count

            if let firstFrame = hostFrames.first(where: { $0.elapsedMS <= firstFrameDeadlineMS }) {
                if firstFrame.width <= 0 || firstFrame.height <= 0 ||
                    firstFrame.realKeyboardPixelPermille < minimumRealKeyboardPixelPermille {
                    blockedReasonIDs.append("host:\(hostID):first-frame-blank")
                }
                if firstFrame.staleLaunchSurfaceSignature {
                    blockedReasonIDs.append("host:\(hostID):stale-launch-surface")
                }
                if firstFrame.appPaintedLaunchSurfaceSignature {
                    blockedReasonIDs.append("host:\(hostID):app-painted-launch-surface")
                }
            } else {
                blockedReasonIDs.append("host:\(hostID):first-frame-missing")
            }

            if keyboardHeightDelta(in: hostFrames) > maximumKeyboardHeightDelta {
                blockedReasonIDs.append("host:\(hostID):height-jump")
            }

            if let stableCommit = hostCommits.first {
                if stableCommit.elapsedMS > stableCommitDeadlineMS {
                    blockedReasonIDs.append("host:\(hostID):stable-commit-late")
                }
                if stableCommit.surfaceVisible {
                    blockedReasonIDs.append("host:\(hostID):stable-commit-surface-visible")
                }
            } else {
                blockedReasonIDs.append("host:\(hostID):stable-commit-missing")
            }

            if blockedReasonIDs.count == issueCountBeforeHost {
                passedHostIDs.append(hostID)
            }
        }

        return HWCKeyboardLaunchVisualGateResult(
            requiredHostIDs: requiredHosts.map(\.rawValue),
            passedHostIDs: passedHostIDs,
            blockedReasonIDs: blockedReasonIDs
        )
    }

    private func keyboardHeightDelta(in frames: [HWCKeyboardLaunchVisualFrameSample]) -> Int {
        let heights = frames.map(\.keyboardHeight).filter { $0 > 0 }
        guard let minHeight = heights.min(), let maxHeight = heights.max() else { return 0 }
        return maxHeight - minHeight
    }
}

enum HWCKeyboardLaunchBenchmarkKeyboard: String, CaseIterable, Equatable, Hashable {
    case hwc
    case swiftKey = "swiftkey"
    case gboard

    static let parityKeyboards: [HWCKeyboardLaunchBenchmarkKeyboard] = [
        .hwc,
        .swiftKey,
        .gboard,
    ]
}

struct HWCKeyboardLaunchBenchmarkCapture: Equatable {
    let keyboard: HWCKeyboardLaunchBenchmarkKeyboard
    let host: HWCKeyboardLaunchHost
    let frameSamples: [HWCKeyboardLaunchVisualFrameSample]
    let stableCommits: [HWCKeyboardLaunchStableCommitSample]

    var captureID: String {
        "host:\(host.rawValue):keyboard:\(keyboard.rawValue)"
    }

    static func referenceGood(
        _ keyboard: HWCKeyboardLaunchBenchmarkKeyboard,
        host: HWCKeyboardLaunchHost,
        firstFrameMS: Int = 120,
        stableCommitMS: Int = 260
    ) -> HWCKeyboardLaunchBenchmarkCapture {
        HWCKeyboardLaunchBenchmarkCapture(
            keyboard: keyboard,
            host: host,
            frameSamples: [
                HWCKeyboardLaunchVisualFrameSample(
                    host: host,
                    elapsedMS: firstFrameMS,
                    width: 393,
                    height: 344,
                    keyboardHeight: 344,
                    realKeyboardPixelPermille: 930,
                    staleLaunchSurfaceSignature: false
                )
            ],
            stableCommits: [
                HWCKeyboardLaunchStableCommitSample(host: host, elapsedMS: stableCommitMS, surfaceVisible: false)
            ]
        )
    }
}

struct HWCKeyboardLaunchParityGateResult: Equatable {
    let requiredCaptureIDs: [String]
    let blockedReasonIDs: [String]

    var isGreen: Bool {
        blockedReasonIDs.isEmpty
    }
}

struct HWCKeyboardLaunchParityGate: Equatable {
    let requiredHosts: [HWCKeyboardLaunchHost]
    let requiredKeyboards: [HWCKeyboardLaunchBenchmarkKeyboard]
    let maximumReferenceLagMS: Int
    let visualGate: HWCKeyboardLaunchVisualGate

    init(
        requiredHosts: [HWCKeyboardLaunchHost] = HWCKeyboardLaunchHost.defaultLaunchHosts,
        requiredKeyboards: [HWCKeyboardLaunchBenchmarkKeyboard] = HWCKeyboardLaunchBenchmarkKeyboard.parityKeyboards,
        maximumReferenceLagMS: Int = 80,
        visualGate: HWCKeyboardLaunchVisualGate = HWCKeyboardLaunchVisualGate()
    ) {
        self.requiredHosts = requiredHosts
        self.requiredKeyboards = requiredKeyboards
        self.maximumReferenceLagMS = maximumReferenceLagMS
        self.visualGate = visualGate
    }

    func evaluate(captures: [HWCKeyboardLaunchBenchmarkCapture]) -> HWCKeyboardLaunchParityGateResult {
        var blockedReasonIDs: [String] = []
        let requiredCaptureIDs = requiredHosts.flatMap { host in
            requiredKeyboards.map { keyboard in
                "host:\(host.rawValue):keyboard:\(keyboard.rawValue)"
            }
        }

        for host in requiredHosts {
            let hostCaptures = captures.filter { $0.host == host }

            for keyboard in requiredKeyboards {
                guard let capture = hostCaptures.first(where: { $0.keyboard == keyboard }) else {
                    blockedReasonIDs.append("host:\(host.rawValue):keyboard:\(keyboard.rawValue):capture-missing")
                    continue
                }

                let result = visualGateFor(host: host).evaluate(
                    frameSamples: capture.frameSamples,
                    stableCommits: capture.stableCommits
                )
                blockedReasonIDs.append(contentsOf: result.blockedReasonIDs.map {
                    "host:\(host.rawValue):keyboard:\(keyboard.rawValue):\($0)"
                })
            }

            blockedReasonIDs.append(contentsOf: parityLagReasons(for: host, captures: hostCaptures))
        }

        return HWCKeyboardLaunchParityGateResult(
            requiredCaptureIDs: requiredCaptureIDs,
            blockedReasonIDs: blockedReasonIDs
        )
    }

    private func visualGateFor(host: HWCKeyboardLaunchHost) -> HWCKeyboardLaunchVisualGate {
        HWCKeyboardLaunchVisualGate(
            requiredHosts: [host],
            firstFrameDeadlineMS: visualGate.firstFrameDeadlineMS,
            stableCommitDeadlineMS: visualGate.stableCommitDeadlineMS,
            minimumRealKeyboardPixelPermille: visualGate.minimumRealKeyboardPixelPermille,
            maximumKeyboardHeightDelta: visualGate.maximumKeyboardHeightDelta
        )
    }

    private func parityLagReasons(
        for host: HWCKeyboardLaunchHost,
        captures: [HWCKeyboardLaunchBenchmarkCapture]
    ) -> [String] {
        guard let hwc = captures.first(where: { $0.keyboard == .hwc }),
              let hwcFirstFrameMS = firstUsableFrameMS(in: hwc.frameSamples),
              let hwcStableCommitMS = hwc.stableCommits.map(\.elapsedMS).min()
        else {
            return []
        }

        let references = captures.filter { $0.keyboard != .hwc }
        let referenceFirstFrameMS = references.compactMap { firstUsableFrameMS(in: $0.frameSamples) }
        let referenceStableCommitMS = references.compactMap { $0.stableCommits.map(\.elapsedMS).min() }
        var reasons: [String] = []

        if let slowestReferenceFirstFrameMS = referenceFirstFrameMS.max(),
           hwcFirstFrameMS - slowestReferenceFirstFrameMS > maximumReferenceLagMS {
            reasons.append("host:\(host.rawValue):hwc-first-frame-lag")
        }

        if let slowestReferenceStableCommitMS = referenceStableCommitMS.max(),
           hwcStableCommitMS - slowestReferenceStableCommitMS > maximumReferenceLagMS {
            reasons.append("host:\(host.rawValue):hwc-stable-commit-lag")
        }

        return reasons
    }

    private func firstUsableFrameMS(in frames: [HWCKeyboardLaunchVisualFrameSample]) -> Int? {
        frames
            .filter {
                $0.width > 0 &&
                    $0.height > 0 &&
                    $0.realKeyboardPixelPermille >= visualGate.minimumRealKeyboardPixelPermille &&
                    !$0.staleLaunchSurfaceSignature &&
                    !$0.appPaintedLaunchSurfaceSignature
            }
            .map(\.elapsedMS)
            .min()
    }
}

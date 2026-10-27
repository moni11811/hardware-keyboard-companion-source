import Foundation

enum HWCHardwareReadingOSPolicy {
    static func unsupportedMessage(majorVersion: Int) -> String? {
        majorVersion == 27 ? "iOS 27 is unsupported" : nil
    }

    static var currentUnsupportedMessage: String? {
        let majorVersion = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        #if DEBUG && targetEnvironment(simulator)
        if majorVersion == 27 { return nil }
        #endif
        return unsupportedMessage(majorVersion: majorVersion)
    }
}

enum HWCBuildFlavor {
    enum ReleaseChannel: String {
        case debug = "DEBUG"
        case testflight = "TESTFLIGHT"
        case production = "PRODUCTION"
    }

    #if HWC_INTERNAL_BUILD
    static let isInternal = true
    #else
    static let isInternal = false
    #endif

    static let releaseChannel: ReleaseChannel = {
        guard
            let rawValue = Bundle.main.object(forInfoDictionaryKey: "HWCReleaseChannel") as? String,
            let channel = ReleaseChannel(
                rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            )
        else {
            return isInternal ? .debug : .production
        }

        return channel
    }()

    static let isBeta = releaseChannel == .testflight
    static let isTestFlight = releaseChannel == .testflight
    static let hardwareRelayDefaultsEnabled = false
    static let hardwarePurchaseGateRepairEnabled = false
    static let readerRetired = true
    static let includesHardwareCapture = false
    static let supportsHardwareDebugTools = includesHardwareCapture && isInternal
    static let autoUnlockPaidFeatures = isInternal && releaseChannel == .debug
    static let hardwareKeypressPaidReliabilityGatePassed = true
    static let hardwareKeypressPaidStoreEnabled = false

    static var hardwareKeypressPaidFeatureIsBeta: Bool {
        !hardwareKeypressPaidReliabilityGatePassed
    }

    static var hardwareKeypressPaidFeatureTitle: String {
        "Hardware Keyboard Reading"
    }

    static var hardwareKeypressPaidFeatureDetail: String {
        "Unlock or restore Hardware Keyboard Reading without the yearly support bundle."
    }

    static var hardwareKeypressPaidPurchaseTitle: String {
        "Unlock Hardware Keyboard Reading"
    }

    static let hardwareKeypressPaidPurchasePausedMessage =
        "Hardware Keyboard Reading has been removed. New purchases are unavailable."
}

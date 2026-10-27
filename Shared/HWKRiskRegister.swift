import Foundation

enum HWKRiskStatus: String, Codable {
    case accepted
    case mitigated
    case blocked
}

struct HWKRiskItem: Codable, Equatable {
    let id: String
    let title: String
    let owner: String
    let status: HWKRiskStatus
    let releaseBlocker: Bool
}

struct HWKRiskRegister: Codable, Equatable {
    let risks: [HWKRiskItem]

    var unresolvedReleaseBlockers: [HWKRiskItem] {
        risks.filter { $0.releaseBlocker && $0.status == .blocked }
    }

    static let roadmapClosure = HWKRiskRegister(risks: [
        HWKRiskItem(id: "hostTiming", title: "Host proxy timing differs by app.", owner: "keyboard", status: .mitigated, releaseBlocker: true),
        HWKRiskItem(id: "modifierTruth", title: "GameController modifier truth wrong.", owner: "input", status: .mitigated, releaseBlocker: true),
        HWKRiskItem(id: "layoutMigration", title: "JSON layout migration breaks maps.", owner: "layout", status: .mitigated, releaseBlocker: true),
        HWKRiskItem(id: "imeUX", title: "Marked text unsupported in host.", owner: "text", status: .accepted, releaseBlocker: false),
        HWKRiskItem(id: "rtlCursor", title: "RTL cursor state wrong.", owner: "text", status: .mitigated, releaseBlocker: true),
        HWKRiskItem(id: "glideBattery", title: "Glide drains battery.", owner: "perf", status: .mitigated, releaseBlocker: true),
        HWKRiskItem(id: "foundationModels", title: "FoundationModels unavailable.", owner: "prediction", status: .accepted, releaseBlocker: false),
        HWKRiskItem(id: "clipboardPrivacy", title: "Clipboard feature review risk.", owner: "privacy", status: .mitigated, releaseBlocker: true),
        HWKRiskItem(id: "internalLeak", title: "App Store build leaks internal tooling.", owner: "release", status: .mitigated, releaseBlocker: true),
    ])
}

import Foundation

struct HWKAccessibleControl: Equatable {
    let identifier: String
    let label: String
    let width: Double
    let height: Double
}

struct HWKContrastPair: Equatable {
    let foreground: HWKRelativeColor
    let background: HWKRelativeColor
    let isLargeText: Bool
}

struct HWKRelativeColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    var luminance: Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.03928 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}

struct HWKAccessibilityIssue: Equatable {
    let identifier: String
    let message: String
}

struct HWKAccessibilityAudit {
    let minimumHitTarget: Double

    init(minimumHitTarget: Double = 44) {
        self.minimumHitTarget = minimumHitTarget
    }

    func issues(for controls: [HWKAccessibleControl]) -> [HWKAccessibilityIssue] {
        controls.flatMap { control in
            var issues: [HWKAccessibilityIssue] = []
            if control.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(HWKAccessibilityIssue(identifier: control.identifier, message: "Missing accessibility label"))
            }
            if control.width < minimumHitTarget || control.height < minimumHitTarget {
                issues.append(HWKAccessibilityIssue(identifier: control.identifier, message: "Hit target below 44pt"))
            }
            return issues
        }
    }

    func contrastRatio(for pair: HWKContrastPair) -> Double {
        let lighter = max(pair.foreground.luminance, pair.background.luminance)
        let darker = min(pair.foreground.luminance, pair.background.luminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    func passesAA(_ pair: HWKContrastPair) -> Bool {
        contrastRatio(for: pair) >= (pair.isLargeText ? 3.0 : 4.5)
    }
}

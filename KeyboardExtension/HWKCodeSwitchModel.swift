import Foundation

struct HWKCodeSwitchContext: Equatable {
    let tokens: [String]
    let primaryLanguage: HWKLanguageID
    let userSelectedLanguage: HWKLanguageID

    init(
        tokens: [String],
        primaryLanguage: HWKLanguageID = .english,
        userSelectedLanguage: HWKLanguageID = .english
    ) {
        self.tokens = tokens
        self.primaryLanguage = primaryLanguage
        self.userSelectedLanguage = userSelectedLanguage
    }
}

struct HWKCodeSwitchDecision: Equatable {
    let activeLanguage: HWKLanguageID
    let shouldSuggestLayoutSwitch: Bool
}

struct HWKCodeSwitchModel {
    private let detector: HWKLanguageDetector
    private let switchThreshold: Double

    init(detector: HWKLanguageDetector = HWKLanguageDetector(), switchThreshold: Double = 0.6) {
        self.detector = detector
        self.switchThreshold = switchThreshold
    }

    func decision(for context: HWKCodeSwitchContext) -> HWKCodeSwitchDecision {
        let detection = detector.detect(tokens: context.tokens, primaryLanguage: context.primaryLanguage)
        let activeLanguage = detection.confidence >= switchThreshold ? detection.language : context.userSelectedLanguage
        return HWKCodeSwitchDecision(
            activeLanguage: activeLanguage,
            shouldSuggestLayoutSwitch: activeLanguage != context.userSelectedLanguage
        )
    }
}

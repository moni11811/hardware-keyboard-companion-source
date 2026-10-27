import Foundation
import UIKit

struct HWKNativeSpellChecker: HWKCorrectionCandidateGenerating {
    private let checker = UITextChecker()
    private let language: String

    init(language: String = "en_US") {
        self.language = language
    }

    func candidates(for word: String) -> [HWKCorrectionCandidate] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let guesses = checker.guesses(forWordRange: range, in: word, language: language) ?? []
        return guesses
            .prefix(5)
            .map {
                HWKCorrectionCandidate(
                    text: $0,
                    editDistance: HWKCorrectionEngine.editDistance(word.lowercased(), $0.lowercased(), maxDistance: 3),
                    frequency: 0.25,
                    source: .nativeSpellChecker
                )
            }
    }
}

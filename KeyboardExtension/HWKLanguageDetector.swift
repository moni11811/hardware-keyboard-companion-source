import Foundation

enum HWKLanguageID: String, Codable, Equatable {
    case english = "en"
    case french = "fr"
    case spanish = "es"
    case unknown
}

struct HWKLanguageDetection: Equatable {
    let language: HWKLanguageID
    let confidence: Double
}

struct HWKLanguageDetector {
    private let markers: [HWKLanguageID: Set<String>] = [
        .english: ["the", "and", "hello", "please", "thanks", "keyboard"],
        .french: ["le", "la", "les", "bonjour", "merci", "clavier", "avec"],
        .spanish: ["el", "la", "los", "hola", "gracias", "teclado", "con"],
    ]

    func detect(tokens: [String], primaryLanguage: HWKLanguageID = .english) -> HWKLanguageDetection {
        let normalized = tokens
            .map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        guard !normalized.isEmpty else {
            return HWKLanguageDetection(language: primaryLanguage, confidence: 0)
        }

        var scores: [HWKLanguageID: Int] = [:]
        for token in normalized.suffix(8) {
            for (language, words) in markers where words.contains(token) {
                scores[language, default: 0] += 1
            }
            if token.range(of: #"[éèêàçù]"#, options: .regularExpression) != nil {
                scores[.french, default: 0] += 2
            }
            if token.range(of: #"[ñáíóú]"#, options: .regularExpression) != nil {
                scores[.spanish, default: 0] += 2
            }
        }

        guard let best = scores.max(by: { $0.value < $1.value }) else {
            return HWKLanguageDetection(language: primaryLanguage, confidence: 0.1)
        }

        let total = max(scores.values.reduce(0, +), 1)
        return HWKLanguageDetection(language: best.key, confidence: Double(best.value) / Double(total))
    }
}

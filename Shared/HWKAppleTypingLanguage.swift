import Foundation
import NaturalLanguage
import CryptoKit

/// A transient language choice for suggestions, never for automatic replacement.
enum HWKAppleTypingLanguage {
    struct Resolution: Equatable, Codable {
        let checkerLanguage: String
        let detectedLanguage: String?
        let confidence: Double

        var permitsEnglishCandidates: Bool {
            (detectedLanguage ?? Self.base(checkerLanguage)) == "en"
        }

        fileprivate static func base(_ identifier: String) -> String {
            identifier.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? identifier
        }
    }

    static func resolve(
        contextBeforeInput: String,
        fallbackLanguage: String,
        availableLanguages: [String]
    ) -> Resolution {
        let sample = recognitionSample(in: contextBeforeInput)
        return resolve(sample: sample, fallbackLanguage: fallbackLanguage, availableLanguages: availableLanguages)
    }

    fileprivate static func resolve(sample: String, fallbackLanguage: String, availableLanguages: [String]) -> Resolution {
        let fallback = supportedLanguage(fallbackLanguage, available: availableLanguages) ?? fallbackLanguage
        guard !sample.isEmpty else {
            return Resolution(checkerLanguage: fallback, detectedLanguage: nil, confidence: 0)
        }
        let recognizer = NLLanguageRecognizer()
        defer { recognizer.reset() }
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        guard let best = hypotheses.first, best.value >= 0.85,
              best.value - (hypotheses.dropFirst().first?.value ?? 0) >= 0.20 else {
            return Resolution(checkerLanguage: fallback, detectedLanguage: nil, confidence: hypotheses.first?.value ?? 0)
        }
        let detected = Resolution.base(best.key.rawValue)
        // Keep a strong unsupported language distinct from an uncertain result:
        // it must not silently enable English-only predictors.
        let checkerLanguage = detected == Resolution.base(fallback)
            ? fallback
            : supportedLanguage(detected, available: availableLanguages) ?? fallback
        return Resolution(checkerLanguage: checkerLanguage, detectedLanguage: detected, confidence: best.value)
    }

    static func recognitionSample(in context: String) -> String {
        let window = context.suffix(385)
        var recent = String(window.suffix(384))
        // Discard a potentially cut word at the start of a long field window.
        if window.count > 384 {
            guard let space = recent.firstIndex(where: \.isWhitespace) else { return "" }
            recent = String(recent[space...])
        }
        if let boundary = recent.lastIndex(where: { ".!?\n\r".contains($0) }) {
            recent = String(recent[recent.index(after: boundary)...])
        }
        // Infer from completed words, not a typo or unfinished word at the caret.
        if let last = recent.last, !last.isWhitespace {
            guard let space = recent.lastIndex(where: \.isWhitespace) else { return "" }
            recent = String(recent[..<space])
        }
        guard !recent.contains(where: { "@/:_`{}=\\".contains($0) }) else { return "" }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = recent
        let tokens = tokenizer.tokens(for: recent.startIndex..<recent.endIndex)
            .map { String(recent[$0]) }
            .filter { token in token.allSatisfy { $0.isLetter || $0 == "'" || $0 == "’" } }
            .suffix(16)
        guard tokens.count >= 3, tokens.joined().filter(\.isLetter).count >= 12 else { return "" }
        return tokens.joined(separator: " ")
    }

    private static func supportedLanguage(_ identifier: String, available: [String]) -> String? {
        let normalized = identifier.replacingOccurrences(of: "-", with: "_").lowercased()
        return available.first { $0.replacingOccurrences(of: "-", with: "_").lowercased() == normalized }
            ?? available.first { Resolution.base($0) == Resolution.base(identifier) }
    }
}

/// One-entry cache holds a digest and result, never the sentence or a history.
final class HWKAppleTypingLanguageResolver {
    private var lastDigest: SHA256.Digest?
    private var lastFallback = ""
    private var lastAvailableLanguages = [String]()
    private var lastResolution: HWKAppleTypingLanguage.Resolution?

    func resolve(contextBeforeInput: String, fallbackLanguage: String,
                 availableLanguages: [String]) -> HWKAppleTypingLanguage.Resolution {
        let sample = HWKAppleTypingLanguage.recognitionSample(in: contextBeforeInput)
        let digest = SHA256.hash(data: Data(sample.utf8))
        if digest == lastDigest, fallbackLanguage == lastFallback,
           availableLanguages == lastAvailableLanguages, let lastResolution { return lastResolution }
        let result = HWKAppleTypingLanguage.resolve(sample: sample, fallbackLanguage: fallbackLanguage,
                                                   availableLanguages: availableLanguages)
        lastDigest = digest
        lastFallback = fallbackLanguage
        lastAvailableLanguages = availableLanguages
        lastResolution = result
        return result
    }
}

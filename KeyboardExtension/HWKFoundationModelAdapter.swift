import Foundation
import Darwin

enum HWKInternalMLDeviceGate {
    static func supportsCurrentDevice() -> Bool {
#if targetEnvironment(simulator)
        return false
#else
        return supportsDeviceIdentifier(currentMachineIdentifier())
#endif
    }

    static func supportsDeviceIdentifier(_ identifier: String) -> Bool {
        guard identifier.hasPrefix("iPhone") else { return false }

        if identifier == "iPhone16,1" || identifier == "iPhone16,2" {
            return true
        }

        guard let major = iPhoneMajorVersion(from: identifier) else {
            return false
        }
        return major >= 17
    }

    private static func iPhoneMajorVersion(from identifier: String) -> Int? {
        let trimmed = identifier.dropFirst("iPhone".count)
        return trimmed.split(separator: ",").first.flatMap { Int($0) }
    }

    private static func currentMachineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { rawBuffer in
            let bytes = rawBuffer.prefix { $0 != 0 }
            return String(bytes: bytes, encoding: .ascii) ?? ""
        }
    }
}

struct HWKFoundationModelAdapter: HWKCorrectionCandidateGenerating {
    private static let fallbackCandidates: [String: [String]] = [
        "teh": ["the"],
        "adn": ["and"],
        "recieve": ["receive"],
        "alot": ["a lot"],
        "definately": ["definitely"],
        "wich": ["which"]
    ]

    var isAvailable: Bool {
        !Self.fallbackCandidates.isEmpty
    }

    func candidates(for word: String) -> [HWKCorrectionCandidate] {
        let normalizedWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var results = [HWKCorrectionCandidate]()

        if let fallback = Self.fallbackCandidates[normalizedWord] {
            for suggestion in fallback {
                let distance = HWKCorrectionEngine.editDistance(normalizedWord, suggestion.lowercased(), maxDistance: 2)
                guard distance <= 2 else { continue }
                results.append(HWKCorrectionCandidate(
                    text: suggestion,
                    editDistance: distance,
                    frequency: 0.9,
                    source: .foundationModel
                ))
            }
        }

        return results
    }

    func predictNextWord(context: String) -> [HWKCorrectionCandidate] {
        // No NLEmbedding fallback: NLEmbedding.wordEmbedding(.english) loads a multi-hundred-MB
        // model into the keyboard extension's ~50MB budget and jetsam-kills it. Next-word
        // prediction is served by the lightweight on-device n-gram/bigram engine elsewhere.
        return []
    }
}

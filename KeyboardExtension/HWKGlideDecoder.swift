import Foundation
import CoreGraphics
import UIKit

struct HWKGlideKey: Equatable {
    var label: String
    var center: CGPoint
    var frame: CGRect?

    init(label: String, center: CGPoint, frame: CGRect? = nil) {
        self.label = label
        self.center = center
        self.frame = frame
    }
}

struct HWKGlideCandidate: Equatable {
    var word: String
    var score: Double
    var confidence: Double
}

enum HWKGlideInputPolicy {
    static func allowsGlideTyping(
        flags: HWKFeatureFlags.Snapshot,
        isSecureTextEntry: Bool,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType?
    ) -> Bool {
        guard flags.isEnabled(.glideTyping),
              !isSecureTextEntry else {
            return false
        }

        switch keyboardType {
        case .default,
             .asciiCapable,
             .alphabet:
            break
        case .emailAddress,
             .URL,
             .numberPad,
             .phonePad,
             .namePhonePad,
             .numbersAndPunctuation,
             .decimalPad,
             .twitter,
             .webSearch,
             .asciiCapableNumberPad:
            return false
        @unknown default:
            return false
        }

        let blockedContentTypes: Set<UITextContentType> = [
            .emailAddress,
            .username,
            .password,
            .newPassword,
            .oneTimeCode,
            .URL,
            .creditCardNumber,
            .telephoneNumber
        ]

        if let textContentType, blockedContentTypes.contains(textContentType) {
            return false
        }

        return true
    }
}

struct HWKGlideDecoder {
    var keys: [HWKGlideKey]
    var lexicon: HWKLexiconStore
    var bigramModel: HWKBigramModel
    var motorOffsets: [String: HWKMotorTouchOffset] = [:]
    var minimumDistance: CGFloat = 8
    var minimumDuration: TimeInterval = 0.04
    var minimumConfidence: Double = 0.25
    var maximumKeyDistance: CGFloat = 44
    var maxCandidates = 5

    func decode(path: HWKTouchPath, previousWord: String? = nil) -> [HWKGlideCandidate] {
        guard path.distance >= minimumDistance,
              path.duration >= minimumDuration else {
            return []
        }

        let simplified = path.simplified()
        let signature = nearestKeySignature(for: simplified)
        guard signature.count > 1 else { return [] }

        return glideCandidates(matching: signature).map { entry in
            let confidence = confidenceForCandidate(entry.word, signature: signature, path: simplified)
            let languageScore = entry.frequency + bigramModel.score(previous: previousWord, candidate: entry.word)
            return HWKGlideCandidate(
                word: entry.word,
                score: languageScore + confidence,
                confidence: confidence
            )
        }
        .filter { $0.confidence >= minimumConfidence }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.word < rhs.word
            }
            return lhs.score > rhs.score
        }
        .prefix(maxCandidates)
        .map { $0 }
    }

    func runtimeCandidate(
        for path: HWKTouchPath,
        previousWord: String? = nil,
        flags: HWKFeatureFlags.Snapshot,
        isSecureTextEntry: Bool,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType?
    ) -> String? {
        guard HWKGlideInputPolicy.allowsGlideTyping(
            flags: flags,
            isSecureTextEntry: isSecureTextEntry,
            keyboardType: keyboardType,
            textContentType: textContentType
        ) else {
            return nil
        }

        return decode(path: path, previousWord: previousWord).first?.word
    }

    func nearestKeySignature(for path: HWKTouchPath) -> String {
        var labels = [String]()
        for point in path.points {
            guard let key = nearestKey(to: point.location) else { continue }
            if labels.last != key.label {
                labels.append(key.label)
            }
        }
        return labels.joined()
    }

    private func nearestKey(to point: CGPoint) -> HWKGlideKey? {
        guard let nearest = keys.min(by: { lhs, rhs in
            distanceSquared(adjustedCenter(for: lhs), point)
                < distanceSquared(adjustedCenter(for: rhs), point)
        }) else {
            return nil
        }

        guard distanceSquared(adjustedCenter(for: nearest), point)
                <= maximumKeyDistance * maximumKeyDistance else {
            return nil
        }

        return nearest
    }

    private func adjustedCenter(for key: HWKGlideKey) -> CGPoint {
        guard let offset = motorOffsets[key.label.lowercased()],
              offset.dx.isFinite,
              offset.dy.isFinite,
              (-16...16).contains(offset.dx),
              (-16...16).contains(offset.dy) else {
            return key.center
        }
        return CGPoint(
            x: key.center.x + CGFloat(offset.dx),
            y: key.center.y + CGFloat(offset.dy)
        )
    }

    private func distanceSquared(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return dx * dx + dy * dy
    }

    private func glideCandidates(matching signature: String) -> [HWKLexiconEntry] {
        let signature = signature.lowercased()
        return lexicon.entries.filter { entry in
            isSubsequence(signature, of: entry.word.lowercased())
        }
    }

    private func confidenceForCandidate(_ word: String, signature: String, path: HWKTouchPath) -> Double {
        let word = word.lowercased()
        let signature = signature.lowercased()
        guard isSubsequence(signature, of: word), !word.isEmpty else { return 0 }

        let coverage = Double(signature.count) / Double(word.count)
        let pointDensity = min(1, Double(path.points.count) / Double(max(2, signature.count)))
        return min(1, (coverage * 0.75) + (pointDensity * 0.25))
    }

    private func isSubsequence(_ signature: String, of word: String) -> Bool {
        guard !signature.isEmpty else { return true }
        var remaining = signature[...]
        for character in word {
            if remaining.first == character {
                remaining.removeFirst()
                if remaining.isEmpty {
                    return true
                }
            }
        }
        return false
    }
}

import CryptoKit
import Compression
import Foundation
import NaturalLanguage

enum HWKGizmoImprovementLane: String, Codable, CaseIterable, Equatable {
    case touch
    case hardware
    case relay
    case aftermath
}

enum HWKGizmoImprovementFeature: String, Codable, CaseIterable, Equatable {
    case autocorrect
    case autocomplete
    case autofix
}

enum HWKGizmoImprovementBucket: String, Codable, CaseIterable, Equatable {
    case correction
    case completion
    case repair
    case language
    case timing
    case ux
}

enum HWKGizmoImprovementOutcome: String, Codable, CaseIterable, Equatable {
    case win
    case miss
    case rejected
    case applied
    case suppressed
}

struct HWKGizmoImprovementSignal: Codable, Equatable {
    var timestamp: Date
    var lane: HWKGizmoImprovementLane
    var feature: HWKGizmoImprovementFeature
    var bucket: HWKGizmoImprovementBucket
    var outcome: HWKGizmoImprovementOutcome
    var latencyMilliseconds: Int
    var confidenceBasisPoints: Int
    var candidateCount: Int
    var contextScalarCount: Int

    init(
        timestamp: Date = Date(),
        lane: HWKGizmoImprovementLane,
        feature: HWKGizmoImprovementFeature,
        bucket: HWKGizmoImprovementBucket,
        outcome: HWKGizmoImprovementOutcome,
        latencyMilliseconds: Int = 0,
        confidenceBasisPoints: Int = 0,
        candidateCount: Int = 0,
        contextScalarCount: Int = 0
    ) {
        self.timestamp = timestamp
        self.lane = lane
        self.feature = feature
        self.bucket = bucket
        self.outcome = outcome
        self.latencyMilliseconds = max(0, latencyMilliseconds)
        self.confidenceBasisPoints = min(max(0, confidenceBasisPoints), 10_000)
        self.candidateCount = max(0, candidateCount)
        self.contextScalarCount = max(0, contextScalarCount)
    }
}

struct HWKGizmoImprovementSummary: Codable, Equatable {
    var totalCount: Int
    var missCount: Int
    var winCount: Int
    var rejectedCount: Int
    var suppressedCount: Int
    var slowCount: Int

    static let empty = HWKGizmoImprovementSummary(
        totalCount: 0,
        missCount: 0,
        winCount: 0,
        rejectedCount: 0,
        suppressedCount: 0,
        slowCount: 0
    )
}

struct HWKGizmoImprovementFocus: Codable, Equatable {
    var lane: HWKGizmoImprovementLane
    var feature: HWKGizmoImprovementFeature
    var bucket: HWKGizmoImprovementBucket
    var totalCount: Int
    var missCount: Int
    var rejectedCount: Int
    var suppressedCount: Int
    var slowCount: Int

    var score: Int {
        (missCount * 4) + (rejectedCount * 3) + (suppressedCount * 2) + slowCount
    }
}

struct HWKGizmoImprovementSnapshot: Codable, Equatable {
    var generatedAt: Date
    var summary: HWKGizmoImprovementSummary
    var backlog: [HWKGizmoImprovementFocus]
    var recentSignals: [HWKGizmoImprovementSignal]
}

enum HWKGizmoImprovementTuningKind: String, Codable, Equatable {
    case hold
    case increaseRecall
    case strengthenSafetyGate
    case reduceLatency
}

struct HWKGizmoImprovementTuningDecision: Codable, Equatable {
    var kind: HWKGizmoImprovementTuningKind
    var focus: HWKGizmoImprovementFocus?

    static let hold = HWKGizmoImprovementTuningDecision(kind: .hold, focus: nil)
}

enum HWKGizmoImprovementTuningPolicy {
    static func decision(for snapshot: HWKGizmoImprovementSnapshot) -> HWKGizmoImprovementTuningDecision {
        guard let focus = snapshot.backlog
            .filter({ $0.score > 0 })
            .sorted(by: shouldRankBefore)
            .first else {
            return .hold
        }

        if focus.rejectedCount > 0 {
            return HWKGizmoImprovementTuningDecision(kind: .strengthenSafetyGate, focus: focus)
        }
        if focus.missCount > 0 || focus.suppressedCount > 0 {
            return HWKGizmoImprovementTuningDecision(kind: .increaseRecall, focus: focus)
        }
        if focus.slowCount > 0 {
            return HWKGizmoImprovementTuningDecision(kind: .reduceLatency, focus: focus)
        }

        return .hold
    }

    private static func shouldRankBefore(
        _ lhs: HWKGizmoImprovementFocus,
        _ rhs: HWKGizmoImprovementFocus
    ) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.totalCount > rhs.totalCount
    }
}

struct HWKGizmoImprovementRing {
    private var storage: [HWKGizmoImprovementSignal?]
    private var writeIndex: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int = 128) {
        let boundedCapacity = min(max(1, capacity), 512)
        self.capacity = boundedCapacity
        self.storage = Array(repeating: nil, count: boundedCapacity)
    }

    mutating func append(_ signal: HWKGizmoImprovementSignal) {
        storage[writeIndex] = signal
        writeIndex = (writeIndex + 1) % capacity
        count = min(count + 1, capacity)
    }

    func snapshot() -> [HWKGizmoImprovementSignal] {
        guard count > 0 else { return [] }

        let startIndex = count == capacity ? writeIndex : 0
        return (0..<count).compactMap { offset in
            storage[(startIndex + offset) % capacity]
        }
    }

    func summary(slowLatencyThresholdMilliseconds: Int = 80) -> HWKGizmoImprovementSummary {
        let signals = snapshot()
        guard !signals.isEmpty else { return .empty }

        var missCount = 0
        var winCount = 0
        var rejectedCount = 0
        var suppressedCount = 0
        var slowCount = 0
        let slowThreshold = max(0, slowLatencyThresholdMilliseconds)

        for signal in signals {
            if signal.outcome == .miss {
                missCount += 1
            }
            if signal.outcome == .win {
                winCount += 1
            }
            if signal.outcome == .rejected {
                rejectedCount += 1
            }
            if signal.outcome == .suppressed {
                suppressedCount += 1
            }
            if signal.latencyMilliseconds > slowThreshold {
                slowCount += 1
            }
        }

        return HWKGizmoImprovementSummary(
            totalCount: signals.count,
            missCount: missCount,
            winCount: winCount,
            rejectedCount: rejectedCount,
            suppressedCount: suppressedCount,
            slowCount: slowCount
        )
    }
}

struct HWKGizmoImprovementRecorder {
    private var ring: HWKGizmoImprovementRing
    private let slowLatencyThresholdMilliseconds: Int

    init(capacity: Int = 128, slowLatencyThresholdMilliseconds: Int = 80) {
        self.ring = HWKGizmoImprovementRing(capacity: capacity)
        self.slowLatencyThresholdMilliseconds = max(0, slowLatencyThresholdMilliseconds)
    }

    mutating func record(_ signal: HWKGizmoImprovementSignal) {
        ring.append(signal)
    }

    func snapshot() -> [HWKGizmoImprovementSignal] {
        ring.snapshot()
    }

    func summary() -> HWKGizmoImprovementSummary {
        ring.summary(slowLatencyThresholdMilliseconds: slowLatencyThresholdMilliseconds)
    }

    func improvementBacklog(limit: Int = 8) -> [HWKGizmoImprovementFocus] {
        guard limit > 0 else { return [] }

        var grouped: [HWKGizmoImprovementFocusKey: HWKGizmoImprovementFocus] = [:]
        for signal in ring.snapshot() {
            let key = HWKGizmoImprovementFocusKey(
                lane: signal.lane,
                feature: signal.feature,
                bucket: signal.bucket
            )
            var focus = grouped[key] ?? HWKGizmoImprovementFocus(
                lane: signal.lane,
                feature: signal.feature,
                bucket: signal.bucket,
                totalCount: 0,
                missCount: 0,
                rejectedCount: 0,
                suppressedCount: 0,
                slowCount: 0
            )
            focus.totalCount += 1
            switch signal.outcome {
            case .miss:
                focus.missCount += 1
            case .rejected:
                focus.rejectedCount += 1
            case .suppressed:
                focus.suppressedCount += 1
            case .win, .applied:
                break
            }
            if signal.latencyMilliseconds > slowLatencyThresholdMilliseconds {
                focus.slowCount += 1
            }
            grouped[key] = focus
        }

        return grouped.values
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.totalCount > $1.totalCount
            }
            .prefix(limit)
            .map { $0 }
    }
}

enum HWKGizmoImprovementSnapshotStore {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let storageKey = "keyboard.gizmoImprovement.latestSnapshot"

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.gizmo-improvement")

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= 128 * 1_024,
              let snapshot = try? makeDecoder().decode(
                  HWKGizmoImprovementSnapshot.self,
                  from: data
              ),
              snapshot.generatedAt.timeIntervalSince1970.isFinite,
              snapshot.backlog.count <= 64,
              snapshot.recentSignals.count <= 128 else {
            return false
        }
        return snapshot.backlog.allSatisfy { focus in
            focus.totalCount >= 0
                && focus.missCount >= 0
                && focus.rejectedCount >= 0
                && focus.suppressedCount >= 0
                && focus.slowCount >= 0
        }
    }

    static func update(from recorder: HWKGizmoImprovementRecorder,
        recentSignalLimit: Int = 16,
        backlogLimit: Int = 8,
        defaults: UserDefaults = sharedDefaults,
        now: Date = Date()
    ) {
        let snapshot = HWKGizmoImprovementSnapshot(
            generatedAt: now,
            summary: recorder.summary(),
            backlog: recorder.improvementBacklog(limit: backlogLimit),
            recentSignals: Array(recorder.snapshot().suffix(max(0, recentSignalLimit)))
        )
        update(snapshot, defaults: defaults)
    }

    static func updateFromKeyboardExtension(
        from recorder: HWKGizmoImprovementRecorder,
        recentSignalLimit: Int = 16,
        backlogLimit: Int = 8,
        defaults: UserDefaults = sharedDefaults,
        now: Date = Date()
    ) {
        let snapshot = HWKGizmoImprovementSnapshot(
            generatedAt: now,
            summary: recorder.summary(),
            backlog: recorder.improvementBacklog(limit: backlogLimit),
            recentSignals: Array(recorder.snapshot().suffix(max(0, recentSignalLimit)))
        )
        queue.sync {
            guard let data = try? makeEncoder().encode(snapshot) else { return }
            defaults.set(data, forKey: storageKey)
            KeyboardSharedPreferences.sync()
        }
    }

    static func update(
        _ snapshot: HWKGizmoImprovementSnapshot,
        defaults: UserDefaults = sharedDefaults
    ) {
        queue.sync {
            guard let data = try? makeEncoder().encode(snapshot) else { return }
            HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                storeIDs: [.gizmoSnapshot]
            ) {
                defaults.set(data, forKey: storageKey)
                KeyboardSharedPreferences.sync()
            }
        }
    }

    static func snapshot(defaults: UserDefaults = sharedDefaults) -> HWKGizmoImprovementSnapshot? {
        queue.sync {
            guard let data = defaults.data(forKey: storageKey) else { return nil }
            guard let snapshot = try? makeDecoder().decode(HWKGizmoImprovementSnapshot.self, from: data) else {
                HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                    storeIDs: [.gizmoSnapshot]
                ) {
                    defaults.removeObject(forKey: storageKey)
                    KeyboardSharedPreferences.sync()
                }
                return nil
            }
            return snapshot
        }
    }

    static func clear(defaults: UserDefaults = sharedDefaults) {
        _ = queue.sync {
            HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                storeIDs: [.gizmoSnapshot]
            ) {
                defaults.removeObject(forKey: storageKey)
                KeyboardSharedPreferences.sync()
            }
        }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

enum HWKAutobotInputModality: String, Codable, Equatable {
    case touch
    case hardware
    case glide
}

struct HWKAutobotInputOriginTracker {
    private var explicitModality: HWKAutobotInputModality?

    mutating func record(_ modality: HWKAutobotInputModality) {
        explicitModality = modality
    }

    mutating func reset() {
        explicitModality = nil
    }

    func resolved(fallback: HWKAutobotInputModality) -> HWKAutobotInputModality {
        explicitModality ?? fallback
    }
}

enum HWKAutobotEpisodeLanguage: String, Codable, Equatable {
    case english
    case englishCodeSwitch
    case romanizedNonEnglish
    case ambiguous
    case noSpaceScript

    private static let latinLanguageCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 32
        return cache
    }()
    private static let latinCodeSwitchCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 32
        return cache
    }()

    var allowsBoundedEnglishLearning: Bool {
        self == .english || self == .englishCodeSwitch
    }

    static func classify(prefix: String) -> HWKAutobotEpisodeLanguage {
        let bounded = String(prefix.suffix(512))
        let full = scriptSignals(in: bounded)
        let activeClause = bounded.split(
            omittingEmptySubsequences: false,
            whereSeparator: { ".!?;:\n。！？".contains($0) }
        ).last.map(String.init) ?? bounded
        let active = scriptSignals(in: activeClause)
        if active.hasRomanizedNonEnglishSignal {
            return .romanizedNonEnglish
        }
        if !full.hasLatin, full.hasNoSpaceScript, !full.hasOtherLetters {
            return .noSpaceScript
        }
        if full.hasLatin, !full.hasNoSpaceScript, !full.hasOtherLetters,
           active.asciiWordCount >= 6,
           hasConfidentSameLatinCodeSwitch(activeClause) {
            return .englishCodeSwitch
        }
        if full.hasLatin, !full.hasNoSpaceScript, !full.hasOtherLetters,
           active.asciiWordCount >= 4,
           active.asciiLetterCount >= 18,
           hasConfidentNonEnglishLatinLanguage(activeClause) {
            return .ambiguous
        }
        if full.hasLatin, !full.hasNoSpaceScript, !full.hasOtherLetters,
           !full.hasRomanizedNonEnglishSignal {
            return .english
        }
        if active.hasNoSpaceScript, !active.hasLatin, !active.hasOtherLetters {
            return .noSpaceScript
        }
        if (full.hasNoSpaceScript || full.hasOtherLetters ||
            full.hasRomanizedNonEnglishSignal),
           active.hasLatin,
           !active.hasNoSpaceScript,
           !active.hasOtherLetters,
           active.asciiWordCount >= 3,
           active.asciiLetterCount >= 12 {
            return .englishCodeSwitch
        }
        return .ambiguous
    }

    private struct ScriptSignals {
        var hasLatin = false
        var hasNoSpaceScript = false
        var hasOtherLetters = false
        var asciiLetterCount = 0
        var asciiWordCount = 0
        var hasRomanizedNonEnglishSignal = false
    }

    private static func scriptSignals(in text: String) -> ScriptSignals {
        var signals = ScriptSignals()
        var insideASCIIWord = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let isLatin = (0x0041...0x005A).contains(value)
                || (0x0061...0x007A).contains(value)
                || (0x00C0...0x024F).contains(value)
                || (0x1E00...0x1EFF).contains(value)
            let isNoSpace = (0x0E00...0x0EFF).contains(value)
                || (0x1000...0x109F).contains(value)
                || (0x1780...0x17FF).contains(value)
                || (0x2E80...0x9FFF).contains(value)
                || (0xAC00...0xD7AF).contains(value)
                || (0xF900...0xFAFF).contains(value)
                || (0x20000...0x2FA1F).contains(value)
            if isLatin {
                signals.hasLatin = true
            } else if isNoSpace {
                signals.hasNoSpaceScript = true
            } else if Character(String(scalar)).isLetter {
                signals.hasOtherLetters = true
            }
            let isASCIILetter = (0x0041...0x005A).contains(value)
                || (0x0061...0x007A).contains(value)
            if isASCIILetter {
                signals.asciiLetterCount += 1
                if !insideASCIIWord {
                    signals.asciiWordCount += 1
                    insideASCIIWord = true
                }
            } else if value != 0x0027 && value != 0x2019 {
                insideASCIIWord = false
            }
        }
        signals.hasRomanizedNonEnglishSignal = containsRomanizedNonEnglishSignal(text)
        return signals
    }

    private static func containsRomanizedNonEnglishSignal(_ text: String) -> Bool {
        let arabiziDigits = Set("2356789")
        for token in text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }) {
            let characters = Array(token)
            guard characters.count >= 4,
                  characters.contains(where: { $0.isLetter }) else {
                continue
            }
            let mappedIndexes = characters.indices.filter {
                arabiziDigits.contains(characters[$0])
            }
            guard !mappedIndexes.isEmpty else { continue }
            if mappedIndexes.count >= 2 || mappedIndexes.contains(where: {
                $0 < characters.index(before: characters.endIndex)
            }) {
                return true
            }
        }
        return false
    }

    private static func hasConfidentNonEnglishLatinLanguage(_ text: String) -> Bool {
        let key = latinLanguageCacheKey(text)
        if let cached = latinLanguageCache.object(forKey: key) {
            return cached.boolValue
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let result = hypotheses
            .filter { $0.key != .english }
            .contains { $0.value >= 0.80 }
        latinLanguageCache.setObject(NSNumber(value: result), forKey: key)
        return result
    }

    private static func hasConfidentSameLatinCodeSwitch(_ text: String) -> Bool {
        let key = latinLanguageCacheKey(text)
        if let cached = latinCodeSwitchCache.object(forKey: key) {
            return cached.boolValue
        }
        let tokens = text.split { character in
            !character.isLetter && character != "'" && character != "’"
        }
        guard tokens.count >= 6 else {
            latinCodeSwitchCache.setObject(NSNumber(value: false), forKey: key)
            return false
        }
        let upperBoundary = min(4, tokens.count - 3)
        let result = (2...upperBoundary).contains { boundary in
            let left = confidentLanguage(in: tokens[..<boundary].joined(separator: " "))
            let right = confidentLanguage(in: tokens[boundary...].joined(separator: " "))
            guard let left, let right else { return false }
            return (left == .english) != (right == .english)
        }
        latinCodeSwitchCache.setObject(NSNumber(value: result), forKey: key)
        return result
    }

    private static func confidentLanguage(in text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.languageHypotheses(withMaximum: 1).first.flatMap {
            $0.value >= 0.80 ? $0.key : nil
        }
    }

    private static func latinLanguageCacheKey(_ text: String) -> NSString {
        String(HWKAutobotEpisodeFingerprint.token(text), radix: 16) as NSString
    }
}

enum HWKAutobotScriptEvidence {
    static func containsSupportedNativeScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x0370...0x052F).contains(value) || // Greek, Cyrillic, Armenian
                (0x0590...0x08FF).contains(value) || // Hebrew, Arabic, Syriac
                (0x0900...0x0DFF).contains(value) || // Indic scripts
                (0x0E00...0x0EFF).contains(value) || // Thai, Lao
                (0x10A0...0x10FF).contains(value) || // Georgian
                (0x3040...0x30FF).contains(value) || // Japanese kana
                (0x3400...0x9FFF).contains(value) || // CJK
                (0xAC00...0xD7AF).contains(value) || // Hangul
                (0xFB1D...0xFDFF).contains(value) || // Hebrew/Arabic presentation forms
                (0xFE70...0xFEFF).contains(value)
        }
    }
}

enum HWKAutobotExposureRisk: String, Codable, Equatable {
    case normal
    case email
    case name
    case unknownWord

    var blocksLearning: Bool { self != .normal }

    static func classify(
        prefix: String,
        isEmailField: Bool,
        isNameField: Bool,
        hasUntrustedUnknownWord: Bool
    ) -> HWKAutobotExposureRisk {
        let bounded = String(prefix.suffix(512))
        let token = bounded.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        let atIndex = token.firstIndex(of: "@")
        let hasEmailShape = atIndex.map { index in
            index != token.startIndex
                && token[token.index(after: index)...].contains(".")
        } ?? false
        if isEmailField || hasEmailShape { return .email }
        if isNameField { return .name }
        if hasUntrustedUnknownWord { return .unknownWord }
        return .normal
    }
}

enum HWKAutobotBoundaryRole: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case sentenceStart
    case afterQuestion
    case afterExclamation
    case afterClause
    case continuation
}

struct HWKAutobotLearningContext: Codable, Equatable {
    static let schemeVersion = 1

    let previousTokenFingerprint: UInt64?
    let previousBigramFingerprint: UInt64?
    let boundaryRole: HWKAutobotBoundaryRole

    var fingerprint: UInt64 {
        HWKAutobotEpisodeFingerprint.learningContext(
            previousTokenFingerprint: previousTokenFingerprint,
            previousBigramFingerprint: previousBigramFingerprint,
            boundaryRole: boundaryRole
        )
    }

    static func derive(prefix: String) -> HWKAutobotLearningContext {
        let boundedPrefix = String(prefix.suffix(512))
        let tokens = boundedPrefix.split(whereSeparator: { character in
            !(character.isLetter || character.isNumber || character == "'" || character == "’")
        })
        let previousToken = tokens.last.map(String.init)
        let previousBigram: String?
        if tokens.count >= 2 {
            previousBigram = tokens.suffix(2).map(String.init).joined(separator: " ")
        } else {
            previousBigram = nil
        }

        let trimmed = boundedPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundaryRole: HWKAutobotBoundaryRole
        switch trimmed.last {
        case nil, ".", "…":
            boundaryRole = .sentenceStart
        case "?":
            boundaryRole = .afterQuestion
        case "!":
            boundaryRole = .afterExclamation
        case ",", ":", ";":
            boundaryRole = .afterClause
        default:
            boundaryRole = .continuation
        }

        return HWKAutobotLearningContext(
            previousTokenFingerprint: previousToken.map(HWKAutobotEpisodeFingerprint.token),
            previousBigramFingerprint: previousBigram.map(HWKAutobotEpisodeFingerprint.token),
            boundaryRole: boundaryRole
        )
    }
}

enum HWKAutobotEpisodeOutcome: String, Codable, Equatable {
    case shown
    case accepted
    case ignored
    case delayedRepair
    case undo
    case backspace
    case retype
}

enum HWKAutobotEnglishStyleDimension: UInt8, Codable, CaseIterable, Equatable, Sendable {
    case contractionRegister = 1
    case letterCase = 2
    case apostropheTypography = 3
    case ellipsisTypography = 4
}

enum HWKAutobotEnglishStyleDirection: String, Codable, Equatable {
    case contracted
    case expanded
    case uppercased
    case lowercased
    case typographic
    case plain

    fileprivate var signedPreference: Int {
        switch self {
        case .contracted, .uppercased, .typographic:
            return 1
        case .expanded, .lowercased, .plain:
            return -1
        }
    }
}

struct HWKAutobotEnglishStyleTransition: Codable, Equatable {
    static let schemeVersion = 1

    let schemeVersion: Int
    let dimension: HWKAutobotEnglishStyleDimension
    let direction: HWKAutobotEnglishStyleDirection
    let sourceFingerprint: UInt64
    let replacementFingerprint: UInt64
    private let attestation: UInt64

    fileprivate init(
        dimension: HWKAutobotEnglishStyleDimension,
        direction: HWKAutobotEnglishStyleDirection,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64
    ) {
        self.schemeVersion = Self.schemeVersion
        self.dimension = dimension
        self.direction = direction
        self.sourceFingerprint = sourceFingerprint
        self.replacementFingerprint = replacementFingerprint
        self.attestation = HWKAutobotEpisodeFingerprint.englishStyleTransitionAttestation(
            dimension: dimension,
            direction: direction,
            sourceFingerprint: sourceFingerprint,
            replacementFingerprint: replacementFingerprint
        )
    }

    var isValid: Bool {
        schemeVersion == Self.schemeVersion &&
        sourceFingerprint != replacementFingerprint &&
        attestation == HWKAutobotEpisodeFingerprint.englishStyleTransitionAttestation(
            dimension: dimension,
            direction: direction,
            sourceFingerprint: sourceFingerprint,
            replacementFingerprint: replacementFingerprint
        )
    }

    func isValid(
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64
    ) -> Bool {
        isValid &&
        self.sourceFingerprint == sourceFingerprint &&
        self.replacementFingerprint == replacementFingerprint
    }
}

enum HWKAutobotEnglishStyleClassifier {
    private static let maximumCharacterCount = 256
    private static let maximumUTF8ByteCount = 1_024
    private static let contractionPairs: [(expanded: String, contracted: String)] = [
        ("cannot", "can't"),
        ("do not", "don't"),
        ("does not", "doesn't"),
        ("did not", "didn't"),
        ("is not", "isn't"),
        ("are not", "aren't"),
        ("was not", "wasn't"),
        ("were not", "weren't"),
        ("will not", "won't"),
        ("would not", "wouldn't"),
        ("should not", "shouldn't"),
        ("could not", "couldn't"),
        ("have not", "haven't"),
        ("has not", "hasn't"),
        ("had not", "hadn't"),
        ("must not", "mustn't"),
    ]

    static func transition(
        source: String,
        replacement: String
    ) -> HWKAutobotEnglishStyleTransition? {
        guard let canonicalSource = boundedCanonical(source),
              let canonicalReplacement = boundedCanonical(replacement),
              canonicalSource != canonicalReplacement else {
            return nil
        }

        var matches = [(HWKAutobotEnglishStyleDimension, HWKAutobotEnglishStyleDirection)]()
        if let direction = singleASCIICaseDirection(
            source: canonicalSource,
            target: canonicalReplacement
        ) {
            matches.append((.letterCase, direction))
        }
        if let direction = exactSingleGlyphDirection(
            source: canonicalSource,
            target: canonicalReplacement,
            plain: "'",
            typographic: "’"
        ) {
            matches.append((.apostropheTypography, direction))
        }
        if isSingleExactSubstitution(
            source: canonicalSource,
            target: canonicalReplacement,
            needle: "...",
            substitute: "…"
        ) {
            matches.append((.ellipsisTypography, .typographic))
        }
        if isSingleExactSubstitution(
            source: canonicalSource,
            target: canonicalReplacement,
            needle: "…",
            substitute: "..."
        ) {
            matches.append((.ellipsisTypography, .plain))
        }

        if canonicalSource.count != canonicalReplacement.count,
           let normalizedSource = normalized(canonicalSource),
           let normalizedReplacement = normalized(canonicalReplacement),
           normalizedSource != normalizedReplacement {
            for pair in contractionPairs {
                if isSingleEquivalentSubstitution(
                    source: normalizedSource,
                    target: normalizedReplacement,
                    needle: pair.expanded,
                    substitute: pair.contracted
                ) {
                    matches.append((.contractionRegister, .contracted))
                }
                if isSingleEquivalentSubstitution(
                    source: normalizedSource,
                    target: normalizedReplacement,
                    needle: pair.contracted,
                    substitute: pair.expanded
                ) {
                    matches.append((.contractionRegister, .expanded))
                }
            }
        }
        guard matches.count == 1, let match = matches.first else {
            return nil
        }
        let usesStyleSensitiveTokenIdentity = match.0 == .letterCase
        return HWKAutobotEnglishStyleTransition(
            dimension: match.0,
            direction: match.1,
            sourceFingerprint: usesStyleSensitiveTokenIdentity
                ? HWKAutobotEpisodeFingerprint.englishStyleToken(source)
                : HWKAutobotEpisodeFingerprint.token(source),
            replacementFingerprint: usesStyleSensitiveTokenIdentity
                ? HWKAutobotEpisodeFingerprint.englishStyleToken(replacement)
                : HWKAutobotEpisodeFingerprint.token(replacement)
        )
    }

    private static func boundedCanonical(_ text: String) -> String? {
        guard !text.isEmpty,
              text.utf8.index(
                text.utf8.startIndex,
                offsetBy: maximumUTF8ByteCount + 1,
                limitedBy: text.utf8.endIndex
              ) == nil,
              text.index(
                text.startIndex,
                offsetBy: maximumCharacterCount + 1,
                limitedBy: text.endIndex
              ) == nil else {
            return nil
        }
        let canonical = text.precomposedStringWithCanonicalMapping
        guard !canonical.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0)
        }) else {
            return nil
        }
        return canonical
    }

    private static func singleASCIICaseDirection(
        source: String,
        target: String
    ) -> HWKAutobotEnglishStyleDirection? {
        guard source.count == target.count else { return nil }
        var direction: HWKAutobotEnglishStyleDirection?
        for (sourceCharacter, targetCharacter) in zip(source, target) {
            guard sourceCharacter != targetCharacter else { continue }
            guard direction == nil,
                  let sourceASCII = asciiLetter(sourceCharacter),
                  let targetASCII = asciiLetter(targetCharacter),
                  asciiLowercased(sourceASCII) == asciiLowercased(targetASCII),
                  asciiIsUppercase(sourceASCII) != asciiIsUppercase(targetASCII) else {
                return nil
            }
            direction = asciiIsUppercase(targetASCII) ? .uppercased : .lowercased
        }
        return direction
    }

    private static func exactSingleGlyphDirection(
        source: String,
        target: String,
        plain: Character,
        typographic: Character
    ) -> HWKAutobotEnglishStyleDirection? {
        guard source.count == target.count else { return nil }
        var direction: HWKAutobotEnglishStyleDirection?
        for (sourceCharacter, targetCharacter) in zip(source, target) {
            guard sourceCharacter != targetCharacter else { continue }
            guard direction == nil else { return nil }
            if sourceCharacter == plain && targetCharacter == typographic {
                direction = .typographic
            } else if sourceCharacter == typographic && targetCharacter == plain {
                direction = .plain
            } else {
                return nil
            }
        }
        return direction
    }

    private static func asciiLetter(_ character: Character) -> UInt32? {
        guard character.unicodeScalars.count == 1,
              let value = character.unicodeScalars.first?.value,
              (65...90).contains(value) || (97...122).contains(value) else {
            return nil
        }
        return value
    }

    private static func asciiLowercased(_ value: UInt32) -> UInt32 {
        asciiIsUppercase(value) ? value + 32 : value
    }

    private static func asciiIsUppercase(_ value: UInt32) -> Bool {
        (65...90).contains(value)
    }

    private static func normalized(_ text: String) -> String? {
        let withoutControls = text.components(separatedBy: .controlCharacters).joined()
        guard withoutControls.count == text.count else { return nil }
        let normalizedApostrophe = withoutControls
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .lowercased()
        let collapsed = normalizedApostrophe
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func isSingleEquivalentSubstitution(
        source: String,
        target: String,
        needle: String,
        substitute: String
    ) -> Bool {
        var searchStart = source.startIndex
        var matchCount = 0
        while searchStart < source.endIndex,
              let range = source.range(
                of: needle,
                range: searchStart..<source.endIndex
              ) {
            if hasWordBoundaries(in: source, around: range) {
                var candidate = source
                candidate.replaceSubrange(range, with: substitute)
                if candidate == target {
                    matchCount += 1
                }
            }
            searchStart = range.upperBound
        }
        return matchCount == 1
    }

    private static func isSingleExactSubstitution(
        source: String,
        target: String,
        needle: String,
        substitute: String
    ) -> Bool {
        var searchStart = source.startIndex
        var matchCount = 0
        while searchStart < source.endIndex,
              let range = source.range(
                of: needle,
                range: searchStart..<source.endIndex
              ) {
            var candidate = source
            candidate.replaceSubrange(range, with: substitute)
            if candidate == target {
                matchCount += 1
            }
            searchStart = range.upperBound
        }
        return matchCount == 1
    }

    private static func hasWordBoundaries(
        in text: String,
        around range: Range<String.Index>
    ) -> Bool {
        let previous = range.lowerBound > text.startIndex
            ? text[text.index(before: range.lowerBound)]
            : nil
        let next = range.upperBound < text.endIndex ? text[range.upperBound] : nil
        return (previous.map { !isWordCharacter($0) } ?? true) &&
            (next.map { !isWordCharacter($0) } ?? true)
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
    }
}

enum HWKAutobotSuggestionSurfaceCandidateKind: UInt8, Codable, Equatable {
    case completion = 1
    case correction = 2
    case replacement = 3
    case saveWord = 4
}

enum HWKAutobotSuggestionSurfaceSourceFamily: UInt8, Codable, Equatable {
    case previousWord = 1
    case prefixCompletion = 2
    case correction = 3
    case saved = 4
    case punctuation = 5
    case action = 6
}

struct HWKAutobotSuggestionScoreEvidence: Equatable {
    let surfaceNeutralScore: Double
    let surfaceChampionDelta: Double
    let modelNeutralScore: Double
    let modelChampionDelta: Double
    let stableOrdinal: Int
    let modelAdjustmentEligible: Bool

    init(
        surfaceNeutralScore: Double,
        surfaceChampionDelta: Double,
        modelNeutralScore: Double,
        modelChampionDelta: Double,
        stableOrdinal: Int,
        modelAdjustmentEligible: Bool = false
    ) {
        self.surfaceNeutralScore = surfaceNeutralScore
        self.surfaceChampionDelta = surfaceChampionDelta
        self.modelNeutralScore = modelNeutralScore
        self.modelChampionDelta = modelChampionDelta
        self.stableOrdinal = stableOrdinal
        self.modelAdjustmentEligible = modelAdjustmentEligible
    }

    var isValid: Bool {
        surfaceNeutralScore.isFinite &&
            surfaceChampionDelta.isFinite &&
            modelNeutralScore.isFinite &&
            modelChampionDelta.isFinite &&
            stableOrdinal >= 0 && stableOrdinal < 256 &&
            Self.micropoints(surfaceNeutralScore) != nil &&
            Self.micropoints(surfaceChampionDelta) != nil &&
            Self.micropoints(modelNeutralScore) != nil &&
            Self.micropoints(modelChampionDelta) != nil
    }

    static func micropoints(_ score: Double) -> Int32? {
        guard score.isFinite else { return nil }
        let scaled = (score * 1_000_000).rounded()
        guard scaled >= Double(Int32.min), scaled <= Double(Int32.max) else { return nil }
        return Int32(scaled)
    }
}

struct HWKAutobotSuggestionModelBinding: Equatable {
    let sourceFingerprint: UInt64
    let replacementFingerprint: UInt64
    let learningContextFingerprint: UInt64?
    let boundaryRole: HWKAutobotBoundaryRole?
    let styleTransition: HWKAutobotEnglishStyleTransition?
    let evidenceSource: HWKAutobotCandidateEvidenceSource?

    init?(
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64,
        learningContext: HWKAutobotLearningContext?,
        styleTransition: HWKAutobotEnglishStyleTransition?,
        evidenceSource: HWKAutobotCandidateEvidenceSource? = nil
    ) {
        self.init(
            sourceFingerprint: sourceFingerprint,
            replacementFingerprint: replacementFingerprint,
            learningContextFingerprint: learningContext?.fingerprint,
            boundaryRole: learningContext?.boundaryRole,
            styleTransition: styleTransition,
            evidenceSource: evidenceSource
        )
    }

    fileprivate init?(
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64,
        learningContextFingerprint: UInt64?,
        boundaryRole: HWKAutobotBoundaryRole?,
        styleTransition: HWKAutobotEnglishStyleTransition?,
        evidenceSource: HWKAutobotCandidateEvidenceSource?
    ) {
        guard sourceFingerprint != 0,
              replacementFingerprint != 0,
              sourceFingerprint != replacementFingerprint,
              (learningContextFingerprint == nil) == (boundaryRole == nil),
              learningContextFingerprint.map({ $0 != 0 }) ?? true,
              styleTransition?.isValid(
                  sourceFingerprint: sourceFingerprint,
                  replacementFingerprint: replacementFingerprint
              ) ?? true else {
            return nil
        }
        self.sourceFingerprint = sourceFingerprint
        self.replacementFingerprint = replacementFingerprint
        self.learningContextFingerprint = learningContextFingerprint
        self.boundaryRole = boundaryRole
        self.styleTransition = styleTransition
        self.evidenceSource = evidenceSource
    }
}

struct HWKAutobotSuggestionProjectionCandidate: Equatable {
    let candidateID: UInt64
    let uniqueKeyFingerprint: UInt64
    let visibleReplacementFingerprint: UInt64
    let surfaceNeutralScoreMicropoints: Int32
    let surfaceChampionDeltaMicropoints: Int32
    let modelNeutralScoreMicropoints: Int32
    let modelChampionDeltaMicropoints: Int32
    let preferredLaneMask: UInt16
    let allowedLaneMask: UInt16
    let sourceFamily: HWKAutobotSuggestionSurfaceSourceFamily
    let kind: HWKAutobotSuggestionSurfaceCandidateKind
    let genericFallbackEligible: Bool
    let stableOrdinal: UInt8
    let modelBinding: HWKAutobotSuggestionModelBinding?

    init?(
        candidateID: UInt64,
        uniqueKeyFingerprint: UInt64,
        visibleReplacementFingerprint: UInt64,
        scoreEvidence: HWKAutobotSuggestionScoreEvidence,
        preferredLaneMask: UInt16,
        allowedLaneMask: UInt16,
        sourceFamily: HWKAutobotSuggestionSurfaceSourceFamily,
        kind: HWKAutobotSuggestionSurfaceCandidateKind,
        genericFallbackEligible: Bool,
        modelBinding: HWKAutobotSuggestionModelBinding? = nil
    ) {
        guard candidateID != 0,
              uniqueKeyFingerprint != 0,
              visibleReplacementFingerprint != 0,
              scoreEvidence.isValid,
              preferredLaneMask & ~allowedLaneMask == 0,
              let surfaceNeutralScoreMicropoints =
                  HWKAutobotSuggestionScoreEvidence.micropoints(scoreEvidence.surfaceNeutralScore),
              let surfaceChampionDeltaMicropoints =
                  HWKAutobotSuggestionScoreEvidence.micropoints(scoreEvidence.surfaceChampionDelta),
              let modelNeutralScoreMicropoints =
                  HWKAutobotSuggestionScoreEvidence.micropoints(scoreEvidence.modelNeutralScore),
              let modelChampionDeltaMicropoints =
                  HWKAutobotSuggestionScoreEvidence.micropoints(scoreEvidence.modelChampionDelta),
              let stableOrdinal = UInt8(exactly: scoreEvidence.stableOrdinal),
              scoreEvidence.modelAdjustmentEligible == (modelBinding != nil) else {
            return nil
        }
        self.candidateID = candidateID
        self.uniqueKeyFingerprint = uniqueKeyFingerprint
        self.visibleReplacementFingerprint = visibleReplacementFingerprint
        self.surfaceNeutralScoreMicropoints = surfaceNeutralScoreMicropoints
        self.surfaceChampionDeltaMicropoints = surfaceChampionDeltaMicropoints
        self.modelNeutralScoreMicropoints = modelNeutralScoreMicropoints
        self.modelChampionDeltaMicropoints = modelChampionDeltaMicropoints
        self.preferredLaneMask = preferredLaneMask
        self.allowedLaneMask = allowedLaneMask
        self.sourceFamily = sourceFamily
        self.kind = kind
        self.genericFallbackEligible = genericFallbackEligible
        self.stableOrdinal = stableOrdinal
        self.modelBinding = modelBinding
    }

    fileprivate init(
        candidateID: UInt64,
        uniqueKeyFingerprint: UInt64,
        visibleReplacementFingerprint: UInt64,
        surfaceNeutralScoreMicropoints: Int32,
        surfaceChampionDeltaMicropoints: Int32,
        modelNeutralScoreMicropoints: Int32,
        modelChampionDeltaMicropoints: Int32,
        preferredLaneMask: UInt16,
        allowedLaneMask: UInt16,
        sourceFamily: HWKAutobotSuggestionSurfaceSourceFamily,
        kind: HWKAutobotSuggestionSurfaceCandidateKind,
        genericFallbackEligible: Bool,
        stableOrdinal: UInt8,
        modelBinding: HWKAutobotSuggestionModelBinding?
    ) {
        self.candidateID = candidateID
        self.uniqueKeyFingerprint = uniqueKeyFingerprint
        self.visibleReplacementFingerprint = visibleReplacementFingerprint
        self.surfaceNeutralScoreMicropoints = surfaceNeutralScoreMicropoints
        self.surfaceChampionDeltaMicropoints = surfaceChampionDeltaMicropoints
        self.modelNeutralScoreMicropoints = modelNeutralScoreMicropoints
        self.modelChampionDeltaMicropoints = modelChampionDeltaMicropoints
        self.preferredLaneMask = preferredLaneMask
        self.allowedLaneMask = allowedLaneMask
        self.sourceFamily = sourceFamily
        self.kind = kind
        self.genericFallbackEligible = genericFallbackEligible
        self.stableOrdinal = stableOrdinal
        self.modelBinding = modelBinding
    }
}

struct HWKAutobotSuggestionProjectionTrace: Codable, Equatable {
    static let schemeVersion: UInt8 = 4
    private static let legacySchemeVersions: Set<UInt8> = [1, 2, 3]
    static let maximumCandidateCount = 21
    private static let legacyRecordByteCount = 48
    private static let schemeThreeRecordByteCount = 91
    private static let recordByteCount = 92
    private static let genericFallbackFlag: UInt8 = 1 << 0
    private static let modelAdjustmentFlag: UInt8 = 1 << 1
    private static let styleTransitionFlag: UInt8 = 1 << 2

    let encodedSchemeVersion: UInt8
    let visibleLaneCount: Int
    let candidates: [HWKAutobotSuggestionProjectionCandidate]

    var supportsDirectModelAdjustments: Bool {
        encodedSchemeVersion == Self.schemeVersion
    }

    var isValid: Bool {
        guard Self.legacySchemeVersions.union([Self.schemeVersion]).contains(encodedSchemeVersion),
              HWKAutobotSuggestionSurface.supportedVisibleLaneCounts.contains(visibleLaneCount),
              !candidates.isEmpty,
              candidates.count <= Self.maximumCandidateCount,
              Set(candidates.map(\.candidateID)).count == candidates.count,
              Set(candidates.map(\.uniqueKeyFingerprint)).count == candidates.count,
              Set(candidates.map(\.stableOrdinal)).count == candidates.count else {
            return false
        }
        let supportedMask = UInt16((1 << visibleLaneCount) - 1)
        guard candidates.allSatisfy({ candidate in
            candidate.preferredLaneMask & ~candidate.allowedLaneMask == 0 &&
                candidate.preferredLaneMask & ~supportedMask == 0 &&
                candidate.allowedLaneMask & ~supportedMask == 0 &&
                Int(candidate.stableOrdinal) < candidates.count &&
                modelBindingIsValid(candidate)
        }) else {
            return false
        }
        return replayedCandidateIDs().contains { $0 != nil }
    }

    private func modelBindingIsValid(
        _ candidate: HWKAutobotSuggestionProjectionCandidate
    ) -> Bool {
        guard encodedSchemeVersion == Self.schemeVersion else {
            return candidate.modelBinding == nil
        }
        if candidate.modelBinding != nil {
            return (candidate.kind == .correction || candidate.kind == .replacement) &&
                candidate.modelChampionDeltaMicropoints ==
                    candidate.surfaceChampionDeltaMicropoints
        }
        return candidate.modelChampionDeltaMicropoints == 0 &&
            candidate.surfaceChampionDeltaMicropoints == 0
    }

    private static func boundaryRole(rawValue: UInt8) -> HWKAutobotBoundaryRole? {
        switch rawValue {
        case 1: return .sentenceStart
        case 2: return .afterQuestion
        case 3: return .afterExclamation
        case 4: return .afterClause
        case 5: return .continuation
        default: return nil
        }
    }

    private static func rawValue(for boundaryRole: HWKAutobotBoundaryRole) -> UInt8 {
        switch boundaryRole {
        case .sentenceStart: return 1
        case .afterQuestion: return 2
        case .afterExclamation: return 3
        case .afterClause: return 4
        case .continuation: return 5
        }
    }

    private static func styleDirection(
        rawValue: UInt8
    ) -> HWKAutobotEnglishStyleDirection? {
        switch rawValue {
        case 1: return .contracted
        case 2: return .expanded
        case 3: return .uppercased
        case 4: return .lowercased
        case 5: return .typographic
        case 6: return .plain
        default: return nil
        }
    }

    private static func rawValue(
        for direction: HWKAutobotEnglishStyleDirection
    ) -> UInt8 {
        switch direction {
        case .contracted: return 1
        case .expanded: return 2
        case .uppercased: return 3
        case .lowercased: return 4
        case .typographic: return 5
        case .plain: return 6
        }
    }

    private static func evidenceSource(
        rawValue: UInt8
    ) -> HWKAutobotCandidateEvidenceSource? {
        switch rawValue {
        case 1: return .dictionary
        case 2: return .savedWord
        case 3: return .nativeSpellChecker
        case 4: return .foundationModel
        case 5: return .rule
        default: return nil
        }
    }

    private static func rawValue(
        for evidenceSource: HWKAutobotCandidateEvidenceSource
    ) -> UInt8 {
        switch evidenceSource {
        case .dictionary: return 1
        case .savedWord: return 2
        case .nativeSpellChecker: return 3
        case .foundationModel: return 4
        case .rule: return 5
        }
    }

    func replayedCandidateIDs(
        replacingChampionDeltasMicropoints replacements: [UInt64: Int32] = [:]
    ) -> [UInt64?] {
        guard HWKAutobotSuggestionSurface.supportedVisibleLaneCounts.contains(visibleLaneCount),
              !candidates.isEmpty,
              candidates.count <= Self.maximumCandidateCount else {
            return []
        }
        let ranked = candidates.sorted { lhs, rhs in
            let lhsDelta = replacements[lhs.candidateID] ?? lhs.surfaceChampionDeltaMicropoints
            let rhsDelta = replacements[rhs.candidateID] ?? rhs.surfaceChampionDeltaMicropoints
            let lhsScore = Int64(lhs.surfaceNeutralScoreMicropoints) + Int64(lhsDelta)
            let rhsScore = Int64(rhs.surfaceNeutralScoreMicropoints) + Int64(rhsDelta)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
            if lhs.surfaceNeutralScoreMicropoints != rhs.surfaceNeutralScoreMicropoints {
                return lhs.surfaceNeutralScoreMicropoints > rhs.surfaceNeutralScoreMicropoints
            }
            if lhs.stableOrdinal != rhs.stableOrdinal {
                return lhs.stableOrdinal < rhs.stableOrdinal
            }
            return lhs.candidateID < rhs.candidateID
        }
        var usedUniqueKeys = Set<UInt64>()
        var usedVisibleKeys = Set<UInt64>()
        var usedSourceFamilies = Set<HWKAutobotSuggestionSurfaceSourceFamily>()
        var selected = Array<HWKAutobotSuggestionProjectionCandidate?>(
            repeating: nil,
            count: visibleLaneCount
        )

        func firstUnused(
            _ pool: [HWKAutobotSuggestionProjectionCandidate]
        ) -> HWKAutobotSuggestionProjectionCandidate? {
            if let distinct = pool.first(where: { candidate in
                !usedUniqueKeys.contains(candidate.uniqueKeyFingerprint) &&
                    !usedVisibleKeys.contains(candidate.visibleReplacementFingerprint) &&
                    !usedSourceFamilies.contains(candidate.sourceFamily)
            }) {
                return distinct
            }
            return pool.first { candidate in
                !usedUniqueKeys.contains(candidate.uniqueKeyFingerprint) &&
                    !usedVisibleKeys.contains(candidate.visibleReplacementFingerprint)
            }
        }

        func select(
            _ candidate: HWKAutobotSuggestionProjectionCandidate,
            laneIndex: Int
        ) {
            selected[laneIndex] = candidate
            usedUniqueKeys.insert(candidate.uniqueKeyFingerprint)
            usedVisibleKeys.insert(candidate.visibleReplacementFingerprint)
            usedSourceFamilies.insert(candidate.sourceFamily)
        }

        for laneIndex in 0..<visibleLaneCount {
            let laneBit = UInt16(1 << laneIndex)
            let preferred = ranked.filter { $0.preferredLaneMask & laneBit != 0 }
            if let candidate = firstUnused(preferred) {
                select(candidate, laneIndex: laneIndex)
            }
        }
        for laneIndex in 0..<visibleLaneCount where selected[laneIndex] == nil {
            let laneBit = UInt16(1 << laneIndex)
            let allowed = ranked.filter { $0.allowedLaneMask & laneBit != 0 }
            let fallback = allowed.isEmpty
                ? ranked.filter(\.genericFallbackEligible)
                : allowed
            if let candidate = firstUnused(fallback) {
                select(candidate, laneIndex: laneIndex)
            }
        }
        return selected.map { $0?.candidateID }
    }

    init(visibleLaneCount: Int, candidates: [HWKAutobotSuggestionProjectionCandidate]) {
        self.encodedSchemeVersion = Self.schemeVersion
        self.visibleLaneCount = visibleLaneCount
        self.candidates = candidates
    }

    private init(
        encodedSchemeVersion: UInt8,
        visibleLaneCount: Int,
        candidates: [HWKAutobotSuggestionProjectionCandidate]
    ) {
        self.encodedSchemeVersion = encodedSchemeVersion
        self.visibleLaneCount = visibleLaneCount
        self.candidates = candidates
    }

    init(from decoder: Decoder) throws {
        let data = try decoder.singleValueContainer().decode(Data.self)
        guard data.count >= 3,
              Self.legacySchemeVersions.union([Self.schemeVersion]).contains(data[0]) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported projection trace.")
            )
        }
        let encodedSchemeVersion = data[0]
        let visibleLaneCount = Int(data[1])
        let candidateCount = Int(data[2])
        let recordByteCount: Int
        switch encodedSchemeVersion {
        case Self.schemeVersion:
            recordByteCount = Self.recordByteCount
        case 3:
            recordByteCount = Self.schemeThreeRecordByteCount
        default:
            recordByteCount = Self.legacyRecordByteCount
        }
        guard candidateCount > 0,
              candidateCount <= Self.maximumCandidateCount,
              data.count == 3 + candidateCount * recordByteCount else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection trace size.")
            )
        }
        var offset = 3
        func readUInt64() -> UInt64 {
            defer { offset += 8 }
            return data[offset..<(offset + 8)].reduce(into: UInt64(0)) {
                $0 = ($0 << 8) | UInt64($1)
            }
        }
        func readUInt32() -> UInt32 {
            defer { offset += 4 }
            return data[offset..<(offset + 4)].reduce(into: UInt32(0)) {
                $0 = ($0 << 8) | UInt32($1)
            }
        }
        func readUInt16() -> UInt16 {
            defer { offset += 2 }
            return data[offset..<(offset + 2)].reduce(into: UInt16(0)) {
                $0 = ($0 << 8) | UInt16($1)
            }
        }
        var candidates = [HWKAutobotSuggestionProjectionCandidate]()
        for _ in 0..<candidateCount {
            let candidateID = readUInt64()
            let uniqueKeyFingerprint = readUInt64()
            let visibleReplacementFingerprint = readUInt64()
            let surfaceNeutralScore = Int32(bitPattern: readUInt32())
            let surfaceChampionDelta = Int32(bitPattern: readUInt32())
            let modelNeutralScore = Int32(bitPattern: readUInt32())
            let modelChampionDelta = Int32(bitPattern: readUInt32())
            let preferredLaneMask = readUInt16()
            let allowedLaneMask = readUInt16()
            let flags = data[offset + 2]
            guard let sourceFamily = HWKAutobotSuggestionSurfaceSourceFamily(rawValue: data[offset]),
                  let kind = HWKAutobotSuggestionSurfaceCandidateKind(rawValue: data[offset + 1]),
                  (encodedSchemeVersion >= 3
                    ? flags & ~(Self.genericFallbackFlag |
                        Self.modelAdjustmentFlag |
                        Self.styleTransitionFlag) == 0
                    : flags <= Self.genericFallbackFlag) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection candidate.")
                )
            }
            let genericFallbackEligible = flags & Self.genericFallbackFlag != 0
            let stableOrdinal = data[offset + 3]
            offset += 4
            var modelBinding: HWKAutobotSuggestionModelBinding?
            if encodedSchemeVersion >= 3 {
                let sourceFingerprint = readUInt64()
                let replacementFingerprint = readUInt64()
                let learningContextFingerprint = readUInt64()
                let styleAttestation = readUInt64()
                let boundaryRoleRawValue = data[offset]
                let styleDimensionRawValue = data[offset + 1]
                let styleDirectionRawValue = data[offset + 2]
                offset += 3
                let evidenceSourceRawValue = encodedSchemeVersion == Self.schemeVersion
                    ? data[offset]
                    : 0
                if encodedSchemeVersion == Self.schemeVersion {
                    offset += 1
                }
                let bindingAttestation = readUInt64()
                let modelAdjustmentEligible = flags & Self.modelAdjustmentFlag != 0
                let hasStyleTransition = flags & Self.styleTransitionFlag != 0
                if modelAdjustmentEligible {
                    let decodedLearningContextFingerprint = learningContextFingerprint == 0
                        ? nil
                        : learningContextFingerprint
                    let boundaryRole = boundaryRoleRawValue == 0
                        ? nil
                        : Self.boundaryRole(rawValue: boundaryRoleRawValue)
                    guard (learningContextFingerprint == 0) == (boundaryRoleRawValue == 0),
                          boundaryRoleRawValue == 0 || boundaryRole != nil else {
                        throw DecodingError.dataCorrupted(
                            .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection context binding.")
                        )
                    }
                    let styleTransition: HWKAutobotEnglishStyleTransition?
                    if hasStyleTransition {
                        guard let dimension = HWKAutobotEnglishStyleDimension(
                            rawValue: styleDimensionRawValue
                        ),
                        let direction = Self.styleDirection(rawValue: styleDirectionRawValue),
                        styleAttestation ==
                            HWKAutobotEpisodeFingerprint.englishStyleTransitionAttestation(
                                dimension: dimension,
                                direction: direction,
                                sourceFingerprint: sourceFingerprint,
                                replacementFingerprint: replacementFingerprint
                            ) else {
                            throw DecodingError.dataCorrupted(
                                .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection style binding.")
                            )
                        }
                        styleTransition = HWKAutobotEnglishStyleTransition(
                            dimension: dimension,
                            direction: direction,
                            sourceFingerprint: sourceFingerprint,
                            replacementFingerprint: replacementFingerprint
                        )
                    } else {
                        guard styleAttestation == 0,
                              styleDimensionRawValue == 0,
                              styleDirectionRawValue == 0 else {
                            throw DecodingError.dataCorrupted(
                                .init(codingPath: decoder.codingPath, debugDescription: "Unexpected projection style binding.")
                            )
                        }
                        styleTransition = nil
                    }
                    let evidenceSource: HWKAutobotCandidateEvidenceSource?
                    if evidenceSourceRawValue == 0 {
                        evidenceSource = nil
                    } else {
                        guard let decoded = Self.evidenceSource(rawValue: evidenceSourceRawValue) else {
                            throw DecodingError.dataCorrupted(
                                .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection evidence source.")
                            )
                        }
                        evidenceSource = decoded
                    }
                    guard let binding = HWKAutobotSuggestionModelBinding(
                        sourceFingerprint: sourceFingerprint,
                        replacementFingerprint: replacementFingerprint,
                        learningContextFingerprint: decodedLearningContextFingerprint,
                        boundaryRole: boundaryRole,
                        styleTransition: styleTransition,
                        evidenceSource: evidenceSource
                    ),
                    bindingAttestation == (encodedSchemeVersion == Self.schemeVersion
                        ?
                        HWKAutobotEpisodeFingerprint.suggestionModelBindingAttestation(
                            candidateID: candidateID,
                            sourceFingerprint: sourceFingerprint,
                            replacementFingerprint: replacementFingerprint,
                            learningContextFingerprint: decodedLearningContextFingerprint,
                            boundaryRole: boundaryRole,
                            styleTransition: styleTransition,
                            evidenceSource: evidenceSource
                        )
                        : HWKAutobotEpisodeFingerprint.suggestionModelBindingAttestation(
                            candidateID: candidateID,
                            sourceFingerprint: sourceFingerprint,
                            replacementFingerprint: replacementFingerprint,
                            learningContextFingerprint: decodedLearningContextFingerprint,
                            boundaryRole: boundaryRole,
                            styleTransition: styleTransition
                        )) else {
                        throw DecodingError.dataCorrupted(
                            .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection model binding.")
                        )
                    }
                    modelBinding = encodedSchemeVersion == Self.schemeVersion ? binding : nil
                } else {
                    guard !hasStyleTransition,
                          sourceFingerprint == 0,
                          replacementFingerprint == 0,
                          learningContextFingerprint == 0,
                          styleAttestation == 0,
                          boundaryRoleRawValue == 0,
                          styleDimensionRawValue == 0,
                          styleDirectionRawValue == 0,
                          evidenceSourceRawValue == 0,
                          bindingAttestation == 0 else {
                        throw DecodingError.dataCorrupted(
                            .init(codingPath: decoder.codingPath, debugDescription: "Unexpected projection model binding.")
                        )
                    }
                    modelBinding = nil
                }
            } else {
                modelBinding = nil
            }
            candidates.append(HWKAutobotSuggestionProjectionCandidate(
                candidateID: candidateID,
                uniqueKeyFingerprint: uniqueKeyFingerprint,
                visibleReplacementFingerprint: visibleReplacementFingerprint,
                surfaceNeutralScoreMicropoints: surfaceNeutralScore,
                surfaceChampionDeltaMicropoints: surfaceChampionDelta,
                modelNeutralScoreMicropoints: modelNeutralScore,
                modelChampionDeltaMicropoints: modelChampionDelta,
                preferredLaneMask: preferredLaneMask,
                allowedLaneMask: allowedLaneMask,
                sourceFamily: sourceFamily,
                kind: kind,
                genericFallbackEligible: genericFallbackEligible,
                stableOrdinal: stableOrdinal,
                modelBinding: modelBinding
            ))
        }
        let trace = Self(
            encodedSchemeVersion: encodedSchemeVersion,
            visibleLaneCount: visibleLaneCount,
            candidates: candidates
        )
        guard trace.isValid else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid projection trace invariants.")
            )
        }
        self = trace
    }

    func encode(to encoder: Encoder) throws {
        guard isValid else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: encoder.codingPath, debugDescription: "Invalid projection trace.")
            )
        }
        var data = Data([encodedSchemeVersion, UInt8(visibleLaneCount), UInt8(candidates.count)])
        func append<T: FixedWidthInteger>(_ value: T) {
            var bigEndian = value.bigEndian
            withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
        }
        for candidate in candidates {
            append(candidate.candidateID)
            append(candidate.uniqueKeyFingerprint)
            append(candidate.visibleReplacementFingerprint)
            append(UInt32(bitPattern: candidate.surfaceNeutralScoreMicropoints))
            append(UInt32(bitPattern: candidate.surfaceChampionDeltaMicropoints))
            append(UInt32(bitPattern: candidate.modelNeutralScoreMicropoints))
            append(UInt32(bitPattern: candidate.modelChampionDeltaMicropoints))
            append(candidate.preferredLaneMask)
            append(candidate.allowedLaneMask)
            data.append(candidate.sourceFamily.rawValue)
            data.append(candidate.kind.rawValue)
            var flags = candidate.genericFallbackEligible
                ? Self.genericFallbackFlag
                : 0
            if encodedSchemeVersion == Self.schemeVersion,
               let binding = candidate.modelBinding {
                flags |= Self.modelAdjustmentFlag
                if binding.styleTransition != nil {
                    flags |= Self.styleTransitionFlag
                }
            }
            data.append(flags)
            data.append(candidate.stableOrdinal)
            if encodedSchemeVersion == Self.schemeVersion {
                guard let binding = candidate.modelBinding else {
                    append(UInt64(0))
                    append(UInt64(0))
                    append(UInt64(0))
                    append(UInt64(0))
                    data.append(0)
                    data.append(0)
                    data.append(0)
                    data.append(0)
                    append(UInt64(0))
                    continue
                }
                append(binding.sourceFingerprint)
                append(binding.replacementFingerprint)
                append(binding.learningContextFingerprint ?? 0)
                if let transition = binding.styleTransition {
                    append(HWKAutobotEpisodeFingerprint.englishStyleTransitionAttestation(
                        dimension: transition.dimension,
                        direction: transition.direction,
                        sourceFingerprint: binding.sourceFingerprint,
                        replacementFingerprint: binding.replacementFingerprint
                    ))
                } else {
                    append(UInt64(0))
                }
                data.append(binding.boundaryRole.map(Self.rawValue(for:)) ?? 0)
                data.append(binding.styleTransition?.dimension.rawValue ?? 0)
                data.append(binding.styleTransition.map {
                    Self.rawValue(for: $0.direction)
                } ?? 0)
                data.append(binding.evidenceSource.map(Self.rawValue(for:)) ?? 0)
                append(HWKAutobotEpisodeFingerprint.suggestionModelBindingAttestation(
                    candidateID: candidate.candidateID,
                    sourceFingerprint: binding.sourceFingerprint,
                    replacementFingerprint: binding.replacementFingerprint,
                    learningContextFingerprint: binding.learningContextFingerprint,
                    boundaryRole: binding.boundaryRole,
                    styleTransition: binding.styleTransition,
                    evidenceSource: binding.evidenceSource
                ))
            }
        }
        var container = encoder.singleValueContainer()
        try container.encode(data)
    }
}

struct HWKAutobotSuggestionSurface: Codable, Equatable {
    static let schemeVersion = 1
    static let supportedVisibleLaneCounts: Set<Int> = [3, 6, 9]

    let schemeVersion: Int
    let visibleLaneCount: Int
    let configurationFingerprint: UInt64
    let selectedCandidateKinds: [HWKAutobotSuggestionSurfaceCandidateKind?]
    let projectionTrace: HWKAutobotSuggestionProjectionTrace?
    private let candidateIndexes: [Int?]
    private let opaqueCandidateIDs: [UInt64?]

    private enum CodingKeys: String, CodingKey {
        case schemeVersion = "v"
        case visibleLaneCount = "n"
        case configurationFingerprint = "f"
        case references = "r"
        case opaqueCandidateIDs = "o"
        case candidateKinds = "k"
        case projectionTrace = "t"
    }

    init(
        visibleLaneCount: Int,
        configurationFingerprint: UInt64,
        selectedCandidateIDs: [UInt64?],
        selectedCandidateKinds: [HWKAutobotSuggestionSurfaceCandidateKind?],
        projectionTrace: HWKAutobotSuggestionProjectionTrace? = nil
    ) {
        self.schemeVersion = Self.schemeVersion
        self.visibleLaneCount = visibleLaneCount
        self.configurationFingerprint = configurationFingerprint
        self.selectedCandidateKinds = selectedCandidateKinds
        self.projectionTrace = projectionTrace
        self.candidateIndexes = Array(repeating: nil, count: selectedCandidateIDs.count)
        self.opaqueCandidateIDs = selectedCandidateIDs
    }

    private init(
        schemeVersion: Int,
        visibleLaneCount: Int,
        configurationFingerprint: UInt64,
        selectedCandidateKinds: [HWKAutobotSuggestionSurfaceCandidateKind?],
        candidateIndexes: [Int?],
        opaqueCandidateIDs: [UInt64?],
        projectionTrace: HWKAutobotSuggestionProjectionTrace?
    ) {
        self.schemeVersion = schemeVersion
        self.visibleLaneCount = visibleLaneCount
        self.configurationFingerprint = configurationFingerprint
        self.selectedCandidateKinds = selectedCandidateKinds
        self.candidateIndexes = candidateIndexes
        self.opaqueCandidateIDs = opaqueCandidateIDs
        self.projectionTrace = projectionTrace
    }

    var selectedCandidateIDs: [UInt64?] {
        opaqueCandidateIDs
    }

    func resolvedCandidateIDs(
        using candidates: [HWKAutobotEpisodeCandidate]
    ) -> [UInt64?] {
        zip(candidateIndexes, opaqueCandidateIDs).map { candidateIndex, opaqueID in
            if let candidateIndex, candidates.indices.contains(candidateIndex) {
                return candidates[candidateIndex].id
            }
            return opaqueID
        }
    }

    func binding(
        to candidates: [HWKAutobotEpisodeCandidate]
    ) -> HWKAutobotSuggestionSurface {
        var indexes = candidateIndexes
        var opaqueIDs = opaqueCandidateIDs
        for laneIndex in opaqueIDs.indices {
            guard indexes[laneIndex] == nil,
                  let candidateID = opaqueIDs[laneIndex],
                  let candidateIndex = candidates.firstIndex(where: {
                      $0.id == candidateID
                  }) else {
                continue
            }
            indexes[laneIndex] = candidateIndex
            opaqueIDs[laneIndex] = nil
        }
        return HWKAutobotSuggestionSurface(
            schemeVersion: schemeVersion,
            visibleLaneCount: visibleLaneCount,
            configurationFingerprint: configurationFingerprint,
            selectedCandidateKinds: selectedCandidateKinds,
            candidateIndexes: indexes,
            opaqueCandidateIDs: opaqueIDs,
            projectionTrace: projectionTrace
        )
    }
    func withoutProjectionTrace() -> HWKAutobotSuggestionSurface {
        HWKAutobotSuggestionSurface(
            schemeVersion: schemeVersion,
            visibleLaneCount: visibleLaneCount,
            configurationFingerprint: configurationFingerprint,
            selectedCandidateKinds: selectedCandidateKinds,
            candidateIndexes: candidateIndexes,
            opaqueCandidateIDs: opaqueCandidateIDs,
            projectionTrace: nil
        )
    }
    func counterfactualCandidateIDs(
        using candidates: [HWKAutobotEpisodeCandidate],
        replacingChampionDeltasMicropoints replacements: [UInt64: Int32]
    ) -> [UInt64?]? {
        guard isValid,
              let projectionTrace,
              Set(replacements.keys).isSubset(of: Set(projectionTrace.candidates.map(\.candidateID))),
              projectionTrace.replayedCandidateIDs() == resolvedCandidateIDs(using: candidates) else {
            return nil
        }
        let replayed = projectionTrace.replayedCandidateIDs(
            replacingChampionDeltasMicropoints: replacements
        )
        guard replayed.count == visibleLaneCount else { return nil }
        return replayed
    }

    var isValid: Bool {
        guard schemeVersion == Self.schemeVersion,
              Self.supportedVisibleLaneCounts.contains(visibleLaneCount),
              configurationFingerprint != 0,
              selectedCandidateKinds.count == visibleLaneCount,
              candidateIndexes.count == visibleLaneCount,
              opaqueCandidateIDs.count == visibleLaneCount,
              projectionTrace.map({ $0.visibleLaneCount == visibleLaneCount }) ?? true,
              projectionTrace?.isValid ?? true else {
            return false
        }
        var selectedIndexes = [Int]()
        var selectedOpaqueIDs = [UInt64]()
        for laneIndex in 0..<visibleLaneCount {
            let candidateIndex = candidateIndexes[laneIndex]
            let opaqueID = opaqueCandidateIDs[laneIndex]
            let kind = selectedCandidateKinds[laneIndex]
            let hasReference = candidateIndex != nil || opaqueID != nil
            guard hasReference == (kind != nil),
                  !(candidateIndex != nil && opaqueID != nil) else {
                return false
            }
            if let candidateIndex {
                guard (0..<9).contains(candidateIndex) else { return false }
                selectedIndexes.append(candidateIndex)
            }
            if let opaqueID {
                guard opaqueID != 0 else { return false }
                selectedOpaqueIDs.append(opaqueID)
            }
        }
        guard !selectedIndexes.isEmpty || !selectedOpaqueIDs.isEmpty,
              Set(selectedIndexes).count == selectedIndexes.count,
              Set(selectedOpaqueIDs).count == selectedOpaqueIDs.count else {
            return false
        }
        if let projectionTrace,
           candidateIndexes.allSatisfy({ $0 == nil }),
           projectionTrace.replayedCandidateIDs() != opaqueCandidateIDs {
            return false
        }
        return true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let visibleLaneCount = try container.decode(Int.self, forKey: .visibleLaneCount)
        let references = try container.decode(Data.self, forKey: .references)
        guard references.count == visibleLaneCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .references,
                in: container,
                debugDescription: "Surface reference count mismatch."
            )
        }
        let packedKinds = try container.decode(UInt32.self, forKey: .candidateKinds)
        let opaqueData = try container.decodeIfPresent(
            Data.self,
            forKey: .opaqueCandidateIDs
        ) ?? Data()
        var opaqueOffset = 0
        var decodedIndexes = [Int?]()
        var decodedOpaqueIDs = [UInt64?]()
        var decodedKinds = [HWKAutobotSuggestionSurfaceCandidateKind?]()

        for laneIndex in 0..<visibleLaneCount {
            let kindRaw = UInt8((packedKinds >> UInt32(laneIndex * 3)) & 0x7)
            let kind = kindRaw == 0
                ? nil
                : HWKAutobotSuggestionSurfaceCandidateKind(rawValue: kindRaw)
            guard kindRaw == 0 || kind != nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .candidateKinds,
                    in: container,
                    debugDescription: "Unsupported surface candidate kind."
                )
            }
            let reference = references[laneIndex]
            if reference == 0, kind != nil {
                guard opaqueOffset + 8 <= opaqueData.count else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .opaqueCandidateIDs,
                        in: container,
                        debugDescription: "Missing opaque surface candidate."
                    )
                }
                let opaqueID = opaqueData[opaqueOffset..<(opaqueOffset + 8)].reduce(
                    into: UInt64(0)
                ) { value, byte in
                    value = (value << 8) | UInt64(byte)
                }
                decodedIndexes.append(nil)
                decodedOpaqueIDs.append(opaqueID)
                opaqueOffset += 8
            } else if reference > 0 {
                decodedIndexes.append(Int(reference - 1))
                decodedOpaqueIDs.append(nil)
            } else {
                decodedIndexes.append(nil)
                decodedOpaqueIDs.append(nil)
            }
            decodedKinds.append(kind)
        }
        guard opaqueOffset == opaqueData.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .opaqueCandidateIDs,
                in: container,
                debugDescription: "Unexpected opaque surface candidates."
            )
        }
        self.init(
            schemeVersion: try container.decode(Int.self, forKey: .schemeVersion),
            visibleLaneCount: visibleLaneCount,
            configurationFingerprint: try container.decode(
                UInt64.self,
                forKey: .configurationFingerprint
            ),
            selectedCandidateKinds: decodedKinds,
            candidateIndexes: decodedIndexes,
            opaqueCandidateIDs: decodedOpaqueIDs,
            projectionTrace: try container.decodeIfPresent(
                HWKAutobotSuggestionProjectionTrace.self,
                forKey: .projectionTrace
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        var references = Data()
        var opaqueData = Data()
        var packedKinds = UInt32(0)
        for laneIndex in 0..<visibleLaneCount {
            if let candidateIndex = candidateIndexes[laneIndex] {
                references.append(UInt8(candidateIndex + 1))
            } else {
                references.append(0)
                if var opaqueID = opaqueCandidateIDs[laneIndex]?.bigEndian {
                    withUnsafeBytes(of: &opaqueID) {
                        opaqueData.append(contentsOf: $0)
                    }
                }
            }
            if let kind = selectedCandidateKinds[laneIndex] {
                packedKinds |= UInt32(kind.rawValue) << UInt32(laneIndex * 3)
            }
        }
        try container.encode(schemeVersion, forKey: .schemeVersion)
        try container.encode(visibleLaneCount, forKey: .visibleLaneCount)
        try container.encode(configurationFingerprint, forKey: .configurationFingerprint)
        try container.encode(references, forKey: .references)
        if !opaqueData.isEmpty {
            try container.encode(opaqueData, forKey: .opaqueCandidateIDs)
        }
        try container.encode(packedKinds, forKey: .candidateKinds)
        try container.encodeIfPresent(projectionTrace, forKey: .projectionTrace)
    }
}

enum HWKAutobotCandidateEvidenceSource: String, Codable, Equatable, Sendable {
    case dictionary
    case savedWord
    case nativeSpellChecker
    case foundationModel
    case rule
}

struct HWKAutobotEpisodeCandidate: Codable, Equatable {
    let id: UInt64
    let sourceFingerprint: UInt64
    let replacementFingerprint: UInt64
    let rank: Int
    let ruleFingerprint: UInt64?
    let evidenceSource: HWKAutobotCandidateEvidenceSource?
    let paragraphPlanFingerprint: UInt64?
    let styleTransition: HWKAutobotEnglishStyleTransition?

    init(
        id: UInt64,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64,
        rank: Int,
        ruleFingerprint: UInt64?,
        evidenceSource: HWKAutobotCandidateEvidenceSource? = nil,
        paragraphPlanFingerprint: UInt64? = nil,
        styleTransition: HWKAutobotEnglishStyleTransition? = nil
    ) {
        self.id = id
        self.sourceFingerprint = sourceFingerprint
        self.replacementFingerprint = replacementFingerprint
        self.rank = max(0, rank)
        self.ruleFingerprint = ruleFingerprint
        self.evidenceSource = evidenceSource
        self.paragraphPlanFingerprint = paragraphPlanFingerprint
        self.styleTransition = styleTransition
    }
}

struct HWKAutobotTypingEpisode: Codable, Equatable {
    let id: UInt64
    let contextFingerprint: UInt64
    let learningContext: HWKAutobotLearningContext?
    let modality: HWKAutobotInputModality
    let language: HWKAutobotEpisodeLanguage
    let candidates: [HWKAutobotEpisodeCandidate]
    let suggestionSurface: HWKAutobotSuggestionSurface?
    let openedAtMilliseconds: Int64
    var updatedAtMilliseconds: Int64
    var immediateOutcome: HWKAutobotEpisodeOutcome?
    var finalOutcome: HWKAutobotEpisodeOutcome
    var resolvedCandidateID: UInt64?

    init(
        id: UInt64,
        contextFingerprint: UInt64,
        learningContext: HWKAutobotLearningContext? = nil,
        modality: HWKAutobotInputModality,
        language: HWKAutobotEpisodeLanguage,
        candidates: [HWKAutobotEpisodeCandidate],
        suggestionSurface: HWKAutobotSuggestionSurface? = nil,
        openedAtMilliseconds: Int64,
        updatedAtMilliseconds: Int64,
        immediateOutcome: HWKAutobotEpisodeOutcome?,
        finalOutcome: HWKAutobotEpisodeOutcome,
        resolvedCandidateID: UInt64?
    ) {
        self.id = id
        self.contextFingerprint = contextFingerprint
        self.learningContext = learningContext
        self.modality = modality
        self.language = language
        self.candidates = candidates
        self.suggestionSurface = suggestionSurface
        self.openedAtMilliseconds = openedAtMilliseconds
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.immediateOutcome = immediateOutcome
        self.finalOutcome = finalOutcome
        self.resolvedCandidateID = resolvedCandidateID
    }
}

struct HWKAutobotTypingEpisodeSnapshot: Equatable {
    let episodes: [HWKAutobotTypingEpisode]
    let eventCount: Int
}

struct HWKAutobotTypingEpisodeRecorder {
    private static let retainedProjectionTraceCount = 12
    private enum EventKind: String, Codable {
        case shown
        case accepted
        case ignored
        case delayedRepair
        case undo
        case backspace
        case retype
    }

    private struct Event: Codable, Equatable {
        let eventID: UInt64
        let episodeID: UInt64
        let timestampMilliseconds: Int64
        let kind: EventKind
        let contextFingerprint: UInt64?
        let learningContext: HWKAutobotLearningContext?
        let modality: HWKAutobotInputModality?
        let language: HWKAutobotEpisodeLanguage?
        let candidates: [HWKAutobotEpisodeCandidate]?
        let suggestionSurface: HWKAutobotSuggestionSurface?
        let candidateID: UInt64?
        let sourceFingerprint: UInt64?
        let replacementFingerprint: UInt64?

        func withoutProjectionTrace() -> Event {
            guard let suggestionSurface,
                  suggestionSurface.projectionTrace != nil else {
                return self
            }
            return Event(
                eventID: eventID,
                episodeID: episodeID,
                timestampMilliseconds: timestampMilliseconds,
                kind: kind,
                contextFingerprint: contextFingerprint,
                learningContext: learningContext,
                modality: modality,
                language: language,
                candidates: candidates,
                suggestionSurface: suggestionSurface.withoutProjectionTrace(),
                candidateID: candidateID,
                sourceFingerprint: sourceFingerprint,
                replacementFingerprint: replacementFingerprint
            )
        }
    }

    private struct ReplayEnvelope: Codable {
        let schemaVersion: Int
        let capacity: Int
        let events: [Event]
    }

    private enum ReplayError: Error {
        case unsupportedSchema
        case invalidEventLog
    }

    private(set) var capacity: Int
    private var events: [Event]
    private var eventIDs: Set<UInt64>

    init(capacity: Int = 32) {
        self.capacity = min(max(1, capacity), 128)
        self.events = []
        self.eventIDs = []
    }

    init(replaying data: Data) throws {
        let envelope = try JSONDecoder().decode(ReplayEnvelope.self, from: data)
        guard (1...3).contains(envelope.schemaVersion) else {
            throw ReplayError.unsupportedSchema
        }

        self.init(capacity: envelope.capacity)
        for event in envelope.events {
            guard replay(event) else {
                throw ReplayError.invalidEventLog
            }
        }
    }

    mutating func begin(
        eventID: UInt64,
        episodeID: UInt64,
        contextFingerprint: UInt64,
        learningContext: HWKAutobotLearningContext? = nil,
        modality: HWKAutobotInputModality,
        language: HWKAutobotEpisodeLanguage,
        candidates: [HWKAutobotEpisodeCandidate],
        suggestionSurface: HWKAutobotSuggestionSurface? = nil,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> UInt64? {
        guard !isSensitive,
              !eventIDs.contains(eventID),
              !snapshot().episodes.contains(where: { $0.id == episodeID }),
              snapshot().episodes.count <= capacity,
              !candidates.isEmpty,
              candidates.count <= 9,
              Set(candidates.map(\.id)).count == candidates.count,
              suggestionSurface?.isValid ?? true,
              candidates.allSatisfy({ candidate in
                  let styleIsValid = candidate.styleTransition?.isValid(
                      sourceFingerprint: candidate.sourceFingerprint,
                      replacementFingerprint: candidate.replacementFingerprint
                  ) ?? true
                  let paragraphPlanIsValid = candidate.paragraphPlanFingerprint == nil
                      || candidate.ruleFingerprint == nil
                          && candidate.styleTransition == nil
                          && candidate.sourceFingerprint
                              == HWKAutobotEpisodeFingerprint.token("")
                  return styleIsValid && paragraphPlanIsValid
              }) else {
            return nil
        }

        append(Event(
            eventID: eventID,
            episodeID: episodeID,
            timestampMilliseconds: timestampMilliseconds,
            kind: .shown,
            contextFingerprint: contextFingerprint,
            learningContext: learningContext,
            modality: modality,
            language: language,
            candidates: candidates,
            suggestionSurface: suggestionSurface,
            candidateID: nil,
            sourceFingerprint: nil,
            replacementFingerprint: nil
        ))
        return episodeID
    }

    mutating func recordImmediateOutcome(
        eventID: UInt64,
        episodeID: UInt64,
        outcome: HWKAutobotEpisodeOutcome,
        candidateID: UInt64? = nil,
        timestampMilliseconds: Int64
    ) -> Bool {
        guard !eventIDs.contains(eventID),
              let episode = snapshot().episodes.first(where: { $0.id == episodeID }),
              episode.immediateOutcome == nil else {
            return false
        }

        let kind: EventKind
        let resolvedCandidateID: UInt64?
        switch outcome {
        case .accepted:
            guard let candidateID,
                  episode.candidates.contains(where: { $0.id == candidateID }) else {
                return false
            }
            kind = .accepted
            resolvedCandidateID = candidateID
        case .ignored:
            kind = .ignored
            resolvedCandidateID = nil
        case .shown, .delayedRepair, .undo, .backspace, .retype:
            return false
        }

        append(Event(
            eventID: eventID,
            episodeID: episodeID,
            timestampMilliseconds: timestampMilliseconds,
            kind: kind,
            contextFingerprint: nil,
            learningContext: nil,
            modality: nil,
            language: nil,
            candidates: nil,
            suggestionSurface: nil,
            candidateID: resolvedCandidateID,
            sourceFingerprint: nil,
            replacementFingerprint: nil
        ))
        return true
    }

    mutating func recordDelayedRepair(
        eventID: UInt64,
        episodeID: UInt64,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64,
        timestampMilliseconds: Int64
    ) -> Bool {
        guard !eventIDs.contains(eventID),
              let episode = snapshot().episodes.first(where: { $0.id == episodeID }),
              episode.immediateOutcome == .ignored,
              episode.finalOutcome == .ignored,
              let candidate = episode.candidates.first(where: {
                  $0.sourceFingerprint == sourceFingerprint &&
                  $0.replacementFingerprint == replacementFingerprint
              }) else {
            return false
        }

        append(Event(
            eventID: eventID,
            episodeID: episodeID,
            timestampMilliseconds: timestampMilliseconds,
            kind: .delayedRepair,
            contextFingerprint: nil,
            learningContext: nil,
            modality: nil,
            language: nil,
            candidates: nil,
            suggestionSurface: nil,
            candidateID: candidate.id,
            sourceFingerprint: sourceFingerprint,
            replacementFingerprint: replacementFingerprint
        ))
        return true
    }

    mutating func recordNegativeOutcome(
        eventID: UInt64,
        episodeID: UInt64,
        outcome: HWKAutobotEpisodeOutcome,
        timestampMilliseconds: Int64
    ) -> Bool {
        guard !eventIDs.contains(eventID),
              let episode = snapshot().episodes.first(where: { $0.id == episodeID }),
              episode.immediateOutcome == .accepted,
              episode.resolvedCandidateID != nil else {
            return false
        }

        let kind: EventKind
        switch outcome {
        case .undo where episode.finalOutcome == .accepted:
            kind = .undo
        case .backspace where episode.finalOutcome == .accepted:
            kind = .backspace
        case .retype where episode.finalOutcome == .accepted || episode.finalOutcome == .backspace:
            kind = .retype
        case .shown, .accepted, .ignored, .delayedRepair, .undo, .backspace, .retype:
            return false
        }

        append(Event(
            eventID: eventID,
            episodeID: episodeID,
            timestampMilliseconds: timestampMilliseconds,
            kind: kind,
            contextFingerprint: nil,
            learningContext: nil,
            modality: nil,
            language: nil,
            candidates: nil,
            suggestionSurface: nil,
            candidateID: episode.resolvedCandidateID,
            sourceFingerprint: nil,
            replacementFingerprint: nil
        ))
        return true
    }

    mutating func discardShownEpisode(episodeID: UInt64) -> Bool {
        guard snapshot().episodes.first(where: { $0.id == episodeID })?.finalOutcome == .shown else {
            return false
        }
        let previousCount = events.count
        events.removeAll { $0.episodeID == episodeID }
        eventIDs = Set(events.map(\.eventID))
        return events.count < previousCount
    }

    func snapshot() -> HWKAutobotTypingEpisodeSnapshot {
        var orderedIDs: [UInt64] = []
        var episodes: [UInt64: HWKAutobotTypingEpisode] = [:]

        for event in events {
            switch event.kind {
            case .shown:
                guard episodes[event.episodeID] == nil,
                      let contextFingerprint = event.contextFingerprint,
                      let modality = event.modality,
                      let language = event.language,
                      let candidates = event.candidates else {
                    continue
                }
                orderedIDs.append(event.episodeID)
                episodes[event.episodeID] = HWKAutobotTypingEpisode(
                    id: event.episodeID,
                    contextFingerprint: contextFingerprint,
                    learningContext: event.learningContext,
                    modality: modality,
                    language: language,
                    candidates: candidates,
                    suggestionSurface: event.suggestionSurface,
                    openedAtMilliseconds: event.timestampMilliseconds,
                    updatedAtMilliseconds: event.timestampMilliseconds,
                    immediateOutcome: nil,
                    finalOutcome: .shown,
                    resolvedCandidateID: nil
                )
            case .accepted, .ignored:
                guard var episode = episodes[event.episodeID],
                      episode.immediateOutcome == nil else {
                    continue
                }
                let outcome: HWKAutobotEpisodeOutcome = event.kind == .accepted ? .accepted : .ignored
                episode.immediateOutcome = outcome
                episode.finalOutcome = outcome
                episode.resolvedCandidateID = event.candidateID
                episode.updatedAtMilliseconds = event.timestampMilliseconds
                episodes[event.episodeID] = episode
            case .delayedRepair:
                guard var episode = episodes[event.episodeID],
                      episode.immediateOutcome == .ignored,
                      episode.finalOutcome == .ignored else {
                    continue
                }
                episode.finalOutcome = .delayedRepair
                episode.resolvedCandidateID = event.candidateID
                episode.updatedAtMilliseconds = event.timestampMilliseconds
                episodes[event.episodeID] = episode
            case .undo, .backspace, .retype:
                guard var episode = episodes[event.episodeID],
                      episode.immediateOutcome == .accepted else {
                    continue
                }
                let outcome: HWKAutobotEpisodeOutcome
                switch event.kind {
                case .undo:
                    guard episode.finalOutcome == .accepted else { continue }
                    outcome = .undo
                case .backspace:
                    guard episode.finalOutcome == .accepted else { continue }
                    outcome = .backspace
                case .retype:
                    guard episode.finalOutcome == .accepted || episode.finalOutcome == .backspace else {
                        continue
                    }
                    outcome = .retype
                case .shown, .accepted, .ignored, .delayedRepair:
                    continue
                }
                episode.finalOutcome = outcome
                episode.updatedAtMilliseconds = event.timestampMilliseconds
                episodes[event.episodeID] = episode
            }
        }

        return HWKAutobotTypingEpisodeSnapshot(
            episodes: orderedIDs.compactMap { episodes[$0] },
            eventCount: events.count
        )
    }

    func credit(candidateID: UInt64) -> Int {
        snapshot().episodes.reduce(into: 0) { total, episode in
            guard episode.resolvedCandidateID == candidateID else { return }
            if episode.finalOutcome == .accepted || episode.finalOutcome == .delayedRepair {
                total += 1
            } else if episode.finalOutcome == .undo ||
                        episode.finalOutcome == .backspace ||
                        episode.finalOutcome == .retype {
                total -= 1
            }
        }
    }

    func encodedReplay() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ReplayEnvelope(
            schemaVersion: 3,
            capacity: capacity,
            events: events
        ))
    }

    func nextAvailableEventID() -> UInt64? {
        guard let maximum = events.map(\.eventID).max() else { return 1 }
        guard maximum < UInt64.max else { return nil }
        return maximum + 1
    }

    func nextAvailableEpisodeID() -> UInt64? {
        guard let maximum = events.map(\.episodeID).max() else { return 1 }
        guard maximum < UInt64.max else { return nil }
        return maximum + 1
    }

    private mutating func replay(_ event: Event) -> Bool {
        switch event.kind {
        case .shown:
            guard let contextFingerprint = event.contextFingerprint,
                  let modality = event.modality,
                  let language = event.language,
                  let candidates = event.candidates else {
                return false
            }
            return begin(
                eventID: event.eventID,
                episodeID: event.episodeID,
                contextFingerprint: contextFingerprint,
                learningContext: event.learningContext,
                modality: modality,
                language: language,
                candidates: candidates,
                suggestionSurface: event.suggestionSurface,
                isSensitive: false,
                timestampMilliseconds: event.timestampMilliseconds
            ) != nil
        case .accepted, .ignored:
            return recordImmediateOutcome(
                eventID: event.eventID,
                episodeID: event.episodeID,
                outcome: event.kind == .accepted ? .accepted : .ignored,
                candidateID: event.candidateID,
                timestampMilliseconds: event.timestampMilliseconds
            )
        case .delayedRepair:
            guard let sourceFingerprint = event.sourceFingerprint,
                  let replacementFingerprint = event.replacementFingerprint else {
                return false
            }
            return recordDelayedRepair(
                eventID: event.eventID,
                episodeID: event.episodeID,
                sourceFingerprint: sourceFingerprint,
                replacementFingerprint: replacementFingerprint,
                timestampMilliseconds: event.timestampMilliseconds
            )
        case .undo, .backspace, .retype:
            let outcome: HWKAutobotEpisodeOutcome
            switch event.kind {
            case .undo:
                outcome = .undo
            case .backspace:
                outcome = .backspace
            case .retype:
                outcome = .retype
            case .shown, .accepted, .ignored, .delayedRepair:
                return false
            }
            return recordNegativeOutcome(
                eventID: event.eventID,
                episodeID: event.episodeID,
                outcome: outcome,
                timestampMilliseconds: event.timestampMilliseconds
            )
        }
    }

    private mutating func evictOldestEpisodeIfNeeded() {
        let episodes = snapshot().episodes
        guard episodes.count > capacity, let oldest = episodes.first else { return }
        events.removeAll { $0.episodeID == oldest.id }
        eventIDs = Set(events.map(\.eventID))
    }

    private mutating func append(_ event: Event) {
        events.append(event)
        eventIDs.insert(event.eventID)
        guard event.kind != .shown else { return }
        evictOldestEpisodeIfNeeded()
        let tracedResolvedEpisodeIDs = snapshot().episodes.compactMap { episode -> UInt64? in
            guard episode.finalOutcome != .shown,
                  episode.suggestionSurface?.projectionTrace != nil else {
                return nil
            }
            return episode.id
        }
        let removalCount = tracedResolvedEpisodeIDs.count - Self.retainedProjectionTraceCount
        guard removalCount > 0 else { return }
        let removedEpisodeIDs = Set(tracedResolvedEpisodeIDs.prefix(removalCount))
        for index in events.indices where removedEpisodeIDs.contains(events[index].episodeID) {
            events[index] = events[index].withoutProjectionTrace()
        }
    }
}

enum HWKAutobotEpisodeFingerprint {
    static let schemeVersion = 2

    private static let keyFilename = ".autobot-fingerprint-key-v2"
    private static let fallbackKeyStorageKey = "keyboard.autobot.fingerprintKey.v2"
    static let portableRootKeyStorageKey = "keyboard.autobot.portableFingerprintSecret.v1"
    private static let keyLock = NSLock()
    private static var cachedKeyData: Data?

    static func token(_ text: String) -> UInt64 {
        digest(namespace: "token", text: normalizedToken(text))
    }

    static func paragraphPlanEvidence(_ text: String) -> UInt64 {
        digest(namespace: "paragraph-plan-evidence-v1", text: normalizedToken(text))
    }

    static func paragraphPlanFeedbackIdentity(
        language: String,
        contextKey: String,
        continuationKey: String,
        paragraphIntent: String? = nil
    ) -> UInt64 {
        let structuralIdentity = normalizedToken(language)
            + "\u{001F}" + normalizedToken(contextKey)
            + "\u{001F}" + normalizedToken(continuationKey)
        let identity = paragraphIntent.map {
            structuralIdentity + "\u{001F}" + normalizedToken($0)
        } ?? structuralIdentity
        return digest(
            namespace: "paragraph-plan-feedback-identity-v1",
            text: identity
        )
    }

    static func paragraphPlanFeedbackEpisode(_ episodeID: UInt64) -> UInt64 {
        digest(
            namespace: "paragraph-plan-feedback-episode-v1",
            text: String(episodeID)
        )
    }

    static func englishStyleToken(_ text: String) -> UInt64 {
        digest(namespace: "english-style-token-v1", text: normalizedEnglishStyleToken(text))
    }

    static func context(
        documentIdentifier: String,
        focusEpoch: UInt64 = 0,
        prefix: String
    ) -> UInt64 {
        let boundedPrefix = String(prefix.suffix(256))
        return digest(
            namespace: "context",
            text: documentIdentifier + "\u{001F}" + String(focusEpoch) + "\u{001F}" + boundedPrefix
        )
    }

    static func candidate(id: String, source: String, replacement: String) -> UInt64 {
        digest(
            namespace: "candidate",
            text: id + "\u{001F}" + normalizedToken(source) + "\u{001F}" + normalizedToken(replacement)
        )
    }

    static func englishStyleCandidate(
        id: String,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64
    ) -> UInt64 {
        digest(
            namespace: "english-style-candidate-v1",
            text: id + "\u{001F}" + String(sourceFingerprint) + "\u{001F}" +
                String(replacementFingerprint)
        )
    }

    static func candidatePair(
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64
    ) -> UInt64 {
        digest(
            namespace: "candidate-pair",
            text: String(sourceFingerprint) + "\u{001F}" + String(replacementFingerprint)
        )
    }

    static func candidatePair(source: String, replacement: String) -> UInt64 {
        candidatePair(
            sourceFingerprint: token(source),
            replacementFingerprint: token(replacement)
        )
    }

    static func learningContext(
        previousTokenFingerprint: UInt64?,
        previousBigramFingerprint: UInt64?,
        boundaryRole: HWKAutobotBoundaryRole
    ) -> UInt64 {
        digest(
            namespace: "learning-context-v\(HWKAutobotLearningContext.schemeVersion)",
            text: [
                previousTokenFingerprint.map(String.init) ?? "none",
                previousBigramFingerprint.map(String.init) ?? "none",
                boundaryRole.rawValue,
            ].joined(separator: "\u{001F}")
        )
    }

    static func contextualCandidatePair(
        candidateKey: UInt64,
        learningContextFingerprint: UInt64
    ) -> UInt64 {
        digest(
            namespace: "contextual-candidate-pair-v\(HWKAutobotLearningContext.schemeVersion)",
            text: String(candidateKey) + "\u{001F}" + String(learningContextFingerprint)
        )
    }

    static func languageScopedCandidatePair(
        candidateKey: UInt64,
        language: HWKAutobotEpisodeLanguage
    ) -> UInt64 {
        guard language == .englishCodeSwitch else { return candidateKey }
        return digest(
            namespace: "language-scoped-candidate-pair-v1",
            text: String(candidateKey) + "\u{001F}" + language.rawValue
        )
    }

    static func englishStyleTransitionAttestation(
        dimension: HWKAutobotEnglishStyleDimension,
        direction: HWKAutobotEnglishStyleDirection,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64
    ) -> UInt64 {
        digest(
            namespace: "english-style-transition-v\(HWKAutobotEnglishStyleTransition.schemeVersion)",
            text: [
                String(dimension.rawValue),
                direction.rawValue,
                String(sourceFingerprint),
                String(replacementFingerprint),
            ].joined(separator: "\u{001F}")
        )
    }

    static func suggestionModelBindingAttestation(
        candidateID: UInt64,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64,
        learningContextFingerprint: UInt64?,
        boundaryRole: HWKAutobotBoundaryRole?,
        styleTransition: HWKAutobotEnglishStyleTransition?
    ) -> UInt64 {
        digest(
            namespace: "suggestion-model-binding-v1",
            text: [
                String(candidateID),
                String(sourceFingerprint),
                String(replacementFingerprint),
                learningContextFingerprint.map(String.init) ?? "none",
                boundaryRole?.rawValue ?? "none",
                styleTransition.map { String($0.dimension.rawValue) } ?? "none",
                styleTransition?.direction.rawValue ?? "none",
            ].joined(separator: "\u{001F}")
        )
    }

    static func suggestionModelBindingAttestation(
        candidateID: UInt64,
        sourceFingerprint: UInt64,
        replacementFingerprint: UInt64,
        learningContextFingerprint: UInt64?,
        boundaryRole: HWKAutobotBoundaryRole?,
        styleTransition: HWKAutobotEnglishStyleTransition?,
        evidenceSource: HWKAutobotCandidateEvidenceSource?
    ) -> UInt64 {
        digest(
            namespace: "suggestion-model-binding-v2",
            text: [
                String(candidateID),
                String(sourceFingerprint),
                String(replacementFingerprint),
                learningContextFingerprint.map(String.init) ?? "none",
                boundaryRole?.rawValue ?? "none",
                styleTransition.map { String($0.dimension.rawValue) } ?? "none",
                styleTransition?.direction.rawValue ?? "none",
                evidenceSource?.rawValue ?? "none",
            ].joined(separator: "\u{001F}")
        )
    }

    static func englishStyleContext(
        dimension: HWKAutobotEnglishStyleDimension,
        boundaryRole: HWKAutobotBoundaryRole
    ) -> UInt64 {
        digest(
            namespace: "english-style-context-v\(HWKAutobotEnglishStyleTransition.schemeVersion)",
            text: String(dimension.rawValue) + "\u{001F}" + boundaryRole.rawValue
        )
    }

    static func suggestionSurfaceConfiguration(_ canonicalConfiguration: String) -> UInt64 {
        digest(
            namespace: "suggestion-surface-v\(HWKAutobotSuggestionSurface.schemeVersion)",
            text: canonicalConfiguration
        )
    }
    static func suggestionSurfaceUniqueKey(_ canonicalKey: String) -> UInt64 {
        digest(namespace: "suggestion-surface-unique-key-v1", text: canonicalKey)
    }
    static func suggestionSurfaceVisibleKey(_ canonicalKey: String) -> UInt64 {
        digest(namespace: "suggestion-surface-visible-key-v1", text: canonicalKey)
    }

    static func rule(_ id: UUID) -> UInt64 {
        digest(namespace: "rule", text: id.uuidString.lowercased())
    }

    static func learnerManifestKeyData() -> Data {
        let rootKey = SymmetricKey(data: localKeyData())
        return Data(HMAC<SHA256>.authenticationCode(
            for: Data("autobot-learner-manifest-v1".utf8),
            using: rootKey
        ))
    }

    static func portableRootKeyData() -> Data {
        localKeyData()
    }

    static func invalidateCachedKey() {
        keyLock.lock()
        cachedKeyData = nil
        keyLock.unlock()
    }

    private static func normalizedToken(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func normalizedEnglishStyleToken(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func digest(namespace: String, text: String) -> UInt64 {
        let key = SymmetricKey(data: localKeyData())
        let digest = HMAC<SHA256>.authenticationCode(
            for: Data((namespace + "\u{001F}" + text).utf8),
            using: key
        )
        return digest.prefix(8).reduce(into: UInt64(0)) { value, byte in
            value = (value << 8) | UInt64(byte)
        }
    }

    private static func localKeyData() -> Data {
        keyLock.lock()
        defer { keyLock.unlock() }
        if let cachedKeyData, cachedKeyData.count == 32 {
            return cachedKeyData
        }

        let defaults = KeyboardSharedPreferences.defaults
        if let portable = defaults.data(forKey: portableRootKeyStorageKey),
           portable.count == 32 {
            cachedKeyData = portable
            return portable
        }

        let generated = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        let fileManager = FileManager.default
        if let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSharedPreferences.appGroupIdentifier
        ) {
            let keyURL = containerURL.appendingPathComponent(keyFilename, isDirectory: false)
            if let stored = try? Data(contentsOf: keyURL), stored.count == 32 {
                defaults.set(stored, forKey: portableRootKeyStorageKey)
                defaults.removeObject(forKey: fallbackKeyStorageKey)
                cachedKeyData = stored
                return stored
            }
            try? generated.write(to: keyURL, options: .withoutOverwriting)
            if let stored = try? Data(contentsOf: keyURL), stored.count == 32 {
                defaults.set(stored, forKey: portableRootKeyStorageKey)
                defaults.removeObject(forKey: fallbackKeyStorageKey)
                cachedKeyData = stored
                return stored
            }
        }

        if let stored = defaults.data(forKey: fallbackKeyStorageKey), stored.count == 32 {
            defaults.set(stored, forKey: portableRootKeyStorageKey)
            defaults.removeObject(forKey: fallbackKeyStorageKey)
            cachedKeyData = stored
            return stored
        }
        defaults.set(generated, forKey: portableRootKeyStorageKey)
        KeyboardSharedPreferences.sync()
        let stored = defaults.data(forKey: portableRootKeyStorageKey) ?? generated
        cachedKeyData = stored
        return stored
    }
}

enum HWKAutobotEpisodeTextBridge {
    struct CommittedToken: Equatable {
        let prefix: String
        let token: String
    }

    static func exposurePrefix(
        contextBeforeInput: String,
        sourceText: String,
        trailingSuffix: String
    ) -> String? {
        if sourceText.isEmpty {
            guard trailingSuffix.isEmpty,
                  contextBeforeInput.last?.isWhitespace == true else {
                return nil
            }
            return contextBeforeInput
        }
        let postBoundarySource = sourceText + trailingSuffix
        if !trailingSuffix.isEmpty, contextBeforeInput.hasSuffix(postBoundarySource) {
            return String(contextBeforeInput.dropLast(postBoundarySource.count))
        }
        guard contextBeforeInput.hasSuffix(sourceText) else { return nil }
        return String(contextBeforeInput.dropLast(sourceText.count))
    }

    static func committedToken(in contextBeforeInput: String) -> CommittedToken? {
        guard !contextBeforeInput.isEmpty else { return nil }
        let boundaryCharacters: Set<Character> = [
            " ", "\n", "\t", ".", ",", "!", "?", ":", ";", "…",
            ")", "]", "}", ">", "\"", "'", "”", "’", "»",
        ]
        var tokenEnd = contextBeforeInput.endIndex
        while tokenEnd > contextBeforeInput.startIndex {
            let previous = contextBeforeInput.index(before: tokenEnd)
            guard boundaryCharacters.contains(contextBeforeInput[previous]) else { break }
            tokenEnd = previous
        }
        guard tokenEnd > contextBeforeInput.startIndex else { return nil }

        var tokenStart = tokenEnd
        while tokenStart > contextBeforeInput.startIndex {
            let previous = contextBeforeInput.index(before: tokenStart)
            let character = contextBeforeInput[previous]
            guard character.isLetter || character.isNumber || character == "'" || character == "’" else {
                break
            }
            tokenStart = previous
        }
        guard tokenStart < tokenEnd else { return nil }
        return CommittedToken(
            prefix: String(contextBeforeInput[..<tokenStart]),
            token: String(contextBeforeInput[tokenStart..<tokenEnd])
        )
    }
}

enum HWKAutobotTextContextContinuity: Equatable {
    case unchanged
    case localInsertion
    case localBackspace
    case caretMove
    case discontinuity

    private static let maximumLocalMutationCharacters = 8
    private static let maximumContextCharacters = 1_024
    private static let maximumContextUTF8Bytes = 4_096

    var requiresAttributionEpochRotation: Bool {
        self == .caretMove || self == .discontinuity
    }

    static func classify(
        previousBeforeInput: String,
        previousAfterInput: String,
        currentBeforeInput: String,
        currentAfterInput: String,
        stableSelectionChangeObserved: Bool = false
    ) -> HWKAutobotTextContextContinuity {
        guard isWithinContextLimit(previousBeforeInput),
              isWithinContextLimit(previousAfterInput),
              isWithinContextLimit(currentBeforeInput),
              isWithinContextLimit(currentAfterInput) else {
            return .discontinuity
        }
        if previousBeforeInput == currentBeforeInput,
           previousAfterInput == currentAfterInput {
            return stableSelectionChangeObserved ? .caretMove : .unchanged
        }

        if previousAfterInput == currentAfterInput {
            if currentBeforeInput.hasPrefix(previousBeforeInput) {
                let insertedCount = currentBeforeInput.count - previousBeforeInput.count
                return insertedCount > 0 && insertedCount <= maximumLocalMutationCharacters
                    ? .localInsertion
                    : .discontinuity
            }
            if previousBeforeInput.hasPrefix(currentBeforeInput) {
                let deletedCount = previousBeforeInput.count - currentBeforeInput.count
                return deletedCount > 0 && deletedCount <= maximumLocalMutationCharacters
                    ? .localBackspace
                    : .discontinuity
            }
        }

        if previousBeforeInput + previousAfterInput == currentBeforeInput + currentAfterInput {
            return .caretMove
        }
        return .discontinuity
    }

    private static func isWithinContextLimit(_ value: String) -> Bool {
        let utf8 = value.utf8
        guard utf8.index(
            utf8.startIndex,
            offsetBy: maximumContextUTF8Bytes + 1,
            limitedBy: utf8.endIndex
        ) == nil else {
            return false
        }
        return value.index(
            value.startIndex,
            offsetBy: maximumContextCharacters + 1,
            limitedBy: value.endIndex
        ) == nil
    }
}

struct HWKAutobotAppliedSpanTracker {
    struct Match: Equatable {
        let prefix: String
        let spanFingerprint: UInt64
        let styleSpanFingerprint: UInt64
    }

    private struct Entry {
        let source: String
        let replacement: String
        let focusEpoch: UInt64
        let recordedAtMilliseconds: Int64
        var negativeObserved: Bool
    }

    private static let maximumSpanCharacters = 96
    private static let lifetimeMilliseconds: Int64 = 60_000
    private static let trailingBoundaries: Set<Character> = [
        " ", "\n", "\t", ".", ",", "!", "?", ":", ";", "…",
        ")", "]", "}", ">", "\"", "”", "»",
    ]

    private var entry: Entry?

    mutating func record(
        source: String,
        replacement: String,
        focusEpoch: UInt64,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) {
        guard !isSensitive else {
            clear()
            return
        }
        let boundedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let boundedReplacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !boundedReplacement.isEmpty,
              boundedSource.count <= Self.maximumSpanCharacters,
              boundedReplacement.count <= Self.maximumSpanCharacters,
              boundedSource != boundedReplacement,
              boundedSource.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              boundedReplacement.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            clear()
            return
        }
        entry = Entry(
            source: boundedSource,
            replacement: boundedReplacement,
            focusEpoch: focusEpoch,
            recordedAtMilliseconds: timestampMilliseconds,
            negativeObserved: false
        )
    }

    mutating func negativeEdit(
        contextBeforeInput: String,
        focusEpoch: UInt64,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> Match? {
        guard validate(
            focusEpoch: focusEpoch,
            isSensitive: isSensitive,
            timestampMilliseconds: timestampMilliseconds
        ), var entry, !entry.negativeObserved,
        let lastCharacter = contextBeforeInput.last,
        lastCharacter.isLetter || lastCharacter.isNumber ||
            lastCharacter == "'" || lastCharacter == "’",
        let range = Self.suffixRange(of: entry.replacement, in: contextBeforeInput) else {
            return nil
        }
        entry.negativeObserved = true
        self.entry = entry
        return Match(
            prefix: String(contextBeforeInput[..<range.lowerBound]),
            spanFingerprint: HWKAutobotEpisodeFingerprint.token(entry.replacement),
            styleSpanFingerprint: HWKAutobotEpisodeFingerprint.englishStyleToken(entry.replacement)
        )
    }

    mutating func committedSource(
        contextBeforeInput: String,
        focusEpoch: UInt64,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> Match? {
        guard validate(
            focusEpoch: focusEpoch,
            isSensitive: isSensitive,
            timestampMilliseconds: timestampMilliseconds
        ), let entry, entry.negativeObserved else {
            return nil
        }
        guard !entry.source.isEmpty else {
            clear()
            return nil
        }
        var spanEnd = contextBeforeInput.endIndex
        while spanEnd > contextBeforeInput.startIndex {
            let previous = contextBeforeInput.index(before: spanEnd)
            guard Self.trailingBoundaries.contains(contextBeforeInput[previous]) else { break }
            spanEnd = previous
        }
        let contextWithoutBoundary = String(contextBeforeInput[..<spanEnd])
        guard let range = Self.suffixRange(of: entry.source, in: contextWithoutBoundary) else {
            return nil
        }
        let result = Match(
            prefix: String(contextWithoutBoundary[..<range.lowerBound]),
            spanFingerprint: HWKAutobotEpisodeFingerprint.token(entry.source),
            styleSpanFingerprint: HWKAutobotEpisodeFingerprint.englishStyleToken(entry.source)
        )
        clear()
        return result
    }

    mutating func clear() {
        entry = nil
    }

    @discardableResult
    private mutating func validate(
        focusEpoch: UInt64,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> Bool {
        guard !isSensitive else {
            clear()
            return false
        }
        guard let entry else { return false }
        let age = timestampMilliseconds - entry.recordedAtMilliseconds
        guard age >= 0, age <= Self.lifetimeMilliseconds else {
            clear()
            return false
        }
        return entry.focusEpoch == focusEpoch
    }

    private static func suffixRange(of suffix: String, in text: String) -> Range<String.Index>? {
        guard let range = text.range(
            of: suffix,
            options: [.caseInsensitive, .anchored, .backwards]
        ), range.upperBound == text.endIndex else {
            return nil
        }
        return range
    }
}

struct HWKAutobotLiveEpisodeCoordinator {
    private enum ReplayCompressionError: Error {
        case invalidCompressedReplay
    }
    private enum ReplayCompression {
        static let maximumDecodedBytes = 1_024 * 1_024
        static let magic = Data([0x41, 0x42, 0x52, 0x01])

        static func encoded(_ source: Data) -> Data {
            guard !source.isEmpty, source.count <= maximumDecodedBytes else { return source }
            var destination = [UInt8](repeating: 0, count: max(64, source.count * 2))
            let destinationCapacity = destination.count
            let encodedCount = source.withUnsafeBytes { sourceBuffer in
                destination.withUnsafeMutableBytes { destinationBuffer in
                    compression_encode_buffer(
                        destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        destinationCapacity,
                        sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        source.count,
                        nil,
                        COMPRESSION_LZFSE
                    )
                }
            }
            guard encodedCount > 0,
                  encodedCount + magic.count < source.count else {
                return source
            }
            var result = magic
            result.append(contentsOf: destination.prefix(encodedCount))
            return result
        }

        static func decoded(_ source: Data) throws -> Data {
            guard source.starts(with: magic) else { return source }
            let payload = source.dropFirst(magic.count)
            guard !payload.isEmpty else { throw ReplayCompressionError.invalidCompressedReplay }
            var destination = [UInt8](repeating: 0, count: maximumDecodedBytes)
            let destinationCapacity = destination.count
            let decodedCount = payload.withUnsafeBytes { sourceBuffer in
                destination.withUnsafeMutableBytes { destinationBuffer in
                    compression_decode_buffer(
                        destinationBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        destinationCapacity,
                        sourceBuffer.bindMemory(to: UInt8.self).baseAddress!,
                        payload.count,
                        nil,
                        COMPRESSION_LZFSE
                    )
                }
            }
            guard decodedCount > 0, decodedCount < maximumDecodedBytes else {
                throw ReplayCompressionError.invalidCompressedReplay
            }
            return Data(destination.prefix(decodedCount))
        }
    }
    private struct ReplayEnvelope: Codable {
        let schemaVersion: Int
        let recorderData: Data
        let nextEventID: UInt64
        let nextEpisodeID: UInt64
        let delayedRepairWindowMilliseconds: Int64
    }

    private enum ReplayError: Error {
        case unsupportedSchema
        case invalidState
    }

    private struct ActiveExposure: Equatable {
        let episodeID: UInt64
        let contextFingerprint: UInt64
        let learningContext: HWKAutobotLearningContext?
        let modality: HWKAutobotInputModality
        let language: HWKAutobotEpisodeLanguage
        let candidates: [HWKAutobotEpisodeCandidate]
        let suggestionSurface: HWKAutobotSuggestionSurface?
    }

    private var recorder: HWKAutobotTypingEpisodeRecorder
    private var activeExposure: ActiveExposure?
    private var nextEventID: UInt64 = 1
    private var nextEpisodeID: UInt64 = 1
    private let delayedRepairWindowMilliseconds: Int64

    init(
        capacity: Int = 32,
        delayedRepairWindowMilliseconds: Int64 = 60_000
    ) {
        self.recorder = HWKAutobotTypingEpisodeRecorder(capacity: capacity)
        self.delayedRepairWindowMilliseconds = max(1_000, delayedRepairWindowMilliseconds)
    }

    init(replaying data: Data) throws {
        let replayData = try ReplayCompression.decoded(data)
        let envelope = try JSONDecoder().decode(ReplayEnvelope.self, from: replayData)
        guard (1...3).contains(envelope.schemaVersion) else {
            throw ReplayError.unsupportedSchema
        }

        let recorder = try HWKAutobotTypingEpisodeRecorder(replaying: envelope.recorderData)
        let snapshot = recorder.snapshot()
        guard !snapshot.episodes.contains(where: { $0.finalOutcome == .shown }),
              let eventIDFloor = recorder.nextAvailableEventID(),
              let episodeIDFloor = recorder.nextAvailableEpisodeID(),
              envelope.nextEventID >= eventIDFloor,
              envelope.nextEpisodeID >= episodeIDFloor,
              envelope.nextEventID > 0,
              envelope.nextEpisodeID > 0,
              envelope.delayedRepairWindowMilliseconds >= 1_000 else {
            throw ReplayError.invalidState
        }

        self.recorder = recorder
        self.activeExposure = nil
        self.nextEventID = envelope.nextEventID
        self.nextEpisodeID = envelope.nextEpisodeID
        self.delayedRepairWindowMilliseconds = envelope.delayedRepairWindowMilliseconds
    }

    mutating func observeSuggestionExposure(
        contextFingerprint: UInt64,
        learningContext: HWKAutobotLearningContext? = nil,
        modality: HWKAutobotInputModality,
        language: HWKAutobotEpisodeLanguage,
        candidates: [HWKAutobotEpisodeCandidate],
        suggestionSurface: HWKAutobotSuggestionSurface? = nil,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> UInt64? {
        guard !isSensitive, !candidates.isEmpty else {
            cancelActiveExposure()
            return nil
        }
        let boundSuggestionSurface = suggestionSurface?.binding(to: candidates)

        let proposed = ActiveExposure(
            episodeID: activeExposure?.episodeID ?? nextEpisodeID,
            contextFingerprint: contextFingerprint,
            learningContext: learningContext,
            modality: modality,
            language: language,
            candidates: candidates,
            suggestionSurface: boundSuggestionSurface
        )
        if let activeExposure,
           activeExposure.contextFingerprint == proposed.contextFingerprint,
           activeExposure.learningContext == proposed.learningContext,
           activeExposure.modality == proposed.modality,
           activeExposure.language == proposed.language,
           activeExposure.candidates == proposed.candidates,
           activeExposure.suggestionSurface == proposed.suggestionSurface {
            return activeExposure.episodeID
        }

        cancelActiveExposure()
        let eventID = takeNextEventID()
        let episodeID = takeNextEpisodeID()
        guard recorder.begin(
            eventID: eventID,
            episodeID: episodeID,
            contextFingerprint: contextFingerprint,
            learningContext: learningContext,
            modality: modality,
            language: language,
            candidates: candidates,
            suggestionSurface: boundSuggestionSurface,
            isSensitive: false,
            timestampMilliseconds: timestampMilliseconds
        ) != nil else {
            return nil
        }
        activeExposure = ActiveExposure(
            episodeID: episodeID,
            contextFingerprint: contextFingerprint,
            learningContext: learningContext,
            modality: modality,
            language: language,
            candidates: candidates,
            suggestionSurface: boundSuggestionSurface
        )
        return episodeID
    }

    mutating func accept(
        episodeID: UInt64?,
        candidateID: UInt64,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> Bool {
        guard !isSensitive else {
            cancelActiveExposure()
            return false
        }
        guard let episodeID,
              let activeExposure,
              activeExposure.episodeID == episodeID,
              activeExposure.candidates.contains(where: { $0.id == candidateID }) else {
            return false
        }
        let eventID = takeNextEventID()
        let accepted = recorder.recordImmediateOutcome(
            eventID: eventID,
            episodeID: activeExposure.episodeID,
            outcome: .accepted,
            candidateID: candidateID,
            timestampMilliseconds: timestampMilliseconds
        )
        if accepted {
            self.activeExposure = nil
        }
        return accepted
    }

    mutating func observeCommittedToken(
        contextFingerprint: UInt64,
        tokenFingerprint: UInt64,
        styleFingerprint: UInt64? = nil,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> HWKAutobotEpisodeOutcome? {
        guard !isSensitive else {
            cancelActiveExposure()
            return nil
        }
        if let activeExposure,
           activeExposure.contextFingerprint == contextFingerprint {
            if activeExposure.candidates.contains(where: {
                Self.matchesSource(
                    $0,
                    tokenFingerprint: tokenFingerprint,
                    styleFingerprint: styleFingerprint
                )
            }) {
                let eventID = takeNextEventID()
                let ignored = recorder.recordImmediateOutcome(
                    eventID: eventID,
                    episodeID: activeExposure.episodeID,
                    outcome: .ignored,
                    timestampMilliseconds: timestampMilliseconds
                )
                if ignored {
                    self.activeExposure = nil
                    return .ignored
                }
            }

            if let candidate = activeExposure.candidates.first(where: {
                Self.matchesReplacement(
                    $0,
                    tokenFingerprint: tokenFingerprint,
                    styleFingerprint: styleFingerprint
                )
            }) {
                let eventID = takeNextEventID()
                let accepted = recorder.recordImmediateOutcome(
                    eventID: eventID,
                    episodeID: activeExposure.episodeID,
                    outcome: .accepted,
                    candidateID: candidate.id,
                    timestampMilliseconds: timestampMilliseconds
                )
                if accepted {
                    self.activeExposure = nil
                    return .accepted
                }
            }
        }

        let episodes = recorder.snapshot().episodes.reversed()
        for episode in episodes {
            let elapsed = timestampMilliseconds - episode.updatedAtMilliseconds
            guard episode.contextFingerprint == contextFingerprint,
                  elapsed >= 0,
                  elapsed <= delayedRepairWindowMilliseconds else {
                continue
            }

            if episode.finalOutcome == .accepted || episode.finalOutcome == .backspace,
               let candidateID = episode.resolvedCandidateID,
               let candidate = episode.candidates.first(where: { $0.id == candidateID }),
               Self.matchesSource(
                    candidate,
                    tokenFingerprint: tokenFingerprint,
                    styleFingerprint: styleFingerprint
               ) {
                let eventID = takeNextEventID()
                if recorder.recordNegativeOutcome(
                    eventID: eventID,
                    episodeID: episode.id,
                    outcome: .retype,
                    timestampMilliseconds: timestampMilliseconds
                ) {
                    return .retype
                }
            }

            if episode.finalOutcome == .ignored,
               let candidate = episode.candidates.first(where: {
                   Self.matchesReplacement(
                       $0,
                       tokenFingerprint: tokenFingerprint,
                       styleFingerprint: styleFingerprint
                   )
               }) {
                let eventID = takeNextEventID()
                if recorder.recordDelayedRepair(
                    eventID: eventID,
                    episodeID: episode.id,
                    sourceFingerprint: candidate.sourceFingerprint,
                    replacementFingerprint: candidate.replacementFingerprint,
                    timestampMilliseconds: timestampMilliseconds
                ) {
                    return .delayedRepair
                }
            }
        }
        return nil
    }

    mutating func observeNegativeEdit(
        contextFingerprint: UInt64,
        replacementFingerprint: UInt64,
        styleReplacementFingerprint: UInt64? = nil,
        outcome: HWKAutobotEpisodeOutcome,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> Bool {
        guard !isSensitive else {
            cancelActiveExposure()
            return false
        }
        guard outcome == .undo || outcome == .backspace else { return false }

        for episode in recorder.snapshot().episodes.reversed() where episode.finalOutcome == .accepted {
            let elapsed = timestampMilliseconds - episode.updatedAtMilliseconds
            guard episode.contextFingerprint == contextFingerprint,
                  elapsed >= 0,
                  elapsed <= delayedRepairWindowMilliseconds,
                  let candidateID = episode.resolvedCandidateID,
                  let candidate = episode.candidates.first(where: { $0.id == candidateID }),
                  Self.matchesReplacement(
                    candidate,
                    tokenFingerprint: replacementFingerprint,
                    styleFingerprint: styleReplacementFingerprint
                  ) else {
                continue
            }
            let eventID = takeNextEventID()
            return recorder.recordNegativeOutcome(
                eventID: eventID,
                episodeID: episode.id,
                outcome: outcome,
                timestampMilliseconds: timestampMilliseconds
            )
        }
        return false
    }

    private static func matchesSource(
        _ candidate: HWKAutobotEpisodeCandidate,
        tokenFingerprint: UInt64,
        styleFingerprint: UInt64?
    ) -> Bool {
        candidate.sourceFingerprint == observedFingerprint(
            for: candidate,
            tokenFingerprint: tokenFingerprint,
            styleFingerprint: styleFingerprint
        )
    }

    private static func matchesReplacement(
        _ candidate: HWKAutobotEpisodeCandidate,
        tokenFingerprint: UInt64,
        styleFingerprint: UInt64?
    ) -> Bool {
        candidate.replacementFingerprint == observedFingerprint(
            for: candidate,
            tokenFingerprint: tokenFingerprint,
            styleFingerprint: styleFingerprint
        )
    }

    private static func observedFingerprint(
        for candidate: HWKAutobotEpisodeCandidate,
        tokenFingerprint: UInt64,
        styleFingerprint: UInt64?
    ) -> UInt64? {
        candidate.styleTransition?.dimension == .letterCase
            ? styleFingerprint
            : tokenFingerprint
    }

    mutating func observeCommittedSpan(
        contextFingerprint: UInt64,
        spanFingerprint: UInt64,
        styleSpanFingerprint: UInt64? = nil,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> HWKAutobotEpisodeOutcome? {
        observeCommittedToken(
            contextFingerprint: contextFingerprint,
            tokenFingerprint: spanFingerprint,
            styleFingerprint: styleSpanFingerprint,
            isSensitive: isSensitive,
            timestampMilliseconds: timestampMilliseconds
        )
    }

    mutating func cancelActiveExposure() {
        guard let activeExposure else { return }
        _ = recorder.discardShownEpisode(episodeID: activeExposure.episodeID)
        self.activeExposure = nil
    }

    mutating func rotateAttributionEpoch(
        focusEpoch: inout UInt64,
        appliedSpanTracker: inout HWKAutobotAppliedSpanTracker
    ) {
        focusEpoch &+= 1
        appliedSpanTracker.clear()
        cancelActiveExposure()
    }

    mutating func applyAttributionTransition(
        _ transition: HWKAutobotTextContextContinuity,
        focusEpoch: inout UInt64,
        appliedSpanTracker: inout HWKAutobotAppliedSpanTracker
    ) -> Bool {
        guard transition.requiresAttributionEpochRotation else { return false }
        rotateAttributionEpoch(
            focusEpoch: &focusEpoch,
            appliedSpanTracker: &appliedSpanTracker
        )
        return true
    }

    func snapshot() -> HWKAutobotTypingEpisodeSnapshot {
        recorder.snapshot()
    }

    func credit(candidateID: UInt64) -> Int {
        recorder.credit(candidateID: candidateID)
    }

    func encodedResolvedReplay() throws -> Data? {
        let snapshot = recorder.snapshot()
        guard activeExposure == nil,
              !snapshot.episodes.contains(where: { $0.finalOutcome == .shown }) else {
            return nil
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let replay = try encoder.encode(ReplayEnvelope(
            schemaVersion: 3,
            recorderData: recorder.encodedReplay(),
            nextEventID: nextEventID,
            nextEpisodeID: nextEpisodeID,
            delayedRepairWindowMilliseconds: delayedRepairWindowMilliseconds
        ))
        return ReplayCompression.encoded(replay)
    }

    private mutating func takeNextEventID() -> UInt64 {
        defer { nextEventID &+= 1 }
        return nextEventID
    }

    private mutating func takeNextEpisodeID() -> UInt64 {
        defer { nextEpisodeID &+= 1 }
        return nextEpisodeID
    }
}

struct HWKAutobotTypingEpisodeStore {
    static let storageKey = "keyboard.autobot.typingEpisodes.v2"
    static let maximumEncodedBytes = 64 * 1_024

    private static let legacyStorageKey = "keyboard.autobot.typingEpisodes.v1"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    @discardableResult
    func save(_ coordinator: HWKAutobotLiveEpisodeCoordinator) -> Bool {
        do {
            guard let data = try coordinator.encodedResolvedReplay(),
                  data.count <= Self.maximumEncodedBytes else {
                return false
            }
            if coordinator.snapshot().episodes.isEmpty {
                clear()
                return defaults.data(forKey: Self.storageKey) == nil
            } else {
                let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                    storeIDs: [.typingEpisodes]
                ) {
                    defaults.set(data, forKey: Self.storageKey)
                    defaults.removeObject(forKey: Self.legacyStorageKey)
                    return true
                }
                return result.value ?? false
            }
        } catch {
            return false
        }
    }

    func load() -> HWKAutobotLiveEpisodeCoordinator? {
        if defaults.data(forKey: Self.storageKey) == nil,
           defaults.data(forKey: Self.legacyStorageKey) != nil {
            HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
                storeIDs: [.typingEpisodes]
            ) {
                defaults.removeObject(forKey: Self.legacyStorageKey)
            }
            return nil
        }
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        guard !data.isEmpty, data.count <= Self.maximumEncodedBytes else {
            clear()
            return nil
        }
        do {
            return try HWKAutobotLiveEpisodeCoordinator(replaying: data)
        } catch {
            clear()
            return nil
        }
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.typingEpisodes]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.legacyStorageKey)
        }
    }
}

struct HWKAutobotRuleHypothesis: Equatable, Identifiable {
    let id: UInt64
    let source: String
    let replacement: String
    let supportingEvidenceCount: Int
    let contradictingEvidenceCount: Int
    let boundaryRoles: [HWKAutobotBoundaryRole]
    let confidence: Double
    let explanation: String
}

struct HWKAutobotRuleHypothesisStorageMetrics: Equatable {
    let candidateCount: Int
    let receiptCount: Int
    let encodedBytes: Int
}

struct HWKAutobotRomanizedHypothesis: Equatable, Identifiable {
    let id: UInt64
    let romanizedText: String
    let nativeScriptText: String
    let supportingEvidenceCount: Int
    let contradictingEvidenceCount: Int
    let confidence: Double
    let explanation: String
}

struct HWKAutobotRomanizedHypothesisStorageMetrics: Equatable {
    let candidateCount: Int
    let receiptCount: Int
    let encodedBytes: Int
}

/// Private evidence ledger for user-observed romanized -> native-script mappings.
/// It never translates, activates a rule, or mutates text by itself.
struct HWKAutobotRomanizedHypothesisStore {
    static let storageKey = "keyboard.autobot.romanizedHypotheses.v1"
    static let maximumEncodedBytes = 32 * 1_024
    static let maximumCandidates = 32
    static let maximumDecisions = 32
    static let maximumReceipts = 96
    static let minimumSupportingEvidence = 3
    static let outcomeMaturityMilliseconds: Int64 = 60_000

    private struct CandidateRecord: Codable, Equatable {
        let candidateKey: UInt64
        let romanizedText: String
        let nativeScriptText: String
        var lastObservedAtMilliseconds: Int64
    }

    private struct Receipt: Codable, Equatable {
        let episodeID: UInt64
        let candidateKey: UInt64
        let credit: Int
        let updatedAtMilliseconds: Int64
    }

    private enum Disposition: String, Codable {
        case rejected
        case confirmed
    }

    private struct DecisionRecord: Codable, Equatable {
        let candidateKey: UInt64
        var disposition: Disposition
        var rejectedThroughEpisodeID: UInt64
        var updatedAtMilliseconds: Int64
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var candidates: [CandidateRecord]
        var receipts: [Receipt]
        var decisions: [DecisionRecord]?

        static let empty = Envelope(
            schemaVersion: 1,
            candidates: [],
            receipts: [],
            decisions: []
        )
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return false
        }
        return Self(defaults: .standard).isValid(envelope)
    }

    @discardableResult
    func rememberCandidate(
        source: String,
        replacement: String,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> UInt64? {
        guard !isSensitive,
              let source = Self.normalizedText(source),
              let replacement = Self.normalizedText(replacement),
              !Self.containsDecimalDigit(source) ||
                HWKAutobotEpisodeLanguage.classify(prefix: source) == .romanizedNonEnglish,
              HWKAutobotScriptEvidence.containsSupportedNativeScript(replacement) else {
            return nil
        }
        let candidateKey = HWKAutobotEpisodeFingerprint.candidatePair(
            source: source,
            replacement: replacement
        )
        var envelope = loadEnvelope()
        if let index = envelope.candidates.firstIndex(where: {
            $0.candidateKey == candidateKey
        }) {
            envelope.candidates[index].lastObservedAtMilliseconds = max(
                envelope.candidates[index].lastObservedAtMilliseconds,
                timestampMilliseconds
            )
        } else {
            envelope.candidates.append(CandidateRecord(
                candidateKey: candidateKey,
                romanizedText: source,
                nativeScriptText: replacement,
                lastObservedAtMilliseconds: timestampMilliseconds
            ))
        }
        enforceCapacities(&envelope)
        guard save(envelope) else { return nil }
        return candidateKey
    }

    @discardableResult
    func reconcile(_ snapshot: HWKAutobotTypingEpisodeSnapshot) -> Bool {
        var envelope = loadEnvelope()
        var changed = false
        for episode in snapshot.episodes {
            guard episode.language == .romanizedNonEnglish,
                  let resolvedCandidateID = episode.resolvedCandidateID,
                  let candidate = episode.candidates.first(where: {
                      $0.id == resolvedCandidateID
                  }) else {
                let count = envelope.receipts.count
                envelope.receipts.removeAll { $0.episodeID == episode.id }
                changed = changed || count != envelope.receipts.count
                continue
            }
            if candidate.ruleFingerprint != nil {
                let count = envelope.receipts.count
                envelope.receipts.removeAll { $0.episodeID == episode.id }
                changed = changed || count != envelope.receipts.count
                continue
            }
            guard let credit = Self.credit(for: episode.finalOutcome) else {
                let count = envelope.receipts.count
                envelope.receipts.removeAll { $0.episodeID == episode.id }
                changed = changed || count != envelope.receipts.count
                continue
            }
            let candidateKey = HWKAutobotEpisodeFingerprint.candidatePair(
                sourceFingerprint: candidate.sourceFingerprint,
                replacementFingerprint: candidate.replacementFingerprint
            )
            guard envelope.candidates.contains(where: {
                $0.candidateKey == candidateKey
            }) else { continue }
            let receipt = Receipt(
                episodeID: episode.id,
                candidateKey: candidateKey,
                credit: credit,
                updatedAtMilliseconds: episode.updatedAtMilliseconds
            )
            if let index = envelope.receipts.firstIndex(where: {
                $0.episodeID == episode.id
            }) {
                guard envelope.receipts[index] != receipt else { continue }
                envelope.receipts[index] = receipt
            } else {
                envelope.receipts.append(receipt)
            }
            changed = true
        }
        guard changed else { return false }
        enforceCapacities(&envelope)
        return save(envelope)
    }

    func pendingHypotheses(
        timestampMilliseconds: Int64 = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    ) -> [HWKAutobotRomanizedHypothesis] {
        let envelope = loadEnvelope()
        return envelope.candidates.compactMap { candidate in
            let decision = envelope.decisions?.first {
                $0.candidateKey == candidate.candidateKey
            }
            guard decision?.disposition != .confirmed else { return nil }
            let evidenceFloor = decision?.disposition == .rejected
                ? decision?.rejectedThroughEpisodeID ?? 0
                : 0
            let receipts = envelope.receipts.filter {
                $0.candidateKey == candidate.candidateKey &&
                $0.episodeID > evidenceFloor &&
                timestampMilliseconds - $0.updatedAtMilliseconds >= Self.outcomeMaturityMilliseconds
            }
            let supporting = receipts.filter { $0.credit > 0 }.count
            let contradicting = receipts.filter { $0.credit < 0 }.count
            guard supporting >= Self.minimumSupportingEvidence,
                  contradicting == 0 else { return nil }
            return HWKAutobotRomanizedHypothesis(
                id: candidate.candidateKey,
                romanizedText: candidate.romanizedText,
                nativeScriptText: candidate.nativeScriptText,
                supportingEvidenceCount: supporting,
                contradictingEvidenceCount: contradicting,
                confidence: min(0.99, 0.70 + Double(supporting) * 0.05),
                explanation: "Romanized-language proposal from \(supporting) accepted choices; review before teaching."
            )
        }.sorted {
            if $0.supportingEvidenceCount != $1.supportingEvidenceCount {
                return $0.supportingEvidenceCount > $1.supportingEvidenceCount
            }
            return $0.id < $1.id
        }
    }

    @discardableResult
    func reject(id: UInt64) -> Bool {
        guard pendingHypotheses().contains(where: { $0.id == id }) else { return false }
        let envelope = loadEnvelope()
        let evidenceFloor = envelope.receipts
            .filter { $0.candidateKey == id }
            .map(\.episodeID)
            .max() ?? 0
        return saveDecision(
            id: id,
            disposition: .rejected,
            rejectedThroughEpisodeID: evidenceFloor
        )
    }

    @discardableResult
    func confirm(id: UInt64) -> Bool {
        guard pendingHypotheses().contains(where: { $0.id == id }) else { return false }
        return saveDecision(
            id: id,
            disposition: .confirmed,
            rejectedThroughEpisodeID: 0,
            pruneReceipts: true
        )
    }

    func storageMetrics() -> HWKAutobotRomanizedHypothesisStorageMetrics {
        let envelope = loadEnvelope()
        return HWKAutobotRomanizedHypothesisStorageMetrics(
            candidateCount: envelope.candidates.count,
            receiptCount: envelope.receipts.count,
            encodedBytes: defaults.data(forKey: Self.storageKey)?.count ?? 0
        )
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.romanizedHypotheses]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    private func loadEnvelope() -> Envelope {
        guard let data = defaults.data(forKey: Self.storageKey) else { return .empty }
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              isValid(envelope) else {
            clear()
            return .empty
        }
        return envelope
    }

    private func save(_ sourceEnvelope: Envelope) -> Bool {
        var envelope = sourceEnvelope
        envelope.schemaVersion = 1
        if envelope.decisions == nil { envelope.decisions = [] }
        enforceCapacities(&envelope)
        envelope.candidates.sort { $0.candidateKey < $1.candidateKey }
        envelope.receipts.sort { $0.episodeID < $1.episodeID }
        envelope.decisions?.sort { $0.candidateKey < $1.candidateKey }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              data.count <= Self.maximumEncodedBytes else { return false }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.romanizedHypotheses]
        ) {
            defaults.set(data, forKey: Self.storageKey)
            return true
        }
        return result.value ?? false
    }

    private func saveDecision(
        id: UInt64,
        disposition: Disposition,
        rejectedThroughEpisodeID: UInt64,
        pruneReceipts: Bool = false
    ) -> Bool {
        var envelope = loadEnvelope()
        guard envelope.candidates.contains(where: { $0.candidateKey == id }) else {
            return false
        }
        var decisions = envelope.decisions ?? []
        let timestampMilliseconds = Int64(
            (Date().timeIntervalSince1970 * 1_000).rounded()
        )
        if let index = decisions.firstIndex(where: { $0.candidateKey == id }) {
            decisions[index].disposition = disposition
            decisions[index].rejectedThroughEpisodeID = rejectedThroughEpisodeID
            decisions[index].updatedAtMilliseconds = timestampMilliseconds
        } else {
            decisions.append(DecisionRecord(
                candidateKey: id,
                disposition: disposition,
                rejectedThroughEpisodeID: rejectedThroughEpisodeID,
                updatedAtMilliseconds: timestampMilliseconds
            ))
        }
        envelope.decisions = decisions
        if pruneReceipts {
            envelope.receipts.removeAll { $0.candidateKey == id }
        }
        enforceCapacities(&envelope)
        return save(envelope)
    }

    private func isValid(_ envelope: Envelope) -> Bool {
        envelope.schemaVersion == 1 &&
        envelope.candidates.count <= Self.maximumCandidates &&
        envelope.receipts.count <= Self.maximumReceipts &&
        Set(envelope.candidates.map(\.candidateKey)).count == envelope.candidates.count &&
        Set(envelope.receipts.map(\.episodeID)).count == envelope.receipts.count &&
        Set((envelope.decisions ?? []).map(\.candidateKey)).count
            == (envelope.decisions ?? []).count &&
        (envelope.decisions ?? []).count <= Self.maximumDecisions &&
        envelope.candidates.allSatisfy {
            Self.normalizedText($0.romanizedText) == $0.romanizedText &&
            Self.normalizedText($0.nativeScriptText) == $0.nativeScriptText &&
            HWKAutobotScriptEvidence.containsSupportedNativeScript($0.nativeScriptText)
        } &&
        envelope.receipts.allSatisfy { receipt in
            (receipt.credit == -1 || receipt.credit == 1) &&
            receipt.updatedAtMilliseconds >= 0 &&
            envelope.candidates.contains { $0.candidateKey == receipt.candidateKey }
        } &&
        (envelope.decisions ?? []).allSatisfy { decision in
            decision.updatedAtMilliseconds >= 0 &&
            (decision.disposition == .confirmed || decision.rejectedThroughEpisodeID > 0) &&
            envelope.candidates.contains { $0.candidateKey == decision.candidateKey }
        }
    }

    private func enforceCapacities(_ envelope: inout Envelope) {
        if envelope.receipts.count > Self.maximumReceipts {
            envelope.receipts = Array(envelope.receipts.sorted {
                $0.episodeID > $1.episodeID
            }.prefix(Self.maximumReceipts))
        }
        if envelope.candidates.count > Self.maximumCandidates {
            let retained = envelope.candidates.sorted {
                $0.lastObservedAtMilliseconds > $1.lastObservedAtMilliseconds
            }.prefix(Self.maximumCandidates)
            envelope.candidates = Array(retained)
            let keys = Set(envelope.candidates.map(\.candidateKey))
            envelope.receipts.removeAll { !keys.contains($0.candidateKey) }
            envelope.decisions?.removeAll { !keys.contains($0.candidateKey) }
        }
        if let decisions = envelope.decisions,
           decisions.count > Self.maximumDecisions {
            envelope.decisions = Array(decisions.sorted {
                $0.updatedAtMilliseconds > $1.updatedAtMilliseconds
            }.prefix(Self.maximumDecisions))
        }
    }

    private static func normalizedText(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= 96,
              !normalized.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
        return normalized
    }

    private static func containsDecimalDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }

    private static func credit(for outcome: HWKAutobotEpisodeOutcome) -> Int? {
        switch outcome {
        case .accepted:
            return 1
        case .undo, .backspace, .retype, .delayedRepair:
            return -1
        case .shown, .ignored:
            return nil
        }
    }
}

struct HWKAutobotRuleHypothesisStore {
    static let storageKey = "keyboard.autobot.ruleHypotheses.v1"
    static let decisionStorageKey = "keyboard.autobot.ruleHypothesisDecisions.v1"
    static let maximumEncodedBytes = 32 * 1_024
    static let maximumDecisionEncodedBytes = 8 * 1_024
    static let maximumCandidates = 32
    static let maximumDecisions = 32
    static let maximumReceipts = 96
    static let minimumSupportingEvidence = 3
    static let outcomeMaturityMilliseconds: Int64 = 60_000

    private enum Disposition: String, Codable {
        case rejected
        case confirmed
    }

    private struct CandidateRecord: Codable, Equatable {
        let candidateKey: UInt64
        let source: String
        let replacement: String
        var lastObservedAtMilliseconds: Int64
    }

    private struct DecisionRecord: Codable, Equatable {
        let candidateKey: UInt64
        var disposition: Disposition
        var rejectedThroughEpisodeID: UInt64
        var updatedAtMilliseconds: Int64
    }

    private struct Receipt: Codable, Equatable {
        let episodeID: UInt64
        let candidateKey: UInt64
        let credit: Int
        let boundaryRole: HWKAutobotBoundaryRole?
        let updatedAtMilliseconds: Int64

        private enum CodingKeys: String, CodingKey {
            case episodeID
            case candidateKey
            case credit
            case boundaryRole
            case updatedAtMilliseconds
        }

        init(
            episodeID: UInt64,
            candidateKey: UInt64,
            credit: Int,
            boundaryRole: HWKAutobotBoundaryRole?,
            updatedAtMilliseconds: Int64
        ) {
            self.episodeID = episodeID
            self.candidateKey = candidateKey
            self.credit = credit
            self.boundaryRole = boundaryRole
            self.updatedAtMilliseconds = updatedAtMilliseconds
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            episodeID = try container.decode(UInt64.self, forKey: .episodeID)
            candidateKey = try container.decode(UInt64.self, forKey: .candidateKey)
            credit = try container.decode(Int.self, forKey: .credit)
            boundaryRole = try container.decodeIfPresent(
                HWKAutobotBoundaryRole.self,
                forKey: .boundaryRole
            )
            updatedAtMilliseconds = try container.decodeIfPresent(
                Int64.self,
                forKey: .updatedAtMilliseconds
            ) ?? 0
        }
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var candidates: [CandidateRecord]
        var receipts: [Receipt]

        static let empty = Envelope(schemaVersion: 2, candidates: [], receipts: [])
    }

    private struct DecisionEnvelope: Codable {
        var schemaVersion: Int
        var decisions: [DecisionRecord]

        static let empty = DecisionEnvelope(schemaVersion: 1, decisions: [])
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidHypothesisPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            return false
        }
        return Self(defaults: .standard).isValid(envelope)
    }

    static func isValidDecisionPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumDecisionEncodedBytes,
              let envelope = try? JSONDecoder().decode(DecisionEnvelope.self, from: data) else {
            return false
        }
        return Self(defaults: .standard).isValid(envelope)
    }

    @discardableResult
    func rememberCandidate(
        source: String,
        replacement: String,
        isSensitive: Bool,
        timestampMilliseconds: Int64
    ) -> UInt64? {
        guard !isSensitive,
              let source = Self.normalizedVisibleText(source),
              let replacement = Self.normalizedVisibleText(replacement),
              source.caseInsensitiveCompare(replacement) != .orderedSame else {
            return nil
        }
        let candidateKey = HWKAutobotEpisodeFingerprint.candidatePair(
            source: source,
            replacement: replacement
        )
        var envelope = loadEnvelope()
        if let index = envelope.candidates.firstIndex(where: {
            $0.candidateKey == candidateKey
        }) {
            envelope.candidates[index].lastObservedAtMilliseconds = max(
                envelope.candidates[index].lastObservedAtMilliseconds,
                timestampMilliseconds
            )
        } else {
            envelope.candidates.append(CandidateRecord(
                candidateKey: candidateKey,
                source: source,
                replacement: replacement,
                lastObservedAtMilliseconds: timestampMilliseconds
            ))
        }
        enforceCapacities(&envelope)
        guard save(envelope) else { return nil }
        return candidateKey
    }

    @discardableResult
    func reconcile(_ snapshot: HWKAutobotTypingEpisodeSnapshot) -> Bool {
        var envelope = loadEnvelope()
        var changed = false
        for episode in snapshot.episodes {
            if episode.language != .english {
                let receiptCount = envelope.receipts.count
                envelope.receipts.removeAll { $0.episodeID == episode.id }
                changed = changed || envelope.receipts.count != receiptCount
                continue
            }
            guard let resolvedCandidateID = episode.resolvedCandidateID,
                  let candidate = episode.candidates.first(where: { $0.id == resolvedCandidateID }),
                  let credit = Self.credit(for: episode.finalOutcome) else {
                continue
            }
            let candidateKey = HWKAutobotEpisodeFingerprint.candidatePair(
                sourceFingerprint: candidate.sourceFingerprint,
                replacementFingerprint: candidate.replacementFingerprint
            )
            guard envelope.candidates.contains(where: {
                $0.candidateKey == candidateKey
            }) else {
                continue
            }
            let receipt = Receipt(
                episodeID: episode.id,
                candidateKey: candidateKey,
                credit: credit,
                boundaryRole: episode.learningContext?.boundaryRole,
                updatedAtMilliseconds: episode.updatedAtMilliseconds
            )
            if let index = envelope.receipts.firstIndex(where: {
                $0.episodeID == episode.id
            }) {
                guard envelope.receipts[index] != receipt else { continue }
                envelope.receipts[index] = receipt
            } else {
                envelope.receipts.append(receipt)
            }
            changed = true
        }
        guard changed else { return false }
        enforceCapacities(&envelope)
        return save(envelope)
    }

    func pendingHypotheses(
        timestampMilliseconds: Int64 = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
    ) -> [HWKAutobotRuleHypothesis] {
        let decisionEnvelope = loadDecisionEnvelope()
        let envelope = loadEnvelope()
        return envelope.candidates.compactMap { candidate in
            let decision = decisionEnvelope.decisions.first {
                $0.candidateKey == candidate.candidateKey
            }
            guard decision?.disposition != .confirmed else { return nil }
            let evidenceFloor = decision?.disposition == .rejected
                ? decision?.rejectedThroughEpisodeID ?? 0
                : 0
            let relevantReceipts = envelope.receipts.filter {
                let age = timestampMilliseconds - $0.updatedAtMilliseconds
                return $0.candidateKey == candidate.candidateKey &&
                    $0.episodeID > evidenceFloor &&
                    age >= Self.outcomeMaturityMilliseconds
            }
            let supporting = relevantReceipts.filter { $0.credit > 0 }
            let contradicting = relevantReceipts.filter { $0.credit < 0 }
            guard supporting.count >= Self.minimumSupportingEvidence,
                  contradicting.isEmpty else {
                return nil
            }
            let boundaryRoles = Array(Set(supporting.compactMap(\.boundaryRole))).sorted {
                $0.rawValue < $1.rawValue
            }
            let confidence = min(0.99, 0.70 + Double(supporting.count) * 0.05)
            return HWKAutobotRuleHypothesis(
                id: candidate.candidateKey,
                source: candidate.source,
                replacement: candidate.replacement,
                supportingEvidenceCount: supporting.count,
                contradictingEvidenceCount: contradicting.count,
                boundaryRoles: boundaryRoles,
                confidence: confidence,
                explanation: Self.explanation(
                    source: candidate.source,
                    replacement: candidate.replacement,
                    evidenceCount: supporting.count,
                    boundaryRoles: boundaryRoles
                )
            )
        }.sorted {
            if $0.supportingEvidenceCount != $1.supportingEvidenceCount {
                return $0.supportingEvidenceCount > $1.supportingEvidenceCount
            }
            return $0.id < $1.id
        }
    }

    func storageMetrics() -> HWKAutobotRuleHypothesisStorageMetrics {
        _ = loadDecisionEnvelope()
        let envelope = loadEnvelope()
        return HWKAutobotRuleHypothesisStorageMetrics(
            candidateCount: envelope.candidates.count,
            receiptCount: envelope.receipts.count,
            encodedBytes: (defaults.data(forKey: Self.storageKey)?.count ?? 0) +
                (defaults.data(forKey: Self.decisionStorageKey)?.count ?? 0)
        )
    }

    @discardableResult
    func reject(id: UInt64) -> Bool {
        guard pendingHypotheses().contains(where: { $0.id == id }) else { return false }
        let envelope = loadEnvelope()
        guard envelope.candidates.contains(where: {
            $0.candidateKey == id
        }) else { return false }
        let rejectedThroughEpisodeID = envelope.receipts
            .filter { $0.candidateKey == id }
            .map(\.episodeID)
            .max() ?? 0
        return saveDecision(
            id: id,
            disposition: .rejected,
            rejectedThroughEpisodeID: rejectedThroughEpisodeID
        )
    }

    @discardableResult
    func confirm(id: UInt64) -> Bool {
        guard pendingHypotheses().contains(where: { $0.id == id }) else { return false }
        let envelope = loadEnvelope()
        guard envelope.candidates.contains(where: {
            $0.candidateKey == id
        }) else { return false }
        return saveDecision(
            id: id,
            disposition: .confirmed,
            rejectedThroughEpisodeID: 0
        )
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.ruleHypotheses, .ruleDecisions]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.decisionStorageKey)
        }
    }

    private func loadEnvelope() -> Envelope {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return .empty
        }
        guard !data.isEmpty, data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              isValid(envelope) else {
            clear()
            return .empty
        }
        return envelope
    }

    private func loadDecisionEnvelope() -> DecisionEnvelope {
        guard let data = defaults.data(forKey: Self.decisionStorageKey) else {
            return .empty
        }
        guard !data.isEmpty, data.count <= Self.maximumDecisionEncodedBytes,
              let envelope = try? JSONDecoder().decode(DecisionEnvelope.self, from: data),
              isValid(envelope) else {
            clear()
            return .empty
        }
        return envelope
    }

    private func save(_ sourceEnvelope: Envelope) -> Bool {
        var envelope = sourceEnvelope
        envelope.schemaVersion = 2
        enforceCapacities(&envelope)
        envelope.candidates.sort { $0.candidateKey < $1.candidateKey }
        envelope.receipts.sort { $0.episodeID < $1.episodeID }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              data.count <= Self.maximumEncodedBytes else {
            return false
        }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.ruleHypotheses]
        ) {
            defaults.set(data, forKey: Self.storageKey)
            return true
        }
        return result.value ?? false
    }

    private func saveDecision(
        id: UInt64,
        disposition: Disposition,
        rejectedThroughEpisodeID: UInt64
    ) -> Bool {
        var envelope = loadDecisionEnvelope()
        let timestampMilliseconds = Int64(
            (Date().timeIntervalSince1970 * 1_000).rounded()
        )
        if let index = envelope.decisions.firstIndex(where: { $0.candidateKey == id }) {
            envelope.decisions[index].disposition = disposition
            envelope.decisions[index].rejectedThroughEpisodeID = rejectedThroughEpisodeID
            envelope.decisions[index].updatedAtMilliseconds = timestampMilliseconds
        } else {
            envelope.decisions.append(DecisionRecord(
                candidateKey: id,
                disposition: disposition,
                rejectedThroughEpisodeID: rejectedThroughEpisodeID,
                updatedAtMilliseconds: timestampMilliseconds
            ))
        }
        enforceDecisionCapacity(&envelope)
        return save(envelope)
    }

    private func save(_ sourceEnvelope: DecisionEnvelope) -> Bool {
        var envelope = sourceEnvelope
        envelope.schemaVersion = 1
        enforceDecisionCapacity(&envelope)
        envelope.decisions.sort { $0.candidateKey < $1.candidateKey }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              data.count <= Self.maximumDecisionEncodedBytes else {
            return false
        }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.ruleDecisions]
        ) {
            defaults.set(data, forKey: Self.decisionStorageKey)
            return true
        }
        return result.value ?? false
    }

    private func isValid(_ envelope: Envelope) -> Bool {
        (envelope.schemaVersion == 1 || envelope.schemaVersion == 2) &&
        envelope.candidates.count <= Self.maximumCandidates &&
        envelope.receipts.count <= Self.maximumReceipts &&
        Set(envelope.candidates.map(\.candidateKey)).count == envelope.candidates.count &&
        Set(envelope.receipts.map(\.episodeID)).count == envelope.receipts.count &&
        envelope.candidates.allSatisfy {
            !$0.source.isEmpty && !$0.replacement.isEmpty &&
            $0.source.count <= 96 && $0.replacement.count <= 96 &&
            $0.source.caseInsensitiveCompare($0.replacement) != .orderedSame
        } &&
        envelope.receipts.allSatisfy { receipt in
            (receipt.credit == -1 || receipt.credit == 1) &&
            receipt.updatedAtMilliseconds >= 0 &&
            envelope.candidates.contains { $0.candidateKey == receipt.candidateKey }
        }
    }

    private func isValid(_ envelope: DecisionEnvelope) -> Bool {
        envelope.schemaVersion == 1 &&
        envelope.decisions.count <= Self.maximumDecisions &&
        Set(envelope.decisions.map(\.candidateKey)).count == envelope.decisions.count &&
        envelope.decisions.allSatisfy {
            $0.updatedAtMilliseconds >= 0 &&
            ($0.disposition == .confirmed || $0.rejectedThroughEpisodeID > 0)
        }
    }

    private func enforceCapacities(_ envelope: inout Envelope) {
        if envelope.receipts.count > Self.maximumReceipts {
            envelope.receipts = Array(
                envelope.receipts.sorted { $0.episodeID > $1.episodeID }
                    .prefix(Self.maximumReceipts)
            )
        }
        while envelope.candidates.count > Self.maximumCandidates {
            guard let oldestIndex = envelope.candidates.indices.min(by: { left, right in
                let leftCandidate = envelope.candidates[left]
                let rightCandidate = envelope.candidates[right]
                if leftCandidate.lastObservedAtMilliseconds != rightCandidate.lastObservedAtMilliseconds {
                    return leftCandidate.lastObservedAtMilliseconds < rightCandidate.lastObservedAtMilliseconds
                }
                return leftCandidate.candidateKey < rightCandidate.candidateKey
            }) else { break }
            let removedKey = envelope.candidates.remove(at: oldestIndex).candidateKey
            envelope.receipts.removeAll { $0.candidateKey == removedKey }
        }
    }

    private func enforceDecisionCapacity(_ envelope: inout DecisionEnvelope) {
        guard envelope.decisions.count > Self.maximumDecisions else { return }
        envelope.decisions = Array(
            envelope.decisions.sorted { left, right in
                if left.updatedAtMilliseconds != right.updatedAtMilliseconds {
                    return left.updatedAtMilliseconds > right.updatedAtMilliseconds
                }
                return left.candidateKey < right.candidateKey
            }.prefix(Self.maximumDecisions)
        )
    }

    private static func credit(for outcome: HWKAutobotEpisodeOutcome) -> Int? {
        switch outcome {
        case .accepted, .delayedRepair:
            return 1
        case .undo, .backspace, .retype:
            return -1
        case .shown, .ignored:
            return nil
        }
    }

    private static func normalizedVisibleText(_ text: String) -> String? {
        let withoutControls = text.components(separatedBy: .controlCharacters).joined()
        let normalized = withoutControls.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.count <= 96,
              !normalized.contains("\"") else {
            return nil
        }
        return normalized
    }

    private static func explanation(
        source: String,
        replacement: String,
        evidenceCount: Int,
        boundaryRoles: [HWKAutobotBoundaryRole]
    ) -> String {
        let contextSummary: String
        if boundaryRoles.isEmpty {
            contextSummary = "across resolved typing decisions"
        } else {
            contextSummary = "in " + boundaryRoles.map(\.explanationLabel).joined(separator: ", ")
        }
        return "I saw you choose “\(replacement)” instead of “\(source)” \(evidenceCount) times \(contextSummary), with no conflicting decision. This is a proposal; teaching it adds a suggestion-only My Rule."
    }
}

private extension HWKAutobotBoundaryRole {
    var explanationLabel: String {
        switch self {
        case .sentenceStart: return "new sentences"
        case .afterQuestion: return "text after questions"
        case .afterExclamation: return "text after exclamations"
        case .afterClause: return "clause continuations"
        case .continuation: return "continuing text"
        }
    }
}

struct HWKAutobotEpisodeCreditModel: Codable, Equatable, Sendable {
    private struct CandidateEvidence: Codable, Equatable, Sendable {
        let candidateKey: UInt64
        var positiveCount: Int
        var negativeCount: Int
        var lastEpisodeID: UInt64
    }

    private struct Contribution: Codable, Equatable, Sendable {
        let episodeID: UInt64
        let candidateKey: UInt64
        var contextualKey: UInt64?
        let credit: Int
    }

    private struct StyleContribution: Codable, Equatable, Sendable {
        let episodeID: UInt64
        let dimension: HWKAutobotEnglishStyleDimension
        let boundaryRole: HWKAutobotBoundaryRole?
        let credit: Int
    }

    private struct SourceContribution: Codable, Equatable, Sendable {
        let episodeID: UInt64
        let source: HWKAutobotCandidateEvidenceSource
        let credit: Int
    }

    private enum CodingKeys: String, CodingKey {
        case capacity
        case evidence
        case contextualEvidence
        case contributions
        case styleEvidence
        case contextualStyleEvidence
        case styleContributions
        case sourceContributions
    }

    private(set) var capacity: Int
    private var evidence: [CandidateEvidence]
    private var contextualEvidence: [CandidateEvidence]
    private var contributions: [Contribution]
    private var styleEvidence: [CandidateEvidence]
    private var contextualStyleEvidence: [CandidateEvidence]
    private var styleContributions: [StyleContribution]
    private var sourceContributions: [SourceContribution]

    init(capacity: Int = 128) {
        self.capacity = min(max(1, capacity), 128)
        self.evidence = []
        self.contextualEvidence = []
        self.contributions = []
        self.styleEvidence = []
        self.contextualStyleEvidence = []
        self.styleContributions = []
        self.sourceContributions = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        capacity = try container.decode(Int.self, forKey: .capacity)
        evidence = try container.decode([CandidateEvidence].self, forKey: .evidence)
        contextualEvidence = try container.decodeIfPresent(
            [CandidateEvidence].self,
            forKey: .contextualEvidence
        ) ?? []
        contributions = try container.decode([Contribution].self, forKey: .contributions)
        styleEvidence = try container.decodeIfPresent(
            [CandidateEvidence].self,
            forKey: .styleEvidence
        ) ?? []
        contextualStyleEvidence = try container.decodeIfPresent(
            [CandidateEvidence].self,
            forKey: .contextualStyleEvidence
        ) ?? []
        styleContributions = try container.decodeIfPresent(
            [StyleContribution].self,
            forKey: .styleContributions
        ) ?? []
        sourceContributions = try container.decodeIfPresent(
            [SourceContribution].self,
            forKey: .sourceContributions
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(capacity, forKey: .capacity)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(contextualEvidence, forKey: .contextualEvidence)
        try container.encode(contributions, forKey: .contributions)
        if !styleEvidence.isEmpty {
            try container.encode(styleEvidence, forKey: .styleEvidence)
        }
        if !contextualStyleEvidence.isEmpty {
            try container.encode(contextualStyleEvidence, forKey: .contextualStyleEvidence)
        }
        if !styleContributions.isEmpty {
            try container.encode(styleContributions, forKey: .styleContributions)
        }
        if !sourceContributions.isEmpty {
            try container.encode(sourceContributions, forKey: .sourceContributions)
        }
    }

    @discardableResult
    mutating func reconcile(_ snapshot: HWKAutobotTypingEpisodeSnapshot) -> Bool {
        var changed = false
        for episode in snapshot.episodes {
            if !episode.language.allowsBoundedEnglishLearning {
                let contributionCount = contributions.count
                let styleContributionCount = styleContributions.count
                let sourceContributionCount = sourceContributions.count
                contributions.removeAll { $0.episodeID == episode.id }
                styleContributions.removeAll { $0.episodeID == episode.id }
                sourceContributions.removeAll { $0.episodeID == episode.id }
                if contributions.count != contributionCount
                    || styleContributions.count != styleContributionCount
                    || sourceContributions.count != sourceContributionCount {
                    rebuildEvidence()
                    changed = true
                }
                continue
            }
            let ruleCandidateKeys = Set(episode.candidates.compactMap { candidate -> UInt64? in
                guard candidate.ruleFingerprint != nil else { return nil }
                return HWKAutobotEpisodeFingerprint.candidatePair(
                    sourceFingerprint: candidate.sourceFingerprint,
                    replacementFingerprint: candidate.replacementFingerprint
                )
            })
            if contributions.contains(where: { contribution in
                contribution.episodeID == episode.id &&
                    ruleCandidateKeys.contains(contribution.candidateKey)
            }) {
                contributions.removeAll { $0.episodeID == episode.id }
                styleContributions.removeAll { $0.episodeID == episode.id }
                sourceContributions.removeAll { $0.episodeID == episode.id }
                rebuildEvidence()
                changed = true
            }
            guard let resolvedCandidateID = episode.resolvedCandidateID,
                  let candidate = episode.candidates.first(where: { $0.id == resolvedCandidateID }) else {
                continue
            }
            if candidate.ruleFingerprint != nil {
                let contributionCount = contributions.count
                let styleContributionCount = styleContributions.count
                let sourceContributionCount = sourceContributions.count
                contributions.removeAll { $0.episodeID == episode.id }
                styleContributions.removeAll { $0.episodeID == episode.id }
                sourceContributions.removeAll { $0.episodeID == episode.id }
                guard contributions.count != contributionCount ||
                        styleContributions.count != styleContributionCount ||
                        sourceContributions.count != sourceContributionCount else {
                    continue
                }
                rebuildEvidence()
                changed = true
                continue
            }
            guard let credit = Self.credit(for: episode.finalOutcome) else {
                continue
            }
            let unscopedCandidateKey = HWKAutobotEpisodeFingerprint.candidatePair(
                sourceFingerprint: candidate.sourceFingerprint,
                replacementFingerprint: candidate.replacementFingerprint
            )
            let candidateKey = HWKAutobotEpisodeFingerprint.languageScopedCandidatePair(
                candidateKey: unscopedCandidateKey,
                language: episode.language
            )
            let contextualKey = episode.learningContext.map {
                HWKAutobotEpisodeFingerprint.contextualCandidatePair(
                    candidateKey: candidateKey,
                    learningContextFingerprint: $0.fingerprint
                )
            }
            let contribution = Contribution(
                episodeID: episode.id,
                candidateKey: candidateKey,
                contextualKey: contextualKey,
                credit: credit
            )
            var episodeChanged = false
            if let index = contributions.firstIndex(where: { $0.episodeID == episode.id }) {
                if contributions[index] != contribution {
                    contributions[index] = contribution
                    episodeChanged = true
                }
            } else {
                contributions.append(contribution)
                episodeChanged = true
            }

            let styleContribution = Self.styleContribution(
                for: episode,
                candidate: candidate,
                outcomeCredit: credit
            )
            if let index = styleContributions.firstIndex(where: {
                $0.episodeID == episode.id
            }) {
                if let styleContribution {
                    if styleContributions[index] != styleContribution {
                        styleContributions[index] = styleContribution
                        episodeChanged = true
                    }
                } else {
                    styleContributions.remove(at: index)
                    episodeChanged = true
                }
            } else if let styleContribution {
                styleContributions.append(styleContribution)
                episodeChanged = true
            }

            let sourceContribution = candidate.evidenceSource.map {
                SourceContribution(
                    episodeID: episode.id,
                    source: $0,
                    credit: credit
                )
            }
            if let index = sourceContributions.firstIndex(where: {
                $0.episodeID == episode.id
            }) {
                if let sourceContribution {
                    if sourceContributions[index] != sourceContribution {
                        sourceContributions[index] = sourceContribution
                        episodeChanged = true
                    }
                } else {
                    sourceContributions.remove(at: index)
                    episodeChanged = true
                }
            } else if let sourceContribution {
                sourceContributions.append(sourceContribution)
                episodeChanged = true
            }

            guard episodeChanged else { continue }
            enforceCapacities()
            rebuildEvidence()
            changed = true
        }
        return changed
    }

    func evidenceCount(for candidateKey: UInt64) -> Int {
        Self.evidenceCount(for: candidateKey, in: evidence)
    }

    func evidenceCount(
        for candidateKey: UInt64,
        language: HWKAutobotEpisodeLanguage
    ) -> Int {
        evidenceCount(for: HWKAutobotEpisodeFingerprint.languageScopedCandidatePair(
            candidateKey: candidateKey,
            language: language
        ))
    }

    func netCredit(for candidateKey: UInt64) -> Int {
        Self.netCredit(for: candidateKey, in: evidence)
    }

    func netCredit(
        for candidateKey: UInt64,
        language: HWKAutobotEpisodeLanguage
    ) -> Int {
        netCredit(for: HWKAutobotEpisodeFingerprint.languageScopedCandidatePair(
            candidateKey: candidateKey,
            language: language
        ))
    }

    func adjustment(for candidateKey: UInt64) -> Double {
        Self.adjustment(for: candidateKey, in: evidence)
    }

    func adjustment(
        for candidateKey: UInt64,
        learningContextFingerprint: UInt64?
    ) -> Double {
        guard let learningContextFingerprint else {
            return adjustment(for: candidateKey)
        }
        let contextualKey = HWKAutobotEpisodeFingerprint.contextualCandidatePair(
            candidateKey: candidateKey,
            learningContextFingerprint: learningContextFingerprint
        )
        let contextualCount = Self.evidenceCount(for: contextualKey, in: contextualEvidence)
        let contextualNet = Self.netCredit(for: contextualKey, in: contextualEvidence)
        guard contextualCount >= 2, contextualNet != 0 else {
            return adjustment(for: candidateKey)
        }
        return Self.adjustment(for: contextualKey, in: contextualEvidence)
    }

    func adjustment(
        for candidateKey: UInt64,
        language: HWKAutobotEpisodeLanguage,
        learningContextFingerprint: UInt64?
    ) -> Double {
        adjustment(
            for: HWKAutobotEpisodeFingerprint.languageScopedCandidatePair(
                candidateKey: candidateKey,
                language: language
            ),
            learningContextFingerprint: learningContextFingerprint
        )
    }

    func sourceEvidenceCount(
        for source: HWKAutobotCandidateEvidenceSource
    ) -> Int {
        sourceContributions.filter { $0.source == source }.count
    }

    func sourceNetCredit(
        for source: HWKAutobotCandidateEvidenceSource
    ) -> Int {
        sourceContributions.reduce(into: 0) { total, contribution in
            guard contribution.source == source else { return }
            total += contribution.credit
        }
    }

    func sourceAdjustment(
        for source: HWKAutobotCandidateEvidenceSource
    ) -> Double {
        let count = sourceEvidenceCount(for: source)
        guard count >= 3 else { return 0 }
        let net = sourceNetCredit(for: source)
        if net > 0 {
            return min(0.12, Double(net) * 0.04)
        }
        if net < 0 {
            return max(-0.15, Double(net) * 0.05)
        }
        return 0
    }

    func styleEvidenceCount(
        for dimension: HWKAutobotEnglishStyleDimension,
        boundaryRole: HWKAutobotBoundaryRole?
    ) -> Int {
        Self.evidenceCount(
            for: Self.styleKey(dimension: dimension, boundaryRole: boundaryRole),
            in: boundaryRole == nil ? styleEvidence : contextualStyleEvidence
        )
    }

    func styleNetCredit(
        for dimension: HWKAutobotEnglishStyleDimension,
        boundaryRole: HWKAutobotBoundaryRole?
    ) -> Int {
        Self.netCredit(
            for: Self.styleKey(dimension: dimension, boundaryRole: boundaryRole),
            in: boundaryRole == nil ? styleEvidence : contextualStyleEvidence
        )
    }

    var styleContributionCount: Int {
        styleContributions.count
    }

    func styleAdjustment(
        for transition: HWKAutobotEnglishStyleTransition,
        boundaryRole: HWKAutobotBoundaryRole?
    ) -> Double {
        guard transition.isValid else { return 0 }
        if let boundaryRole {
            let contextualKey = Self.styleKey(
                dimension: transition.dimension,
                boundaryRole: boundaryRole
            )
            let contextualCount = Self.evidenceCount(
                for: contextualKey,
                in: contextualStyleEvidence
            )
            if contextualCount > 0 {
                return Self.styleAdjustment(
                    for: transition,
                    key: contextualKey,
                    in: contextualStyleEvidence
                )
            }
            if transition.dimension == .letterCase {
                return 0
            }
        }
        return Self.styleAdjustment(
            for: transition,
            key: Self.styleKey(
                dimension: transition.dimension,
                boundaryRole: nil
            ),
            in: styleEvidence
        )
    }

    var isValid: Bool {
        guard (1...128).contains(capacity),
              evidence.count <= capacity,
              contextualEvidence.count <= contextualCapacity,
              contributions.count <= contributionCapacity,
              styleEvidence.count <= HWKAutobotEnglishStyleDimension.allCases.count,
              contextualStyleEvidence.count <=
                HWKAutobotEnglishStyleDimension.allCases.count * HWKAutobotBoundaryRole.allCases.count,
              styleContributions.count <= contributionCapacity,
              sourceContributions.count <= contributionCapacity,
              Set(evidence.map(\.candidateKey)).count == evidence.count,
              Set(contextualEvidence.map(\.candidateKey)).count == contextualEvidence.count,
              Set(contributions.map(\.episodeID)).count == contributions.count,
              Set(styleEvidence.map(\.candidateKey)).count == styleEvidence.count,
              Set(contextualStyleEvidence.map(\.candidateKey)).count == contextualStyleEvidence.count,
              Set(styleContributions.map(\.episodeID)).count == styleContributions.count,
              Set(sourceContributions.map(\.episodeID)).count == sourceContributions.count,
              Self.entriesAreValid(evidence),
              Self.entriesAreValid(contextualEvidence),
              Self.entriesAreValid(styleEvidence),
              Self.entriesAreValid(contextualStyleEvidence),
              contributions.allSatisfy({ $0.credit == -1 || $0.credit == 1 }),
              styleContributions.allSatisfy({ $0.credit == -1 || $0.credit == 1 }),
              sourceContributions.allSatisfy({ $0.credit == -1 || $0.credit == 1 }),
              evidence.allSatisfy({ entry in
                  Self.matches(entry, receipts: contributions.filter {
                      $0.candidateKey == entry.candidateKey
                  })
              }),
              contextualEvidence.allSatisfy({ entry in
                  Self.matches(entry, receipts: contributions.filter {
                      $0.contextualKey == entry.candidateKey
                  })
              }),
              contributions.allSatisfy({ receipt in
                  evidence.contains { $0.candidateKey == receipt.candidateKey } &&
                  (receipt.contextualKey == nil || contextualEvidence.contains {
                      $0.candidateKey == receipt.contextualKey
                  })
              }),
              styleEvidence == Self.aggregateStyle(
                contributions: styleContributions,
                contextual: false
              ),
              contextualStyleEvidence == Self.aggregateStyle(
                contributions: styleContributions,
                contextual: true
              ) else {
            return false
        }
        return true
    }

    private var contributionCapacity: Int {
        min(256, max(32, capacity * 2))
    }

    private var contextualCapacity: Int {
        contributionCapacity
    }

    private static func credit(for outcome: HWKAutobotEpisodeOutcome) -> Int? {
        switch outcome {
        case .accepted, .delayedRepair:
            return 1
        case .undo, .backspace, .retype:
            return -1
        case .shown, .ignored:
            return nil
        }
    }

    private static func evidenceCount(
        for candidateKey: UInt64,
        in entries: [CandidateEvidence]
    ) -> Int {
        guard let entry = entries.first(where: { $0.candidateKey == candidateKey }) else {
            return 0
        }
        return entry.positiveCount + entry.negativeCount
    }

    private static func netCredit(
        for candidateKey: UInt64,
        in entries: [CandidateEvidence]
    ) -> Int {
        guard let entry = entries.first(where: { $0.candidateKey == candidateKey }) else {
            return 0
        }
        return entry.positiveCount - entry.negativeCount
    }

    private static func adjustment(
        for candidateKey: UInt64,
        in entries: [CandidateEvidence]
    ) -> Double {
        let count = evidenceCount(for: candidateKey, in: entries)
        guard count >= 2 else { return 0 }
        let net = netCredit(for: candidateKey, in: entries)
        if net > 0 {
            return min(0.24, Double(net) * 0.06)
        }
        if net < 0 {
            return max(-0.28, Double(net) * 0.08)
        }
        return 0
    }

    private static func styleContribution(
        for episode: HWKAutobotTypingEpisode,
        candidate: HWKAutobotEpisodeCandidate,
        outcomeCredit: Int
    ) -> StyleContribution? {
        guard episode.language == .english,
              let transition = candidate.styleTransition,
              transition.isValid(
                sourceFingerprint: candidate.sourceFingerprint,
                replacementFingerprint: candidate.replacementFingerprint
              ) else {
            return nil
        }
        return StyleContribution(
            episodeID: episode.id,
            dimension: transition.dimension,
            boundaryRole: episode.learningContext?.boundaryRole,
            credit: transition.direction.signedPreference * outcomeCredit
        )
    }

    private static func styleKey(
        dimension: HWKAutobotEnglishStyleDimension,
        boundaryRole: HWKAutobotBoundaryRole?
    ) -> UInt64 {
        guard let boundaryRole else { return UInt64(dimension.rawValue) }
        return HWKAutobotEpisodeFingerprint.englishStyleContext(
            dimension: dimension,
            boundaryRole: boundaryRole
        )
    }

    private static func styleAdjustment(
        for transition: HWKAutobotEnglishStyleTransition,
        key: UInt64,
        in entries: [CandidateEvidence]
    ) -> Double {
        let count = evidenceCount(for: key, in: entries)
        let net = netCredit(for: key, in: entries)
        guard count >= 4, abs(net) >= 2 else { return 0 }
        let learnedPreference = net > 0 ? 1 : -1
        return transition.direction.signedPreference == learnedPreference ? 0.10 : -0.10
    }

    private static func entriesAreValid(_ entries: [CandidateEvidence]) -> Bool {
        entries.allSatisfy {
            $0.positiveCount >= 0 && $0.negativeCount >= 0 &&
            $0.positiveCount + $0.negativeCount > 0 &&
            $0.positiveCount <= 1_000_000 && $0.negativeCount <= 1_000_000
        }
    }

    private static func matches(
        _ entry: CandidateEvidence,
        receipts: [Contribution]
    ) -> Bool {
        entry.positiveCount == receipts.filter { $0.credit > 0 }.count &&
        entry.negativeCount == receipts.filter { $0.credit < 0 }.count &&
        entry.lastEpisodeID == receipts.map(\.episodeID).max()
    }

    private mutating func enforceCapacities() {
        while contributions.count > contributionCapacity,
              let oldestIndex = contributions.indices.min(by: {
                  contributions[$0].episodeID < contributions[$1].episodeID
              }) {
            contributions.remove(at: oldestIndex)
        }

        while Set(contributions.map(\.candidateKey)).count > capacity {
            let keys = Set(contributions.map(\.candidateKey))
            guard let oldestKey = keys.min(by: {
                let leftEpisodeID = latestEpisodeID(forCandidateKey: $0)
                let rightEpisodeID = latestEpisodeID(forCandidateKey: $1)
                return leftEpisodeID == rightEpisodeID ? $0 < $1 : leftEpisodeID < rightEpisodeID
            }) else { break }
            contributions.removeAll { $0.candidateKey == oldestKey }
        }

        while Set(contributions.compactMap(\.contextualKey)).count > contextualCapacity {
            let keys = Set(contributions.compactMap(\.contextualKey))
            guard let oldestKey = keys.min(by: {
                let leftEpisodeID = latestEpisodeID(forContextualKey: $0)
                let rightEpisodeID = latestEpisodeID(forContextualKey: $1)
                return leftEpisodeID == rightEpisodeID ? $0 < $1 : leftEpisodeID < rightEpisodeID
            }) else { break }
            for index in contributions.indices where contributions[index].contextualKey == oldestKey {
                contributions[index].contextualKey = nil
            }
        }

        while styleContributions.count > contributionCapacity,
              let oldestIndex = styleContributions.indices.min(by: {
                  styleContributions[$0].episodeID < styleContributions[$1].episodeID
              }) {
            styleContributions.remove(at: oldestIndex)
        }
        while sourceContributions.count > contributionCapacity,
              let oldestIndex = sourceContributions.indices.min(by: {
                  sourceContributions[$0].episodeID < sourceContributions[$1].episodeID
              }) {
            sourceContributions.remove(at: oldestIndex)
        }
    }

    private func latestEpisodeID(forCandidateKey key: UInt64) -> UInt64 {
        contributions.filter { $0.candidateKey == key }.map(\.episodeID).max() ?? 0
    }

    private func latestEpisodeID(forContextualKey key: UInt64) -> UInt64 {
        contributions.filter { $0.contextualKey == key }.map(\.episodeID).max() ?? 0
    }

    private mutating func rebuildEvidence() {
        evidence = Self.aggregate(
            contributions: contributions,
            key: { $0.candidateKey }
        )
        contextualEvidence = Self.aggregate(
            contributions: contributions,
            key: { $0.contextualKey }
        )
        styleEvidence = Self.aggregateStyle(
            contributions: styleContributions,
            contextual: false
        )
        contextualStyleEvidence = Self.aggregateStyle(
            contributions: styleContributions,
            contextual: true
        )
    }

    private static func aggregate(
        contributions: [Contribution],
        key: (Contribution) -> UInt64?
    ) -> [CandidateEvidence] {
        var result: [UInt64: CandidateEvidence] = [:]
        for contribution in contributions {
            guard let candidateKey = key(contribution) else { continue }
            var entry = result[candidateKey] ?? CandidateEvidence(
                candidateKey: candidateKey,
                positiveCount: 0,
                negativeCount: 0,
                lastEpisodeID: contribution.episodeID
            )
            if contribution.credit > 0 {
                entry.positiveCount += 1
            } else {
                entry.negativeCount += 1
            }
            entry.lastEpisodeID = max(entry.lastEpisodeID, contribution.episodeID)
            result[candidateKey] = entry
        }
        return result.values.sorted {
            if $0.lastEpisodeID != $1.lastEpisodeID {
                return $0.lastEpisodeID < $1.lastEpisodeID
            }
            return $0.candidateKey < $1.candidateKey
        }
    }

    private static func aggregateStyle(
        contributions: [StyleContribution],
        contextual: Bool
    ) -> [CandidateEvidence] {
        var result: [UInt64: CandidateEvidence] = [:]
        for contribution in contributions {
            if contextual && contribution.boundaryRole == nil { continue }
            let candidateKey = styleKey(
                dimension: contribution.dimension,
                boundaryRole: contextual ? contribution.boundaryRole : nil
            )
            var entry = result[candidateKey] ?? CandidateEvidence(
                candidateKey: candidateKey,
                positiveCount: 0,
                negativeCount: 0,
                lastEpisodeID: contribution.episodeID
            )
            if contribution.credit > 0 {
                entry.positiveCount += 1
            } else {
                entry.negativeCount += 1
            }
            entry.lastEpisodeID = max(entry.lastEpisodeID, contribution.episodeID)
            result[candidateKey] = entry
        }
        return result.values.sorted {
            if $0.lastEpisodeID != $1.lastEpisodeID {
                return $0.lastEpisodeID < $1.lastEpisodeID
            }
            return $0.candidateKey < $1.candidateKey
        }
    }
}

struct HWKAutobotEpisodeCreditStore {
    static let storageKey = "keyboard.autobot.episodeCredit.v1"
    static let maximumEncodedBytes = 64 * 1_024

    private struct Envelope: Codable {
        let schemaVersion: Int
        let model: HWKAutobotEpisodeCreditModel
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1 else {
            return false
        }
        return envelope.model.isValid
    }

    func load() -> HWKAutobotEpisodeCreditModel {
        guard let data = defaults.data(forKey: Self.storageKey) else {
            return HWKAutobotEpisodeCreditModel()
        }
        guard Self.isValidPersistedData(data),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.schemaVersion == 1,
              envelope.model.isValid else {
            clear()
            return HWKAutobotEpisodeCreditModel()
        }
        return envelope.model
    }

    @discardableResult
    func reconcile(
        _ snapshot: HWKAutobotTypingEpisodeSnapshot
    ) -> HWKAutobotEpisodeCreditModel {
        var model = load()
        guard model.reconcile(snapshot) else { return model }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(Envelope(schemaVersion: 1, model: model)),
              data.count <= Self.maximumEncodedBytes else {
            return load()
        }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.legacyEpisodeCredit]
        ) {
            defaults.set(data, forKey: Self.storageKey)
            return model
        }
        return result.value ?? load()
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.legacyEpisodeCredit]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }
}

enum HWKAutobotBrainDecision: String, Codable, Equatable {
    case hold
    case promote
    case reject
    case rollback
}

struct HWKAutobotBrainDeclarations: Codable, Equatable {
    let storesRawText: Bool
    let fingerprintSchemeVersion: Int
    let learningContextSchemeVersion: Int
    let maximumContextEvidence: Int
    let maximumSlotBytes: Int
    let minimumTrainingSamples: Int
    let holdoutSamples: Int
    let outcomeMaturityMilliseconds: Int64

    static let standard = HWKAutobotBrainDeclarations(
        storesRawText: false,
        fingerprintSchemeVersion: HWKAutobotEpisodeFingerprint.schemeVersion,
        learningContextSchemeVersion: HWKAutobotLearningContext.schemeVersion,
        maximumContextEvidence: 256,
        maximumSlotBytes: 128 * 1_024,
        minimumTrainingSamples: 24,
        holdoutSamples: 12,
        outcomeMaturityMilliseconds: 60_000
    )
}

struct HWKAutobotBrainReplayMetrics: Codable, Equatable {
    let trainingSampleCount: Int
    let holdoutSampleCount: Int
    let positiveOutcomeCount: Int
    let negativeOutcomeCount: Int
    let championUtilityBasisPoints: Int
    let challengerUtilityBasisPoints: Int
    let championHarmCount: Int
    let challengerHarmCount: Int
    let championWinCount: Int
    let challengerWinCount: Int

    static let empty = HWKAutobotBrainReplayMetrics(
        trainingSampleCount: 0,
        holdoutSampleCount: 0,
        positiveOutcomeCount: 0,
        negativeOutcomeCount: 0,
        championUtilityBasisPoints: 0,
        challengerUtilityBasisPoints: 0,
        championHarmCount: 0,
        challengerHarmCount: 0,
        championWinCount: 0,
        challengerWinCount: 0
    )

    var isValid: Bool {
        guard (0...48).contains(trainingSampleCount),
              (0...HWKAutobotBrainDeclarations.standard.holdoutSamples).contains(holdoutSampleCount),
              positiveOutcomeCount >= 0,
              negativeOutcomeCount >= 0,
              positiveOutcomeCount + negativeOutcomeCount == holdoutSampleCount,
              (-10_000...10_000).contains(championUtilityBasisPoints),
              (-10_000...10_000).contains(challengerUtilityBasisPoints),
              (0...holdoutSampleCount).contains(championHarmCount),
              (0...holdoutSampleCount).contains(challengerHarmCount),
              (0...holdoutSampleCount).contains(championWinCount),
              (0...holdoutSampleCount).contains(challengerWinCount),
              championWinCount + challengerWinCount <= holdoutSampleCount else {
            return false
        }
        return true
    }
}

struct HWKAutobotBrainReplayEvaluation: Equatable {
    let decision: HWKAutobotBrainDecision
    let metrics: HWKAutobotBrainReplayMetrics
}

enum HWKAutobotBrainReplayEvaluator {
    private static let minimumUtilityGainBasisPoints = 300
    private static let minimumNetWins = 3
    private static let epsilon = 0.000_1

    static func evaluate(
        champion: HWKAutobotEpisodeCreditModel,
        challenger: HWKAutobotEpisodeCreditModel,
        trainingSampleCount: Int,
        holdout: HWKAutobotTypingEpisodeSnapshot
    ) -> HWKAutobotBrainReplayEvaluation {
        var championUtility = 0.0
        var challengerUtility = 0.0
        var championHarmCount = 0
        var challengerHarmCount = 0
        var championWinCount = 0
        var challengerWinCount = 0
        var positiveOutcomeCount = 0
        var negativeOutcomeCount = 0
        var evaluatedCount = 0

        for episode in holdout.episodes {
            guard let resolvedCandidateID = episode.resolvedCandidateID,
                  episode.candidates.contains(where: { $0.id == resolvedCandidateID }),
                  let credit = credit(for: episode.finalOutcome),
                  let championProjection = projectedCandidateIDs(
                      model: champion,
                      episode: episode,
                      validatesRecordedChampion: true
                  ),
                  let challengerProjection = projectedCandidateIDs(
                      model: challenger,
                      episode: episode,
                      validatesRecordedChampion: false
                  ) else {
                continue
            }
            let championSignedUtility = signedLaneUtility(
                candidateID: resolvedCandidateID,
                projection: championProjection,
                credit: credit
            )
            let challengerSignedUtility = signedLaneUtility(
                candidateID: resolvedCandidateID,
                projection: challengerProjection,
                credit: credit
            )
            championUtility += championSignedUtility
            challengerUtility += challengerSignedUtility
            championHarmCount += championSignedUtility < -epsilon ? 1 : 0
            challengerHarmCount += challengerSignedUtility < -epsilon ? 1 : 0
            if challengerSignedUtility - championSignedUtility > epsilon {
                challengerWinCount += 1
            } else if championSignedUtility - challengerSignedUtility > epsilon {
                championWinCount += 1
            }
            positiveOutcomeCount += credit > 0 ? 1 : 0
            negativeOutcomeCount += credit < 0 ? 1 : 0
            evaluatedCount += 1
        }

        let championUtilityBasisPoints = basisPoints(
            total: championUtility,
            count: evaluatedCount
        )
        let challengerUtilityBasisPoints = basisPoints(
            total: challengerUtility,
            count: evaluatedCount
        )
        let metrics = HWKAutobotBrainReplayMetrics(
            trainingSampleCount: min(max(0, trainingSampleCount), 48),
            holdoutSampleCount: evaluatedCount,
            positiveOutcomeCount: positiveOutcomeCount,
            negativeOutcomeCount: negativeOutcomeCount,
            championUtilityBasisPoints: championUtilityBasisPoints,
            challengerUtilityBasisPoints: challengerUtilityBasisPoints,
            championHarmCount: championHarmCount,
            challengerHarmCount: challengerHarmCount,
            championWinCount: championWinCount,
            challengerWinCount: challengerWinCount
        )

        let declarations = HWKAutobotBrainDeclarations.standard
        guard trainingSampleCount >= declarations.minimumTrainingSamples,
              evaluatedCount >= declarations.holdoutSamples else {
            return HWKAutobotBrainReplayEvaluation(decision: .hold, metrics: metrics)
        }
        if challengerHarmCount > championHarmCount ||
            challengerUtilityBasisPoints <= championUtilityBasisPoints - minimumUtilityGainBasisPoints ||
            championWinCount - challengerWinCount >= minimumNetWins {
            return HWKAutobotBrainReplayEvaluation(decision: .reject, metrics: metrics)
        }
        if challengerUtilityBasisPoints - championUtilityBasisPoints >= minimumUtilityGainBasisPoints,
           challengerWinCount - championWinCount >= minimumNetWins,
           challengerHarmCount <= championHarmCount {
            return HWKAutobotBrainReplayEvaluation(decision: .promote, metrics: metrics)
        }
        return HWKAutobotBrainReplayEvaluation(decision: .hold, metrics: metrics)
    }

    private static func credit(for outcome: HWKAutobotEpisodeOutcome) -> Int? {
        switch outcome {
        case .accepted, .delayedRepair:
            return 1
        case .undo, .backspace, .retype:
            return -1
        case .shown, .ignored:
            return nil
        }
    }

    private static func projectedCandidateIDs(
        model: HWKAutobotEpisodeCreditModel,
        episode: HWKAutobotTypingEpisode,
        validatesRecordedChampion: Bool
    ) -> [UInt64?]? {
        guard let surface = episode.suggestionSurface,
              let trace = surface.projectionTrace,
              trace.supportsDirectModelAdjustments,
              surface.isValid else {
            return nil
        }
        var replacements = [UInt64: Int32]()
        for projectionCandidate in trace.candidates {
            let adjustmentMicropoints: Int32
            if let modelBinding = projectionCandidate.modelBinding {
                guard let micropoints = HWKAutobotSuggestionScoreEvidence.micropoints(
                    modelAdjustment(
                        model: model,
                        binding: modelBinding,
                        language: episode.language
                    )
                ) else {
                    return nil
                }
                adjustmentMicropoints = micropoints
            } else {
                adjustmentMicropoints = 0
            }
            if validatesRecordedChampion,
               (projectionCandidate.modelChampionDeltaMicropoints != adjustmentMicropoints ||
                projectionCandidate.surfaceChampionDeltaMicropoints != adjustmentMicropoints) {
                return nil
            }
            replacements[projectionCandidate.candidateID] = adjustmentMicropoints
        }
        return surface.counterfactualCandidateIDs(
            using: episode.candidates,
            replacingChampionDeltasMicropoints: replacements
        )
    }

    private static func modelAdjustment(
        model: HWKAutobotEpisodeCreditModel,
        binding: HWKAutobotSuggestionModelBinding,
        language: HWKAutobotEpisodeLanguage
    ) -> Double {
        let candidateKey = HWKAutobotEpisodeFingerprint.candidatePair(
            sourceFingerprint: binding.sourceFingerprint,
            replacementFingerprint: binding.replacementFingerprint
        )
        let pairAdjustment = model.adjustment(
            for: candidateKey,
            language: language,
            learningContextFingerprint: binding.learningContextFingerprint
        )
        let styleAdjustment = language == .english ? binding.styleTransition.map {
            model.styleAdjustment(for: $0, boundaryRole: binding.boundaryRole)
        } ?? 0 : 0
        let sourceAdjustment = binding.evidenceSource.map {
            model.sourceAdjustment(for: $0)
        } ?? 0
        return pairAdjustment + styleAdjustment + sourceAdjustment
    }

    private static func signedLaneUtility(
        candidateID: UInt64,
        projection: [UInt64?],
        credit: Int
    ) -> Double {
        guard !projection.isEmpty,
              let laneIndex = projection.firstIndex(where: { $0 == candidateID }) else {
            return 0
        }
        let visibility = Double(projection.count - laneIndex) / Double(projection.count)
        return Double(credit) * visibility
    }

    private static func basisPoints(total: Double, count: Int) -> Int {
        guard count > 0, total.isFinite else { return 0 }
        return Int(((total / Double(count)) * 10_000).rounded())
    }
}

struct HWKAutobotBrainSnapshot: Codable, Equatable {
    static let schemaVersion = 2
    static let evaluatorVersion = 4

    let schemaVersion: Int
    let evaluatorVersion: Int
    let revision: UInt64
    let parentRevision: UInt64?
    let createdAtMilliseconds: Int64
    let sourceUpperBoundEpisodeID: UInt64
    let sourceFingerprint: UInt64
    let declarations: HWKAutobotBrainDeclarations
    let creditModel: HWKAutobotEpisodeCreditModel
    let metrics: HWKAutobotBrainReplayMetrics

    static let initial = HWKAutobotBrainSnapshot(
        schemaVersion: schemaVersion,
        evaluatorVersion: evaluatorVersion,
        revision: 1,
        parentRevision: nil,
        createdAtMilliseconds: 0,
        sourceUpperBoundEpisodeID: 0,
        sourceFingerprint: 0,
        declarations: .standard,
        creditModel: HWKAutobotEpisodeCreditModel(),
        metrics: .empty
    )

    var isValid: Bool {
        guard schemaVersion == Self.schemaVersion,
              evaluatorVersion == Self.evaluatorVersion,
              revision > 0,
              parentRevision.map({ $0 < revision }) ?? true,
              createdAtMilliseconds >= 0,
              declarations == .standard,
              creditModel.isValid,
              metrics.isValid else {
            return false
        }
        if sourceUpperBoundEpisodeID == 0 || sourceFingerprint == 0 {
            return self == Self.initial
        }
        return true
    }
}

struct HWKAutobotBrainState: Codable, Equatable {
    let generation: UInt64
    let nextRevision: UInt64
    let champion: HWKAutobotBrainSnapshot
    let challenger: HWKAutobotBrainSnapshot?
    let rollback: HWKAutobotBrainSnapshot?
    let lastDecision: HWKAutobotBrainDecision

    static let initial = HWKAutobotBrainState(
        generation: 0,
        nextRevision: 2,
        champion: .initial,
        challenger: nil,
        rollback: nil,
        lastDecision: .hold
    )

    var isValid: Bool {
        let snapshots = [champion, challenger, rollback].compactMap { $0 }
        guard champion.isValid,
              challenger?.isValid ?? true,
              rollback?.isValid ?? true,
              challenger.map({ $0.parentRevision == champion.revision }) ?? true,
              rollback.map({ $0.revision != champion.revision }) ?? true,
              Set(snapshots.map(\.revision)).count == snapshots.count,
              nextRevision > (snapshots.map(\.revision).max() ?? 0) else {
            return false
        }
        return true
    }
}

struct HWKAutobotBrainUpdate: Equatable {
    let decision: HWKAutobotBrainDecision
    let state: HWKAutobotBrainState
}

struct HWKAutobotBrainSnapshotStore {
    static let storageKey = "keyboard.autobot.brainSnapshot.current.v1"
    static let recoveryKey = "keyboard.autobot.brainSnapshot.recovery.v1"
    static let maximumEncodedBytes = 128 * 1_024

    private static let resetEpochKey = "keyboard.autobot.brainSnapshot.resetEpoch.v1"
    private static let envelopeVersion = 1
    private static let storeLock = NSLock()

    private struct ReplayPlan {
        let training: HWKAutobotTypingEpisodeSnapshot
        let holdout: HWKAutobotTypingEpisodeSnapshot
        let sourceUpperBoundEpisodeID: UInt64
        let sourceFingerprint: UInt64
    }

    private struct Payload: Codable {
        let envelopeVersion: Int
        let resetEpoch: String
        let state: HWKAutobotBrainState
    }

    private struct Envelope: Codable {
        let envelopeVersion: Int
        let resetEpoch: String
        let state: HWKAutobotBrainState
        let checksum: String
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    static func isValidPersistedEnvelopeData(
        _ data: Data,
        resetEpoch: String
    ) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.envelopeVersion == Self.envelopeVersion,
              envelope.resetEpoch == resetEpoch,
              envelope.state.isValid,
              envelope.checksum == checksum(
                  state: envelope.state,
                  resetEpoch: envelope.resetEpoch
              ) else {
            return false
        }
        return true
    }

    func load() -> HWKAutobotBrainState {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
        return loadUnlocked()
    }

    private func loadUnlocked() -> HWKAutobotBrainState {
        let epoch = currentResetEpoch()
        let current = decodedSlot(forKey: Self.storageKey, resetEpoch: epoch)
        let recovery = decodedSlot(forKey: Self.recoveryKey, resetEpoch: epoch)
        let candidates = [current.map { ($0, true) }, recovery.map { ($0, false) }]
            .compactMap { $0 }
        guard let selected = candidates.max(by: { lhs, rhs in
            if lhs.0.state.generation != rhs.0.state.generation {
                return lhs.0.state.generation < rhs.0.state.generation
            }
            return !lhs.1 && rhs.1
        }) else {
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.recoveryKey)
            return .initial
        }
        if current?.state != selected.0.state {
            defaults.set(selected.0.data, forKey: Self.storageKey)
        }
        return selected.0.state
    }

    func loadChampion() -> HWKAutobotBrainSnapshot {
        load().champion
    }

    @discardableResult
    func observe(
        _ replay: HWKAutobotTypingEpisodeSnapshot,
        timestampMilliseconds: Int64
    ) -> HWKAutobotBrainUpdate {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }

        for _ in 0..<2 {
            let resetEpoch = currentResetEpoch()
            let base = loadUnlocked()
            let plan = replayPlan(
                replay,
                timestampMilliseconds: timestampMilliseconds
            )

            if let rollback = base.rollback {
                let regression = HWKAutobotBrainReplayEvaluator.evaluate(
                    champion: base.champion.creditModel,
                    challenger: rollback.creditModel,
                    trainingSampleCount: plan.training.episodes.count,
                    holdout: plan.holdout
                )
                if regression.decision == .promote {
                    let rolledBack = HWKAutobotBrainState(
                        generation: base.generation &+ 1,
                        nextRevision: base.nextRevision,
                        champion: rollback,
                        challenger: nil,
                        rollback: base.champion,
                        lastDecision: .rollback
                    )
                    if publish(rolledBack, replacing: base, resetEpoch: resetEpoch) {
                        retireLegacyDirectCredit()
                        return HWKAutobotBrainUpdate(decision: .rollback, state: rolledBack)
                    }
                    continue
                }
            }

            var challengerModel: HWKAutobotEpisodeCreditModel
            if let challenger = base.challenger,
               challenger.parentRevision == base.champion.revision {
                challengerModel = challenger.creditModel
            } else {
                challengerModel = base.champion.creditModel
            }
            let modelChanged = challengerModel.reconcile(plan.training)
            let evaluation = HWKAutobotBrainReplayEvaluator.evaluate(
                champion: base.champion.creditModel,
                challenger: challengerModel,
                trainingSampleCount: plan.training.episodes.count,
                holdout: plan.holdout
            )
            let candidate = HWKAutobotBrainSnapshot(
                schemaVersion: HWKAutobotBrainSnapshot.schemaVersion,
                evaluatorVersion: HWKAutobotBrainSnapshot.evaluatorVersion,
                revision: base.nextRevision,
                parentRevision: base.champion.revision,
                createdAtMilliseconds: timestampMilliseconds,
                sourceUpperBoundEpisodeID: plan.sourceUpperBoundEpisodeID,
                sourceFingerprint: plan.sourceFingerprint,
                declarations: .standard,
                creditModel: challengerModel,
                metrics: evaluation.metrics
            )

            if evaluation.decision == .hold,
               !modelChanged,
               let existing = base.challenger,
               existing.creditModel == candidate.creditModel,
               existing.metrics == candidate.metrics,
               existing.sourceFingerprint == candidate.sourceFingerprint {
                retireLegacyDirectCredit()
                return HWKAutobotBrainUpdate(decision: .hold, state: base)
            }

            let nextState: HWKAutobotBrainState
            switch evaluation.decision {
            case .promote:
                nextState = HWKAutobotBrainState(
                    generation: base.generation &+ 1,
                    nextRevision: base.nextRevision &+ 1,
                    champion: candidate,
                    challenger: nil,
                    rollback: base.champion,
                    lastDecision: .promote
                )
            case .reject:
                nextState = HWKAutobotBrainState(
                    generation: base.generation &+ 1,
                    nextRevision: base.nextRevision &+ 1,
                    champion: base.champion,
                    challenger: nil,
                    rollback: base.rollback,
                    lastDecision: .reject
                )
            case .hold:
                nextState = HWKAutobotBrainState(
                    generation: base.generation &+ 1,
                    nextRevision: base.nextRevision &+ 1,
                    champion: base.champion,
                    challenger: candidate,
                    rollback: base.rollback,
                    lastDecision: .hold
                )
            case .rollback:
                return HWKAutobotBrainUpdate(decision: .hold, state: base)
            }

            guard nextState.isValid else {
                return HWKAutobotBrainUpdate(decision: .hold, state: base)
            }
            if publish(nextState, replacing: base, resetEpoch: resetEpoch) {
                retireLegacyDirectCredit()
                return HWKAutobotBrainUpdate(decision: evaluation.decision, state: nextState)
            }
        }
        return HWKAutobotBrainUpdate(decision: .hold, state: loadUnlocked())
    }

    @discardableResult
    func rollbackToPreviousChampion() -> Bool {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
        let resetEpoch = currentResetEpoch()
        let base = loadUnlocked()
        guard let rollback = base.rollback else { return false }
        let nextState = HWKAutobotBrainState(
            generation: base.generation &+ 1,
            nextRevision: base.nextRevision,
            champion: rollback,
            challenger: nil,
            rollback: base.champion,
            lastDecision: .rollback
        )
        return publish(nextState, replacing: base, resetEpoch: resetEpoch)
    }

    func clear() {
        Self.storeLock.lock()
        defer { Self.storeLock.unlock() }
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.brainSnapshot]
        ) {
            defaults.set(UUID().uuidString.lowercased(), forKey: Self.resetEpochKey)
            defaults.removeObject(forKey: Self.storageKey)
            defaults.removeObject(forKey: Self.recoveryKey)
        }
    }

    private func replayPlan(
        _ replay: HWKAutobotTypingEpisodeSnapshot,
        timestampMilliseconds: Int64
    ) -> ReplayPlan {
        let maturity = HWKAutobotBrainDeclarations.standard.outcomeMaturityMilliseconds
        let mature = replay.episodes
            .filter { episode in
                guard episode.updatedAtMilliseconds <= timestampMilliseconds - maturity,
                      episode.resolvedCandidateID != nil else {
                    return false
                }
                switch episode.finalOutcome {
                case .accepted, .delayedRepair, .undo, .backspace, .retype:
                    return true
                case .shown, .ignored:
                    return false
                }
            }
            .sorted { lhs, rhs in
                if lhs.updatedAtMilliseconds != rhs.updatedAtMilliseconds {
                    return lhs.updatedAtMilliseconds < rhs.updatedAtMilliseconds
                }
                return lhs.id < rhs.id
            }
        let holdoutCount = min(
            HWKAutobotBrainDeclarations.standard.holdoutSamples,
            mature.count
        )
        let trainingCount = mature.count - holdoutCount
        let trainingEpisodes = Array(mature.prefix(trainingCount))
        let holdoutEpisodes = Array(mature.suffix(holdoutCount))
        return ReplayPlan(
            training: HWKAutobotTypingEpisodeSnapshot(
                episodes: trainingEpisodes,
                eventCount: trainingEpisodes.count
            ),
            holdout: HWKAutobotTypingEpisodeSnapshot(
                episodes: holdoutEpisodes,
                eventCount: holdoutEpisodes.count
            ),
            sourceUpperBoundEpisodeID: mature.map(\.id).max() ?? 0,
            sourceFingerprint: sourceFingerprint(for: mature)
        )
    }

    private func sourceFingerprint(for episodes: [HWKAutobotTypingEpisode]) -> UInt64 {
        guard !episodes.isEmpty else { return 0 }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(episodes) else { return 0 }
        return SHA256.hash(data: data).prefix(8).reduce(into: UInt64(0)) { value, byte in
            value = (value << 8) | UInt64(byte)
        }
    }

    private func publish(
        _ state: HWKAutobotBrainState,
        replacing base: HWKAutobotBrainState,
        resetEpoch: String
    ) -> Bool {
        guard currentResetEpoch() == resetEpoch,
              loadUnlocked().generation == base.generation,
              let recoveryData = encodedEnvelope(state: base, resetEpoch: resetEpoch),
              let currentData = encodedEnvelope(state: state, resetEpoch: resetEpoch),
              recoveryData.count <= Self.maximumEncodedBytes,
              currentData.count <= Self.maximumEncodedBytes else {
            return false
        }
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.brainSnapshot]
        ) {
            defaults.set(recoveryData, forKey: Self.recoveryKey)
            guard currentResetEpoch() == resetEpoch else { return false }
            defaults.set(currentData, forKey: Self.storageKey)
            return true
        }
        return result.value ?? false
    }

    private func decodedSlot(
        forKey key: String,
        resetEpoch: String
    ) -> (state: HWKAutobotBrainState, data: Data)? {
        guard let data = defaults.data(forKey: key),
              !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.envelopeVersion == Self.envelopeVersion,
              envelope.resetEpoch == resetEpoch,
              envelope.state.isValid,
              envelope.checksum == Self.checksum(
                  state: envelope.state,
                  resetEpoch: envelope.resetEpoch
              ) else {
            return nil
        }
        return (envelope.state, data)
    }

    private func encodedEnvelope(
        state: HWKAutobotBrainState,
        resetEpoch: String
    ) -> Data? {
        guard state.isValid else { return nil }
        let envelope = Envelope(
            envelopeVersion: Self.envelopeVersion,
            resetEpoch: resetEpoch,
            state: state,
            checksum: Self.checksum(state: state, resetEpoch: resetEpoch)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(envelope)
    }

    private static func checksum(
        state: HWKAutobotBrainState,
        resetEpoch: String
    ) -> String {
        let payload = Payload(
            envelopeVersion: Self.envelopeVersion,
            resetEpoch: resetEpoch,
            state: state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func currentResetEpoch() -> String {
        defaults.string(forKey: Self.resetEpochKey) ?? "initial"
    }

    private func retireLegacyDirectCredit() {
        HWKAutobotEpisodeCreditStore(defaults: defaults).clear()
    }
}

private struct HWKGizmoImprovementFocusKey: Hashable {
    var lane: HWKGizmoImprovementLane
    var feature: HWKGizmoImprovementFeature
    var bucket: HWKGizmoImprovementBucket
}

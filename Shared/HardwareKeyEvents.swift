import Foundation

enum KeySessionRelay {
    static let isEnabled: Bool = {
#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        true
#else
        false
#endif
    }()
}

struct HWKKnownKeySnapshotEdge<Key: Hashable> {
    let key: Key
    let isPressed: Bool
}

struct HWKKnownKeySnapshotReconciliation<Key: Hashable> {
    let pressedKeys: Set<Key>
    let edges: [HWKKnownKeySnapshotEdge<Key>]
}

enum HWKKnownKeySnapshotReconciler {
    static func reconcile<Key: Hashable>(
        trackedKeys: [Key],
        previouslyPressed: Set<Key>,
        snapshotPressed: Set<Key>,
        isAnyKeyPressed: Bool,
        allowsMissingKeyReleases: Bool = false
    ) -> HWKKnownKeySnapshotReconciliation<Key> {
        var seen = Set<Key>()
        let orderedTrackedKeys = trackedKeys.filter { seen.insert($0).inserted }
        let tracked = Set(orderedTrackedKeys)
        let previousPressedKeys = previouslyPressed.intersection(tracked)
        let observedPressedKeys = isAnyKeyPressed ? snapshotPressed.intersection(tracked) : []
        let pressedKeys = allowsMissingKeyReleases
            ? observedPressedKeys
            : previousPressedKeys.union(observedPressedKeys)
        let edges = orderedTrackedKeys.compactMap { key -> HWKKnownKeySnapshotEdge<Key>? in
            let wasPressed = previousPressedKeys.contains(key)
            let isPressed = pressedKeys.contains(key)
            guard wasPressed != isPressed else { return nil }
            return HWKKnownKeySnapshotEdge(key: key, isPressed: isPressed)
        }
        return HWKKnownKeySnapshotReconciliation(pressedKeys: pressedKeys, edges: edges)
    }
}

enum HWKGameControllerSnapshotWake: String, Codable {
    case attach = "a"
    case poll = "p"
    case valueChanged = "v"
    case keyChanged = "k"
}

struct HWKGameControllerSnapshotProbeState: Codable, Equatable {
    var captureCount = 0
    var attachCaptureCount = 0
    var pollCaptureCount = 0
    var valueChangedCaptureCount = 0
    var keyChangedCaptureCount = 0
    var anyKeyPressedCaptureCount = 0
    var knownPressedCaptureCount = 0
    var knownEdgeCount = 0
    var timestampAdvanceCount = 0
    var timestampRegressionCount = 0
    var lastEventTimestamp: TimeInterval?
    var liveAnyKeyPressedCaptureCount = 0
    var liveKnownPressedCaptureCount = 0
    var liveTimestampAdvanceCount = 0
    var liveTimestampRegressionCount = 0
    var lastLiveEventTimestamp: TimeInterval?

    mutating func record(
        wake: HWKGameControllerSnapshotWake,
        sourceTimestamp: TimeInterval,
        isAnyKeyPressed: Bool,
        knownPressedCount: Int,
        liveSourceTimestamp: TimeInterval,
        liveIsAnyKeyPressed: Bool,
        liveKnownPressedCount: Int,
        edgeCount: Int
    ) {
        captureCount += 1
        switch wake {
        case .attach:
            attachCaptureCount += 1
        case .poll:
            pollCaptureCount += 1
        case .valueChanged:
            valueChangedCaptureCount += 1
        case .keyChanged:
            keyChangedCaptureCount += 1
        }
        if isAnyKeyPressed {
            anyKeyPressedCaptureCount += 1
        }
        if knownPressedCount > 0 {
            knownPressedCaptureCount += 1
        }
        if liveIsAnyKeyPressed {
            liveAnyKeyPressedCaptureCount += 1
        }
        if liveKnownPressedCount > 0 {
            liveKnownPressedCaptureCount += 1
        }
        knownEdgeCount += max(0, edgeCount)

        if liveSourceTimestamp > 0 {
            if let lastLiveEventTimestamp {
                if liveSourceTimestamp > lastLiveEventTimestamp {
                    liveTimestampAdvanceCount += 1
                    self.lastLiveEventTimestamp = liveSourceTimestamp
                } else if liveSourceTimestamp < lastLiveEventTimestamp {
                    liveTimestampRegressionCount += 1
                }
            } else {
                lastLiveEventTimestamp = liveSourceTimestamp
            }
        }

        guard sourceTimestamp > 0 else { return }
        if let lastEventTimestamp {
            if sourceTimestamp > lastEventTimestamp {
                timestampAdvanceCount += 1
                self.lastEventTimestamp = sourceTimestamp
            } else if sourceTimestamp < lastEventTimestamp {
                timestampRegressionCount += 1
            }
        } else {
            lastEventTimestamp = sourceTimestamp
        }
    }
}

#if HWC_INTERNAL_BUILD
enum HWKGameControllerSnapshotProbeStore {
    static let storageKey = "keyboard.gameControllerSnapshotProbe"

    private static let queue = DispatchQueue(
        label: "dev.moni11811.hwkbcompanion.game-controller-snapshot-probe"
    )
    private static var cachedState: HWKGameControllerSnapshotProbeState?
    private static var lastPersistedAt: TimeInterval = 0

    static func record(
        wake: HWKGameControllerSnapshotWake,
        sourceTimestamp: TimeInterval,
        isAnyKeyPressed: Bool,
        knownPressedCount: Int,
        liveSourceTimestamp: TimeInterval,
        liveIsAnyKeyPressed: Bool,
        liveKnownPressedCount: Int,
        edgeCount: Int
    ) {
        queue.async {
            var state = cachedState ?? load()
            let previousTimestamp = state.lastEventTimestamp
            let previousLiveTimestamp = state.lastLiveEventTimestamp
            state.record(
                wake: wake,
                sourceTimestamp: sourceTimestamp,
                isAnyKeyPressed: isAnyKeyPressed,
                knownPressedCount: knownPressedCount,
                liveSourceTimestamp: liveSourceTimestamp,
                liveIsAnyKeyPressed: liveIsAnyKeyPressed,
                liveKnownPressedCount: liveKnownPressedCount,
                edgeCount: edgeCount
            )
            cachedState = state

            let now = Date.timeIntervalSinceReferenceDate
            let shouldPersist = wake != .poll
                || edgeCount > 0
                || state.lastEventTimestamp != previousTimestamp
                || state.lastLiveEventTimestamp != previousLiveTimestamp
                || now - lastPersistedAt >= 1
            guard shouldPersist else { return }
            persist(state)
            lastPersistedAt = now
        }
    }

    static func snapshot() -> HWKGameControllerSnapshotProbeState {
        queue.sync {
            let state = cachedState ?? load()
            cachedState = state
            return state
        }
    }

    static func clear() {
        queue.sync {
            cachedState = .init()
            lastPersistedAt = 0
            sharedDefaults.removeObject(forKey: storageKey)
        }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard
    }

    private static func load() -> HWKGameControllerSnapshotProbeState {
        guard let data = sharedDefaults.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(HWKGameControllerSnapshotProbeState.self, from: data) else {
            return .init()
        }
        return state
    }

    private static func persist(_ state: HWKGameControllerSnapshotProbeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        sharedDefaults.set(data, forKey: storageKey)
    }
}
#endif

enum KeyEventSource: String, Codable {
#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
    case pressesBegan = "b"
    case pressesChanged = "h"
    case pressesEnded = "e"
    case keyCommand = "k"
    case inferred = "i"
    case appDebug = "a"

    static let captured = Self.pressesBegan
    static let capturedKeyDown = Self.pressesBegan
    static let capturedKeyChanged = Self.pressesChanged
    static let capturedKeyUp = Self.pressesEnded
    static let capturedKeyCommand = Self.keyCommand
#else
    // Non-capture builds keep compact tokens only so stale payloads can decode safely.
    case captured = "c"
    case inferred = "i"

    static let capturedKeyDown = Self.captured
    static let capturedKeyChanged = Self.captured
    static let capturedKeyUp = Self.captured
    static let capturedKeyCommand = Self.captured
#endif

    var archiveString: String {
#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        switch self {
        case .pressesBegan:
            return "pressesBegan"
        case .pressesChanged:
            return "pressesChanged"
        case .pressesEnded:
            return "pressesEnded"
        case .keyCommand:
            return "keyCommand"
        case .inferred:
            return "inferred"
        case .appDebug:
            return "appDebug"
        }
#else
        switch self {
        case .captured:
            return "captured"
        case .inferred:
            return "inferred"
        }
#endif
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let source = Self(rawValue: value) {
            self = source
            return
        }

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        switch value {
        case "pressesBegan":
            self = .pressesBegan
        case "pressesChanged":
            self = .pressesChanged
        case "pressesEnded":
            self = .pressesEnded
        case "keyCommand":
            self = .keyCommand
        case "captured":
            self = .capturedKeyDown
        case "inferred":
            self = .inferred
        case "appDebug":
            self = .appDebug
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid key source token: \(value)"
            )
        }
#else
        switch value {
        case "captured":
            self = .captured
        case "inferred":
            self = .inferred
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid key source token: \(value)"
            )
        }
#endif
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum KeyPhase: String, Codable {
    case down = "d"
    case up = "u"

    var archiveString: String {
        switch self {
        case .down:
            return "down"
        case .up:
            return "up"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let phase = Self(rawValue: value) {
            self = phase
            return
        }

        switch value {
        case "down":
            self = .down
        case "up":
            self = .up
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid key phase token: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum KeyModifier: String, Codable, CaseIterable {
    case shift = "s"
    case control = "c"
    case option = "o"
    case command = "m"
    case capsLock = "l"
    case numericPad = "n"
    case alphaShift = "a"

    var archiveString: String {
        switch self {
        case .shift:
            return "shift"
        case .control:
            return "control"
        case .option:
            return "option"
        case .command:
            return "command"
        case .capsLock:
            return "capsLock"
        case .numericPad:
            return "numericPad"
        case .alphaShift:
            return "alphaShift"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let modifier = Self(rawValue: value) {
            self = modifier
            return
        }

        switch value {
        case "shift":
            self = .shift
        case "control":
            self = .control
        case "option":
            self = .option
        case "command":
            self = .command
        case "capsLock":
            self = .capsLock
        case "numericPad":
            self = .numericPad
        case "alphaShift":
            self = .alphaShift
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid key modifier token: \(value)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum HWKHardwareEventIdentity {
    static func relaySignature(for event: KeyEvent, shiftIsPhysicallyHeld: Bool = false) -> String {
        [
            event.phase.rawValue,
            keyIdentity(for: event),
            modifierSignature(normalizedCaseModifiers(for: event, shiftIsPhysicallyHeld: shiftIsPhysicallyHeld)),
        ].joined(separator: "|")
    }

    static func repeatSignature(for event: KeyEvent, shiftIsPhysicallyHeld: Bool = false) -> String {
        [
            keyIdentity(for: event),
            modifierSignature(normalizedCaseModifiers(for: event, shiftIsPhysicallyHeld: shiftIsPhysicallyHeld)),
        ].joined(separator: "|")
    }

    static func repeatStopIdentity(for event: KeyEvent) -> String {
        keyIdentity(for: event)
    }

    static func normalizedCaseModifiers(
        _ modifiers: Set<KeyModifier>,
        characters: String?,
        charactersIgnoringModifiers: String?,
        shiftIsPhysicallyHeld: Bool = false
    ) -> Set<KeyModifier> {
        let capsLocked = modifiers.contains(.capsLock) || modifiers.contains(.alphaShift)
        guard capsLocked,
              modifiers.contains(.shift),
              !shiftIsPhysicallyHeld,
              isSyntheticCapsShiftOutput(
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers
              ) else {
            return modifiers
        }

        var normalized = modifiers
        normalized.remove(.shift)
        return normalized
    }

    private static func keyIdentity(for event: KeyEvent) -> String {
        if let keyCode = event.keyCode {
            return "k:\(keyCode)"
        }

        if let charactersIgnoringModifiers = event.charactersIgnoringModifiers,
           !charactersIgnoringModifiers.isEmpty {
            return "g:\(charactersIgnoringModifiers)"
        }

        return "c:\(event.characters ?? "")"
    }

    private static func modifierSignature(_ modifiers: Set<KeyModifier>) -> String {
        var canonical = modifiers
        if canonical.contains(.capsLock) || canonical.contains(.alphaShift) {
            canonical.remove(.capsLock)
            canonical.remove(.alphaShift)
            canonical.insert(.capsLock)
        }
        return canonical.map(\.rawValue).sorted().joined(separator: ",")
    }

    private static func normalizedCaseModifiers(
        for event: KeyEvent,
        shiftIsPhysicallyHeld: Bool = false
    ) -> Set<KeyModifier> {
        normalizedCaseModifiers(
            event.modifiers,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            shiftIsPhysicallyHeld: shiftIsPhysicallyHeld
        )
    }

    private static func isSyntheticCapsShiftOutput(
        characters: String?,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        guard let output = singleASCIILetter(characters),
              let ignoring = singleASCIILetter(charactersIgnoringModifiers) else {
            return false
        }

        return output.lowercase == ignoring.lowercase &&
            output.isUppercase &&
            !ignoring.isUppercase
    }

    private static func singleASCIILetter(_ text: String?) -> (lowercase: UInt8, isUppercase: Bool)? {
        guard let text,
              text.utf8.count == 1,
              let byte = text.utf8.first else {
            return nil
        }

        switch byte {
        case 65...90:
            return (byte + 32, true)
        case 97...122:
            return (byte, false)
        default:
            return nil
        }
    }
}

struct KeyEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let source: KeyEventSource
    let phase: KeyPhase
    let characters: String?
    let charactersIgnoringModifiers: String?
    let keyCode: Int?
    let modifiers: Set<KeyModifier>
    let isRepeat: Bool
    let sequence: UInt64
    let isSynthetic: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: KeyEventSource,
        phase: KeyPhase,
        characters: String? = nil,
        charactersIgnoringModifiers: String? = nil,
        keyCode: Int? = nil,
        modifiers: Set<KeyModifier> = [],
        isRepeat: Bool = false,
        sequence: UInt64 = 0,
        isSynthetic: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.phase = phase
        self.characters = characters
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
        self.sequence = sequence
        self.isSynthetic = isSynthetic
    }

    private var shouldPersistCharacterPayload: Bool {
        false
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case timestamp = "t"
        case source = "s"
        case phase = "p"
        case characters = "c"
        case charactersIgnoringModifiers = "g"
        case keyCode = "k"
        case modifiers = "m"
        case isRepeat = "r"
        case sequence = "n"
        case isSynthetic = "y"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case phase
        case characters
        case charactersIgnoringModifiers
        case keyCode
        case modifiers
        case isRepeat
    }

    init(from decoder: Decoder) throws {
        let compact = try decoder.container(keyedBy: CodingKeys.self)

        if !compact.allKeys.isEmpty {
            id = try compact.decode(UUID.self, forKey: .id)
            timestamp = try compact.decode(Date.self, forKey: .timestamp)
            source = try compact.decode(KeyEventSource.self, forKey: .source)
            phase = try compact.decode(KeyPhase.self, forKey: .phase)
            characters = try compact.decodeIfPresent(String.self, forKey: .characters)
            charactersIgnoringModifiers = try compact.decodeIfPresent(
                String.self,
                forKey: .charactersIgnoringModifiers
            )
            keyCode = try compact.decodeIfPresent(Int.self, forKey: .keyCode)
            modifiers = try compact.decodeIfPresent(Set<KeyModifier>.self, forKey: .modifiers) ?? []
            isRepeat = try compact.decodeIfPresent(Bool.self, forKey: .isRepeat) ?? false
            sequence = try compact.decodeIfPresent(UInt64.self, forKey: .sequence) ?? 0
            isSynthetic = try compact.decodeIfPresent(Bool.self, forKey: .isSynthetic) ?? false
            return
        }

        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try legacy.decode(UUID.self, forKey: .id)
        timestamp = try legacy.decode(Date.self, forKey: .timestamp)
        source = try legacy.decode(KeyEventSource.self, forKey: .source)
        phase = try legacy.decode(KeyPhase.self, forKey: .phase)
        characters = try legacy.decodeIfPresent(String.self, forKey: .characters)
        charactersIgnoringModifiers = try legacy.decodeIfPresent(
            String.self,
            forKey: .charactersIgnoringModifiers
        )
        keyCode = try legacy.decodeIfPresent(Int.self, forKey: .keyCode)
        modifiers = try legacy.decodeIfPresent(Set<KeyModifier>.self, forKey: .modifiers) ?? []
        isRepeat = try legacy.decodeIfPresent(Bool.self, forKey: .isRepeat) ?? false
        sequence = 0
        isSynthetic = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(phase, forKey: .phase)
        if shouldPersistCharacterPayload {
            try container.encodeIfPresent(characters, forKey: .characters)
            try container.encodeIfPresent(charactersIgnoringModifiers, forKey: .charactersIgnoringModifiers)
        }
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        if !modifiers.isEmpty {
            try container.encode(modifiers, forKey: .modifiers)
        }
        if isRepeat {
            try container.encode(true, forKey: .isRepeat)
        }
        if sequence != 0 {
            try container.encode(sequence, forKey: .sequence)
        }
        if isSynthetic {
            try container.encode(true, forKey: .isSynthetic)
        }
    }
}

struct HWKCommittedContextReconstructor {
    private static let deleteBackspaceKeyCode = 42

    private(set) var committedContext: String

    init(committedContext: String = "") {
        self.committedContext = committedContext
    }

    mutating func reset(to context: String) {
        committedContext = context
    }

    mutating func reconcile(freshContext: String) -> [KeyEvent] {
        defer {
            committedContext = freshContext
        }

        guard freshContext != committedContext else { return [] }

        let commonPrefix = committedContext.commonPrefix(with: freshContext)
        if commonPrefix == committedContext {
            return freshContext.dropFirst(committedContext.count).map { grapheme in
                let text = String(grapheme)
                let caseObservation = Self.caseObservation(for: text)
                return KeyEvent(
                    source: .inferred,
                    phase: .down,
                    characters: text,
                    charactersIgnoringModifiers: caseObservation.charactersIgnoringModifiers,
                    modifiers: caseObservation.modifiers,
                    isSynthetic: true
                )
            }
        }

        if commonPrefix == freshContext {
            let deletedCount = committedContext.count - freshContext.count
            guard deletedCount > 0 else { return [] }
            return (0..<deletedCount).map { _ in
                KeyEvent(
                    source: .inferred,
                    phase: .down,
                    characters: "⌫",
                    charactersIgnoringModifiers: "⌫",
                    keyCode: Self.deleteBackspaceKeyCode,
                    isSynthetic: true
                )
            }
        }

        return []
    }

    private static func caseObservation(for text: String) -> (
        charactersIgnoringModifiers: String,
        modifiers: Set<KeyModifier>
    ) {
        guard text.count == 1,
              let scalar = text.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(scalar) else {
            return (text, [])
        }

        let lowercase = text.lowercased()
        guard lowercase != text else {
            return (text, [])
        }

        return (lowercase, [.shift])
    }
}

struct HWKRawInputLivenessArbiter {
    private let rawCallbackWindow: Int
    private var callbacksSinceRawDelivery: Int?

    init(rawCallbackWindow: Int = 3) {
        self.rawCallbackWindow = max(1, rawCallbackWindow)
    }

    mutating func markRawDelivery() {
        callbacksSinceRawDelivery = 0
    }

    mutating func shouldReconstructAfterTextCallback() -> Bool {
        guard let callbacksSinceRawDelivery else {
            return true
        }

        let nextCount = callbacksSinceRawDelivery + 1
        self.callbacksSinceRawDelivery = nextCount
        return nextCount > rawCallbackWindow
    }
}

enum HardwareLabModifierEvidence {
    private static let caseModifiers: Set<KeyModifier> = [.shift, .capsLock, .alphaShift]
    private static let futureTolerance: TimeInterval = 0.05

    static func eventByMergingRecentCaseModifiers(
        event: KeyEvent,
        expectedTextDelta: String,
        recentEvents: [KeyEvent],
        observedAt: Date,
        matchWindow: TimeInterval
    ) -> KeyEvent {
        guard expectedTextDelta.rangeOfCharacter(from: .uppercaseLetters) != nil else {
            return event
        }

        let mergedModifiers = event.modifiers.union(
            recentCaseModifiers(
                excluding: event,
                from: recentEvents,
                observedAt: observedAt,
                matchWindow: matchWindow
            )
        )
        guard mergedModifiers != event.modifiers else { return event }

        return KeyEvent(
            id: event.id,
            timestamp: event.timestamp,
            source: event.source,
            phase: event.phase,
            characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode,
            modifiers: mergedModifiers,
            isRepeat: event.isRepeat,
            sequence: event.sequence,
            isSynthetic: event.isSynthetic
        )
    }

    private static func recentCaseModifiers(
        excluding event: KeyEvent,
        from recentEvents: [KeyEvent],
        observedAt: Date,
        matchWindow: TimeInterval
    ) -> Set<KeyModifier> {
        var active = Set<KeyModifier>()
        let candidates = recentEvents
            .filter { $0.id != event.id }
            .filter { observedAt.timeIntervalSince($0.timestamp) >= -futureTolerance }
            .filter { observedAt.timeIntervalSince($0.timestamp) <= matchWindow }
            .sorted { $0.timestamp < $1.timestamp }

        for candidate in candidates {
            if candidate.phase == .up,
               caseModifierKeyCode(candidate.keyCode) == .shift {
                active.remove(.shift)
                continue
            }

            active.formUnion(candidate.modifiers.intersection(caseModifiers))

            if candidate.phase == .down,
               let keyModifier = caseModifierKeyCode(candidate.keyCode) {
                active.insert(keyModifier)
            }
        }

        return active
    }

    private static func caseModifierKeyCode(_ keyCode: Int?) -> KeyModifier? {
        switch keyCode {
        case 225, 229:
            return .shift
        case 57, 130:
            return .capsLock
        default:
            return nil
        }
    }
}

private struct KeyArchiveEvent: Encodable {
    let id: UUID
    let timestamp: Date
    let source: String
    let phase: String
    let characters: String?
    let charactersIgnoringModifiers: String?
    let keyCode: Int?
    let modifiers: [String]
    let isRepeat: Bool
    let sequence: UInt64
    let isSynthetic: Bool

    init(_ event: KeyEvent) {
        id = event.id
        timestamp = event.timestamp
        source = event.source.archiveString
        phase = event.phase.archiveString
        characters = event.characters
        charactersIgnoringModifiers = event.charactersIgnoringModifiers
        keyCode = event.keyCode
        modifiers = event.modifiers.map(\.archiveString).sorted()
        isRepeat = event.isRepeat
        sequence = event.sequence
        isSynthetic = event.isSynthetic
    }
}

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
struct HardwareLabHostVisibleRow: Codable, Equatable, Identifiable {
    private static let redactedTextDelta = "[redacted]"

    let id: String
    let transactionID: String
    let source: String
    let phase: String
    let keyCode: Int?
    let expectedTextDelta: String
    let observedTextDelta: String
    let modifiers: [String]
    let mutationOwner: String
    let sourceRows: [String]
    let latencyMs: Double

    init(
        transactionID: String,
        source: String,
        phase: String,
        keyCode: Int?,
        expectedTextDelta: String,
        observedTextDelta: String,
        modifiers: [String] = [],
        mutationOwner: String,
        sourceRows: [String],
        latencyMs: Double
    ) {
        self.id = transactionID
        self.transactionID = transactionID
        self.source = source
        self.phase = phase
        self.keyCode = keyCode
        self.expectedTextDelta = expectedTextDelta
        self.observedTextDelta = observedTextDelta
        self.modifiers = modifiers
        self.mutationOwner = mutationOwner
        self.sourceRows = sourceRows
        self.latencyMs = latencyMs
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case transactionID
        case source
        case phase
        case keyCode
        case expectedTextDelta
        case observedTextDelta
        case modifiers
        case mutationOwner
        case sourceRows
        case latencyMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        transactionID = try container.decode(String.self, forKey: .transactionID)
        source = try container.decode(String.self, forKey: .source)
        phase = try container.decode(String.self, forKey: .phase)
        keyCode = try container.decodeIfPresent(Int.self, forKey: .keyCode)
        expectedTextDelta = try container.decode(String.self, forKey: .expectedTextDelta)
        observedTextDelta = try container.decode(String.self, forKey: .observedTextDelta)
        modifiers = try container.decodeIfPresent([String].self, forKey: .modifiers) ?? []
        mutationOwner = try container.decode(String.self, forKey: .mutationOwner)
        sourceRows = try container.decode([String].self, forKey: .sourceRows)
        latencyMs = try container.decode(Double.self, forKey: .latencyMs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(transactionID, forKey: .transactionID)
        try container.encode(source, forKey: .source)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
        try container.encode(Self.redactedTextDelta, forKey: .expectedTextDelta)
        try container.encode(Self.redactedTextDelta, forKey: .observedTextDelta)
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(mutationOwner, forKey: .mutationOwner)
        try container.encode(sourceRows, forKey: .sourceRows)
        try container.encode(latencyMs, forKey: .latencyMs)
    }
}

struct HardwareLabHostVisiblePayload: Codable, Equatable {
    let seed: Int?
    let generatedAtMs: Double?
    let hostVisibleRows: [HardwareLabHostVisibleRow]
}

struct HardwareLabExportStore {
    static let latestPayloadKey = "hardwareLabLatestHostVisiblePayloadJSON"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard) {
        self.defaults = defaults
    }

    func saveLatestPayload(_ json: String) {
        defaults.set(json, forKey: Self.latestPayloadKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.latestPayloadKey)
    }
}

final class HardwareLabHostVisibleRecorder {
    private(set) var rows: [HardwareLabHostVisibleRow] = []
    private let exportStore: HardwareLabExportStore?

    init(exportStore: HardwareLabExportStore? = nil) {
        self.exportStore = exportStore
    }

    func clear() {
        rows.removeAll()
        exportStore?.clear()
    }

    func record(
        event: KeyEvent,
        expectedTextDelta: String,
        previousText: String,
        currentText: String,
        sourceLane: String? = nil,
        mutationOwner: String = "HardwareLab",
        observedAt: Date = Date()
    ) {
        let source = sourceLane ?? Self.defaultSourceLane(for: event.source)
        let phase = event.phase.archiveString
        let sourceRows = [
            "\(source):\(phase):\(event.keyCode.map(String.init) ?? "nil")",
            "event:\(event.id.uuidString)",
        ]
        rows.append(
            HardwareLabHostVisibleRow(
                transactionID: event.id.uuidString,
                source: source,
                phase: phase,
                keyCode: event.keyCode,
                expectedTextDelta: expectedTextDelta,
                observedTextDelta: Self.observedTextDelta(before: previousText, after: currentText),
                modifiers: event.modifiers.map(\.archiveString).sorted(),
                mutationOwner: mutationOwner,
                sourceRows: sourceRows,
                latencyMs: Self.roundedMilliseconds(from: event.timestamp, to: observedAt)
            )
        )
        _ = persistLatestPayload()
    }

    func payload(seed: Int? = nil) -> HardwareLabHostVisiblePayload {
        HardwareLabHostVisiblePayload(
            seed: seed,
            generatedAtMs: Date().timeIntervalSince1970 * 1000,
            hostVisibleRows: rows
        )
    }

    func payloadJSONString(seed: Int? = nil) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(payload(seed: seed))
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func persistLatestPayload(seed: Int? = nil) -> String? {
        guard let json = try? payloadJSONString(seed: seed) else { return nil }
        exportStore?.saveLatestPayload(json)
        return json
    }

    private static func observedTextDelta(before: String, after: String) -> String {
        if after.hasPrefix(before) {
            return String(after.dropFirst(before.count))
        }

        let prefix = after.commonPrefix(with: before)
        return String(after.dropFirst(prefix.count))
    }

    private static func roundedMilliseconds(from start: Date, to end: Date) -> Double {
        let milliseconds = max(0, end.timeIntervalSince(start) * 1000)
        return (milliseconds * 1000).rounded() / 1000
    }

    private     static func defaultSourceLane(for source: KeyEventSource) -> String {
        switch source {
        case .keyCommand:
            return "UIKeyCommand"
        case .appDebug:
            return "GameControllerDelta"
        case .pressesBegan, .pressesChanged, .pressesEnded, .inferred:
            return "UIPress"
        }
    }
}
#endif

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
enum HardwareReliabilityCounter: String, Codable, CaseIterable {
    case modifierMismatch
    case lifecycleViolation
    case orphanedDown
    case orphanedUp
    case crossSourceDivergence
    case firstResponderLoss
}

/// Event counters for hardware key capture diagnostics
struct HardwareEventCounters: Codable, Equatable {
    var totalCaptured: UInt64 = 0
    var droppedDedup: UInt64 = 0
    var droppedOverflow: UInt64 = 0
    var droppedRelay: UInt64 = 0
    var synthesizedUp: UInt64 = 0
    var modifierMismatch: UInt64 = 0
    var lifecycleViolation: UInt64 = 0
    var orphanedDown: UInt64 = 0
    var orphanedUp: UInt64 = 0
    var crossSourceDivergence: UInt64 = 0
    var firstResponderLoss: UInt64 = 0
    var lastOverflowTimestamp: Date?

    mutating func increment(_ counter: HardwareReliabilityCounter) {
        switch counter {
        case .modifierMismatch:
            modifierMismatch += 1
        case .lifecycleViolation:
            lifecycleViolation += 1
        case .orphanedDown:
            orphanedDown += 1
        case .orphanedUp:
            orphanedUp += 1
        case .crossSourceDivergence:
            crossSourceDivergence += 1
        case .firstResponderLoss:
            firstResponderLoss += 1
        }
    }

    func value(for counter: HardwareReliabilityCounter) -> UInt64 {
        switch counter {
        case .modifierMismatch:
            return modifierMismatch
        case .lifecycleViolation:
            return lifecycleViolation
        case .orphanedDown:
            return orphanedDown
        case .orphanedUp:
            return orphanedUp
        case .crossSourceDivergence:
            return crossSourceDivergence
        case .firstResponderLoss:
            return firstResponderLoss
        }
    }

    private enum CodingKeys: String, CodingKey {
        case totalCaptured = "tc"
        case droppedDedup = "dd"
        case droppedOverflow = "do"
        case droppedRelay = "rl"
        case synthesizedUp = "su"
        case modifierMismatch = "mm"
        case lifecycleViolation = "lv"
        case orphanedDown = "od"
        case orphanedUp = "ou"
        case crossSourceDivergence = "xd"
        case firstResponderLoss = "fr"
        case lastOverflowTimestamp = "lo"
    }
}
#endif

#if HWC_INTERNAL_BUILD
enum KeyDiagComponent: String, Codable {
    case companion = "a"
    case keyboard = "k"
}

enum KeyDiagCode: String, Codable {
    case appVisible = "av"
    case captureChanged = "cg"
    case keyboardVisible = "kv"
    case keyboardHidden = "kh"
    case selectionChanged = "sc"
    case textChanged = "tc"
    case responderState = "rs"
    case pressDown = "pd"
    case pressUp = "pu"
    case keyCommand = "kc"
    case relayApplied = "ta"
    case pressDeduped = "dp"
    case relayDeduped = "dr"
    case relayDropped = "rd"
    case relaySkipped = "rk"
    case ringPayloadDecodeError = "re"
    case ringOverflow = "ro"
    case modifierRepaired = "mr"
    case capsLockChanged = "cl"
    case gameControllerUnavailable = "gu"
    case gameControllerAttached = "ga"
    case gameControllerKeyChanged = "gk"
    case repeatStarted = "r0"
    case repeatTick = "r1"
    case repeatStopped = "r2"
    case memoryFlush = "mf"
    case manualForceCloseRequested = "mc"
}

struct KeyDiagEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let component: KeyDiagComponent
    let code: KeyDiagCode
    let flags: Int
    let source: KeyEventSource?
    let keyCode: Int?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        component: KeyDiagComponent,
        code: KeyDiagCode,
        flags: Int,
        source: KeyEventSource? = nil,
        keyCode: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.component = component
        self.code = code
        self.flags = flags
        self.source = source
        self.keyCode = keyCode
    }

    private enum CodingKeys: String, CodingKey {
        case id = "i"
        case timestamp = "t"
        case component = "c"
        case code = "d"
        case flags = "f"
        case source = "s"
        case keyCode = "k"
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case id
        case timestamp
        case component
        case code
        case flags
        case source
        case keyCode
    }

    init(from decoder: Decoder) throws {
        let compact = try decoder.container(keyedBy: CodingKeys.self)

        if !compact.allKeys.isEmpty {
            id = try compact.decode(UUID.self, forKey: .id)
            timestamp = try compact.decode(Date.self, forKey: .timestamp)
            component = try compact.decode(KeyDiagComponent.self, forKey: .component)
            code = try compact.decode(KeyDiagCode.self, forKey: .code)
            flags = try compact.decode(Int.self, forKey: .flags)
            source = try compact.decodeIfPresent(KeyEventSource.self, forKey: .source)
            keyCode = try compact.decodeIfPresent(Int.self, forKey: .keyCode)
            return
        }

        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        id = try legacy.decode(UUID.self, forKey: .id)
        timestamp = try legacy.decode(Date.self, forKey: .timestamp)
        component = try legacy.decode(KeyDiagComponent.self, forKey: .component)
        code = try legacy.decode(KeyDiagCode.self, forKey: .code)
        flags = try legacy.decode(Int.self, forKey: .flags)
        source = try legacy.decodeIfPresent(KeyEventSource.self, forKey: .source)
        keyCode = try legacy.decodeIfPresent(Int.self, forKey: .keyCode)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(component, forKey: .component)
        try container.encode(code, forKey: .code)
        try container.encode(flags, forKey: .flags)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(keyCode, forKey: .keyCode)
    }
}

enum KeyDiagStore {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let storageKey = "keyboard.hwDiagnostics.events"
    static let countersKey = "keyboard.hwDiagnostics.counters"
    static let capacity = 96
    static let retentionInterval: TimeInterval = 15 * 60

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.hw-diagnostics")

    static func append(_ event: KeyDiagEvent) {
        queue.sync {
            appendLocked(event)
        }
    }

    static func appendFromInputPath(_ event: KeyDiagEvent) {
        queue.async {
            appendLocked(event)
        }
    }

    static func append(
        component: KeyDiagComponent,
        code: KeyDiagCode,
        flags: Int,
        source: KeyEventSource? = nil,
        keyCode: Int? = nil
    ) {
        append(
            KeyDiagEvent(
                component: component,
                code: code,
                flags: flags,
                source: source,
                keyCode: keyCode
            )
        )
    }

    static func clear() {
        queue.sync {
            sharedDefaults.removeObject(forKey: storageKey)
            sharedDefaults.removeObject(forKey: countersKey)
            KeyboardSharedPreferences.sync()
        }
    }

    static func getCounters() -> HardwareEventCounters {
        queue.sync {
            loadCountersLocked()
        }
    }

    static func incrementTotalCaptured() {
        queue.sync {
            var counters = loadCountersLocked()
            counters.totalCaptured += 1
            saveCounters(counters)
        }
    }

    static func incrementDroppedDedup() {
        queue.sync {
            var counters = loadCountersLocked()
            counters.droppedDedup += 1
            saveCounters(counters)
        }
    }

    static func incrementDroppedOverflow(count: UInt64 = 1) {
        queue.sync {
            var counters = loadCountersLocked()
            counters.droppedOverflow += count
            counters.lastOverflowTimestamp = Date()
            saveCounters(counters)
        }
    }

    static func incrementSynthesizedUp() {
        queue.sync {
            var counters = loadCountersLocked()
            counters.synthesizedUp += 1
            saveCounters(counters)
        }
    }

    static func incrementDroppedRelay() {
        queue.sync {
            var counters = loadCountersLocked()
            counters.droppedRelay += 1
            saveCounters(counters)
        }
    }

    static func incrementReliabilityCounter(_ counter: HardwareReliabilityCounter) {
        queue.sync {
            var counters = loadCountersLocked()
            counters.increment(counter)
            saveCounters(counters)
        }
    }

    static func resetCounters() {
        queue.sync {
            sharedDefaults.removeObject(forKey: countersKey)
            KeyboardSharedPreferences.sync()
        }
    }

    private static func saveCounters(_ counters: HardwareEventCounters) {
        guard let data = try? makeEncoder().encode(counters) else { return }
        sharedDefaults.set(data, forKey: countersKey)
        KeyboardSharedPreferences.sync()
    }

    private static func loadCountersLocked() -> HardwareEventCounters {
        guard let data = sharedDefaults.data(forKey: countersKey),
              let counters = try? makeDecoder().decode(HardwareEventCounters.self, from: data) else {
            return HardwareEventCounters()
        }
        return counters
    }

    static func crashMessage(reason: String, settings: KeyboardSettingsSnapshot = .load()) -> String {
        queue.sync {
            let defaults = sharedDefaults
            let events = Array(storedEvents(from: defaults).suffix(32))
            let settingsToken = compactSettingsToken(for: settings)
            let checksum = checksumToken(for: events)

            guard !events.isEmpty else {
                return "HWC_DIAG_V1|r=\(reason)|s=\(settingsToken)|n=0|x=\(checksum)"
            }

            var trimmedEvents = events
            var message = serializedCrashMessage(
                reason: reason,
                settingsToken: settingsToken,
                events: trimmedEvents,
                checksum: checksum
            )

            while message.count > 700, trimmedEvents.count > 8 {
                trimmedEvents.removeFirst(trimmedEvents.count - max(trimmedEvents.count - 4, 8))
                message = serializedCrashMessage(
                    reason: reason,
                    settingsToken: settingsToken,
                    events: trimmedEvents,
                    checksum: checksum
                )
            }

            return message
        }
    }

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    private static func appendLocked(_ event: KeyDiagEvent) {
        let defaults = sharedDefaults
        var events = storedEvents(from: defaults, referenceDate: event.timestamp)
        events.append(event)

        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }

        guard let data = try? makeEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
        KeyboardSharedPreferences.sync()
    }

    private static func storedEvents(
        from defaults: UserDefaults,
        referenceDate: Date = Date()
    ) -> [KeyDiagEvent] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        guard let events = try? makeDecoder().decode([KeyDiagEvent].self, from: data) else {
            defaults.removeObject(forKey: storageKey)
            KeyboardSharedPreferences.sync()
            return []
        }

        let retainedEvents = events.filter { referenceDate.timeIntervalSince($0.timestamp) <= retentionInterval }
        if retainedEvents.count != events.count {
            if let data = try? makeEncoder().encode(retainedEvents) {
                defaults.set(data, forKey: storageKey)
            } else {
                defaults.removeObject(forKey: storageKey)
            }
            KeyboardSharedPreferences.sync()
        }

        return Array(retainedEvents.suffix(capacity))
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

    private static func compactSettingsToken(for settings: KeyboardSettingsSnapshot) -> String {
        let enabled = settings.signalRelayEnabled ? "1" : "0"
        let emitKeyUp = settings.signalRelayEmitKeyUp ? "1" : "0"
        let priorityMode = settings.signalRelayPriorityMode ? "1" : "0"
        let persist = settings.signalRelaySessionPersist ? "1" : "0"
        let holdTrigger = String(settings.signalRelayHoldTriggerMs, radix: 36)
        return [enabled, emitKeyUp, priorityMode, persist, holdTrigger].joined()
    }

    private static func serializedCrashMessage(
        reason: String,
        settingsToken: String,
        events: [KeyDiagEvent],
        checksum: String
    ) -> String {
        let baseTimestamp = events.first?.timestamp ?? Date()
        let payload = events.map { compactEventToken($0, baseTimestamp: baseTimestamp) }.joined(separator: ",")
        return "HWC_DIAG_V1|r=\(reason)|s=\(settingsToken)|n=\(events.count)|e=\(payload)|x=\(checksum)"
    }

    private static func compactEventToken(
        _ event: KeyDiagEvent,
        baseTimestamp: Date
    ) -> String {
        let deltaTenths = max(0, Int(event.timestamp.timeIntervalSince(baseTimestamp) * 10))
        let sourceToken = event.source?.rawValue ?? "-"
        let keyToken = event.keyCode.map { String($0, radix: 36) } ?? "-"
        return [
            String(deltaTenths, radix: 36),
            event.component.rawValue,
            event.code.rawValue,
            sourceToken,
            keyToken,
            String(event.flags, radix: 36),
        ].joined(separator: ".")
    }

    private static func checksumToken(for events: [KeyDiagEvent]) -> String {
        let checksum = events.reduce(0) { partialResult, event in
            let timestamp = Int(event.timestamp.timeIntervalSince1970.rounded())
            return partialResult ^ (timestamp &+ event.flags &+ (event.keyCode ?? 0))
        }
        return String(checksum, radix: 36)
    }
}

struct RelayResponderPolledModifierSnapshot: Codable, Equatable, Sendable {
    static let empty = RelayResponderPolledModifierSnapshot(
        keyNames: [],
        keyCodes: []
    )

    let keyNames: [String]
    let keyCodes: [Int]
}

struct RelayResponderLivenessRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let observedAt: Date
    let becomeFirstResponderResult: Bool
    let isFirstResponder: Bool
    let didReceivePress: Bool
    let isGameControllerKeyboardPresent: Bool
    let polledModifierKeyNames: [String]
    let polledModifierKeyCodes: [Int]
    let hostViewWidth: Double
    let hostViewHeight: Double
    let canBecomeFocused: Bool
    let focusSystemAvailable: Bool

    init(
        id: UUID = UUID(),
        observedAt: Date = Date(),
        becomeFirstResponderResult: Bool,
        isFirstResponder: Bool,
        didReceivePress: Bool,
        isGameControllerKeyboardPresent: Bool,
        polledModifierSnapshot: RelayResponderPolledModifierSnapshot = .empty,
        hostViewWidth: Double = 0,
        hostViewHeight: Double = 0,
        canBecomeFocused: Bool = false,
        focusSystemAvailable: Bool = false
    ) {
        self.id = id
        self.observedAt = observedAt
        self.becomeFirstResponderResult = becomeFirstResponderResult
        self.isFirstResponder = isFirstResponder
        self.didReceivePress = didReceivePress
        self.isGameControllerKeyboardPresent = isGameControllerKeyboardPresent
        self.polledModifierKeyNames = polledModifierSnapshot.keyNames
        self.polledModifierKeyCodes = polledModifierSnapshot.keyCodes
        self.hostViewWidth = hostViewWidth
        self.hostViewHeight = hostViewHeight
        self.canBecomeFocused = canBecomeFocused
        self.focusSystemAvailable = focusSystemAvailable
    }
}

enum HardwareReconstructionCharacterClass: String, Codable, Equatable, Sendable {
    private static let deleteBackspaceKeyCode = 42

    case lowercaseLetter = "lowercaseLetter"
    case uppercaseLetter = "uppercaseLetter"
    case digit = "digit"
    case whitespace = "whitespace"
    case punctuation = "punctuation"
    case symbol = "symbol"
    case delete = "delete"
    case other = "other"

    static func classify(_ event: KeyEvent) -> HardwareReconstructionCharacterClass {
        if event.keyCode == Self.deleteBackspaceKeyCode {
            return .delete
        }

        guard let text = event.characters,
              text.count == 1,
              let scalar = text.unicodeScalars.first else {
            return .other
        }

        if CharacterSet.lowercaseLetters.contains(scalar) { return .lowercaseLetter }
        if CharacterSet.uppercaseLetters.contains(scalar) { return .uppercaseLetter }
        if CharacterSet.decimalDigits.contains(scalar) { return .digit }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return .whitespace }
        if CharacterSet.punctuationCharacters.contains(scalar) { return .punctuation }
        if CharacterSet.symbols.contains(scalar) { return .symbol }
        return .other
    }
}

struct HardwareReconstructionBatchRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let observedAt: Date
    let beforeLength: Int
    let afterLength: Int
    let attemptedCount: Int
    let emittedCount: Int
    let dedupedCount: Int
    let rawInputLive: Bool
    let isRelayFirstResponder: Bool
    let isGameControllerKeyboardPresent: Bool
    let characterClasses: [HardwareReconstructionCharacterClass]

    init(
        id: UUID = UUID(),
        observedAt: Date = Date(),
        beforeLength: Int,
        afterLength: Int,
        attemptedCount: Int,
        emittedCount: Int,
        dedupedCount: Int,
        rawInputLive: Bool,
        isRelayFirstResponder: Bool,
        isGameControllerKeyboardPresent: Bool,
        characterClasses: [HardwareReconstructionCharacterClass]
    ) {
        self.id = id
        self.observedAt = observedAt
        self.beforeLength = beforeLength
        self.afterLength = afterLength
        self.attemptedCount = attemptedCount
        self.emittedCount = emittedCount
        self.dedupedCount = dedupedCount
        self.rawInputLive = rawInputLive
        self.isRelayFirstResponder = isRelayFirstResponder
        self.isGameControllerKeyboardPresent = isGameControllerKeyboardPresent
        self.characterClasses = characterClasses
    }
}

enum HardwareReconstructionBatchStore {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let storageKey = "keyboard.hardwareReconstruction.latestBatch"

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.hardware-reconstruction")

    static func update(_ record: HardwareReconstructionBatchRecord) {
        queue.sync {
            guard let data = try? makeEncoder().encode(record) else { return }
            sharedDefaults.set(data, forKey: storageKey)
            KeyboardSharedPreferences.sync()
        }
    }

    static func record() -> HardwareReconstructionBatchRecord? {
        queue.sync {
            guard let data = sharedDefaults.data(forKey: storageKey) else { return nil }
            guard let record = try? makeDecoder().decode(HardwareReconstructionBatchRecord.self, from: data) else {
                sharedDefaults.removeObject(forKey: storageKey)
                KeyboardSharedPreferences.sync()
                return nil
            }
            return record
        }
    }

    static func clear() {
        queue.sync {
            sharedDefaults.removeObject(forKey: storageKey)
            KeyboardSharedPreferences.sync()
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

enum RelayResponderLivenessStore {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let storageKey = "keyboard.relayResponderLiveness.record"

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.relay-responder-liveness")

    static func update(_ record: RelayResponderLivenessRecord) {
        queue.sync {
            guard let data = try? makeEncoder().encode(record) else { return }
            sharedDefaults.set(data, forKey: storageKey)
            KeyboardSharedPreferences.sync()
        }
    }

    static func record() -> RelayResponderLivenessRecord? {
        queue.sync {
            guard let data = sharedDefaults.data(forKey: storageKey) else { return nil }
            guard let record = try? makeDecoder().decode(RelayResponderLivenessRecord.self, from: data) else {
                sharedDefaults.removeObject(forKey: storageKey)
                KeyboardSharedPreferences.sync()
                return nil
            }
            return record
        }
    }

    static func clear() {
        queue.sync {
            sharedDefaults.removeObject(forKey: storageKey)
            KeyboardSharedPreferences.sync()
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
#endif

#if HWC_HARDWARE_CAPTURE && !HWC_INTERNAL_BUILD
enum KeyDiagStore {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let countersKey = "keyboard.hwDiagnostics.counters"

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.hw-diagnostics")

    static func getCounters() -> HardwareEventCounters {
        queue.sync {
            loadCountersLocked()
        }
    }

    static func incrementReliabilityCounter(_ counter: HardwareReliabilityCounter) {
        queue.sync {
            var counters = loadCountersLocked()
            counters.increment(counter)
            saveCounters(counters)
        }
    }

    static func resetCounters() {
        queue.sync {
            sharedDefaults.removeObject(forKey: countersKey)
            KeyboardSharedPreferences.sync()
        }
    }

    private static func saveCounters(_ counters: HardwareEventCounters) {
        guard let data = try? makeEncoder().encode(counters) else { return }
        sharedDefaults.set(data, forKey: countersKey)
        KeyboardSharedPreferences.sync()
    }

    private static func loadCountersLocked() -> HardwareEventCounters {
        guard let data = sharedDefaults.data(forKey: countersKey),
              let counters = try? makeDecoder().decode(HardwareEventCounters.self, from: data) else {
            return HardwareEventCounters()
        }
        return counters
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
#endif

#if HWC_INTERNAL_BUILD
enum KeyEventRing {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let storageKey = "keyboard.hwEvents.ringBuffer"
    static let darwinNotification = "dev.moni11811.hwkbcompanion.hw-events-did-change"
    static let capacity = 1024

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.hw-events")
    private static var lastNotificationAt = Date.distantPast
    private static var pendingNotificationWorkItem: DispatchWorkItem?
    private static var pendingInputPathEvents = [KeyEvent]()
    private static var pendingInputPathFlushWorkItem: DispatchWorkItem?
    private static let inputPathFlushDelay: TimeInterval = 0.01

    static func append(_ event: KeyEvent) {
        queue.sync {
            appendLocked([event])
        }
    }

    static func appendFromInputPath(_ event: KeyEvent) {
        queue.async {
            pendingInputPathEvents.append(event)
            scheduleInputPathFlushLocked()
        }
    }

    static func drain() -> [KeyEvent] {
        queue.sync {
            flushInputPathEventsLocked()
            guard KeySessionRelay.isEnabled else {
                clearSharedPayloadLocked()
                return []
            }

            guard let defaults = sharedDefaults else { return [] }

            let events = storedEvents(from: defaults)
            defaults.removeObject(forKey: storageKey)
            KeyboardSharedPreferences.sync()
            return events
        }
    }

    static func clear() {
        queue.sync {
            pendingInputPathFlushWorkItem?.cancel()
            pendingInputPathFlushWorkItem = nil
            pendingInputPathEvents.removeAll()
            clearSharedPayloadLocked()
            KeyDiagStore.resetCounters()
        }
    }

    static func prettyPrintedJSON(for events: [KeyEvent]) -> String? {
        guard KeySessionRelay.isEnabled else { return nil }
        let encoder = makePrettyEncoder()
        let archiveEvents = events.map(KeyArchiveEvent.init)
        guard let data = try? encoder.encode(archiveEvents) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    private static func appendLocked(_ eventsToAppend: [KeyEvent]) {
        guard !eventsToAppend.isEmpty else { return }

        guard KeySessionRelay.isEnabled else {
            for event in eventsToAppend {
                recordRelayDropLocked(code: .relayDropped, event: event)
            }
            clearSharedPayloadLocked()
            return
        }

        guard let defaults = sharedDefaults else {
            for event in eventsToAppend {
                recordRelayDropLocked(code: .relayDropped, event: event)
            }
            return
        }

        var events = storedEvents(from: defaults)
        events.append(contentsOf: eventsToAppend)
        let diagnosticEvent = eventsToAppend.last

        if events.count > capacity {
            let droppedCount = UInt64(events.count - capacity)
            events.removeFirst(events.count - capacity)
            if droppedCount > 0 {
                KeyDiagStore.incrementDroppedOverflow(count: droppedCount)
                KeyDiagStore.append(
                    component: .keyboard,
                    code: .ringOverflow,
                    flags: Int(droppedCount),
                    source: diagnosticEvent?.source,
                    keyCode: diagnosticEvent?.keyCode
                )
            }
        }

        let encoder = makeTransportEncoder()
        guard let data = try? encoder.encode(events) else {
            for event in eventsToAppend {
                recordRelayDropLocked(code: .relayDropped, event: event)
            }
            return
        }

        defaults.set(data, forKey: storageKey)
        scheduleDidChangeNotificationLocked()
    }

    private static func scheduleInputPathFlushLocked() {
        guard pendingInputPathFlushWorkItem == nil else { return }

        let workItem = DispatchWorkItem {
            queue.async {
                pendingInputPathFlushWorkItem = nil
                flushInputPathEventsLocked()
            }
        }

        pendingInputPathFlushWorkItem = workItem
        queue.asyncAfter(deadline: .now() + inputPathFlushDelay, execute: workItem)
    }

    private static func flushInputPathEventsLocked() {
        pendingInputPathFlushWorkItem?.cancel()
        pendingInputPathFlushWorkItem = nil
        let events = pendingInputPathEvents
        pendingInputPathEvents.removeAll(keepingCapacity: true)
        appendLocked(events)
    }

    private static func storedEvents(from defaults: UserDefaults) -> [KeyEvent] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        guard let events = try? makeTransportDecoder().decode([KeyEvent].self, from: data) else {
            KeyDiagStore.append(
                component: .keyboard,
                code: .ringPayloadDecodeError,
                flags: 1
            )
            defaults.removeObject(forKey: storageKey)
            KeyboardSharedPreferences.sync()
            return []
        }

        return Array(events.suffix(capacity))
    }

    private static func makeTransportEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    private static func makeTransportDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }

    private static func makePrettyEncoder() -> JSONEncoder {
        let encoder = makeTransportEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func clearSharedPayloadLocked() {
        guard let defaults = sharedDefaults else { return }
        defaults.removeObject(forKey: storageKey)
        KeyboardSharedPreferences.sync()
    }

    private static func recordRelayDropLocked(code: KeyDiagCode, event: KeyEvent) {
        KeyDiagStore.incrementDroppedRelay()
        KeyDiagStore.append(
            component: .keyboard,
            code: code,
            flags: diagnosticFlags(for: event),
            source: event.source,
            keyCode: event.keyCode
        )
    }

    private static func diagnosticFlags(for event: KeyEvent) -> Int {
        var flags = 0
        for modifier in event.modifiers {
            switch modifier {
            case .shift:
                flags |= 1 << 0
            case .control:
                flags |= 1 << 1
            case .option:
                flags |= 1 << 2
            case .command:
                flags |= 1 << 3
            case .capsLock:
                flags |= 1 << 4
            case .numericPad:
                flags |= 1 << 5
            case .alphaShift:
                flags |= 1 << 6
            }
        }
        return flags
    }

    private static func scheduleDidChangeNotificationLocked() {
        let minimumInterval: TimeInterval = 0.01
        let now = Date()
        let elapsed = now.timeIntervalSince(lastNotificationAt)

        if elapsed >= minimumInterval {
            postDidChangeNotificationLocked()
            return
        }

        guard pendingNotificationWorkItem == nil else { return }

        let workItem = DispatchWorkItem {
            queue.async {
                pendingNotificationWorkItem = nil
                postDidChangeNotificationLocked()
            }
        }

        pendingNotificationWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (minimumInterval - elapsed),
            execute: workItem
        )
    }

    private static func postDidChangeNotificationLocked() {
        pendingNotificationWorkItem?.cancel()
        pendingNotificationWorkItem = nil
        lastNotificationAt = Date()

        let name = CFNotificationName(darwinNotification as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }
}
#elseif HWC_HARDWARE_CAPTURE
enum KeyEventRing {
    static let suiteName = KeyboardSharedPreferences.appGroupIdentifier
    static let storageKey = "keyboard.hwEvents.ringBuffer"
    static let darwinNotification = "dev.moni11811.hwkbcompanion.hw-events-did-change"
    static let capacity = 1024

    private static let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.hw-events-public")

    static func append(_ event: KeyEvent) {
        queue.sync {
            _ = event
        }
    }

    static func drain() -> [KeyEvent] {
        queue.sync { [] }
    }

    static func clear() {
        queue.sync {}
    }

    static func prettyPrintedJSON(for events: [KeyEvent]) -> String? {
        _ = events
        return nil
    }
}
#endif

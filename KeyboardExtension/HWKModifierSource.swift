import Foundation
import UIKit

enum HWKModifierSource: String, Codable, CaseIterable {
    case uiPressEvent
    case uiKeyCommand
    case gameControllerSnapshot
    case gameControllerDelta
    case characterInference
    case fallback

    var priority: Int {
        switch self {
        case .gameControllerSnapshot:
            return 50
        case .uiPressEvent:
            return 45
        case .uiKeyCommand:
            return 40
        case .gameControllerDelta:
            return 35
        case .characterInference:
            return 20
        case .fallback:
            return 10
        }
    }

    var isClearableByEmptyGameControllerSnapshot: Bool {
        switch self {
        case .gameControllerSnapshot, .gameControllerDelta, .fallback:
            return true
        case .uiPressEvent, .uiKeyCommand, .characterInference:
            return false
        }
    }

    static func resolvedInsertText(
        input: String?,
        propertyListText: String?,
        keyCode: Int?,
        modifiers: Set<KeyModifier>
    ) -> String? {
        HWKHardwareCommandText.resolvedInsertText(
            input: input,
            propertyListText: propertyListText,
            keyCode: keyCode,
            modifiers: modifiers
        )
    }
}

struct HWKModifierTruth {
    private static let publishedModifierMask: UIKeyModifierFlags = [.shift, .alphaShift]

    static func publishedModifierFlags(
        isHardwareShiftHeld: Bool,
        isHardwareCapsLocked: Bool
    ) -> UIKeyModifierFlags {
        var flags = UIKeyModifierFlags()
        if isHardwareShiftHeld {
            flags.insert(.shift)
        }
        if isHardwareCapsLocked {
            flags.insert(.alphaShift)
        }
        return flags
    }

    static func retainedPublishedModifierFlags(from flags: UIKeyModifierFlags) -> UIKeyModifierFlags {
        flags.intersection(publishedModifierMask)
    }

    static func publishedStateMatches(
        retainedFlags: UIKeyModifierFlags,
        isHardwareShiftHeld: Bool,
        isHardwareCapsLocked: Bool
    ) -> Bool {
        retainedPublishedModifierFlags(from: retainedFlags) == publishedModifierFlags(
            isHardwareShiftHeld: isHardwareShiftHeld,
            isHardwareCapsLocked: isHardwareCapsLocked
        )
    }
}

enum HWKHardwareTextCaseResolver {
    static func provesCapsLockInactive(
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: Set<KeyModifier>
    ) -> Bool {
        guard !modifiers.isDisjoint(with: [.capsLock, .alphaShift]),
              !modifiers.contains(.shift),
              currentCharactersPreserveCase(
                characters ?? "",
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers
              ),
              let characters,
              characters == characters.lowercased(),
              characters != characters.uppercased() else {
            return false
        }
        return true
    }

    static func resolvedText(
        _ text: String,
        characters: String?,
        charactersIgnoringModifiers: String?,
        modifiers: Set<KeyModifier>,
        isSymbolKeyboard: Bool,
        isCapsShiftActive: Bool,
        prefersTranslatedLayout: Bool = false
    ) -> String {
        guard modifiers.isDisjoint(with: [.option, .command, .control, .numericPad]) else {
            return text
        }
        if !prefersTranslatedLayout || characters?.lowercased() == text.lowercased() {
            if let modifiedCharacters = trustedUIKitModifiedCharacters(
                characters: characters,
                charactersIgnoringModifiers: charactersIgnoringModifiers
            ) {
                return modifiedCharacters
            }
        }
        guard text.count == 1, let scalar = text.unicodeScalars.first else { return text }
        let isLetter = CharacterSet.letters.contains(scalar)
        guard isLetter else { return text }

        let shiftHeld = modifiers.contains(.shift)
        let capsLocked = modifiers.contains(.capsLock)

        if currentCharactersPreserveCase(
            text,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers
        ), !shiftHeld {
            return text
        }

        if shiftHeld && capsLocked {
            return text.lowercased()
        }

        if shiftHeld || capsLocked {
            return text.uppercased()
        }

        if !isSymbolKeyboard && isCapsShiftActive {
            return text.uppercased()
        }

        return text
    }

    private static func trustedUIKitModifiedCharacters(
        characters: String?,
        charactersIgnoringModifiers: String?
    ) -> String? {
        guard let characters,
              let charactersIgnoringModifiers,
              !characters.isEmpty,
              !charactersIgnoringModifiers.isEmpty,
              characters != charactersIgnoringModifiers else {
            return nil
        }
        return characters
    }

    private static func currentCharactersPreserveCase(
        _ text: String,
        characters: String?,
        charactersIgnoringModifiers: String?
    ) -> Bool {
        guard let characters,
              let charactersIgnoringModifiers,
              characters == text,
              characters == charactersIgnoringModifiers,
              characters.count == 1,
              let scalar = characters.unicodeScalars.first,
              CharacterSet.letters.contains(scalar) else {
            return false
        }
        return true
    }
}

struct HWKModifierState: Equatable {
    var modifiers: Set<KeyModifier>
    var source: HWKModifierSource

    static let empty = HWKModifierState(modifiers: [], source: .fallback)

    func replacingIfStronger(_ candidate: HWKModifierState) -> HWKModifierState {
        if source == .gameControllerSnapshot,
           modifiers.isEmpty,
           !candidate.modifiers.isEmpty,
           !candidate.source.isClearableByEmptyGameControllerSnapshot {
            return candidate
        }

        if candidate.source == .gameControllerSnapshot,
           candidate.modifiers.isEmpty,
           !modifiers.isEmpty,
           !source.isClearableByEmptyGameControllerSnapshot {
            return self
        }

        return candidate.source.priority >= source.priority ? candidate : self
    }

    static func resolved(from candidates: [HWKModifierState]) -> HWKModifierState {
        candidates.reduce(HWKModifierState.empty) { current, candidate in
            current.replacingIfStronger(candidate)
        }
    }

    static func resolvedForHardwarePress(
        uiPressState: Set<KeyModifier>,
        passthroughState: Set<KeyModifier>,
        snapshotState: Set<KeyModifier>?,
        retainedState: Set<KeyModifier>,
        retainedSource: HWKModifierSource
    ) -> HWKModifierState {
        let tracked: Set<KeyModifier> = [.command, .option, .control]
        let explicitTrackedState = uiPressState.intersection(tracked)
        let uiPressCaseState = uiPressState.subtracting(tracked)
        let filteredPassthroughState = passthroughState.subtracting(tracked)
        let filteredSnapshotState = snapshotState?.subtracting(tracked) ?? []
        let filteredRetainedState = retainedState.subtracting(tracked)

        var candidates = [HWKModifierState]()

        if !filteredRetainedState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: filteredRetainedState,
                    source: retainedSource
                )
            )
        }
        if !uiPressCaseState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: uiPressCaseState,
                    source: .uiPressEvent
                )
            )
        }
        if !filteredPassthroughState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: filteredPassthroughState,
                    source: .gameControllerDelta
                )
            )
        }
        if !filteredSnapshotState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: filteredSnapshotState,
                    source: .gameControllerSnapshot
                )
            )
        }

        let resolvedCaseState = HWKModifierState.resolved(from: candidates)
        let resolvedModifiers = resolvedCaseState.modifiers.union(explicitTrackedState)
        guard !resolvedModifiers.isEmpty else { return .empty }

        let source: HWKModifierSource
        if resolvedCaseState.modifiers.isEmpty {
            source = .uiPressEvent
        } else if !explicitTrackedState.isEmpty,
                  HWKModifierSource.uiPressEvent.priority >= resolvedCaseState.source.priority {
            source = .uiPressEvent
        } else {
            source = resolvedCaseState.source
        }
        return HWKModifierState(modifiers: resolvedModifiers, source: source)
    }

    static func resolvedForKeyCommand(
        uiPressState: Set<KeyModifier>,
        passthroughState: Set<KeyModifier>,
        snapshotState: Set<KeyModifier>?,
        retainedState: Set<KeyModifier>,
        retainedSource: HWKModifierSource,
        retainedLevelModifiersAreLive: Bool = false,
        keyCode: Int? = nil
    ) -> HWKModifierState {
        let tracked: Set<KeyModifier> = [.command, .option, .control]

        let explicitTrackedState = uiPressState.intersection(Set(tracked))
        let filteredPassthroughState = passthroughState.intersection(tracked)
        let filteredSnapshotState = snapshotState?.intersection(tracked) ?? []
        let untrackedPassthroughState = passthroughState.subtracting(tracked)
        let untrackedSnapshotState = snapshotState?.subtracting(tracked) ?? []
        let retainedStateWithoutImplicitTracked = explicitTrackedState.isEmpty
            ? retainedState.filter {
                guard !tracked.contains($0) else { return false }
                if $0 == .capsLock || $0 == .alphaShift {
                    return true
                }
                return retainedLevelModifiersAreLive || uiPressState.contains($0)
            }
            : retainedState.intersection(explicitTrackedState)
        let hasExplicitTrackedModifiers = !explicitTrackedState.isEmpty

        var candidates = [HWKModifierState]()

        if !retainedStateWithoutImplicitTracked.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: retainedStateWithoutImplicitTracked,
                    source: retainedSource
                )
            )
        }
        if !uiPressState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: uiPressState,
                    source: .uiPressEvent
            )
        )
        }
        if !hasExplicitTrackedModifiers && !untrackedPassthroughState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: untrackedPassthroughState,
                    source: .gameControllerDelta
                )
            )
        }
        if !hasExplicitTrackedModifiers, !untrackedSnapshotState.isEmpty {
            candidates.append(
                HWKModifierState(
                    modifiers: untrackedSnapshotState,
                    source: .gameControllerSnapshot
                )
            )
        }

        let resolvedState = HWKModifierState.resolved(from: candidates)
        let trackedState = filteredPassthroughState.union(filteredSnapshotState)
        guard !trackedState.isEmpty else { return resolvedState }

        let gameControllerSnapshotAddsTracked = !filteredSnapshotState
            .subtracting(explicitTrackedState)
            .isEmpty
        let gameControllerDeltaAddsTracked = !filteredPassthroughState
            .subtracting(explicitTrackedState.union(filteredSnapshotState))
            .isEmpty

        let trackedSource: HWKModifierSource
        if gameControllerSnapshotAddsTracked {
            trackedSource = .gameControllerSnapshot
        } else if gameControllerDeltaAddsTracked {
            trackedSource = .gameControllerDelta
        } else if !explicitTrackedState.isEmpty {
            trackedSource = .uiPressEvent
        } else if !filteredSnapshotState.isEmpty {
            trackedSource = .gameControllerSnapshot
        } else {
            trackedSource = .gameControllerDelta
        }

        let state = HWKModifierState(
            modifiers: resolvedState.modifiers.union(trackedState),
            source: trackedSource.priority >= resolvedState.source.priority ? trackedSource : resolvedState.source
        )
        return state.droppingStaleCommandForCaseLetterKeyCommand(
            uiPressState: uiPressState,
            retainedSource: retainedSource,
            keyCode: keyCode
        )
    }

    private func droppingStaleCommandForCaseLetterKeyCommand(
        uiPressState: Set<KeyModifier>,
        retainedSource: HWKModifierSource,
        keyCode: Int?
    ) -> HWKModifierState {
        guard let keyCode,
              Self.isLetterKeyCode(keyCode),
              modifiers.contains(.command),
              uiPressState.isDisjoint(with: [.command]),
              !modifiers.isDisjoint(with: [.shift, .capsLock, .alphaShift]) else {
            return self
        }

        var nextModifiers = modifiers
        nextModifiers.remove(.command)
        let nextSource: HWKModifierSource = nextModifiers.isEmpty ? .fallback : retainedSource
        return HWKModifierState(modifiers: nextModifiers, source: nextSource)
    }

    private static func isLetterKeyCode(_ keyCode: Int) -> Bool {
        (Int(UIKeyboardHIDUsage.keyboardA.rawValue)...Int(UIKeyboardHIDUsage.keyboardZ.rawValue)).contains(keyCode)
    }
}

struct HWKCapsLockLifecycle {
    enum Action: Equatable {
        case toggle
        case close
        case ignore
    }

    private var activeSources = Set<HWKModifierSource>()

    var isOpen: Bool {
        !activeSources.isEmpty
    }

    mutating func reset() {
        activeSources.removeAll()
    }

    mutating func handle(
        source: HWKModifierSource,
        phase: KeyPhase,
        isRepeat: Bool = false
    ) -> Action {
        switch phase {
        case .down:
            guard !isRepeat else { return .ignore }
            let wasOpen = isOpen
            activeSources.insert(source)
            return wasOpen ? .ignore : .toggle
        case .up:
            guard activeSources.remove(source) != nil else { return .ignore }
            return isOpen ? .ignore : .close
        }
    }
}

struct HWKMomentaryModifierLifecycle {
    enum Action: Equatable {
        case activate
        case deactivate
        case ignore
    }

    private struct Key: Hashable {
        let source: HWKModifierSource
        let keyCode: Int
    }

    private var activeKeys = [Key: Date]()

    var isHeld: Bool {
        !activeKeys.isEmpty
    }

    mutating func reset() {
        activeKeys.removeAll()
    }

    mutating func handle(
        source: HWKModifierSource,
        keyCode: Int,
        phase: KeyPhase,
        isRepeat: Bool = false,
        at date: Date = Date()
    ) -> Action {
        let key = Key(source: source, keyCode: keyCode)
        switch phase {
        case .down:
            guard !isRepeat else { return .ignore }
            let wasHeld = isHeld
            activeKeys[key] = date
            return wasHeld ? .ignore : .activate
        case .up:
            guard activeKeys.removeValue(forKey: key) != nil else { return .ignore }
            return isHeld ? .ignore : .deactivate
        }
    }

    mutating func expire(before cutoff: Date) -> Action {
        let wasHeld = isHeld
        activeKeys = activeKeys.filter { _, observedAt in
            observedAt > cutoff
        }
        guard wasHeld else { return .ignore }
        return isHeld ? .ignore : .deactivate
    }
}

struct HWKPassthroughModifierLifecycle {
    private struct Key: Hashable {
        let source: HWKModifierSource
        let keyCode: Int
    }

    private struct EventEntry {
        let flags: UIKeyModifierFlags
        let observedAt: Date
    }

    private static let trackedFlags: UIKeyModifierFlags = [.command, .alternate, .control]
    private var eventFlagsByKey = [Key: EventEntry]()
    private var polledFlags = UIKeyModifierFlags()

    var flags: UIKeyModifierFlags {
        eventFlags.union(polledFlags)
    }

    mutating func reset() {
        eventFlagsByKey.removeAll()
        polledFlags = []
    }

    @discardableResult
    mutating func handle(
        source: HWKModifierSource,
        keyCode: Int,
        flags: UIKeyModifierFlags,
        phase: KeyPhase,
        at date: Date = Date()
    ) -> UIKeyModifierFlags {
        let key = Key(source: source, keyCode: keyCode)
        switch phase {
        case .down:
            eventFlagsByKey[key] = EventEntry(
                flags: flags.intersection(Self.trackedFlags),
                observedAt: date
            )
        case .up:
            eventFlagsByKey.removeValue(forKey: key)
        }
        return self.flags
    }

    @discardableResult
    mutating func syncPolledFlags(_ flags: UIKeyModifierFlags) -> UIKeyModifierFlags {
        polledFlags = flags.intersection(Self.trackedFlags)
        return self.flags
    }

    @discardableResult
    mutating func expireEvents(before cutoff: Date) -> UIKeyModifierFlags {
        eventFlagsByKey = eventFlagsByKey.filter { _, entry in
            entry.observedAt > cutoff
        }
        return flags
    }

    private var eventFlags: UIKeyModifierFlags {
        eventFlagsByKey.values.reduce(into: UIKeyModifierFlags()) { result, entry in
            result.formUnion(entry.flags)
        }
    }
}

enum HWKHardwareCommandText {
    private static let keyboardALowerBound = 4
    private static let keyboardZUpperBound = 29

    static func resolvedInsertText(
        input: String?,
        propertyListText: String?,
        keyCode: Int?,
        modifiers: Set<KeyModifier>
    ) -> String? {
        let cachedText = nonEmpty(propertyListText) ?? nonEmpty(input)

        guard let keyCode else {
            return cachedText
        }

        if !(keyboardALowerBound...keyboardZUpperBound).contains(keyCode) {
            if let propertyListText = nonEmpty(propertyListText),
               HWKHardwarePrintableKey.text(forHIDKeyCode: keyCode, shifted: modifiers.contains(.shift)) != nil {
                return propertyListText
            }

            guard modifiers.isDisjoint(with: [.option, .command, .control]) else {
                return cachedText
            }

            return HWKHardwarePrintableKey.text(forHIDKeyCode: keyCode, shifted: modifiers.contains(.shift))
                ?? cachedText
        }

        if modifiers.contains(.option) {
            return cachedText
        }

        if let propertyListText = nonEmpty(propertyListText),
           !isSingleASCIILetter(propertyListText) {
            return propertyListText
        }

        guard let letter = normalizedSingleASCIILetter(input)
                ?? normalizedSingleASCIILetter(propertyListText)
                ?? letter(forHIDKeyCode: keyCode) else {
            return cachedText
        }

        let shiftHeld = modifiers.contains(.shift)
        let capsLocked = modifiers.contains(.capsLock) || modifiers.contains(.alphaShift)
        if shiftHeld && capsLocked {
            return (cachedText ?? letter).lowercased()
        }

        if shiftHeld || capsLocked {
            return (cachedText ?? letter).uppercased()
        }

        return cachedText ?? letter
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func normalizedSingleASCIILetter(_ text: String?) -> String? {
        guard let text = nonEmpty(text),
              text.utf8.count == 1,
              let byte = text.utf8.first else {
            return nil
        }

        switch byte {
        case 65...90:
            return String(UnicodeScalar(byte + 32))
        case 97...122:
            return text
        default:
            return nil
        }
    }

    private static func isSingleASCIILetter(_ text: String) -> Bool {
        normalizedSingleASCIILetter(text) != nil
    }

    private static func letter(forHIDKeyCode keyCode: Int) -> String? {
        guard (keyboardALowerBound...keyboardZUpperBound).contains(keyCode) else {
            return nil
        }

        return String(UnicodeScalar(UInt8(97 + keyCode - keyboardALowerBound)))
    }

}

struct HWKHardwarePrintableKey: Equatable {
    let input: String
    let shiftedText: String
    let keyCode: UIKeyboardHIDUsage

    static func text(forHIDKeyCode keyCode: Int, shifted: Bool) -> String? {
        guard let key = usQWERTYByRawHID[keyCode] else { return nil }
        return shifted ? key.shiftedText : key.input
    }

    static let usQWERTY: [HWKHardwarePrintableKey] = [
        HWKHardwarePrintableKey(input: "1", shiftedText: "!", keyCode: .keyboard1),
        HWKHardwarePrintableKey(input: "2", shiftedText: "@", keyCode: .keyboard2),
        HWKHardwarePrintableKey(input: "3", shiftedText: "#", keyCode: .keyboard3),
        HWKHardwarePrintableKey(input: "4", shiftedText: "$", keyCode: .keyboard4),
        HWKHardwarePrintableKey(input: "5", shiftedText: "%", keyCode: .keyboard5),
        HWKHardwarePrintableKey(input: "6", shiftedText: "^", keyCode: .keyboard6),
        HWKHardwarePrintableKey(input: "7", shiftedText: "&", keyCode: .keyboard7),
        HWKHardwarePrintableKey(input: "8", shiftedText: "*", keyCode: .keyboard8),
        HWKHardwarePrintableKey(input: "9", shiftedText: "(", keyCode: .keyboard9),
        HWKHardwarePrintableKey(input: "0", shiftedText: ")", keyCode: .keyboard0),
        HWKHardwarePrintableKey(input: "-", shiftedText: "_", keyCode: .keyboardHyphen),
        HWKHardwarePrintableKey(input: "=", shiftedText: "+", keyCode: .keyboardEqualSign),
        HWKHardwarePrintableKey(input: "[", shiftedText: "{", keyCode: .keyboardOpenBracket),
        HWKHardwarePrintableKey(input: "]", shiftedText: "}", keyCode: .keyboardCloseBracket),
        HWKHardwarePrintableKey(input: "\\", shiftedText: "|", keyCode: .keyboardBackslash),
        HWKHardwarePrintableKey(input: ";", shiftedText: ":", keyCode: .keyboardSemicolon),
        HWKHardwarePrintableKey(input: "'", shiftedText: "\"", keyCode: .keyboardQuote),
        HWKHardwarePrintableKey(input: "`", shiftedText: "~", keyCode: .keyboardGraveAccentAndTilde),
        HWKHardwarePrintableKey(input: ",", shiftedText: "<", keyCode: .keyboardComma),
        HWKHardwarePrintableKey(input: ".", shiftedText: ">", keyCode: .keyboardPeriod),
        HWKHardwarePrintableKey(input: "/", shiftedText: "?", keyCode: .keyboardSlash),
    ]

    private static let usQWERTYByRawHID = Dictionary(
        uniqueKeysWithValues: usQWERTY.map { (Int($0.keyCode.rawValue), $0) }
    )
}

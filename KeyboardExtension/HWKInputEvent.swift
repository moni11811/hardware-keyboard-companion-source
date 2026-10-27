import Foundation

enum HWKInputEventSource: String, Codable, CaseIterable {
    case softwareKey
    case uiPress
    case uiKeyCommand
    case gameController
    case textContext
}

enum HWKInputEventKind: Equatable {
    case character(String)
    case deadKey(HWKDeadKey)
    case deleteBackward
    case deleteForward
    case returnKey
    case tab
    case escape
    case cursor(offset: Int)
    case modifierOnly
    case layoutCommand(String)
    case unknown
}

struct HWKInputEvent: Equatable {
    var id: UUID
    var timestamp: TimeInterval
    var source: HWKInputEventSource
    var kind: HWKInputEventKind
    var keyCode: Int?
    var characters: String
    var modifierState: HWKModifierState
    var phase: KeyPhase

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        source: HWKInputEventSource,
        kind: HWKInputEventKind,
        keyCode: Int? = nil,
        characters: String = "",
        modifierState: HWKModifierState = .empty,
        phase: KeyPhase = .down
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.kind = kind
        self.keyCode = keyCode
        self.characters = characters
        self.modifierState = modifierState
        self.phase = phase
    }
}

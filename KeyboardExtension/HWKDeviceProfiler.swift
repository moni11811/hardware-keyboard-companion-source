import Foundation
import UIKit
import GameController

#if HWC_HARDWARE_CAPTURE || HWC_HARDWARE_CAPTURE

struct HWKDeviceProfile: Codable, Equatable {
    struct Transport: OptionSet, Codable, Equatable {
        let rawValue: UInt
        static let gameController = Transport(rawValue: 1 << 0)
        static let uiPress = Transport(rawValue: 1 << 1)
        static let uiKeyCommand = Transport(rawValue: 1 << 2)
    }

    struct SourceLane: OptionSet, Codable, Equatable {
        let rawValue: UInt
        static let uiPressEvent = SourceLane(rawValue: 1 << 0)
        static let uiKeyCommand = SourceLane(rawValue: 1 << 1)
        static let gameControllerDelta = SourceLane(rawValue: 1 << 2)
        static let gameControllerSnapshot = SourceLane(rawValue: 1 << 3)
    }

    struct ModifierBehavior: OptionSet, Codable, Equatable {
        let rawValue: UInt
        static let shiftMomentary = ModifierBehavior(rawValue: 1 << 0)
        static let capsLockLatched = ModifierBehavior(rawValue: 1 << 1)
        static let leftRightShiftVisible = ModifierBehavior(rawValue: 1 << 2)
        static let leftRightAltVisible = ModifierBehavior(rawValue: 1 << 3)
        static let leftRightGuiVisible = ModifierBehavior(rawValue: 1 << 4)
        static let leftRightControlVisible = ModifierBehavior(rawValue: 1 << 5)
        static let modifierOnlyRowsVisible = ModifierBehavior(rawValue: 1 << 6)
    }

    struct LayoutBehavior: OptionSet, Codable, Equatable {
        let rawValue: UInt
        static let hidStable = LayoutBehavior(rawValue: 1 << 0)
        static let charactersAvailable = LayoutBehavior(rawValue: 1 << 1)
        static let charactersIgnoringModifiersAvailable = LayoutBehavior(rawValue: 1 << 2)
    }

    struct FailureFlags: OptionSet, Codable, Equatable {
        let rawValue: UInt
        static let noKeyUp = FailureFlags(rawValue: 1 << 0)
        static let duplicateDown = FailureFlags(rawValue: 1 << 1)
        static let emptySnapshot = FailureFlags(rawValue: 1 << 2)
        static let coalescedAmbiguity = FailureFlags(rawValue: 1 << 3)
        static let firstResponderLoss = FailureFlags(rawValue: 1 << 4)
        static let gameControllerDisconnect = FailureFlags(rawValue: 1 << 5)
        static let staleModifierExpiry = FailureFlags(rawValue: 1 << 6)
        static let orphanedDown = FailureFlags(rawValue: 1 << 7)
        static let orphanedUp = FailureFlags(rawValue: 1 << 8)
    }

    var transport: Transport = []
    var sourceLanes: SourceLane = []
    var modifierBehavior: ModifierBehavior = []
    var layoutBehavior: LayoutBehavior = []
    var failureFlags: FailureFlags = []
    var sessionStartAtMs: Double = 0
    var totalKeyDowns: Int = 0
    var totalKeyUps: Int = 0
    var totalModifierOnlyEvents: Int = 0
}

final class HWKDeviceProfiler {
    private(set) var profile = HWKDeviceProfile()
    private var observedHIDCodes = Set<Int>()
    private var observedModifierHIDCodes = Set<Int>()
    private var hasCharacters = false
    private var hasCharactersIgnoringModifiers = false

    var summary: HWKDeviceProfile { profile }

    func markSessionStart() {
        profile.sessionStartAtMs = Date().timeIntervalSince1970 * 1000
    }

    func markGameControllerAvailable() {
        profile.transport.insert(.gameController)
    }

    func markGameControllerUnavailable() {
        profile.transport.remove(.gameController)
    }

    func markUIPressEvent() {
        profile.transport.insert(.uiPress)
    }

    func markUIKeyCommand() {
        profile.transport.insert(.uiKeyCommand)
    }

    func recordSourceLane(_ lane: HWKDeviceProfile.SourceLane) {
        profile.sourceLanes.insert(lane)
    }

    func recordKeyEvent(
        hidCode: Int,
        characters: String,
        charactersIgnoringModifiers: String
    ) {
        observedHIDCodes.insert(hidCode)
        if !characters.isEmpty { hasCharacters = true }
        if !charactersIgnoringModifiers.isEmpty { hasCharactersIgnoringModifiers = true }
        updateLayoutBehavior()
    }

    func recordModifierHIDCode(_ hidCode: Int) {
        observedModifierHIDCodes.insert(hidCode)
        updateModifierBehavior()
    }

    func recordModifierOnlyRow() {
        profile.totalModifierOnlyEvents += 1
        profile.modifierBehavior.insert(.modifierOnlyRowsVisible)
    }

    func recordKeyDown() {
        profile.totalKeyDowns += 1
    }

    func recordKeyUp() {
        profile.totalKeyUps += 1
    }

    func recordFailure(_ flag: HWKDeviceProfile.FailureFlags) {
        profile.failureFlags.insert(flag)
    }

    func clearFailure(_ flag: HWKDeviceProfile.FailureFlags) {
        profile.failureFlags.remove(flag)
    }

    func reset() {
        profile = HWKDeviceProfile()
        observedHIDCodes.removeAll()
        observedModifierHIDCodes.removeAll()
        hasCharacters = false
        hasCharactersIgnoringModifiers = false
    }

    private func updateModifierBehavior() {
        if observedModifierHIDCodes.contains(Int(GCKeyCode.leftShift.rawValue)) ||
           observedModifierHIDCodes.contains(Int(GCKeyCode.rightShift.rawValue)) {
            profile.modifierBehavior.insert(.shiftMomentary)
        }
        if observedModifierHIDCodes.contains(Int(GCKeyCode.leftShift.rawValue)) &&
           observedModifierHIDCodes.contains(Int(GCKeyCode.rightShift.rawValue)) {
            profile.modifierBehavior.insert(.leftRightShiftVisible)
        }
        if observedModifierHIDCodes.contains(Int(GCKeyCode.capsLock.rawValue)) {
            profile.modifierBehavior.insert(.capsLockLatched)
        }
        if observedModifierHIDCodes.contains(Int(GCKeyCode.leftAlt.rawValue)) &&
           observedModifierHIDCodes.contains(Int(GCKeyCode.rightAlt.rawValue)) {
            profile.modifierBehavior.insert(.leftRightAltVisible)
        }
        if observedModifierHIDCodes.contains(Int(GCKeyCode.leftGUI.rawValue)) &&
           observedModifierHIDCodes.contains(Int(GCKeyCode.rightGUI.rawValue)) {
            profile.modifierBehavior.insert(.leftRightGuiVisible)
        }
        if observedModifierHIDCodes.contains(Int(GCKeyCode.leftControl.rawValue)) &&
           observedModifierHIDCodes.contains(Int(GCKeyCode.rightControl.rawValue)) {
            profile.modifierBehavior.insert(.leftRightControlVisible)
        }
    }

    private func updateLayoutBehavior() {
        if !observedHIDCodes.isEmpty {
            profile.layoutBehavior.insert(.hidStable)
        }
        if hasCharacters {
            profile.layoutBehavior.insert(.charactersAvailable)
        }
        if hasCharactersIgnoringModifiers {
            profile.layoutBehavior.insert(.charactersIgnoringModifiersAvailable)
        }
    }
}

#endif

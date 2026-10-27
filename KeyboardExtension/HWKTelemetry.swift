import Foundation
import os

protocol HWKTelemetryRecording {
    func record(_ event: HWKTelemetryEvent)
}

struct HWKTelemetryEvent: Equatable {
    enum Name: String {
        case keyDownToOutcome
    }

    enum Phase: String {
        case begin
        case end
    }

    var name: Name
    var phase: Phase
    var source: HWKInputEventSource
    var kind: String
    var inputPhase: String
    var mutationCount: Int
    var sideEffectCount: Int

    static func begin(for event: HWKInputEvent) -> HWKTelemetryEvent {
        HWKTelemetryEvent(
            name: .keyDownToOutcome,
            phase: .begin,
            source: event.source,
            kind: event.kind.telemetryLabel,
            inputPhase: event.phase.rawValue,
            mutationCount: 0,
            sideEffectCount: 0
        )
    }

    static func end(for event: HWKInputEvent, outcome: HWKInputOutcome) -> HWKTelemetryEvent {
        HWKTelemetryEvent(
            name: .keyDownToOutcome,
            phase: .end,
            source: event.source,
            kind: event.kind.telemetryLabel,
            inputPhase: event.phase.rawValue,
            mutationCount: outcome.textMutations.count,
            sideEffectCount: outcome.sideEffects.count
        )
    }
}

struct HWKOSLogTelemetryRecorder: HWKTelemetryRecording {
    func record(_ event: HWKTelemetryEvent) {
        switch event.phase {
        case .begin:
            os_signpost(
                .begin,
                log: HWKTelemetry.perf,
                name: "keyDownToOutcome",
                "%{private}@ %{private}@ %{private}@",
                event.source.rawValue,
                event.kind,
                event.inputPhase
            )
        case .end:
            os_signpost(
                .end,
                log: HWKTelemetry.perf,
                name: "keyDownToOutcome",
                "%{private}@ %{private}@ mutations=%{public}d sideEffects=%{public}d",
                event.source.rawValue,
                event.kind,
                event.mutationCount,
                event.sideEffectCount
            )
        }

        os_log(
            "kernel %{private}@ source=%{private}@ kind=%{private}@ mutations=%{public}d sideEffects=%{public}d",
            log: HWKTelemetry.input,
            type: .debug,
            event.phase.rawValue,
            event.source.rawValue,
            event.kind,
            event.mutationCount,
            event.sideEffectCount
        )
    }
}

enum HWKTelemetry {
    static let input = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "input")
    static let layout = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "layout")
    static let text = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "text")
    static let prediction = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "prediction")
    static let perf = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "perf")
    static let release = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "release")
    static let reliability = OSLog(subsystem: "dev.moni11811.hwkbcompanion.keyboard", category: "reliability")

    static func signpostID(_ object: AnyObject) -> OSSignpostID {
        OSSignpostID(log: perf, object: object)
    }

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
    static func recordHardwareReliabilityCounter(_ counter: HardwareReliabilityCounter, total: UInt64) {
        os_log(
            "hardwareReliability counter=%{public}d total=%{public}llu",
            log: reliability,
            type: .info,
            counter.telemetryCode,
            total
        )
    }
#endif
}

private extension HWKInputEventKind {
    var telemetryLabel: String {
        switch self {
        case .character:
            return "character"
        case .deadKey:
            return "deadKey"
        case .deleteBackward:
            return "deleteBackward"
        case .deleteForward:
            return "deleteForward"
        case .returnKey:
            return "returnKey"
        case .tab:
            return "tab"
        case .escape:
            return "escape"
        case .cursor:
            return "cursor"
        case .modifierOnly:
            return "modifierOnly"
        case .layoutCommand:
            return "layoutCommand"
        case .unknown:
            return "unknown"
        }
    }
}

#if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
private extension HardwareReliabilityCounter {
    var telemetryCode: Int {
        switch self {
        case .modifierMismatch:
            return 1
        case .lifecycleViolation:
            return 2
        case .orphanedDown:
            return 3
        case .orphanedUp:
            return 4
        case .crossSourceDivergence:
            return 5
        case .firstResponderLoss:
            return 6
        }
    }
}
#endif

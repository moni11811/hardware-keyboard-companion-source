import Foundation
import os
import UIKit

enum HWCHardwareKeyboardNativePathProbe {
    static let defaultsKey = "hardwareNativePathProbe.lines"
    private static let lineLimit = 256
    private static let log = OSLog(
        subsystem: "dev.moni11811.hwkbcompanion.keyboard",
        category: "hardware-native-probe"
    )

    static func contextSummary(before: String?, after: String?) -> String {
        let beforeCount = before?.count ?? -1
        let afterCount = after?.count ?? -1
        return [
            "beforeLen=\(beforeCount)",
            "afterLen=\(afterCount)",
            "delta=\(afterCount - beforeCount)",
            "beforeHash=\(fingerprint(before))",
            "afterHash=\(fingerprint(after))",
        ].joined(separator: " ")
    }

    static func pressSummary(_ presses: Set<UIPress>) -> String {
        let rows = presses
            .sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return ObjectIdentifier(lhs).hashValue < ObjectIdentifier(rhs).hashValue
            }
            .map { press -> String in
                guard let key = press.key else {
                    return "noKey"
                }
                return [
                    "code=\(Int(key.keyCode.rawValue))",
                    "charsLen=\(key.characters.count)",
                    "ignoringLen=\(key.charactersIgnoringModifiers.count)",
                    "mods=\(modifierSummary(key.modifierFlags))",
                ].joined(separator: ":")
            }
        return rows.joined(separator: ",")
    }

    static func recordLifecycle(phase: String, contextSummary: String) {
        #if HWC_INTERNAL_BUILD
        let line = consoleLine(
            event: "lifecycle=\(phase)",
            detail: contextSummary
        )
        os_log(
            "%{public}@",
            log: log,
            type: .default,
            line
        )
        NSLog("%@", line)
        persistLine(line)
        #endif
    }

    static func recordPresses(
        callback: String,
        count: Int,
        pressSummary: String,
        contextSummary: String,
        relayEnabled: Bool,
        readerFirstResponder: Bool
    ) {
        #if HWC_INTERNAL_BUILD
        guard relayEnabled else { return }
        let line = consoleLine(
            event: "callback=\(callback) count=\(count) relayEnabled=\(relayEnabled) readerFirstResponder=\(readerFirstResponder)",
            detail: "presses=\(pressSummary) \(contextSummary)"
        )
        os_log(
            "%{public}@",
            log: log,
            type: .default,
            line
        )
        NSLog("%@", line)
        persistLine(line)
        #endif
    }

    static func recordKeyCommands(callback: String, count: Int, contextSummary: String) {
        #if HWC_INTERNAL_BUILD
        let line = consoleLine(
            event: "callback=\(callback) keyCommands=\(count)",
            detail: contextSummary
        )
        os_log(
            "%{public}@",
            log: log,
            type: .default,
            line
        )
        NSLog("%@", line)
        persistLine(line)
        #endif
    }

    static func recordTextContextChange(source: String, beforeSummary: String, afterSummary: String) {
        #if HWC_INTERNAL_BUILD
        let line = consoleLine(
            event: "textContext source=\(source)",
            detail: "before={\(beforeSummary)} after={\(afterSummary)}"
        )
        os_log(
            "%{public}@",
            log: log,
            type: .default,
            line
        )
        NSLog("%@", line)
        persistLine(line)
        #endif
    }

    static func consoleLine(event: String, detail: String) -> String {
        "nativePathProbe \(event) \(detail)"
    }

    static func persistLine(
        _ line: String,
        defaults: UserDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard,
        limit: Int = lineLimit
    ) {
        let trimmedLimit = max(1, limit)
        var lines = recordedLines(defaults: defaults)
        lines.append(line)
        if lines.count > trimmedLimit {
            lines.removeFirst(lines.count - trimmedLimit)
        }
        defaults.set(lines, forKey: defaultsKey)
        defaults.synchronize()
    }

    static func recordedLines(
        defaults: UserDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard
    ) -> [String] {
        defaults.stringArray(forKey: defaultsKey) ?? []
    }

    static func clearRecordedLines(
        defaults: UserDefaults = UserDefaults(suiteName: KeyboardSharedPreferences.appGroupIdentifier) ?? .standard
    ) {
        defaults.removeObject(forKey: defaultsKey)
        defaults.synchronize()
    }

    private static func fingerprint(_ text: String?) -> String {
        guard let text else { return "nil" }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private static func modifierSummary(_ flags: UIKeyModifierFlags) -> String {
        var names = [String]()
        if flags.contains(.alphaShift) { names.append("caps") }
        if flags.contains(.shift) { names.append("shift") }
        if flags.contains(.control) { names.append("control") }
        if flags.contains(.alternate) { names.append("alternate") }
        if flags.contains(.command) { names.append("command") }
        if flags.contains(.numericPad) { names.append("numericPad") }
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }
}

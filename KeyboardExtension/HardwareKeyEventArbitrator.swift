import Foundation

#if HWC_INTERNAL_BUILD
#if HWC_HARDWARE_CAPTURE

/// Arbitrates hardware key events to prevent duplicates, enforce ordering,
/// and emit synthetic key-up events for orphaned down events.
final class HardwareKeyEventArbitrator {
    /// Event counters for diagnostics
    struct Counters: Codable, Equatable {
        var totalCaptured: UInt64 = 0
        var droppedDedup: UInt64 = 0
        var droppedOverflow: UInt64 = 0
        var synthesizedUp: UInt64 = 0
        var modifierMismatch: UInt64 = 0
        var lifecycleViolation: UInt64 = 0
        var orphanedDown: UInt64 = 0
        var orphanedUp: UInt64 = 0
        var crossSourceDivergence: UInt64 = 0
        var firstResponderLoss: UInt64 = 0

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
    }

    /// Source priority for deduplication (higher = preferred)
    enum SourcePriority {
        case pressesBegan
        case pressesChanged
        case pressesEnded
        case keyCommand
        case inferred
        case appDebug

        var rawValue: Int {
            switch self {
            case .pressesBegan:
                return 3
            case .pressesChanged, .pressesEnded:
                return 2
            case .keyCommand:
                return 1
            case .inferred, .appDebug:
                return 0
            }
        }

        static func priority(for source: KeyEventSource) -> SourcePriority {
            switch source {
            case .pressesBegan: return .pressesBegan
            case .pressesChanged: return .pressesChanged
            case .pressesEnded: return .pressesEnded
            case .keyCommand: return .keyCommand
            case .inferred: return .inferred
            case .appDebug: return .appDebug
            }
        }
    }

    /// Fingerprint for deduplication
    private struct EventFingerprint: Hashable {
        let phase: KeyPhase
        let keyCode: Int?
        let modifiers: Set<KeyModifier>
        let characters: String?
        let charactersIgnoringModifiers: String?

        init(_ event: KeyEvent) {
            self.phase = event.phase
            self.keyCode = event.keyCode
            self.modifiers = event.modifiers
            self.characters = event.characters
            self.charactersIgnoringModifiers = event.charactersIgnoringModifiers
        }
    }

    private struct RecentFingerprint {
        let source: KeyEventSource
        let timestamp: Date
    }

    /// Pending down event awaiting key-up
    private struct PendingDownEvent {
        let event: KeyEvent
        let timestamp: Date
    }

    private struct PendingDownAlias {
        let canonicalKey: String
        let timestamp: Date
    }

    private struct RecentSourceEvent {
        let source: KeyEventSource
        let phase: KeyPhase
        let keyCode: Int?
        let characters: String?
        let charactersIgnoringModifiers: String?
        let modifiers: Set<KeyModifier>
        let timestamp: Date

        init(_ event: KeyEvent, timestamp: Date) {
            source = event.source
            phase = event.phase
            keyCode = event.keyCode
            characters = event.characters
            charactersIgnoringModifiers = event.charactersIgnoringModifiers
            modifiers = event.modifiers
            self.timestamp = timestamp
        }

        func matchesLogicalKey(_ event: KeyEvent) -> Bool {
            if let lhs = keyCode, let rhs = event.keyCode {
                return lhs == rhs
            }
            guard
                let lhs = charactersIgnoringModifiers,
                let rhs = event.charactersIgnoringModifiers,
                !lhs.isEmpty,
                !rhs.isEmpty
            else {
                return false
            }
            return lhs == rhs
        }

        func hasModifierDivergence(with event: KeyEvent, at date: Date, within window: TimeInterval) -> Bool {
            source != event.source &&
                phase == event.phase &&
                abs(date.timeIntervalSince(timestamp)) < window &&
                matchesLogicalKey(event) &&
                modifiers != event.modifiers
        }
    }

    private let dedupWindow: TimeInterval
    private let syntheticUpTimeout: TimeInterval = 5.0
    private let pendingAliasLifetime: TimeInterval = 5.0

    private var recentFingerprints: [EventFingerprint: RecentFingerprint] = [:]
    private var recentSourceEvents: [RecentSourceEvent] = []
    private var pendingDownEvents: [String: PendingDownEvent] = [:]
    private var dedupedPendingDownAliases: [String: PendingDownAlias] = [:]
    private var closedPendingDownKeys: [String: Date] = [:]
    private var nextSequence: UInt64 = 1
    private var counters = Counters()

    private let queue = DispatchQueue(label: "dev.moni11811.hwkbcompanion.arbitrator")

    init(dedupWindow: TimeInterval = 0.02) {
        self.dedupWindow = max(0, dedupWindow)
    }

    /// Process an incoming event and return the events to emit (may be empty if deduped)
    func process(_ event: KeyEvent) -> [KeyEvent] {
        return queue.sync {
            counters.totalCaptured += 1

            let fingerprint = EventFingerprint(event)
            let now = Date()
            let eventTimestamp = event.timestamp

            // Prune old fingerprints
            pruneFingerprints(before: eventTimestamp)

            // Check for duplicate within dedup window
            if let previous = recentFingerprints[fingerprint],
               abs(eventTimestamp.timeIntervalSince(previous.timestamp)) < dedupWindow,
               shouldDropDuplicate(event, after: previous.source) {
                if event.phase == .down, !event.isRepeat {
                    let aliasKey = downEventKey(for: event)
                    dedupedPendingDownAliases[aliasKey] = PendingDownAlias(
                        canonicalKey: matchingPendingDownKey(for: event) ?? aliasKey,
                        timestamp: eventTimestamp
                    )
                } else if event.phase == .up {
                    _ = closePendingDownLifecycle(for: event)
                }
                counters.droppedDedup += 1
                return []
            }

            if recentSourceEvents.contains(where: { $0.hasModifierDivergence(with: event, at: eventTimestamp, within: dedupWindow) }) {
                recordReliabilityIssueLocked(.crossSourceDivergence)
            }

            if event.phase == .down,
               !event.isRepeat,
               isAdvisoryPrintableKeyCommand(event),
               let ownerKey = rawPressOwnerKey(for: event, at: eventTimestamp) {
                let aliasKey = downEventKey(for: event)
                dedupedPendingDownAliases[aliasKey] = PendingDownAlias(canonicalKey: ownerKey, timestamp: eventTimestamp)
                counters.droppedDedup += 1
                return []
            }

            if event.phase == .down,
               !event.isRepeat,
               isAdvisoryPrintableRawPress(event),
               let ownerKey = keyCommandOwnerKey(for: event, at: eventTimestamp) {
                let aliasKey = downEventKey(for: event)
                dedupedPendingDownAliases[aliasKey] = PendingDownAlias(canonicalKey: ownerKey, timestamp: eventTimestamp)
                counters.droppedDedup += 1
                return []
            }

            // Record fingerprint
            recentFingerprints[fingerprint] = RecentFingerprint(
                source: event.source,
                timestamp: eventTimestamp
            )
            recentSourceEvents.append(RecentSourceEvent(event, timestamp: eventTimestamp))

            // Track pending down events for synthetic up emission
            if event.phase == .down, !event.isRepeat {
                let key = downEventKey(for: event)
                pendingDownEvents[key] = PendingDownEvent(event: event, timestamp: now)
                closedPendingDownKeys.removeValue(forKey: key)
            } else if event.phase == .up {
                if !closePendingDownLifecycle(for: event) {
                    recordReliabilityIssueLocked(.orphanedUp)
                    recordInvariantViolationLocked(
                        .lifecycleViolation,
                        message: "M15.R5 I2 lifecycle invariant failed: up without prior down"
                    )
                }
            }

            // Assign sequence number
            var sequencedEvent = event
            sequencedEvent = KeyEvent(
                id: event.id,
                timestamp: event.timestamp,
                source: event.source,
                phase: event.phase,
                characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                modifiers: event.modifiers,
                isRepeat: event.isRepeat,
                sequence: nextSequence,
                isSynthetic: event.isSynthetic
            )
            nextSequence += 1

            return [sequencedEvent]
        }
    }

    /// Emit synthetic key-up events for all pending down events
    func emitSyntheticUpEvents() -> [KeyEvent] {
        return queue.sync {
            var syntheticEvents: [KeyEvent] = []

            for (_, pending) in pendingDownEvents {
                let syntheticUp = KeyEvent(
                    id: UUID(),
                    timestamp: Date(),
                    source: pending.event.source,
                    phase: .up,
                    characters: pending.event.characters,
                    charactersIgnoringModifiers: pending.event.charactersIgnoringModifiers,
                    keyCode: pending.event.keyCode,
                    modifiers: pending.event.modifiers,
                    isRepeat: false,
                    sequence: nextSequence,
                    isSynthetic: true
                )
                nextSequence += 1
                syntheticEvents.append(syntheticUp)
                counters.synthesizedUp += 1
                recordReliabilityIssueLocked(.orphanedDown)
                recordInvariantViolationLocked(
                    .lifecycleViolation,
                    message: "M15.R5 I2 lifecycle invariant failed: down expired without up"
                )
            }

            pendingDownEvents.removeAll()
            return syntheticEvents
        }
    }

    /// Clear all pending state
    func clear() {
        queue.sync {
            recentFingerprints.removeAll()
            recentSourceEvents.removeAll()
            pendingDownEvents.removeAll()
            dedupedPendingDownAliases.removeAll()
            closedPendingDownKeys.removeAll()
        }
    }

    /// Get current counters
    func getCounters() -> Counters {
        return queue.sync {
            counters
        }
    }

    /// Reset counters
    func resetCounters() {
        queue.sync {
            counters = Counters()
        }
    }

    /// Record an overflow event
    func recordOverflow(count: UInt64) {
        queue.sync {
            counters.droppedOverflow += count
        }
    }

    func recordReliabilityIssue(_ counter: HardwareReliabilityCounter) {
        queue.sync {
            recordReliabilityIssueLocked(counter)
        }
    }

    private func recordReliabilityIssueLocked(_ counter: HardwareReliabilityCounter) {
        counters.increment(counter)
        KeyDiagStore.incrementReliabilityCounter(counter)
        HWKTelemetry.recordHardwareReliabilityCounter(counter, total: KeyDiagStore.getCounters().value(for: counter))
    }

    private func recordInvariantViolationLocked(_ counter: HardwareReliabilityCounter, message _: @autoclosure () -> String) {
        recordReliabilityIssueLocked(counter)
    }

    private func pruneFingerprints(before date: Date) {
        let cutoff = date.addingTimeInterval(-dedupWindow * 2)
        let aliasCutoff = date.addingTimeInterval(-pendingAliasLifetime)
        recentFingerprints = recentFingerprints.filter { $0.value.timestamp > cutoff }
        recentSourceEvents = recentSourceEvents.filter { $0.timestamp > cutoff }
        dedupedPendingDownAliases = dedupedPendingDownAliases.filter { $0.value.timestamp > aliasCutoff }
        closedPendingDownKeys = closedPendingDownKeys.filter { $0.value > cutoff }
    }

    private func shouldDropDuplicate(_ event: KeyEvent, after previousSource: KeyEventSource) -> Bool {
        if event.source == .inferred {
            return previousSource != .inferred
        }

        if previousSource == .inferred {
            return false
        }

        return true
    }

    private func downEventKey(for event: KeyEvent) -> String {
        let keyParts = [
            lifecycleSourceKey(for: event.source),
            event.keyCode.map { String($0) } ?? "",
            event.charactersIgnoringModifiers ?? ""
        ]
        return keyParts.joined(separator: "|")
    }

    private func matchingPendingDownKey(for event: KeyEvent) -> String? {
        let logicalKey = logicalDownEventKey(for: event)
        return pendingDownEvents.keys.first { key in
            logicalDownEventKey(fromDownEventKey: key) == logicalKey
        }
    }

    private func closePendingDownLifecycle(for event: KeyEvent) -> Bool {
        let key = downEventKey(for: event)
        let eventTimestamp = event.timestamp

        if pendingDownEvents.removeValue(forKey: key) != nil {
            closedPendingDownKeys[key] = eventTimestamp
            return true
        }

        if let alias = dedupedPendingDownAliases.removeValue(forKey: key) {
            guard abs(eventTimestamp.timeIntervalSince(alias.timestamp)) < pendingAliasLifetime else {
                return false
            }
            _ = pendingDownEvents.removeValue(forKey: alias.canonicalKey)
            closedPendingDownKeys[alias.canonicalKey] = eventTimestamp
            return true
        }

        if let closedTimestamp = closedPendingDownKeys[key],
           abs(eventTimestamp.timeIntervalSince(closedTimestamp)) < dedupWindow {
            return true
        }

        return false
    }

    private func logicalDownEventKey(for event: KeyEvent) -> String {
        let keyParts = [
            event.keyCode.map { String($0) } ?? "",
            event.charactersIgnoringModifiers ?? ""
        ]
        return keyParts.joined(separator: "|")
    }

    private func logicalDownEventKey(fromDownEventKey key: String) -> String {
        key.split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .joined(separator: "|")
    }

    private func rawPressOwnerKey(for event: KeyEvent, at date: Date) -> String? {
        guard SourcePriority.priority(for: event.source) == .keyCommand else {
            return nil
        }

        return recentSourceEvents.first { recent in
            isRawPressSource(recent.source) &&
                recent.phase == .down &&
                isPrintableMutationCandidate(recent) &&
                abs(date.timeIntervalSince(recent.timestamp)) < dedupWindow &&
                recent.matchesLogicalKey(event)
        }.flatMap { recent in
            matchingPendingDownKey(
                for: KeyEvent(
                    timestamp: recent.timestamp,
                    source: recent.source,
                    phase: recent.phase,
                    charactersIgnoringModifiers: recent.charactersIgnoringModifiers,
                    keyCode: recent.keyCode,
                    modifiers: recent.modifiers
                )
            )
        }
    }

    private func keyCommandOwnerKey(for event: KeyEvent, at date: Date) -> String? {
        guard isRawPressSource(event.source) else {
            return nil
        }

        return recentSourceEvents.first { recent in
            SourcePriority.priority(for: recent.source) == .keyCommand &&
                recent.phase == .down &&
                isPrintableMutationCandidate(recent) &&
                abs(date.timeIntervalSince(recent.timestamp)) < dedupWindow &&
                recent.matchesLogicalKey(event)
        }.flatMap { recent in
            matchingPendingDownKey(
                for: KeyEvent(
                    timestamp: recent.timestamp,
                    source: recent.source,
                    phase: recent.phase,
                    charactersIgnoringModifiers: recent.charactersIgnoringModifiers,
                    keyCode: recent.keyCode,
                    modifiers: recent.modifiers
                )
            )
        }
    }

    private func isAdvisoryPrintableKeyCommand(_ event: KeyEvent) -> Bool {
        SourcePriority.priority(for: event.source) == .keyCommand &&
            isPrintableMutationCandidate(event)
    }

    private func isAdvisoryPrintableRawPress(_ event: KeyEvent) -> Bool {
        isRawPressSource(event.source) &&
            isPrintableMutationCandidate(event)
    }

    private func isPrintableMutationCandidate(_ event: KeyEvent) -> Bool {
        guard event.modifiers.isDisjoint(with: [.command, .control]),
              let characters = event.characters,
              !characters.isEmpty else {
            return false
        }
        return characters.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7f
        }
    }

    private func isPrintableMutationCandidate(_ event: RecentSourceEvent) -> Bool {
        guard event.modifiers.isDisjoint(with: [.command, .control]),
              let characters = event.characters,
              !characters.isEmpty else {
            return false
        }
        return characters.unicodeScalars.allSatisfy { scalar in
            scalar.value >= 0x20 && scalar.value != 0x7f
        }
    }

    private func isRawPressSource(_ source: KeyEventSource) -> Bool {
        switch source {
        case .pressesBegan, .pressesChanged:
            return true
        default:
            return false
        }
    }

    private func lifecycleSourceKey(for source: KeyEventSource) -> String {
        switch source {
        case .pressesBegan, .pressesChanged, .pressesEnded:
            return "presses"
        default:
            return source.rawValue
        }
    }
}

#endif
#endif

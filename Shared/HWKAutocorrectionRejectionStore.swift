import CryptoKit
import Foundation

struct HWKAutocorrectionRejectionStore {
    static let maximumEntries = 128
    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60

    private static let storageKey = "keyboard.autocorrection.rejectionFingerprints.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    func record(original: String, replacement: String, at date: Date = Date()) {
        record(
            fingerprint: Self.fingerprint(original: original, replacement: replacement),
            at: date
        )
    }

    func record(fingerprint: String, at date: Date = Date()) {
        guard Self.isValidFingerprint(fingerprint) else { return }
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.rejections]
        ) {
            var records = load().filter { $0.fingerprint != fingerprint }
            records.append(Record(fingerprint: fingerprint, rejectedAt: date.timeIntervalSince1970))
            save(pruned(records, now: date))
        }
    }

    func contains(
        original: String,
        replacement: String,
        now: Date = Date()
    ) -> Bool {
        activeFingerprints(now: now).contains(
            Self.fingerprint(original: original, replacement: replacement)
        )
    }

    func activeFingerprints(now: Date = Date()) -> Set<String> {
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.rejections]
        ) {
            let active = pruned(load(), now: now)
            save(active)
            return Set(active.map(\.fingerprint))
        }
        return result.value ?? Set(pruned(load(), now: now).map(\.fingerprint))
    }

    /// Read-only extension refresh. Call from
    /// `KeyboardLearningWriteCoordinator.withOrderedPersistenceRead`; durable pruning
    /// remains owned by mutation paths.
    func activeFingerprintsSnapshot(now: Date = Date()) -> Set<String> {
        Set(pruned(load(), now: now).map(\.fingerprint))
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.rejections]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    static func fingerprint(original: String, replacement: String) -> String {
        let normalized = original.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            + "\u{001F}"
            + replacement.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return SHA256.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard let records = try? JSONDecoder().decode([Record].self, from: data),
              records.count <= Self.maximumEntries,
              Set(records.map(\.fingerprint)).count == records.count else {
            return false
        }
        return records.allSatisfy { record in
            Self.isValidFingerprint(record.fingerprint)
                && record.rejectedAt.isFinite
                && record.rejectedAt >= 0
        }
    }

    private static func isValidFingerprint(_ fingerprint: String) -> Bool {
        fingerprint.count == 64 && fingerprint.allSatisfy { $0.isHexDigit }
    }

    private func load() -> [Record] {
        guard let data = defaults.data(forKey: Self.storageKey),
              Self.isValidPersistedData(data),
              let records = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        return records
    }

    private func save(_ records: [Record]) {
        guard !records.isEmpty else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func pruned(_ records: [Record], now: Date) -> [Record] {
        let current = now.timeIntervalSince1970
        return records
            .filter { record in
                record.rejectedAt <= current + 300
                    && current - record.rejectedAt <= Self.retentionInterval
            }
            .sorted { $0.rejectedAt > $1.rejectedAt }
            .prefix(Self.maximumEntries)
            .map { $0 }
    }

    private struct Record: Codable, Sendable {
        let fingerprint: String
        let rejectedAt: TimeInterval
    }
}

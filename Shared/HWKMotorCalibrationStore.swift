import Foundation

enum HWKMotorInputModality: String, Codable {
    case touch
    case hardware
}

struct HWKMotorCalibrationContext: Hashable, Codable {
    let deviceClass: String
    let layoutID: String
    let modality: HWKMotorInputModality
}

struct HWKMotorTouchOffset: Equatable, Codable {
    let dx: Double
    let dy: Double
}

struct HWKMotorCalibrationStore {
    static let storageKey = "keyboard.motorCalibration.v1"
    static let maximumStorageBytes = 16 * 1024

    private struct Payload: Codable {
        var contexts: [String: ContextPayload]
        var order: [String]
    }

    private struct ContextPayload: Codable {
        var offsets: [String: HWKMotorTouchOffset]
    }

    private let defaults: UserDefaults
    private var payload: Payload
    private var hasPendingChanges = false

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           Self.isValidPersistedData(data),
           let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
            payload = decoded
        } else {
            payload = Payload(contexts: [:], order: [])
        }
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumStorageBytes,
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.contexts.count <= 12,
              payload.order.count <= 12,
              Set(payload.order).count == payload.order.count,
              Set(payload.order) == Set(payload.contexts.keys) else {
            return false
        }
        return payload.contexts.allSatisfy { contextKey, context in
            !contextKey.isEmpty
                && contextKey.count <= 256
                && context.offsets.count <= 128
                && context.offsets.allSatisfy { label, offset in
                    label.count == 1
                        && offset.dx.isFinite
                        && offset.dy.isFinite
                        && (-16...16).contains(offset.dx)
                        && (-16...16).contains(offset.dy)
                }
        }
    }

    mutating func recordTouch(
        label: String,
        dx: Double,
        dy: Double,
        context: HWKMotorCalibrationContext,
        persistImmediately: Bool = true
    ) {
        let normalized = label.lowercased()
        guard normalized.count == 1, dx.isFinite, dy.isFinite else { return }
        let contextKey = Self.contextKey(context)
        var contextPayload = payload.contexts[contextKey] ?? ContextPayload(offsets: [:])
        let clamped = HWKMotorTouchOffset(
            dx: min(16, max(-16, dx)),
            dy: min(16, max(-16, dy))
        )
        if let current = contextPayload.offsets[normalized] {
            contextPayload.offsets[normalized] = HWKMotorTouchOffset(
                dx: (current.dx * 0.68) + (clamped.dx * 0.32),
                dy: (current.dy * 0.68) + (clamped.dy * 0.32)
            )
        } else {
            contextPayload.offsets[normalized] = clamped
        }
        payload.contexts[contextKey] = contextPayload
        payload.order.removeAll { $0 == contextKey }
        payload.order.append(contextKey)
        hasPendingChanges = true
        if persistImmediately {
            flushPendingChanges()
        }
    }

    mutating func flushPendingChanges() {
        guard let data = takePendingPersistenceData() else { return }
        Self.persist(data, defaults: defaults)
    }

    mutating func takePendingPersistenceData() -> Data? {
        guard hasPendingChanges else { return nil }
        trimToStorageLimit()
        guard let data = try? JSONEncoder().encode(payload),
              Self.isValidPersistedData(data) else {
            return nil
        }
        hasPendingChanges = false
        return data
    }

    static func persist(
        _ data: Data,
        defaults: UserDefaults = KeyboardSharedPreferences.defaults
    ) {
        guard isValidPersistedData(data) else { return }
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.motorCalibration]
        ) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func touchOffset(for label: String, context: HWKMotorCalibrationContext) -> HWKMotorTouchOffset? {
        payload.contexts[Self.contextKey(context)]?.offsets[label.lowercased()]
    }

    func touchOffsets(context: HWKMotorCalibrationContext) -> [String: HWKMotorTouchOffset] {
        payload.contexts[Self.contextKey(context)]?.offsets ?? [:]
    }

    mutating func clear() {
        payload = Payload(contexts: [:], order: [])
        hasPendingChanges = false
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.motorCalibration]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    private mutating func trimToStorageLimit() {
        while payload.order.count > 12, let oldest = payload.order.first {
            payload.order.removeFirst()
            payload.contexts.removeValue(forKey: oldest)
        }
        while let data = try? JSONEncoder().encode(payload), data.count > Self.maximumStorageBytes,
              let oldest = payload.order.first {
            payload.order.removeFirst()
            payload.contexts.removeValue(forKey: oldest)
        }
    }

    private static func contextKey(_ context: HWKMotorCalibrationContext) -> String {
        "\(context.deviceClass)|\(context.layoutID)|\(context.modality.rawValue)"
    }
}

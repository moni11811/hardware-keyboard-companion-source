import Foundation

struct HWKAutocorrectionPersonalizationStore {
    static let maximumEncodedBytes = 16 * 1_024

    private static let storageKey = "keyboard.autocorrection.personalization.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    func load() -> HWKFTRLPersonalizer {
        guard let data = defaults.data(forKey: Self.storageKey),
              Self.isValidPersistedData(data),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else {
            return .standard
        }
        return envelope.model
    }

    static func isValidPersistedData(_ data: Data) -> Bool {
        guard !data.isEmpty,
              data.count <= Self.maximumEncodedBytes,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1 else {
            return false
        }
        return envelope.model.isValid
    }

    @discardableResult
    func observe(
        context: HWKPersonalizationContext,
        accepted: Bool
    ) -> HWKFTRLPersonalizer {
        let result = HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.personalization]
        ) {
            var model = load()
            model.observe(context: context, accepted: accepted)
            persist(model)
            return model
        }
        return result.value ?? load()
    }

    func clear() {
        HWKAutobotLearnerManifestStore(defaults: defaults).performMutation(
            storeIDs: [.personalization]
        ) {
            defaults.removeObject(forKey: Self.storageKey)
        }
    }

    var encodedByteCount: Int {
        defaults.data(forKey: Self.storageKey)?.count ?? 0
    }

    func replacePersistedDataForTesting(_ data: Data) {
        defaults.set(data, forKey: Self.storageKey)
    }

    private func persist(_ model: HWKFTRLPersonalizer) {
        guard let data = try? JSONEncoder().encode(Envelope(version: 1, model: model)),
              data.count <= Self.maximumEncodedBytes else {
            return
        }
        defaults.set(data, forKey: Self.storageKey)
    }

    private struct Envelope: Codable {
        let version: Int
        let model: HWKFTRLPersonalizer
    }
}

import Foundation
import Security

enum HWCCloudSnapshotKeychainError: Error, Equatable {
    case status(OSStatus)
    case invalidResult
    case conflictingKey(String)
}
/// One immutable synchronizable Keychain item per snapshot key. Rotation adds a
/// new item; historical items are never updated or deleted automatically.
final class HWCCloudSnapshotSynchronizableKeychainMaterialStore: HWCCloudSnapshotKeyMaterialStoring {
    private static let service = "dev.moni11811.hwc.cloud-snapshot.keys.v1"
    private static let accountPrefix = "snapshot-key-v1."

    private let accessGroup: String?

    init(
        accessGroup: String? = Bundle.main.object(
            forInfoDictionaryKey: "HWCKeychainAccessGroup"
        ) as? String
    ) {
        self.accessGroup = accessGroup?.isEmpty == false ? accessGroup : nil
    }

    func loadAll() throws -> [HWCCloudSnapshotKeyMaterial] {
        var query = baseQuery()
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else {
            throw HWCCloudSnapshotKeychainError.status(status)
        }
        let dictionaries: [[String: Any]]
        if let values = result as? [[String: Any]] {
            dictionaries = values
        } else if let value = result as? [String: Any] {
            dictionaries = [value]
        } else {
            throw HWCCloudSnapshotKeychainError.invalidResult
        }

        return try dictionaries.map { dictionary in
            guard let account = dictionary[kSecAttrAccount as String] as? String,
                  account.hasPrefix(Self.accountPrefix),
                  let data = dictionary[kSecValueData as String] as? Data,
                  let material = try? JSONDecoder().decode(
                      HWCCloudSnapshotKeyMaterial.self,
                      from: data
                  ),
                  account == Self.accountPrefix + material.keyID else {
                throw HWCCloudSnapshotKeychainError.invalidResult
            }
            _ = try material.validatedKey()
            return material
        }
        .sorted {
            if $0.createdAtMilliseconds != $1.createdAtMilliseconds {
                return $0.createdAtMilliseconds < $1.createdAtMilliseconds
            }
            return $0.keyID < $1.keyID
        }
    }

    func save(_ material: HWCCloudSnapshotKeyMaterial) throws {
        _ = try material.validatedKey()
        if let existing = try loadAll().first(where: {
            $0.keyID == material.keyID
        }) {
            guard existing == material else {
                throw HWCCloudSnapshotKeychainError.conflictingKey(material.keyID)
            }
            return
        }

        var attributes = baseQuery()
        attributes[kSecAttrAccount as String] = Self.accountPrefix + material.keyID
        attributes[kSecAttrSynchronizable as String] = true
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        attributes[kSecValueData as String] = try JSONEncoder().encode(material)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem,
           let existing = try loadAll().first(where: {
               $0.keyID == material.keyID
           }), existing == material {
            return
        }
        guard status == errSecSuccess else {
            throw HWCCloudSnapshotKeychainError.status(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

final class HWCCloudSnapshotUserDefaultsCurrentKeyStore: HWCCloudSnapshotCurrentKeyStoring {
    private static let storageKey = "cloudSnapshot.currentKeyID.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = KeyboardSharedPreferences.defaults) {
        self.defaults = defaults
    }

    var currentKeyID: String? {
        get { defaults.string(forKey: Self.storageKey) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: Self.storageKey)
            } else {
                defaults.removeObject(forKey: Self.storageKey)
            }
            defaults.synchronize()
        }
    }
}

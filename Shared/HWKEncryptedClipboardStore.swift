import CryptoKit
import Foundation
import Security

struct HWKClipboardSnippet: Codable, Equatable, Identifiable {
    let id: UUID
    var label: String
    var text: String
    var updatedAt: Date
}

struct HWKEncryptedClipboardRecord: Codable, Equatable {
    let id: UUID
    let label: String
    let sealedData: Data
    let updatedAt: Date
}

private struct HWKEncryptedClipboardPayload: Codable, Equatable {
    let label: String
    let text: String
}

enum HWKEncryptedClipboardStoreError: Error, Equatable {
    case invalidKey
    case encryptionFailed
    case invalidPayload
    case keyUnavailable
    case keyStorageFailed
}

struct HWKEncryptedClipboardStore {
    struct KeyStorage {
        let load: () -> Data?
        let persist: (Data) -> Bool
    }

    static let snippetRecordsDefaultsKey = "keyboard.encryptedClipboard.snippetRecords"
    private static let snippetRecordLimit = 64
    private static let snippetKeyDefaultsKey = "keyboard.encryptedClipboard.key"
    private static let keyDirectoryName = "HWKEncryptedClipboardStore"
    private static let keyFileName = "clipboard.key"
    private static let keychainService = "dev.moni11811.hwc.encrypted-clipboard"
    private static let keychainAccount = "snippet-aes-key-v1"
    private static let keychainAccessGroupInfoKey = "HWCKeychainAccessGroup"
    private let key: SymmetricKey

    init(keyData: Data) throws {
        guard keyData.count >= 32 else { throw HWKEncryptedClipboardStoreError.invalidKey }
        self.key = SymmetricKey(data: keyData.prefix(32))
    }

    func encrypt(_ snippet: HWKClipboardSnippet) throws -> HWKEncryptedClipboardRecord {
        let payload = HWKEncryptedClipboardPayload(label: snippet.label, text: snippet.text)
        guard let payloadData = try? JSONEncoder().encode(payload) else {
            throw HWKEncryptedClipboardStoreError.encryptionFailed
        }
        let sealed = try AES.GCM.seal(payloadData, using: key)
        guard let combined = sealed.combined else {
            throw HWKEncryptedClipboardStoreError.encryptionFailed
        }
        return HWKEncryptedClipboardRecord(
            id: snippet.id,
            label: Self.redactedLabel,
            sealedData: combined,
            updatedAt: snippet.updatedAt
        )
    }

    func decrypt(_ record: HWKEncryptedClipboardRecord) throws -> HWKClipboardSnippet {
        let sealed = try AES.GCM.SealedBox(combined: record.sealedData)
        let data = try AES.GCM.open(sealed, using: key)
        if let payload = try? JSONDecoder().decode(HWKEncryptedClipboardPayload.self, from: data) {
            return HWKClipboardSnippet(
                id: record.id,
                label: payload.label,
                text: payload.text,
                updatedAt: record.updatedAt
            )
        }
        guard record.label != Self.redactedLabel else {
            throw HWKEncryptedClipboardStoreError.invalidPayload
        }

        return HWKClipboardSnippet(
            id: record.id,
            label: record.label,
            text: String(decoding: data, as: UTF8.self),
            updatedAt: record.updatedAt
        )
    }

    func deleteAll(_ records: inout [HWKEncryptedClipboardRecord]) {
        records.removeAll()
    }

    static func loadSnippets(from defaults: UserDefaults) -> [HWKClipboardSnippet] {
        loadSnippets(from: defaults, keyStorage: productionKeyStorage)
    }

    static func loadSnippets(
        from defaults: UserDefaults,
        keyStorage: KeyStorage
    ) -> [HWKClipboardSnippet] {
        (try? snapshotExportSnippets(
            from: defaults,
            existingKeyData: { existingEncryptionKeyData(from: defaults, keyStorage: keyStorage) }
        )) ?? []
    }

    /// Exports every encrypted snippet or fails closed. Existing ciphertext is
    /// never interpreted as an empty clipboard merely because its device key is
    /// temporarily unavailable.
    static func snapshotExportSnippets(
        from defaults: UserDefaults
    ) throws -> [HWKClipboardSnippet] {
        try snapshotExportSnippets(
            from: defaults,
            existingKeyData: {
                existingEncryptionKeyData(
                    from: defaults,
                    keyStorage: productionKeyStorage
                )
            }
        )
    }

    static func snapshotExportSnippets(
        from defaults: UserDefaults,
        existingKeyData: () -> Data?
    ) throws -> [HWKClipboardSnippet] {
        let records = snippetRecords(from: defaults)
        guard !records.isEmpty else { return [] }
        guard let keyData = existingKeyData() else {
            throw HWKEncryptedClipboardStoreError.keyUnavailable
        }
        let store = try HWKEncryptedClipboardStore(keyData: keyData)
        do {
            return try records.map(store.decrypt)
        } catch {
            throw HWKEncryptedClipboardStoreError.invalidPayload
        }
    }

    static func snippetRecords(from defaults: UserDefaults) -> [HWKEncryptedClipboardRecord] {
        guard let data = defaults.data(forKey: snippetRecordsDefaultsKey) else {
            return []
        }
        guard let records = try? JSONDecoder().decode([HWKEncryptedClipboardRecord].self, from: data) else {
            return []
        }
        let repairedRecords = recordsByApplyingLimit(records)
        if repairedRecords.count != records.count {
            persist(repairedRecords, to: defaults)
        }
        return repairedRecords
    }

    static func snippetCount(from defaults: UserDefaults) -> Int {
        snippetRecords(from: defaults).count
    }

    static func appendSnippet(_ snippet: HWKClipboardSnippet, to defaults: UserDefaults) throws {
        try appendSnippet(snippet, to: defaults, keyStorage: productionKeyStorage)
    }

    static func appendSnippet(
        _ snippet: HWKClipboardSnippet,
        to defaults: UserDefaults,
        keyStorage: KeyStorage
    ) throws {
        guard let keyData = encryptionKeyData(from: defaults, keyStorage: keyStorage) else {
            throw HWKEncryptedClipboardStoreError.keyStorageFailed
        }
        let store = try HWKEncryptedClipboardStore(keyData: keyData)
        let encoded = try store.encrypt(snippet)
        var records = snippetRecords(from: defaults)
        records.removeAll { $0.id == encoded.id }
        records.append(encoded)
        persist(recordsByApplyingLimit(records), to: defaults)
    }

    static func encodedRecordsForSnapshotRestore(
        _ snippets: [HWKClipboardSnippet],
        defaults: UserDefaults
    ) throws -> Data {
        let validated = try validatedPortableSnippets(snippets)
        guard let keyData = encryptionKeyData(from: defaults, keyStorage: productionKeyStorage) else {
            throw HWKEncryptedClipboardStoreError.keyStorageFailed
        }
        let store = try HWKEncryptedClipboardStore(keyData: keyData)
        let records = try validated.map(store.encrypt)
        guard let data = try? JSONEncoder().encode(records) else {
            throw HWKEncryptedClipboardStoreError.encryptionFailed
        }
        return data
    }

    static func validatedPortableSnippets(
        _ snippets: [HWKClipboardSnippet]
    ) throws -> [HWKClipboardSnippet] {
        guard snippets.count <= snippetRecordLimit,
              Set(snippets.map(\.id)).count == snippets.count,
              snippets.allSatisfy({ snippet in
                  !snippet.text.isEmpty &&
                      snippet.text.count <= 500 &&
                      snippet.label.count <= 128 &&
                      snippet.updatedAt.timeIntervalSince1970.isFinite
              }) else {
            throw HWKEncryptedClipboardStoreError.invalidPayload
        }
        return snippets.sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt < rhs.updatedAt
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    static func makeSnippet(
        _ text: String,
        id: UUID = UUID(),
        now: Date = Date()
    ) -> HWKClipboardSnippet? {
        let trimmedText = normalizedClipboardText(text)
        guard !trimmedText.isEmpty else { return nil }

        return HWKClipboardSnippet(
            id: id,
            label: clipboardSnippetLabel(from: trimmedText),
            text: trimmedText,
            updatedAt: now
        )
    }

    static func deleteSnippet(id: UUID, in defaults: UserDefaults) throws {
        var records = snippetRecords(from: defaults)
        records.removeAll { $0.id == id }
        persist(records, to: defaults)
    }

    static func autoCaptureSnippet(
        _ text: String,
        to defaults: UserDefaults,
        now: Date = Date()
    ) throws {
        guard let snippet = makeSnippet(text, now: now) else { return }
        let trimmedText = snippet.text
        guard !loadSnippets(from: defaults).contains(where: { $0.text == trimmedText }) else { return }

        try appendSnippet(snippet, to: defaults)
    }

    static func deleteAllSnippets(in defaults: UserDefaults) {
        defaults.removeObject(forKey: snippetRecordsDefaultsKey)
    }

    private static func recordsByApplyingLimit(
        _ records: [HWKEncryptedClipboardRecord]
    ) -> [HWKEncryptedClipboardRecord] {
        guard records.count > snippetRecordLimit else { return records }

        let keptIDs = Set(records
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .prefix(snippetRecordLimit)
            .map(\.id))

        return records.filter { keptIDs.contains($0.id) }
    }

    private static func persist(
        _ records: [HWKEncryptedClipboardRecord],
        to defaults: UserDefaults
    ) {
        guard let encodedData = try? JSONEncoder().encode(records) else { return }
        defaults.set(encodedData, forKey: snippetRecordsDefaultsKey)
    }

    private static func normalizedClipboardText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
    }

    private static func clipboardSnippetLabel(from text: String) -> String {
        let firstLine = text.components(separatedBy: .newlines).first ?? text
        let label = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLabel = String(label.prefix(38))
        return trimmedLabel.isEmpty ? "Clipboard snippet" : trimmedLabel
    }

    private static func encryptionKeyData(
        from defaults: UserDefaults,
        keyStorage: KeyStorage
    ) -> Data? {
        if let existing = existingEncryptionKeyData(from: defaults, keyStorage: keyStorage) {
            return existing
        }
        // Never generate a replacement key over ciphertext that may become
        // readable again after Keychain unlock or migration recovery.
        guard snippetRecords(from: defaults).isEmpty else { return nil }
        return makeAndPersistEncryptionKey(using: keyStorage)
    }

    private static func existingEncryptionKeyData(
        from defaults: UserDefaults,
        keyStorage: KeyStorage
    ) -> Data? {
        if let storedKeyData = keyStorage.load() {
            defaults.removeObject(forKey: snippetKeyDefaultsKey)
            removeLegacyEncryptionKeyFiles()
            return storedKeyData
        }
        if let existing = defaults.string(forKey: snippetKeyDefaultsKey),
           let keyData = Data(base64Encoded: existing),
           keyData.count >= 32 {
            if keyStorage.persist(keyData) {
                defaults.removeObject(forKey: snippetKeyDefaultsKey)
                removeLegacyEncryptionKeyFiles()
                return keyData
            }
            return nil
        }
        if defaults.object(forKey: snippetKeyDefaultsKey) != nil {
            defaults.removeObject(forKey: snippetKeyDefaultsKey)
        }
        for keyURL in encryptionKeyFileURLs() {
            guard let keyData = try? Data(contentsOf: keyURL), keyData.count >= 32 else { continue }
            guard keyStorage.persist(keyData) else { return nil }
            removeLegacyEncryptionKeyFiles()
            return keyData
        }
        return nil
    }

    private static func makeAndPersistEncryptionKey(using keyStorage: KeyStorage) -> Data? {
        let keyData = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        guard keyData.count >= 32 else { return nil }
        return keyStorage.persist(keyData) ? keyData : nil
    }

    private static let productionKeyStorage = KeyStorage(
        load: { storedEncryptionKeyData() },
        persist: { persistEncryptionKeyData($0) }
    )

    private static func storedEncryptionKeyData() -> Data? {
        var query = keychainBaseQuery()
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let keyData = item as? Data,
              keyData.count >= 32 else {
            return nil
        }
        return keyData
    }

    private static func persistEncryptionKeyData(_ keyData: Data) -> Bool {
        guard keyData.count >= 32 else { return false }
        let query = keychainBaseQuery()
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData: keyData] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }
        var newItem = query
        newItem[kSecValueData] = keyData
        newItem[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    private static func keychainBaseQuery() -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        if let accessGroup = Bundle.main.object(forInfoDictionaryKey: keychainAccessGroupInfoKey) as? String,
           !accessGroup.isEmpty,
           !accessGroup.contains("$(") {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    private static func encryptionKeyFileURLs() -> [URL] {
        var directoryURLs: [URL] = []
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardSharedPreferences.appGroupIdentifier
        ) {
            directoryURLs.append(
                groupURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
            )
        }
        if let appSupportURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            directoryURLs.append(appSupportURL)
        }
        directoryURLs.append(FileManager.default.temporaryDirectory)

        var seen = Set<String>()
        return directoryURLs.compactMap { directoryURL in
            let keyURL = directoryURL
                .appendingPathComponent(keyDirectoryName, isDirectory: true)
                .appendingPathComponent(keyFileName, isDirectory: false)
            guard seen.insert(keyURL.standardizedFileURL.path).inserted else { return nil }
            return keyURL
        }
    }

    private static func removeLegacyEncryptionKeyFiles() {
        for keyURL in encryptionKeyFileURLs() {
            try? FileManager.default.removeItem(at: keyURL)
        }
    }

    private static let redactedLabel = "Encrypted snippet"
}

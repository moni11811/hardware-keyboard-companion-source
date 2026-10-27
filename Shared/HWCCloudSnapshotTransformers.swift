import Foundation

struct HWCEncryptedClipboardSnapshotTransformer: HWCCloudSnapshotStoreTransformer {
    private static let sourceKey = "keyboard.encryptedClipboard.snippetRecords"
    private static let snapshotKey = "clipboard.plaintext.v1"

    private let exportSnippets: () throws -> [HWKClipboardSnippet]
    private let encodeRestoredSnippets: ([HWKClipboardSnippet]) throws -> Data

    init(
        exportSnippets: @escaping () throws -> [HWKClipboardSnippet],
        encodeRestoredSnippets: @escaping ([HWKClipboardSnippet]) throws -> Data
    ) {
        self.exportSnippets = exportSnippets
        self.encodeRestoredSnippets = encodeRestoredSnippets
    }

    init(defaults: UserDefaults) {
        exportSnippets = {
            try HWKEncryptedClipboardStore.snapshotExportSnippets(from: defaults)
        }
        encodeRestoredSnippets = { snippets in
            try HWKEncryptedClipboardStore.encodedRecordsForSnapshotRestore(
                snippets,
                defaults: defaults
            )
        }
    }

    func capture(
        descriptor: HWCCloudSnapshotStoreDescriptor,
        from source: HWCCloudSnapshotUserDefaultsBacking
    ) throws -> [HWCCloudSnapshotEntry] {
        guard descriptor.id == .clipboardSnippets,
              descriptor.sourceKeys == [Self.sourceKey],
              descriptor.snapshotKeys == [Self.snapshotKey] else {
            throw HWCCloudSnapshotAdapterError.invalidTransformerEntries(
                descriptor.id
            )
        }
        let snippets = try HWKEncryptedClipboardStore.validatedPortableSnippets(
            exportSnippets()
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return [
            HWCCloudSnapshotEntry(
                key: Self.snapshotKey,
                value: .data(try encoder.encode(snippets))
            ),
        ]
    }

    func restore(
        entries: [HWCCloudSnapshotEntry],
        descriptor: HWCCloudSnapshotStoreDescriptor
    ) throws -> HWCCloudSnapshotUserDefaultsMutation {
        guard descriptor.id == .clipboardSnippets,
              descriptor.sourceKeys == [Self.sourceKey],
              descriptor.snapshotKeys == [Self.snapshotKey],
              entries.count == 1,
              entries[0].key == Self.snapshotKey else {
            throw HWCCloudSnapshotAdapterError.invalidTransformerEntries(
                descriptor.id
            )
        }
        guard let value = entries[0].value else {
            return HWCCloudSnapshotUserDefaultsMutation(
                removingKeys: [Self.sourceKey]
            )
        }
        guard case .data(let data) = value,
              let decoded = try? JSONDecoder().decode(
                  [HWKClipboardSnippet].self,
                  from: data
              ) else {
            throw HWKEncryptedClipboardStoreError.invalidPayload
        }
        let snippets = try HWKEncryptedClipboardStore.validatedPortableSnippets(
            decoded
        )
        return HWCCloudSnapshotUserDefaultsMutation(
            values: [Self.sourceKey: try encodeRestoredSnippets(snippets)]
        )
    }
}

import Foundation

enum HWKKeymapTransferAdapter {
    enum RowRole: Equatable {
        case content
        case appOwned
    }

    struct Row: Equatable {
        var role: RowRole
        var keys: [HWKKeymapTransferDocument.Key]
    }

    static func document(
        title: String,
        kind: HWKKeymapTransferDocument.LayerKind,
        rows: [Row]
    ) throws -> HWKKeymapTransferDocument {
        let contentRows = rows
            .filter { $0.role == .content }
            .map(\.keys)
        let expectedRowCount = kind == .mainRow ? 1 : 3
        guard contentRows.count == expectedRowCount else {
            throw HWKKeymapTransferError.exportFailed
        }

        let document = HWKKeymapTransferDocument(
            title: title,
            kind: kind,
            rows: contentRows
        )
        try document.validate()
        return document
    }
}

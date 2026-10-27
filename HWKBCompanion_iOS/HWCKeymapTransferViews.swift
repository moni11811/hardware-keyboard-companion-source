import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let hwcKeymapLayer = UTType(
        exportedAs: "dev.moni11811.hwkc.keymap-layer",
        conformingTo: .json
    )
}

struct HWCKeymapTransferFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.hwcKeymapLayer, .json] }
    static var writableContentTypes: [UTType] { [.hwcKeymapLayer] }

    let data: Data

    init(data: Data) throws {
        _ = try HWKKeymapTransferDocument.decodeFileData(data)
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw HWKKeymapTransferError.invalidFile
        }
        try self.init(data: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        transferFileWrapper()
    }

    func transferFileWrapper() -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct HWCKeymapTransferPreview: Identifiable {
    let id = UUID()
    let document: HWKKeymapTransferDocument
    let data: Data
    let sourceFilename: String?

    init(data: Data, sourceFilename: String? = nil) throws {
        document = try HWKKeymapTransferDocument.decodeFileData(data)
        self.data = data
        self.sourceFilename = sourceFilename
    }

    var kindTitle: String {
        document.kind == .mainRow ? "Main Row" : "Expanded Layer"
    }

    var totalKeyCount: Int {
        document.rows.reduce(0) { $0 + $1.count }
    }

    var suggestedFilename: String {
        HWKKeymapTransferDocument.suggestedFilenameStem(for: document.title)
    }

    func accessibilitySummary(forRow index: Int) -> String {
        guard document.rows.indices.contains(index) else { return "" }
        let row = document.rows[index]
        let taps = row.map { key in
            key.tap.isEmpty ? "Empty key" : key.tap
        }.joined(separator: ", ")
        let holdCount = row.reduce(0) { $0 + $1.holdChoices.count }
        return "\(taps). \(holdCount) ordered Hold action\(holdCount == 1 ? "" : "s")."
    }
}

enum HWCKeymapTransferSheetDestination: Identifiable {
    case importPreview(HWCKeymapTransferPreview)
    case exportPreview(HWCKeymapTransferPreview)

    var id: String {
        switch self {
        case .importPreview(let preview):
            return "import-\(preview.id.uuidString)"
        case .exportPreview(let preview):
            return "export-\(preview.id.uuidString)"
        }
    }
}

enum HWCKeymapTransferErrorPresentation {
    enum Operation {
        case importTransfer
        case exportTransfer
    }

    static func message(for error: Error, operation: Operation) -> String? {
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain,
           cocoaError.code == NSUserCancelledError {
            return nil
        }
        if let transferError = error as? HWKKeymapTransferError {
            return transferError.errorDescription
        }

        switch operation {
        case .importTransfer:
            return "HWC could not read this keymap layer file."
        case .exportTransfer:
            if cocoaError.domain == NSCocoaErrorDomain,
               cocoaError.code == CocoaError.fileWriteOutOfSpace.rawValue {
                return "The selected location does not have enough storage for this HWC layer file."
            }
            return "HWC could not save this keymap layer to the selected location."
        }
    }
}

struct HWCKeymapImportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: HWCKeymapTransferPreview
    let accessMessage: String?
    let canImport: Bool
    let onImport: (Data) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Layer") {
                    LabeledContent("Name", value: preview.document.title)
                    LabeledContent("Type", value: preview.kindTitle)
                    LabeledContent("Rows", value: "\(preview.document.rows.count)")
                    LabeledContent("Keys", value: "\(preview.totalKeyCount)")
                    if let sourceFilename = preview.sourceFilename {
                        LabeledContent("File", value: sourceFilename)
                    }
                }

                Section("Preview") {
                    ForEach(Array(preview.document.rows.enumerated()), id: \.offset) { pair in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Row \(pair.offset + 1)")
                                .font(.headline)
                            Text(pair.element.map(\.tap).joined(separator: "  "))
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            let holdCount = pair.element.reduce(0) { $0 + $1.holdChoices.count }
                            Text("\(holdCount) ordered Hold action\(holdCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Row \(pair.offset + 1)")
                        .accessibilityValue(preview.accessibilitySummary(forRow: pair.offset))
                        .accessibilityIdentifier("hwc.keymapTransfer.import.row.\(pair.offset + 1)")
                    }
                }

                Section {
                    Text(accessMessage ?? "This adds a new Live Keyboard Editor layer without changing existing layers or My Presets.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("hwc.keymapTransfer.import.result")
                }
            }
            .accessibilityIdentifier("hwc.keymapTransfer.import.sheet")
            .navigationTitle("Import Layer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("hwc.keymapTransfer.import.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Layer") {
                        let data = preview.data
                        dismiss()
                        DispatchQueue.main.async {
                            onImport(data)
                        }
                    }
                    .disabled(!canImport)
                    .accessibilityHint("Adds this file as a new Live Keyboard Editor layer")
                    .accessibilityIdentifier("hwc.keymapTransfer.import.confirm")
                }
            }
        }
    }
}

struct HWCKeymapExportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let preview: HWCKeymapTransferPreview
    let onExport: (HWCKeymapTransferPreview) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Layer") {
                    LabeledContent("Name", value: preview.document.title)
                    LabeledContent("Type", value: preview.kindTitle)
                    LabeledContent("Rows", value: "\(preview.document.rows.count)")
                    LabeledContent("Keys", value: "\(preview.totalKeyCount)")
                }

                Section("Privacy") {
                    Text("The file contains only this layer's Tap and ordered Hold actions. It does not include purchases, cloud history, clipboard content, learning data, or other settings.")
                        .accessibilityIdentifier("hwc.keymapTransfer.export.privacy")
                }
            }
            .accessibilityIdentifier("hwc.keymapTransfer.export.sheet")
            .navigationTitle("Export Layer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .accessibilityIdentifier("hwc.keymapTransfer.export.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save or Share") {
                        dismiss()
                        DispatchQueue.main.async {
                            onExport(preview)
                        }
                    }
                    .accessibilityHint("Opens the system export picker for a private HWC layer file")
                    .accessibilityIdentifier("hwc.keymapTransfer.export.confirm")
                }
            }
        }
    }
}

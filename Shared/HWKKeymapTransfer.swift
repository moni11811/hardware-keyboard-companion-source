import Foundation

enum HWKKeymapTransferError: Error, Equatable, LocalizedError {
    case unsupportedFormat
    case unsupportedVersion
    case invalidTitle
    case invalidRowCount
    case invalidKeyCount
    case invalidKeyValue
    case unsupportedLayerReference
    case fileTooLarge
    case invalidFile
    case importFailed
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This is not an HWC keymap layer file."
        case .unsupportedVersion:
            return "This keymap layer was created by an unsupported version."
        case .invalidTitle:
            return "The layer name must contain 1 to 24 characters."
        case .invalidRowCount:
            return "The keymap layer has an invalid number of rows."
        case .invalidKeyCount:
            return "Each keymap row must contain 6 to 12 keys."
        case .invalidKeyValue:
            return "A key value or hold choice is too long."
        case .unsupportedLayerReference:
            return "A custom-layer link cannot be included in a single-layer HWC file. Replace that key before exporting."
        case .fileTooLarge:
            return "This keymap layer file is larger than 256 KB."
        case .invalidFile:
            return "HWC could not read this keymap layer file."
        case .importFailed:
            return "HWC could not add this keymap layer."
        case .exportFailed:
            return "HWC could not export this keymap layer."
        }
    }
}

struct HWKKeymapTransferDocument: Codable, Equatable {
    static let formatIdentifier = "hwc-keymap-layer"
    static let legacyFormatIdentifier = "hwkc-keymap-layer"
    static let fileExtension = "hwclayer"
    static let currentVersion = 1
    static let maxTitleLength = 24
    static let minKeysPerRow = 6
    static let maxKeysPerRow = 12
    static let maxKeyValueLength = 64
    static let maxHoldChoices = 8
    static let maxFileBytes = 262_144

    enum LayerKind: String, Codable, Equatable {
        case mainRow
        case expanded
    }

    struct Key: Codable, Equatable {
        var tap: String
        var holdChoices: [String]

        init(tap: String, holdChoices: [String] = []) {
            self.tap = tap
            self.holdChoices = holdChoices
        }
    }

    var format: String
    var version: Int
    var title: String
    var kind: LayerKind
    var rows: [[Key]]

    init(
        format: String = HWKKeymapTransferDocument.formatIdentifier,
        version: Int = HWKKeymapTransferDocument.currentVersion,
        title: String,
        kind: LayerKind,
        rows: [[Key]]
    ) {
        self.format = format
        self.version = version
        self.title = title
        self.kind = kind
        self.rows = rows
    }

    func validate() throws {
        guard format == Self.formatIdentifier || format == Self.legacyFormatIdentifier else {
            throw HWKKeymapTransferError.unsupportedFormat
        }
        guard version == Self.currentVersion else {
            throw HWKKeymapTransferError.unsupportedVersion
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              Self.websiteLength(of: trimmedTitle) <= Self.maxTitleLength else {
            throw HWKKeymapTransferError.invalidTitle
        }
        let expectedRowCount = kind == .mainRow ? 1 : 3
        guard rows.count == expectedRowCount else {
            throw HWKKeymapTransferError.invalidRowCount
        }
        for row in rows {
            guard (Self.minKeysPerRow...Self.maxKeysPerRow).contains(row.count) else {
                throw HWKKeymapTransferError.invalidKeyCount
            }
            for key in row {
                guard Self.websiteLength(of: key.tap) <= Self.maxKeyValueLength,
                      key.holdChoices.count <= Self.maxHoldChoices,
                      key.holdChoices.allSatisfy({ choice in
                          !choice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                              Self.websiteLength(of: choice) <= Self.maxKeyValueLength
                      }) else {
                    throw HWKKeymapTransferError.invalidKeyValue
                }
                if ([key.tap] + key.holdChoices).contains(where: Self.isDeviceLocalLayerReference) {
                    throw HWKKeymapTransferError.unsupportedLayerReference
                }
            }
        }
    }

    private static func isDeviceLocalLayerReference(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("@layer:")
    }

    private static func websiteLength(of value: String) -> Int {
        value.utf16.count
    }

    static func decodeFileData(_ data: Data) throws -> HWKKeymapTransferDocument {
        guard data.count <= maxFileBytes else {
            throw HWKKeymapTransferError.fileTooLarge
        }
        do {
            try HWKJSONDuplicateKeyValidator.validate(data)
            let document = try JSONDecoder().decode(HWKKeymapTransferDocument.self, from: data)
            try document.validate()
            return document
        } catch let error as HWKKeymapTransferError {
            throw error
        } catch {
            throw HWKKeymapTransferError.invalidFile
        }
    }

    static func suggestedFilenameStem(for title: String) -> String {
        let components = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let stem = components.joined(separator: "-").lowercased()
        return stem.isEmpty ? "hwc-layer" : stem
    }

    func encodeFileData() throws -> Data {
        var canonical = self
        canonical.format = Self.formatIdentifier
        canonical.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try canonical.validate()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(canonical)
        data.append(0x0A)
        guard data.count <= Self.maxFileBytes else {
            throw HWKKeymapTransferError.fileTooLarge
        }
        return data
    }
}

enum HWKKeymapTransferFileLoader {
    typealias FileSizeProvider = (URL) throws -> Int?

    static func load(
        from url: URL,
        fileSizeProvider: FileSizeProvider = { url in
            try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        }
    ) throws -> Data {
        let reportedSize: Int?
        do {
            reportedSize = try fileSizeProvider(url)
        } catch {
            reportedSize = nil
        }
        if let reportedSize,
           reportedSize > HWKKeymapTransferDocument.maxFileBytes {
            throw HWKKeymapTransferError.fileTooLarge
        }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw HWKKeymapTransferError.invalidFile
        }
        defer { try? handle.close() }

        var data = Data()
        let readLimit = HWKKeymapTransferDocument.maxFileBytes + 1
        do {
            while data.count < readLimit {
                let remaining = readLimit - data.count
                let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
            }
        } catch {
            throw HWKKeymapTransferError.invalidFile
        }
        guard data.count <= HWKKeymapTransferDocument.maxFileBytes else {
            throw HWKKeymapTransferError.fileTooLarge
        }
        return data
    }
}

private enum HWKJSONDuplicateKeyValidator {
    private enum ValidationError: Error {
        case invalidJSON
        case duplicateKey
        case nestingTooDeep
    }

    static func validate(_ data: Data) throws {
        var scanner = Scanner(bytes: Array(data))
        do {
            try scanner.validate()
        } catch {
            throw HWKKeymapTransferError.invalidFile
        }
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        let maximumDepth = 64

        mutating func validate() throws {
            skipWhitespace()
            try parseValue(depth: 0)
            skipWhitespace()
            guard index == bytes.count else { throw ValidationError.invalidJSON }
        }

        private mutating func parseValue(depth: Int) throws {
            guard depth <= maximumDepth, index < bytes.count else {
                throw depth > maximumDepth ? ValidationError.nestingTooDeep : ValidationError.invalidJSON
            }
            switch bytes[index] {
            case 0x7B:
                try parseObject(depth: depth + 1)
            case 0x5B:
                try parseArray(depth: depth + 1)
            case 0x22:
                _ = try parseString()
            default:
                try parsePrimitive()
            }
        }

        private mutating func parseObject(depth: Int) throws {
            index += 1
            skipWhitespace()
            if consume(0x7D) { return }

            var keys = Set<String>()
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == 0x22 else {
                    throw ValidationError.invalidJSON
                }
                let key = try parseString()
                guard keys.insert(key).inserted else {
                    throw ValidationError.duplicateKey
                }
                skipWhitespace()
                guard consume(0x3A) else { throw ValidationError.invalidJSON }
                skipWhitespace()
                try parseValue(depth: depth)
                skipWhitespace()
                if consume(0x7D) { return }
                guard consume(0x2C) else { throw ValidationError.invalidJSON }
            }
        }

        private mutating func parseArray(depth: Int) throws {
            index += 1
            skipWhitespace()
            if consume(0x5D) { return }

            while true {
                try parseValue(depth: depth)
                skipWhitespace()
                if consume(0x5D) { return }
                guard consume(0x2C) else { throw ValidationError.invalidJSON }
                skipWhitespace()
            }
        }

        private mutating func parseString() throws -> String {
            let start = index
            index += 1
            while index < bytes.count {
                let byte = bytes[index]
                if byte == 0x22 {
                    index += 1
                    let data = Data(bytes[start..<index])
                    guard let value = try? JSONDecoder().decode(String.self, from: data) else {
                        throw ValidationError.invalidJSON
                    }
                    return value
                }
                if byte == 0x5C {
                    index += 1
                    guard index < bytes.count else { throw ValidationError.invalidJSON }
                    if bytes[index] == 0x75 {
                        guard index + 4 < bytes.count else { throw ValidationError.invalidJSON }
                        for offset in 1...4 where !Self.isHexDigit(bytes[index + offset]) {
                            throw ValidationError.invalidJSON
                        }
                        index += 5
                    } else {
                        guard Self.simpleEscapes.contains(bytes[index]) else {
                            throw ValidationError.invalidJSON
                        }
                        index += 1
                    }
                    continue
                }
                guard byte >= 0x20 else { throw ValidationError.invalidJSON }
                index += 1
            }
            throw ValidationError.invalidJSON
        }

        private mutating func parsePrimitive() throws {
            let start = index
            while index < bytes.count,
                  !Self.primitiveDelimiters.contains(bytes[index]) {
                index += 1
            }
            guard index > start else { throw ValidationError.invalidJSON }
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, Self.whitespace.contains(bytes[index]) {
                index += 1
            }
        }

        private mutating func consume(_ byte: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        private static let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        private static let primitiveDelimiters: Set<UInt8> = whitespace.union([0x2C, 0x5D, 0x7D])
        private static let simpleEscapes: Set<UInt8> = [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74]

        private static func isHexDigit(_ byte: UInt8) -> Bool {
            (0x30...0x39).contains(byte) ||
                (0x41...0x46).contains(byte) ||
                (0x61...0x66).contains(byte)
        }
    }
}

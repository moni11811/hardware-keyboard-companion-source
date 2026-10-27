import CoreFoundation
import Foundation

enum HWCCloudSnapshotAdapterError: Error, Equatable {
    case unsupportedValue(HWCCloudSnapshotStoreID, String)
    case nonFiniteNumber
    case integerOutOfRange
    case missingTransformer(HWCCloudSnapshotStoreID)
    case invalidTransformerEntries(HWCCloudSnapshotStoreID)
    case incompletePayload
    case duplicateSourceKey(String)
    case totalTooLarge(Int)
}

struct HWCCloudSnapshotUserDefaultsMutation {
    var values: [String: Any]
    var removingKeys: Set<String>

    init(
        values: [String: Any] = [:],
        removingKeys: Set<String> = []
    ) {
        self.values = values
        self.removingKeys = removingKeys
    }

    var touchedKeys: Set<String> {
        Set(values.keys).union(removingKeys)
    }
}

protocol HWCCloudSnapshotUserDefaultsBacking: AnyObject {
    func object(forKey key: String) -> Any?
    func replaceAtomically(_ mutation: HWCCloudSnapshotUserDefaultsMutation) throws
}

final class HWCCloudSnapshotMemoryUserDefaultsBacking: HWCCloudSnapshotUserDefaultsBacking {
    private var values: [String: Any]
    private(set) var atomicReplacementCount = 0

    init(values: [String: Any] = [:]) {
        self.values = values
    }

    func object(forKey key: String) -> Any? {
        values[key]
    }

    func replaceAtomically(_ mutation: HWCCloudSnapshotUserDefaultsMutation) throws {
        var next = values
        for key in mutation.removingKeys {
            next.removeValue(forKey: key)
        }
        for (key, value) in mutation.values {
            next[key] = value
        }
        values = next
        atomicReplacementCount += 1
    }
}

protocol HWCCloudSnapshotStoreTransformer {
    func capture(
        descriptor: HWCCloudSnapshotStoreDescriptor,
        from source: HWCCloudSnapshotUserDefaultsBacking
    ) throws -> [HWCCloudSnapshotEntry]

    func restore(
        entries: [HWCCloudSnapshotEntry],
        descriptor: HWCCloudSnapshotStoreDescriptor
    ) throws -> HWCCloudSnapshotUserDefaultsMutation
}

enum HWCCloudSnapshotUserDefaultsAdapter {
    static let defaultMaximumTotalEncodedBytes = 8 * 1_024 * 1_024

    static func capture(
        from source: HWCCloudSnapshotUserDefaultsBacking,
        registry: HWCCloudSnapshotRegistry,
        revision: UInt64,
        modifiedAtMilliseconds: Int64,
        maximumTotalEncodedBytes: Int = defaultMaximumTotalEncodedBytes,
        transformers: [HWCCloudSnapshotStoreID: HWCCloudSnapshotStoreTransformer] = [:]
    ) throws -> [HWCCloudSnapshotRecord] {
        try validateRegistry(registry)
        var records = [HWCCloudSnapshotRecord]()

        for descriptor in registry.descriptors.sorted(by: {
            $0.id.rawValue < $1.id.rawValue
        }) {
            let entries: [HWCCloudSnapshotEntry]
            if descriptor.sourceKeys != descriptor.snapshotKeys {
                guard let transformer = transformers[descriptor.id] else {
                    throw HWCCloudSnapshotAdapterError.missingTransformer(descriptor.id)
                }
                entries = try transformer.capture(descriptor: descriptor, from: source)
                try validateTransformerEntries(entries, descriptor: descriptor)
            } else {
                entries = try descriptor.sourceKeys.sorted().map { key in
                    let value: HWCCloudSnapshotValue?
                    if let stored = source.object(forKey: key) {
                        do {
                            value = try snapshotValue(from: stored)
                        } catch {
                            throw HWCCloudSnapshotAdapterError.unsupportedValue(
                                descriptor.id,
                                key
                            )
                        }
                    } else {
                        value = nil
                    }
                    return HWCCloudSnapshotEntry(key: key, value: value)
                }
            }

            let encodedEntries = try deterministicEncode(entries)
            guard encodedEntries.count <= descriptor.maximumEncodedBytes else {
                throw HWCCloudSnapshotError.recordTooLarge(
                    descriptor.id,
                    encodedEntries.count
                )
            }
            records.append(try HWCCloudSnapshotRecord.make(
                id: descriptor.id,
                schemaVersion: descriptor.schemaVersion,
                revision: revision,
                modifiedAtMilliseconds: modifiedAtMilliseconds,
                entries: entries
            ))
        }

        let totalBytes = try deterministicEncode(records).count
        guard totalBytes <= maximumTotalEncodedBytes else {
            throw HWCCloudSnapshotAdapterError.totalTooLarge(totalBytes)
        }
        return records
    }

    static func restore(
        _ payload: HWCCloudSnapshotPayload,
        registry: HWCCloudSnapshotRegistry,
        into destination: HWCCloudSnapshotUserDefaultsBacking,
        maximumTotalEncodedBytes: Int = defaultMaximumTotalEncodedBytes,
        transformers: [HWCCloudSnapshotStoreID: HWCCloudSnapshotStoreTransformer] = [:]
    ) throws {
        let staged = try validatedRestoreMutation(
            payload,
            registry: registry,
            maximumTotalEncodedBytes: maximumTotalEncodedBytes,
            transformers: transformers
        )
        try destination.replaceAtomically(staged)
    }

    /// Performs every schema, size, transformer, and completeness check without
    /// touching the destination. Callers can safely compare-and-swap remote
    /// authority before applying the returned mutation once.
    static func validatedRestoreMutation(
        _ payload: HWCCloudSnapshotPayload,
        registry: HWCCloudSnapshotRegistry,
        maximumTotalEncodedBytes: Int = defaultMaximumTotalEncodedBytes,
        transformers: [HWCCloudSnapshotStoreID: HWCCloudSnapshotStoreTransformer] = [:]
    ) throws -> HWCCloudSnapshotUserDefaultsMutation {
        try payload.validate()
        try validateRegistry(registry)
        let currentStoreIDs = Set(payload.records.map(\.id)).union(
            payload.storeTombstones.map(\.id)
        )
        guard currentStoreIDs == Set(registry.descriptors.map(\.id)) else {
            throw HWCCloudSnapshotAdapterError.incompletePayload
        }
        let totalBytes = try deterministicEncode(payload.records).count
        guard totalBytes <= maximumTotalEncodedBytes else {
            throw HWCCloudSnapshotAdapterError.totalTooLarge(totalBytes)
        }

        var staged = HWCCloudSnapshotUserDefaultsMutation()
        for record in payload.records {
            guard let descriptor = registry.descriptor(for: record.id) else {
                throw HWCCloudSnapshotError.unknownStore(record.id)
            }
            guard record.schemaVersion == descriptor.schemaVersion else {
                throw HWCCloudSnapshotError.unsupportedStoreSchema(
                    record.id,
                    record.schemaVersion
                )
            }
            try record.validate()
            let encodedEntries = try deterministicEncode(record.entries)
            guard encodedEntries.count <= descriptor.maximumEncodedBytes else {
                throw HWCCloudSnapshotError.recordTooLarge(
                    record.id,
                    encodedEntries.count
                )
            }
            guard Set(record.entries.map(\.key)) == descriptor.snapshotKeys,
                  Set(record.entries.map(\.key)).count == record.entries.count else {
                throw HWCCloudSnapshotError.unexpectedStoreKey(
                    record.id,
                    record.entries.first?.key ?? ""
                )
            }

            let mutation: HWCCloudSnapshotUserDefaultsMutation
            if descriptor.sourceKeys != descriptor.snapshotKeys {
                guard let transformer = transformers[descriptor.id] else {
                    throw HWCCloudSnapshotAdapterError.missingTransformer(descriptor.id)
                }
                mutation = try transformer.restore(
                    entries: record.entries,
                    descriptor: descriptor
                )
                guard mutation.touchedKeys == descriptor.sourceKeys,
                      mutation.touchedKeys.isDisjoint(with: descriptor.snapshotKeys.subtracting(descriptor.sourceKeys)) else {
                    throw HWCCloudSnapshotAdapterError.invalidTransformerEntries(
                        descriptor.id
                    )
                }
            } else {
                var values = [String: Any]()
                var removals = Set<String>()
                for entry in record.entries {
                    if let value = entry.value {
                        values[entry.key] = try userDefaultsValue(from: value)
                    } else {
                        removals.insert(entry.key)
                    }
                }
                mutation = HWCCloudSnapshotUserDefaultsMutation(
                    values: values,
                    removingKeys: removals
                )
            }

            guard staged.touchedKeys.isDisjoint(with: mutation.touchedKeys) else {
                let duplicate = staged.touchedKeys.intersection(
                    mutation.touchedKeys
                ).sorted().first ?? ""
                throw HWCCloudSnapshotAdapterError.duplicateSourceKey(duplicate)
            }
            staged.values.merge(mutation.values) { current, _ in current }
            staged.removingKeys.formUnion(mutation.removingKeys)
        }

        for tombstone in payload.storeTombstones {
            guard let descriptor = registry.descriptor(for: tombstone.id) else {
                throw HWCCloudSnapshotError.unknownStore(tombstone.id)
            }
            guard tombstone.schemaVersion == descriptor.schemaVersion else {
                throw HWCCloudSnapshotError.unsupportedStoreSchema(
                    tombstone.id,
                    tombstone.schemaVersion
                )
            }
            try tombstone.validate()
            guard staged.touchedKeys.isDisjoint(with: descriptor.sourceKeys) else {
                let duplicate = staged.touchedKeys.intersection(
                    descriptor.sourceKeys
                ).sorted().first ?? ""
                throw HWCCloudSnapshotAdapterError.duplicateSourceKey(duplicate)
            }
            staged.removingKeys.formUnion(descriptor.sourceKeys)
        }

        return staged
    }

    static func snapshotValue(from value: Any) throws -> HWCCloudSnapshotValue {
        if let data = value as? Data {
            return .data(data)
        }
        if let string = value as? String {
            return .string(string)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .boolean(number.boolValue)
            }
            let type = String(cString: number.objCType)
            if ["f", "d"].contains(type) {
                let double = number.doubleValue
                guard double.isFinite else {
                    throw HWCCloudSnapshotAdapterError.nonFiniteNumber
                }
                return .double(double)
            }
            return .integer(number.int64Value)
        }
        if let integer = value as? Int {
            return .integer(Int64(integer))
        }
        if let integer = value as? Int64 {
            return .integer(integer)
        }
        if let unsigned = value as? UInt {
            guard unsigned <= UInt(Int64.max) else {
                throw HWCCloudSnapshotAdapterError.integerOutOfRange
            }
            return .integer(Int64(unsigned))
        }
        if let double = value as? Double {
            guard double.isFinite else {
                throw HWCCloudSnapshotAdapterError.nonFiniteNumber
            }
            return .double(double)
        }
        if let float = value as? Float {
            guard float.isFinite else {
                throw HWCCloudSnapshotAdapterError.nonFiniteNumber
            }
            return .double(Double(float))
        }
        if let array = value as? [Any] {
            return .array(try array.map(snapshotValue(from:)))
        }
        if let dictionary = value as? [String: Any] {
            return .dictionary(try dictionary.mapValues(snapshotValue(from:)))
        }
        throw HWCCloudSnapshotAdapterError.unsupportedValue(.settings, "")
    }

    static func userDefaultsValue(from value: HWCCloudSnapshotValue) throws -> Any {
        switch value {
        case .data(let data):
            return data
        case .string(let string):
            return string
        case .integer(let integer):
            guard integer >= Int64(Int.min), integer <= Int64(Int.max) else {
                throw HWCCloudSnapshotAdapterError.integerOutOfRange
            }
            return Int(integer)
        case .double(let double):
            guard double.isFinite else {
                throw HWCCloudSnapshotAdapterError.nonFiniteNumber
            }
            return double
        case .boolean(let boolean):
            return boolean
        case .array(let values):
            return try values.map(userDefaultsValue(from:))
        case .dictionary(let values):
            return try values.mapValues(userDefaultsValue(from:))
        }
    }

    private static func validateRegistry(
        _ registry: HWCCloudSnapshotRegistry
    ) throws {
        guard Set(registry.descriptors.map(\.id)).count == registry.descriptors.count else {
            throw HWCCloudSnapshotAdapterError.incompletePayload
        }
        var sourceKeys = Set<String>()
        for descriptor in registry.descriptors {
            for key in descriptor.sourceKeys {
                guard sourceKeys.insert(key).inserted else {
                    throw HWCCloudSnapshotAdapterError.duplicateSourceKey(key)
                }
            }
        }
    }

    private static func validateTransformerEntries(
        _ entries: [HWCCloudSnapshotEntry],
        descriptor: HWCCloudSnapshotStoreDescriptor
    ) throws {
        guard Set(entries.map(\.key)) == descriptor.snapshotKeys,
              Set(entries.map(\.key)).count == entries.count else {
            throw HWCCloudSnapshotAdapterError.invalidTransformerEntries(
                descriptor.id
            )
        }
    }

    private static func deterministicEncode<T: Encodable>(
        _ value: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

import Foundation

enum HWKLayoutEngineError: Error, Equatable {
    case unsupportedSchema(Int)
    case emptyLayers
    case emptyRows(HWKLayoutLayerID)
    case emptyKeys(String)
}

struct HWKResolvedLayout: Equatable {
    var descriptor: HWKLayoutDescriptor
    var rowsByLayer: [HWKLayoutLayerID: [HWKLayoutRowDescriptor]]
}

struct HWKLayoutEngine {
    private let decoder = JSONDecoder()

    func decodeDescriptor(from data: Data) throws -> HWKLayoutDescriptor {
        let descriptor = try decoder.decode(HWKLayoutDescriptor.self, from: data)
        try validate(descriptor)
        return descriptor
    }

    func resolve(_ descriptor: HWKLayoutDescriptor) throws -> HWKResolvedLayout {
        try validate(descriptor)
        var rowsByLayer = [HWKLayoutLayerID: [HWKLayoutRowDescriptor]]()
        for layer in descriptor.layers {
            rowsByLayer[layer.id] = layer.rows
        }
        return HWKResolvedLayout(descriptor: descriptor, rowsByLayer: rowsByLayer)
    }

    func fallback() -> HWKResolvedLayout {
        let descriptor = HWKLayoutDescriptor.compactEnglishUS()
        let rowsByLayer = Dictionary(uniqueKeysWithValues: descriptor.layers.map { ($0.id, $0.rows) })
        return HWKResolvedLayout(descriptor: descriptor, rowsByLayer: rowsByLayer)
    }

    func bundled(locale: String) throws -> HWKResolvedLayout {
        guard let descriptor = HWKEuropeanLayoutCatalog.descriptor(locale: locale)
            ?? HWKScriptLayoutCatalog.descriptor(locale: locale) else {
            return fallback()
        }
        return try resolve(descriptor)
    }

    private func validate(_ descriptor: HWKLayoutDescriptor) throws {
        guard descriptor.schemaVersion == HWKLayoutSchemaVersion.current else {
            throw HWKLayoutEngineError.unsupportedSchema(descriptor.schemaVersion)
        }
        guard !descriptor.layers.isEmpty else {
            throw HWKLayoutEngineError.emptyLayers
        }
        for layer in descriptor.layers {
            guard !layer.rows.isEmpty else {
                throw HWKLayoutEngineError.emptyRows(layer.id)
            }
            for row in layer.rows {
                guard !row.keys.isEmpty else {
                    throw HWKLayoutEngineError.emptyKeys(row.id)
                }
            }
        }
    }
}

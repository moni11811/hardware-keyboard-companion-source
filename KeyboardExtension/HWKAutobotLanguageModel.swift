import Foundation
import CoreML
import CryptoKit

struct HWKAutobotModelResult: Sendable {
    let candidates: [HWKAutobotWordScore]
    let candidateLogits: [String: Double]
}

protocol HWKAutobotPredicting: AnyObject {
    func predict(context: HWKAutobotContext, candidateWords: [String]) throws -> HWKAutobotModelResult
    func unload()
}

/// Confined to the coordinator's serial worker; neither initialization nor prediction runs on the typing thread.
final class HWKAutobotLanguageModel: HWKAutobotPredicting {
    struct Manifest: Decodable {
        let schema: Int
        let tokenizerVersion: Int
        let contextLength: Int
        let vocabularySize: Int
        let qualified: Bool
        let modelVersion: String
        let vocabularySHA256: String
    }

    private let bundle: Bundle
    private let allowsUnqualifiedModel: Bool
    private var model: MLModel?
    private var tokenizer: HWKAutobotTokenizer?

    init(bundle: Bundle = .main, allowsUnqualifiedModel: Bool = false) {
        self.bundle = bundle
        self.allowsUnqualifiedModel = allowsUnqualifiedModel
    }

    func unload() {
        model = nil
        tokenizer = nil
    }

    private func loadIfNeeded() throws {
        guard model == nil else { return }
        guard let manifestURL = bundle.url(forResource: "HWKAutobotManifest", withExtension: "json"),
              let vocabularyURL = bundle.url(forResource: "HWKAutobotVocabulary", withExtension: "json"),
              let modelURL = bundle.url(forResource: "HWKAutobotContextModel", withExtension: "mlmodelc") else {
            throw HWKAutobotError.unavailable
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schema == 1, manifest.tokenizerVersion == 1, manifest.contextLength == 128,
              manifest.vocabularySize == 8192 else { throw HWKAutobotError.invalidManifest }
        guard manifest.qualified || allowsUnqualifiedModel else { throw HWKAutobotError.unqualified }
        let data = try Data(contentsOf: vocabularyURL)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == manifest.vocabularySHA256 else { throw HWKAutobotError.invalidVocabulary }
        let words = try JSONDecoder().decode([String].self, from: data)
        guard words.count == manifest.vocabularySize else { throw HWKAutobotError.invalidVocabulary }
        let loadedTokenizer = try HWKAutobotTokenizer(vocabulary: words)
        let configuration = MLModelConfiguration()
        // Small recurrent graphs avoid GPU contention and accelerator warm-up memory.
        configuration.computeUnits = .cpuOnly
        let loaded = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard let input = loaded.modelDescription.inputDescriptionsByName["tokens"]?.multiArrayConstraint,
              input.shape.map(\.intValue) == [1, 128], input.dataType == .int32,
              let output = loaded.modelDescription.outputDescriptionsByName["logits"]?.multiArrayConstraint,
              output.shape.map(\.intValue) == [1, 8192], output.dataType == .float32 else {
            throw HWKAutobotError.invalidManifest
        }
        tokenizer = loadedTokenizer
        model = loaded
    }

    func predict(context: HWKAutobotContext, candidateWords: [String]) throws -> HWKAutobotModelResult {
        precondition(!Thread.isMainThread, "Autobot inference must never block typing")
        try loadIfNeeded()
        guard let model, let tokenizer else { throw HWKAutobotError.unavailable }
        let tokens = try MLMultiArray(shape: [1, 128], dataType: .int32)
        for (index, value) in tokenizer.encode(context.modelContext).enumerated() { tokens[index] = NSNumber(value: value) }
        let input = try MLDictionaryFeatureProvider(dictionary: ["tokens": MLFeatureValue(multiArray: tokens)])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "logits")?.multiArrayValue,
              array.shape.map(\.intValue) == [1, 8192] else { throw HWKAutobotError.invalidOutput }
        let logits = (0..<array.count).map { array[$0].floatValue }
        let candidates = try HWKAutobotContextualRanker.candidates(logits: logits, tokenizer: tokenizer, prefix: context.prefix)
        var candidateLogits = [String: Double]()
        for word in candidateWords.prefix(24) {
            if let id = tokenizer.id(for: word), id >= 4 { candidateLogits[word.lowercased()] = Double(logits[id]) }
        }
        return HWKAutobotModelResult(candidates: candidates, candidateLogits: candidateLogits)
    }
}

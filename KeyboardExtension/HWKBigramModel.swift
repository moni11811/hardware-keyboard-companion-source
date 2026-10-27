import Foundation

struct HWKBigramModel {
    private var weights: [String: [String: Double]]

    init(weights: [String: [String: Double]] = [:]) {
        self.weights = weights
    }

    func score(previous: String?, candidate: String) -> Double {
        guard let previous else { return 0 }
        return weights[previous.lowercased()]?[candidate.lowercased()] ?? 0
    }
}


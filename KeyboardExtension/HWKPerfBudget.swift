import Foundation

enum HWKPerfMetricID: String, Codable, CaseIterable {
    case keyboardColdLaunchP95MS
    case firstKeyDownToOutcomeP95MS
    case keyInsertMedianMS
    case keyInsertP95MS
    case keyDownToOutcomeP95MS
    case suggestionP95MS
    case layoutResolveP95MS
    case extensionMemoryMB
}

struct HWKPerfSample: Codable, Equatable {
    let metric: HWKPerfMetricID
    let value: Double
}

struct HWKPerfBudget: Codable, Equatable {
    let metric: HWKPerfMetricID
    let maximum: Double
}

struct HWKPerfGateIssue: Equatable {
    let metric: HWKPerfMetricID
    let value: Double
    let maximum: Double
}

struct HWKPerfGate {
    let budgets: [HWKPerfMetricID: HWKPerfBudget]

    init(budgets: [HWKPerfBudget]) {
        self.budgets = Dictionary(uniqueKeysWithValues: budgets.map { ($0.metric, $0) })
    }

    func issues(for samples: [HWKPerfSample]) -> [HWKPerfGateIssue] {
        samples.compactMap { sample in
            guard let budget = budgets[sample.metric], sample.value > budget.maximum else { return nil }
            return HWKPerfGateIssue(metric: sample.metric, value: sample.value, maximum: budget.maximum)
        }
    }
}

struct HWKPerfBurstHarness {
    func measureSyntheticTyping(iterations: Int, handler: (HWKInputEvent) -> HWKInputOutcome) -> HWKPerfSample {
        return measureSyntheticTypingSamples(iterations: iterations, handler: handler).first {
            $0.metric == .keyInsertMedianMS
        } ?? HWKPerfSample(metric: .keyInsertMedianMS, value: 0)
    }

    func measureSyntheticTypingSamples(
        iterations: Int,
        handler: (HWKInputEvent) -> HWKInputOutcome
    ) -> [HWKPerfSample] {
        let samples = measureSyntheticTypingLatencyMs(iterations: iterations, handler: handler)
        guard !samples.isEmpty else {
            return [
                HWKPerfSample(metric: .keyInsertMedianMS, value: 0),
                HWKPerfSample(metric: .keyInsertP95MS, value: 0),
            ]
        }

        return [
            HWKPerfSample(metric: .keyInsertMedianMS, value: percentile(samples, percentile: 0.5)),
            HWKPerfSample(metric: .keyInsertP95MS, value: percentile(samples, percentile: 0.95)),
        ]
    }

    func percentile(_ samples: [Double], percentile: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let clamped = min(max(percentile, 0), 1)
        let sorted = samples.sorted()
        guard sorted.count > 1 else { return sorted[0] }

        let index = clamped * Double(sorted.count - 1)
        let lowerIndex = Int(index.rounded(.down))
        let upperIndex = Int(index.rounded(.up))

        if lowerIndex == upperIndex {
            return sorted[lowerIndex]
        }

        let lowerValue = sorted[lowerIndex]
        let upperValue = sorted[upperIndex]
        let ratio = index - Double(lowerIndex)
        return lowerValue + (upperValue - lowerValue) * ratio
    }

    private func measureSyntheticTypingLatencyMs(
        iterations: Int,
        handler: (HWKInputEvent) -> HWKInputOutcome
    ) -> [Double] {
        guard iterations > 0 else { return [] }

        var values: [Double] = []
        values.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = DispatchTime.now().uptimeNanoseconds
            _ = handler(HWKInputEvent(source: .softwareKey, kind: .character("a")))
            let end = DispatchTime.now().uptimeNanoseconds
            values.append(Double(end - start) / 1_000_000)
        }

        return values
    }
}

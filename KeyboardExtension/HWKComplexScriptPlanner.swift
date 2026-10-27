import Foundation

struct HWKScriptRun: Equatable {
    let script: HWKScript
    let direction: HWKTextDirection
    let text: String
}

struct HWKCursorMovementPlan: Equatable {
    let logicalOffset: Int
    let visualOffset: Int
    let direction: HWKTextDirection
}

struct HWKComplexScriptPlanner {
    private let scriptEngine = HWKScriptEngine()
    private let graphemeNavigator = HWKGraphemeNavigator()
    private let bidiCursor = HWKBiDiCursor()

    func runs(in text: String) -> [HWKScriptRun] {
        var runs: [HWKScriptRun] = []

        for cluster in graphemeNavigator.clusters(in: text) {
            let script = scriptEngine.dominantScript(for: cluster)
            let direction = scriptEngine.direction(for: script)

            if let last = runs.last,
               last.script == script,
               last.direction == direction {
                runs[runs.count - 1] = HWKScriptRun(
                    script: last.script,
                    direction: last.direction,
                    text: last.text + cluster
                )
            } else {
                runs.append(HWKScriptRun(script: script, direction: direction, text: cluster))
            }
        }

        return runs
    }

    func deleteBackward(in text: String) -> String {
        graphemeNavigator.deleteBackward(in: text)
    }

    func deleteForward(in text: String) -> String {
        graphemeNavigator.deleteForward(in: text)
    }

    func movementPlan(context: String, logicalOffset: Int) -> HWKCursorMovementPlan {
        let direction = direction(for: context, at: logicalOffset)
        return HWKCursorMovementPlan(
            logicalOffset: logicalOffset,
            visualOffset: bidiCursor.visualOffset(logicalOffset: logicalOffset, direction: direction),
            direction: direction
        )
    }

    private func direction(for context: String, at logicalOffset: Int) -> HWKTextDirection {
        let runs = runs(in: context)
        guard !runs.isEmpty else {
            return .neutral
        }

        let clampedOffset = min(max(0, logicalOffset), context.count)
        guard clampedOffset > 0 else {
            return runs.first?.direction ?? .neutral
        }

        var consumedOffset = 0
        for (index, run) in runs.enumerated() {
            let runLength = run.text.count
            let nextOffset = consumedOffset + runLength
            if clampedOffset <= nextOffset {
                return strongDirection(in: runs, at: index)
            }
            consumedOffset = nextOffset
        }

        return runs.last?.direction ?? .neutral
    }

    private func strongDirection(in runs: [HWKScriptRun], at index: Int) -> HWKTextDirection {
        let direction = runs[index].direction
        guard direction == .neutral else { return direction }

        if index > 0 {
            for previousIndex in stride(from: index - 1, through: 0, by: -1) {
                let previousDirection = runs[previousIndex].direction
                if previousDirection != .neutral {
                    return previousDirection
                }
            }
        }

        if index + 1 < runs.count {
            for nextIndex in (index + 1)..<runs.count {
                let nextDirection = runs[nextIndex].direction
                if nextDirection != .neutral {
                    return nextDirection
                }
            }
        }

        return .neutral
    }
}

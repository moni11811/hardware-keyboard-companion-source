struct HWKComplexScriptCursorOffsetTranslator {
    private let planner: HWKComplexScriptPlanner

    init(planner: HWKComplexScriptPlanner = HWKComplexScriptPlanner()) {
        self.planner = planner
    }

    func translatedOffset(_ offset: Int, inBeforeContext context: String) -> Int {
        guard !context.isEmpty else { return offset }

        let direction = planner.movementPlan(context: context, logicalOffset: context.count).direction
        guard direction == .rightToLeft else {
            return offset
        }

        return -offset
    }
}

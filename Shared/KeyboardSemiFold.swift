import Foundation

/// Each finger must move independently; a two-finger pan or a stationary thumb is not a split.
struct KeyboardSemiFoldSession {
    let leftStart: CGPoint
    let rightStart: CGPoint
    let joining: Bool
    private(set) var claimed = false
    private(set) var shouldCommit = false
    private(set) var rejected = false

    init?(left: CGPoint, right: CGPoint, joining: Bool) {
        guard right.x - left.x >= 44 else { return nil }
        leftStart = left
        rightStart = right
        self.joining = joining
    }

    mutating func update(left: CGPoint, right: CGPoint) {
        guard !rejected else { return }
        let sign: CGFloat = joining ? -1 : 1
        let leftTravel = (leftStart.x - left.x) * sign
        let rightTravel = (right.x - rightStart.x) * sign
        let vertical = max(abs(left.y - leftStart.y), abs(right.y - rightStart.y))
        if vertical > 24 || leftTravel < -12 || rightTravel < -12 {
            rejected = true
            shouldCommit = false
            return
        }
        if min(leftTravel, rightTravel) >= 10 { claimed = true }
        shouldCommit = claimed && min(leftTravel, rightTravel) >= 36
            && min(leftTravel, rightTravel) >= vertical * 1.5
    }
}

/// A single frame per key, with weighted widths within each half. No hit area crosses the gap.
enum KeyboardSemiFoldGeometry {
    static func frames(weights: [CGFloat], size: CGSize, gap: CGFloat, spacing: CGFloat, splitIndex: Int? = nil) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        let width = max(0, size.width)
        let gap = min(max(0, gap), width * 0.3)
        let half = max(0, (width - gap) / 2)
        let split = min(weights.count, max(1, splitIndex ?? (weights.count + 1) / 2))
        var result = [CGRect]()
        for range in [0..<split, split..<weights.count] where !range.isEmpty {
            let localSpacing = min(max(0, spacing), half / CGFloat(max(1, range.count - 1)))
            let units = range.reduce(CGFloat.zero) { $0 + max(0.01, weights[$1]) }
            let usable = max(0, half - localSpacing * CGFloat(max(0, range.count - 1)))
            var x: CGFloat = range.lowerBound == 0 ? 0 : half + gap
            for index in range {
                let keyWidth = usable * max(0.01, weights[index]) / units
                result.append(CGRect(x: x, y: 0, width: keyWidth, height: max(0, size.height)))
                x += keyWidth + localSpacing
            }
        }
        return result
    }
}

struct KeyboardSemiFoldRowPlan {
    let sourceIndices: [Int]
    let leftCount: Int

    init(values: [String], boundary: String? = nil, duplicateBoundary: Bool = false,
         allowsTerminalDuplication: Bool = false) {
        let indices = Array(values.indices)
        guard let boundary,
              let index = values.firstIndex(where: { $0.lowercased() == boundary }),
              index < values.count - 1 || (duplicateBoundary && allowsTerminalDuplication) else {
            sourceIndices = indices
            leftCount = (values.count + 1) / 2
            return
        }
        leftCount = index + 1
        sourceIndices = Array(indices.prefix(leftCount))
            + Array(indices.dropFirst(duplicateBoundary ? index : leftCount))
    }
}

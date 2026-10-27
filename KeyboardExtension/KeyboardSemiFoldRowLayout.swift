import SwiftUI

private struct SemiFoldKeyActionsSuppressed: EnvironmentKey {
    static let defaultValue: () -> Bool = { false }
}

private struct SemiFoldCancellationGeneration: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var semiFoldCancellationGeneration: Int {
        get { self[SemiFoldCancellationGeneration.self] }
        set { self[SemiFoldCancellationGeneration.self] = newValue }
    }
    var semiFoldKeyActionsSuppressed: () -> Bool {
        get { self[SemiFoldKeyActionsSuppressed.self] }
        set { self[SemiFoldKeyActionsSuppressed.self] = newValue }
    }
}

struct KeyboardSemiFoldWeight: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

struct KeyboardSemiFoldRowLayout: Layout {
    let gap: CGFloat
    let spacing: CGFloat
    var splitIndex: Int? = nil

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0,
               height: proposal.height ?? subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = KeyboardSemiFoldGeometry.frames(weights: subviews.map { $0[KeyboardSemiFoldWeight.self] },
                                                    size: bounds.size, gap: gap, spacing: spacing, splitIndex: splitIndex)
        for (index, subview) in subviews.enumerated() {
            let frame = frames[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(frame.size))
        }
    }
}

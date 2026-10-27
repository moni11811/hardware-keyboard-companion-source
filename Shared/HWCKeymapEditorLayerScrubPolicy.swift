import CoreGraphics

enum HWCKeymapEditorLayerScrubTarget: Equatable {
    case main(index: Int)
    case additional(index: Int)
}

struct HWCKeymapEditorLayerScrubPolicy {
    static let topRowHeight: CGFloat = 31
    private static let additionalRowHeight: CGFloat = 30
    private static let columnCount = 4
    private static let bubbleBoundaryPadding: CGFloat = 4

    static func target(
        at location: CGPoint,
        width: CGFloat,
        customLayerCount: Int
    ) -> HWCKeymapEditorLayerScrubTarget? {
        guard width > 0 else { return nil }
        let column = min(
            max(Int((min(max(location.x, 0), width) / width) * CGFloat(columnCount)), 0),
            columnCount - 1
        )
        if location.y < topRowHeight {
            return .main(index: column)
        }

        let row = max(Int((location.y - topRowHeight) / additionalRowHeight), 0)
        let gridIndex = row * columnCount + column
        guard gridIndex > 0, gridIndex <= customLayerCount else { return nil }
        return .additional(index: gridIndex - 1)
    }

    static func clampedBubbleCenter(
        _ desired: CGPoint,
        containerSize: CGSize,
        bubbleSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: clampedAxis(
                desired.x,
                containerLength: containerSize.width,
                bubbleLength: bubbleSize.width
            ),
            y: clampedAxis(
                desired.y,
                containerLength: containerSize.height,
                bubbleLength: bubbleSize.height
            )
        )
    }

    private static func clampedAxis(
        _ value: CGFloat,
        containerLength: CGFloat,
        bubbleLength: CGFloat
    ) -> CGFloat {
        guard containerLength > 0 else { return 0 }
        let minimum = (bubbleLength * 0.5) + bubbleBoundaryPadding
        let maximum = containerLength - minimum
        guard maximum >= minimum else { return containerLength * 0.5 }
        return min(max(value, minimum), maximum)
    }
}

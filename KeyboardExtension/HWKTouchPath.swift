import Foundation
import CoreGraphics

struct HWKTouchPoint: Equatable {
    var location: CGPoint
    var timestamp: TimeInterval
}

struct HWKTouchPath: Equatable {
    var points: [HWKTouchPoint]

    var isEmpty: Bool {
        points.isEmpty
    }

    var duration: TimeInterval {
        guard let first = points.first,
              let last = points.last else { return 0 }
        return max(0, last.timestamp - first.timestamp)
    }

    var distance: CGFloat {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(CGFloat(0)) { total, pair in
            let dx = pair.1.location.x - pair.0.location.x
            let dy = pair.1.location.y - pair.0.location.y
            return total + sqrt(dx * dx + dy * dy)
        }
    }

    func simplified(minDistance: CGFloat = 8) -> HWKTouchPath {
        guard let first = points.first else { return self }
        var kept = [first]
        for point in points.dropFirst() {
            guard let last = kept.last else { continue }
            let dx = point.location.x - last.location.x
            let dy = point.location.y - last.location.y
            if sqrt(dx * dx + dy * dy) >= minDistance {
                kept.append(point)
            }
        }
        if let last = points.last, kept.last != last {
            kept.append(last)
        }
        return HWKTouchPath(points: kept)
    }
}

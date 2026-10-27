import CoreGraphics
import UIKit

private func nearestMatchingKey(label: String, location: CGPoint, keys: [HWKGlideKey]) -> HWKGlideKey? {
    keys.filter { $0.label.lowercased() == label }.min {
        let leftContains = $0.frame?.contains(location) == true
        let rightContains = $1.frame?.contains(location) == true
        if leftContains != rightContains { return leftContains }
        return hypot($0.center.x - location.x, $0.center.y - location.y)
            < hypot($1.center.x - location.x, $1.center.y - location.y)
    }
}

enum HWKSpatialTouchInputPolicy {
    static func allowsSpatialTouchAdjustment(
        enabled: Bool,
        isSecureTextEntry: Bool,
        keyboardType: UIKeyboardType,
        textContentType: UITextContentType?
    ) -> Bool {
        guard enabled, !isSecureTextEntry else { return false }

        switch keyboardType {
        case .default,
             .asciiCapable,
             .alphabet,
             .emailAddress,
             .URL,
             .twitter,
             .webSearch:
            break
        case .numberPad,
             .phonePad,
             .namePhonePad,
             .numbersAndPunctuation,
             .decimalPad,
             .asciiCapableNumberPad:
            return false
        @unknown default:
            return false
        }

        let blockedContentTypes: Set<UITextContentType> = [
            .password,
            .newPassword,
            .oneTimeCode,
            .creditCardNumber
        ]

        if let textContentType, blockedContentTypes.contains(textContentType) {
            return false
        }

        return true
    }
}

struct HWKTouchHeatmapModel: Equatable {
    private struct LearnedOffset: Equatable {
        var dx: CGFloat
        var dy: CGFloat
        var weight: CGFloat
    }

    private var offsetsByLabel = [String: LearnedOffset]()
    var learningRate: CGFloat = 0.32
    var maximumOffset: CGFloat = 16
    var maximumObservedTapDistance: CGFloat = 24

    init(persistedOffsets: [String: HWKMotorTouchOffset] = [:]) {
        offsetsByLabel = persistedOffsets.mapValues {
            LearnedOffset(dx: CGFloat($0.dx), dy: CGFloat($0.dy), weight: 1)
        }
    }

    mutating func recordTap(emitted: String, location: CGPoint, keys: [HWKGlideKey]) {
        let label = emitted.lowercased()
        guard label.count == 1,
              let key = nearestMatchingKey(label: label, location: location, keys: keys) else {
            return
        }

        let offset = CGSize(
            width: location.x - key.center.x,
            height: location.y - key.center.y
        )
        guard hypot(offset.width, offset.height) <= maximumObservedTapDistance else {
            return
        }

        record(label: label, offset: offset)
    }

    func adjustedCenter(for label: String, fallbackCenter: CGPoint) -> CGPoint {
        guard let offset = offsetsByLabel[label.lowercased()] else {
            return fallbackCenter
        }

        return CGPoint(
            x: fallbackCenter.x + offset.dx,
            y: fallbackCenter.y + offset.dy
        )
    }

    func learnedOffset(for label: String) -> HWKMotorTouchOffset? {
        guard let offset = offsetsByLabel[label.lowercased()] else { return nil }
        return HWKMotorTouchOffset(dx: Double(offset.dx), dy: Double(offset.dy))
    }

    private mutating func record(label: String, offset: CGSize) {
        let clampedOffset = clamped(offset)
        let normalized = label.lowercased()

        if let current = offsetsByLabel[normalized] {
            let retained = 1 - learningRate
            offsetsByLabel[normalized] = LearnedOffset(
                dx: (current.dx * retained) + (clampedOffset.width * learningRate),
                dy: (current.dy * retained) + (clampedOffset.height * learningRate),
                weight: min(1, current.weight + 0.12)
            )
        } else {
            offsetsByLabel[normalized] = LearnedOffset(
                dx: clampedOffset.width,
                dy: clampedOffset.height,
                weight: learningRate
            )
        }
    }

    private func clamped(_ offset: CGSize) -> CGSize {
        let distance = hypot(offset.width, offset.height)
        guard distance > maximumOffset, distance > 0 else {
            return offset
        }

        let scale = maximumOffset / distance
        return CGSize(width: offset.width * scale, height: offset.height * scale)
    }
}

struct HWKSpatialTapResolver {
    var keys: [HWKGlideKey]
    var heatmap: HWKTouchHeatmapModel = HWKTouchHeatmapModel()
    var maximumKeyDistance: CGFloat = 34
    var maximumKeyCenterCorrectionDistance: CGFloat = 52
    var minimumDistanceAdvantage: CGFloat = 7
    var maximumStableMissclickDistanceAdvantage: CGFloat = 18

    func resolvedText(emitted: String, location: CGPoint) -> String? {
        let normalized = emitted.lowercased()
        guard normalized.count == 1,
              let emittedKey = nearestMatchingKey(label: normalized, location: location, keys: keys),
              let nearestKey = nearestKey(to: location) else {
            return nil
        }

        let nearestLabel = nearestKey.label.lowercased()
        guard nearestLabel.count == 1,
              nearestLabel != normalized,
              distance(from: emittedKey.center, to: nearestKey.center) <= maximumKeyCenterCorrectionDistance else {
            return nil
        }

        let emittedDistance = distance(
            from: location,
            to: heatmap.adjustedCenter(for: normalized, fallbackCenter: emittedKey.center)
        )
        let nearestDistance = distance(
            from: location,
            to: heatmap.adjustedCenter(for: nearestLabel, fallbackCenter: nearestKey.center)
        )

        guard nearestDistance <= maximumKeyDistance,
              emittedDistance - nearestDistance >= minimumDistanceAdvantage else {
            return nil
        }

        return nearestLabel
    }

    func releaseResolvedText(
        emitted: String,
        startLocation: CGPoint,
        location: CGPoint
    ) -> String? {
        let normalized = emitted.lowercased()
        let startRanked = rankedKeys(to: startLocation)
        let ranked = rankedKeys(to: location)
        guard normalized.count == 1,
              let emittedKey = nearestMatchingKey(label: normalized, location: startLocation, keys: keys),
              let startNearest = startRanked.first,
              let nearest = ranked.first else {
            return nil
        }

        let startLabel = startNearest.key.label.lowercased()
        let nearestLabel = nearest.key.label.lowercased()
        if startLabel != normalized {
            return stableTouchResolvedText(
                emitted: normalized,
                emittedKey: emittedKey,
                startNearest: startNearest,
                startSecondDistance: startRanked.dropFirst().first?.distance ?? CGFloat.greatestFiniteMagnitude,
                releaseNearest: nearest,
                releaseSecondDistance: ranked.dropFirst().first?.distance ?? CGFloat.greatestFiniteMagnitude
            )
        }

        guard nearestLabel.count == 1,
              nearestLabel != normalized,
              distance(from: emittedKey.center, to: nearest.key.center) <= maximumKeyCenterCorrectionDistance,
              nearest.distance <= maximumKeyDistance else {
            return nil
        }

        let secondDistance = ranked.dropFirst().first?.distance ?? CGFloat.greatestFiniteMagnitude
        if secondDistance < nearest.distance + minimumDistanceAdvantage {
            return nil
        }

        return nearestLabel
    }

    private func stableTouchResolvedText(
        emitted: String,
        emittedKey: HWKGlideKey,
        startNearest: (key: HWKGlideKey, distance: CGFloat),
        startSecondDistance: CGFloat,
        releaseNearest: (key: HWKGlideKey, distance: CGFloat),
        releaseSecondDistance: CGFloat
    ) -> String? {
        let label = startNearest.key.label.lowercased()
        guard label.count == 1,
              label != emitted,
              releaseNearest.key.label.lowercased() == label,
              startNearest.distance <= maximumKeyDistance,
              releaseNearest.distance <= maximumKeyDistance,
              startSecondDistance >= startNearest.distance + minimumDistanceAdvantage,
              releaseSecondDistance >= releaseNearest.distance + minimumDistanceAdvantage,
              startSecondDistance - startNearest.distance <= maximumStableMissclickDistanceAdvantage,
              releaseSecondDistance - releaseNearest.distance <= maximumStableMissclickDistanceAdvantage,
              distance(from: emittedKey.center, to: startNearest.key.center) <= maximumKeyCenterCorrectionDistance else {
            return nil
        }

        return label
    }

    func nearestText(location: CGPoint) -> String? {
        guard let nearestKey = nearestKey(to: location) else { return nil }
        let label = nearestKey.label.lowercased()
        let nearestDistance = distance(
            from: location,
            to: heatmap.adjustedCenter(for: label, fallbackCenter: nearestKey.center)
        )
        guard label.count == 1,
              nearestDistance <= maximumKeyDistance else {
            return nil
        }
        return label
    }

    private func nearestKey(to location: CGPoint) -> HWKGlideKey? {
        rankedKeys(to: location).first?.key
    }

    private func rankedKeys(to location: CGPoint) -> [(key: HWKGlideKey, distance: CGFloat)] {
        let rankedByFrame = keys
            .filter { $0.label.lowercased().count == 1 }
            .map { key in
                (
                    key: key,
                    distance: keyFrameDistance(from: location, to: key)
                )
            }
            .sorted { $0.distance < $1.distance }

        guard let frameHit = rankedByFrame
            .filter({ keyFrameContains(point: location, key: $0.key) })
            .sorted(by: {
                if $0.distance == $1.distance {
                    return keyCenterDistance(from: location, to: $0.key)
                        < keyCenterDistance(from: location, to: $1.key)
                }
                return $0.distance < $1.distance
            })
            .first else {
            return rankedByFrame
        }

        return [frameHit] + rankedByFrame.filter { $0.key != frameHit.key }
    }

    private func keyFrameContains(point: CGPoint, key: HWKGlideKey) -> Bool {
        guard let frame = key.frame else { return false }
        return frame.contains(point)
    }

    private func keyFrameDistance(from point: CGPoint, to key: HWKGlideKey) -> CGFloat {
        guard let frame = key.frame else {
            return keyCenterDistance(from: point, to: key)
        }
        if frame.contains(point) {
            return 0
        }

        let dx = max(frame.minX - point.x, 0, point.x - frame.maxX)
        let dy = max(frame.minY - point.y, 0, point.y - frame.maxY)
        return hypot(dx, dy)
    }

    private func keyCenterDistance(from point: CGPoint, to key: HWKGlideKey) -> CGFloat {
        distance(
            from: point,
            to: heatmap.adjustedCenter(for: key.label, fallbackCenter: key.center)
        )
    }

    private func distance(from point: CGPoint, to center: CGPoint) -> CGFloat {
        hypot(point.x - center.x, point.y - center.y)
    }
}

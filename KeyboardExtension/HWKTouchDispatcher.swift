import SwiftUI

struct HWKKeyFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

final class HWKKeyFrameRegistry: ObservableObject {
    var frames: [String: CGRect] = [:]
    let coordinateSpace = "hwc-key-frames"

    func keyID(at point: CGPoint) -> String? {
        for (id, frame) in frames where frame.contains(point) {
            return id
        }
        return nil
    }
}

extension View {
    func keyFrame(keyID: String, in registry: HWKKeyFrameRegistry) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: HWKKeyFramePreferenceKey.self,
                    value: [keyID: geometry.frame(in: .named(registry.coordinateSpace))]
                )
            }
        )
    }
}

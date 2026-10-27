import SwiftUI
import UIKit

@MainActor
final class HWCEasterEggHost: UIHostingController<HWCFlappyMiniGame> {
    private let model: HWCFlappyMiniGameModel
    private var disabledSiblingViews = [UIView]()

    init(onClose: @escaping () -> Void) {
        let model = HWCFlappyMiniGameModel()
        self.model = model
        super.init(rootView: HWCFlappyMiniGame(model: model, onClose: onClose))
        view.backgroundColor = .clear
        view.isOpaque = false
        view.isUserInteractionEnabled = true
    }

    @MainActor
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addAsOverlay(to parent: UIViewController) {
        parent.addChild(self)
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.view.addSubview(view)
        disabledSiblingViews = parent.view.subviews.filter { $0 !== view && $0.isUserInteractionEnabled }
        disabledSiblingViews.forEach { $0.isUserInteractionEnabled = false }
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: parent.view.topAnchor),
            view.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: parent.view.bottomAnchor),
        ])
        didMove(toParent: parent)
    }

    func removeOverlay() {
        model.stop()
        disabledSiblingViews.forEach { $0.isUserInteractionEnabled = true }
        disabledSiblingViews.removeAll()
        willMove(toParent: nil)
        view.removeFromSuperview()
        removeFromParent()
    }

    func handle(key: UIKey) {
        guard key.keyCode == .keyboardSpacebar else { return }
        model.flap()
    }

    func pause() {
        model.pause()
    }

    func resume() {
        model.resume()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.resume()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.pause()
    }
}

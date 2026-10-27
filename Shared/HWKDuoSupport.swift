import SwiftUI
import UIKit

/// Device-local capability evidence, deliberately excluded from settings sync/backup payloads.
/// The companion can establish support even if the keyboard host does not deliver hinge updates.
@MainActor
final class HWKDuoSupport: ObservableObject {
    static let shared = HWKDuoSupport()
    private static let evidenceKey = "device.duo.hingeVerifiedModel"
    @Published private(set) var isSupported: Bool
    // Live state only: a persisted fold angle would be stale when another app hosts the keyboard.
    private var isPartiallyOpen: Bool?
    #if DEBUG
    private var lastDiagnostic: String?
    #endif

    private static var modelIdentifier: String {
        #if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
        #else
        var info = utsname()
        uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
        #endif
    }

    private init() {
        let model = Self.modelIdentifier
        isSupported = UIDevice.current.userInterfaceIdiom == .phone && !model.isEmpty
            && KeyboardSharedPreferences.defaults.string(forKey: Self.evidenceKey) == model
    }

    func refresh() {
        let model = Self.modelIdentifier
        if UIDevice.current.userInterfaceIdiom == .phone, !model.isEmpty,
           KeyboardSharedPreferences.defaults.string(forKey: Self.evidenceKey) == model {
            isSupported = true
        }
    }

    @discardableResult
    func observe(in view: UIView, onUpdate: @escaping () -> Void = {}) -> () -> Void {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] interaction, update in
                guard let self else { return }
                #if DEBUG
                let owner = interaction.view.map { String(describing: type(of: $0)) } ?? "detached"
                NSLog("HWC Hinge callback view=%@ attached=%d status=%ld", owner,
                      interaction.view?.window != nil ? 1 : 0, update.hinge?.status.rawValue ?? -1)
                #endif
                self.isPartiallyOpen = update.hinge.map { $0.status == .partiallyOpen }
                if update.hinge != nil, UIDevice.current.userInterfaceIdiom == .phone {
                    let model = Self.modelIdentifier
                    if !model.isEmpty {
                        KeyboardSharedPreferences.defaults.set(model, forKey: Self.evidenceKey)
                        self.isSupported = true
                    }
                }
                onUpdate()
            }
            // Re-enabling requests the current state when the attached hierarchy provides it.
            interaction.isEnabled = false
            view.addInteraction(interaction)
            interaction.isEnabled = true
            return { [weak self, weak view, weak interaction] in
                self?.isPartiallyOpen = nil
                guard let interaction else { return }
                interaction.isEnabled = false
                view?.removeInteraction(interaction)
            }
        }
        #endif
        return {}
    }

    func shouldAutomaticallySplit(in view: UIView) -> Bool {
        #if DEBUG
        traceFoldSignal(in: view)
        #endif
        guard UIDevice.current.userInterfaceIdiom == .phone else { return false }
        if let isPartiallyOpen { return isPartiallyOpen }
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            // Some keyboard hosts expose the division without forwarding hinge interactions.
            // Query active regions only; includeInactive would also split a fully open Duo.
            let hasDivision = view.reservedRegions(kind: .division).contains {
                $0.frame.height > $0.frame.width && $0.frame.intersects(view.bounds)
            }
            if hasDivision, !isSupported {
                let model = Self.modelIdentifier
                if !model.isEmpty {
                    KeyboardSharedPreferences.defaults.set(model, forKey: Self.evidenceKey)
                    isSupported = true
                }
            }
            return hasDivision && isSupported
        }
        #endif
        return false
    }

    #if DEBUG
    private func traceFoldSignal(in view: UIView) {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            var ancestors: [String] = []
            var current: UIView? = view
            while let node = current {
                let active = node.reservedRegions(kind: .division).count
                let all = node.reservedRegions(kind: .division, options: [.includeInactive]).count
                ancestors.append("\(type(of: node))=\(active)/\(all)")
                current = node.superview
            }
            let diagnostic = "HWC Fold supported=\(isSupported) partial=\(String(describing: isPartiallyOpen)) divisions(active/all)=\(ancestors.joined(separator: ",")) attached=\(view.window != nil)"
            if diagnostic != lastDiagnostic {
                lastDiagnostic = diagnostic
                NSLog("%@", diagnostic)
            }
        }
        #endif
    }
    #endif

    /// A vertical division can enlarge the user-requested split without chasing hinge angle noise.
    func divisionWidth(in view: UIView) -> CGFloat {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return view.reservedRegions(kind: .division, options: [.includeInactive])
                .filter { $0.frame.height > $0.frame.width && $0.frame.intersects(view.bounds) }
                .map { $0.frame.width } // UIKit's frame already includes its margins.
                .max() ?? 0
        }
        #endif
        return 0
    }
}

struct HWKDuoHingeObserver: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        HWKDuoSupport.shared.observe(in: view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

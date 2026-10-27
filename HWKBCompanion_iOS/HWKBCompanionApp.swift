import SwiftUI
import Foundation

@main
struct HWKBCompanionApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var setupDeepLinkRequestAt = 0.0
    @State private var hardwareLabDeepLinkRequestAt = 0.0
    @State private var pendingKeymapImportURL: URL?
    @State private var remoteConfigRefreshTask: Task<Void, Never>?

    var body: some Scene {
        WindowGroup {
            rootView
                .onAppear {
                    refreshRemoteConfigIfNeeded(force: true)
                    HWCEncryptedCloudSnapshotController.shared.reconcileNow()
                    openHardwareLabFromAutomationIfNeeded()
                }
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == HWKKeymapTransferDocument.fileExtension {
                        pendingKeymapImportURL = url
                        return
                    }
                    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          components.scheme == "hwc" else { return }

                    if components.host == "setup" || components.path == "/setup" {
                        setupDeepLinkRequestAt = Date().timeIntervalSince1970
                    } else if components.host == "hardware-lab" || components.path == "/hardware-lab" {
                        hardwareLabDeepLinkRequestAt = Date().timeIntervalSince1970
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        refreshRemoteConfigIfNeeded()
                        HWCEncryptedCloudSnapshotController.shared.reconcileNow()
                    }
                }
        }
    }

    private var rootView: some View {
        companionHome
    }

    private var companionHome: some View {
        CompanionHomeView(
            setupDeepLinkRequestAt: $setupDeepLinkRequestAt,
            hardwareLabDeepLinkRequestAt: $hardwareLabDeepLinkRequestAt,
            pendingKeymapImportURL: $pendingKeymapImportURL
        )
    }

    private func refreshRemoteConfigIfNeeded(force: Bool = false) {
        guard let coordinator = HWKRemoteConfigRefreshCoordinator.configuredForCompanionApp() else {
            return
        }

        remoteConfigRefreshTask?.cancel()
        remoteConfigRefreshTask = Task {
            guard !Task.isCancelled else { return }
            _ = await coordinator.refresh(force: force)
        }
    }

    private func openHardwareLabFromAutomationIfNeeded() {
        #if HWC_INTERNAL_BUILD || HWC_HARDWARE_CAPTURE
        guard ProcessInfo.processInfo.environment["HWK_AUTOMATION_OPEN_HARDWARE_LAB"] == "1" else { return }
        hardwareLabDeepLinkRequestAt = Date().timeIntervalSince1970
        #endif
    }
}

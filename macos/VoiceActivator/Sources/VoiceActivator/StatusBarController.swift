import AppKit
import Combine
import Foundation
import SwiftUI

/// Owns the NSStatusItem. Kept as a singleton because there is only ever one
/// menu bar icon for the app and we want it addressable from any code path
/// (e.g. the Settings window's "reveal in Finder" actions).
@MainActor
final class StatusBarController {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var hostingView: NSHostingView<AnyView>?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func install(
        supervisor: ProcessSupervisor,
        backend: BackendClient,
        settings: SettingsStore
    ) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = item

        // The icon is bound to supervisor.statusIconName so SwiftUI updates
        // flow into AppKit's status bar button.
        item.button?.imagePosition = .imageOnly

        // Build the SwiftUI menu content. We re-publish to drive the menu
        // by simply replacing the menu on the status item whenever the
        // supervisor state changes — AppKit re-renders.
        let root = AnyView(
            MenuContentView()
                .environmentObject(supervisor)
                .environmentObject(backend)
                .environmentObject(settings)
        )

        // Build a host view that renders nothing visible — the menu bar
        // icon is the only persistent UI. The hosting view is what
        // allows us to read `supervisor.statusIconName` (an @Published
        // value) and keep NSStatusItem.button.image in sync.
        let host = NSHostingView(rootView: root)
        host.frame = .zero
        self.hostingView = host

        // Observe icon name and re-apply to NSStatusItem button.
        supervisor.$statusIconName
            .receive(on: RunLoop.main)
            .sink { [weak self] name in
                self?.applyIcon(name: name)
            }
            .store(in: &cancellables)

        supervisor.$menuState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshMenu(supervisor: supervisor, backend: backend, settings: settings)
            }
            .store(in: &cancellables)

        applyIcon(name: supervisor.statusIconName)
        refreshMenu(supervisor: supervisor, backend: backend, settings: settings)

        // Click behaviour: a normal left click opens the menu (the default).
        item.button?.target = self
        item.button?.action = #selector(handleClick(_:))
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        // Default behaviour: status item shows its menu. Action just exists
        // so the button is not "disabled".
    }

    private func applyIcon(name: String) {
        guard let button = statusItem?.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Voice Module") {
            image.isTemplate = true
            button.image = image.withSymbolConfiguration(config)
        } else {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Voice Module")
        }
    }

    private func refreshMenu(
        supervisor: ProcessSupervisor,
        backend: BackendClient,
        settings: SettingsStore
    ) {
        let view = MenuContentView()
            .environmentObject(supervisor)
            .environmentObject(backend)
            .environmentObject(settings)

        let host = NSHostingController(rootView: AnyView(view))
        host.view.frame = NSRect(x: 0, y: 0, width: 280, height: 1)

        let menu = NSMenu()
        let menuItem = NSMenuItem()
        menuItem.view = host.view
        menu.addItem(menuItem)

        statusItem?.menu = menu
    }
}

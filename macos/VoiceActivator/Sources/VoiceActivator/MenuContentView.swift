import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject var supervisor: ProcessSupervisor
    @EnvironmentObject var backend: BackendClient
    @EnvironmentObject var settings: SettingsStore

    @State private var settingsWindowOpen: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Status line
            HStack(spacing: 8) {
                Image(systemName: supervisor.statusIconName)
                    .imageScale(.medium)
                    .foregroundColor(iconTint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Module")
                        .font(.system(size: 13, weight: .semibold))
                    Text(supervisor.menuState.label)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)

            Divider()

            // ── Backend / Client health
            HStack {
                statusDot(for: supervisor.backend)
                Text("Backend: \(label(for: supervisor.backend))")
                    .font(.system(size: 11))
                Spacer()
            }
            HStack {
                statusDot(for: supervisor.client)
                Text("Client: \(label(for: supervisor.client))")
                    .font(.system(size: 11))
                Spacer()
            }

            Divider()

            // ── Actions
            HStack(spacing: 6) {
                Button("Start") {
                    Task { await handleStart() }
                }
                .disabled(!canStart)

                Button("Stop") {
                    Task { await handleStop() }
                }
                .disabled(!canStop)

                Button("Restart") {
                    Task { await handleRestart() }
                }
                .disabled(!canRestart)
            }
            .controlSize(.small)

            Divider()

            // ── Settings / Open / Quit
            Button("Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                SettingsWindowController.shared.show()
            }
            Button("Open Logs") {
                openInFinder(AppPaths.logDir)
            }
            Button("Open Config Folder") {
                openInFinder(AppPaths.pythonConfigDir)
            }

            Divider()

            Button("Quit Voice Module") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 280)
    }

    // MARK: - Status helpers

    private var iconTint: Color {
        switch supervisor.menuState {
        case .idle: return .blue
        case .listening: return .red
        case .transcribing: return .orange
        case .error: return .red
        case .offline: return .gray
        }
    }

    private func statusDot(for state: Any) -> some View {
        let color = dotColor(for: state)
        return Circle().fill(color).frame(width: 6, height: 6)
    }

    private func dotColor(for state: Any) -> Color {
        if let b = state as? BackendProcessState {
            return b.dotColor
        }
        if let c = state as? ClientProcessState {
            return c.dotColor
        }
        return .gray
    }

    private func label(for state: Any) -> String {
        if let b = state as? BackendProcessState { return b.shortLabel }
        if let c = state as? ClientProcessState { return c.shortLabel }
        return "unknown"
    }

    // MARK: - Buttons enable/disable

    private var canStart: Bool {
        let backendDown = supervisor.backend != .running
        let clientDown = supervisor.client != .running
        return backendDown || clientDown
    }

    private var canStop: Bool {
        return supervisor.backend == .running || supervisor.client == .running
    }

    private var canRestart: Bool {
        return supervisor.backend == .running || supervisor.client == .running
    }

    // MARK: - Actions

    private func handleStart() async {
        if supervisor.backend != .running {
            try? await supervisor.startBackend()
        }
        if supervisor.client != .running {
            try? await supervisor.startClient()
        }
    }

    private func handleStop() async {
        if supervisor.client == .running {
            try? supervisor.stopClient()
        }
        if supervisor.backend == .running {
            await supervisor.stopBackend()
        }
    }

    private func handleRestart() async {
        await supervisor.restartBackend()
        do {
            try await supervisor.restartClient()
        } catch {
            LogStore.shared.error("Restart client failed: \(error.localizedDescription)")
        }
    }

    private func openInFinder(_ url: URL) {
        // If the dir doesn't exist, create it (config dir) so the user lands
        // somewhere sensible.
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}

import AppKit
import SwiftUI

/// Singleton controller for the Settings window. We use AppKit's NSWindow
/// directly rather than `WindowGroup` / `openWindow` because we need a single
/// instance (the user clicking "Settings…" twice should not spawn two
/// windows) and we want a fixed lifecycle tied to the app delegate.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private init() {}

    func show(supervisor: ProcessSupervisor? = nil,
              backend: BackendClient? = nil,
              settings: SettingsStore? = nil) {
        // Reuse environment objects from the AppDelegate if not provided.
        let appDelegate = NSApp.delegate as? AppDelegate
        let resolvedSupervisor = supervisor ?? appDelegate?.supervisor
        let resolvedBackend = backend ?? appDelegate?.backend
        let resolvedSettings = settings ?? appDelegate?.settings

        guard let s = resolvedSupervisor,
              let b = resolvedBackend,
              let st = resolvedSettings else {
            LogStore.shared.error("SettingsWindowController.show: missing environment objects.")
            return
        }

        if window == nil {
            let view = SettingsView()
                .environmentObject(s)
                .environmentObject(b)
                .environmentObject(st)
            let host = NSHostingController(rootView: view)
            host.view.frame = NSRect(x: 0, y: 0, width: 520, height: 460)

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.title = "Voice Module — Settings"
            win.contentViewController = host
            win.isReleasedWhenClosed = false
            win.center()
            self.window = win
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @EnvironmentObject var supervisor: ProcessSupervisor
    @EnvironmentObject var backend: BackendClient
    @EnvironmentObject var settings: SettingsStore

    @State private var capturedHotkey: Hotkey?
    @State private var actions: [Action] = []
    @State private var loadError: String? = nil
    @State private var notificationStatus: String = "checking"
    @State private var launchAtLoginStatus: String = "checking"
    @State private var refreshToggle: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // ── Header
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .imageScale(.large)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading) {
                    Text("Voice Module Settings").font(.headline)
                    Text("Changes save to the backend (127.0.0.1:8080).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Form {
                Section("Readiness") {
                    HStack {
                        Button("Refresh") {
                            AppDiagnostics.invalidatePythonDepsCache()
                            // Force re-evaluation of all readiness checks
                            refreshToggle.toggle()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                    }
                    ReadinessRow(label: "Hotkey registered", ok: supervisor.hotkeyRegistered)
                    ReadinessRow(label: "Microphone", ok: AppDiagnostics.microphoneStatus == "granted")
                    ReadinessRow(label: "Backend healthy", ok: supervisor.backend == .running)
                    ReadinessRow(label: "Worker ready", ok: supervisor.workerReady)
                    ReadinessRow(label: "Python deps", ok: AppDiagnostics.pythonDepsStatus() == "OK")
                }

                Section("Hotkey") {
                    HStack(alignment: .center, spacing: 12) {
                        KeyCaptureView(
                            hotkey: $capturedHotkey,
                            placeholder: "Click then press a hotkey..."
                        )
                        .frame(width: 220, height: 36)
                        VStack(alignment: .leading) {
                            Text("Current: \(settings.hotkey)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("At least one modifier required.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .onChange(of: capturedHotkey) { new in
                        if let hk = new {
                            settings.hotkey = hk.encode()
                        }
                    }
                }

                Section("Mode") {
                    Picker("Activation", selection: $settings.mode) {
                        Text("Hold (push-to-talk)").tag("hold")
                        Text("Toggle (press to start, again to stop)").tag("toggle")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Action") {
                    Picker("Action to run on transcription", selection: $settings.action) {
                        if actions.isEmpty {
                            Text("Loading…").tag(settings.action)
                        }
                        ForEach(actions) { a in
                            Text(actionLabel(a)).tag(a.name)
                        }
                    }
                    if let err = loadError {
                        Text("Could not load actions: \(err)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section("Status") {
                    LabeledContent("Backend") { Text(pretty(supervisor.backend)) }
                    LabeledContent("Client") { Text(pretty(supervisor.client)) }
                    LabeledContent("Menu state") { Text(supervisor.menuState.label) }
                    LabeledContent("Repo root") {
                        Text(supervisor.repoRoot?.path ?? "unknown")
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Section("Permissions") {
                    LabeledContent("Accessibility") {
                        Text(AppDiagnostics.accessibilityTrusted ? "granted" : "missing")
                            .foregroundColor(AppDiagnostics.accessibilityTrusted ? .green : .orange)
                    }
                    LabeledContent("Microphone") {
                        Text(AppDiagnostics.microphoneStatus)
                    }
                    LabeledContent("Notifications") {
                        Text(notificationStatus)
                    }
                    HStack {
                        Button("Open Accessibility Settings") {
                            AppDiagnostics.openAccessibilitySettings()
                        }
                        Button("Open Microphone Settings") {
                            AppDiagnostics.openMicrophoneSettings()
                        }
                        Button("Run Diagnostics") {
                            Task { await refreshDiagnostics() }
                        }
                    }
                    if !AppDiagnostics.accessibilityTrusted {
                        Text("Some paste/automation actions may require granting Accessibility to VoiceActivator.app.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Section("Startup") {
                    LabeledContent("Launch at login") {
                        Text(launchAtLoginStatus)
                    }
                    HStack {
                        Button("Enable") {
                            setLaunchAtLogin(true)
                        }
                        Button("Disable") {
                            setLaunchAtLogin(false)
                        }
                    }
                }

                Section("Logs") {
                    LabeledContent("Menu bar log") {
                        Text(AppPaths.logFile.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Client log dir") {
                        Text(AppPaths.pythonLogDir.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    HStack {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.open(AppPaths.logDir)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            // ── Footer
            HStack {
                if let err = settings.saveError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                } else if settings.saveSuccessAt != nil {
                    Text("Saved.")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Spacer()
                }
                Spacer()
                Button("Cancel") { NSApp.keyWindow?.performClose(nil) }
                Button("Save") {
                    Task { await saveAndRestartClient() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.isSaving || !settings.isDirty)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 460)
        .task {
            await refreshActions()
            await refreshDiagnostics()
        }
    }

    // MARK: - Helpers

    private func refreshActions() async {
        do {
            actions = try await backend.fetchActions()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func saveAndRestartClient() async {
        do {
            try await settings.save(using: backend)
        } catch {
            settings.markSaveError(error.localizedDescription)
            return
        }

        do {
            try await supervisor.restartClient()
            try supervisor.configureHotkeyFromCurrentSettings()
            settings.markSaveSuccess()
            LogStore.shared.log("Settings saved and client restarted.")
        } catch {
            settings.markSaveError("Saved, but client restart failed: \(error.localizedDescription)")
            LogStore.shared.error("Client restart after settings save failed: \(error.localizedDescription)")
        }
    }

    private func refreshDiagnostics() async {
        notificationStatus = await AppDiagnostics.notificationStatus()
        if #available(macOS 13.0, *) {
            launchAtLoginStatus = AppDiagnostics.launchAtLoginStatus
        } else {
            launchAtLoginStatus = "unsupported"
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                try AppDiagnostics.setLaunchAtLogin(enabled)
                launchAtLoginStatus = AppDiagnostics.launchAtLoginStatus
            } catch {
                launchAtLoginStatus = "error: \(error.localizedDescription)"
            }
        } else {
            launchAtLoginStatus = "unsupported"
        }
    }

    private func actionLabel(_ a: Action) -> String {
        if let d = a.description, !d.isEmpty { return "\(a.name) — \(d)" }
        return "\(a.name) (\(a.type))"
    }

    private func pretty(_ state: Any) -> String {
        if let b = state as? BackendProcessState { return b.shortLabel }
        if let c = state as? ClientProcessState { return c.shortLabel }
        return "unknown"
    }
}

// MARK: - Readiness Row

private struct ReadinessRow: View {
    let label: String
    let ok: Bool

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(ok ? .green : .red)
                Text(ok ? "Ready" : "Missing")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

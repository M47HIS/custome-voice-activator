import Combine
import Foundation
import SwiftUI

/// UI-facing settings model. The local Python config is authoritative so the
/// menu-bar app continues to work without a Docker backend.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var hotkey: String = BackendSettings.default.hotkey
    @Published var mode: String = BackendSettings.default.mode  // "hold" | "toggle"
    @Published var action: String = BackendSettings.default.action
    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil
    @Published var saveSuccessAt: Date? = nil

    /// Whether local state diverges from the last saved local configuration.
    var isDirty: Bool {
        BackendSettings(hotkey: hotkey, mode: mode, action: action) != snapshot
    }

    private var snapshot: BackendSettings = .default
    private var feedbackResetTask: Task<Void, Never>?

    func apply(remote: BackendSettings) {
        hotkey = remote.hotkey
        mode = remote.mode
        action = "clipboard"
        snapshot = BackendSettings(hotkey: remote.hotkey, mode: remote.mode, action: "clipboard")
    }

    func revert() {
        hotkey = snapshot.hotkey
        mode = snapshot.mode
        action = snapshot.action
    }

    func load() {
        guard let data = try? Data(contentsOf: AppPaths.pythonConfigFile),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            apply(remote: .default)
            return
        }
        let loaded = BackendSettings(
            hotkey: object["hotkey"] as? String ?? BackendSettings.default.hotkey,
            mode: object["mode"] as? String ?? BackendSettings.default.mode,
            action: "clipboard"
        )
        apply(remote: loaded)
    }

    func save() throws {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let payload = BackendSettings(hotkey: hotkey, mode: mode, action: action)
        do {
            AppPaths.ensureDirectories()
            var document: [String: Any] = [:]
            if let data = try? Data(contentsOf: AppPaths.pythonConfigFile),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                document = existing
            }
            document["hotkey"] = payload.hotkey
            document["mode"] = payload.mode
            document["action"] = payload.action
            let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: AppPaths.pythonConfigFile, options: .atomic)
            snapshot = payload
            LogStore.shared.log("Settings saved locally.")
        } catch {
            markSaveError(error.localizedDescription)
            LogStore.shared.error("Local settings save failed: \(error.localizedDescription)")
            throw error
        }
    }

    func markSaveSuccess() {
        saveSuccessAt = Date()
        saveError = nil
        scheduleFeedbackReset()
    }

    func markSaveError(_ message: String) {
        saveError = message
        saveSuccessAt = nil
        scheduleFeedbackReset()
    }

    private func scheduleFeedbackReset() {
        feedbackResetTask?.cancel()
        feedbackResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveError = nil
            self?.saveSuccessAt = nil
        }
    }
}

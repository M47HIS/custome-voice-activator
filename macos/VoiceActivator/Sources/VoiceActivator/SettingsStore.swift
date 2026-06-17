import Combine
import Foundation
import SwiftUI

/// UI-facing settings model. The source of truth lives in the backend; this
/// store mirrors it and is the binding target for the Settings window.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var hotkey: String = BackendSettings.default.hotkey
    @Published var mode: String = BackendSettings.default.mode  // "hold" | "toggle"
    @Published var action: String = BackendSettings.default.action
    @Published var isSaving: Bool = false
    @Published var saveError: String? = nil
    @Published var saveSuccessAt: Date? = nil

    /// Whether local state diverges from the backend.
    var isDirty: Bool {
        BackendSettings(hotkey: hotkey, mode: mode, action: action) != snapshot
    }

    private var snapshot: BackendSettings = .default

    func apply(remote: BackendSettings) {
        hotkey = remote.hotkey
        mode = remote.mode
        action = remote.action
        snapshot = remote
    }

    func revert() {
        hotkey = snapshot.hotkey
        mode = snapshot.mode
        action = snapshot.action
    }

    func save(using backend: BackendClient) async throws {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let payload = BackendSettings(hotkey: hotkey, mode: mode, action: action)
        do {
            try await backend.saveSettings(payload)
            snapshot = payload
            LogStore.shared.log("Settings saved to backend.")
        } catch {
            saveError = error.localizedDescription
            LogStore.shared.error("Save settings failed: \(error.localizedDescription)")
            throw error
        }
    }

    func markSaveSuccess() {
        saveSuccessAt = Date()
        saveError = nil
    }

    func markSaveError(_ message: String) {
        saveError = message
        saveSuccessAt = nil
    }
}

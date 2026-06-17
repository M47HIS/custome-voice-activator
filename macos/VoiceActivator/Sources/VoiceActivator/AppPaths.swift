import Foundation

/// Centralized filesystem paths the app touches. All paths are resolved
/// against standard macOS locations so the app respects sandboxing and
/// user-expected conventions.
enum AppPaths {
    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("VoiceModule", isDirectory: true)
    }()

    static let authTokenFile: URL = appSupportDir.appendingPathComponent("auth_token")
    static let voiceClientPIDFile: URL = appSupportDir.appendingPathComponent("voice_client.pid")

    static let logDir: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base.appendingPathComponent("Logs/VoiceModule", isDirectory: true)
    }()

    static let logFile: URL = logDir.appendingPathComponent("menu-bar.log")

    /// ~/.config/voice-module — owned by the Python client. We open it via
    /// the "Open Config Folder" menu item so users can inspect config.json.
    static let pythonConfigDir: URL = {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/voice-module", isDirectory: true)
    }()

    /// ~/.local/log/voice-module — Python client logs.
    static let pythonLogDir: URL = {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".local/log/voice-module", isDirectory: true)
    }()

    @discardableResult
    static func ensureDirectories() -> Bool {
        let fm = FileManager.default
        for dir in [appSupportDir, logDir] {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                NSLog("Failed to create %@: %@", dir.path, error.localizedDescription)
                return false
            }
        }
        return true
    }

    /// Walk up from a starting directory looking for `docker-compose.yml`.
    /// Returns the directory containing the file, or nil if not found.
    static func findRepoRoot(from start: URL) -> URL? {
        var url = start.standardizedFileURL
        let fm = FileManager.default
        // Hard cap at 8 levels to avoid runaway traversal on weird paths.
        for _ in 0..<8 {
            let candidate = url.appendingPathComponent("docker-compose.yml")
            if fm.fileExists(atPath: candidate.path) {
                return url
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            url = parent
        }
        return nil
    }
}

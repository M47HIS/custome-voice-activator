import AppKit
import AVFoundation
import Combine
import Darwin
import Foundation
import SwiftUI

// MARK: - Process lifecycle

enum BackendProcessState: Equatable {
    case unknown
    case stopped
    case starting
    case running
    case error(String)

    var dotColor: Color {
        switch self {
        case .running: return .green
        case .stopped: return .gray
        case .starting: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }

    var shortLabel: String {
        switch self {
        case .running: return "running"
        case .stopped: return "stopped"
        case .starting: return "starting…"
        case .error(let msg): return "error: \(msg)"
        case .unknown: return "unknown"
        }
    }
}

enum ClientProcessState: Equatable {
    case unknown
    case stopped
    case starting
    case running
    case error(String)

    var dotColor: Color {
        switch self {
        case .running: return .green
        case .stopped: return .gray
        case .starting: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }

    var shortLabel: String {
        switch self {
        case .running: return "running"
        case .stopped: return "stopped"
        case .starting: return "starting…"
        case .error(let msg): return "error: \(msg)"
        case .unknown: return "unknown"
        }
    }
}

enum MenuState: Equatable {
    case idle
    case listening
    case loadingModel
    case transcribing
    case success
    case error(String)
    case offline

    var iconName: String {
        switch self {
        case .idle: return "waveform.circle"
        case .listening: return "waveform.circle.fill"
        case .loadingModel: return "arrow.down.circle"
        case .transcribing: return "waveform.path.ecg"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .offline: return "xmark.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .listening: return "Recording…"
        case .loadingModel: return "Loading local model…"
        case .transcribing: return "Transcribing"
        case .success: return "Copied to clipboard"
        case .error(let msg): return "Error: \(msg)"
        case .offline: return "Offline"
        }
    }

    var tint: Color {
        switch self {
        case .idle: return .accentColor
        case .listening, .error: return .red
        case .loadingModel, .transcribing: return .orange
        case .success: return .green
        case .offline: return .secondary
        }
    }

    var showsOverlay: Bool {
        switch self {
        case .idle, .offline: return false
        case .listening, .loadingModel, .transcribing, .success, .error: return true
        }
    }

    var isTransient: Bool {
        switch self {
        case .success, .error: return true
        default: return false
        }
    }
}

private struct BackendRunner {
    let executable: String
    let leadingArgs: [String]
    let label: String

    var displayCommand: String {
        ([executable] + leadingArgs).joined(separator: " ")
    }

    static func resolve() -> BackendRunner {
        let candidates: [(path: String, args: [String], label: String)] = [
            ("/usr/local/bin/docker", ["compose"], "Docker"),
            ("/opt/homebrew/bin/docker", ["compose"], "Docker"),
            ("/Applications/Docker.app/Contents/Resources/bin/docker", ["compose"], "Docker Desktop"),
            ("/Applications/OrbStack.app/Contents/MacOS/xbin/docker", ["compose"], "OrbStack Docker"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return BackendRunner(
                executable: candidate.path,
                leadingArgs: candidate.args,
                label: candidate.label
            )
        }
        return BackendRunner(
            executable: "/usr/bin/env",
            leadingArgs: ["docker", "compose"],
            label: "docker from PATH"
        )
    }
}

private final class WorkerLineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    func append(_ data: Data) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if let text = String(data: line, encoding: .utf8), !text.isEmpty {
                lines.append(text)
            }
        }
        return lines
    }
}

private final class ProcessOutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

private final class ProcessCompletion: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<Void, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

@MainActor
final class ProcessSupervisor: ObservableObject {
    // Published state
    @Published private(set) var backend: BackendProcessState = .unknown
    @Published private(set) var client: ClientProcessState = .unknown
    @Published private(set) var menuState: MenuState = .offline
    @Published private(set) var statusIconName: String = "waveform.circle"
    @Published private(set) var repoRoot: URL? = nil
    @Published var hotkeyRegistered: Bool = false
    @Published var workerReady: Bool = false

    // Wiring
    private var backendClient: BackendClient?
    private var settingsStore: SettingsStore?

    private let backendRunner = BackendRunner.resolve()
    nonisolated static func resolvedPythonPath() -> String {
        if FileManager.default.isExecutableFile(atPath: AppPaths.pythonVirtualEnvExecutable.path) {
            return AppPaths.pythonVirtualEnvExecutable.path
        }
        let candidates = [
            "/opt/homebrew/opt/python@3.11/libexec/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/bin/python3"
    }
    private let pythonExecutable = ProcessSupervisor.resolvedPythonPath()

    private var clientProcess: Process?
    private var workerInput: Pipe?
    private var workerOutput: Pipe?
    private var webSocketTask: Task<Void, Never>?
    private var transientStateTask: Task<Void, Never>?
    private var bootstrapComplete = false
    private let hotkeyManager = HotkeyManager()
    private let audioRecorder = AudioRecorder()
    private var registeredHotkey: Hotkey?

    func attach(backend: BackendClient, settings: SettingsStore) {
        self.backendClient = backend
        self.settingsStore = settings
    }

    // MARK: - Bootstrap

    /// Called once on app launch. The native worker is the product path;
    /// Docker remains an explicit optional integration.
    func bootstrap() async {
        guard let settingsStore else {
            LogStore.shared.error("Supervisor bootstrap called before attach().")
            return
        }

        // Locate the repo root. We walk up from the executable looking for
        // docker-compose.yml.
        let execURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        if let root = AppPaths.findRepoRoot(from: execURL) {
            self.repoRoot = root
            LogStore.shared.log("Repo root resolved: \(root.path)")
        } else if let envRoot = ProcessInfo.processInfo.environment["VOICE_MODULE_REPO"],
                  FileManager.default.fileExists(atPath: envRoot + "/docker-compose.yml") {
            self.repoRoot = URL(fileURLWithPath: envRoot)
            LogStore.shared.log("Repo root from env: \(envRoot)")
        } else {
            self.repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            LogStore.shared.warn("Could not locate repo root via docker-compose.yml; using CWD.")
        }

        backend = .stopped
        settingsStore.load()
        do {
            try configureHotkey(from: settingsStore)
        } catch {
            LogStore.shared.error("Could not register native hotkey: \(error.localizedDescription)")
        }

        do {
            try await startClient()
        } catch {
            LogStore.shared.error("Client start failed: \(error.localizedDescription). Try starting manually from the menu.")
        }

        bootstrapComplete = true
        refreshMenuState()
    }

    func requestShutdown() {
        LogStore.shared.log("Shutting down...")
        webSocketTask?.cancel()
        backendClient?.stopStatusPolling()
        backendClient?.disconnectWebSocket()
        try? stopClient()
        hotkeyManager.unregister()
    }

    // MARK: - Settings

    func configureHotkeyFromCurrentSettings() throws {
        guard let settingsStore else {
            throw NSError(domain: "ProcessSupervisor", code: 20, userInfo: [NSLocalizedDescriptionKey: "Settings store unavailable."])
        }
        try configureHotkey(from: settingsStore)
    }

    private func configureHotkey(from store: SettingsStore) throws {
        let hotkey = try Hotkey.parse(store.hotkey)
        hotkeyManager.onPressed = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if store.mode == "toggle" {
                    if self.audioRecorder.isRecording {
                        self.finishRecording()
                    } else {
                        await self.beginRecording()
                    }
                } else {
                    await self.beginRecording()
                }
            }
        }
        hotkeyManager.onReleased = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if store.mode == "hold" {
                    self.finishRecording()
                }
            }
        }
        let previous = registeredHotkey
        do {
            try hotkeyManager.register(hotkey)
        } catch {
            if let previous { try? hotkeyManager.register(previous) }
            throw error
        }
        registeredHotkey = hotkey
        hotkeyRegistered = true
        LogStore.shared.log("Registered native hotkey: \(store.hotkey) mode=\(store.mode)")
    }

    private func beginRecording() async {
        guard client == .running, workerReady else {
            setMenuState(.error("Local worker is not ready"))
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            setMenuState(granted ? .idle : .error("Microphone permission is required"))
            return
        case .denied, .restricted:
            setMenuState(.error("Microphone permission is required"))
            return
        case .authorized:
            break
        @unknown default:
            setMenuState(.error("Microphone permission is unavailable"))
            return
        }

        do {
            try audioRecorder.startRecording()
            setMenuState(.listening)
            LogStore.shared.log("Started native audio recording.")
        } catch {
            setMenuState(.error("Could not start recording: \(error.localizedDescription)"))
            LogStore.shared.error("Native audio recording failed: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard let url = audioRecorder.stopRecording() else {
            if menuState == .listening {
                setMenuState(.error("No audio was captured"))
            }
            return
        }

        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard bytes > 44 else {
            try? FileManager.default.removeItem(at: url)
            setMenuState(.error("No audio was captured; check Microphone access"))
            LogStore.shared.error("Recorded WAV was empty (\(bytes) bytes).")
            return
        }

        setMenuState(.transcribing)
        sendWorkerJSON(["type": "transcribe_file", "path": url.path])
        LogStore.shared.log("Sent \(bytes)-byte recording for transcription: \(url.path)")
    }

    private func setMenuState(_ state: MenuState) {
        transientStateTask?.cancel()
        menuState = state
        statusIconName = state.iconName
        guard state.isTransient else { return }

        let delay: UInt64 = state == .success ? 1_500_000_000 : 3_000_000_000
        transientStateTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled, self.menuState == state else { return }
            self.setMenuState(self.client == .running ? .idle : .offline)
        }
    }

    // MARK: - Backend (Docker)

    func startBackend() async throws {
        guard let root = repoRoot else {
            throw NSError(domain: "ProcessSupervisor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Repo root unknown."])
        }

        let composeFile = root.appendingPathComponent("docker-compose.yml").path

        backend = .starting
        LogStore.shared.log("Starting backend via \(backendRunner.displayCommand) up -d --build...")

        do {
            try await runProcess(
                executable: backendRunner.executable,
                args: backendRunner.leadingArgs + ["-f", composeFile, "up", "-d", "--build"],
                env: nil,
                description: "docker compose up"
            )
        } catch {
            backend = .error("Start failed: \(error.localizedDescription)")
            refreshMenuState()
            throw error
        }

        // Wait for /api/status to respond (poll).
        let healthy = await waitForBackendReady(timeoutSeconds: 60)
        if healthy {
            backend = .running
            LogStore.shared.log("Backend is healthy.")
        } else {
            backend = .error("Backend did not become healthy within 60s.")
            LogStore.shared.error("Backend health check timed out.")
        }
        refreshMenuState()
    }

    func stopBackend() async {
        guard let root = repoRoot else { return }
        let composeFile = root.appendingPathComponent("docker-compose.yml").path
        LogStore.shared.log("Stopping backend (docker compose stop)...")
        do {
            try await runProcess(
                executable: backendRunner.executable,
                args: backendRunner.leadingArgs + ["-f", composeFile, "stop", "voice-backend"],
                env: nil,
                description: "docker compose stop"
            )
            backend = .stopped
        } catch {
            LogStore.shared.error("Stop backend failed: \(error.localizedDescription)")
            backend = .error("Stop failed: \(error.localizedDescription)")
        }
        refreshMenuState()
    }

    func restartBackend() async {
        guard let root = repoRoot else { return }
        let composeFile = root.appendingPathComponent("docker-compose.yml").path
        LogStore.shared.log("Restarting backend...")
        do {
            try await runProcess(
                executable: backendRunner.executable,
                args: backendRunner.leadingArgs + ["-f", composeFile, "restart", "voice-backend"],
                env: nil,
                description: "docker compose restart"
            )
            let healthy = await waitForBackendReady(timeoutSeconds: 60)
            backend = healthy ? .running : .error("Restart timed out.")
        } catch {
            backend = .error("Restart failed: \(error.localizedDescription)")
        }
        refreshMenuState()
    }

    private func waitForBackendReady(timeoutSeconds: Int) async -> Bool {
        guard let backendClient else { return false }
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Date() < deadline {
            do {
                let status = try await backendClient.fetchStatus()
                LogStore.shared.log("Backend reachable. state=\(status.state)")
                return true
            } catch {
                // Not yet — sleep and retry.
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    // MARK: - Client (Python)

    func startClient() async throws {
        if clientProcess != nil {
            LogStore.shared.log("Client already running (pid=\(clientProcess!.processIdentifier))")
            return
        }
        if let pid = readClientPID(), isProcessRunning(pid) {
            LogStore.shared.log("Stopping existing voice client before starting worker (pid=\(pid)).")
            kill(pid, SIGTERM)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if isProcessRunning(pid) {
                kill(pid, SIGKILL)
            }
            clearClientPID()
        }

        guard let scriptURL = AppPaths.workerScript(repoRoot: repoRoot) else {
            client = .error("voice_client.py not found in the app bundle or repository")
            refreshMenuState()
            throw NSError(domain: "ProcessSupervisor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Client script missing."])
        }
        let script = scriptURL.path

        client = .starting
        LogStore.shared.log("Starting Python client with \(pythonExecutable): \(script)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonExecutable)
        proc.arguments = pythonExecutable == "/usr/bin/env" ? ["python3", script, "--worker"] : [script, "--worker"]
        proc.currentDirectoryURL = scriptURL.deletingLastPathComponent()

        // Worker stdout is JSON events consumed by the menu-bar app. Stderr
        // keeps normal Python logging.
        let logDir = AppPaths.pythonLogDir
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let errFile = logDir.appendingPathComponent("client-supervisor.err.log")
        if !FileManager.default.fileExists(atPath: errFile.path) {
            FileManager.default.createFile(atPath: errFile.path, contents: nil)
        }
        let errHandle = try? FileHandle(forWritingTo: errFile)
        _ = try? errHandle?.seekToEnd()

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        proc.standardInput = inputPipe
        proc.standardOutput = outputPipe
        proc.standardError = errHandle
        self.workerInput = inputPipe
        self.workerOutput = outputPipe
        installWorkerOutputHandler(outputPipe)

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self else { return }
                let reason: String
                if p.terminationReason == .exit {
                    reason = "exited (\(p.terminationStatus))"
                } else {
                    reason = "terminated"
                }
                LogStore.shared.warn("Client process \(reason).")
                self.clearClientPID(ifMatches: p.processIdentifier)
                if self.clientProcess?.processIdentifier == p.processIdentifier {
                    self.clientProcess = nil
                }
                self.workerInput = nil
                self.workerOutput?.fileHandleForReading.readabilityHandler = nil
                self.workerOutput = nil
                self.client = .stopped
                self.refreshMenuState()
            }
        }

        do {
            try proc.run()
        } catch {
            client = .error("Failed to launch: \(error.localizedDescription)")
            refreshMenuState()
            throw error
        }

        self.clientProcess = proc
        writeClientPID(proc.processIdentifier)
        client = .running
        LogStore.shared.log("Python worker started (pid=\(proc.processIdentifier))")
        refreshMenuState()
    }

    func stopClient() throws {
        if let proc = clientProcess, proc.isRunning {
            sendWorkerCommand("shutdown")
            proc.terminate()
            // Give it a moment, then SIGKILL if still alive.
            Thread.sleep(forTimeInterval: 1.5)
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
        } else if let pid = readClientPID(), isProcessRunning(pid) {
            LogStore.shared.log("Stopping client from PID file (pid=\(pid)).")
            kill(pid, SIGTERM)
            Thread.sleep(forTimeInterval: 1.5)
            if isProcessRunning(pid) {
                kill(pid, SIGKILL)
            }
        }
        clientProcess = nil
        workerInput = nil
        workerOutput?.fileHandleForReading.readabilityHandler = nil
        workerOutput = nil
        clearClientPID()
        client = .stopped
        LogStore.shared.log("Client stopped.")
        refreshMenuState()
    }

    func restartClient() async throws {
        do {
            try stopClient()
        } catch {
            LogStore.shared.error("Stop during restart failed: \(error.localizedDescription)")
            throw error
        }
        // Brief settle delay.
        try? await Task.sleep(nanoseconds: 500_000_000)
        try await startClient()
    }

    private func readClientPID() -> pid_t? {
        guard let text = try? String(contentsOf: AppPaths.voiceClientPIDFile, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0 else {
            return nil
        }
        return pid
    }

    private func writeClientPID(_ pid: pid_t) {
        AppPaths.ensureDirectories()
        do {
            try "\(pid)\n".write(to: AppPaths.voiceClientPIDFile, atomically: true, encoding: .utf8)
        } catch {
            LogStore.shared.warn("Could not write client PID file: \(error.localizedDescription)")
        }
    }

    private func clearClientPID() {
        try? FileManager.default.removeItem(at: AppPaths.voiceClientPIDFile)
    }

    private func clearClientPID(ifMatches pid: pid_t) {
        guard readClientPID() == pid else { return }
        clearClientPID()
    }

    private func isProcessRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private func sendWorkerCommand(_ type: String) {
        guard let data = "{\"type\":\"\(type)\"}\n".data(using: .utf8),
              let handle = workerInput?.fileHandleForWriting else {
            LogStore.shared.warn("Worker command ignored; worker input is unavailable: \(type)")
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            LogStore.shared.error("Could not send worker command \(type): \(error.localizedDescription)")
        }
    }

    private func sendWorkerJSON(_ dict: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(dict),
              var data = try? JSONSerialization.data(withJSONObject: dict),
              let handle = workerInput?.fileHandleForWriting else {
            LogStore.shared.warn("Worker JSON command ignored; worker input is unavailable.")
            return
        }
        data.append(0x0A) // newline terminator
        do {
            try handle.write(contentsOf: data)
        } catch {
            LogStore.shared.error("Could not send worker JSON: \(error.localizedDescription)")
        }
    }

    private func installWorkerOutputHandler(_ pipe: Pipe) {
        let lineBuffer = WorkerLineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for text in lineBuffer.append(data) {
                Task { @MainActor in
                    self?.handleWorkerEvent(text)
                }
            }
        }
    }

    private func handleWorkerEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            LogStore.shared.warn("Ignoring malformed worker event: \(text)")
            return
        }

        switch type {
        case "ready":
            client = .running
            workerReady = true
            LogStore.shared.log("Worker ready.")
        case "status":
            let state = json["state"] as? String ?? "idle"
            switch state {
            case "listening": setMenuState(.listening)
            case "transcribing": setMenuState(.transcribing)
            default:
                if case .error = menuState {
                    break
                }
                setMenuState(.idle)
            }
        case "model_loading":
            setMenuState(.loadingModel)
        case "transcribed":
            let text = json["text"] as? String ?? ""
            LogStore.shared.log("Worker transcribed \(text.count) characters.")
            setMenuState(text.isEmpty ? .error("No speech detected") : .success)
        case "action_done":
            let action = json["action"] as? String ?? "unknown"
            let ok = json["ok"] as? Bool ?? false
            LogStore.shared.log("Worker action \(action) completed ok=\(ok).")
            if !ok { setMenuState(.error("Could not copy transcript")) }
        case "error":
            let message = json["message"] as? String ?? "Worker error"
            setMenuState(.error(message))
            LogStore.shared.error("Worker error: \(message)")
        default:
            LogStore.shared.warn("Unknown worker event: \(text)")
        }
        refreshMenuState()
    }

    // MARK: - WebSocket listener

    private func listenForWebSocketStatus() {
        guard let backendClient else { return }
        webSocketTask?.cancel()
        webSocketTask = Task { @MainActor in
            // Try once; if it fails, the polling loop still keeps us informed.
            let stream = backendClient.connectWebSocket()
            for await message in stream {
                if Task.isCancelled { break }
                if case .string(let text) = message {
                    self.handleWebSocketText(text)
                }
            }
        }
    }

    private func handleWebSocketText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard let type = json["type"] as? String, type == "status" else { return }
        guard let state = json["state"] as? String else { return }
        switch state {
        case "listening": setMenuState(.listening)
        case "transcribing": setMenuState(.transcribing)
        case "idle":
            if case .error = menuState { return }
            setMenuState(.idle)
        default: setMenuState(.idle)
        }
    }

    // MARK: - Menu state derivation

    func refreshMenuState() {
        if case .error(let msg) = client {
            if case .error = menuState { return }
            setMenuState(.error(msg))
        } else if client == .running {
            if menuState == .offline { setMenuState(.idle) }
        } else if client != .starting {
            setMenuState(.offline)
        }
    }

    // MARK: - Process helper

    private func runProcess(
        executable: String,
        args: [String],
        env: [String: String]?,
        description: String,
        timeout: TimeInterval? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: executable)
            proc.arguments = args
            if let env { proc.environment = env }
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            let output = ProcessOutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    output.append(data)
                }
            }

            let completion = ProcessCompletion(cont)

            proc.terminationHandler = { p in
                pipe.fileHandleForReading.readabilityHandler = nil
                if let remaining = try? pipe.fileHandleForReading.readToEnd(), !remaining.isEmpty {
                    output.append(remaining)
                }
                if p.terminationStatus == 0 {
                    completion.resume(with: .success(()))
                } else {
                    let data = output.snapshot()
                    let msg = String(data: data, encoding: .utf8) ?? "exit \(p.terminationStatus)"
                    completion.resume(with: .failure(NSError(
                        domain: "ProcessSupervisor",
                        code: Int(p.terminationStatus),
                        userInfo: [NSLocalizedDescriptionKey: "\(description) failed: \(msg)"]
                    )))
                }
            }
            do {
                try proc.run()
            } catch {
                completion.resume(with: .failure(error))
                return
            }

            if let timeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    guard proc.isRunning else { return }
                    proc.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if proc.isRunning {
                            kill(proc.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }
}

import Foundation

/// Spawns the `fin` CLI in JSONL mode and streams decoded events back on the
/// main queue. Owns the process's stdin so approval decisions can be written.
final class FinRunner {
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()

    /// Called for each decoded event, on the main queue.
    var onEvent: ((FinEvent) -> Void)?
    /// Called when the process exits, on the main queue.
    var onExit: (() -> Void)?

    var isRunning: Bool { process?.isRunning ?? false }

    /// Locate the fin binary. Prefers PATH (resolved via a login shell) and
    /// falls back to common install locations.
    static func resolveFinPath() -> String {
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v fin"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        if (try? shell.run()) != nil {
            shell.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
                FileManager.default.isExecutableFile(atPath: s) {
                return s
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for candidate in [
            "\(home)/.local/share/go/bin/fin",
            "\(home)/go/bin/fin",
            "/opt/homebrew/bin/fin",
            "/usr/local/bin/fin",
        ] where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "fin"
    }

    /// The user's login-shell environment, captured once. GUI apps launched by
    /// launchd don't inherit the shell profile (and thus miss API keys), so we
    /// source it from an interactive login shell.
    static let loginEnvironment: [String: String] = {
        let fallback = ProcessInfo.processInfo.environment
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "env"]
        let pipe = Pipe()
        shell.standardOutput = pipe
        shell.standardError = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return fallback }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        guard let raw = String(data: data, encoding: .utf8) else { return fallback }

        var env: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let eq = line.firstIndex(of: "=") else { continue }
            env[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return env.isEmpty ? fallback : env
    }()

    /// Start a fin turn. `continueSession` chains onto the previous session.
    func start(prompt: String, continueSession: Bool, model: String?) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.resolveFinPath())

        // No -approve override: fin uses the approval mode from its config
        // (settings.approve + per-tool approval), prompting via the JSONL
        // approval events whenever the config asks for confirmation.
        var args = ["-ui", "json"]
        if continueSession { args.append("-c") }
        if let model, !model.isEmpty { args += ["-m", model] }
        args.append(prompt)
        proc.arguments = args

        // Use the login-shell environment so provider API keys (exported in the
        // user's shell profile) are present even when launched as a .app, where
        // launchd hands us a minimal environment without them.
        proc.environment = Self.loginEnvironment

        let outPipe = Pipe()
        let inPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardInput = inPipe
        proc.standardError = errPipe
        stdinHandle = inPipe.fileHandleForWriting

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ingest(data)
        }

        // Surface stderr (retries, fatal errors) as error events.
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let s = String(data: data, encoding: .utf8),
                  !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            DispatchQueue.main.async {
                self?.onEvent?(FinEvent(t: "stderr", text: s, idx: nil, total: nil,
                                        name: nil, args: nil, result: nil, error: nil,
                                        line: nil, resumed: nil, label: nil,
                                        attempt: nil, max: nil))
            }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                self?.onExit?()
            }
        }

        self.process = proc
        do {
            try proc.run()
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(FinEvent(t: "error", text: "failed to launch fin: \(error.localizedDescription)",
                                        idx: nil, total: nil, name: nil, args: nil, result: nil,
                                        error: nil, line: nil, resumed: nil, label: nil,
                                        attempt: nil, max: nil))
                self?.onExit?()
            }
        }
    }

    /// Feed raw stdout bytes, splitting into newline-delimited JSON objects.
    private func ingest(_ data: Data) {
        buffer.append(data)
        let newline = UInt8(ascii: "\n")
        while let idx = buffer.firstIndex(of: newline) {
            let lineData = buffer.subdata(in: buffer.startIndex..<idx)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard !lineData.isEmpty else { continue }
            if let event = try? JSONDecoder().decode(FinEvent.self, from: lineData) {
                DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
            }
        }
    }

    /// Answer a pending approval request.
    func respondToApproval(approve: Bool) {
        guard let stdinHandle else { return }
        let reply = "{\"approve\":\(approve)}\n"
        if let data = reply.data(using: .utf8) {
            try? stdinHandle.write(contentsOf: data)
        }
    }

    /// Terminate the running process (used when the user cancels / starts anew).
    func cancel() {
        process?.terminate()
    }
}

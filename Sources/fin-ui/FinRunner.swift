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

    /// How a turn chains onto prior conversation.
    enum Continuation {
        case fresh                // brand new session
        case last                 // continue the most recent session (-c)
        case session(String)      // continue a specific session (-s <id>)

        var args: [String] {
            switch self {
            case .fresh: return []
            case .last: return ["-c"]
            case .session(let id): return ["-s", id]
            }
        }
    }

    /// Start a fin turn.
    func start(prompt: String, continuation: Continuation, model: String?) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.resolveFinPath())

        // No -approve override: fin uses the approval mode from its config
        // (settings.approve + per-tool approval), prompting via the JSONL
        // approval events whenever the config asks for confirmation.
        var args = ["-ui", "json"] + continuation.args
        // Tag every session started from fin-ui so the picker only shows our own.
        // For .fresh this tags the new session; for .last it filters to our last one.
        if case .session = continuation { } else { args += ["-tag", "fin-ui"] }
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

    /// Load a session by reading its JSONL file directly (no fin spawn). The
    /// first line is the header; each remaining line is one message. Completion
    /// runs on the main queue.
    func loadSession(url: URL,
                     completion: @escaping (_ id: String?, _ title: String?, _ messages: [LoadedMessage]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url) else {
                DispatchQueue.main.async { completion(nil, nil, []) }
                return
            }
            let dec = JSONDecoder()
            let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)

            var sid: String?
            var title: String?
            var parsed: [ExportedMessage] = []
            for (i, line) in lines.enumerated() {
                if i == 0 {
                    if let h = try? dec.decode(SessionHeader.self, from: Data(line)) {
                        sid = h.id
                        title = h.title
                    }
                    continue
                }
                if let m = try? dec.decode(ExportedMessage.self, from: Data(line)) {
                    parsed.append(m)
                }
            }

            // Index tool results (role "tool") by their tool_call_id.
            var results: [String: String] = [:]
            for m in parsed where m.role == "tool" {
                if let id = m.toolCallID { results[id] = m.content }
            }

            var loaded: [LoadedMessage] = []
            for m in parsed {
                let role: ChatMessage.Role
                switch m.role {
                case "user": role = .user
                case "assistant": role = .assistant
                default: continue // tool results consumed above; skip system
                }
                let text = (m.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let tools: [LoadedTool] = (m.toolCalls ?? []).map { tc in
                    LoadedTool(name: tc.name,
                               args: Self.decodeArgs(tc.arguments),
                               result: results[tc.id])
                }
                guard !text.isEmpty || !tools.isEmpty else { continue }
                loaded.append(LoadedMessage(role: role, text: text, tools: tools))
            }
            DispatchQueue.main.async { completion(sid, title, loaded) }
        }
    }

    /// Decode a tool call's raw JSON argument string into a display map.
    private static func decodeArgs(_ raw: String) -> [String: JSONValue] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data)
        else { return [:] }
        return obj
    }

    /// List the most recent sessions by reading each JSONL file's header line.
    /// Runs off the main thread; completion runs on the main queue.
    func listSessions(limit: Int,
                      completion: @escaping ([SessionSummary]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = Self.loginEnvironment["HOME"] ?? NSHomeDirectory()
            let dir = URL(fileURLWithPath: home)
                .appendingPathComponent(".local/share/fin/sessions")
            let fm = FileManager.default
            let urls = (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles])) ?? []

            let recent = urls
                .filter { $0.pathExtension == "jsonl" }
                .map { url -> (URL, Date) in
                    let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
                    return (url, d)
                }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)

            var result: [SessionSummary] = []
            for (url, mtime) in recent {
                guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? handle.close() }
                // The header is the small first line; the system prompt (huge)
                // is the second, so a bounded read is enough.
                let chunk = (try? handle.read(upToCount: 8192)) ?? Data()
                guard let nl = chunk.firstIndex(of: 0x0A) else { continue }
                let headerData = chunk.subdata(in: chunk.startIndex..<nl)
                guard let h = try? JSONDecoder().decode(SessionHeader.self, from: headerData)
                else { continue }
                guard h.tags?.contains("fin-ui") == true else { continue }
                let title = (h.title?.isEmpty == false) ? h.title! : h.id
                result.append(SessionSummary(id: h.id, title: title, date: mtime, url: url))
            }
            DispatchQueue.main.async { completion(result) }
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

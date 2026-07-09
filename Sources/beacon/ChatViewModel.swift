import Foundation
import SwiftUI
import Combine

/// Drives the Spotlight window: owns the transcript, the running fin process,
/// and delegates approval and session tracking to focused sub-objects.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isBusy: Bool = false
    @Published var statusText: String?
    /// True while the startup auto-resume check is in flight; the view stays
    /// at full height during this window so there's no expansion flash.
    @Published var isResolvingAutoResume: Bool = false
    /// Bumped on every content-changing event so the view can auto-scroll
    /// (SpotlightView doesn't otherwise observe nested message updates).
    @Published var streamTick: Int = 0

    private let runner: FinRunner
    private let sessionManager: SessionManager
    private(set) var approval: ApprovalModel

    private var currentAssistant: ChatMessage?
    /// The text block currently being streamed. Reset when a tool starts or the
    /// block ends, so the next text after a tool becomes a fresh ordered segment
    /// rather than being appended to the previous block.
    private var currentTextSegment: TextSegment?
    private var activeTools: [Int: ToolCall] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        let r = FinRunner()
        let sm = SessionManager(runner: r)
        let ap = ApprovalModel(runner: r)
        runner = r
        sessionManager = sm
        approval = ap

        // Forward approval changes so the view refreshes.
        ap.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        runner.onEvent = { [weak self] event in self?.handle(event) }
        runner.onExit = { [weak self] in self?.finishTurn() }

        if let url = SessionManager.cachedResumeURL() {
            isResolvingAutoResume = true
            isBusy = true
            statusText = "loading chat…"
            loadSessionFromURL(url, fallbackID: nil)
        }
    }

    /// Called on launch. Loads the most recent session automatically if it had
    /// activity within the last 5 minutes and the user hasn't explicitly started
    /// a new chat more recently than that session's last message.
    func autoResumeIfNeeded() {
        listSessions { [weak self] sessions in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let recent = sessions.first else { return }
                guard recent.date > Date().addingTimeInterval(-5 * 60) else { return }
                let d = UserDefaults.standard
                if d.object(forKey: "fin.chat.lastExplicitNewChat") != nil {
                    let newChatTime = Date(timeIntervalSinceReferenceDate: d.double(forKey: "fin.chat.lastExplicitNewChat"))
                    if newChatTime > recent.date { return }
                }
                self.loadSession(recent)
            }
        }
    }

    var canSubmit: Bool { !isBusy }

    func submit(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistant = ChatMessage(role: .assistant, streaming: true)
        messages.append(assistant)
        currentAssistant = assistant
        currentTextSegment = nil
        activeTools = [:]
        isBusy = true
        statusText = nil

        let continuation = sessionManager.continuation
        runner.start(prompt: trimmed, continuation: continuation, model: AppSettings.shared.selectedModel.isEmpty ? nil : AppSettings.shared.selectedModel)
    }

    /// Fetch the recent session list for the picker.
    func listSessions(_ completion: @escaping @Sendable ([SessionSummary]) -> Void) {
        sessionManager.listSessions(limit: 50, completion: completion)
    }

    /// Load a session (from the picker) into the transcript by reading its file
    /// directly. Follow-ups continue it.
    func loadSession(_ summary: SessionSummary) {
        guard !isBusy else { return }
        isBusy = true
        statusText = "loading chat…"
        sessionManager.recordSessionURL(summary.url)
        loadSessionFromURL(summary.url, fallbackID: summary.id)
    }

    private func loadSessionFromURL(_ url: URL, fallbackID: String?) {
        sessionManager.loadSession(url: url) { [weak self] sid, title, loaded in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.isBusy = false
                self.isResolvingAutoResume = false
                guard !loaded.isEmpty else {
                    self.statusText = "could not load chat"
                    return
                }
                self.messages = loaded.map { lm in
                    // User turns keep plain text; assistant turns are rebuilt as
                    // ordered segments (text block, if any, then its tool calls —
                    // the order fin persists them in an assistant message).
                    let msg = ChatMessage(role: lm.role,
                                          text: lm.role == .user ? lm.text : "")
                    if lm.role == .assistant {
                        if !lm.text.isEmpty {
                            msg.segments.append(.text(TextSegment(lm.text)))
                        }
                        for (i, lt) in lm.tools.enumerated() {
                            let tool = ToolCall(index: i, name: lt.name, args: lt.args)
                            tool.running = false
                            tool.result = lt.result
                            msg.segments.append(.tool(tool))
                        }
                    }
                    return msg
                }
                self.sessionManager.applyLoadedSession(id: sid ?? fallbackID)
                self.statusText = title
                self.streamTick &+= 1
            }
        }
    }

    /// Reset the window for a brand-new conversation.
    func newChat() {
        guard !isBusy else { return }
        sessionManager.clearForNewChat()
        messages.removeAll()
        currentAssistant = nil
        currentTextSegment = nil
        activeTools = [:]
        approval.clear()
        statusText = nil
    }

    func cancel() {
        runner.cancel()
    }

    // MARK: - Event handling

    private func handle(_ event: FinEvent) {
        defer { streamTick &+= 1 }
        switch event.t {
        case "text":
            if let text = event.text { appendText(text) }

        case "end":
            // A text block ended; the next text starts a fresh ordered segment.
            currentTextSegment = nil

        case "tool_start":
            guard let idx = event.idx, idx >= 0, let name = event.name else { return }
            let tool = ToolCall(index: idx, name: name, args: event.args ?? [:])
            activeTools[idx] = tool
            currentAssistant?.segments.append(.tool(tool))
            // Any text after this tool belongs to a new block below it.
            currentTextSegment = nil

        case "tool_output":
            if let idx = event.idx, let tool = activeTools[idx] {
                tool.outputLines = event.total ?? tool.outputLines
            }

        case "tool_done":
            if let idx = event.idx, let tool = activeTools[idx] {
                tool.running = false
                tool.result = event.result
                tool.errorText = event.error
            }

        case "approval":
            if let name = event.name {
                approval.set(ApprovalRequest(name: name, args: event.args ?? [:]))
            }

        case "session":
            if let label = event.label, !label.isEmpty {
                statusText = event.resumed == true ? "continuing \(label)" : label
            }

        case "retry":
            let a = event.attempt ?? 0
            let m = event.max ?? 0
            statusText = "retrying (\(a)/\(m))…"

        case "info":
            statusText = event.text

        case "error", "stderr":
            let msg = (event.text ?? event.error ?? "unknown error")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !msg.isEmpty else { return }
            if currentAssistant != nil {
                let seg = ensureTextSegment()
                let prefix = seg?.text.isEmpty == false ? "\n\n" : ""
                seg?.text += "\(prefix)> ⚠️ \(msg)"
            } else {
                statusText = msg
            }

        default:
            break
        }
    }

    /// Append a streamed text delta to the current block, opening one if needed.
    private func appendText(_ text: String) {
        ensureTextSegment()?.text += text
    }

    /// The open text block, creating and appending it to the current assistant
    /// turn if none is active. Returns nil if there's no assistant turn.
    @discardableResult
    private func ensureTextSegment() -> TextSegment? {
        guard let assistant = currentAssistant else { return nil }
        if let seg = currentTextSegment { return seg }
        let seg = TextSegment()
        assistant.segments.append(.text(seg))
        currentTextSegment = seg
        return seg
    }

    private func finishTurn() {
        currentAssistant?.streaming = false
        currentAssistant = nil
        currentTextSegment = nil
        isBusy = false
        sessionManager.markTurnDone()
        approval.clear()
    }
}

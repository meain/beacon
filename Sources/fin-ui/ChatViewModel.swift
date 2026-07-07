import Foundation
import SwiftUI

/// Drives the Spotlight window: owns the transcript, the running fin process,
/// and the pending approval state.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var pendingApproval: ApprovalRequest?
    @Published var isBusy: Bool = false
    @Published var statusText: String?
    /// When set for a fresh window, the first turn continues fin's last saved
    /// session instead of starting one-off. Default off.
    @Published var continuePrevious: Bool = false

    private let runner = FinRunner()
    private var currentAssistant: ChatMessage?
    private var activeTools: [Int: ToolCall] = [:]
    /// True once this window has completed at least one turn — subsequent turns
    /// chain onto it so the conversation flows naturally.
    private var hasHadTurn = false

    init() {
        runner.onEvent = { [weak self] event in self?.handle(event) }
        runner.onExit = { [weak self] in self?.finishTurn() }
    }

    var canSubmit: Bool { !isBusy }

    func submit(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isBusy else { return }

        messages.append(ChatMessage(role: .user, text: trimmed))
        let assistant = ChatMessage(role: .assistant, streaming: true)
        messages.append(assistant)
        currentAssistant = assistant
        activeTools = [:]
        isBusy = true
        statusText = nil

        let shouldContinue = hasHadTurn || continuePrevious
        runner.start(prompt: trimmed, continueSession: shouldContinue, model: nil)
    }

    /// Reset the window for a brand-new conversation.
    func newChat() {
        guard !isBusy else { return }
        messages.removeAll()
        currentAssistant = nil
        activeTools = [:]
        hasHadTurn = false
        pendingApproval = nil
        statusText = nil
    }

    func approve() {
        pendingApproval = nil
        runner.respondToApproval(approve: true)
    }

    func deny() {
        pendingApproval = nil
        runner.respondToApproval(approve: false)
    }

    func cancel() {
        runner.cancel()
    }

    // MARK: - Event handling

    private func handle(_ event: FinEvent) {
        switch event.t {
        case "text":
            if let text = event.text { currentAssistant?.text += text }

        case "end":
            break // A text block ended; the turn may continue with tools.

        case "tool_start":
            guard let idx = event.idx, idx >= 0, let name = event.name else { return }
            let tool = ToolCall(index: idx, name: name, args: event.args ?? [:])
            activeTools[idx] = tool
            currentAssistant?.tools.append(tool)

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
                pendingApproval = ApprovalRequest(name: name, args: event.args ?? [:])
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
            if let assistant = currentAssistant {
                let prefix = assistant.text.isEmpty ? "" : "\n\n"
                assistant.text += "\(prefix)> ⚠️ \(msg)"
            } else {
                statusText = msg
            }

        default:
            break
        }
    }

    private func finishTurn() {
        currentAssistant?.streaming = false
        currentAssistant = nil
        isBusy = false
        hasHadTurn = true
        pendingApproval = nil
    }
}

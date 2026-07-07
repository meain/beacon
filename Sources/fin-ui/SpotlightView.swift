import SwiftUI

/// The Spotlight-style panel: a prominent prompt field on top and a streaming
/// transcript below.
struct SpotlightView: View {
    @StateObject private var vm = ChatViewModel()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var showsTranscript: Bool {
        !vm.messages.isEmpty || vm.pendingApproval != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            promptBar
            if showsTranscript {
                Divider()
                transcript
            }
            footer
        }
        .frame(width: 680)
        // A fixed height once there's a conversation gives the ScrollView real
        // space to fill; otherwise the window sizes to the prompt bar alone.
        .frame(height: showsTranscript ? 540 : nil)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onAppear { inputFocused = true }
        // Esc denies a pending approval, otherwise closes the popup.
        .onExitCommand {
            if vm.pendingApproval != nil {
                vm.deny()
                inputFocused = true
            } else {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Prompt bar

    private var promptBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)

            TextField("Ask fin…", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 20, weight: .regular))
                .focused($inputFocused)
                .onSubmit(send)

            if vm.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(vm.messages) { message in
                        messageView(message).id(message.id)
                    }
                    if let approval = vm.pendingApproval {
                        ApprovalView(request: approval,
                                     onApprove: vm.approve,
                                     onDeny: vm.deny)
                            .id("approval")
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: vm.messages.last?.text) { scrollToBottom(proxy) }
            .onChange(of: vm.messages.count) { scrollToBottom(proxy) }
            .onChange(of: vm.pendingApproval?.id) { scrollToBottom(proxy) }
        }
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.system(size: 14))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }
        case .assistant:
            AssistantMessageView(message: message)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let status = vm.statusText {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if vm.messages.isEmpty {
                Toggle("Continue last chat (⌘L)", isOn: $vm.continuePrevious)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .background(
                        Button("") { vm.continuePrevious.toggle() }
                            .keyboardShortcut("l", modifiers: .command)
                            .opacity(0)
                    )
            } else {
                Button(action: vm.newChat) {
                    Label("New", systemImage: "square.and.pencil").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut("n", modifiers: .command)
                .disabled(vm.isBusy)
            }
            Text("⏎ send · esc close")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func send() {
        guard vm.canSubmit else { return }
        let prompt = input
        input = ""
        vm.submit(prompt)
        inputFocused = true
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.12)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

/// An assistant turn: streamed markdown plus any tool calls, in order.
struct AssistantMessageView: View {
    @ObservedObject var message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(message.tools) { tool in
                ToolCallView(tool: tool)
            }
            if !message.text.isEmpty {
                MarkdownView(markdown: message.text)
            } else if message.streaming && message.tools.isEmpty {
                Text("Thinking…")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

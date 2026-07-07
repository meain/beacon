import SwiftUI

/// The Spotlight-style panel: a prominent prompt field on top and a streaming
/// transcript below.
struct SpotlightView: View {
    @StateObject private var vm = ChatViewModel()
    @StateObject private var picker = PickerModel()
    @State private var input = ""
    @FocusState private var inputFocused: Bool

    private var showsTranscript: Bool {
        !vm.messages.isEmpty || vm.pendingApproval != nil
    }

    var body: some View {
        Group {
            if picker.visible {
                pickerOverlay
            } else {
                mainContent
            }
        }
        .frame(width: 680)
        // A fixed height when there's a conversation (or the picker is open)
        // gives the scroll area real space; otherwise size to the prompt bar.
        .frame(height: (showsTranscript || picker.visible) ? 540 : nil)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .background(
            // Global ⌘P — open the picker from any state.
            Button("") { openPicker() }
                .keyboardShortcut("p", modifiers: .command)
                .opacity(0)
        )
        .onAppear {
            inputFocused = true
            picker.onSelect = { session in
                inputFocused = true
                vm.loadSession(session)
            }
            picker.onCancel = { inputFocused = true }
        }
        .onExitCommand(perform: handleEscape)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            promptBar
            if showsTranscript {
                Divider()
                transcript
            }
            footer
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
                // Fires on launch and whenever we return from the picker, once
                // the field is actually back in the hierarchy.
                .onAppear { DispatchQueue.main.async { inputFocused = true } }

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
            .onChange(of: vm.streamTick) { scrollToBottom(proxy) }
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
                Button(action: openPicker) {
                    footerLabel("Previous chat", systemImage: "clock.arrow.circlepath", shortcut: "⌘P")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(vm.isBusy)
            } else {
                Button(action: vm.newChat) {
                    footerLabel("New", systemImage: "square.and.pencil", shortcut: "⌘N")
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

    /// A footer button label with its keyboard shortcut shown alongside.
    private func footerLabel(_ title: String, systemImage: String, shortcut: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title)
            Text(shortcut)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .font(.system(size: 11))
    }

    // MARK: - Previous-chat picker

    private var pickerOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("Go to previous chat")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                Text("↑↓ navigate · ⏎ open · esc cancel")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(picker.sessions.enumerated()), id: \.element.id) { i, session in
                            pickerRow(index: i, session: session)
                                .id(i)
                        }
                        if picker.sessions.isEmpty {
                            Text("No previous chats")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: picker.selection) {
                    withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(picker.selection) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickerRow(index: Int, session: SessionSummary) -> some View {
        HStack(spacing: 10) {
            Text(session.title)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 12)
            Text(Self.relativeFormatter.localizedString(for: session.date, relativeTo: Date()))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(index == picker.selection ? Color.accentColor.opacity(0.20) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture { picker.choose(index) }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func openPicker() {
        guard !vm.isBusy, !picker.visible else { return }
        inputFocused = false
        vm.listSessions { list in picker.show(list) }
    }

    private func handleEscape() {
        if picker.visible {
            picker.hide()
            inputFocused = true
        } else if vm.pendingApproval != nil {
            vm.deny()
            inputFocused = true
        } else {
            NSApplication.shared.terminate(nil)
        }
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

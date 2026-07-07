import SwiftUI

/// Inline card asking the user to approve or deny a tool call.
/// ⌘⏎ approves, Esc denies.
struct ApprovalView: View {
    let request: ApprovalRequest
    let onApprove: () -> Void
    let onDeny: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Approve \(request.name)?")
                    .font(settings.font(13, weight: .semibold))
            }

            if let arg = request.primaryArg {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(arg)
                        .font(settings.mono(12))
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxWidth: .infinity, maxHeight: 120, alignment: .leading)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 10) {
                Spacer()
                Text("⌘⏎ approve · esc deny")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button("Deny", role: .cancel, action: onDeny)
                Button("Approve", action: onApprove)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

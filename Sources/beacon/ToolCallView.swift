import SwiftUI

/// A compact row showing a tool invocation and its state.
struct ToolCallView: View {
    @ObservedObject var tool: ToolCall
    @ObservedObject private var settings = AppSettings.shared
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusIcon
                Text(tool.name)
                    .font(settings.mono(12, weight: .semibold))
                if let arg = tool.primaryArg {
                    Text(arg)
                        .font(settings.mono(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if hasDetail {
                    Button(action: { expanded.toggle() }) {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if expanded, let detail = detailText {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(detail)
                        .font(settings.mono(11.5))
                        .foregroundStyle(tool.errorText != nil ? .red : .primary)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 160)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(settings.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private var hasDetail: Bool { detailText?.isEmpty == false }

    private var detailText: String? {
        if let err = tool.errorText, !err.isEmpty { return err }
        if let old = tool.args["old_string"]?.displayString,
           let new = tool.args["new_string"]?.displayString {
            var text = "--- old\n\(old)\n\n+++ new\n\(new)"
            if let res = tool.result, !res.isEmpty { text += "\n\n" + res }
            return text
        }
        if let res = tool.result, !res.isEmpty { return res }
        return nil
    }

    @ViewBuilder
    private var statusIcon: some View {
        if tool.running {
            ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 14, height: 14)
        } else if tool.errorText != nil {
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.system(size: 12))
        } else {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
        }
    }
}

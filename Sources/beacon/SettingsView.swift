import AppKit
import SwiftUI

/// In-panel settings page (rendered as an overlay, like the previous-chat
/// picker — a separate window would make the borderless panel resign key and
/// close). Adjusts fonts and the accent color, and links out to fin's config
/// and docs. `onClose` returns to the transcript.
struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    let onClose: () -> Void

    /// fin's config file (a symlink is fine — the OS opens the target).
    private var finConfigPath: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".config/fin/config.toml")
    }

    private var accentBinding: Binding<Color> {
        Binding(get: { settings.accent }, set: { settings.setAccent($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    appearanceSection
                    finSection
                    HStack {
                        Spacer()
                        Button("Reset to defaults", action: settings.resetToDefaults)
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            // Esc closes settings. The borderless panel doesn't deliver Esc to
            // SwiftUI's onExitCommand without a focused text field, so register
            // it as a window-level key equivalent instead (same trick as ⌘P/⌘,).
            Button("", action: onClose)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            Text("Settings")
                .font(.system(size: 16, weight: .medium))
            Spacer()
            Text("esc close")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Button("Done", action: onClose)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Appearance")

            settingRow("Font") {
                Picker("", selection: $settings.fontFamily) {
                    Text("System").tag("")
                    Divider()
                    ForEach(AppSettings.fontFamilies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            settingRow("Mono font") {
                Picker("", selection: $settings.monoFontFamily) {
                    Text("System monospaced").tag("")
                    Divider()
                    ForEach(AppSettings.monoFontFamilies, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            settingRow("Text size") {
                HStack(spacing: 10) {
                    Slider(value: $settings.baseFontSize, in: 10...22, step: 1)
                        .frame(width: 180)
                    Text("\(Int(settings.baseFontSize))pt")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            settingRow("Accent") {
                HStack(spacing: 10) {
                    ColorPicker("", selection: accentBinding, supportsOpacity: false)
                        .labelsHidden()
                    if !settings.accentColorHex.isEmpty {
                        Button("Use system") { settings.accentColorHex = "" }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            // Live preview so choices are visible without leaving settings.
            // Pass nominal design sizes (font(_:) scales them by baseFontSize/14).
            VStack(alignment: .leading, spacing: 6) {
                Text("The quick brown fox").font(settings.font(14))
                Text("let answer = 42  // preview")
                    .font(settings.mono(12.5))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(settings.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.top, 2)
        }
    }

    // MARK: - fin links

    private var finSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("beacon")
            linkRow("Getting started", detail: "github.com/meain/beacon/blob/master/GETTING_STARTED.md",
                    systemImage: "book") {
                if let url = URL(string: "https://github.com/meain/beacon/blob/master/GETTING_STARTED.md") {
                    NSWorkspace.shared.open(url)
                }
            }
            linkRow("beacon on GitHub", detail: "github.com/meain/beacon",
                    systemImage: "square.and.arrow.up") {
                if let url = URL(string: "https://github.com/meain/beacon") {
                    NSWorkspace.shared.open(url)
                }
            }

            sectionTitle("fin")
            linkRow("Edit fin config", detail: "~/.config/fin/config.toml",
                    systemImage: "doc.text") {
                NSWorkspace.shared.open(URL(fileURLWithPath: finConfigPath))
            }
            linkRow("fin on GitHub", detail: "github.com/meain/fin",
                    systemImage: "square.and.arrow.up") {
                if let url = URL(string: "https://github.com/meain/fin") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.5)
    }

    private func settingRow<Content: View>(_ label: String,
                                           @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func linkRow(_ title: String, detail: String, systemImage: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(settings.accent)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13))
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

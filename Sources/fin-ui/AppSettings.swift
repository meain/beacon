import AppKit
import SwiftUI

/// User-adjustable appearance settings, persisted in UserDefaults and shared as
/// a singleton so every view can observe the same instance without plumbing.
/// Views read fonts through `font(_:)` / `mono(_:)` so a size or family change
/// re-flows the whole transcript uniformly.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// Proportional font family for prose. Empty = system default.
    @Published var fontFamily: String {
        didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) }
    }
    /// Monospaced font family for code / tool output. Empty = system monospaced.
    @Published var monoFontFamily: String {
        didSet { defaults.set(monoFontFamily, forKey: Keys.monoFontFamily) }
    }
    /// Base body size; every nominal size scales relative to this (default 14).
    @Published var baseFontSize: Double {
        didSet { defaults.set(baseFontSize, forKey: Keys.baseFontSize) }
    }
    /// Accent color as `#RRGGBB`. Empty = system accent.
    @Published var accentColorHex: String {
        didSet { defaults.set(accentColorHex, forKey: Keys.accentColorHex) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let fontFamily = "fin.font.family"
        static let monoFontFamily = "fin.font.mono"
        static let baseFontSize = "fin.font.size"
        static let accentColorHex = "fin.color.accent"
    }

    static let defaultSize: Double = 14

    private init() {
        fontFamily = defaults.string(forKey: Keys.fontFamily) ?? ""
        monoFontFamily = defaults.string(forKey: Keys.monoFontFamily) ?? ""
        let saved = defaults.double(forKey: Keys.baseFontSize)
        baseFontSize = saved == 0 ? Self.defaultSize : saved
        accentColorHex = defaults.string(forKey: Keys.accentColorHex) ?? ""
    }

    /// Scale applied to every nominal font size (the design was authored at 14pt).
    private var scale: CGFloat { CGFloat(baseFontSize) / CGFloat(Self.defaultSize) }

    /// A proportional font at `nominal` design size, scaled and in the chosen
    /// family. Falls back to the system font when unset or unresolvable.
    func font(_ nominal: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = nominal * scale
        guard resolvedFontFamily != nil else { return .system(size: size, weight: weight) }
        return .custom(fontFamily, size: size).weight(weight)
    }

    /// A monospaced font at `nominal` design size, scaled and in the chosen
    /// family. Falls back to the system monospaced font when unset/unresolvable.
    func mono(_ nominal: CGFloat, weight: Font.Weight = .regular) -> Font {
        let size = nominal * scale
        guard resolvedMonoFamily != nil else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(monoFontFamily, size: size).weight(weight)
    }

    /// The resolved prompt font as an `NSFont` (the input is an AppKit text view).
    func promptNSFont() -> NSFont {
        let size = 20 * scale
        if let family = resolvedFontFamily, let f = NSFont(name: family, size: size) { return f }
        return .systemFont(ofSize: size)
    }

    /// The chosen proportional family if set and installed, else nil (= system).
    private var resolvedFontFamily: String? {
        (!fontFamily.isEmpty && Self.fontFamilySet.contains(fontFamily)) ? fontFamily : nil
    }

    /// The chosen mono family if set and installed, else nil (= system mono).
    private var resolvedMonoFamily: String? {
        (!monoFontFamily.isEmpty && Self.monoFontFamilySet.contains(monoFontFamily)) ? monoFontFamily : nil
    }

    /// The chosen accent, or the system accent when none is set.
    var accent: Color {
        accentColorHex.isEmpty ? .accentColor : (Color(hex: accentColorHex) ?? .accentColor)
    }

    /// Store an accent color chosen via a picker (as `#RRGGBB`).
    func setAccent(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        accentColorHex = String(format: "#%02X%02X%02X", r, g, b)
    }

    func resetToDefaults() {
        fontFamily = ""
        monoFontFamily = ""
        baseFontSize = Self.defaultSize
        accentColorHex = ""
    }

    // MARK: - Available fonts

    /// All installed font families, for the family picker.
    static let fontFamilies: [String] = NSFontManager.shared.availableFontFamilies.sorted()

    /// Installed families whose default member is fixed-pitch, for the mono picker.
    static let monoFontFamilies: [String] = NSFontManager.shared.availableFontFamilies
        .filter { NSFont(name: $0, size: 12)?.isFixedPitch ?? false }
        .sorted()

    /// Membership sets for fast, allocation-free lookups during rendering.
    private static let fontFamilySet = Set(fontFamilies)
    private static let monoFontFamilySet = Set(monoFontFamilies)
}

extension Color {
    /// Parse a `#RRGGBB` (or `RRGGBB`) hex string.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

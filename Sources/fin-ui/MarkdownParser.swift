import SwiftUI

/// A block-level element parsed from markdown. Inline styling (bold, italic,
/// links, inline code) is handled downstream via AttributedString(markdown:).
enum MarkdownBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bulletList(items: [String])
    case orderedList(items: [String])
    case codeBlock(language: String, code: String)
    case blockquote(text: String)
    case rule

    var id: String {
        switch self {
        case .heading(let l, let t): return "h\(l):\(t)"
        case .paragraph(let t): return "p:\(t)"
        case .bulletList(let i): return "ul:\(i.joined())"
        case .orderedList(let i): return "ol:\(i.joined())"
        case .codeBlock(let lang, let c): return "code:\(lang):\(c)"
        case .blockquote(let t): return "q:\(t)"
        case .rule: return "hr:\(UUID().uuidString)"
        }
    }
}

enum MarkdownParser {
    /// Parse markdown into block elements. Tolerant of unterminated code fences
    /// (common while streaming) — the open fence is treated as a code block.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        func flushParagraph(_ buf: inout [String]) {
            if !buf.isEmpty {
                blocks.append(.paragraph(text: buf.joined(separator: "\n")))
                buf.removeAll()
            }
        }

        var paragraph: [String] = []

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") {
                flushParagraph(&paragraph)
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // skip closing fence (or EOF)
                blocks.append(.codeBlock(language: lang, code: code.joined(separator: "\n")))
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph(&paragraph)
                blocks.append(.rule); i += 1; continue
            }

            // Heading.
            if let hashes = headingLevel(trimmed) {
                flushParagraph(&paragraph)
                let text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: hashes, text: text))
                i += 1; continue
            }

            // Blockquote.
            if trimmed.hasPrefix(">") {
                flushParagraph(&paragraph)
                var quote: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    quote.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.blockquote(text: quote.joined(separator: "\n")))
                continue
            }

            // Bullet list.
            if isBullet(trimmed) {
                flushParagraph(&paragraph)
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(t.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Ordered list.
            if isOrdered(trimmed) {
                flushParagraph(&paragraph)
                var items: [String] = []
                while i < lines.count, isOrdered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let dot = t.firstIndex(of: ".") {
                        items.append(String(t[t.index(after: dot)...]).trimmingCharacters(in: .whitespaces))
                    }
                    i += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // Blank line ends a paragraph.
            if trimmed.isEmpty {
                flushParagraph(&paragraph)
                i += 1; continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph(&paragraph)
        return blocks
    }

    private static func headingLevel(_ s: String) -> Int? {
        guard s.hasPrefix("#") else { return nil }
        let count = s.prefix(while: { $0 == "#" }).count
        guard count <= 6, s.count > count, s[s.index(s.startIndex, offsetBy: count)] == " " else { return nil }
        return count
    }

    private static func isBullet(_ s: String) -> Bool {
        s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("+ ")
    }

    private static func isOrdered(_ s: String) -> Bool {
        guard let dot = s.firstIndex(of: ".") else { return false }
        let prefix = s[s.startIndex..<dot]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber)
    }

    /// Render inline markdown (bold, italic, code, links) to an AttributedString.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: text, options: options) {
            return attr
        }
        return AttributedString(text)
    }
}

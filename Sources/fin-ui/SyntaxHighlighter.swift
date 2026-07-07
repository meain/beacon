import SwiftUI

/// A small, dependency-free syntax highlighter. It tokenises source into
/// comments, strings, numbers, keywords and identifiers and colours them for
/// a light theme. Good enough for readable code blocks in the popup.
enum SyntaxHighlighter {

    // Light-theme palette.
    private static let commentColor = Color(red: 0.42, green: 0.47, blue: 0.53)
    private static let stringColor  = Color(red: 0.05, green: 0.52, blue: 0.20)
    private static let numberColor  = Color(red: 0.00, green: 0.36, blue: 0.75)
    private static let keywordColor = Color(red: 0.66, green: 0.13, blue: 0.55)
    private static let typeColor    = Color(red: 0.15, green: 0.35, blue: 0.70)
    private static let plainColor   = Color(red: 0.13, green: 0.14, blue: 0.16)

    static func highlight(_ code: String, language: String) -> AttributedString {
        let lang = language.lowercased()
        let keywords = keywordSet(for: lang)
        let hashComments = hashCommentLangs.contains(lang)

        var out = AttributedString()
        let chars = Array(code)
        var i = 0
        let n = chars.count

        func append(_ s: String, _ color: Color) {
            var piece = AttributedString(s)
            piece.foregroundColor = color
            out.append(piece)
        }

        func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" || c == "$" }
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" || c == "$" }

        while i < n {
            let c = chars[i]

            // Line comment: // ... or (for some langs) # ...
            if c == "/" && i + 1 < n && chars[i + 1] == "/" {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                append(String(chars[i..<j]), commentColor); i = j; continue
            }
            if hashComments && c == "#" {
                var j = i
                while j < n && chars[j] != "\n" { j += 1 }
                append(String(chars[i..<j]), commentColor); i = j; continue
            }
            // Block comment: /* ... */
            if c == "/" && i + 1 < n && chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n && !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, n)
                append(String(chars[i..<j]), commentColor); i = j; continue
            }
            // String / char literals.
            if c == "\"" || c == "'" || c == "`" {
                let quote = c
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == quote { j += 1; break }
                    j += 1
                }
                j = min(j, n)
                append(String(chars[i..<j]), stringColor); i = j; continue
            }
            // Numbers.
            if c.isNumber {
                var j = i
                while j < n && (chars[j].isNumber || chars[j] == "." || chars[j] == "x"
                    || chars[j] == "e" || (chars[j].isLetter && chars[j].isHexDigit)) { j += 1 }
                append(String(chars[i..<j]), numberColor); i = j; continue
            }
            // Identifiers / keywords.
            if isIdentStart(c) {
                var j = i
                while j < n && isIdent(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if keywords.contains(word) {
                    append(word, keywordColor)
                } else if let first = word.first, first.isUppercase {
                    append(word, typeColor)
                } else {
                    append(word, plainColor)
                }
                i = j; continue
            }

            append(String(c), plainColor); i += 1
        }
        return out
    }

    private static let hashCommentLangs: Set<String> = [
        "bash", "sh", "shell", "zsh", "python", "py", "ruby", "rb",
        "yaml", "yml", "toml", "makefile", "make", "dockerfile", "perl", "r",
    ]

    private static func keywordSet(for lang: String) -> Set<String> {
        switch lang {
        case "swift":
            return ["func", "let", "var", "if", "else", "for", "while", "return",
                    "struct", "class", "enum", "protocol", "extension", "import",
                    "guard", "switch", "case", "default", "in", "do", "try", "catch",
                    "throw", "throws", "async", "await", "self", "nil", "true", "false",
                    "public", "private", "internal", "static", "final", "init", "some", "any"]
        case "go", "golang":
            return ["func", "package", "import", "var", "const", "type", "struct",
                    "interface", "map", "chan", "go", "defer", "if", "else", "for",
                    "range", "return", "switch", "case", "default", "select", "nil",
                    "true", "false", "break", "continue", "goto", "fallthrough"]
        case "python", "py":
            return ["def", "class", "import", "from", "as", "if", "elif", "else",
                    "for", "while", "return", "yield", "try", "except", "finally",
                    "with", "lambda", "None", "True", "False", "and", "or", "not",
                    "in", "is", "pass", "break", "continue", "global", "async", "await"]
        case "js", "javascript", "ts", "typescript", "jsx", "tsx":
            return ["function", "const", "let", "var", "if", "else", "for", "while",
                    "return", "class", "extends", "import", "export", "from", "default",
                    "async", "await", "try", "catch", "finally", "throw", "new", "this",
                    "null", "undefined", "true", "false", "typeof", "instanceof",
                    "interface", "type", "enum", "public", "private", "readonly"]
        case "rust", "rs":
            return ["fn", "let", "mut", "if", "else", "for", "while", "loop", "match",
                    "return", "struct", "enum", "impl", "trait", "use", "mod", "pub",
                    "self", "Self", "async", "await", "move", "ref", "where", "as",
                    "true", "false", "None", "Some", "Ok", "Err"]
        case "c", "cpp", "c++", "objc":
            return ["int", "char", "float", "double", "void", "long", "short",
                    "unsigned", "signed", "struct", "union", "enum", "typedef", "static",
                    "const", "if", "else", "for", "while", "do", "switch", "case",
                    "default", "return", "break", "continue", "sizeof", "class",
                    "public", "private", "protected", "namespace", "template", "auto"]
        case "bash", "sh", "shell", "zsh":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                    "case", "esac", "function", "return", "in", "export", "local",
                    "echo", "exit", "cd", "set", "source"]
        case "json":
            return ["true", "false", "null"]
        default:
            return ["if", "else", "for", "while", "return", "function", "class",
                    "import", "true", "false", "null", "nil"]
        }
    }
}

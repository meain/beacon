import Foundation

// MARK: - Flexible JSON value

/// A minimal JSON value used to decode arbitrary tool argument objects
/// coming from fin's JSONL stream.
enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    /// A human-readable single-line rendering, used for compact display.
    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            if n == n.rounded() { return String(Int(n)) }
            return String(n)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array(let a): return "[" + a.map { $0.displayString }.joined(separator: ", ") + "]"
        case .object(let o):
            return "{" + o.map { "\($0): \($1.displayString)" }.joined(separator: ", ") + "}"
        }
    }
}

// MARK: - Wire events (decoded from fin -ui json)

/// One decoded line from fin's JSONL output.
struct FinEvent: Decodable {
    let t: String
    let text: String?
    let idx: Int?
    let total: Int?
    let name: String?
    let args: [String: JSONValue]?
    let result: String?
    let error: String?
    let line: String?
    let resumed: Bool?
    let label: String?
    let attempt: Int?
    let max: Int?
}

// MARK: - Exported session (fin -export json)

struct ExportedSession: Decodable {
    let id: String?
    let title: String?
    let messages: [ExportedMessage]
}

struct ExportedMessage: Decodable {
    let role: String
    let content: String?
}

/// A message loaded from a previous session, ready to seed the transcript.
struct LoadedMessage {
    let role: ChatMessage.Role
    let text: String
}

/// The first line of a session JSONL file.
struct SessionHeader: Decodable {
    let id: String
    let title: String?
}

/// A previous session shown in the picker.
struct SessionSummary: Identifiable {
    let id: String
    let title: String
    let date: Date
}

// MARK: - View models for rendered content

/// A single tool invocation shown in the transcript.
final class ToolCall: Identifiable, ObservableObject {
    let id = UUID()
    let index: Int
    let name: String
    let args: [String: JSONValue]
    @Published var running: Bool = true
    @Published var outputLines: Int = 0
    @Published var result: String? = nil
    @Published var errorText: String? = nil

    init(index: Int, name: String, args: [String: JSONValue]) {
        self.index = index
        self.name = name
        self.args = args
    }

    /// The most relevant argument to show as a subtitle (command / path / etc).
    var primaryArg: String? {
        for key in ["command", "path", "file", "old_string", "content", "query", "name"] {
            if let v = args[key] { return v.displayString }
        }
        return args.first?.value.displayString
    }
}

/// A pending tool-approval request awaiting a user decision.
struct ApprovalRequest: Identifiable {
    let id = UUID()
    let name: String
    let args: [String: JSONValue]

    var primaryArg: String? {
        for key in ["command", "path", "file", "content", "old_string", "new_string"] {
            if let v = args[key] { return v.displayString }
        }
        return args.first?.value.displayString
    }
}

/// A turn in the conversation transcript.
final class ChatMessage: Identifiable, ObservableObject {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    @Published var text: String
    @Published var tools: [ToolCall] = []
    @Published var streaming: Bool

    init(role: Role, text: String = "", streaming: Bool = false) {
        self.role = role
        self.text = text
        self.streaming = streaming
    }
}

import Foundation

/// Tracks session continuity and delegates I/O to FinRunner.
@MainActor
final class SessionManager {
    private(set) var currentSessionID: String?
    private(set) var hasHadTurn: Bool = false

    private let runner: FinRunner

    private let lastNewChatKey = "fin.chat.lastExplicitNewChat"
    private let lastSessionURLKey = "fin.chat.lastSessionURL"

    init(runner: FinRunner) {
        self.runner = runner
    }

    /// The continuation mode to use for the next turn.
    var continuation: FinRunner.Continuation {
        if let id = currentSessionID {
            return .session(id)
        } else if hasHadTurn {
            return .last
        } else {
            return .fresh
        }
    }

    func markTurnDone() {
        hasHadTurn = true
    }

    func clearForNewChat() {
        hasHadTurn = false
        currentSessionID = nil
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: lastNewChatKey)
    }

    func applyLoadedSession(id: String?) {
        currentSessionID = id
        hasHadTurn = true
    }

    /// Synchronous check: returns the URL of the most recent beacon session if
    /// it was active within the last 5 minutes and the user hasn't started a
    /// new chat more recently. Reads only UserDefaults + a single file stat.
    static func cachedResumeURL() -> URL? {
        let d = UserDefaults.standard
        guard let urlStr = d.string(forKey: "fin.chat.lastSessionURL"),
              let url = URL(string: urlStr) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? .distantPast
        guard mtime > Date().addingTimeInterval(-5 * 60) else { return nil }
        if d.object(forKey: "fin.chat.lastExplicitNewChat") != nil {
            let newChatTime = Date(timeIntervalSinceReferenceDate: d.double(forKey: "fin.chat.lastExplicitNewChat"))
            if newChatTime > mtime { return nil }
        }
        return url
    }

    func listSessions(limit: Int = 50, completion: @escaping @Sendable ([SessionSummary]) -> Void) {
        runner.listSessions(limit: limit, completion: completion)
    }

    func loadSession(url: URL, completion: @escaping @Sendable (String?, String?, [LoadedMessage]) -> Void) {
        runner.loadSession(url: url, completion: completion)
    }

    func recordSessionURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: lastSessionURLKey)
    }
}

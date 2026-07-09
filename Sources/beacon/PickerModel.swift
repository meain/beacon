import AppKit
import SwiftUI

/// State + keyboard handling for the previous-chat picker. Uses an AppKit local
/// event monitor for arrow/return/escape because SwiftUI's `.onKeyPress` doesn't
/// reliably receive focus inside a borderless panel.
@MainActor
final class PickerModel: ObservableObject {
    @Published var visible = false
    @Published var sessions: [SessionSummary] = []
    @Published var selection = 0
    @Published var filterText: String = "" {
        didSet { filterChanged() }
    }

    var filteredSessions: [SessionSummary] {
        guard !filterText.isEmpty else { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(filterText) }
    }

    /// Invoked when the user picks a session or cancels.
    var onSelect: ((SessionSummary) -> Void)?
    var onCancel: (() -> Void)?

    private var monitor: Any?

    func show(_ list: [SessionSummary]) {
        sessions = list
        selection = 0
        filterText = ""
        visible = true
        installMonitor()
    }

    func hide() {
        visible = false
        filterText = ""
        removeMonitor()
    }

    func move(_ delta: Int) {
        let list = filteredSessions
        guard !list.isEmpty else { return }
        selection = min(max(0, selection + delta), list.count - 1)
    }

    func choose(_ index: Int) {
        selection = index
        commit()
    }

    private func filterChanged() {
        let count = filteredSessions.count
        guard count > 0 else { selection = 0; return }
        selection = min(selection, count - 1)
    }

    private func commit() {
        let list = filteredSessions
        guard list.indices.contains(selection) else { return }
        let session = list[selection]
        hide()
        onSelect?(session)
    }

    private func cancel() {
        hide()
        onCancel?()
    }

    private func installMonitor() {
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.visible else { return event }
            switch event.keyCode {
            case 126: self.move(-1); return nil   // up
            case 125: self.move(1); return nil    // down
            case 36, 76: self.commit(); return nil // return / enter
            case 53: self.cancel(); return nil     // escape
            default: return event
            }
        }
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
}

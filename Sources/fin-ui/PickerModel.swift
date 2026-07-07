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

    /// Invoked when the user picks a session or cancels.
    var onSelect: ((SessionSummary) -> Void)?
    var onCancel: (() -> Void)?

    private var monitor: Any?

    func show(_ list: [SessionSummary]) {
        sessions = list
        selection = 0
        visible = true
        installMonitor()
    }

    func hide() {
        visible = false
        removeMonitor()
    }

    func move(_ delta: Int) {
        guard !sessions.isEmpty else { return }
        selection = min(max(0, selection + delta), sessions.count - 1)
    }

    func choose(_ index: Int) {
        selection = index
        commit()
    }

    private func commit() {
        guard sessions.indices.contains(selection) else { return }
        let session = sessions[selection]
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

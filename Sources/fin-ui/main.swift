import AppKit
import SwiftUI

/// Borderless window that can still become key (needed for text input).
final class FloatingPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: FloatingPanel?
    /// True once the window sits at a user-chosen (or restored) position, so we
    /// stop auto-centring it.
    private var userPositioned = false
    /// Guards against reacting to our own programmatic moves.
    private var programmaticMove = false

    private let topLeftXKey = "fin.window.topLeftX"
    private let topLeftYKey = "fin.window.topLeftY"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()

        let controller = NSHostingController(rootView: SpotlightView())
        let panel = FloatingPanel(
            contentViewController: controller
        )
        panel.styleMask = [.borderless, .fullSizeContentView]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window = panel

        // Restore the last user position if there is one, else centre.
        if let topLeft = savedTopLeft() {
            applyTopLeft(topLeft, to: panel)
            userPositioned = true
        } else {
            center(panel)
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        // Spotlight-style: close when focus is lost.
        NotificationCenter.default.addObserver(
            self, selector: #selector(resign),
            name: NSWindow.didResignKeyNotification, object: panel)
        // Keep position stable as the window grows/shrinks with content.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowResized),
            name: NSWindow.didResizeNotification, object: panel)
        // Remember where the user drags the window to.
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMoved),
            name: NSWindow.didMoveNotification, object: panel)
    }

    /// Move without tripping the didMove handler.
    private func moveWindow(_ window: NSWindow, to origin: NSPoint) {
        programmaticMove = true
        window.setFrameOrigin(origin)
        programmaticMove = false
    }

    /// Place the window at the exact centre of the active screen.
    private func center(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let f = window.frame
        moveWindow(window, to: NSPoint(x: screen.visibleFrame.midX - f.width / 2,
                                       y: screen.visibleFrame.midY - f.height / 2))
    }

    /// Position the window so its top-left corner sits at `topLeft`.
    private func applyTopLeft(_ topLeft: NSPoint, to window: NSWindow) {
        moveWindow(window, to: NSPoint(x: topLeft.x, y: topLeft.y - window.frame.height))
    }

    private func savedTopLeft() -> NSPoint? {
        let d = UserDefaults.standard
        guard d.object(forKey: topLeftXKey) != nil,
              d.object(forKey: topLeftYKey) != nil else { return nil }
        return NSPoint(x: d.double(forKey: topLeftXKey), y: d.double(forKey: topLeftYKey))
    }

    private func saveTopLeft(_ window: NSWindow) {
        UserDefaults.standard.set(Double(window.frame.minX), forKey: topLeftXKey)
        UserDefaults.standard.set(Double(window.frame.maxY), forKey: topLeftYKey)
    }

    @objc private func windowResized() {
        guard let window else { return }
        if userPositioned, let topLeft = savedTopLeft() {
            applyTopLeft(topLeft, to: window) // keep top-left fixed as it grows
        } else {
            center(window)
        }
    }

    @objc private func windowMoved() {
        guard !programmaticMove, let window else { return }
        userPositioned = true
        saveTopLeft(window)
    }

    @objc private func resign() {
        // The panel loses key focus both when the user clicks away (should close)
        // and when one of our own auxiliary windows takes focus — the color
        // picker opened from Settings, or a popup font menu (should NOT close).
        // Defer a runloop tick, then only terminate if the whole app is now
        // inactive (i.e. another app is frontmost).
        DispatchQueue.main.async {
            if !NSApp.isActive { NSApp.terminate(nil) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// A minimal menu so standard editing shortcuts (⌘C/⌘V/⌘A) and ⌘Q work.
    private func setupMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit fin-ui", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

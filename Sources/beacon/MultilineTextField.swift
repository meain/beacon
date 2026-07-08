import AppKit
import SwiftUI

/// A multiline text input where ⏎ submits and ⇧⏎ inserts a newline.
/// Grows vertically up to a capped height; always remains editable.
struct MultilineTextField: NSViewRepresentable {
    @Binding var text: String
    /// Increment to request focus (token-based so repeated requests fire).
    @Binding var focusToken: Int
    /// The input font, resolved from the user's appearance settings.
    var font: NSFont
    var onSubmit: () -> Void
    var onHeightChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSScrollView {
        let textView = SubmitTextView()
        textView.onSubmit = onSubmit
        textView.isRichText = false
        textView.font = font
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        context.coordinator.onHeightChange = onHeightChange

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? SubmitTextView else { return }
        textView.onSubmit = onSubmit
        context.coordinator.onHeightChange = onHeightChange

        if textView.font != font {
            textView.font = font
            context.coordinator.recalculateHeight(textView)
        }

        if textView.string != text {
            let sel = textView.selectedRange()
            textView.string = text
            let newLen = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(sel.location, newLen), length: 0))
            context.coordinator.recalculateHeight(textView)
        }

        let token = focusToken
        if token != context.coordinator.lastFocusToken {
            context.coordinator.lastFocusToken = token
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onHeightChange: ((CGFloat) -> Void)?
        var lastFocusToken: Int = -1

        init(text: Binding<String>) { _text = text }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if text != tv.string { text = tv.string }
            recalculateHeight(tv)
        }

        func recalculateHeight(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = max(lm.usedRect(for: tc).height, 24)
            DispatchQueue.main.async { self.onHeightChange?(h) }
        }
    }
}

final class SubmitTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn {
            if event.modifierFlags.contains(.shift) {
                insertNewline(nil)
            } else {
                onSubmit?()
            }
            return
        }
        super.keyDown(with: event)
    }
}

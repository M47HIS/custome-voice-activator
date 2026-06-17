import AppKit
import Carbon.HIToolbox
import SwiftUI

/// NSViewRepresentable that becomes the first responder while the user is
/// recording a hotkey. It captures the next keyDown, including modifiers,
/// and forwards a `Hotkey` via the binding.
struct KeyCaptureView: NSViewRepresentable {
    @Binding var hotkey: Hotkey?
    var placeholder: String = "Click then press a hotkey..."
    var onCommit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let view = CaptureView()
        view.coordinator = context.coordinator
        view.placeholder = placeholder
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let v = nsView as? CaptureView {
            v.placeholder = placeholder
            v.needsDisplay = true
        }
    }

    final class Coordinator: NSObject {
        let parent: KeyCaptureView
        init(_ parent: KeyCaptureView) { self.parent = parent }

        func handle(_ hk: Hotkey) {
            parent.hotkey = hk
            parent.onCommit?()
        }
    }

    final class CaptureView: NSView {
        weak var coordinator: Coordinator?
        var placeholder: String = ""
        private var isFirstResponderInstalled = false

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Don't auto-become first responder — the user clicks the field
            // first (see mouseDown). This avoids stealing focus from other apps
            // on launch.
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            dirtyRect.fill()

            let display = coordinator?.parent.hotkey?.encode() ?? placeholder
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: coordinator?.parent.hotkey == nil
                    ? NSColor.secondaryLabelColor
                    : NSColor.labelColor
            ]
            let s = NSAttributedString(string: display, attributes: attrs)
            let size = s.size()
            let rect = NSRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            s.draw(in: rect)

            // Border
            NSColor.separatorColor.setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
            path.lineWidth = 1
            path.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            // We accept the event by NOT calling super. First, try to map to
            // a Hotkey.
            if let hk = Hotkey.from(event: event) {
                coordinator?.handle(hk)
            } else {
                // Flash a hint by redrawing. Common case: user pressed a
                // modifier-only combo (e.g. just Shift).
                needsDisplay = true
                NSSound.beep()
            }
        }

        // Required to receive keyDown.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            return true
        }
    }
}

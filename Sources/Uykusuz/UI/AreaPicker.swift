import AppKit
import Carbon.HIToolbox

/// A borderless window refuses key status by default, and Esc needs it.
private final class AreaPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Dims the screen under the mouse and lets the mouse draw an area on it. The
/// app comes forward for that moment, for the crosshair and Esc, and gives the
/// front back to the app that had it.
@MainActor
final class AreaPicker {
    struct Area: Sendable {
        /// In the display's own points, from its top left.
        var rect: CGRect
        var display: CGDirectDisplayID?
        var scale: CGFloat
    }

    private var panel: NSPanel?
    private var continuation: CheckedContinuation<Area?, Never>?

    /// The area drawn, or nil when the user gave up.
    func pick() async -> Area? {
        guard panel == nil,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return nil }
        let previous = NSWorkspace.shared.frontmostApplication
        let area = await withCheckedContinuation { (continuation: CheckedContinuation<Area?, Never>) in
            self.continuation = continuation
            let panel = AreaPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = AreaView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let display = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let scale = screen.backingScaleFactor
            let height = screen.frame.height
            view.onDone = { [weak self] rect in
                self?.finish(rect.map { Area(rect: AreaView.fromTopLeft($0, height: height), display: display, scale: scale) })
            }
            panel.contentView = view
            panel.setFrame(screen.frame, display: true)
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            NSCursor.crosshair.push()
            self.panel = panel
        }
        previous?.activate()
        return area
    }

    func cancel() {
        guard continuation != nil else { return }
        finish(nil)
    }

    private func finish(_ area: Area?) {
        NSCursor.pop()
        panel?.orderOut(nil)
        panel = nil
        continuation?.resume(returning: area)
        continuation = nil
    }
}

final class AreaView: NSView {
    static let hint = "Okunacak alanı fareyle çizin · Esc: vazgeç"
    /// Below this a press is taken as a slip.
    static let smallest: CGFloat = 8

    /// The area in this view's points, or nil for no area.
    var onDone: ((CGRect?) -> Void)?

    /// A rectangle of this view, which covers its display, as the display counts.
    static func fromTopLeft(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    private var start: CGPoint?
    private var current: CGPoint?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()
        if let rect = selection {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            NSColor.systemGreen.setStroke()
            let path = NSBezierPath(rect: rect)
            path.lineWidth = 2
            path.stroke()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white]
        let size = Self.hint.size(withAttributes: attributes)
        let origin = CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 90)
        // On a white page the dim alone leaves white letters hard to read.
        NSColor.black.withAlphaComponent(0.85).setFill()
        NSBezierPath(roundedRect: CGRect(origin: origin, size: size).insetBy(dx: -14, dy: -8), xRadius: 10, yRadius: 10).fill()
        Self.hint.draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let rect = selection, rect.width > Self.smallest, rect.height > Self.smallest else {
            onDone?(nil)
            return
        }
        onDone?(rect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onDone?(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}

import AppKit

/// Minimal selection tip: only "Copy". Dismiss on click outside. No close button.
@MainActor
final class CopyTip {
    static let shared = CopyTip()

    private var panel: NSPanel?
    private var text: String = ""
    private var dismissMonitor: Any?
    private var ignoreDismissUntil: Date = .distantPast

    var isVisible: Bool { panel != nil }

    private init() {}

    func show(text: String, near bounds: CGRect? = nil) {
        hide()
        self.text = text

        let btn = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 13, weight: .medium)
        btn.contentTintColor = .labelColor
        btn.setButtonType(.momentaryChange)

        let padding: CGFloat = 10
        btn.sizeToFit()
        let w = max(56, btn.bounds.width + padding * 2)
        let h: CGFloat = 32
        btn.frame = CGRect(x: padding, y: (h - btn.bounds.height) / 2, width: w - padding * 2, height: btn.bounds.height)

        let container = TipClickView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.onClick = { [weak self] in self?.copyTapped() }
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(btn)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(Int(CGWindowLevelForKey(.assistiveTechHighWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = container

        placeBelowCursor(panel, size: NSSize(width: w, height: h))
        panel.orderFrontRegardless()
        self.panel = panel

        // Avoid instantly dismissing / copying from the same mouse-up that showed the tip.
        ignoreDismissUntil = Date().addingTimeInterval(0.25)
        installDismissMonitor()
    }

    func hide() {
        removeDismissMonitor()
        panel?.orderOut(nil)
        panel = nil
        text = ""
    }

    @objc private func copyTapped() {
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        hide()
    }

    private func installDismissMonitor() {
        removeDismissMonitor()
        // Global monitor: nonactivating tip often lets clicks pass through —
        // treat a click inside the tip frame as Copy; outside dismisses.
        dismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.handleClickWhileVisible()
            }
        }
    }

    private func removeDismissMonitor() {
        if let dismissMonitor {
            NSEvent.removeMonitor(dismissMonitor)
            self.dismissMonitor = nil
        }
    }

    private func handleClickWhileVisible() {
        guard Date() >= ignoreDismissUntil else { return }
        guard let panel else { return }
        let screenPoint = NSEvent.mouseLocation
        if panel.frame.contains(screenPoint) {
            copyTapped()
        } else {
            hide()
        }
    }

    /// Place tip just below the mouse cursor (AppKit: lower y = visually below).
    private func placeBelowCursor(_ panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let m = NSEvent.mouseLocation
        var origin = NSPoint(
            x: m.x - size.width / 2,
            y: m.y - size.height - 14
        )
        origin.x = min(max(origin.x, screen.minX + 6), screen.maxX - size.width - 6)
        origin.y = min(max(origin.y, screen.minY + 6), screen.maxY - size.height - 6)
        panel.setFrameOrigin(origin)
    }
}

/// Whole tip surface is clickable (padding + label).
private final class TipClickView: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

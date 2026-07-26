import AppKit
import Foundation
import ObjectiveC

/// ⌥Z screenshot: drag to select → size badge / resize handles / Confirm · Cancel → capture.
@MainActor
final class RegionSelectionController {
    var onCaptured: ((Result<CGImage, SnapCopyError>) -> Void)?

    private var windows: [RegionSelectionWindow] = []
    private var keyMonitor: Any?

    func begin() {
        tearDown()
        // Capture window list before overlay windows appear, so it matches the frozen backdrop.
        let capturedWindows = WindowHitTester.listCompleteWindows()
        for screen in NSScreen.screens {
            let win = RegionSelectionWindow(screen: screen, capturedWindows: capturedWindows)
            win.onCommitGlobalAppKit = { [weak self] rect in
                self?.finish(rectAppKit: rect)
            }
            win.onCancel = { [weak self] in
                self?.abort(.captureCancelled)
            }
            windows.append(win)
            win.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.abort(.captureCancelled)
                return nil
            }
            if event.keyCode == 36 || event.keyCode == 76 {
                for win in self?.windows ?? [] {
                    if let view = win.contentView as? RegionSelectionView, view.confirmIfAdjusting() {
                        return nil
                    }
                }
            }
            return event
        }
    }

    private func finish(rectAppKit: CGRect) {
        windows.forEach { $0.alphaValue = 0 }
        windows.forEach { $0.orderOut(nil) }
        tearDownMonitorsOnly()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.windows.removeAll()
            Task { @MainActor in
                let result = await ScreenCaptureService.capture(rect: rectAppKit)
                self.onCaptured?(result)
            }
        }
    }

    private func abort(_ error: SnapCopyError) {
        tearDown()
        onCaptured?(.failure(error))
    }

    private func tearDownMonitorsOnly() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func tearDown() {
        tearDownMonitorsOnly()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

@MainActor
final class RegionSelectionWindow: NSWindow {
    var onCommitGlobalAppKit: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    private let screenFrame: CGRect

    init(screen: NSScreen, capturedWindows: [CapturedWindowInfo]) {
        self.screenFrame = screen.frame
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        setFrame(screen.frame, display: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true

        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.screenFrame = screen.frame
        view.capturedWindows = capturedWindows
        // Keep the raw CGImage — NSImage(cgImage:)+draw(in:from:) mis-maps coords in a
        // flipped view and shows a mirrored patch inside the selection.
        view.frozenCGImage = ScreenCaptureService.captureScreenSnapshot(screen)
        view.onConfirmLocal = { [weak self] local in
            guard let self else { return }
            let global = CGRect(
                x: self.screenFrame.minX + local.minX,
                y: self.screenFrame.maxY - local.maxY,
                width: local.width,
                height: local.height
            ).integral
            self.onCommitGlobalAppKit?(global)
        }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class RegionSelectionView: NSView {
    var onConfirmLocal: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    /// Snapshot of the desktop taken the moment selection began — keeps the picture fixed
    /// while dragging, instead of showing whatever is changing live underneath.
    var frozenCGImage: CGImage?
    /// Global screen frame for this overlay (bottom-left origin).
    var screenFrame: CGRect = .zero
    /// Complete windows captured at selection start (front → back).
    var capturedWindows: [CapturedWindowInfo] = []

    private enum Mode { case idle, dragging, adjusting }
    private enum DragKind {
        case create
        case move
        case resize(ResizeHandle)
    }
    private enum ResizeHandle: CaseIterable {
        case n, s, e, w, ne, nw, se, sw
    }

    private var mode: Mode = .idle
    private var selection = CGRect.zero
    private var dragKind: DragKind?
    private var dragStartMouse = CGPoint.zero
    private var dragStartSelection = CGRect.zero
    /// Where the drag ended — buttons anchor to this side of the selection.
    private var dragEndPoint = CGPoint.zero
    private let handleSize: CGFloat = 8
    /// Hover preview of a complete window under the cursor (idle only). Nil = no window.
    private var hoverPreview: CGRect?
    /// mouseDown started a potential click (not yet a drag).
    private var clickCandidate = false
    private let dragThreshold: CGFloat = 4

    private lazy var confirmButton: NSButton = makeButton("Confirm", kind: .confirm) { [weak self] in
        self?.confirmIfAdjusting()
    }
    private lazy var cancelButton: NSButton = makeButton("Cancel", kind: .cancel) { [weak self] in
        self?.hideButtons()
        self?.onCancel?()
    }
    private var buttonTargets: [ButtonTarget] = []

    private enum ActionButtonKind { case confirm, cancel }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        window?.acceptsMouseMovedEvents = true
        if confirmButton.superview == nil {
            addSubview(cancelButton)
            addSubview(confirmButton)
            hideButtons()
        }
        updateTrackingAreas()
        DispatchQueue.main.async { [weak self] in
            self?.updateHoverPreview()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    @discardableResult
    func confirmIfAdjusting() -> Bool {
        guard mode == .adjusting, selection.width >= 4, selection.height >= 4 else { return false }
        hideButtons()
        onConfirmLocal?(selection.integral)
        return true
    }

    /// Solid high-contrast buttons so they stay readable on the dimmed screenshot overlay.
    private func makeButton(_ title: String, kind: ActionButtonKind, handler: @escaping () -> Void) -> NSButton {
        let btn = NSButton(title: title, target: nil, action: nil)
        btn.bezelStyle = .flexiblePush
        btn.isBordered = false
        btn.setButtonType(.momentaryChange)
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 7
        btn.layer?.masksToBounds = true
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        switch kind {
        case .confirm:
            btn.layer?.backgroundColor = NSColor.systemBlue.cgColor
            btn.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: font,
                .foregroundColor: NSColor.white,
            ])
        case .cancel:
            btn.layer?.backgroundColor = NSColor.white.cgColor
            btn.layer?.borderWidth = 1
            btn.layer?.borderColor = NSColor.black.withAlphaComponent(0.35).cgColor
            btn.attributedTitle = NSAttributedString(string: title, attributes: [
                .font: font,
                .foregroundColor: NSColor.black.withAlphaComponent(0.88),
            ])
        }
        let target = ButtonTarget(handler)
        buttonTargets.append(target)
        btn.target = target
        btn.action = #selector(ButtonTarget.invoke)
        return btn
    }

    private func showButtons() {
        layoutButtons()
        confirmButton.isHidden = false
        cancelButton.isHidden = false
    }

    private func hideButtons() {
        confirmButton.isHidden = true
        cancelButton.isHidden = true
    }

    private func layoutButtons() {
        let btnW: CGFloat = 84
        let btnH: CGFloat = 32
        let gap: CGFloat = 10
        let totalW = btnW * 2 + gap
        let r = selection

        // Prefer the side where the mouse finished dragging.
        let endRight = dragEndPoint.x >= r.midX
        let endBelow = dragEndPoint.y >= r.midY

        var origin = CGPoint.zero
        if endBelow {
            origin.y = r.maxY + 10
            if origin.y + btnH > bounds.height - 8 {
                origin.y = max(8, r.minY - btnH - 10)
            }
        } else {
            origin.y = r.minY - btnH - 10
            if origin.y < 8 {
                origin.y = min(bounds.height - btnH - 8, r.maxY + 10)
            }
        }

        if endRight {
            origin.x = r.maxX - totalW
        } else {
            origin.x = r.minX
        }
        origin.x = min(max(8, origin.x), bounds.width - totalW - 8)

        cancelButton.frame = CGRect(x: origin.x, y: origin.y, width: btnW, height: btnH)
        confirmButton.frame = CGRect(x: origin.x + btnW + gap, y: origin.y, width: btnW, height: btnH)
    }

    // MARK: - Window hover / click-to-lock

    private func updateHoverPreview(atLocalPoint _: CGPoint? = nil) {
        guard mode == .idle else { return }
        let global = NSEvent.mouseLocation

        // Prefer a fully-visible complete window under the cursor.
        if screenFrame.contains(global),
           let hit = WindowHitTester.frontmostWindow(atGlobalPoint: global, in: capturedWindows) {
            let local = WindowHitTester.localFlippedRect(globalBounds: hit.bounds, screenFrame: screenFrame)
            if local.width >= 4, local.height >= 4 {
                setHoverPreview(local)
                return
            }
        }

        // Outside any selectable window (desktop gap, menu bar, Dock, screen edge)
        // → full-screen preview on this display.
        setHoverPreview(bounds)
    }

    private func setHoverPreview(_ rect: CGRect?) {
        let normalized = rect?.integral
        if normalized == hoverPreview { return }
        hoverPreview = normalized
        needsDisplay = true
    }

    /// Lock a rect into adjusting mode (window click or full-screen click).
    private func lockSelection(_ rect: CGRect, at point: CGPoint) {
        let locked = clamp(rect.integral)
        guard locked.width >= 4, locked.height >= 4 else { return }
        hoverPreview = nil
        selection = locked
        dragEndPoint = point
        mode = .adjusting
        showButtons()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverPreview(atLocalPoint: convert(event.locationInWindow, from: nil))
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragStartMouse = p

        if mode == .adjusting {
            if let handle = hitHandle(at: p) {
                dragKind = .resize(handle)
                dragStartSelection = selection
                clickCandidate = false
                return
            }
            if selection.insetBy(dx: -2, dy: -2).contains(p) {
                dragKind = .move
                dragStartSelection = selection
                clickCandidate = false
                return
            }
            // Click outside current selection → start a new custom drag (existing behavior).
            clickCandidate = false
            hoverPreview = nil
            mode = .dragging
            dragKind = .create
            selection = CGRect(origin: p, size: .zero)
            hideButtons()
            needsDisplay = true
            return
        }

        // Idle: wait to see if this is a click (window / full-screen) or a drag (custom region).
        clickCandidate = true
        dragKind = nil
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        if clickCandidate {
            let dx = abs(p.x - dragStartMouse.x)
            let dy = abs(p.y - dragStartMouse.y)
            if dx >= dragThreshold || dy >= dragThreshold {
                // Promote to custom drag selection — ignore window hover.
                clickCandidate = false
                hoverPreview = nil
                mode = .dragging
                dragKind = .create
                selection = CGRect(pointA: dragStartMouse, pointB: p).integral
                hideButtons()
                needsDisplay = true
            }
            return
        }

        switch dragKind {
        case .create:
            selection = CGRect(pointA: dragStartMouse, pointB: p).integral
            mode = .dragging
        case .move:
            var r = dragStartSelection
            r.origin.x += p.x - dragStartMouse.x
            r.origin.y += p.y - dragStartMouse.y
            selection = clamp(r)
            layoutButtons()
        case .resize(let handle):
            selection = clamp(resize(dragStartSelection, handle: handle, to: p))
            layoutButtons()
        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragEndPoint = p
        defer { dragKind = nil }

        if clickCandidate {
            clickCandidate = false
            // Click without drag: lock hovered window, or full screen if no window.
            updateHoverPreview()
            if let preview = hoverPreview {
                lockSelection(preview, at: p)
            } else {
                lockSelection(bounds, at: p)
            }
            return
        }

        guard mode == .dragging || mode == .adjusting else { return }

        if mode == .dragging {
            selection = selection.integral
            if selection.width < 4 || selection.height < 4 {
                mode = .idle
                selection = .zero
                hideButtons()
                updateHoverPreview()
                needsDisplay = true
                return
            }
            mode = .adjusting
            showButtons()
            needsDisplay = true
            return
        }

        selection = clamp(selection).integral
        layoutButtons()
        needsDisplay = true
    }

    private func hitHandle(at p: CGPoint) -> ResizeHandle? {
        for h in ResizeHandle.allCases where handleRect(h).insetBy(dx: -4, dy: -4).contains(p) {
            return h
        }
        return nil
    }

    private func handleRect(_ h: ResizeHandle) -> CGRect {
        let s = handleSize
        let r = selection
        switch h {
        case .n:  return CGRect(x: r.midX - s/2, y: r.minY - s/2, width: s, height: s)
        case .s:  return CGRect(x: r.midX - s/2, y: r.maxY - s/2, width: s, height: s)
        case .e:  return CGRect(x: r.maxX - s/2, y: r.midY - s/2, width: s, height: s)
        case .w:  return CGRect(x: r.minX - s/2, y: r.midY - s/2, width: s, height: s)
        case .ne: return CGRect(x: r.maxX - s/2, y: r.minY - s/2, width: s, height: s)
        case .nw: return CGRect(x: r.minX - s/2, y: r.minY - s/2, width: s, height: s)
        case .se: return CGRect(x: r.maxX - s/2, y: r.maxY - s/2, width: s, height: s)
        case .sw: return CGRect(x: r.minX - s/2, y: r.maxY - s/2, width: s, height: s)
        }
    }

    private func resize(_ r: CGRect, handle: ResizeHandle, to p: CGPoint) -> CGRect {
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        switch handle {
        case .n:  minY = p.y
        case .s:  maxY = p.y
        case .e:  maxX = p.x
        case .w:  minX = p.x
        case .ne: minY = p.y; maxX = p.x
        case .nw: minY = p.y; minX = p.x
        case .se: maxY = p.y; maxX = p.x
        case .sw: maxY = p.y; minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY), width: abs(maxX - minX), height: abs(maxY - minY))
    }

    private func clamp(_ r: CGRect) -> CGRect {
        var r = r
        r.origin.x = min(max(0, r.origin.x), bounds.width - 2)
        r.origin.y = min(max(0, r.origin.y), bounds.height - 2)
        r.size.width = min(max(2, r.width), bounds.width - r.origin.x)
        r.size.height = min(max(2, r.height), bounds.height - r.origin.y)
        return r
    }

    /// Draw the frozen screen snapshot upright in this flipped view.
    /// Uses one full-bounds draw only — never a cropped `from:` rect (that caused mirroring).
    private func drawFrozenBackdrop() {
        guard let image = frozenCGImage,
              let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        // View is flipped (y grows downward). CGImage draws with bottom-left origin,
        // so flip the CTM once before drawing the full image into bounds.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: bounds.size))
        ctx.restoreGState()
    }

    /// Dim everything except the selection (even-odd fill). Selection stays undimmed
    /// by leaving the already-correct frozen pixels visible — no second image draw.
    private func fillDimOutsideSelection(_ selection: CGRect?) {
        let path = NSBezierPath(rect: bounds)
        if let selection, selection.width > 0, selection.height > 0 {
            path.append(NSBezierPath(rect: selection))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.4).setFill()
        path.fill()
    }

    private func strokeSelectionBorder(_ r: CGRect, preview: Bool) {
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = preview ? 2 : 1.5
        if preview {
            // Dashed outline = hover preview (not locked yet).
            let pattern: [CGFloat] = [6, 4]
            border.setLineDash(pattern, count: 2, phase: 0)
        }
        border.stroke()
    }

    override func draw(_ dirtyRect: NSRect) {
        // 1) Frozen full-screen backdrop (fixed at shortcut press).
        drawFrozenBackdrop()

        if mode == .idle {
            if let preview = hoverPreview, preview.width > 0, preview.height > 0 {
                fillDimOutsideSelection(preview)
                strokeSelectionBorder(preview, preview: true)
                drawSizeBadge(for: preview)
            } else {
                fillDimOutsideSelection(nil)
            }
            let text = "Hover window · outside = full screen · click to lock · drag for custom"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 15, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92)
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: 48), withAttributes: attrs)
            return
        }

        let r = selection
        guard r.width > 0, r.height > 0 else {
            fillDimOutsideSelection(nil)
            return
        }

        // 2) Dim only outside the selection. Inside stays the same upright frozen pixels.
        if frozenCGImage != nil {
            fillDimOutsideSelection(r)
        } else {
            // Fallback if snapshot failed: dim all, then punch through to live desktop.
            NSColor.black.withAlphaComponent(0.4).setFill()
            bounds.fill()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSColor.black.setFill()
            r.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
        }

        strokeSelectionBorder(r, preview: false)
        drawSizeBadge(for: r)

        if mode == .adjusting {
            for h in ResizeHandle.allCases {
                let hr = handleRect(h)
                NSColor.white.setFill()
                NSBezierPath(ovalIn: hr).fill()
                NSColor.black.withAlphaComponent(0.4).setStroke()
                let ring = NSBezierPath(ovalIn: hr.insetBy(dx: 0.5, dy: 0.5))
                ring.lineWidth = 1
                ring.stroke()
            }
        }
    }

    private func drawSizeBadge(for r: CGRect) {
        let label = "\(Int(r.width)) × \(Int(r.height))"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let textSize = label.size(withAttributes: [.font: font])
        let badge = CGRect(
            x: r.minX,
            y: max(4, r.minY - textSize.height - 10),
            width: textSize.width + 12,
            height: textSize.height + 6
        )
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        label.draw(at: CGPoint(x: badge.minX + 6, y: badge.minY + 3), withAttributes: [
            .font: font,
            .foregroundColor: NSColor.white
        ])
    }
}

private final class ButtonTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func invoke() { handler() }
}

private extension CGRect {
    init(pointA: CGPoint, pointB: CGPoint) {
        self.init(
            x: min(pointA.x, pointB.x),
            y: min(pointA.y, pointB.y),
            width: abs(pointA.x - pointB.x),
            height: abs(pointA.y - pointB.y)
        )
    }
}

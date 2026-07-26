import AppKit
import Foundation
import os.log

private let log = Logger(subsystem: "app.snapcopy", category: "Select")

/// Drag / double-click selection → show "Copy" tip only; dismiss on click outside.
@MainActor
final class SelectionWatcher {
    static let shared = SelectionWatcher()

    var isPaused = false

    private var monitors: [Any] = []
    private var downPoint: CGPoint?
    private var dragged = false
    private var lastShown: String?
    private var busy = false

    private init() {}

    func start() {
        stop()

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] e in
            Task { @MainActor in self?.onDown(e) }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] e in
            Task { @MainActor in self?.onDrag(e) }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] e in
            Task { @MainActor in self?.onUp(e) }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] e in
            Task { @MainActor in self?.onDown(e) }
            return e
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] e in
            Task { @MainActor in self?.onDrag(e) }
            return e
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] e in
            Task { @MainActor in self?.onUp(e) }
            return e
        }) { monitors.append(m) }

        AppFlow.shared.refreshStatus()
        log.info("SelectionWatcher monitors=\(self.monitors.count)")
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }

    func forgetShown() {
        lastShown = nil
        CopyTip.shared.hide()
    }

    private func onDown(_ event: NSEvent) {
        downPoint = NSEvent.mouseLocation
        dragged = false
    }

    private func onDrag(_ event: NSEvent) {
        guard let start = downPoint else { return }
        let now = NSEvent.mouseLocation
        if hypot(now.x - start.x, now.y - start.y) > 4 { dragged = true }
    }

    private func onUp(_ event: NSEvent) {
        guard !isPaused, !busy else { return }
        let isDrag = dragged
        let isDouble = event.clickCount >= 2
        downPoint = nil
        dragged = false
        guard isDrag || isDouble else { return }

        // Finder double-click opens PDF/image files; filename gets selected — skip copy tip.
        if isDouble, Self.isFinderFrontmost() {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.captureAndShow()
        }
    }

    private func captureAndShow() {
        guard !isPaused, !busy else { return }
        busy = true
        defer { busy = false }

        // Never show tip for Finder file operations (not text selection).
        if Self.isFinderFrontmost() { return }

        var text: String?
        var fromAX = false

        if let snap = AXSelectionService.captureSelectedText() {
            text = snap.text
            fromAX = true
        } else if PermissionGate.accessibilityOK {
            // Clipboard fallback for Electron editors where AX selection is unavailable;
            // on web pages, ⌘C on a file often copies the filename — filter those out.
            text = ClipboardSelection.readSelectedText()
        }

        guard let text, (1...8000).contains(text.count) else { return }
        // Skip selections that look like filenames, not body text (cloud drives, attachment lists, etc.).
        if Self.looksLikeFileNameSelection(text) { return }
        if text == lastShown, CopyTip.shared.isVisible { return }

        lastShown = text
        CopyTip.shared.show(text: text)
        AppFlow.shared.status = "Selected"
        log.info("copy tip len=\(text.count) ax=\(fromAX)")
    }

    private static func isFinderFrontmost() -> Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
    }

    /// Single-line selection that looks like a filename (with extension) — common false positive on web pages.
    private static func looksLikeFileNameSelection(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("\n"), t.count <= 240 else { return false }

        // Path or file://
        if t.hasPrefix("file://") || t.contains("/Users/") { return true }
        if t.hasPrefix("/") , t.contains(".") { return true }

        let name = (t as NSString).lastPathComponent
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else { return false }
        let ext = String(name[name.index(after: dot)...]).lowercased()
        // Extension must be 2+ chars with a letter — avoid "v1.2" / "i.e" false positives.
        guard (2...8).contains(ext.count), ext.contains(where: \.isLetter),
              ext.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }

        if nonTextFileExtensions.contains(ext) { return true }

        // Entire selection is "filename.ext" — treat as file click in web/list UI.
        if name == t {
            let body = String(name[..<dot])
            if !body.isEmpty, body.count <= 200 { return true }
        }
        return false
    }

    private static let nonTextFileExtensions: Set<String> = [
        "pdf", "txt", "rtf", "md", "csv", "json", "xml", "html", "htm", "css", "js", "ts",
        "png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tif", "tiff", "bmp", "ico", "svg",
        "mov", "mp4", "m4v", "avi", "mkv", "mp3", "wav", "aac", "flac", "m4a",
        "zip", "rar", "7z", "dmg", "pkg", "iso", "tar", "gz",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        "psd", "ai", "sketch", "fig", "dwg",
        "swift", "py", "java", "kt", "go", "rs", "c", "cpp", "h", "m", "mm",
        "app", "exe", "apk", "ipa",
    ]
}

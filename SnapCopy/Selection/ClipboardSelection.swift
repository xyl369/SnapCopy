import AppKit
import Carbon
import Foundation

/// When AX can't read selection (Electron / Chrome / Cursor), briefly ⌘C then restore clipboard.
/// Only returns plain text selections — never file rows / file URLs.
enum ClipboardSelection {
    static func readSelectedText() -> String? {
        let pb = NSPasteboard.general
        let saved: [[String: Data]] = (pb.pasteboardItems ?? []).map { item in
            var map: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type.rawValue] = data
                }
            }
            return map
        }
        let before = pb.changeCount

        postCommandC()

        // Wait up to ~250ms for pasteboard update
        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            if pb.changeCount != before { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        // Pasteboard never changed → ⌘C copied nothing, i.e. there was no real selection
        // (e.g. dragging a webpage/window/scrollbar, no text under the cursor). Do NOT fall
        // back to whatever was already on the clipboard — that would resurface stale text.
        guard pb.changeCount != before else {
            restore(saved)
            return nil
        }

        // When a web/cloud file is selected, clipboard often carries a file URL — not text selection.
        if containsFilePayload(pb) {
            restore(saved)
            return nil
        }

        let text = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        restore(saved)

        guard let text, !text.isEmpty, text.count <= 8000 else { return nil }
        return text
    }

    private static func containsFilePayload(_ pb: NSPasteboard) -> Bool {
        let types = Set(pb.types?.map(\.rawValue) ?? [])
        let fileMarkers: Set<String> = [
            NSPasteboard.PasteboardType.fileURL.rawValue,
            "public.file-url",
            "NSFilenamesPboardType",
            "com.apple.pasteboard.promised-file-url",
            "com.apple.pasteboard.promised-file-content-type",
            "com.apple.Finder.fileURL",
            "org.chromium.filename",
            "text/uri-list",
        ]
        if !types.isDisjoint(with: fileMarkers) { return true }
        if pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.isEmpty == false {
            return true
        }
        return false
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func restore(_ saved: [[String: Data]]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !saved.isEmpty else { return }
        var items: [NSPasteboardItem] = []
        for map in saved {
            let item = NSPasteboardItem()
            for (type, data) in map {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            items.append(item)
        }
        pb.writeObjects(items)
    }
}

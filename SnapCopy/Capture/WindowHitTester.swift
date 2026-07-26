import AppKit
import CoreGraphics
import Foundation

/// Front-to-back list of complete, fully-visible on-screen app windows.
struct CapturedWindowInfo {
    let windowID: CGWindowID
    /// Global AppKit screen coords (origin bottom-left of primary display).
    let bounds: CGRect
    let ownerName: String
    let name: String
}

enum WindowHitTester {
    /// Minimum size so tiny panels / badges are ignored — only “complete” windows.
    private static let minWidth: CGFloat = 160
    private static let minHeight: CGFloat = 120
    /// Ignore 1–2px hairline overlaps when judging occlusion.
    private static let occludeSlop: CGFloat = 2

    private static let excludedOwners: Set<String> = [
        "window server",
        "dock",
        "systemuiserver",
        "control center",
        "notification center",
        "controlcentre",
        "spotlight",
        "wallpaper",
        "loginwindow",
        "textinputmenuagent",
        "axvisualsupportagent",
    ]

    /// Snapshot complete, unoccluded windows (front → back). Call once at selection start,
    /// before SnapCopy overlay windows are shown, so the list matches the frozen backdrop.
    static func listCompleteWindows(excludingPID: pid_t = getpid()) -> [CapturedWindowInfo] {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        let flipY = primaryDisplayFlipY()
        var candidates: [CapturedWindowInfo] = []
        candidates.reserveCapacity(info.count)

        for entry in info {
            guard let windowID = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if ownerPID == excludingPID { continue }

            // Layer 0 ≈ normal app windows. Menu bar / Dock / overlays sit higher.
            let layer = entry[kCGWindowLayer as String] as? Int ?? -1
            guard layer == 0 else { continue }

            let alpha = entry[kCGWindowAlpha as String] as? CGFloat ?? 1
            guard alpha >= 0.85 else { continue }

            var quartzBounds = CGRect.zero
            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  CGRectMakeWithDictionaryRepresentation(boundsDict, &quartzBounds),
                  quartzBounds.width >= minWidth,
                  quartzBounds.height >= minHeight
            else { continue }

            let owner = entry[kCGWindowOwnerName as String] as? String ?? ""
            let name = entry[kCGWindowName as String] as? String ?? ""
            if isExcludedSystemSurface(owner: owner, name: name) { continue }

            // CGWindow bounds: origin at top-left of main display, Y downward.
            // AppKit / NSEvent.mouseLocation: origin at bottom-left, Y upward.
            let appKitBounds = CGRect(
                x: quartzBounds.origin.x,
                y: flipY - quartzBounds.origin.y - quartzBounds.height,
                width: quartzBounds.width,
                height: quartzBounds.height
            ).integral

            // Strip menu-bar / Dock shaped regions even if mis-reported as layer 0.
            if looksLikeMenuBarOrDock(appKitBounds) { continue }

            candidates.append(CapturedWindowInfo(
                windowID: windowID,
                bounds: appKitBounds,
                ownerName: owner,
                name: name
            ))
        }

        // Only keep windows that are fully visible — any overlap from a front window
        // means this window is “blocked” and must not be offered for framing.
        return filterFullyVisible(candidates)
    }

    /// Frontmost selectable window under a global mouse point (AppKit coords).
    static func frontmostWindow(
        atGlobalPoint point: CGPoint,
        in windows: [CapturedWindowInfo]
    ) -> CapturedWindowInfo? {
        windows.first { $0.bounds.contains(point) }
    }

    /// Convert a global AppKit (bottom-left) rect into this screen view’s flipped local coords.
    static func localFlippedRect(
        globalBounds: CGRect,
        screenFrame: CGRect
    ) -> CGRect {
        let intersection = globalBounds.intersection(screenFrame)
        guard !intersection.isNull, intersection.width >= 2, intersection.height >= 2 else {
            return .zero
        }
        let localBottomLeft = CGRect(
            x: intersection.minX - screenFrame.minX,
            y: intersection.minY - screenFrame.minY,
            width: intersection.width,
            height: intersection.height
        )
        return CGRect(
            x: localBottomLeft.minX,
            y: screenFrame.height - localBottomLeft.maxY,
            width: localBottomLeft.width,
            height: localBottomLeft.height
        ).integral
    }

    // MARK: - Filters

    /// Drop any window whose bounds intersect a window in front of it.
    private static func filterFullyVisible(_ frontToBack: [CapturedWindowInfo]) -> [CapturedWindowInfo] {
        var visible: [CapturedWindowInfo] = []
        visible.reserveCapacity(frontToBack.count)
        for (index, window) in frontToBack.enumerated() {
            let blocked = frontToBack[..<index].contains { front in
                meaningfullyIntersects(front.bounds, window.bounds)
            }
            if !blocked {
                visible.append(window)
            }
        }
        return visible
    }

    private static func meaningfullyIntersects(_ a: CGRect, _ b: CGRect) -> Bool {
        let inter = a.intersection(b)
        guard !inter.isNull else { return false }
        return inter.width > occludeSlop && inter.height > occludeSlop
    }

    private static func isExcludedSystemSurface(owner: String, name: String) -> Bool {
        let ownerLower = owner.lowercased()
        let nameLower = name.lowercased()
        if excludedOwners.contains(ownerLower) { return true }
        if ownerLower.contains("dock") { return true }
        if nameLower.contains("dock") { return true }
        if nameLower.contains("menubar") || nameLower.contains("menu bar") { return true }
        if nameLower.contains("statusitem") || nameLower.contains("status item") { return true }
        return false
    }

    /// Menu bar / Dock shaped strips across a screen — never treat as app windows.
    private static func looksLikeMenuBarOrDock(_ bounds: CGRect) -> Bool {
        for screen in NSScreen.screens {
            let f = screen.frame
            let coversWidth = bounds.width >= f.width * 0.45

            // Menu bar: thin strip along the top of the screen.
            let nearTop = bounds.maxY >= f.maxY - 4
            if coversWidth && nearTop && bounds.height <= 48 {
                return true
            }

            // Dock: thin strip along the bottom (or side) of the screen.
            let nearBottom = bounds.minY <= f.minY + 8
            if coversWidth && nearBottom && bounds.height <= 140 {
                return true
            }

            let coversHeight = bounds.height >= f.height * 0.45
            let nearLeft = bounds.minX <= f.minX + 8
            let nearRight = bounds.maxX >= f.maxX - 8
            if coversHeight && bounds.width <= 140 && (nearLeft || nearRight) {
                return true
            }
        }
        return false
    }

    private static func primaryDisplayFlipY() -> CGFloat {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        return primary?.frame.maxY ?? 0
    }
}

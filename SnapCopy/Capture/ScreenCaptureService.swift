import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureService {
    /// One frozen display buffer taken at ⌥Z press time.
    struct FrozenScreen {
        let frame: CGRect
        let image: CGImage
    }

    /// Capture on-screen pixels in an AppKit global rect (origin bottom-left).
    /// Prefer `cropFromFrozen` when a freeze buffer exists — live capture after the overlay
    /// dismisses Dock menus / popovers that were visible at hotkey press.
    static func capture(rect: CGRect) async -> Result<CGImage, SnapCopyError> {
        guard rect.width >= 2, rect.height >= 2 else {
            return .failure(.captureFailed("Selection too small"))
        }

        if #available(macOS 14.0, *) {
            do {
                let image = try await captureWithSCK(rect: rect)
                return .success(image)
            } catch {
                // Fall through to legacy API
            }
        }

        return captureLegacy(rect: rect)
    }

    /// Crop the selection from freeze buffers taken at hotkey press.
    /// This is the primary Confirm path so Dock popovers / menus stay in the result.
    static func cropFromFrozen(_ frozen: [FrozenScreen], rect: CGRect) -> Result<CGImage, SnapCopyError> {
        guard rect.width >= 2, rect.height >= 2 else {
            return .failure(.captureFailed("Selection too small"))
        }
        guard !frozen.isEmpty else {
            return .failure(.captureFailed("No frozen screen buffer"))
        }

        // Prefer the display that covers the largest share of the selection.
        let best = frozen.max { a, b in
            area(a.frame.intersection(rect)) < area(b.frame.intersection(rect))
        }
        guard let screen = best else {
            return .failure(.captureFailed("No frozen screen buffer"))
        }

        let intersection = screen.frame.intersection(rect)
        guard !intersection.isNull, intersection.width >= 2, intersection.height >= 2 else {
            return .failure(.captureFailed("Selection outside frozen screen"))
        }

        let scaleX = CGFloat(screen.image.width) / screen.frame.width
        let scaleY = CGFloat(screen.image.height) / screen.frame.height

        // Selection is AppKit bottom-left; CGImage crop is top-left within the image.
        let localX = intersection.minX - screen.frame.minX
        let localYFromBottom = intersection.minY - screen.frame.minY
        let localYFromTop = screen.frame.height - localYFromBottom - intersection.height

        var pixelRect = CGRect(
            x: localX * scaleX,
            y: localYFromTop * scaleY,
            width: intersection.width * scaleX,
            height: intersection.height * scaleY
        ).integral

        let imageBounds = CGRect(x: 0, y: 0, width: screen.image.width, height: screen.image.height)
        pixelRect = pixelRect.intersection(imageBounds)
        guard pixelRect.width >= 1, pixelRect.height >= 1,
              let cropped = screen.image.cropping(to: pixelRect)
        else {
            return .failure(.captureFailed("Cannot crop frozen screen"))
        }
        return .success(cropped)
    }

    // MARK: - ScreenCaptureKit (macOS 14+)

    @available(macOS 14.0, *)
    private static func captureWithSCK(rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = display(for: rect, in: content.displays) else {
            throw SnapCopyError.captureFailed("Display not found")
        }

        // SC uses top-left relative to display
        let displayBounds = CGDisplayBounds(display.displayID)
        let crop = CGRect(
            x: rect.minX - displayBounds.minX,
            y: displayBounds.maxY - rect.maxY, // flip to top-left within display
            width: rect.width,
            height: rect.height
        ).integral

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = crop
        config.width = max(1, Int(crop.width) * scale(for: display))
        config.height = max(1, Int(crop.height) * scale(for: display))
        config.showsCursor = false
        config.capturesAudio = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    @available(macOS 14.0, *)
    private static func display(for rect: CGRect, in displays: [SCDisplay]) -> SCDisplay? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return displays.first { CGDisplayBounds($0.displayID).contains(center) } ?? displays.first
    }

    @available(macOS 14.0, *)
    private static func scale(for display: SCDisplay) -> Int {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
        }) else { return 2 }
        return max(1, Int(screen.backingScaleFactor))
    }

    // MARK: - Freeze at hotkey press

    /// Full-screen snapshot of one display. Call for every screen *before* showing overlays
    /// or activating SnapCopy — otherwise Dock menus / popovers dismiss and are missing.
    static func captureScreenSnapshot(_ screen: NSScreen) -> CGImage? {
        // optionOnScreenOnly includes Dock, menus, and popovers visible at this instant.
        CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    /// Freeze every display now. Must run before overlay windows / app activation.
    static func freezeAllScreens() -> [FrozenScreen] {
        NSScreen.screens.compactMap { screen in
            guard let image = captureScreenSnapshot(screen) else { return nil }
            return FrozenScreen(frame: screen.frame, image: image)
        }
    }

    // MARK: - Legacy

    private static func captureLegacy(rect: CGRect) -> Result<CGImage, SnapCopyError> {
        // CRITICAL: optionOnScreenOnly — captures windows + desktop in rect.
        // optionOnScreenBelowWindow + kCGNullWindowID → often only wallpaper.
        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return .failure(.captureFailed("Cannot capture screen (check Screen Recording permission)"))
        }
        return .success(image)
    }

    private static func area(_ r: CGRect) -> CGFloat {
        guard !r.isNull else { return 0 }
        return max(0, r.width) * max(0, r.height)
    }
}

import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureService {
    /// Capture on-screen pixels in an AppKit global rect (origin bottom-left).
    /// Must use on-screen windows — NOT `BelowWindow` + null ID (that yields bare desktop).
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
}

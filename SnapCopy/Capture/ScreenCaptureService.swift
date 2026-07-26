import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureService {
    /// One frozen display buffer taken at ⌥Z press time (native Retina pixels).
    struct FrozenScreen {
        /// AppKit global frame (points, bottom-left origin).
        let frame: CGRect
        /// Full-display bitmap at `scale` pixels per point.
        let image: CGImage
        /// backingScaleFactor used when capturing (typically 2 on Retina).
        let scale: CGFloat
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

        // Use the capture scale (Retina) — never assume 1x.
        let scaleX = CGFloat(screen.image.width) / screen.frame.width
        let scaleY = CGFloat(screen.image.height) / screen.frame.height

        // Selection is AppKit bottom-left; CGImage crop is top-left within the image.
        let localX = intersection.minX - screen.frame.minX
        let localYFromBottom = intersection.minY - screen.frame.minY
        let localYFromTop = screen.frame.height - localYFromBottom - intersection.height

        // Floor origin / ceil size so we don't drop a Retina pixel row/column to rounding.
        let px = floor(localX * scaleX)
        let py = floor(localYFromTop * scaleY)
        let pw = ceil(intersection.width * scaleX)
        let ph = ceil(intersection.height * scaleY)

        var pixelRect = CGRect(x: px, y: py, width: pw, height: ph)
        let imageBounds = CGRect(x: 0, y: 0, width: screen.image.width, height: screen.image.height)
        pixelRect = pixelRect.intersection(imageBounds).integral
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

        let scale = scale(for: display)
        // SC uses top-left relative to display (points).
        let displayBounds = CGDisplayBounds(display.displayID)
        let crop = CGRect(
            x: rect.minX - displayBounds.minX,
            y: displayBounds.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = crop
        // Native Retina output — use display pixel size ratio, not a guessed 1x buffer.
        config.width = max(1, Int((crop.width * CGFloat(scale)).rounded(.up)))
        config.height = max(1, Int((crop.height * CGFloat(scale)).rounded(.up)))
        config.scalesToFit = false
        config.showsCursor = false
        config.capturesAudio = false
        if #available(macOS 14.2, *) {
            config.captureResolution = .best
        }

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
        return max(1, Int(screen.backingScaleFactor.rounded()))
    }

    // MARK: - Freeze at hotkey press (Retina)

    /// Full-display freeze via ScreenCaptureKit at native pixel resolution.
    @available(macOS 14.0, *)
    private static func captureScreenSnapshotSCK(_ screen: NSScreen) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == displayID })
            else { return nil }

            // SCDisplay.width/height are in points (same as NSScreen.frame), not pixels.
            // Multiply by backingScaleFactor for native Retina capture resolution.
            let scale = max(1, screen.backingScaleFactor)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = max(1, Int((CGFloat(display.width) * scale).rounded()))
            config.height = max(1, Int((CGFloat(display.height) * scale).rounded()))
            config.scalesToFit = false
            config.showsCursor = false
            config.capturesAudio = false
            if #available(macOS 14.2, *) {
                config.captureResolution = .best
            }

            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    /// Legacy fallback (may be soft / unavailable on newer macOS). Prefer SCK.
    private static func captureScreenSnapshotLegacy(_ screen: NSScreen) -> CGImage? {
        CGWindowListCreateImage(
            screen.frame,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
    }

    /// Freeze every display at native Retina pixels. Call before overlays / activation.
    static func freezeAllScreens() async -> [FrozenScreen] {
        var result: [FrozenScreen] = []
        result.reserveCapacity(NSScreen.screens.count)

        for screen in NSScreen.screens {
            let scale = max(1, screen.backingScaleFactor)
            var image: CGImage?
            if #available(macOS 14.0, *) {
                image = await captureScreenSnapshotSCK(screen)
            }
            if image == nil {
                image = captureScreenSnapshotLegacy(screen)
            }
            guard let image else { continue }

            // Guard against accidental 1x buffers on Retina (would look soft when pasted).
            let expectedW = screen.frame.width * scale
            if scale >= 1.5, CGFloat(image.width) + 1 < expectedW * 0.75 {
                // Try once more via SCK if legacy returned a soft buffer.
                if #available(macOS 14.0, *), let retry = await captureScreenSnapshotSCK(screen) {
                    result.append(FrozenScreen(frame: screen.frame, image: retry, scale: scale))
                    continue
                }
            }

            result.append(FrozenScreen(frame: screen.frame, image: image, scale: scale))
        }
        return result
    }

    // MARK: - Legacy live capture

    private static func captureLegacy(rect: CGRect) -> Result<CGImage, SnapCopyError> {
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

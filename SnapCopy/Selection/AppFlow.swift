import AppKit
import Foundation
import os.log

private let log = Logger(subsystem: "app.snapcopy", category: "Flow")

@MainActor
final class AppFlow: ObservableObject {
    static let shared = AppFlow()

    @Published var status: String = PermissionGate.statusLine()

    private let overlay = RegionSelectionController()
    private var capturing = false

    private init() {
        overlay.onCaptured = { [weak self] result in
            guard let self else { return }
            self.capturing = false
            SelectionWatcher.shared.isPaused = false
            switch result {
            case .success(let image):
                guard PermissionGate.screenOK else {
                    self.status = "Screen Recording not enabled"
                    PermissionGate.requestScreen()
                    return
                }
                self.copyImage(image)
                self.status = "Ready · select to copy · ⌥Z screenshot"
            case .failure(let error):
                self.status = error.localizedDescription
            }
        }
    }

    func refreshStatus() {
        status = PermissionGate.statusLine()
    }

    func startScreenshot() {
        refreshStatus()
        guard PermissionGate.screenOK else {
            PermissionGate.requestScreen()
            status = "Allow access in the system prompt"
            return
        }
        guard !capturing else { return }
        capturing = true
        SelectionWatcher.shared.isPaused = true
        SelectionWatcher.shared.forgetShown()
        status = "Drag to select, adjust, then Confirm"
        overlay.begin()
    }

    private func copyImage(_ image: CGImage) {
        let scale = Self.pasteboardScale(for: image)

        // TIFF gets a Retina "point size" hint so native Mac apps (Preview, Pages, Notes,
        // Mail) paste the image at its correct on-screen physical size.
        let tiffRep = NSBitmapImageRep(cgImage: image)
        if scale > 1.01 {
            tiffRep.size = NSSize(
                width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale
            )
        }

        // PNG is kept at its natural 1:1 pixel size with no DPI/size hint. Most web upload
        // pipelines (browser paste → File → upload) read raw pixel dimensions directly;
        // an embedded Retina hint on that representation is unnecessary and, on some sites,
        // gets treated as a signal to downscale before upload. A separate, hint-free rep
        // removes that ambiguity while the underlying pixels stay identical either way.
        let pngRep = NSBitmapImageRep(cgImage: image)

        guard let tiff = tiffRep.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
        if let png = pngRep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        log.info("copied \(image.width)x\(image.height) px @\(scale, privacy: .public)x")
    }

    /// Prefer a screen whose full frame matches the bitmap; otherwise main Retina scale.
    private static func pasteboardScale(for image: CGImage) -> CGFloat {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        for screen in NSScreen.screens {
            let s = screen.backingScaleFactor
            if abs(w / s - screen.frame.width) < 2, abs(h / s - screen.frame.height) < 2 {
                return s
            }
        }
        return max(1, NSScreen.main?.backingScaleFactor ?? 2)
    }
}

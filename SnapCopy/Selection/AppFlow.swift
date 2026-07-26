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
        let rep = NSBitmapImageRep(cgImage: image)
        guard let tiff = rep.tiffRepresentation else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        log.info("copied \(image.width)x\(image.height)")
    }
}

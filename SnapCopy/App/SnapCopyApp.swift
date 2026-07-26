import SwiftUI
import AppKit

@main
struct SnapCopyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("SnapCopy", systemImage: "doc.on.clipboard") {
            MenuBarRootView()
                .environmentObject(AppFlow.shared)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        HotkeyManager.shared.onScreenshot = { AppFlow.shared.startScreenshot() }
        HotkeyManager.shared.register()
        SelectionWatcher.shared.start()

        // Only system dialogs — no custom multi-step lectures.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if !PermissionGate.screenOK { PermissionGate.requestScreen() }
            if !PermissionGate.accessibilityOK { PermissionGate.requestAccessibility() }
            AppFlow.shared.refreshStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyManager.shared.unregister()
        SelectionWatcher.shared.stop()
    }
}

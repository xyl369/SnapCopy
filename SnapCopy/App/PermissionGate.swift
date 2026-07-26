import AppKit
import ApplicationServices
import CoreGraphics

enum PermissionGate {
    static var screenOK: Bool { CGPreflightScreenCaptureAccess() }
    static var accessibilityOK: Bool { AXIsProcessTrusted() }

    static func requestScreen() { _ = CGRequestScreenCaptureAccess() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    @MainActor
    static func statusLine() -> String {
        if accessibilityOK && screenOK { return "Ready · select to copy · ⌥Z screenshot" }
        if !accessibilityOK && !screenOK { return "Waiting for system permission…" }
        if !accessibilityOK { return "Waiting for Accessibility…" }
        return "Waiting for Screen Recording…"
    }
}

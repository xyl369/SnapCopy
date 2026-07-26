import ApplicationServices
import AppKit
import Foundation

enum AXSelectionService {
    struct Snapshot: Sendable {
        let text: String
        let bounds: CGRect?
        let role: String?
    }

    /// Read selection only from text-selectable controls; returns nil for lists, buttons, file rows, etc.
    static func captureSelectedText() -> Snapshot? {
        guard AXIsProcessTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()

        // 1) Focused UI element
        if let snap = selectedText(fromFocusedOf: systemWide) {
            return snap
        }

        // 2) Focused application → focused window → focused element
        var appRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &appRef
        ) == .success, let appRef {
            let app = appRef as! AXUIElement
            if let snap = selectedText(fromFocusedOf: app) {
                return snap
            }
            var winRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                app,
                kAXFocusedWindowAttribute as CFString,
                &winRef
            ) == .success, let winRef {
                if let snap = selectedText(fromFocusedOf: winRef as! AXUIElement) {
                    return snap
                }
            }
        }
        return nil
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func promptForAccessibilityIfNeeded() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // MARK: - Private

    private static func selectedText(fromFocusedOf root: AXUIElement) -> Snapshot? {
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            root,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return nil }

        let element = focusedRef as! AXUIElement
        let role = stringAttribute(element, kAXRoleAttribute as String)
        // Hard chrome only — Notion / docs tables often focus AXGroup / AXCell / AXWebArea.
        if let role, hardNonTextRoles.contains(role) { return nil }

        // Prefer real selected-text range; some web apps omit range but still expose selected text.
        let rangeLen = selectedRangeLength(element)
        if let text = readSelectedText(element) {
            if rangeLen > 0 || text.count >= 1 {
                return Snapshot(text: text, bounds: selectionBounds(for: element), role: role)
            }
        }
        return nil
    }

    /// Roles that are never text selection hosts (keep Group/Cell/Table out — web docs use them).
    private static let hardNonTextRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXImage", "AXSplitter", "AXToolbar", "AXTabGroup", "AXSlider",
        "AXIncrementor", "AXDisclosureTriangle", "AXComboBox",
        "AXMenu", "AXMenuItem", "AXMenuBar", "AXProgressIndicator", "AXBusyIndicator",
        "AXScrollBar", "AXValueIndicator", "AXColorWell",
    ]

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let ref else { return nil }
        return ref as? String
    }

    private static func selectedRangeLength(_ element: AXUIElement) -> Int {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeValue = rangeRef else { return 0 }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return 0 }
        return range.length
    }

    private static func readSelectedText(_ element: AXUIElement) -> String? {
        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        ) == .success, let raw = selectedRef as? String {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        if let viaRange = textViaSelectedRange(element) {
            let t = viaRange.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    private static func textViaSelectedRange(_ element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeValue = rangeRef else { return nil }

        var textRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &textRef
        ) == .success else { return nil }
        return textRef as? String
    }

    private static func selectionBounds(for element: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        ) == .success, let rangeValue = rangeRef {
            var boundsRef: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeValue,
                &boundsRef
            ) == .success, let axValue = boundsRef {
                var rect = CGRect.zero
                if AXValueGetValue(axValue as! AXValue, .cgRect, &rect) {
                    return rect
                }
            }
        }
        return frame(of: element)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal = posRef, let sizeVal = sizeRef else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posVal as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }
}

import AppKit
import ApplicationServices

/// The single place where Accessibility API calls are made (per PLAN §4).
///
/// If a future macOS release changes AX behavior, only this file needs to be
/// adapted. Item *movement* no longer uses AX — see `CGEventItemDragger`.
enum AXHelpers {
    /// Returns the AX element at the given point (CG global coordinates).
    static func element(at point: CGPoint, pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var element: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &element)
        guard result == .success else {
            return nil
        }
        return element
    }

    /// Performs the default action (a click) on an element.
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    /// Writes `kAXPositionAttribute` on an element; false when macOS rejects the move.
    static func setPosition(_ point: CGPoint, of element: AXUIElement) -> Bool {
        var mutablePoint = point
        guard let axValue = AXValueCreate(.cgPoint, &mutablePoint) else {
            return false
        }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, axValue) == .success
    }
}

extension AXHelpers {
    static func role(of element: AXUIElement) -> String {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
              let roleValue = roleRef, CFGetTypeID(roleValue) == CFStringGetTypeID() else {
            return "?"
        }
        return unsafeDowncast(roleValue, to: CFString.self) as String
    }

    static func label(of element: AXUIElement) -> String? {
        var titleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
           let titleValue = titleRef, CFGetTypeID(titleValue) == CFStringGetTypeID() {
            let title = unsafeDowncast(titleValue, to: CFString.self) as String
            if !title.isEmpty { return title }
        }
        var descRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef) == .success,
           let descValue = descRef, CFGetTypeID(descValue) == CFStringGetTypeID() {
            return unsafeDowncast(descValue, to: CFString.self) as String
        }
        return nil
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionValue = positionRef, let sizeValue = sizeRef,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return nil
        }
        let positionAX = unsafeDowncast(positionValue, to: AXValue.self)
        let sizeAX = unsafeDowncast(sizeValue, to: AXValue.self)
        guard AXValueGetType(positionAX) == .cgPoint, AXValueGetType(sizeAX) == .cgSize else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionAX, .cgPoint, &point)
        AXValueGetValue(sizeAX, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}

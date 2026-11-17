import AppKit
import CoreGraphics
import Foundation

/// Abstraction over item dragging so the visibility logic can be unit-tested
/// with a fake dragger.
protocol DragsItems: AnyObject {
    @discardableResult
    func drag(windowID: CGWindowID, ownerPID: pid_t, from frame: CGRect, toLeftX destX: CGFloat, barMidY: CGFloat) -> Bool
}

/// Moves and clicks menu bar items by synthesizing ⌘-drag events.
///
/// On macOS 26, `AXUIElementSetAttributeValue(kAXPositionAttribute)` is
/// rejected for menu bar items, so HoverBar uses the synthesized-drag
/// technique pioneered by Ice (MIT) — see Docs/ARCHITECTURE.md. The events
/// embed the item's window id so the system knows which item is being dragged,
/// and the "physical" mouse never has to be near the item.
final class CGEventItemDragger: DragsItems {
    private let farPoint = CGPoint(x: 20_000, y: 20_000)

    @discardableResult
    func drag(windowID: CGWindowID, ownerPID: pid_t, from frame: CGRect, toLeftX destX: CGFloat, barMidY: CGFloat) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return false
        }
        permitAllEvents(source)

        // Dropping at (x, y) inserts the item centered on that point.
        let dropPoint = CGPoint(x: destX + frame.width / 2, y: barMidY)
        guard
            let mouseDown = Self.menuBarItemEvent(
                type: .leftMouseDown,
                flags: .maskCommand,
                at: farPoint,
                windowID: windowID,
                ownerPID: ownerPID,
                source: source
            ),
            let mouseUp = Self.menuBarItemEvent(
                type: .leftMouseUp,
                flags: [],
                at: dropPoint,
                windowID: windowID,
                ownerPID: ownerPID,
                source: source
            )
        else {
            return false
        }

        let cursorRestore = CGEvent(source: nil)?.location
        mouseDown.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.03)
        mouseUp.post(tap: .cgSessionEventTap)
        Thread.sleep(forTimeInterval: 0.02)
        if let cursorRestore {
            CGWarpMouseCursorPosition(cursorRestore)
        }
        return true
    }

    /// Delivers a click to an item at the given onscreen point.
    func click(windowID: CGWindowID, ownerPID: pid_t, at point: CGPoint) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            guard let event = Self.menuBarItemEvent(
                type: type,
                flags: [],
                at: point,
                windowID: windowID,
                ownerPID: ownerPID,
                source: source
            ) else {
                continue
            }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cgSessionEventTap)
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    private func permitAllEvents(_ source: CGEventSource) {
        let permitAll: CGEventFilterMask = [
            .permitLocalMouseEvents,
            .permitLocalKeyboardEvents,
            .permitSystemDefinedEvents,
        ]
        source.setLocalEventsFilterDuringSuppressionState(permitAll, state: .eventSuppressionStateSuppressionInterval)
        source.setLocalEventsFilterDuringSuppressionState(permitAll, state: .eventSuppressionStateRemoteMouseDrag)
        source.localEventsSuppressionInterval = 0
    }

    /// Builds a mouse event addressed to a specific menu bar item window.
    private static func menuBarItemEvent(
        type: CGEventType,
        flags: CGEventFlags,
        at point: CGPoint,
        windowID: CGWindowID,
        ownerPID: pid_t,
        source: CGEventSource
    ) -> CGEvent? {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return nil
        }
        event.flags = flags
        let window = Int64(windowID)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ownerPID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: window)
        event.setIntegerValueField(Self.windowIDField, value: window)
        return event
    }

    /// Undocumented window-id field (0x33) — same value Ice uses.
    private static let windowIDField = CGEventField(rawValue: 0x33) ?? .mouseEventWindowUnderMousePointer
}

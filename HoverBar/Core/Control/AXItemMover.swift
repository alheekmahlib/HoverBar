import ApplicationServices

/// Moves menu bar items by writing `kAXPositionAttribute` on their
/// `AXMenuBarItem` elements — verified working on macOS 26 (see
/// Docs/ARCHITECTURE.md). Writing on the bar container itself is rejected,
/// which is why discovery must surface per-item elements.
final class AXItemMover: MovesItems {
    @discardableResult
    func move(_ element: AXUIElement, to point: CGPoint) -> Bool {
        AXHelpers.setPosition(point, of: element)
    }
}

/// Abstraction over item movement so visibility logic stays unit-testable.
protocol MovesItems: AnyObject {
    @discardableResult
    func move(_ element: AXUIElement, to point: CGPoint) -> Bool
}

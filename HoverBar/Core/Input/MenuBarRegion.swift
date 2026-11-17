import AppKit

/// Menu bar rectangles, one per screen, in AppKit global coordinates
/// (origin at the primary display's bottom-left corner — the same space as
/// `NSEvent.mouseLocation`).
enum MenuBarRegion {
    /// Fallback thickness when the status bar cannot be queried.
    static let fallbackHeight: CGFloat = 24

    /// Height of the menu bar on the current system.
    static func barHeight(statusBarThickness: CGFloat?) -> CGFloat {
        statusBarThickness ?? fallbackHeight
    }

    /// The menu bar rectangle along the top edge of the given screen.
    static func menuBarRect(forScreenFrame frame: CGRect, barHeight: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: frame.maxY - barHeight,
            width: frame.width,
            height: barHeight
        )
    }

    /// Whether a point lies inside any of the given rectangles.
    static func contains(_ point: CGPoint, inRects rects: [CGRect]) -> Bool {
        rects.contains { $0.contains(point) }
    }
}

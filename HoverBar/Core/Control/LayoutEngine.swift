import CoreGraphics

/// Pure geometry for hiding and staging menu bar items. All coordinates are in
/// the CG global space (origin at the primary display's top-left corner).
enum LayoutEngine {
    /// Frames for a sequential strip of hidden items, parked offscreen to the
    /// left of every display. Items are laid side by side (no overlap) so their
    /// snapshots stay individually capturable.
    static func hiddenFrames(widths: [CGFloat], y: CGFloat, height: CGFloat, margin: CGFloat = 120) -> [CGRect] {
        let totalWidth = widths.reduce(0, +)
        var x = -(totalWidth + margin)
        return widths.map { width in
            let frame = CGRect(x: x, y: y, width: width, height: height)
            x += width
            return frame
        }
    }

    /// A temporary onscreen frame for a hidden item, placed just left of the
    /// given reference frame (the leftmost always-visible item) so a proxied
    /// click lands at a plausible menu bar position.
    static func stagingFrame(width: CGFloat, height: CGFloat, leftOf reference: CGRect, spacing: CGFloat = 2) -> CGRect {
        CGRect(
            x: reference.minX - width - spacing,
            y: reference.minY,
            width: width,
            height: height
        )
    }

    /// The usable width of a menu bar after excluding a centered notch area.
    static func effectiveWidth(ofBar bar: CGRect, notchWidth: CGFloat) -> CGFloat {
        max(0, bar.width - notchWidth)
    }
}

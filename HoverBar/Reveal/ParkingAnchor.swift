import AppKit
import CoreGraphics

/// The Ice-style cover window: an extra-long, empty status item that extends
/// the menu bar background over the area where hidden items are parked.
///
/// Menu bar items can only be dropped where a real item window exists, so
/// "hiding" is done by (1) extending a cover item across the bar and
/// (2) dragging third-party items beneath it — they stay alive, clickable via
/// our tray, and invisible to the user. Ports Ice's hidden-section trick.
final class ParkingAnchor {
    private var statusItem: NSStatusItem?
    private(set) var frame: CGRect = .zero

    /// Installs the cover starting at the left edge of the bar.
    func install(x: CGFloat = 0, y: CGFloat = 0) {
        let item = NSStatusBar.system.statusItem(withLength: 10_000)
        item.button?.image = nil
        item.button?.toolTip = ""
        statusItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let window = item.button?.window else { return }
            window.setFrameOrigin(CGPoint(x: x, y: y))
            // The cover's own width would span past the screen; clip the
            // reported frame to the physical bar.
            let barWidth = NSScreen.main?.frame.width ?? 1512
            self?.frame = CGRect(x: x, y: y, width: barWidth, height: window.frame.height)
            DiagnosticLog.write("cover installed frame=\(self?.frame ?? .zero)")
        }
    }

    /// Items parked at x below this boundary live beneath the cover.
    var coveredBoundary: CGFloat {
        // Park items in the left half of the bar; everything from the
        /// rightmost system item onward stays visible.
        frame.maxX - 700
    }
}

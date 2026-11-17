import AppKit
import CoreGraphics

/// Activates a hidden menu bar item's menu on its behalf (PLAN §3.2, risk 6.10).
///
/// Strategy: press the item's AX button directly when it is on screen. When it
/// is parked offscreen, stage it on screen (just left of the leftmost visible
/// item) with a synthesized drag, deliver a window-addressed synthetic click,
/// and leave re-hiding to the next collapse pass.
final class ClickProxy {
    private let mover: MovesItems

    init(mover: MovesItems = AXItemMover()) {
        self.mover = mover
    }

    enum Outcome: Equatable, CustomStringConvertible {
        case pressedDirectly
        case pressedAfterStaging
        case failed

        var description: String {
            switch self {
            case .pressedDirectly: "pressed-directly"
            case .pressedAfterStaging: "pressed-after-staging"
            case .failed: "failed"
            }
        }
    }

    @discardableResult
    func activate(item: TrackedItem, anchor: CGRect?) -> Outcome {
        if item.isOnScreenNow, let button = item.axButton, AXHelpers.press(button) {
            Log.reveal.info("pressed \(item.info.displayName, privacy: .public) directly")
            return .pressedDirectly
        }

        guard let anchor else {
            Log.reveal.error("click proxy: no visible anchor to stage against")
            return .failed
        }

        let staged = LayoutEngine.stagingFrame(
            width: item.info.frame.width,
            height: item.info.frame.height,
            leftOf: anchor
        )
        guard let element = item.info.element ?? item.axButton else {
            Log.reveal.error("click proxy: no element for \(item.info.displayName, privacy: .public)")
            return .failed
        }
        guard mover.move(element, to: staged.origin) else {
            Log.reveal.error("click proxy: staging move rejected for \(item.info.displayName, privacy: .public)")
            return .failed
        }
        Thread.sleep(forTimeInterval: 0.08)
        if AXHelpers.press(element) {
            Log.reveal.info("staged and pressed \(item.info.displayName, privacy: .public)")
            return .pressedAfterStaging
        }
        Log.reveal.error("click proxy: press failed for \(item.info.displayName, privacy: .public)")
        return .failed
    }
}

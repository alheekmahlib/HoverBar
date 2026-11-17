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
    private let dragger: DragsItems

    init(mover: MovesItems = AXItemMover(), dragger: DragsItems = CGEventItemDragger()) {
        self.mover = mover
        self.dragger = dragger
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
        var stagedX = staged.minX
        if !mover.move(element, to: staged.origin) {
            // AX write rejected (hosted item) — stage with a synthesized drag.
            guard item.info.windowID != 0, let dragger = dragger as? CGEventItemDragger else {
                Log.reveal.error("click proxy: no staging path for \(item.info.displayName, privacy: .public)")
                return .failed
            }
            guard dragger.drag(
                windowID: item.info.windowID,
                ownerPID: item.info.ownerPID,
                from: item.info.frame,
                toLeftX: staged.minX,
                barMidY: staged.midY
            ) else {
                Log.reveal.error("click proxy: staging drag rejected for \(item.info.displayName, privacy: .public)")
                return .failed
            }
        }
        Thread.sleep(forTimeInterval: 0.12)
        stagedX += item.info.frame.width / 2
        if AXHelpers.press(element) {
            Log.reveal.info("staged and pressed \(item.info.displayName, privacy: .public)")
            return .pressedAfterStaging
        }
        if let dragger = dragger as? CGEventItemDragger, item.info.windowID != 0 {
            dragger.click(
                windowID: item.info.windowID,
                ownerPID: item.info.ownerPID,
                at: CGPoint(x: stagedX, y: staged.midY)
            )
            Log.reveal.info("staged and clicked \(item.info.displayName, privacy: .public)")
            return .pressedAfterStaging
        }
        Log.reveal.error("click proxy: press failed for \(item.info.displayName, privacy: .public)")
        return .failed
    }
}

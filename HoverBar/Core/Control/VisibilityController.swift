import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// One discovered menu bar item, tracked across scans: its AX handle, its
/// pre-hide frame, its visibility state and its cached snapshot.
final class TrackedItem {
    let identity: ItemIdentity

    /// AX handle captured at discovery; used for moves and presses.
    let axButton: AXUIElement?

    /// Latest scan info.
    private(set) var info: MenuBarItem

    /// Frame captured before the first hide; used by `restoreAll()`.
    private(set) var originalFrame: CGRect

    private(set) var isHidden = false

    /// Snapshot provider captured right before the item was hidden (tray image).
    private(set) var snapshotProvider: (() -> NSImage?)?

    /// True while a hide attempt is in flight; keeps the item tracked when its
    /// window detaches mid-attempt.
    private(set) var hidingAttempted = false

    func beginHideAttempt() {
        hidingAttempted = true
    }

    func endHideAttempt() {
        hidingAttempted = false
    }

    /// Set when macOS rejected the move; the item stays visible and is logged
    /// as unsupported (PLAN §3.2).
    private(set) var moveFailed = false

    /// Whether the item is currently displayed in the menu bar.
    var isOnScreenNow: Bool {
        !isHidden && info.isOnScreen
    }

    init(info: MenuBarItem, axButton: AXUIElement?) {
        self.info = info
        self.identity = info.identity
        // Prefer the scanner's own element: for unlabeled hosted items it is
        // the per-item AX child, whereas positional lookup returns the bar.
        self.axButton = info.element ?? axButton
        self.originalFrame = info.frame
    }

    func update(info newInfo: MenuBarItem) {
        info = newInfo
        if !isHidden, newInfo.isOnScreen {
            originalFrame = newInfo.frame
        }
    }

    /// Keeps stale info but flags the item as parked (its window is detached).
    func markParkedOffscreen() {
        var parked = info
        parked = parked.updatingIsOnScreen(false)
        info = parked
    }

    func markHidden() {
        isHidden = true
    }

    func markRestored() {
        isHidden = false
    }

    func markMoveFailed() {
        moveFailed = true
        isHidden = false
    }

    func storeSnapshot(_ provider: @escaping () -> NSImage?) {
        snapshotProvider = provider
    }
}

/// Decides which items participate in hiding.
struct VisibilityPolicy {
    /// MVP policy (PLAN Phase 1, updated for macOS 26 hosting): hide
    /// third-party items — unlabeled items hosted inside ControlCenter, plus
    /// windows owned by non-Apple processes. Keep Apple system modules,
    /// protected items and HoverBar's own item visible.
    var shouldHide: (MenuBarItem) -> Bool = { item in
        if ProtectedItems.isImmovable(item.identity) || ProtectedItems.isNonHideable(item.identity) {
            return false
        }
        switch item.owner {
        case .hoverBar:
            return false
        case .controlCenter, .systemUIServer:
            return !SystemModules.isSystemTitle(item.identity.title)
        case .other:
            return true
        }
    }
}

/// Summary of one hide/restore pass.
struct MoveSummary: Equatable {
    var moved = 0
    var failed = 0
    var skipped = 0

    var logString: String {
        "moved=\(moved) failed=\(failed) skipped=\(skipped)"
    }
}

/// Orchestrates scanning, tracking and hiding/restoring of menu bar items.
final class VisibilityController {
    private let scanner: ScansItems
    private let mover: MovesItems
    private let dragger: DragsItems
    private let snapshotStore: ItemSnapshotStore
    var policy: VisibilityPolicy

    private(set) var tracked: [TrackedItem] = []

    var hiddenItems: [TrackedItem] {
        tracked.filter(\.isHidden)
    }

    /// The leftmost always-visible item on the main screen, if any — the anchor
    /// used when staging a hidden item for a proxied click.
    var leftmostVisibleAnchor: CGRect? {
        tracked
            .filter({ !$0.isHidden && $0.info.isOnScreen && $0.info.frame.width > 1 })
            .map(\.info.frame)
            .min { $0.minX < $1.minX }
    }

    init(
        scanner: ScansItems = AXMenuBarItemScanner(),
        mover: MovesItems = AXItemMover(),
        dragger: DragsItems = CGEventItemDragger(),
        snapshotStore: ItemSnapshotStore = ItemSnapshotStore(),
        policy: VisibilityPolicy = VisibilityPolicy()
    ) {
        self.scanner = scanner
        self.mover = mover
        self.dragger = dragger
        self.snapshotStore = snapshotStore
        self.policy = policy
    }

    /// Frame of the cover window, when installed.
    var parkingAnchorFrame: (() -> CGRect?)?

    /// Items whose x falls below this boundary count as hidden (under cover).
    var coveredBoundary: CGFloat = .greatestFiniteMagnitude

    /// Resolves the AX handle for a newly seen item; injectable for tests.
    var elementResolver: (MenuBarItem) -> AXUIElement? = { item in
        AXHelpers.element(at: CGPoint(x: item.frame.midX, y: item.frame.midY), pid: item.ownerPID)
    }

    /// Scans the window list and merges results into tracked items.
    /// Items that are currently hidden and whose window vanished (parked
    /// offscreen by a drag) are kept in the tracked list.
    @discardableResult
    func rescan() -> [MenuBarItem] {
        let items = scanner.scanAllItems()
        var seen = Set<ItemIdentity>()

        for item in items {
            seen.insert(item.identity)
            if let existing = tracked.first(where: { $0.identity == item.identity }) {
                existing.update(info: item)
            } else {
                let button = item.isOnScreen ? elementResolver(item) : nil
                tracked.append(TrackedItem(info: item, axButton: button))
            }
        }
        for trackedItem in tracked where !seen.contains(trackedItem.identity) {
            if trackedItem.isHidden || trackedItem.hidingAttempted {
                trackedItem.markParkedOffscreen()
            }
        }
        tracked.removeAll { !seen.contains($0.identity) && !$0.isHidden && !$0.hidingAttempted }
        if !items.isEmpty {
            let summary = items
                .map { "\($0.displayName)(\($0.owner), \($0.isOnScreen ? "on" : "off")screen)" }
                .joined(separator: ", ")
            DiagnosticLog.write("scan: \(items.count) items → [\(summary)]")
        }
        return items
    }

    /// Hides every policy-eligible visible item. Labeled items with an AX
    /// element move via AX; hosted unlabeled items are dragged offscreen with
    /// a synthesized ⌘-drag (their window detaches — that counts as hidden).
    /// Each item is handled with a fresh scan because successful drags change
    /// the window ids of the remaining items.
    @discardableResult
    func applyHiddenState() -> MoveSummary {
        rescan()
        var summary = MoveSummary()
        var slotIndex = 0
        var attempts: [TrackedItem] = []

        while true {
            guard let next = tracked.first(where: { candidate in
                !candidate.moveFailed
                    && candidate.info.isOnScreen
                    && candidate.info.frame.minX >= 0
                    && policy.shouldHide(candidate.info)
                    && (!candidate.isHidden || candidate.info.isOnScreen)
            }) else {
                break
            }
            let windowID = next.info.windowID
            next.storeSnapshot { [snapshotStore] in
                windowID != 0 ? snapshotStore.snapshot(windowID: windowID) : nil
            }
            next.beginHideAttempt()
            attempts.append(next)

            // Park items beneath the cover window (Ice-style), from the left
            // edge rightward; ~60px per slot keeps windows from overlapping.
            let targetX: CGFloat = 30 + CGFloat(slotIndex) * 60
            slotIndex += 1
            for _ in 0..<3 {
                if let element = next.axButton {
                    // Try a direct AX position write first — works for labeled
                    // system items and (observed) some hosted items.
                    _ = mover.move(element, to: CGPoint(x: targetX, y: next.info.frame.minY))
                }
                _ = dragger.drag(
                    windowID: next.info.windowID,
                    ownerPID: next.info.ownerPID,
                    from: next.info.frame,
                    toLeftX: targetX,
                    barMidY: next.info.frame.midY
                )
                Thread.sleep(forTimeInterval: 0.12)
                rescan()
                let gone = next.info.frame.minX < coveredBoundary || !next.info.isOnScreen
                if gone {
                    break
                }
            }

            let parked = next.info.frame.minX < coveredBoundary
            if parked || next.info.frame.minX < 0 || !next.info.isOnScreen {
                next.markHidden()
                summary.moved += 1
            } else {
                next.markMoveFailed()
                next.endHideAttempt()
                summary.failed += 1
                DiagnosticLog.write("move-rejected: \(next.info.displayName) frame=\(next.info.frame)")
            }
        }

        summary.skipped = max(tracked.count - summary.moved - summary.failed, 0)
        let hiddenNames = tracked.filter(\.isHidden).map(\.identity.title).joined(separator: ", ")
        DiagnosticLog.write("hide-pass: \(summary.logString) hidden=[\(hiddenNames)]")
        return summary
    }

    /// Restores every hidden item to its original frame (used on quit and on
    /// demand from the menu).
    @discardableResult
    func restoreAll() -> MoveSummary {
        var summary = MoveSummary()
        let toRestore = tracked.filter(\.isHidden)

        for item in toRestore {
            if let element = item.axButton, item.originalFrame.minX >= 0 {
                mover.move(element, to: item.originalFrame.origin)
            } else if item.info.windowID != 0 {
                // Dragged-offscreen items need a drag back on screen.
                _ = dragger.drag(
                    windowID: item.info.windowID,
                    ownerPID: item.info.ownerPID,
                    from: item.info.frame,
                    toLeftX: item.originalFrame.minX,
                    barMidY: item.originalFrame.midY
                )
            } else if let element = item.axButton {
                mover.move(element, to: item.originalFrame.origin)
            }
        }
        guard !toRestore.isEmpty else {
            DiagnosticLog.write("restore-pass: nothing hidden")
            return summary
        }

        Thread.sleep(forTimeInterval: 0.12)
        rescan()
        for item in toRestore {
            if item.info.isOnScreen, item.info.frame.minX >= 0 {
                item.markRestored()
                summary.moved += 1
            } else {
                summary.failed += 1
                DiagnosticLog.write("restore-rejected: \(item.info.displayName)")
            }
        }
        DiagnosticLog.write("restore-pass: \(summary.logString)")
        return summary
    }
}

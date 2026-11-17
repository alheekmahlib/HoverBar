import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// AX-based menu bar discovery — the macOS 26 way.
///
/// Findings (Docs/ARCHITECTURE.md): items live as `AXMenuBarItem` children of
/// the `AXMenuBar` inside each hosting process (ControlCenter hosts both system
/// modules and third-party NSStatusItems). Writing `kAXPositionAttribute` on
/// the *item* elements works; writing on the bar does not. The CG window list
/// is still consulted to map items to window ids for snapshot capture.
final class AXMenuBarItemScanner: ScansItems {
    private let cgScanner = MenuBarItemScanner()

    func scanAllItems() -> [MenuBarItem] {
        let cgItems = cgScanner.scanAllItems()
        var hostPIDs = Set(cgItems.map(\.ownerPID))
        // ControlCenter is a host even when its CG windows are all detached.
        if let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first {
            hostPIDs.insert(controlCenter.processIdentifier)
        }

        var results: [MenuBarItem] = []
        for pid in hostPIDs {
            results.append(contentsOf: items(inHost: pid, cgItems: cgItems.filter { $0.ownerPID == pid }))
        }
        return results.sorted { $0.frame.minX < $1.frame.minX }
    }

    private func items(inHost pid: pid_t, cgItems: [MenuBarItem]) -> [MenuBarItem] {
        let app = AXUIElementCreateApplication(pid)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return cgItems
        }
        guard let menuBar = children.first(where: { AXHelpers.role(of: $0) == "AXMenuBar" }) else {
            return cgItems
        }
        var itemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &itemsRef) == .success,
              let axItems = itemsRef as? [AXUIElement] else {
            return cgItems
        }

        let bundleID = Self.bundleIdentifier(pid: pid)
        let owner = Self.owner(pid: pid, bundleID: bundleID)
        var matchedWindowIDs = Set<CGWindowID>()
        var found: [MenuBarItem] = []

        // Pass 1: labeled AX items match their CG window by position.
        for element in axItems {
            let label = AXHelpers.label(of: element)
            guard let label, !label.isEmpty,
                  let frame = AXHelpers.frame(of: element),
                  frame.width > 1, frame.height > 1 else {
                continue
            }
            let window = cgItems.first {
                $0.ownerPID == pid && !matchedWindowIDs.contains($0.windowID)
                    && abs($0.frame.minX - frame.minX) < 14
            }
            if let window {
                matchedWindowIDs.insert(window.windowID)
            }
            found.append(makeItem(
                element: element,
                label: label,
                frame: frame,
                windowID: window?.windowID ?? 0,
                bundleID: bundleID,
                owner: owner,
                pid: pid
            ))
        }

        // Pass 2: unlabeled/degenerate AX items (hosted third-party NSStatusItems)
        // adopt the remaining CG windows in visual order.
        var remainingWindows = cgItems.filter { !matchedWindowIDs.contains($0.windowID) }
        let unlabeled = axItems.filter { element in
            guard let frame = AXHelpers.frame(of: element) else { return false }
            let label = AXHelpers.label(of: element)
            return label?.isEmpty != false || frame.width < 2 || frame.height < 2
        }
        for element in unlabeled {
            guard let window = remainingWindows.first else { continue }
            remainingWindows.removeFirst()
            found.append(makeItem(
                element: element,
                label: nil,
                frame: window.frame,
                windowID: window.windowID,
                bundleID: bundleID,
                owner: owner,
                pid: pid
            ))
        }

        // Pass 3: CG windows with no AX representation at all.
        for window in remainingWindows {
            found.append(makeItem(
                element: nil,
                label: nil,
                frame: window.frame,
                windowID: window.windowID,
                bundleID: bundleID,
                owner: owner,
                pid: pid
            ))
        }
        return found
    }

    private func makeItem(
        element: AXUIElement?,
        label: String?,
        frame: CGRect,
        windowID: CGWindowID,
        bundleID: String,
        owner: MenuBarItemOwner,
        pid: pid_t
    ) -> MenuBarItem {
        let identity: ItemIdentity
        if let label, !label.isEmpty {
            identity = ItemIdentity(ownerBundleID: bundleID, title: label)
        } else if windowID != 0 {
            identity = ItemIdentity.fallback(ownerBundleID: bundleID, windowID: UInt32(windowID))
        } else {
            identity = ItemIdentity(ownerBundleID: bundleID, title: "detached")
        }
        return MenuBarItem(
            identity: identity,
            owner: owner,
            ownerPID: pid,
            windowID: windowID,
            frame: frame,
            isOnScreen: frame.minX >= 0,
            displayName: label?.nilIfEmpty ?? bundleID,
            element: element
        )
    }

    private static func bundleIdentifier(pid: pid_t) -> String {
        if let running = NSRunningApplication(processIdentifier: pid),
           let bundleID = running.bundleIdentifier {
            return bundleID
        }
        return "host-\(pid)"
    }

    private static func owner(pid: pid_t, bundleID: String) -> MenuBarItemOwner {
        if pid == ProcessInfo.processInfo.processIdentifier {
            return .hoverBar
        }
        switch bundleID {
        case "com.apple.controlcenter":
            return .controlCenter
        case "com.apple.SystemUIServer":
            return .systemUIServer
        default:
            return .other(bundleID)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

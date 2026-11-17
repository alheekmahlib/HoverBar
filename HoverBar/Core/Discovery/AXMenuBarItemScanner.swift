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
        guard let (_, axItems) = Self.menuBarItems(inHost: pid) else {
            return cgItems
        }
        let bundleID = Self.bundleIdentifier(pid: pid)
        let host = Host(bundleID: bundleID, owner: Self.owner(pid: pid, bundleID: bundleID), pid: pid)

        var matched = Set<CGWindowID>()
        var found = Self.labeledItems(axItems: axItems, cgItems: cgItems, host: host, matched: &matched)

        var remaining = cgItems.filter { !matched.contains($0.windowID) }
        found.append(contentsOf: Self.unlabeledItems(axItems: axItems, remaining: &remaining, host: host))
        found.append(contentsOf: remaining.map { window in
            Self.makeItem(element: nil, label: nil, frame: window.frame, windowID: window.windowID, host: host)
        })
        return found
    }

    /// The AXMenuBar element and its AXMenuBarItem children in a host process.
    private static func menuBarItems(inHost pid: pid_t) -> (AXUIElement, [AXUIElement])? {
        let app = AXUIElementCreateApplication(pid)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement],
              let menuBar = children.first(where: { AXHelpers.role(of: $0) == "AXMenuBar" }) else {
            return nil
        }
        var itemsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &itemsRef) == .success,
              let axItems = itemsRef as? [AXUIElement] else {
            return nil
        }
        return (menuBar, axItems)
    }

    /// Pass 1: labeled AX items matched to their CG window by position.
    private static func labeledItems(
        axItems: [AXUIElement],
        cgItems: [MenuBarItem],
        host: Host,
        matched: inout Set<CGWindowID>
    ) -> [MenuBarItem] {
        let pid = host.pid
        var found: [MenuBarItem] = []
        for element in axItems {
            let label = AXHelpers.label(of: element)
            guard let label, !label.isEmpty,
                  let frame = AXHelpers.frame(of: element),
                  frame.width > 1, frame.height > 1 else {
                continue
            }
            let window = cgItems.first {
                $0.ownerPID == pid && !matched.contains($0.windowID)
                    && abs($0.frame.minX - frame.minX) < 14
            }
            if let window {
                matched.insert(window.windowID)
            }
            found.append(makeItem(element: element, label: label, frame: frame, windowID: window?.windowID ?? 0, host: host))
        }
        return found
    }

    /// Pass 2: unlabeled/degenerate AX items (hosted third-party) adopt the
    /// remaining CG windows in visual order.
    private static func unlabeledItems(
        axItems: [AXUIElement],
        remaining: inout [MenuBarItem],
        host: Host
    ) -> [MenuBarItem] {
        var found: [MenuBarItem] = []
        for element in axItems {
            let label = AXHelpers.label(of: element)
            let frame = AXHelpers.frame(of: element)
            let unlabeled = label?.isEmpty != false || (frame?.width ?? 0) < 2 || (frame?.height ?? 0) < 2
            guard unlabeled, let window = remaining.first else {
                continue
            }
            remaining.removeFirst()
            found.append(makeItem(element: element, label: nil, frame: window.frame, windowID: window.windowID, host: host))
        }
        return found
    }

    /// Shared facts about one hosting process.
    private struct Host {
        let bundleID: String
        let owner: MenuBarItemOwner
        let pid: pid_t
    }

    /// Builds one item from merged AX/CG facts.
    private static func makeItem(
        element: AXUIElement?,
        label: String?,
        frame: CGRect,
        windowID: CGWindowID,
        host: Host
    ) -> MenuBarItem {
        let identity: ItemIdentity
        if let label, !label.isEmpty {
            identity = ItemIdentity(ownerBundleID: host.bundleID, title: label)
        } else if windowID != 0 {
            identity = ItemIdentity.fallback(ownerBundleID: host.bundleID, windowID: UInt32(windowID))
        } else {
            identity = ItemIdentity(ownerBundleID: host.bundleID, title: "detached")
        }
        return MenuBarItem(
            identity: identity,
            owner: host.owner,
            ownerPID: host.pid,
            windowID: windowID,
            frame: frame,
            isOnScreen: frame.minX >= 0,
            displayName: label?.nilIfEmpty ?? host.bundleID,
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

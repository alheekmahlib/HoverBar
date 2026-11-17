import AppKit
import CoreGraphics
import Foundation

/// Abstraction over window scanning so discovery can be unit-tested.
protocol ScansItems: AnyObject {
    func scanAllItems() -> [MenuBarItem]
}

/// Scans the window list for menu bar item windows.
///
/// Findings on macOS 26 (documented in Docs/ARCHITECTURE.md): both system
/// modules and third-party NSStatusItems are hosted by the `ControlCenter`
/// process, under generic `Item-N` titles — `SystemUIServer` owns no item
/// windows at all. Some apps also own their item windows directly. Discovery
/// therefore accepts every layer-25 window that looks like a bar item
/// (geometry check) and classifies ownership afterwards.
final class MenuBarItemScanner: ScansItems {
    private let statusWindowLayer = 25

    /// Scans every menu bar item window, including currently hidden (offscreen) ones.
    func scanAllItems() -> [MenuBarItem] {
        guard let rawList = CGWindowListCopyWindowInfo([], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let items = rawList
            .compactMap { Self.item(fromWindowInfo: $0, layer: statusWindowLayer) }
            .sorted { $0.frame.minX < $1.frame.minX }
        return Self.uniquifyTitles(items)
    }

    /// Extracts a menu bar item from one window-list record; nil when the record
    /// does not look like a menu bar item window.
    static func item(fromWindowInfo info: [String: Any], layer: Int) -> MenuBarItem? {
        guard let rawLayer = info[kCGWindowLayer as String] as? Int, rawLayer == layer else {
            return nil
        }
        guard let windowID = info[kCGWindowNumber as String] as? Int else {
            return nil
        }
        let ownerPID = info[kCGWindowOwnerPID as String] as? Int ?? Int(NSNotFound)
        let ownerName = (info[kCGWindowOwnerName as String] as? String) ?? ""
        let title = info[kCGWindowName as String] as? String

        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let boundsDict = bounds as CFDictionary? else {
            return nil
        }
        var frame = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDict, &frame) else {
            return nil
        }
        // Menu bar items are thin strips along the very top of a display.
        guard frame.width > 1, (16...44).contains(frame.height), frame.maxY <= 44 else {
            return nil
        }

        frame.origin.x = frame.origin.x.rounded()

        let bundleID = Self.bundleIdentifier(ownerPID: pid_t(ownerPID), ownerName: ownerName)
        let owner = Self.owner(bundleID: bundleID, ownerName: ownerName, ownerPID: pid_t(ownerPID))
        let identity: ItemIdentity
        if let title, !title.isEmpty {
            identity = ItemIdentity(ownerBundleID: bundleID, title: title)
        } else {
            identity = ItemIdentity.fallback(ownerBundleID: bundleID, windowID: UInt32(windowID))
        }
        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Int ?? 0) == 1

        return MenuBarItem(
            identity: identity,
            owner: owner,
            ownerPID: pid_t(ownerPID),
            windowID: CGWindowID(windowID),
            frame: frame,
            isOnScreen: isOnScreen,
            displayName: Self.displayName(owner: owner, title: title, ownerName: ownerName)
        )
    }

    /// Disambiguates duplicate titles within one scan ("Item", "Item#2", …) so
    /// identities stay unique when several windows share a title.
    static func uniquifyTitles(_ items: [MenuBarItem]) -> [MenuBarItem] {
        var counts: [String: Int] = [:]
        return items.map { item in
            let key = item.identity.ownerBundleID + "#" + item.identity.title
            counts[key, default: 0] += 1
            guard let count = counts[key], count > 1 else {
                return item
            }
            return item.reidentified(title: "\(item.identity.title)#\(count)")
        }
    }

    private static func owner(bundleID: String, ownerName: String, ownerPID: pid_t) -> MenuBarItemOwner {
        if ownerPID == ProcessInfo.processInfo.processIdentifier {
            return .hoverBar
        }
        if bundleID == "com.apple.controlcenter" || ownerName == "ControlCenter" || ownerName == "Control Center" {
            return .controlCenter
        }
        if bundleID == "com.apple.SystemUIServer" || ownerName == "SystemUIServer" {
            return .systemUIServer
        }
        return .other(bundleID.isEmpty ? ownerName : bundleID)
    }

    private static func bundleIdentifier(ownerPID: pid_t, ownerName: String) -> String {
        if let running = NSRunningApplication(processIdentifier: ownerPID),
           let bundleID = running.bundleIdentifier {
            return bundleID
        }
        return canonicalOwner(fromName: ownerName) ?? ownerName
    }

    private static func canonicalOwner(fromName name: String) -> String? {
        switch name {
        case "SystemUIServer":
            return "com.apple.SystemUIServer"
        case "ControlCenter", "Control Center":
            return "com.apple.controlcenter"
        default:
            return nil
        }
    }

    private static func displayName(owner: MenuBarItemOwner, title: String?, ownerName: String) -> String {
        if owner == .controlCenter, let title {
            if let mapped = SystemModules.displayTitle(for: title) {
                return mapped
            }
        }
        if let title, !title.isEmpty {
            return title
        }
        return ownerName.nilIfEmpty ?? owner.bundleIdentifier ?? "Unknown"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

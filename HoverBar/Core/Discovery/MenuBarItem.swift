import ApplicationServices
import CoreGraphics
import Foundation

/// The process that owns a menu bar item window.
enum MenuBarItemOwner: Equatable {
    case systemUIServer
    case controlCenter
    case hoverBar
    case other(String)

    /// Bundle identifier of the owning process, if known.
    var bundleIdentifier: String? {
        switch self {
        case .systemUIServer:
            return "com.apple.SystemUIServer"
        case .controlCenter:
            return "com.apple.controlcenter"
        case .hoverBar:
            return Bundle.main.bundleIdentifier
        case .other(let bundle):
            return bundle
        }
    }
}

/// A snapshot of one menu bar item, as discovered by ``MenuBarItemScanner``.
///
/// Coordinates use the Core Graphics global space (origin at the primary
/// display's top-left corner), matching `CGWindowList` conventions.
struct MenuBarItem: Equatable {
    /// Stable fingerprint used to match the item across scans.
    let identity: ItemIdentity

    /// The owning process.
    let owner: MenuBarItemOwner

    /// Process identifier of the owning process.
    let ownerPID: pid_t

    /// Identifier of the item's window.
    let windowID: CGWindowID

    /// Frame of the item's window, in CG global coordinates.
    let frame: CGRect

    /// Whether the item's window is currently on screen.
    let isOnScreen: Bool

    /// A name suited for display to the user.
    let displayName: String

    /// The item's AX element (`AXMenuBarItem`), when discovered via AX.
    let element: AXUIElement?

    init(
        identity: ItemIdentity,
        owner: MenuBarItemOwner,
        ownerPID: pid_t,
        windowID: CGWindowID,
        frame: CGRect,
        isOnScreen: Bool,
        displayName: String,
        element: AXUIElement? = nil
    ) {
        self.identity = identity
        self.owner = owner
        self.ownerPID = ownerPID
        self.windowID = windowID
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.displayName = displayName
        self.element = element
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity
    }

    /// The same item with an updated on-screen flag.
    func updatingIsOnScreen(_ onScreen: Bool) -> MenuBarItem {
        MenuBarItem(
            identity: identity,
            owner: owner,
            ownerPID: ownerPID,
            windowID: windowID,
            frame: frame,
            isOnScreen: onScreen,
            displayName: displayName,
            element: element
        )
    }

    /// The same item under a disambiguated identity title.
    func reidentified(title: String) -> MenuBarItem {
        MenuBarItem(
            identity: ItemIdentity(ownerBundleID: identity.ownerBundleID, title: title),
            owner: owner,
            ownerPID: ownerPID,
            windowID: windowID,
            frame: frame,
            isOnScreen: isOnScreen,
            displayName: displayName
        )
    }
}

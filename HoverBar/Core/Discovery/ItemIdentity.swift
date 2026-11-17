/// A stable fingerprint used to match menu bar items across scans and launches.
///
/// The pair (owner bundle id, window title) survives re-scans and app restarts,
/// unlike `CGWindowID`, which changes whenever the owning app recreates the
/// item's window. When Screen Recording permission is missing, window titles
/// are unreadable, so the scanner falls back to a `window-<id>` title that is
/// stable for the lifetime of the window.
struct ItemIdentity: Equatable, Hashable, Codable {
    let ownerBundleID: String
    let title: String

    /// Fallback identity for a window whose title cannot be read.
    static func fallback(ownerBundleID: String, windowID: UInt32) -> ItemIdentity {
        ItemIdentity(ownerBundleID: ownerBundleID, title: "window-\(windowID)")
    }
}

/// macOS items with known move/hide restrictions (seeds from Ice's research,
/// verified against our own findings in Docs/TESTING.md).
enum ProtectedItems {
    /// Items that cannot be moved at all — they stay visible, always.
    static let immovableTitles = ["Clock", "Siri", "BentoBox", "Control Center"]

    /// Items that can be moved but immediately reappear when hidden.
    static let nonHideableTitles = ["AudioVideoModule", "FaceTime", "MusicRecognition"]

    static func isImmovable(_ identity: ItemIdentity) -> Bool {
        guard identity.ownerBundleID == "com.apple.controlcenter" else { return false }
        return immovableTitles.contains { matches(identity.title, system: $0) }
    }

    static func isNonHideable(_ identity: ItemIdentity) -> Bool {
        guard identity.ownerBundleID == "com.apple.controlcenter" else { return false }
        return nonHideableTitles.contains { matches(identity.title, system: $0) }
    }

    /// System windows carry suffixes on some macOS builds ("BentoBox-0").
    private static func matches(_ title: String, system: String) -> Bool {
        title == system || title.hasPrefix("\(system)-") || title.hasPrefix("\(system)#")
    }
}

/// Titles of Apple's own menu bar modules (macOS 14–26). On macOS 26 every
/// hosted item lives in ControlCenter, so a meaningful title is what separates
/// system modules from hosted third-party items ("Item-N" titles).
enum SystemModules {
    /// System module titles (prefix matching covers suffixed variants).
    static let systemTitles = [
        "Clock", "Siri", "BentoBox",
        "WiFi", "Wi-Fi", "Battery", "Bluetooth", "Sound", "Now Playing", "NowPlaying", "Control Center",
        "FocusModes", "MusicRecognition", "KeyboardBrightness", "ScreenMirroring",
        "StageManager", "AccessibilityShortcuts", "UserSwitcher", "AudioVideoModule",
        "FaceTime", "Keyboard", "TextInput", "InputMenu", "Spotlight", "Location",
        "TimeMachine", "Passwords",
    ]

    static func isSystemTitle(_ title: String) -> Bool {
        let normalized = title
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .lowercased()
        if normalized.isEmpty { return false }
        return systemKeywords.contains { normalized.contains($0) }
    }

    /// Normalized keywords covering AX labels ("Wi-Fi, connected, 3 bars") and
    /// window-title forms ("WiFi", "FocusModes") across macOS versions.
    static let systemKeywords = [
        "wi-fi", "wifi", "battery", "clock", "bluetooth", "control center",
        "bento", "now playing", "nowplaying", "focus", "siri", "spotlight",
        "keyboard brightness", "keyboardbrightness", "screen mirroring",
        "screenmirroring", "music recognition", "musicrecognition",
        "stage manager", "stagemanager", "accessibility shortcuts",
        "fast user switching", "user switcher", "userswitcher", "passwords",
        "time machine", "timemachine", "audiovideomodule", "facetime", "sound",
    ]

    /// Friendly display titles for known system modules (prefix variants).
    static let displayTitles: [String: String] = [
        "WiFi": "Wi-Fi",
        "Wi-Fi": "Wi-Fi",
        "FocusModes": "Focus",
        "MusicRecognition": "Music Recognition",
        "KeyboardBrightness": "Keyboard Brightness",
        "ScreenMirroring": "Screen Mirroring",
        "StageManager": "Stage Manager",
        "AccessibilityShortcuts": "Accessibility Shortcuts",
        "UserSwitcher": "Fast User Switching",
        "Now Playing": "Now Playing",
        "NowPlaying": "Now Playing",
    ]

    /// Friendly display title for a system module, nil for anything else.
    static func displayTitle(for title: String) -> String? {
        if title.hasPrefix("BentoBox") {
            return "Control Center"
        }
        return displayTitles[title]
    }
}

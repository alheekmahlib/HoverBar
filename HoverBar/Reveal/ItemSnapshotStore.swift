import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures images of menu bar item windows.
///
/// Uses the (deprecated but irreplaceable) `CGWindowListCreateImage` family:
/// unlike ScreenCaptureKit, it can capture windows that are currently parked
/// offscreen — exactly our situation after hiding items. Screen Recording
/// permission is required for window contents and titles.
final class ItemSnapshotStore {
    /// Captures one item window; nil without Screen Recording permission.
    func snapshot(windowID: CGWindowID) -> NSImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            [],
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    /// Whether the app currently holds Screen Recording permission.
    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system Screen Recording permission prompt (macOS 15+).
    static func requestScreenRecordingPermission() {
        if #available(macOS 15.0, *) {
            SCShareableContent.getWithCompletionHandler { _, _ in }
        } else {
            CGRequestScreenCaptureAccess()
        }
    }
}

/// Deprecated-but-functional capture entry point, kept warning-free behind a
/// protocol shim (same technique as Ice — see Docs/ARCHITECTURE.md).
private protocol WindowListImage {
    init?(windowListFromArrayScreenBounds screenBounds: CGRect, windowArray: CFArray, imageOption: CGWindowImageOption)
}

private extension WindowListImage {
    static func windowListImage(
        from screenBounds: CGRect,
        windowArray: CFArray,
        imageOption: CGWindowImageOption
    ) -> Self? {
        Self(
            windowListFromArrayScreenBounds: screenBounds,
            windowArray: windowArray,
            imageOption: imageOption
        )
    }
}

extension CGImage: WindowListImage {}

private func CGWindowListCreateImage(
    _ screenBounds: CGRect,
    _ listOption: CGWindowListOption,
    _ windowID: CGWindowID,
    _ imageOption: CGWindowImageOption
) -> CGImage? {
    var pointer = [UnsafeRawPointer(bitPattern: UInt(windowID))]
    guard let array = CFArrayCreate(kCFAllocatorDefault, &pointer, 1, nil) else {
        return nil
    }
    return CGImage.windowListImage(from: screenBounds, windowArray: array, imageOption: imageOption)
}

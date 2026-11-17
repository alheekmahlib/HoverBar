import ApplicationServices

/// Permission checks and prompts (Accessibility mandatory; Screen Recording
/// needed for item snapshots — see PLAN §2 and Docs/ARCHITECTURE.md).
enum Permissions {
    /// Whether the app is trusted for Accessibility; optionally prompts.
    static func isAccessibilityTrusted(prompt: Bool = false) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Triggers the Screen Recording permission prompt when missing.
    static func requestScreenRecordingIfMissing() {
        guard !ItemSnapshotStore.hasScreenRecordingPermission() else { return }
        Log.app.notice("screen recording permission missing — snapshots disabled until granted")
        ItemSnapshotStore.requestScreenRecordingPermission()
    }
}

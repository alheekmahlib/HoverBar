import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: RevealCoordinator?
    private var statusItem: NSStatusItem?
    private var trustPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("HoverBar launching (phase 1 MVP)")
        DiagnosticLog.write("launch: waiting-for-accessibility=\(Permissions.isAccessibilityTrusted())")

        if ProcessInfo.processInfo.environment["HOVERBAR_RESTORE_ALL"] == "1" {
            restoreAllOffscreenItems()
            return
        }

        if Permissions.isAccessibilityTrusted(prompt: true) {
            startCoordinator()
        } else {
            Log.app.notice("waiting for accessibility permission…")
            trustPollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                if Permissions.isAccessibilityTrusted() {
                    self?.trustPollTimer?.invalidate()
                    self?.startCoordinator()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trustPollTimer?.invalidate()
        coordinator?.shutdown()
    }

    private func startCoordinator() {
        guard coordinator == nil else { return }
        let coordinator = RevealCoordinator()
        coordinator.start()
        self.coordinator = coordinator
        installStatusItem()
        Log.app.info("accessibility granted — MVP active")
        DiagnosticLog.write("coordinator started")
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "···"

        let menu = NSMenu()
        let rescan = NSMenuItem(title: "Rescan Menu Bar", action: #selector(rescanAction), keyEquivalent: "")
        let restore = NSMenuItem(title: "Restore All Items", action: #selector(restoreAction), keyEquivalent: "")
        let quit = NSMenuItem(title: "Quit HoverBar", action: #selector(quitAction), keyEquivalent: "q")
        [rescan, restore, quit].forEach { item in
            item.target = self
            menu.addItem(item)
        }
        menu.insertItem(.separator(), at: 2)
        item.menu = menu
        statusItem = item
    }

    @objc private func rescanAction() {
        coordinator?.rescanAndReapply()
    }

    @objc private func restoreAction() {
        coordinator?.restoreAllItems()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    /// Safety net: brings every offscreen menu bar item back to visible
    /// positions. Launch with HOVERBAR_RESTORE_ALL=1.
    private func restoreAllOffscreenItems() {
        let scanner = AXMenuBarItemScanner()
        let items = scanner.scanAllItems()
        let mover = AXItemMover()
        var slot: CGFloat = 700
        var restored = 0
        for item in items where item.frame.minX < 0 {
            guard let element = item.element ?? AXHelpers.element(
                at: CGPoint(x: item.frame.midX, y: item.frame.midY),
                pid: item.ownerPID
            ) else { continue }
            if mover.move(element, to: CGPoint(x: slot, y: max(item.frame.minY, 0))) {
                restored += 1
                slot += item.frame.width + 4
            }
        }
        DiagnosticLog.write("rescue: restored \(restored) offscreen items")
        Log.app.info("rescue restored \(restored, privacy: .public) items")
    }
}

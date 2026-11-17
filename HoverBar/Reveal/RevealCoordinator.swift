import AppKit

/// Glue layer: wires hover monitoring, the reveal state machine, item
/// visibility and the tray surface into the product behavior.
final class RevealCoordinator {
    private let controller: VisibilityController
    private let snapshotStore: ItemSnapshotStore
    private let clickProxy: ClickProxy
    private let hoverMonitor: HoverMonitor
    private let tray: TrayPanel
    private var machine = RevealStateMachine()
    private var workspaceObservers: [NSObjectProtocol] = []
    private let parkingAnchor = ParkingAnchor()

    init(
        controller: VisibilityController = VisibilityController(),
        snapshotStore: ItemSnapshotStore = ItemSnapshotStore()
    ) {
        self.controller = controller
        self.snapshotStore = snapshotStore
        self.clickProxy = ClickProxy()
        self.hoverMonitor = HoverMonitor()
        self.tray = TrayPanel()
    }

    func start() {
        Permissions.requestScreenRecordingIfMissing()
        parkingAnchor.install()
        controller.parkingAnchorFrame = { [weak self] in
            self?.parkingAnchor.frame
        }
        controller.coveredBoundary = 600
        // Give the anchor window a moment to be created before hiding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.controller.applyHiddenState()
        }

        hoverMonitor.onReveal = { [weak self] in self?.reveal() }
        hoverMonitor.onCollapse = { [weak self] in self?.collapse() }
        // The open tray extends the hover region so the pointer can travel
        // from the bar down into it without the reveal session collapsing.
        hoverMonitor.extendedRegionProvider = { [weak self] in
            guard let self, self.tray.isVisible else { return [] }
            return [self.tray.frame]
        }
        hoverMonitor.start()

        observeWorkspaceNotifications()
        Log.app.info("reveal coordinator started")
    }

    func shutdown() {
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        workspaceObservers.removeAll()
        hoverMonitor.stop()
        tray.dismiss()
        controller.restoreAll()
        Log.app.info("reveal coordinator stopped — items restored")
    }

    func rescanAndReapply() {
        controller.rescan()
        controller.applyHiddenState()
    }

    func restoreAllItems() {
        controller.restoreAll()
    }

    // MARK: - Reveal flow

    private func reveal() {
        guard machine.send(.hoverEntered) else { return }
        let entries = buildEntries()
        guard !entries.isEmpty else {
            machine.send(.forcedCollapse)
            return
        }
        tray.present(entries: entries, belowBar: currentBarRect())
        DiagnosticLog.write("tray-present: \(entries.count) entries")
        machine.send(.didReveal)
    }

    private func collapse() {
        guard machine.send(.hoverExited) else { return }
        tray.dismiss()
        machine.send(.didCollapse)
        DiagnosticLog.write("tray-dismiss")
        // Re-hide any item staged for a proxied click, but give its menu a
        // moment to close first (documented MVP trade-off in ARCHITECTURE.md).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.machine.state == .collapsed else { return }
            self.controller.applyHiddenState()
        }
    }

    private func forceCollapse() {
        _ = machine.send(.forcedCollapse)
        tray.dismiss()
    }

    private func buildEntries() -> [TrayPanel.Entry] {
        controller.rescan()
        return controller.hiddenItems.map { item in
            TrayPanel.Entry(
                image: item.snapshotProvider?(),
                title: item.info.displayName,
                handler: { [weak self] in
                    guard let self else { return }
                    let outcome = self.clickProxy.activate(item: item, anchor: self.controller.leftmostVisibleAnchor)
                    DiagnosticLog.write("click: \(item.info.displayName) outcome=\(outcome)")
                    self.tray.dismiss()
                }
            )
        }
    }

    private func currentBarRect() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let frame = screen?.frame ?? .zero
        return MenuBarRegion.menuBarRect(
            forScreenFrame: frame,
            barHeight: MenuBarRegion.barHeight(statusBarThickness: NSStatusBar.system.thickness)
        )
    }

    private func observeWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceCollapse()
        })
    }
}

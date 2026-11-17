import AppKit

/// Watches the global mouse stream and reports settled hover sessions on the
/// menu bar region (with basic debounce; advanced tuning arrives in Phase 2).
final class HoverMonitor {
    /// How long the pointer must rest on the bar before revealing (seconds).
    var revealDelay: TimeInterval = 0.12

    /// How long the pointer must stay away before collapsing (seconds).
    var collapseDelay: TimeInterval = 0.5

    /// Fired once per settled hover-in.
    var onReveal: (() -> Void)?

    /// Fired once per settled hover-out.
    var onCollapse: (() -> Void)?

    private var monitors: [Any] = []
    private var revealWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var watchdog: Timer?
    private var isRevealed = false

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let globalHandler: (NSEvent) -> Void = { [weak self] _ in
            self?.handleMouseActivity()
        }
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: globalHandler) {
            monitors.append(globalMonitor)
        }
        let localHandler: (NSEvent) -> NSEvent = { [weak self] event in
            self?.handleMouseActivity()
            return event
        }
        if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: localHandler) {
            monitors.append(localMonitor)
        }
        // Menus (ours or an app's) swallow exit events while tracking, which
        // can leave the monitor stuck in "revealed". A default-mode timer only
        // fires between tracking sessions — exactly the self-heal we need.
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.healIfNeeded()
        }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        watchdog?.invalidate()
        revealWork?.cancel()
        collapseWork?.cancel()
    }

    /// Forces a collapse when the pointer is away but no exit event arrived.
    private func healIfNeeded() {
        guard isRevealed else { return }
        let regions = currentRegions()
        guard !MenuBarRegion.contains(NSEvent.mouseLocation, inRects: regions) else { return }
        isRevealed = false
        revealWork?.cancel()
        revealWork = nil
        collapseWork?.cancel()
        collapseWork = nil
        onCollapse?()
        Log.app.debug("hover monitor healed a stuck reveal")
    }

    private func currentRegions() -> [CGRect] {
        NSScreen.screens.map { screen in
            MenuBarRegion.menuBarRect(
                forScreenFrame: screen.frame,
                barHeight: MenuBarRegion.barHeight(statusBarThickness: NSStatusBar.system.thickness)
            )
        }
    }

    private func handleMouseActivity() {
        let inside = MenuBarRegion.contains(NSEvent.mouseLocation, inRects: currentRegions())

        if inside {
            collapseWork?.cancel()
            guard !isRevealed, revealWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isRevealed == false else { return }
                self.isRevealed = true
                self.onReveal?()
            }
            revealWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay, execute: work)
        } else {
            revealWork?.cancel()
            revealWork = nil
            guard isRevealed, collapseWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isRevealed else { return }
                self.isRevealed = false
                self.onCollapse?()
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + collapseDelay, execute: work)
        }
    }
}

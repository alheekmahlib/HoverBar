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
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        revealWork?.cancel()
        collapseWork?.cancel()
    }

    private func handleMouseActivity() {
        let regions = NSScreen.screens.map { screen in
            MenuBarRegion.menuBarRect(
                forScreenFrame: screen.frame,
                barHeight: MenuBarRegion.barHeight(statusBarThickness: NSStatusBar.system.thickness)
            )
        }
        let inside = MenuBarRegion.contains(NSEvent.mouseLocation, inRects: regions)

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

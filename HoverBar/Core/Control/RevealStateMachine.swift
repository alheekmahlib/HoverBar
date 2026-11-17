/// Pure reveal lifecycle. "Expanded" means the floating tray is visible.
///
///     collapsed ──hoverEntered──▶ revealing ──didReveal──▶ expanded
///     expanded ──hoverExited────▶ collapsing ──didCollapse──▶ collapsed
///
/// Space changes, fullscreen entry and screen lock force-collapse from any
/// state. A hover during `collapsing` cancels back into `revealing`.
struct RevealStateMachine: Equatable {
    enum State: Equatable {
        case collapsed
        case revealing
        case expanded
        case collapsing
    }

    enum Event: Equatable {
        case hoverEntered
        case didReveal
        case hoverExited
        case didCollapse
        case forcedCollapse
    }

    private(set) var state: State = .collapsed

    /// Sends an event; returns true when a transition was applied.
    @discardableResult
    mutating func send(_ event: Event) -> Bool {
        let from = state
        switch (from, event) {
        case (.collapsed, .hoverEntered),
             (.collapsing, .hoverEntered):
            state = .revealing
        case (.revealing, .didReveal):
            state = .expanded
        case (.revealing, .hoverExited),
             (.expanded, .hoverExited):
            state = .collapsing
        case (.collapsing, .didCollapse):
            state = .collapsed
        case (.revealing, .forcedCollapse),
             (.expanded, .forcedCollapse),
             (.collapsing, .forcedCollapse):
            state = .collapsed
        default:
            return false
        }
        return from != state || event == .forcedCollapse
    }
}

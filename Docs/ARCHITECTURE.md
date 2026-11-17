# HoverBar Architecture

Living document. Last updated: 2026-11-17 (Phase 1 R&D).

## The one-minute version

```
┌─────────────────────────────────────────────────────────────┐
│  HoverMonitor (global mouse stream)                         │
│      hover enters/leaves menu-bar region (debounced)        │
│                    │                                        │
│                    ▼                                        │
│  RevealStateMachine (collapsed → revealing → expanded…)     │
│                    │                                        │
│                    ▼                                        │
│  RevealCoordinator ──► VisibilityController                 │
│        │                    │                               │
│        ▼                    ├── AXMenuBarItemScanner (AX+CG)│
│  TrayPanel (mini-dock)      ├── policy (system vs 3rd-party)│
│  snapshots + click proxy    └── hide/restore (AX + cover)   │
└─────────────────────────────────────────────────────────────┘
```

## macOS 26/27 research findings (the heart of this project)

Every technique below was verified by experiment on macOS 27 beta
(build 27A9275, MacBook with notch). This is knowledge Ice's source
could only hint at — much of it appears to be new territory.

### 1. Where menu bar items actually live
- `SystemUIServer` owns **zero** menu bar item windows. Everything is
  hosted by the **ControlCenter** process (`com.apple.controlcenter`).
- Third-party `NSStatusItem`s appear there as CG windows titled
  `Item-N` (duplicate titles are the norm) — or with no title at all
  without Screen Recording permission.
- Some apps (e.g. NexusIsland) own their item window directly
  (layer 25, their own pid).
- AX tree: each host has an `AXMenuBar` child whose children are
  `AXMenuBarItem`s. System modules have rich labels
  ("Wi-Fi, connected, 3 bars" — note the U+2011 non-breaking hyphen!).
  Hosted third-party items appear as **unlabeled, zero-size** AX items.

### 2. What works for moving items
| Technique | Result on macOS 27 |
|---|---|
| AX `kAXPosition` on the `AXMenuBar` container | rejected |
| AX `kAXPosition` on labeled `AXMenuBarItem` (Apple modules) | **works** (Battery moved to x=-300 instantly) |
| AX `kAXPosition` on unlabeled hosted items | rejected |
| Synthesized ⌘-drag CGEvents (Ice's field recipe) | **reorders** items; raw offscreen drops get clamped to the leftmost valid slot |
| Ice's offscreen "parking anchor" (own status item parked at negative x) | anchor installs, but does NOT extend the valid drop region |
| **Cover window (Ice's real trick): a 10,000px-wide status item covering the bar** | **works** — items can then be dropped/parked far offscreen (observed at x = -3,800 and beyond) |

The hide mechanism is therefore the Ice pattern, adapted:
1. install a giant cover status item (`ParkingAnchor`), which extends
   the valid drop region across (and beyond) the bar;
2. drag third-party items left — they park offscreen, their windows
   eventually detach from the CG list (still alive; snapshot must be
   captured **before** the move);
3. AX position writes remain the fast path for Apple-labeled items.

### 3. Permissions reality
- **Accessibility** is required (AX reads/writes, event posting).
- **Screen Recording** is required for window titles (`kCGWindowName`)
  and for `CGWindowListCreateImage` snapshots. Without it, identities
  degrade to `window-<id>` fallbacks and the tray falls back to text.
- TCC grants key off the code signature: **ad-hoc builds lose grants
  on every rebuild**. Dev builds must be signed with a stable identity
  (`scripts/sign-dev.sh`, Developer ID) and launched via `open`
  (`scripts/dev-run.sh`) — direct exec from a non-app context breaks
  the AX trust check.

### 4. Tools
- `CGWindowListCreateImage` (deprecated) still captures offscreen
  windows — ScreenCaptureKit cannot. Silenced via a protocol shim
  (Ice's technique).
- The unified log is unreadable from some contexts; the app writes
  `~/Library/Logs/HoverBar.log` (`DiagnosticLog`) instead.

## Module map (Phase 1)

| Module | Responsibility |
|---|---|
| `Core/Discovery/MenuBarItemScanner` | CG window scan (layer 25, bar-shaped windows) |
| `Core/Discovery/AXMenuBarItemScanner` | AX discovery + CG merge (windowIDs for snapshots) |
| `Core/Discovery/ItemIdentity` | stable identities, system-module keywords, protected items |
| `Core/Control/VisibilityController` | tracking, hide/restore passes, verification, snapshot capture |
| `Core/Control/AXItemMover` | AX position writes |
| `Core/Control/CGEventItemDragger` | synthesized ⌘-drags (Ice-derived field recipe) |
| `Core/Control/LayoutEngine` | pure geometry (slots, staging, notch) |
| `Core/Control/RevealStateMachine` | pure lifecycle (unit-tested) |
| `Core/Input/HoverMonitor`, `MenuBarRegion` | hover sessions over the bar |
| `Reveal/TrayPanel` | the floating mini-dock surface |
| `Reveal/ParkingAnchor` | the Ice-style cover window |
| `Reveal/ClickProxy` | stage hidden item + AX press |
| `Reveal/RevealCoordinator` | glue |
| `Support/AXHelpers`, `Log`, `DiagnosticLog` | AX calls, logging |

## Known gaps (next up)
- Hide pass succeeds per-item but full-bar passes need reliability
  tuning (Ice uses 5 retries + wake-up + frame-change waits).
- Click proxy on hidden items: staging works in theory, end-to-end
  menu opening not yet verified on device.
- Window-id churn after every reorder forces per-item rescans
  (already implemented); identities for duplicate `Item-N` windows
  churn with scan order.
- Multi-display: hidden strip assumes primary display coordinates.

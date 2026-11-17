# Testing log — real-device findings

Machine: MacBook (notch), macOS 27 beta (27A9275), arm64.
Date: 2026-11-17. Tester: automated agent + owner.

## Unit tests
31 tests, all green (CI: `swiftlint --strict` + `xcodebuild test`).
Cover: state machine transitions, layout math, scanner parsing
(CG + identity + policy), visibility controller (hide/restore/escape/
merge) with injected fakes.

## On-device experiment log (chronological)

| # | Experiment | Result |
|---|---|---|
| 1 | CG scan of layer-25 windows | ✓ 14–19 items; all owned by ControlCenter; SystemUIServer owns none |
| 2 | AX position write on element-at-point | ✗ returns the `AXMenuBar` container; write rejected |
| 3 | CGEvent ⌘-drag (session/hid/annotated taps × sources × drag paths × cursor hiding) without permissions | ✗ all no-ops (permissions missing) |
| 4 | Ad-hoc rebuilt binary keeps TCC grants | ✗ grants lost every rebuild → `scripts/sign-dev.sh` (Developer ID) |
| 5 | Direct binary exec vs `open` | `open` required; direct exec reports `AXIsProcessTrusted() == false` even with grants |
| 6 | AX enumeration of ControlCenter | ✓ `AXMenuBar` → `AXMenuBarItem` children; Apple modules labeled; hosted third-party unlabeled/0×0; found previously-dragged item parked at x=-229 |
| 7 | AX position write on labeled `AXMenuBarItem` (Battery) | ✓ **moved to x=-300 instantly** (returns kAXErrorCannotComplete despite applying) |
| 8 | AX position write on unlabeled hosted items | ✗ rejected |
| 9 | CGEvent drag with valid permissions, onscreen drop | ✓ item reordered (window id churned) |
| 10 | CGEvent drag, offscreen drop | ✗ clamped back to leftmost valid slot; one lucky run parked an item at x=-229 (window detached) |
| 11 | Ice parking-anchor (own item at x=-350) | anchor window installs at negative x, but drops still clamp |
| 12 | **Ice cover window (10,000px status item)** | ✓✓ items park at x≈-3,800 and beyond; windows alive during pass; one full hide cycle succeeded (`moved=1`, others parked), tray presented with snapshot entry |

## Works / doesn't work (summary)

**Works**
- Discovery (CG + AX hybrid) with rich labels for system modules
- Hiding via cover window + drags (mechanism proven)
- AX moves for Apple-labeled items
- Hover → tray present (on device)
- Restore via `killall ControlCenter` (nuclear, reliable)

**Doesn't work (yet / on this OS)**
- Raw offscreen drags without the cover (clamped)
- AX writes on hosted unlabeled items
- Unified-log readability from agent context (file log used instead)

## Manual test script (for humans)
1. `scripts/dev-run.sh` (build+sign+install+launch via `open`)
2. Grant Accessibility + Screen Recording once (stable identity)
3. Watch `~/Library/Logs/HoverBar.log`
4. Third-party icons should disappear; hover the bar → mini-dock tray
5. Rescue: `HOVERBAR_RESTORE_ALL=1` launch, or `killall ControlCenter`

## Next test priorities
- Full-bar hide reliability (retries, wake-ups, timing)
- Click proxy end-to-end: tray icon → staged item → menu opens
- Quit → restoreAll on device

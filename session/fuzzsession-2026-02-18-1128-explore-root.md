# Explore Session — ButtonHeist Test App (Root)

## Config
- **Status**: complete
- **Screen**: ButtonHeist Test App (Root)
- **Trace file**: fuzzsession-2026-02-18-1128-explore-root.trace.md
- **Next finding ID**: F-1
- **Device**: iPhone 16 Pro iOS 18.5
- **App**: AccessibilityTestApp
- **Started**: 2026-02-18T11:28:47Z
- **Completed**: 2026-02-18T11:32:25Z

## Element Inventory

| Order | Label | Identifier | Actions | Notes |
|-------|-------|-----------|---------|-------|
| 0 | Controls Demo | — | activate | Nav row → Controls Demo screen |
| 1 | Touch Canvas | — | activate | Nav row → Touch Canvas screen |
| 2 | ButtonHeist Test App | — | (none) | Heading — fully inert |

## Coverage

- [x] Order 0 — Controls Demo → navigates to Controls Demo (9 elements) — trace #2
- [x] Order 1 — Touch Canvas → navigates to Touch Canvas (3 elements) — trace #4
- [x] Order 2 — ButtonHeist Test App heading — tap: no-op, long-press: no-op — traces #11, #12

## Findings

None. All interactions behaved as expected.

## Touch Canvas Sub-Screen Coverage (explored en route)

| Order | Label | Identifier | Actions | Result |
|-------|-------|-----------|---------|--------|
| 0 | ButtonHeist Test App | — | activate | Back navigation → root |
| 1 | Reset | buttonheist.touchCanvas.resetButton | activate | Clears canvas drawing |
| 2 | Touch Canvas | — | (none) | Heading — fully inert |

Additional:
- `draw_path` with a diamond path → rendered correctly on canvas (confirmed via screenshot) — trace #6
- Reset after drawing → canvas cleared (confirmed via screenshot) — trace #7
- Small red dot visible at ~(480, 880) after draw_path — possibly a touch indicator artifact, disappeared after reset

## Transitions Discovered

| From | Element | Destination | Element Count | Notes |
|------|---------|-------------|---------------|-------|
| Root | Controls Demo (0) | Controls Demo | 9 | 7 nav rows + back button + heading |
| Root | Touch Canvas (1) | Touch Canvas | 3 | Back + Reset buttons + heading; canvas not in a11y tree |
| Controls Demo | Back (order 7, "ButtonHeist Test App") | Root | 3 | Back label = root app name |
| Touch Canvas | Back (order 0, "ButtonHeist Test App") | Root | 3 | Back label = root app name |

## Notable Observations

1. **Back button diff anomaly**: Activating Back from both Controls Demo and Touch Canvas triggers `DIFF` (partial update) rather than `SCREEN_CHANGED`. The diff reports only 1–2 element changes during what is a full navigation. This is likely a UIKit animation interleaving where the accessibility tree is captured mid-transition. The final `get_interface` always shows the correct destination screen.

2. **draw_path works on canvas**: The canvas accepts `draw_path` gestures and renders them visually (blue stroke). The canvas is a custom `UIView` — invisible to the a11y tree but still responsive to touch input.

3. **Red dot artifact**: After `draw_path`, a small red dot appeared at ~(480, 880). It disappeared after Reset was called. Likely a touch position indicator in the test app, not a bug.

4. **Reset is always a no-op at the element level**: Canvas clearing is purely visual — no a11y elements change, so NO_CHANGE is always returned regardless of canvas state.

## Progress

Complete — all 3 root elements tested + Touch Canvas sub-screen explored. 12 trace entries recorded.

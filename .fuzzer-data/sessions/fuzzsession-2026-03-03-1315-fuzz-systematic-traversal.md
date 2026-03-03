# Fuzzer Session Notes

## Config
- **Command**: fuzz
- **Strategy**: systematic-traversal
- **Max iterations**: 30
- **App**: ButtonHeist Test App
- **Device**: iPhone 16 Pro iOS 26.1 (Simulator)
- **Status**: complete
- **Trace file**: fuzzsession-2026-03-03-1315-fuzz-systematic-traversal.trace.md
- **Next finding ID**: F-1

## Progress
- **Actions**: 6
- **Current screen**: Settings
- **Phase**: complete

## Screens Discovered

| # | Screen Name | Elements | Fingerprint |
|---|-------------|----------|-------------|
| 1 | Main Menu | 10 | {Controls Demo, Todo List, Notes, Calculator, Touch Canvas, Settings, Long List, Corner Scroll, Scroll Tests, ButtonHeist Test App} |
| 2 | Controls Demo | 9 | {Text Input, Toggles & Pickers, Buttons & Actions, Adjustable Controls, Disclosure & Grouping, Alerts & Sheets, Display, BackButton, Controls Demo heading} |
| 3 | Toggles & Pickers | 19 | {subscribeToggle, menuPicker, Low/Medium/High segmented, Date Picker, colorPicker, lastActionLabel, BackButton} |
| 4 | Settings | 32 | {System/Light/Dark theme, Blue/Purple/Green/Orange accent, Small/Medium/Large text, username field, showCompleted, compactMode, current values, BackButton} |

## Coverage

### Main Menu
- [x] Controls Demo (order:0) — activate → elementsChanged (navigated)
- [ ] Todo List (order:1) — activate
- [ ] Notes (order:2) — activate
- [ ] Calculator (order:3) — activate
- [ ] Touch Canvas (order:4) — activate
- [x] Settings (order:5) — activate → screenChanged (navigated)
- [ ] Long List (order:6) — activate
- [ ] Corner Scroll (order:7) — activate

### Toggles & Pickers
- [x] subscribeToggle — activate → valuesChanged (0→1, "Last action: Toggle: ON")
- [x] Medium segmented — activate → valuesChanged (syntheticTap fallback)

### Settings
- [x] index 11 — activate → valuesChanged (showCompleted 1→0)

## Transitions

| From | Action | To |
|------|--------|-----|
| Main Menu | activate index:0 | Controls Demo (elementsChanged) |
| Controls Demo | activate index:1 | Toggles & Pickers (screenChanged) |
| Toggles & Pickers | activate BackButton | Main Menu (screenChanged) |
| Main Menu | activate index:5 | Settings (screenChanged) |

## Navigation Stack
- Main Menu (depth 0) → Settings (depth 1)

## Findings

No CRASH, ERROR, or ANOMALY findings in this validation session.

## Action Log

| # | Command | Delta | Notes |
|---|---------|-------|-------|
| 1 | activate --index 0 | elementsChanged | Main Menu → Controls Demo |
| 2 | get_interface (session) | — | Read Controls Demo submenu |
| 3 | activate --index 1 | screenChanged | Controls Demo → Toggles & Pickers |
| 4 | activate --identifier subscribeToggle | valuesChanged | Toggle 0→1 |
| 5 | activate BackButton | screenChanged | Back to Main Menu |
| 6 | activate --index 5 | screenChanged | Main Menu → Settings |
| 7 | activate --index 11 | valuesChanged | showCompleted 1→0 |

## Next Actions
- Session complete (validation run)

# Explore Session — Controls Demo

## Config
- **Status**: complete
- **Screen**: Controls Demo
- **Trace file**: fuzzsession-2026-02-18-1105-explore-controls-demo.trace.md
- **Next finding ID**: F-1
- **Device**: iPhone 16 Pro iOS 18.5
- **App**: AccessibilityTestApp
- **Started**: 2026-02-18T11:05:00Z
- **Completed**: 2026-02-18T11:08:00Z

## Element Inventory

| Order | Label | Identifier | Actions | Notes |
|-------|-------|-----------|---------|-------|
| 0 | Text Input | — | activate | Nav row → sub-screen |
| 1 | Toggles & Pickers | — | activate | Nav row → sub-screen |
| 2 | Buttons & Actions | — | activate | Nav row → sub-screen |
| 3 | Adjustable Controls | — | activate | Nav row → sub-screen |
| 4 | Disclosure & Grouping | — | activate | Nav row → sub-screen |
| 5 | Alerts & Sheets | — | activate | Nav row → sub-screen |
| 6 | Display | — | activate | Nav row → sub-screen |
| 7 | Touch Canvas (Back) | — | activate | Back navigation → Touch Canvas screen |
| 8 | Controls Demo (Heading) | — | — | Static label, fully inert |

## Coverage

- [x] Order 0 — Text Input → navigates to Text Input screen (trace #2)
- [x] Order 1 — Toggles & Pickers → navigates to Toggles & Pickers screen (trace #4)
- [x] Order 2 — Buttons & Actions → navigates to Buttons & Actions screen (trace #6)
- [x] Order 3 — Adjustable Controls → navigates to Adjustable Controls screen (trace #8)
- [x] Order 4 — Disclosure & Grouping → navigates to Disclosure & Grouping screen (trace #10)
- [x] Order 5 — Alerts & Sheets → navigates to Alerts & Sheets screen (trace #12)
- [x] Order 6 — Display → navigates to Display screen (trace #14)
- [x] Order 7 — Touch Canvas Back button → navigates to Touch Canvas (trace #16)
- [x] Order 8 — Controls Demo Heading — tap: no-op, long-press: no-op (traces #19, #20)

## Findings

None. All interactions behaved as expected.

## Transitions Discovered

| Element | Destination Screen | Element Count | Notes |
|---------|-------------------|---------------|-------|
| Text Input (0) | Text Input | 7 | 3 text fields + multiline editor |
| Toggles & Pickers (1) | Toggles & Pickers | 12 | Toggle, menu picker, segmented control, date picker, color picker |
| Buttons & Actions (2) | Buttons & Actions | 11 | Includes disabled button + swipe-action item with Share/Favorite custom actions |
| Adjustable Controls (3) | Adjustable Controls | 10 | Slider, stepper (decrement dimmed at 0), gauge, linear/spinner progress |
| Disclosure & Grouping (4) | Disclosure & Grouping | 6 | Collapsible Advanced Settings group |
| Alerts & Sheets (5) | Alerts & Sheets | 7 | Alert, confirmation, sheet triggers |
| Display (6) | Display | 8 | Star image, info label, Apple Accessibility link |
| Back button (7) | Touch Canvas | 3 | Sibling screen — canvas not in a11y tree |
| Back → Root → Controls Demo | Controls Demo | 9 | Back label changes to "ButtonHeist Test App" when entered from root |

## App Hierarchy Discovered

```
ButtonHeist Test App (root)
├── Controls Demo
│   ├── Text Input
│   ├── Toggles & Pickers
│   ├── Buttons & Actions
│   ├── Adjustable Controls
│   ├── Disclosure & Grouping
│   ├── Alerts & Sheets
│   └── Display
└── Touch Canvas
```

## Notable Observations

1. **Back button label is context-sensitive**: When Controls Demo is reached via Touch Canvas's navigation stack, its back button reads "Touch Canvas". When reached from root, it reads "ButtonHeist Test App". Correct nav-stack behavior.
2. **Touch Canvas canvas area invisible to accessibility**: The drawing surface in Touch Canvas exposes only Back + Reset buttons. No canvas element in the a11y tree.
3. **Stepper Decrement disabled at minimum**: In Adjustable Controls, the decrement button becomes dimmed (no actions) when the stepper is at value 0.
4. **Swipe actions as custom a11y actions**: In Buttons & Actions, `customActionsItem` exposes "Share" and "Favorite" as named custom accessibility actions — correct pattern.

## Progress

Complete — all 9 elements tested, 20 trace entries recorded.

# Fuzzing Report

**Session**: fuzzsession-2026-02-19-1346-fuzz-state-exploration
**Strategy**: state-exploration
**Date**: 2026-02-19
**App**: AccessibilityTestApp
**Device**: iPhone 16 Pro iOS 18.5
**Duration**: ~82 actions across 12 screens
**Trace file**: fuzzsession-2026-02-19-1346-fuzz-state-exploration.trace.md

---

## Summary

| Severity | Count |
|----------|-------|
| CRASH    | 0     |
| ERROR    | 0     |
| ANOMALY  | 6     |
| INFO     | 1     |

**2 new screens discovered** not present in the prior session's nav graph: **Todo List** and **Settings**.

Settings changes (Dark mode, Green accent, Large text) are applied app-wide and persist across navigation. This cross-screen effect was confirmed visually on all visited screens.

---

## Findings

### F-1 [ANOMALY] Todo List does not persist items across navigation
**Screen**: Todo List
**Severity**: High — core feature broken
**Confidence**: Confirmed (reproduced 3/3)

**Steps to reproduce**:
1. Navigate to Todo List
2. Type "Buy groceries" → tap Add
3. Verify item appears ("1 item remaining")
4. Tap Back → navigate to Main Menu
5. Re-enter Todo List

**Expected**: "Buy groceries" still present (1 item remaining)
**Actual**: List resets to empty state on every visit — "0 items remaining", "No todos yet"

**Impact**: All todo data is lost on every navigation. The feature is non-functional for persistent use.

**Trace refs**: #15 (navigate away), #16 (return — empty)

---

### F-2 [ANOMALY] Empty state message "No all todos" is grammatically incorrect
**Screen**: Todo List
**Severity**: Low — copy/text bug
**Confidence**: Confirmed (reproduced 2/2)

**Steps to reproduce**:
1. In Settings, set Show Completed Todos = OFF
2. Navigate to Todo List, ensure "All" filter is selected
3. Add an item and activate (complete) it

**Expected**: A natural-language empty state like "No todos", "All caught up", or "No visible todos"
**Actual**: Label reads **"No all todos"** — grammatically broken

**Root cause**: The empty state message is likely constructed as `"No \(filterName.lowercased()) todos"`. For "Active" → "No active todos" ✓, "Completed" → "No completed todos" ✓, but "All" → "No all todos" ✗. The "All" filter name needs special-casing.

**Trace refs**: #28

---

### F-3 [ANOMALY] "Clear Completed" button visible when completed items are hidden
**Screen**: Todo List
**Severity**: Medium — confusing/misleading UX
**Confidence**: Confirmed (reproduced 2/2)

**Steps to reproduce**:
1. In Settings, set Show Completed Todos = OFF
2. Navigate to Todo List, add an item, complete it
3. Observe "Clear Completed" button is present
4. Switch to "Completed" filter — shows empty ("No completed todos")

**Expected**: Either (a) "Clear Completed" is hidden when show completed = OFF, or (b) completed items are still visible in the Completed filter regardless of setting
**Actual**: "Clear Completed" is visible and can delete items the user cannot see. The Completed filter is also always empty when the setting is OFF, making the filter button useless.

**Impact**: User can accidentally delete completed todos they cannot see. The "Completed" filter appears broken.

**Trace refs**: #29

---

### F-4 [ANOMALY] Color picker exposes zero accessibility elements — completely inaccessible to VoiceOver
**Screen**: Toggles & Pickers → colorPicker
**Severity**: High — complete accessibility failure
**Confidence**: Confirmed (visual screenshot + accessibility tree)

**Steps to reproduce**:
1. Navigate to Controls Demo → Toggles & Pickers
2. Tap the "Accent color" (`buttonheist.pickers.colorPicker`) element
3. Call `get_interface`

**Expected**: Color picker UI elements (color grid, spectrum/sliders tabs, opacity slider, close button) are all accessible via VoiceOver
**Actual**: `get_interface` returns **0 elements**. The entire color picker UI is inaccessible. The only thing in the tree is a `PopoverDismissRegion` at off-screen coordinates (frameX: -402, frameY: -874).

**Additional impact**: Attempting to dismiss the color picker is unreliable — tapping in the nav bar area behind the picker triggered unintended back navigation (Controls Demo Submenu) instead of dismissing the sheet. VoiceOver users are effectively trapped with no way to interact with or dismiss the picker.

**Screenshot**: Available (taken during session)

**Trace refs**: ~#50 area

---

### F-5 [ANOMALY] Three elements share the same accessibility identifier in Disclosure & Grouping
**Screen**: Disclosure & Grouping (expanded state)
**Severity**: Medium — breaks test automation and VoiceOver targeting
**Confidence**: Confirmed (reproduced 2/2 on expand)

**Affected elements** (all share `identifier: "buttonheist.disclosure.advancedGroup"`):
- Order 0: "Advanced Settings" disclosure header/toggle (button, header)
- Order 3: "Enable notifications" switch (button, value: "1")
- Order 4: "Dark mode" switch (button, value: "0")

**Expected**: Each element has a unique accessibility identifier
**Actual**: All three share `"buttonheist.disclosure.advancedGroup"`, making any identifier-based targeting ambiguous

**Impact**: `XCTest` queries like `app.buttons["buttonheist.disclosure.advancedGroup"]` will match all three elements. The ButtonHeist `activate(identifier:)` tool also cannot reliably target the individual toggles.

**Trace refs**: Disclosure & Grouping exploration

---

### F-6 [ANOMALY] Disclosed toggles ("Enable notifications", "Dark mode") are completely inert
**Screen**: Disclosure & Grouping (expanded state)
**Severity**: Medium — interactive elements that don't respond
**Confidence**: Confirmed (4/4 attempts, all interaction methods)

**Steps to reproduce**:
1. Navigate to Controls Demo → Disclosure & Grouping
2. Activate "Advanced Settings" to expand the group
3. Try `activate(order: 3)` on "Enable notifications"
4. Try `tap(x: 338, y: 266)` on "Enable notifications"
5. Try `activate(order: 4)` on "Dark mode"
6. Try `long_press(x: 338, y: 310)` on "Dark mode"

**Expected**: Toggle values change (0 → 1 or 1 → 0), hint "Double tap to toggle setting" fulfilled
**Actual**: All interactions return `noChange`. Both toggles are completely unresponsive to activate, tap, and long press.

**Note**: This finding may be related to F-5 — the duplicate identifiers could cause the activation to be misrouted to the header element (order 0) instead of the intended toggle.

**Trace refs**: Disclosure & Grouping exploration

---

### INFO-1: Settings have real visual cross-screen effects
**Screens**: All screens
**Severity**: Informational

Settings changes are reflected app-wide:
- **Dark mode** → app-wide black background, light text (confirmed on Main Menu, Todo List, Alerts & Sheets)
- **Green accent color** → nav bar titles and buttons change to green (confirmed on Alerts & Sheets screenshot)
- **Large text size** → navigation bar title style changed from large-title to inline-title format on Main Menu and Todo List; section heading heights increased (37pt → 46pt)

These are intentional and working correctly — noted as INFO for completeness.

---

## Screen Map

```
Main Menu (root)
├── Controls Demo Submenu
│   ├── Text Input (prior session, not re-explored)
│   ├── Toggles & Pickers
│   │   ├── menuPicker → [Daily/Weekly/Monthly] context menu
│   │   ├── Date Picker → calendar popover (28 days + month nav)
│   │   └── colorPicker → opens (visual only, 0 a11y elements) [F-4]
│   ├── Buttons & Actions
│   │   ├── optionsMenu → [Option A / Option B / Delete] context menu
│   │   └── customActionsItem (Share, Favorite custom actions)
│   ├── Adjustable Controls (prior session, not re-explored)
│   ├── Disclosure & Grouping
│   │   └── advancedGroup (expand) → [Enable notifications, Dark mode] toggles [F-5, F-6]
│   ├── Alerts & Sheets
│   │   ├── alertButton → Alert overlay → OK
│   │   ├── confirmButton → Confirmation action sheet → CANCEL/SAVE/DISCARD
│   │   └── sheetButton → Sheet (auto-dismisses, F-1 from prior session: dismiss off-screen)
│   └── Display
│       └── learnMoreLink → opens Safari externally (noChange in app)
├── Todo List [F-1, F-2, F-3]
│   └── items → activate (complete/uncomplete), Delete (custom action)
├── Touch Canvas (prior session, not re-explored)
└── Settings [persists across navigation]
    ├── Color Scheme: System/Light/Dark
    ├── Accent Color: Blue/Purple/Green/Orange
    ├── Text Size: Small/Medium/Large
    ├── Username (text field)
    ├── Show Completed Todos toggle (cross-screen effect on Todo List)
    └── Compact Mode toggle
```

---

## Coverage

| Screen | Interactive Elements | Tested | Notes |
|--------|---------------------|--------|-------|
| Main Menu | 4 | 4/4 | 100% |
| Todo List | ~7 | 7/7 | 100% |
| Settings | 10 | 10/10 | 100% |
| Controls Demo Submenu | 7 | 7/7 | 100% |
| Buttons & Actions | 5 | 5/5 | 100% |
| Toggles & Pickers | 5 | 5/5 | colorPicker visually tested |
| Disclosure & Grouping | 3 | 3/3 | toggles inert (F-6) |
| Alerts & Sheets | 3 | 3/3 | 100% |
| Display | 1 | 1/1 | learnMoreLink opens Safari |
| Text Input | (prior session) | - | Not re-explored |
| Adjustable Controls | (prior session) | - | Not re-explored |
| Touch Canvas | (prior session) | - | Not re-explored |

**Overall**: 12 unique screens visited (including overlays). All new screens fully explored.

---

## New Transitions (additions to nav-graph.md)

| From | Action | To | Reverse | Reliable |
|------|--------|----|---------|----------|
| Main Menu | activate order 1 "Todo List" | Todo List | tap (40,78) "Back" | YES |
| Main Menu | activate order 3 "Settings" | Settings | activate order 21 "Back" | YES |
| Toggles & Pickers | activate "Date Picker" (order 6) | Date Picker calendar popover | activate PopoverDismissRegion | YES |
| Toggles & Pickers | activate colorPicker | Color picker sheet | tap (50,100) [unreliable — causes back nav] | UNRELIABLE |

# AccessibilityTestApp — Full App Fuzzing Report

**App**: AccessibilityTestApp (`com.buttonheist.testapp`)
**Device**: iPhone 16 Pro iOS 18.5
**Report generated**: 2026-02-19
**Sessions covering this report**: 6 sessions, 2026-02-17 through 2026-02-19

---

## Executive Summary

Six fuzzing sessions have been completed across AccessibilityTestApp using stress testing, swarm testing, screen mapping, state exploration, and gesture fuzzing strategies. Together they covered all 16 discovered screens and exercised the full reachable surface area.

| Metric | Value |
|--------|-------|
| Sessions | 6 |
| Total actions | ~200 |
| Screens discovered | 16 |
| Unique findings | 13 |
| CRITICAL | 1 |
| ANOMALY (High) | 2 |
| ANOMALY (Medium) | 4 |
| ANOMALY (Low) | 2 |
| INFO | 2 |
| Crashes | 0 |

**Overall app health**: The app is stable — no crashes detected across ~200 actions. However it has significant **accessibility failures**, **data persistence bugs**, and **gesture instability** that would affect real users and automated testing.

---

## App Structure

```
Main Menu (root)
├── Controls Demo Submenu
│   ├── Text Input          (4 text fields: name, email, password, bio)
│   ├── Toggles & Pickers   (toggle, menu picker, segmented, date picker, color picker)
│   ├── Buttons & Actions   (primary, bordered, destructive, options menu, custom actions)
│   ├── Adjustable Controls (slider, stepper, gauge, 2 progress indicators)
│   ├── Disclosure & Grouping (disclosure group with 2 inner toggles)
│   ├── Alerts & Sheets     (alert, confirmation sheet, bottom sheet)
│   └── Display             (image, labels, external link)
├── Todo List               (add/complete/delete/filter todos)
├── Touch Canvas            (free-draw canvas + reset)
└── Settings                (color scheme, accent, text size, username, behavior toggles)
```

**Modal overlays** (not standalone screens):
- Alert overlay (from Alerts & Sheets)
- Confirmation action sheet (from Alerts & Sheets)
- Bottom Sheet overlay (from Alerts & Sheets)
- Date Picker calendar popover (from Toggles & Pickers)
- Color Picker sheet (from Toggles & Pickers)
- Options Menu context menu (from Buttons & Actions)

**Max navigation depth**: 2 levels (shallow — all content within 2 taps of Main Menu)

---

## Findings

### CRITICAL

---

#### CRIT-1 — Rotate gesture fails at 50% rate and triggers unintended navigation
**Session**: stress-test-2026-02-17
**Screen**: Buttons & Actions
**Severity**: CRITICAL
**Status**: Open (not re-tested in later sessions)

Rapid rotate gestures on button elements fail unpredictably. Across 4 elements tested:
- Primary Button: 5 rotates — ✅ all passed
- Bordered Button: 5 rotates — ✅ all passed
- Destructive Button: failed on 5th rotate, **triggered back navigation** to Controls Demo Submenu (state reset: tap count 70→0)
- Options Menu: failed on 1st rotate

**Steps to reproduce**:
1. Navigate to Controls Demo → Buttons & Actions
2. Execute 5 rapid rotate gestures on the Destructive Button
3. Observe "Failed: syntheticRotate" on ~5th attempt and back navigation

**Root cause hypothesis**: Rotate gesture movement pattern may conflict with the iOS swipe-right-to-go-back recognizer. Gesture recognizer priority not set correctly for button elements.

**Impact**: Unintended navigation causes state loss. Rotate gestures cannot be relied on for automation. Potential real-user impact if two-finger rotation over a button element triggers spurious back navigation.

---

### ANOMALY — High

---

#### A-HIGH-1 — Todo List does not persist items across navigation
**Session**: report-2026-02-19-1346-state-exploration
**Screen**: Todo List
**Severity**: High — core feature broken
**Confidence**: Confirmed (reproduced 3/3)

**Steps to reproduce**:
1. Navigate to Main Menu → Todo List
2. Type "Buy groceries" → tap Add → verify "1 item remaining"
3. Tap Back → navigate to Main Menu
4. Re-enter Todo List

**Expected**: "Buy groceries" still present
**Actual**: List resets to empty ("0 items remaining", "No todos yet") on every visit

**Impact**: All todo data is lost on every navigation. The feature is non-functional for any persistent use.

---

#### A-HIGH-2 — Color Picker exposes zero accessibility elements — VoiceOver completely locked out
**Session**: report-2026-02-19-1346-state-exploration, report-2026-02-19-1419-color-picker-investigation
**Screen**: Toggles & Pickers → color picker sheet
**Severity**: High — complete accessibility failure
**Confidence**: Confirmed

**Steps to reproduce**:
1. Navigate to Controls Demo → Toggles & Pickers
2. Tap `buttonheist.pickers.colorPicker` ("Accent color")
3. Call `get_interface`

**Expected**: Color grid, tab bar (Grid/Spectrum/Sliders), opacity slider, X button all accessible via VoiceOver
**Actual**: `get_interface` returns **0 elements**. The only element in the tree is a `PopoverDismissRegion` at off-screen coordinates (frameX: -402, frameY: -874). The entire color picker UI is inaccessible.

**VoiceOver user impact**: Cannot see any picker UI, cannot select a color, cannot know the current color, cannot dismiss the picker — making the entire feature inaccessible.

**Nuance (from session 3)**: Sighted users CAN interact via coordinate taps. `tap(x: 195, y: 640)` successfully changed the value from "cyan blue" to "dark purple" (confirmed by element value after dismiss). The feature is not pixel-dead — only accessibility-dead.

---

### ANOMALY — Medium

---

#### A-MED-1 — "Clear Completed" button visible when completed items are hidden
**Session**: report-2026-02-19-1346-state-exploration
**Screen**: Todo List
**Severity**: Medium — misleading UX, data loss risk
**Confidence**: Confirmed (reproduced 2/2)

**Steps to reproduce**:
1. In Settings, set Show Completed Todos = OFF
2. Navigate to Todo List, add an item, complete it
3. Observe "Clear Completed" button is present
4. Switch to "Completed" filter — shows empty ("No completed todos")

**Expected**: Either "Clear Completed" is hidden when showCompleted=OFF, or the Completed filter still shows items
**Actual**: "Clear Completed" is visible and operable on items the user cannot see. The "Completed" filter is also always empty when the setting is OFF, making the filter button useless.

**Impact**: User can accidentally delete todos they cannot see. Silent data loss.

---

#### A-MED-2 — Three elements share the same accessibility identifier in Disclosure & Grouping
**Session**: report-2026-02-19-1346-state-exploration
**Screen**: Disclosure & Grouping (expanded state)
**Severity**: Medium — breaks test automation and VoiceOver targeting
**Confidence**: Confirmed (reproduced 2/2)

All three of these elements share `identifier: "buttonheist.disclosure.advancedGroup"`:
- Order 0: "Advanced Settings" disclosure header (button)
- Order 3: "Enable notifications" switch
- Order 4: "Dark mode" switch

**Expected**: Each element has a unique accessibility identifier
**Actual**: All three share the same identifier — any identifier-based targeting is ambiguous

**Impact**: `XCTest` queries like `app.buttons["buttonheist.disclosure.advancedGroup"]` match all three. ButtonHeist `activate(identifier:)` cannot reliably target the individual toggles. Likely root cause of A-MED-3 below.

---

#### A-MED-3 — Disclosed toggles ("Enable notifications", "Dark mode") are completely inert
**Session**: report-2026-02-19-1346-state-exploration
**Screen**: Disclosure & Grouping (expanded state)
**Severity**: Medium — interactive elements that don't respond
**Confidence**: Confirmed (4/4 attempts, all interaction methods)

**Steps to reproduce**:
1. Navigate to Controls Demo → Disclosure & Grouping
2. Activate "Advanced Settings" to expand the group
3. Try any interaction on "Enable notifications" (order 3) or "Dark mode" (order 4):
   - `activate(order: 3)` → `noChange`
   - `tap(x: 338, y: 266)` → `noChange`
   - `activate(order: 4)` → `noChange`
   - `long_press(x: 338, y: 310)` → `noChange`

**Expected**: Toggle values change; hint "Double tap to toggle setting" fulfilled
**Actual**: All interactions return `noChange`. Both toggles are completely unresponsive.

**Note**: May be caused by A-MED-2 — duplicate identifiers could route all activation attempts to the header element (order 0) rather than the intended toggle.

---

#### A-MED-4 — MCP delta reporting returns `noChange` for real interactions when accessibility tree is empty
**Session**: report-2026-02-19-1419-color-picker-investigation
**Screen**: Any screen with 0 a11y elements (color picker open)
**Severity**: Medium — testing tooling reliability
**Confidence**: Confirmed

While the color picker is open (`elementCount: 0`), every MCP action tool returns `{"kind": "noChange", "elementCount": 0}` — even for interactions that visually succeed. A color selection at (195, 640) was confirmed to have changed the value to "dark purple" by both `get_screen` screenshot and post-dismiss `get_interface`, despite all intermediate tool calls reporting `noChange`.

**Root cause**: Delta-detection diffs the accessibility tree. With 0 elements, no diff is possible — all interactions appear as `noChange` by default.

**Impact**: Automated fuzz loops will silently misclassify any interaction in a 0-element state as "no effect". `get_screen` before/after is the only reliable verification mechanism.

---

### ANOMALY — Low

---

#### A-LOW-1 — Empty state message "No all todos" is grammatically incorrect
**Session**: report-2026-02-19-1346-state-exploration
**Screen**: Todo List
**Severity**: Low — copy/text bug
**Confidence**: Confirmed (reproduced 2/2)

**Steps to reproduce**:
1. In Settings, set Show Completed Todos = OFF
2. In Todo List with "All" filter selected, complete all active items

**Expected**: Natural-language message like "No todos", "All caught up", or "Nothing to show"
**Actual**: `buttonheist.todo.emptyLabel` reads **"No all todos"**

**Root cause**: Message constructed as `"No \(filterName.lowercased()) todos"`. Works for "Active" → "No active todos" and "Completed" → "No completed todos", but "All" → "No all todos". The "All" filter name needs special-casing.

---

#### A-LOW-2 — Pinch gesture fails on multiline text editor (bioEditor)
**Session**: fuzz-2026-02-17-swarm-testing
**Screen**: Text Input
**Severity**: Low — gesture type unsupported on this element
**Confidence**: Single occurrence (1/1 attempt)

`pinch(identifier: buttonheist.text.bioEditor, scale: 2.0)` returned "Failed: syntheticPinch". Other gestures on text fields (tap, type_text, long_press, swipe) all succeeded.

**Possible intent**: Pinch-to-zoom on a text editor may be a legitimate iOS behavior (adjusting text size), but the implementation rejects the gesture.

---

### INFO

---

#### INFO-1 — Settings changes apply app-wide and persist across navigation (working correctly)
**Session**: report-2026-02-19-1346-state-exploration
**Severity**: Informational

Settings changes are reflected throughout the app:
- **Dark mode** → immediate app-wide dark background/light text (persists)
- **Accent color** → nav bar titles and buttons update immediately (persists)
- **Large text size** → nav bar switches from large-title to inline-title style; section headings grow (persists)
- **Show Completed Todos** → directly and immediately affects Todo List filter/empty state behavior (persists)
- **All settings** persist across navigation (navigate away and return — values preserved)

This is working correctly and is noted for completeness.

---

#### INFO-2 — Delta type inconsistency on back-navigation to Main Menu
**Session**: 2026-02-18-1754-screen-map, report-2026-02-19-1346-state-exploration
**Severity**: Informational

Back-navigation from Controls Demo Submenu→Main Menu and Touch Canvas→Main Menu sometimes reports `valuesChanged` or `elementsChanged` delta instead of `screenChanged`. The navigation works correctly — the delta classification alone is wrong.

**Impact**: Automation relying on `screenChanged` to detect navigation will miss these specific transitions. Use element content/count to verify destination, not delta type alone.

---

### Previously Reported / Resolved

#### RESOLVED — Sheet Dismiss button positioned off-screen
**Session**: 2026-02-18-1754-screen-map
**Resolution**: Fixed in a later InsideMan iteration

`buttonheist.presentation.sheetDismiss` was previously reported at Y:1268 in an 874pt window (414pt off-screen). Resolved.

---

#### RESOLVED — Unexpected navigation from Toggles & Pickers during swarm testing
**Session**: fuzz-2026-02-17-swarm-testing
**Resolution**: Fixed in a later InsideMan iteration

Activating the "Medium" segmented control occasionally triggered spurious back navigation to Controls Demo Submenu. Not reproduced in subsequent sessions. Resolved.

---

#### RESOLVED — Touch Canvas back button navigated to wrong screen
**Session**: 2026-02-17-1908-screen-map
**Resolution**: Fixed between Feb 17 and Feb 18

In the Feb 17 session, the Touch Canvas back button navigated to Controls Demo Submenu instead of Main Menu, creating a circular navigation path. By the Feb 18 screen map session, this was no longer observed — Touch Canvas back navigation now correctly returns to Main Menu.

---

## Screen Coverage Summary

| Screen | Sessions | Interactive Elements | Coverage | Key Findings |
|--------|----------|---------------------|----------|--------------|
| Main Menu | All | 4 | 100% | — |
| Controls Demo Submenu | All | 7 | 100% | INFO-2 (delta inconsistency) |
| Text Input | Feb 17, Feb 18 | 4 fields | 100% | A-LOW-2 (pinch fails on bioEditor) |
| Toggles & Pickers | All | 7 | 90% | A-HIGH-2, A-MED-4 |
| Buttons & Actions | Feb 17, Feb 19 | 5 | 100% | CRIT-1 (rotate instability) |
| Adjustable Controls | Feb 17, Feb 18 | 5 | 80% | — (stable) |
| Disclosure & Grouping | Feb 18, Feb 19 | 3 | 100% | A-MED-2 (dup IDs), A-MED-3 (inert toggles) |
| Alerts & Sheets | Feb 18, Feb 19 | 3 | 100% | — |
| Display | Feb 17, Feb 18, Feb 19 | 2 | 100% | — (learnMoreLink opens Safari correctly) |
| Touch Canvas | Feb 17, Feb 18, Feb 19 | 2 | 60% | RESOLVED (wrong back nav fixed) |
| Todo List | Feb 19 | 7 | 100% | A-HIGH-1, A-MED-1, A-LOW-1 |
| Settings | Feb 19 | 10 | 100% | INFO-1 |
| Alert overlay | Feb 18, Feb 19 | 2 | 100% | — |
| Confirmation sheet | Feb 18, Feb 19 | 3 | 100% | — |
| Bottom Sheet | Feb 18, Feb 19 | 2 | 100% | — |
| Date Picker calendar | Feb 19 | 28+ | 80% | — |

### Not Yet Tested

| Area | Why |
|------|-----|
| Color picker: Spectrum + Sliders tabs | Coordinate-based; not reached in current sessions |
| Color picker: opacity slider | Coordinate-based; not reached |
| Color picker: predefined swatches | Coordinate-based; not reached |
| Touch Canvas: drawing gestures | Draw/drag paths not explored |
| Adjustable Controls: stepper increment/decrement | Excluded from swarm session |
| Settings: adversarial username values | (long strings, emoji, injection) |
| Text Input: submit/form behavior | No submit button observed |

---

## Gestures Used Across All Sessions

| Gesture | Screens Tested On | Notes |
|---------|-----------------|-------|
| tap / activate | All | Reliable except when a11y tree is empty |
| type_text | Text Input, Todo List | Reliable; emoji, XSS, SQL injection all accepted as plain text |
| swipe | Multiple | Reliable for dismissal; used for slider adjustment |
| long_press | Text Input, Display, Adjustable Controls | Reliable |
| pinch | Text Input, Buttons & Actions | FAILS on bioEditor (A-LOW-2); works on buttons |
| rotate | Buttons & Actions | CRITICAL instability (CRIT-1) — 50% failure rate |
| increment/decrement | Not tested in recent sessions | — |
| draw_path | Not tested | Touch Canvas untested with draw |

---

## Priority Recommendations

### Fix immediately

1. **A-HIGH-1 (Todo persistence)**: Data loss on every navigation. The core feature is non-functional. Add `@AppStorage` or `UserDefaults`/Core Data persistence to the Todo view model.

2. **A-HIGH-2 (ColorPicker accessibility)**: File as a SwiftUI bug or wrap `ColorPicker` in a custom accessible container. The entire feature is invisible to VoiceOver.

3. **CRIT-1 (Rotate gesture instability)**: The rotate gesture conflicts with the back-swipe recognizer. Either disable rotation on elements that aren't designed for it, or adjust gesture recognizer priorities.

### Fix soon

4. **A-MED-2 + A-MED-3 (Disclosure group identifiers + inert toggles)**: Assign unique identifiers to the header, "Enable notifications", and "Dark mode" elements. Fixing the identifier duplication will likely resolve the inert toggle issue.

5. **A-MED-1 (Clear Completed UX)**: Either hide "Clear Completed" when `showCompleted=OFF`, or make completed items visible in the "Completed" filter regardless of the setting.

### Fix when possible

6. **A-LOW-1 ("No all todos")**: Special-case the "All" filter name in the empty state message. E.g. `filterName == "All" ? "No todos" : "No \(filterName.lowercased()) todos"`.

7. **A-LOW-2 (Pinch on bioEditor)**: Decide whether pinch is intentional on the bio editor. If not, document the limitation. If yes, debug the gesture recognizer.

### Testing tool improvements

8. **A-MED-4 (noChange when elementCount=0)**: When the fuzzer encounters a 0-element state, it should call `get_screen` before and after each tap batch instead of relying on delta classification. `noChange` with `elementCount: 0` should be treated as "unknown" not "no effect".

---

## Sessions Index

| Date | Session File | Strategy | Findings |
|------|-------------|----------|----------|
| 2026-02-17 | stress-test-2026-02-17-buttons-actions | stress-test | CRIT-1 |
| 2026-02-17 | 2026-02-17-1908-screen-map | map-screens | Touch Canvas back nav (RESOLVED) |
| 2026-02-17 | fuzz-2026-02-17-swarm-testing | swarm-testing | A-LOW-2, RESOLVED |
| 2026-02-18 | 2026-02-18-1754-screen-map | map-screens | RESOLVED, INFO-2 |
| 2026-02-19 | report-2026-02-19-1346-state-exploration | state-exploration | A-HIGH-1, A-HIGH-2, A-MED-1, A-MED-2, A-MED-3, A-LOW-1, INFO-1 |
| 2026-02-19 | report-2026-02-19-1419-color-picker-investigation | gesture-fuzzing | A-MED-6, A-HIGH-2 (nuance) |

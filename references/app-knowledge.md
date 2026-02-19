# App Knowledge Base

Persistent knowledge accumulated across fuzzing sessions. Read at session start to plan intelligently. Update at session end with new discoveries.

**Last updated**: 2026-02-19
**App**: AccessibilityTestApp
**Sessions contributing**: 6

## Coverage Summary

Per-screen testing depth. Use this to identify where to focus next.

| Screen | Intent | Elements | Tested | Action Types Used | Strategies Run | Last Tested | Gaps |
|--------|--------|----------|--------|-------------------|----------------|-------------|------|
| Main Menu | Nav Hub | 4 | 4 (100%) | activate, tap | systematic, state-exploration, swarm, map-screens | 2026-02-19 | — |
| Controls Demo Submenu | Nav Hub | 7 | 7 (100%) | activate, tap | systematic, state-exploration, swarm, map-screens | 2026-02-19 | — |
| Text Input | Form | 4 | 4 (100%) | activate, tap, type_text, long_press, pinch | swarm | 2026-02-17 | adversarial values not tested, no submit behavior tested |
| Toggles & Pickers | Settings | 7 | 6 (90%) | activate, tap | state-exploration, map-screens | 2026-02-19 | colorPicker has 0 a11y elements (untestable via tree) |
| Buttons & Actions | Mixed | 5 | 5 (100%) | activate, tap, rotate, long_press, swipe, pinch | stress-test, swarm | 2026-02-17 | — |
| Adjustable Controls | Settings | 5 | 4 (80%) | activate, tap, swipe | swarm, map-screens | 2026-02-18 | stepper increment/decrement boundary not tested |
| Disclosure & Grouping | Settings | 3 | 3 (100%) | activate, tap, long_press | state-exploration, map-screens | 2026-02-19 | inner toggles inert (A-MED-3), may need re-test after identifier fix |
| Alerts & Sheets | Mixed | 3 | 3 (100%) | activate, tap | state-exploration, map-screens | 2026-02-19 | — |
| Display | Detail | 2 | 2 (100%) | activate, tap, long_press | swarm, map-screens | 2026-02-19 | — |
| Touch Canvas | Canvas | 2 | 1 (50%) | activate, tap | map-screens | 2026-02-18 | draw_path never used, drawing gestures untested |
| Todo List | Item List | 7 | 7 (100%) | activate, tap, type_text, swipe | state-exploration | 2026-02-19 | — |
| Settings | Settings | 10 | 10 (100%) | activate, tap, increment, decrement | state-exploration | 2026-02-19 | adversarial username values not tested |
| Alert overlay | Alert | 2 | 2 (100%) | activate | state-exploration, map-screens | 2026-02-19 | — |
| Confirmation sheet | Alert | 3 | 3 (100%) | activate | state-exploration, map-screens | 2026-02-19 | — |
| Bottom Sheet | Alert | 2 | 2 (100%) | activate | state-exploration, map-screens | 2026-02-19 | — |
| Date Picker calendar | Picker | 28+ | 5 (20%) | activate | state-exploration | 2026-02-19 | most day buttons untested, month navigation untested |

## Behavioral Models

Accumulated per-screen models from the most recent session that tested each screen. These are starting points — always verify against current app state.

### Todo List (Item List)
**Last validated**: 2026-02-19 (state-exploration session)
**State**: {items: [], count: 0, filter: "All", emptyVisible: true, clearCompletedVisible: false}
**Coupling**: newItemField.text ↔ addButton.enabled, items.length → itemCount label, items.length==0 → emptyLabel.visible, filter → visible subset of items, showCompleted setting → completed item visibility
**Cross-screen effects**: Settings.showCompleted directly affects filter behavior and empty state messages
**Confirmed predictions**: add→count++, delete→count--, filter changes visible subset, empty label appears at count==0
**Violated predictions**: items DO NOT persist across navigation (F-1), "All" filter empty state message is grammatically broken (F-2), "Clear Completed" visible when completed items hidden (F-3)

### Settings (Settings/Preferences)
**Last validated**: 2026-02-19 (state-exploration session)
**State**: {colorScheme: "light"|"dark", accentColor: color, textSize: "default"|"large", username: string, showCompleted: bool, compactMode: bool}
**Coupling**: showCompleted → Todo List filter/empty state, colorScheme → app-wide theme, accentColor → nav bar tint, textSize → nav bar style + heading size
**Cross-screen effects**: All settings persist and apply app-wide immediately
**Confirmed predictions**: settings persist across navigation (3/3), dark mode applies to all screens, showCompleted affects Todo List filter behavior
**Open questions**: Does changing username affect any other screen? Does compactMode change anything visible?

### Disclosure & Grouping (Settings)
**Last validated**: 2026-02-19 (state-exploration session)
**State**: {advancedExpanded: bool, enableNotifications: ?, darkMode: ?}
**Coupling**: advancedGroup.activate → expand/collapse child elements
**Confirmed predictions**: activate header toggles expand/collapse
**Violated predictions**: inner toggles should respond to activate — they don't (F-6). All 3 elements share same identifier (F-5).
**Open questions**: Are inner toggles broken due to identifier duplication, or is there a separate bug?

## Findings Tracker

Track every finding across all sessions with investigation status.

| ID | Severity | Screen | Summary | Found | Status | Investigation Notes |
|----|----------|--------|---------|-------|--------|---------------------|
| A-HIGH-1 | HIGH | Todo List | Items not persisted across navigation | 2026-02-19 | open:confirmed | Reproduced 3/3. Scoped: entire screen state ephemeral. Settings DO persist. Root cause: @State not @StateObject or persistent storage. |
| A-HIGH-2 | HIGH | Toggles & Pickers | Color picker 0 accessibility elements | 2026-02-19 | open:investigated | Dedicated investigation session confirmed. Coordinate taps work but a11y tree empty. SwiftUI ColorPicker limitation. |
| A-MED-1 | MEDIUM | Todo List | Clear Completed visible when completed items hidden | 2026-02-19 | open:confirmed | Reproduced 2/2. showCompleted=OFF hides items but not the Clear Completed button. |
| A-MED-2 | MEDIUM | Disclosure & Grouping | 3 elements share same identifier | 2026-02-19 | open:confirmed | Header + both inner toggles all have "buttonheist.disclosure.advancedGroup". Likely root cause of A-MED-3. |
| A-MED-3 | MEDIUM | Disclosure & Grouping | Disclosed toggles completely inert | 2026-02-19 | open:uninvestigated | 4/4 attempts all noChange. Needs: test via coordinate tap at exact toggle center, test after potential identifier fix |
| A-MED-4 | MEDIUM | Any (0-element state) | noChange reported for real interactions when a11y tree empty | 2026-02-19 | open:investigated | Confirmed: delta detection diffs a11y tree. With 0 elements, no diff possible. get_screen is only verification method. |
| A-LOW-1 | LOW | Todo List | "No all todos" grammatical error | 2026-02-19 | open:confirmed | String interpolation: "No \(filter) todos" without special-casing "All". |
| A-LOW-2 | LOW | Text Input | Pinch fails on bioEditor | 2026-02-17 | open:uninvestigated | Single occurrence. Needs: reproduce, test pinch on other text fields for comparison |

### Status values:
- `open:uninvestigated` — found but not probed further (HIGH PRIORITY for next session)
- `open:investigating` — currently being investigated
- `open:confirmed` — reproduced and scoped, but not fixed
- `open:investigated` — fully investigated, understood, awaiting fix
- `closed:fixed` — verified fixed in a later session
- `closed:wont-fix` — intentional behavior or won't address

## Testing Gaps

Explicit list of known untested areas. Consult this when planning sessions.

- [ ] Text Input: adversarial values (injection, unicode edge cases, long strings) — never tested across 6 sessions
- [ ] Touch Canvas: drawing gestures (draw_path, draw_bezier) — canvas mapped but never drawn on
- [ ] Color picker: Spectrum + Sliders tabs — coordinate-based, not reached
- [ ] Color picker: opacity slider — coordinate-based, not reached
- [ ] Adjustable Controls: stepper increment/decrement boundary testing
- [ ] Settings: adversarial username values (long strings, emoji, injection)
- [ ] Date Picker: month navigation, boundary dates (Feb 29, Dec 31), rapid day selection
- [ ] Invariant testing: never run as a dedicated strategy
- [ ] Boundary testing: never run as a dedicated strategy
- [x] Todo List: CRUD lifecycle + persistence — tested 2026-02-19
- [x] Settings: cross-screen effects — verified 2026-02-19
- [x] Sub-interactions: menuPicker, Date Picker, optionsMenu, customActions, disclosure — explored 2026-02-19

## Session History

| Date | Strategy | Actions | Findings | Focus |
|------|----------|---------|----------|-------|
| 2026-02-17 | stress-test | ~390 | 0 | Buttons & Actions rapid gestures |
| 2026-02-17 | map-screens | ~50 | 1 (resolved) | Full app screen discovery |
| 2026-02-17 | swarm-testing | ~100 | 2 (A-LOW-2, 1 resolved) | Random action subsets across screens |
| 2026-02-18 | map-screens | ~50 | 1 (INFO-2) | Re-map after fixes |
| 2026-02-19 | state-exploration | ~92 | 7 | Todo List, Settings, cross-screen effects |
| 2026-02-19 | gesture-fuzzing | ~10 | 1 | Color picker investigation |

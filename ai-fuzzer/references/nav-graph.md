# Navigation Graph

Persistent navigation knowledge accumulated across fuzzing sessions. Read this at session start to pre-populate your navigation graph. Update it at session end with any new discoveries.

**Last updated**: 2026-02-19
**App**: AccessibilityTestApp
**Sessions contributing**: 4 (fuzzsession-2026-02-18-1751-map-screens.md, fuzzsession-2026-02-19-1127-explore-todo-list.md, fuzzsession-2026-02-19-1234-explore-revisit.md, fuzzsession-2026-02-19-1239-explore-settings.md)

## Screens

| # | Name | Fingerprint | Elements | Entry Points |
|---|------|-------------|----------|--------------|
| 1 | Main Menu | [Controls Demo, Touch Canvas, ButtonHeist Test App heading] | 3 | App launch root |
| 2 | Controls Demo Submenu | [Text Input, Toggles & Pickers, Buttons & Actions, Adjustable Controls, Disclosure & Grouping, Alerts & Sheets, Display, ButtonHeist Test App Back, Controls Demo heading] | 9 | Main Menu → "Controls Demo" |
| 3 | Text Input | [buttonheist.text.nameField, emailField, passwordField, bioEditor] | 7 | Controls Demo Submenu → "Text Input" |
| 4 | Toggles & Pickers | [buttonheist.pickers.subscribeToggle, menuPicker, colorPicker, lastActionLabel] | 12 | Controls Demo Submenu → "Toggles & Pickers" |
| 5 | Buttons & Actions | [buttonheist.actions.primaryButton, borderedButton, destructiveButton, optionsMenu, customActionsItem] | 11 | Controls Demo Submenu → "Buttons & Actions" |
| 6 | Adjustable Controls | [buttonheist.adjustable.slider, stepper-Increment, gauge, linearProgress, spinnerProgress] | 10 | Controls Demo Submenu → "Adjustable Controls" |
| 7 | Disclosure & Grouping | [buttonheist.disclosure.advancedGroup, versionLabel, buildLabel] | 6 | Controls Demo Submenu → "Disclosure & Grouping" |
| 8 | Alerts & Sheets | [buttonheist.presentation.alertButton, confirmButton, sheetButton, lastActionLabel] | 7 | Controls Demo Submenu → "Alerts & Sheets" |
| 9 | Display | [buttonheist.display.starImage, infoLabel, learnMoreLink, headerText, staticText] | 8 | Controls Demo Submenu → "Display" |
| 10 | Touch Canvas | [buttonheist.touchCanvas.resetButton] | 3 | Main Menu → "Touch Canvas" |
| 15 | Settings | [System/Light/Dark, Blue/Purple/Green/Orange, Small/Medium/Large, buttonheist.settings.username, buttonheist.settings.showCompleted, buttonheist.settings.compactMode, currentColorScheme/AccentColor/TextSize/Username labels] | 23 | Main Menu → "Settings" |
| 14 | Todo List | [buttonheist.todo.newItemField, addButton, itemCount, emptyLabel, filter All/Active/Completed] | 11 (base) | Main Menu → "Todo List" |
| 11 | Alert overlay | [Alert Title, message, OK button] | 3 | Alerts & Sheets → alertButton |
| 12 | Confirmation action sheet | [SAVE, DISCARD, CANCEL buttons] | 3 | Alerts & Sheets → confirmButton |
| 13 | Sheet overlay | [buttonheist.presentation.sheetTitle, sheetDismiss] | 2 | Alerts & Sheets → sheetButton |

## Transitions

| From | Action | To | Reverse Action | Reliable |
|------|--------|----|----------------|----------|
| Main Menu | activate "Controls Demo" (order 0) | Controls Demo Submenu | activate "ButtonHeist Test App" Back (order 7) | YES |
| Main Menu | activate "Touch Canvas" (order 1) | Touch Canvas | activate Back (order 0) | YES |
| Main Menu | activate "Settings" (order 3) | Settings | activate Back (order 21) | YES |
| Main Menu | activate "Todo List" (order 1) | Todo List | tap X:34 Y:78 (Back) | YES |
| Controls Demo Submenu | activate "Text Input" (order 0) | Text Input | activate "Controls Demo" Back (order 5) | YES |
| Controls Demo Submenu | activate "Toggles & Pickers" (order 1) | Toggles & Pickers | activate "Controls Demo" Back (order 10) | YES |
| Controls Demo Submenu | activate "Buttons & Actions" (order 2) | Buttons & Actions | activate "Controls Demo" Back (order 9) | YES |
| Controls Demo Submenu | activate "Adjustable Controls" (order 3) | Adjustable Controls | activate "Controls Demo" Back (order 8) | YES |
| Controls Demo Submenu | activate "Disclosure & Grouping" (order 4) | Disclosure & Grouping | activate "Controls Demo" Back (order 4) | YES |
| Controls Demo Submenu | activate "Alerts & Sheets" (order 5) | Alerts & Sheets | activate "Controls Demo" Back (order 5) | YES |
| Controls Demo Submenu | activate "Display" (order 6) | Display | activate "Controls Demo" Back (order 6) | YES |
| Alerts & Sheets | activate buttonheist.presentation.alertButton | Alert overlay | activate OK (order 2) | YES |
| Alerts & Sheets | activate buttonheist.presentation.confirmButton | Confirmation action sheet | activate CANCEL (order 2) | YES |
| Alerts & Sheets | activate buttonheist.presentation.sheetButton | Sheet overlay | ⚠️ sheetDismiss identifier fails; sheet auto-dismisses | UNRELIABLE |

## Back Routes

Known reliable back-navigation from each screen. Use these before falling back to heuristic back-navigation.

| Screen | Back Action | Destination | Method |
|--------|-------------|-------------|--------|
| Controls Demo Submenu | activate order 7 ("ButtonHeist Test App") | Main Menu | Back button |
| Text Input | activate order 5 ("Controls Demo") | Controls Demo Submenu | Back button |
| Toggles & Pickers | activate order 10 ("Controls Demo") | Controls Demo Submenu | Back button |
| Buttons & Actions | activate order 9 ("Controls Demo") | Controls Demo Submenu | Back button |
| Adjustable Controls | activate order 8 ("Controls Demo") | Controls Demo Submenu | Back button |
| Disclosure & Grouping | activate order 4 ("Controls Demo") | Controls Demo Submenu | Back button |
| Alerts & Sheets | activate order 5 ("Controls Demo") | Controls Demo Submenu | Back button |
| Display | activate order 6 ("Controls Demo") | Controls Demo Submenu | Back button |
| Touch Canvas | activate order 0 ("ButtonHeist Test App") | Main Menu | Back button |
| Settings | activate order 21 ("ButtonHeist Test App") | Main Menu | Back button |
| Todo List | tap X:34 Y:78 (Back button) | Main Menu | coordinate tap (activate fails) |
| Alert overlay | activate order 2 (OK) | Alerts & Sheets | OK button |
| Confirmation action sheet | activate order 2 (CANCEL) | Alerts & Sheets | CANCEL button |
| Sheet overlay | ⚠️ sheetDismiss not reliably activatable | Alerts & Sheets | auto-dismiss / swipe down |

## Notes

### Delta classification inconsistency
Back-navigation from Controls Demo Submenu→Main Menu and Touch Canvas→Main Menu sometimes reports `valuesChanged` or `elementsChanged` delta instead of `screenChanged`. The navigation still works — use element content/count to verify destination, not delta type alone.

### Todo List: swipe-to-Delete button not tappable mid-swipe
`buttonheist.todo.item-*` rows reveal a red Delete button on left swipe. The Delete button (order 0 in accessibility tree) cannot be tapped via tap/activate when exposed mid-swipe. Full swipe to X:20 edge deletes immediately. Back button on Todo List requires coordinate tap (X:34, Y:78) — `activate` returns "does not support activation".

### Sheet Dismiss button off-screen (F-1)
`buttonheist.presentation.sheetDismiss` appears at Y:1268 in an 874pt window — below the visible screen. Activation by identifier fails. The sheet self-dismisses after the animation warning. This is an accessibility bug: the dismiss button is not reachable via accessibility API.

### Main Menu: now has 4 items (Settings added)
RootView.swift updated — "Settings" is now order 3 at the root level. Main Menu element count is 5 (4 nav links + heading).

### Todo List: state not persisted across navigation (BUG)
`TodoListView.swift:11` — `@State private var items: [TodoItem] = []` — all todos are lost when the view is popped from NavigationStack. Confirmed: add items, navigate Back, return → empty list.

### Settings screen: all back navigation works via activate
Unlike Todo List, the Settings back button (order 21) works via `activate`. No coordinate tap workaround needed.

### Settings: showCompleted=Off hides items from ALL filters
When `buttonheist.settings.showCompleted = 0`, completed todos are hidden in ALL three filters (All, Active, Completed). The empty state in All filter shows "No all todos" — grammatically odd, from `"No \(filter.rawValue.lowercased()) todos"`.

### Unexplored sub-interactions (in-screen, not full screens)
- Toggles & Pickers: menuPicker dropdown, Date Picker calendar, colorPicker sheet
- Buttons & Actions: optionsMenu context menu, customActionsItem (Share/Favorite custom actions)
- Display: learnMoreLink (opens Safari externally)
- Disclosure & Grouping: advancedGroup disclosure toggle

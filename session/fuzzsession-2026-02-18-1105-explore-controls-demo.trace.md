# Action Trace

- **Session**: fuzzsession-2026-02-18-1105-explore-controls-demo.md
- **App**: AccessibilityTestApp
- **Device**: iPhone 16 Pro iOS 18.5
- **Started**: 2026-02-18T11:05:00Z
- **Format version**: 1

---

### #1 | observe | Controls Demo
```yaml
seq: 1
ts: "2026-02-18T11:05:03Z"
type: observe
tool: get_interface
screen: "Controls Demo"
screen_fingerprint: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
element_count: 9
interactive_count: 8
notes: "Navigation menu with 7 sub-screen rows, a Back button (Touch Canvas), and a static heading"
```

---

### #2 | interact | Controls Demo
```yaml
seq: 2
ts: "2026-02-18T11:05:42Z"
type: interact
tool: activate
args:
  order: 0
target:
  label: "Text Input"
  identifier: null
  order: 0
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Text Input"
  screen_fingerprint_after: ["buttonheist.text.bioEditor", "buttonheist.text.emailField", "buttonheist.text.nameField", "buttonheist.text.passwordField", "Controls Demo", "TEXT INPUT", "Text Input"]
  element_count_after: 7
  value_after: null
  finding: null
```

---

### #3 | navigate | Text Input
```yaml
seq: 3
ts: "2026-02-18T11:06:00Z"
type: navigate
tool: activate
args:
  order: 5
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 5
  value: null
  actions: ["activate"]
screen_before: "Text Input"
screen_fingerprint_before: ["buttonheist.text.bioEditor", "buttonheist.text.emailField", "buttonheist.text.nameField", "buttonheist.text.passwordField", "Controls Demo", "TEXT INPUT", "Text Input"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #4 | interact | Controls Demo
```yaml
seq: 4
ts: "2026-02-18T11:06:05Z"
type: interact
tool: activate
args:
  order: 1
target:
  label: "Toggles & Pickers"
  identifier: null
  order: 1
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Toggles & Pickers"
  screen_fingerprint_after: ["buttonheist.pickers.colorPicker", "buttonheist.pickers.lastActionLabel", "buttonheist.pickers.menuPicker", "buttonheist.pickers.subscribeToggle", "Controls Demo", "Date", "Date Picker", "High", "Low", "Medium", "TOGGLES & PICKERS", "Toggles & Pickers"]
  element_count_after: 12
  value_after: null
  finding: null
```

---

### #5 | navigate | Toggles & Pickers
```yaml
seq: 5
ts: "2026-02-18T11:06:12Z"
type: navigate
tool: activate
args:
  order: 10
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 10
  value: null
  actions: ["activate"]
screen_before: "Toggles & Pickers"
screen_fingerprint_before: ["buttonheist.pickers.colorPicker", "buttonheist.pickers.lastActionLabel", "buttonheist.pickers.menuPicker", "buttonheist.pickers.subscribeToggle", "Controls Demo", "Date", "Date Picker", "High", "Low", "Medium", "TOGGLES & PICKERS", "Toggles & Pickers"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #6 | interact | Controls Demo
```yaml
seq: 6
ts: "2026-02-18T11:06:15Z"
type: interact
tool: activate
args:
  order: 2
target:
  label: "Buttons & Actions"
  identifier: null
  order: 2
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Buttons & Actions"
  screen_fingerprint_after: ["buttonheist.actions.borderedButton", "buttonheist.actions.customActionsItem", "buttonheist.actions.destructiveButton", "buttonheist.actions.disabledButton", "buttonheist.actions.lastActionLabel", "buttonheist.actions.optionsMenu", "buttonheist.actions.primaryButton", "buttonheist.actions.tapCountLabel", "Buttons & Actions", "BUTTONS & ACTIONS", "Controls Demo"]
  element_count_after: 11
  value_after: null
  finding: null
notes: "customActionsItem has Share and Favorite custom actions; disabledButton is dimmed with no actions"
```

---

### #7 | navigate | Buttons & Actions
```yaml
seq: 7
ts: "2026-02-18T11:06:20Z"
type: navigate
tool: activate
args:
  order: 9
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 9
  value: null
  actions: ["activate"]
screen_before: "Buttons & Actions"
screen_fingerprint_before: ["buttonheist.actions.borderedButton", "buttonheist.actions.customActionsItem", "buttonheist.actions.destructiveButton", "buttonheist.actions.disabledButton", "buttonheist.actions.lastActionLabel", "buttonheist.actions.optionsMenu", "buttonheist.actions.primaryButton", "buttonheist.actions.tapCountLabel", "Buttons & Actions", "BUTTONS & ACTIONS", "Controls Demo"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #8 | interact | Controls Demo
```yaml
seq: 8
ts: "2026-02-18T11:06:24Z"
type: interact
tool: activate
args:
  order: 3
target:
  label: "Adjustable Controls"
  identifier: null
  order: 3
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Adjustable Controls"
  screen_fingerprint_after: ["Adjustable Controls", "ADJUSTABLE CONTROLS", "buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment", "Controls Demo"]
  element_count_after: 10
  value_after: null
  finding: null
notes: "stepper-Decrement is dimmed (no actions) at value=0; slider at 50, linearProgress at 40%, spinnerProgress at 1"
```

---

### #9 | navigate | Adjustable Controls
```yaml
seq: 9
ts: "2026-02-18T11:06:30Z"
type: navigate
tool: activate
args:
  order: 8
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 8
  value: null
  actions: ["activate"]
screen_before: "Adjustable Controls"
screen_fingerprint_before: ["Adjustable Controls", "ADJUSTABLE CONTROLS", "buttonheist.adjustable.gauge", "buttonheist.adjustable.lastActionLabel", "buttonheist.adjustable.linearProgress", "buttonheist.adjustable.slider", "buttonheist.adjustable.spinnerProgress", "buttonheist.adjustable.stepper-Decrement", "buttonheist.adjustable.stepper-Increment", "Controls Demo"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #10 | interact | Controls Demo
```yaml
seq: 10
ts: "2026-02-18T11:06:35Z"
type: interact
tool: activate
args:
  order: 4
target:
  label: "Disclosure & Grouping"
  identifier: null
  order: 4
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Disclosure & Grouping"
  screen_fingerprint_after: ["buttonheist.disclosure.advancedGroup", "buttonheist.disclosure.buildLabel", "buttonheist.disclosure.versionLabel", "Controls Demo", "Disclosure & Grouping", "DISCLOSURE & GROUPING"]
  element_count_after: 6
  value_after: null
  finding: null
notes: "advancedGroup is a disclosure button/heading; Version 1.0.0 and Build 42 labels already visible"
```

---

### #11 | navigate | Disclosure & Grouping
```yaml
seq: 11
ts: "2026-02-18T11:06:40Z"
type: navigate
tool: activate
args:
  order: 4
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 4
  value: null
  actions: ["activate"]
screen_before: "Disclosure & Grouping"
screen_fingerprint_before: ["buttonheist.disclosure.advancedGroup", "buttonheist.disclosure.buildLabel", "buttonheist.disclosure.versionLabel", "Controls Demo", "Disclosure & Grouping", "DISCLOSURE & GROUPING"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #12 | interact | Controls Demo
```yaml
seq: 12
ts: "2026-02-18T11:06:45Z"
type: interact
tool: activate
args:
  order: 5
target:
  label: "Alerts & Sheets"
  identifier: null
  order: 5
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Alerts & Sheets"
  screen_fingerprint_after: ["Alerts & Sheets", "ALERTS & SHEETS", "buttonheist.presentation.alertButton", "buttonheist.presentation.confirmButton", "buttonheist.presentation.lastActionLabel", "buttonheist.presentation.sheetButton", "Controls Demo"]
  element_count_after: 7
  value_after: null
  finding: null
```

---

### #13 | navigate | Alerts & Sheets
```yaml
seq: 13
ts: "2026-02-18T11:06:50Z"
type: navigate
tool: activate
args:
  order: 5
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 5
  value: null
  actions: ["activate"]
screen_before: "Alerts & Sheets"
screen_fingerprint_before: ["Alerts & Sheets", "ALERTS & SHEETS", "buttonheist.presentation.alertButton", "buttonheist.presentation.confirmButton", "buttonheist.presentation.lastActionLabel", "buttonheist.presentation.sheetButton", "Controls Demo"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #14 | interact | Controls Demo
```yaml
seq: 14
ts: "2026-02-18T11:06:53Z"
type: interact
tool: activate
args:
  order: 6
target:
  label: "Display"
  identifier: null
  order: 6
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Display"
  screen_fingerprint_after: ["buttonheist.display.headerText", "buttonheist.display.infoLabel", "buttonheist.display.learnMoreLink", "buttonheist.display.starImage", "buttonheist.display.staticText", "Controls Demo", "Display", "DISPLAY"]
  element_count_after: 8
  value_after: null
  finding: null
notes: "learnMoreLink is an Apple Accessibility link button; starImage and staticText are non-interactive"
```

---

### #15 | navigate | Display
```yaml
seq: 15
ts: "2026-02-18T11:06:58Z"
type: navigate
tool: activate
args:
  order: 6
purpose: back_navigation
target:
  label: "Controls Demo"
  identifier: null
  order: 6
  value: null
  actions: ["activate"]
screen_before: "Display"
screen_fingerprint_before: ["buttonheist.display.headerText", "buttonheist.display.infoLabel", "buttonheist.display.learnMoreLink", "buttonheist.display.starImage", "buttonheist.display.staticText", "Controls Demo", "Display", "DISPLAY"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #16 | interact | Controls Demo
```yaml
seq: 16
ts: "2026-02-18T11:07:07Z"
type: interact
tool: activate
args:
  order: 7
target:
  label: "Touch Canvas"
  identifier: null
  order: 7
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers", "Touch Canvas"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "buttonheist.touchCanvas.resetButton", "Touch Canvas"]
  element_count_after: 3
  value_after: null
  finding: null
notes: "Back button leads to Touch Canvas (sibling screen in nav stack), not to app root. Canvas drawing area not exposed in accessibility tree."
```

---

### #17 | navigate | Touch Canvas
```yaml
seq: 17
ts: "2026-02-18T11:07:20Z"
type: navigate
tool: activate
args:
  order: 0
purpose: back_navigation
target:
  label: "ButtonHeist Test App"
  identifier: null
  order: 0
  value: null
  actions: ["activate"]
screen_before: "Touch Canvas"
screen_fingerprint_before: ["ButtonHeist Test App", "buttonheist.touchCanvas.resetButton", "Touch Canvas"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "ButtonHeist Test App"
  screen_fingerprint_after: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
  element_count_after: 3
  value_after: null
  finding: null
notes: "Root screen — two entries: Controls Demo and Touch Canvas"
```

---

### #18 | navigate | ButtonHeist Test App
```yaml
seq: 18
ts: "2026-02-18T11:07:30Z"
type: navigate
tool: activate
args:
  order: 0
purpose: setup
target:
  label: "Controls Demo"
  identifier: null
  order: 0
  value: null
  actions: ["activate"]
screen_before: "ButtonHeist Test App"
screen_fingerprint_before: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "ButtonHeist Test App", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
  element_count_after: 9
  value_after: null
  finding: null
notes: "Back button now reads 'ButtonHeist Test App' instead of 'Touch Canvas' — nav stack correctly updated"
```

---

### #19 | interact | Controls Demo
```yaml
seq: 19
ts: "2026-02-18T11:07:40Z"
type: interact
tool: tap
args:
  x: 133
  y: 124
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "ButtonHeist Test App", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
result:
  status: success
  method: syntheticTap
  screen_changed: false
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "ButtonHeist Test App", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
  element_count_after: 9
  value_after: null
  finding: null
notes: "Tap on Controls Demo heading — no state change, expected"
```

---

### #20 | interact | Controls Demo
```yaml
seq: 20
ts: "2026-02-18T11:07:46Z"
type: interact
tool: long_press
args:
  order: 8
target:
  label: "Controls Demo"
  identifier: null
  order: 8
  value: null
  actions: []
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "ButtonHeist Test App", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
result:
  status: success
  method: syntheticLongPress
  screen_changed: false
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "Buttons & Actions", "ButtonHeist Test App", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
  element_count_after: 9
  value_after: null
  finding: null
notes: "Long-press on Controls Demo heading — fully inert, no context menu or state change"
```

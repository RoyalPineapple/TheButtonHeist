# Action Trace

- **Session**: fuzzsession-2026-02-18-1128-explore-root.md
- **App**: AccessibilityTestApp
- **Device**: iPhone 16 Pro iOS 18.5
- **Started**: 2026-02-18T11:28:47Z
- **Format version**: 1

---

### #1 | observe | ButtonHeist Test App (Root)
```yaml
seq: 1
ts: "2026-02-18T11:28:47Z"
type: observe
tool: get_interface
screen: "ButtonHeist Test App (Root)"
screen_fingerprint: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
element_count: 3
interactive_count: 2
notes: "Root navigation screen with 2 nav rows and a heading"
```

---

### #2 | interact | ButtonHeist Test App (Root)
```yaml
seq: 2
ts: "2026-02-18T11:29:10Z"
type: interact
tool: activate
args:
  order: 0
target:
  label: "Controls Demo"
  identifier: null
  order: 0
  value: null
  actions: ["activate"]
screen_before: "ButtonHeist Test App (Root)"
screen_fingerprint_before: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Controls Demo"
  screen_fingerprint_after: ["Adjustable Controls", "Alerts & Sheets", "ButtonHeist Test App", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
  element_count_after: 9
  value_after: null
  finding: null
```

---

### #3 | navigate | Controls Demo
```yaml
seq: 3
ts: "2026-02-18T11:29:44Z"
type: navigate
tool: activate
args:
  order: 7
purpose: back_navigation
target:
  label: "ButtonHeist Test App"
  identifier: null
  order: 7
  value: null
  actions: ["activate"]
screen_before: "Controls Demo"
screen_fingerprint_before: ["Adjustable Controls", "Alerts & Sheets", "ButtonHeist Test App", "Buttons & Actions", "Controls Demo", "Disclosure & Grouping", "Display", "Text Input", "Toggles & Pickers"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "ButtonHeist Test App (Root)"
  screen_fingerprint_after: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
  element_count_after: 3
  value_after: null
  finding: null
```

---

### #4 | interact | ButtonHeist Test App (Root)
```yaml
seq: 4
ts: "2026-02-18T11:30:00Z"
type: interact
tool: activate
args:
  order: 1
target:
  label: "Touch Canvas"
  identifier: null
  order: 1
  value: null
  actions: ["activate"]
screen_before: "ButtonHeist Test App (Root)"
screen_fingerprint_before: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
  element_count_after: 3
  value_after: null
  finding: null
```

---

### #5 | interact | Touch Canvas
```yaml
seq: 5
ts: "2026-02-18T11:31:10Z"
type: interact
tool: activate
args:
  order: 1
target:
  label: "Reset"
  identifier: "buttonheist.touchCanvas.resetButton"
  order: 1
  value: null
  actions: ["activate"]
screen_before: "Touch Canvas"
screen_fingerprint_before: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
result:
  status: success
  method: activate
  screen_changed: false
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Canvas was already blank; reset is a no-op on empty canvas"
```

---

### #6 | interact | Touch Canvas
```yaml
seq: 6
ts: "2026-02-18T11:31:20Z"
type: interact
tool: draw_path
args:
  points:
    - {x: 100, y: 300}
    - {x: 200, y: 400}
    - {x: 300, y: 300}
    - {x: 200, y: 200}
    - {x: 100, y: 300}
target: null
screen_before: "Touch Canvas"
screen_fingerprint_before: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
result:
  status: success
  method: syntheticDrawPath
  screen_changed: false
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Diamond shape rendered on canvas (confirmed via screenshot). Small red dot visible near bottom of screen at ~(480, 880)."
```

---

### #7 | interact | Touch Canvas
```yaml
seq: 7
ts: "2026-02-18T11:31:35Z"
type: interact
tool: activate
args:
  order: 1
target:
  label: "Reset"
  identifier: "buttonheist.touchCanvas.resetButton"
  order: 1
  value: null
  actions: ["activate"]
screen_before: "Touch Canvas"
screen_fingerprint_before: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
result:
  status: success
  method: activate
  screen_changed: false
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Canvas cleared — diamond stroke removed (confirmed via screenshot)"
```

---

### #8 | interact | Touch Canvas
```yaml
seq: 8
ts: "2026-02-18T11:31:45Z"
type: interact
tool: tap
args:
  order: 2
target:
  label: "Touch Canvas"
  identifier: null
  order: 2
  value: null
  actions: []
screen_before: "Touch Canvas"
screen_fingerprint_before: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
result:
  status: success
  method: syntheticTap
  screen_changed: false
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Heading tap — no-op as expected"
```

---

### #9 | interact | Touch Canvas
```yaml
seq: 9
ts: "2026-02-18T11:31:50Z"
type: interact
tool: long_press
args:
  order: 2
target:
  label: "Touch Canvas"
  identifier: null
  order: 2
  value: null
  actions: []
screen_before: "Touch Canvas"
screen_fingerprint_before: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
result:
  status: success
  method: syntheticLongPress
  screen_changed: false
  screen_after: "Touch Canvas"
  screen_fingerprint_after: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Heading long-press — no-op as expected"
```

---

### #10 | navigate | Touch Canvas
```yaml
seq: 10
ts: "2026-02-18T11:32:10Z"
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
screen_fingerprint_before: ["ButtonHeist Test App", "Touch Canvas", "buttonheist.touchCanvas.resetButton"]
result:
  status: success
  method: syntheticTap
  screen_changed: true
  screen_after: "ButtonHeist Test App (Root)"
  screen_fingerprint_after: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
  element_count_after: 3
  value_after: null
  finding: null
```

---

### #11 | interact | ButtonHeist Test App (Root)
```yaml
seq: 11
ts: "2026-02-18T11:32:20Z"
type: interact
tool: tap
args:
  order: 2
target:
  label: "ButtonHeist Test App"
  identifier: null
  order: 2
  value: null
  actions: []
screen_before: "ButtonHeist Test App (Root)"
screen_fingerprint_before: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
result:
  status: success
  method: syntheticTap
  screen_changed: false
  screen_after: "ButtonHeist Test App (Root)"
  screen_fingerprint_after: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Heading tap — no-op as expected"
```

---

### #12 | interact | ButtonHeist Test App (Root)
```yaml
seq: 12
ts: "2026-02-18T11:32:25Z"
type: interact
tool: long_press
args:
  order: 2
target:
  label: "ButtonHeist Test App"
  identifier: null
  order: 2
  value: null
  actions: []
screen_before: "ButtonHeist Test App (Root)"
screen_fingerprint_before: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
result:
  status: success
  method: syntheticLongPress
  screen_changed: false
  screen_after: "ButtonHeist Test App (Root)"
  screen_fingerprint_after: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
  element_count_after: 3
  value_after: null
  finding: null
  notes: "Heading long-press — no-op as expected"
```

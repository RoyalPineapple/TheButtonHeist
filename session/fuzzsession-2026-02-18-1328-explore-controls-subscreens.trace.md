# Action Trace

- **Session**: fuzzsession-2026-02-18-1328-explore-controls-subscreens.md
- **App**: AccessibilityTestApp
- **Device**: iPhone 16 Pro iOS 18.5
- **Started**: 2026-02-18T15:11:00Z
- **Format version**: 1

---

### #1 | observe | ButtonHeist Test App (Root)
```yaml
seq: 1
ts: "2026-02-18T15:11:03Z"
type: observe
tool: get_interface
screen: "ButtonHeist Test App (Root)"
screen_fingerprint: ["ButtonHeist Test App", "Controls Demo", "Touch Canvas"]
element_count: 3
interactive_count: 2
notes: "At root — navigating to Controls Demo"
```

---

### #2 | navigate | ButtonHeist Test App (Root)
```yaml
seq: 2
ts: "2026-02-18T15:11:10Z"
type: navigate
tool: activate
args: {order: 0}
target: {label: "Controls Demo", order: 0}
screen_before: "ButtonHeist Test App (Root)"
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Controls Demo"
  element_count_after: 9
  finding: null
```

---

### #3 | navigate | Controls Demo
```yaml
seq: 3
ts: "2026-02-18T15:11:20Z"
type: navigate
tool: activate
args: {order: 0}
target: {label: "Text Input", order: 0}
screen_before: "Controls Demo"
result:
  status: success
  method: activate
  screen_changed: true
  screen_after: "Text Input"
  element_count_after: 14
  finding: null
```

---

### #4 | interact | Text Input
```yaml
seq: 4
ts: "2026-02-18T15:11:30Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.nameField", text: "Alice"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "Alice"
  finding: null
  notes: "Name field accepted basic ASCII text"
```

---

### #5 | interact | Text Input
```yaml
seq: 5
ts: "2026-02-18T15:11:35Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.nameField", deleteCount: 10, text: "José 🎉"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "José 🎉"
  finding: null
  notes: "Name field accepted unicode (accented char + emoji)"
```

---

### #6 | interact | Text Input
```yaml
seq: 6
ts: "2026-02-18T15:11:40Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.nameField", deleteCount: 20, text: "AAAA...x100"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  finding: null
  notes: "Name field accepted 100-char string with no truncation"
```

---

### #7 | interact | Text Input
```yaml
seq: 7
ts: "2026-02-18T15:11:50Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.emailField", text: "user@example.com"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "user@example.com"
  finding: null
  notes: "Email field accepted valid email address"
```

---

### #8 | interact | Text Input
```yaml
seq: 8
ts: "2026-02-18T15:11:55Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.emailField", deleteCount: 20, text: "notanemail"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "notanemail"
  finding: null
  notes: "Email field accepted invalid email — no validation enforced"
```

---

### #9 | interact | Text Input
```yaml
seq: 9
ts: "2026-02-18T15:12:00Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.emailField", deleteCount: 20, text: "<script>alert(1)</script>"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "<script>alert(1)</script>"
  finding: null
  notes: "Email field accepted HTML/script injection string — no crash or unexpected behavior (expected for UITextField)"
```

---

### #10 | interact | Text Input
```yaml
seq: 10
ts: "2026-02-18T15:12:05Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.passwordField", text: "secret123!"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "••••••••••"
  finding: null
  notes: "Password field is a secure text field — value masked as dots"
```

---

### #11 | interact | Text Input
```yaml
seq: 11
ts: "2026-02-18T15:12:08Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.passwordField", deleteCount: 15, text: "  "}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "••"
  finding: null
  notes: "Password field accepted whitespace-only — no validation"
```

---

### #12 | interact | Text Input
```yaml
seq: 12
ts: "2026-02-18T15:12:12Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.bioEditor", text: "Hello world! This is a multiline bio."}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "Hello world! This is a multiline bio."
  finding: null
  notes: "Bio text editor accepted text"
```

---

### #13 | interact | Text Input
```yaml
seq: 13
ts: "2026-02-18T15:12:16Z"
type: interact
tool: type_text
args: {identifier: "buttonheist.text.bioEditor", deleteCount: 50, text: "Line1\nLine2\nLine3\n🌍🌎🌏"}
screen_before: "Text Input"
result:
  status: success
  method: typeText
  screen_changed: false
  value_after: "Line1\nLine2\nLine3\n🌍🌎🌏"
  finding: null
  notes: "Bio editor accepted newlines and multi-emoji — all preserved correctly"
```

---

### #14 | interact | Text Input
```yaml
seq: 14
ts: "2026-02-18T15:12:20Z"
type: interact
tool: tap
args: {order: 4}
target: {label: "TEXT INPUT", order: 4}
screen_before: "Text Input"
result:
  status: success
  method: syntheticTap
  screen_changed: false
  finding: null
  notes: "TEXT INPUT section heading — fully inert"
```

---

### #15 | interact | Text Input
```yaml
seq: 15
ts: "2026-02-18T15:12:22Z"
type: interact
tool: long_press
args: {order: 6}
target: {label: "Text Input", order: 6}
screen_before: "Text Input"
result:
  status: success
  method: syntheticLongPress
  screen_changed: false
  finding: null
  notes: "Nav title heading — fully inert"
```

---

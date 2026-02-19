# Explore Session — Controls Demo Sub-Screens

## Config
- **Status**: in_progress
- **Screen**: Controls Demo sub-screens (Text Input, Toggles & Pickers, Buttons & Actions, Adjustable Controls, Disclosure & Grouping, Alerts & Sheets, Display)
- **Trace file**: fuzzsession-2026-02-18-1328-explore-controls-subscreens.trace.md
- **Next finding ID**: F-1
- **Device**: iPhone 16 Pro iOS 18.5
- **App**: AccessibilityTestApp
- **Started**: 2026-02-18T13:28:00Z

## Navigation Stack

(empty — at root)

## Coverage

### Text Input ✅ Complete (traces #2–#15)
- [x] nameField — basic text, unicode (José 🎉), 100-char long string — all accepted
- [x] emailField — valid email, invalid format, HTML injection — all accepted, no validation
- [x] passwordField — masked as ••, accepts whitespace-only
- [x] bioEditor — multiline text, newlines, emoji — all accepted correctly
- [x] TEXT INPUT heading (order 4) — tap: inert
- [x] Text Input nav title (order 6) — long_press: inert

### Toggles & Pickers
- [ ] Pending exploration

### Buttons & Actions
- [ ] Pending exploration

### Adjustable Controls
- [ ] Pending exploration

### Disclosure & Grouping
- [ ] Pending exploration

### Alerts & Sheets
- [ ] Pending exploration

### Display
- [ ] Pending exploration

## Findings

None yet.

## Transitions Discovered

(from prior sessions)
- Root → Controls Demo (order 0)
- Controls Demo → Text Input (order 0)
- Controls Demo → Toggles & Pickers (order 1)
- Controls Demo → Buttons & Actions (order 2)
- Controls Demo → Adjustable Controls (order 3)
- Controls Demo → Disclosure & Grouping (order 4)
- Controls Demo → Alerts & Sheets (order 5)
- Controls Demo → Display (order 6)

## Progress

Starting — navigating to Controls Demo.

## Next Actions

1. Navigate root → Controls Demo → Text Input
2. Explore all text fields thoroughly (type, delete, edge cases)
3. Return to Controls Demo → explore next sub-screen
4. Repeat for all 7 sub-screens

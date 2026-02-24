# Fuzzing Report

**Session**: fuzzsession-2026-02-19-1413-fuzz-gesture-fuzzing
**Strategy**: gesture-fuzzing (focused investigation: color picker synthetic tap behavior)
**Date**: 2026-02-19T14:19:05Z
**App**: AccessibilityTestApp
**Device**: iPhone 16 Pro iOS 18.5
**Duration**: ~10 actions on 1 target screen (Toggles & Pickers)
**Trace file**: fuzzsession-2026-02-19-1413-fuzz-gesture-fuzzing.trace.md

---

## Summary

| Metric | Value |
|--------|-------|
| Screens visited | 3 (Todo List → Main Menu → Controls Demo Submenu → Toggles & Pickers) |
| Total actions | ~10 |
| Findings | 2 |
| CRASH | 0 |
| ERROR | 0 |
| ANOMALY | 2 |
| INFO | 0 |

**Context**: This session is a focused follow-up to F-4 from `report-2026-02-19-1346-state-exploration.md`. That session established the color picker exposes **0 accessibility elements** when open. This session investigated whether **coordinate-based synthetic taps** can still interact with the inaccessible UI.

**Answer**: **Yes — synthetic taps DO select colors.** The color changed from "cyan blue" to "dark purple" after `tap(x: 195, y: 640)`. After dismissal, `colorPicker.value` confirmed "dark purple". The color picker is not completely interaction-dead; it only fails the accessibility layer.

---

## Findings

### F-1 [ANOMALY] Synthetic taps select colors in the color picker despite zero accessibility elements

**Screen**: Toggles & Pickers — color picker sheet (open)
**Severity**: Medium — partially mitigates F-4, but exposes unreliable test signal
**Confidence**: Confirmed (visual + value read-back after dismissal)

**Steps to reproduce**:
1. Navigate to Controls Demo → Toggles & Pickers
2. Verify `buttonheist.pickers.colorPicker` value: "cyan blue"
3. Tap `buttonheist.pickers.colorPicker` (activationPoint: 348, 437) — picker opens
4. `get_interface` returns 0 elements (F-4 confirmed: a11y tree is empty)
5. `tap(x: 195, y: 640)` — targets a dark purple area in the color grid
6. All MCP tools return `{"kind": "noChange", "elementCount": 0}` — apparently no response
7. Dismiss the picker (swipe-down from center of sheet)
8. `get_interface` → `colorPicker.value` is now **"dark purple"** (was "cyan blue")

**Expected**: Either (a) taps are fully ignored (picker immutable without a11y), or (b) taps work AND the MCP detects the value change
**Actual**: Taps DO change the selected color. The color picker responds to synthetic touch input at the pixel level. However, MCP tools report `noChange` throughout because the delta-detection is driven by the accessibility tree — which is empty. The actual state change is invisible to the fuzzer until after the picker is dismissed.

**Impact**:
- **Positive**: The color picker is interactive for sighted users even without accessibility. The visual UI responds to touch.
- **Negative for testing**: Any MCP tool call made while the picker is open returns `noChange` with 0 elements regardless of what actually happened. The fuzzer cannot verify color selection success in real-time. A "did the color change?" check requires: open picker → tap → dismiss → read value.
- **Negative for VoiceOver users**: The feature remains completely inaccessible via VoiceOver — F-4 stands.

**Trace refs**: See session trace, actions #2 (open picker), #3 (tap at 195,640), #4 (dismiss), #5 (confirm value)

---

### F-2 [ANOMALY] MCP delta reporting is unreliable when accessibility tree is empty — `noChange` masks real interactions

**Screen**: Any screen with 0 accessibility elements (e.g., color picker open)
**Severity**: Medium — misleads the fuzzer, causes false "no interaction" classifications
**Confidence**: Confirmed

**Observation**:
When the accessibility tree has 0 elements (as happens when the color picker sheet is open), every MCP action tool returns:

```json
{"kind": "noChange", "elementCount": 0}
```

This was returned for:
- `tap(x: 195, y: 640)` — which VISUALLY selected a new color (confirmed by screenshot and post-dismiss value)
- `tap(x: 365, y: 436)` — targeting the X close button (result unknown; may or may not have registered)
- `swipe(direction: down, startX: 201, startY: 400)` — which apparently DID dismiss the picker

In all cases, `noChange` was the reported delta. The value change ("cyan blue" → "dark purple") was only detectable after dismissal.

**Root cause**: The MCP's change detection is based on diffing the accessibility element tree. With 0 elements, there is nothing to diff, so every interaction reports `noChange` by default — even when the UI visually changed.

**Impact**:
- Automated fuzzing loops that treat `noChange` as "interaction had no effect" will silently skip or misclassify any interaction performed while the a11y tree is empty
- Color selection, opacity adjustment, tab switching (Grid/Spectrum/Sliders) are all **completely opaque** to the fuzzer while the picker is open
- `get_screen` is the only tool that can reveal what happened — but the fuzzer only calls it for findings, not routinely

**Mitigation for fuzz scripts**: When entering a 0-element state, use `get_screen` before and after each tap batch to detect visual changes. Do not trust `noChange` as ground truth when `elementCount: 0`.

---

## Color Picker Interaction Map

Based on this session, the color picker can be partially interacted with via synthetic taps. Full behavioral map:

| Action | Method | Works? | Notes |
|--------|--------|--------|-------|
| Open picker | `tap(x: 348, y: 437)` or `activate(identifier: "buttonheist.pickers.colorPicker")` | ✅ Yes | Opens color grid view |
| Select a grid color | `tap(x, y)` in grid area | ✅ Yes (CONFIRMED) | Value changes visually; requires dismiss to verify via a11y |
| Switch to Spectrum tab | `tap(x: 201, y: 287)` est. | ❓ Unknown | Not tested this session |
| Switch to Sliders tab | `tap(x: 321, y: 287)` est. | ❓ Unknown | Not tested this session |
| Adjust opacity slider | `tap` or `swipe` on slider | ❓ Unknown | Slider visible but not tested |
| Tap predefined swatches | `tap(x, y)` in swatch row | ❓ Unknown | Swatches visible but not tested |
| Close via X button | `tap(x: ~365, y: ~248)` | ❌ Didn't close | Coordinate may need further calibration |
| Close via swipe-down | `swipe(down)` from sheet | ✅ Yes (apparent) | Dismissed picker, confirming value change |
| VoiceOver interaction | Any accessibility method | ❌ Impossible | 0 elements, nothing to target |

**Coordinate calibration note**: The color picker sheet starts at approximately **y: 225pt** (not y: 415pt as naively estimated from the colorPicker row position). The sheet is a full-height overlay starting from near the top of the content area. Key approximate coordinates:
- X close button: `(367, 248)`
- Grid/Spectrum/Sliders tabs: `(76, 287)` / `(201, 287)` / `(321, 287)`
- Color grid: `x: 20–382`, `y: 318–624`
- Opacity slider: `y: ~677`
- Predefined swatches: `y: ~757`

---

## Relationship to Prior Findings

| Prior Finding | Status | Update |
|---------------|--------|--------|
| F-4: ColorPicker exposes 0 a11y elements (accessibility failure) | **Confirmed — still broken** | VoiceOver remains unable to access any element in the picker |
| F-4 additional: Dismiss is unreliable via a11y API | **Partially resolved** | Swipe-down gesture dismisses the picker; X button via synthetic tap needs calibration |

**F-4 remains HIGH severity** for accessibility. This session adds nuance: sighted users with motor control (or test scripts using coordinate taps) CAN interact with the picker. But VoiceOver users have no path in or out.

---

## Coverage

### Screen: Toggles & Pickers (color picker sheet)

| Element | Tested | Result |
|---------|--------|--------|
| Color grid (Grid tab) | ✅ Tap at (195, 640) | Color changes to dark purple — WORKS |
| X close button | ✅ Tap at (367, 248) | Did not close — coordinates may be off |
| Spectrum tab | ❌ Not tested | Unknown |
| Sliders tab | ❌ Not tested | Unknown |
| Opacity slider | ❌ Not tested | Unknown |
| Predefined swatches | ❌ Not tested | Unknown |
| Eyedropper button | ❌ Not tested | Unknown |
| Swipe-down dismiss | ✅ Swipe from (201, 400) down | Dismissed picker — WORKS |

### Gestures Used

| Gesture | Count |
|---------|-------|
| tap | 4 |
| swipe | 1 |
| activate | 3 |

---

## Recommendations

1. **Refine color picker coordinate map**: Run a systematic grid of taps with screenshot verification to build a complete coordinate → color map. The 12×11 grid spans approximately x: 20–382, y: 318–624.

2. **Test remaining tabs**: Try `tap(x: 201, y: 287)` for Spectrum and `tap(x: 321, y: 287)` for Sliders. If those tabs open, test their interactions.

3. **Test predefined swatches**: The row at y: ~757 contains preset colors (black, blue, green, yellow, red). These are likely tappable.

4. **Fix the X button coordinate**: Calibrate more precisely. The X button appears at approximately x: 365, y: 248 but the tap didn't register. Possible the button's hit area is smaller than expected.

5. **File accessibility bug**: The 0-element a11y tree when the picker is open is a SwiftUI bug (or an intentional omission). A VoiceOver user cannot: (a) see any picker UI, (b) select a color, (c) know the current color, or (d) dismiss the picker — making the entire feature inaccessible.

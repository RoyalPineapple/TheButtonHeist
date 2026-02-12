# Strategy: Gesture Fuzzing

Applies unexpected gestures to elements that probably don't handle them. Finds crash bugs, unhandled gesture recognizer conflicts, and unexpected state changes.

## Goal

Test what happens when elements receive gestures they weren't designed for. Most developers only test the "happy path" gesture for each element — this strategy tests everything else.

## Element Selection

Target elements that are **least likely** to expect complex gestures:

1. **Buttons** — Try pinch, rotate, swipe, drag, long_press on them
2. **Labels/text** — Try all gestures on static-looking text
3. **Toggle switches** — Try pinch, rotate, drag
4. **Navigation elements** — Try long_press, swipe, pinch
5. **Table/list cells** — Try rotate, pinch, two_finger_tap
6. **Any element** — Try two_finger_tap and rotate (rarely handled)

## Action Selection

For each element, apply the **full gesture matrix**:

### Single-Finger Gestures
1. `tap` — baseline
2. `long_press(duration: 0.5)` — default long press
3. `long_press(duration: 3.0)` — extended long press
4. `swipe(direction: "up")`
5. `swipe(direction: "down")`
6. `swipe(direction: "left")`
7. `swipe(direction: "right")`
8. `drag` from element center to 200pt in each direction

### Multi-Touch Gestures
9. `two_finger_tap` — centered on element
10. `pinch(scale: 2.0)` — zoom in
11. `pinch(scale: 0.5)` — zoom out
12. `rotate(angle: 1.57)` — 90 degrees
13. `rotate(angle: -1.57)` — -90 degrees

### Rapid Sequences (on same element)
14. Tap 5 times rapidly (5 sequential `tap` calls)
15. Swipe up then immediately swipe down
16. Pinch in then immediately pinch out
17. Tap then immediately long_press

### Random Coordinate Gestures

Generate a few interactions at random positions on the screen:
1. Pick random x,y within screen bounds
2. `tap(x: random_x, y: random_y)`
3. `swipe(startX: random_x1, startY: random_y1, endX: random_x2, endY: random_y2)`
4. `pinch(centerX: random_x, centerY: random_y, scale: random_scale)`

Use the screen dimensions from get_interface context to stay in bounds. Pick 5-10 random locations per screen.

## Termination

Stop gesture fuzzing a screen when:
- Every element has received the full gesture matrix
- Random coordinate gestures have been applied
- Any CRASH is detected (stop and report immediately)

Move to the next screen after completing the current one. Use `tap` on navigation elements to find new screens.

## What to Look For

- **Crashes from unexpected gestures**: The most valuable finding. Multi-touch gestures on simple elements sometimes trigger nil-pointer crashes in gesture recognizer code.
- **Gesture recognizer conflicts**: Two gesture recognizers competing can cause stuttery behavior or deadlocks.
- **Unintended actions**: A pinch on a button accidentally triggers the button's action.
- **State corruption**: After an unexpected gesture, the element is in a broken state (wrong value, wrong appearance).
- **UI freezes**: After a gesture sequence, the app stops responding to further actions (detectable when subsequent `get_interface` returns the same state and actions stop working).
- **Memory pressure**: Rapid gesture sequences may leak — watch for degrading response times (tool calls taking longer).

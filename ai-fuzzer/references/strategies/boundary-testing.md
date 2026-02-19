# Strategy: Boundary Testing

Targets the edges and extremes of the UI. Finds bugs that occur at boundaries — element edges, screen borders, extreme values, and coordinate edge cases.

## Goal

Test the boundaries of every interactive element and the screen itself. Finds layout bugs, off-by-one errors, hit-testing issues, and value overflow problems.

## Element Selection

Focus on elements that have **spatial properties** (frames) and **adjustable values**:

1. Elements with the largest frames (more boundary surface area)
2. Elements near screen edges (partial visibility issues)
3. Adjustable elements (sliders, steppers — they have value boundaries)
4. Overlapping elements (elements whose frames intersect)

## Action Selection

### Coordinate Boundary Taps

For each element, extract its frame (`frameX`, `frameY`, `frameWidth`, `frameHeight`) and tap at:

1. **Top-left corner**: `tap(x: frameX, y: frameY)`
2. **Top-right corner**: `tap(x: frameX + frameWidth, y: frameY)`
3. **Bottom-left corner**: `tap(x: frameX, y: frameY + frameHeight)`
4. **Bottom-right corner**: `tap(x: frameX + frameWidth, y: frameY + frameHeight)`
5. **Just outside each edge** (1 point beyond):
   - `tap(x: frameX - 1, y: center_y)` — left of element
   - `tap(x: frameX + frameWidth + 1, y: center_y)` — right of element
   - `tap(x: center_x, y: frameY - 1)` — above element
   - `tap(x: center_x, y: frameY + frameHeight + 1)` — below element

### Screen Edge Interactions

Test the absolute edges of the screen (use screen dimensions from server info):

1. `tap(x: 0, y: 0)` — top-left corner
2. `tap(x: screenWidth, y: 0)` — top-right corner
3. `tap(x: 0, y: screenHeight)` — bottom-left corner
4. `tap(x: screenWidth, y: screenHeight)` — bottom-right corner
5. `swipe(startX: 0, startY: screenHeight/2, direction: "right")` — left edge swipe
6. `swipe(startX: screenWidth, startY: screenHeight/2, direction: "left")` — right edge swipe
7. `swipe(startX: screenWidth/2, startY: 0, direction: "down")` — top edge swipe (notification center area)
8. `swipe(startX: screenWidth/2, startY: screenHeight, direction: "up")` — bottom edge swipe

### Value Boundaries

For adjustable elements (those with increment/decrement actions):

1. **Increment to maximum**: Call `increment` repeatedly (20 times) and track the value. Does it stop? Does it wrap?
2. **Decrement to minimum**: Call `decrement` repeatedly (20 times). Same checks.
3. **Rapid alternation**: Increment then decrement 10 times quickly.

### Extreme Gesture Parameters

1. `pinch(scale: 0.01)` — Extreme zoom out
2. `pinch(scale: 100.0)` — Extreme zoom in
3. `rotate(angle: 6.28)` — Full rotation (2*pi)
4. `rotate(angle: 628.0)` — 100 full rotations
5. `swipe(distance: 2000)` — Swipe way beyond screen
6. `long_press(duration: 10.0)` — Very long press
7. `drag` from (0,0) to (screenWidth, screenHeight) — full diagonal drag

## Termination

Stop boundary testing a screen when:
- All elements have been boundary-tested
- All edge coordinates have been tried
- All adjustable elements have been pushed to their limits

## What to Look For

- **Hit-testing failures**: Tapping inside an element's frame doesn't register
- **Ghost taps**: Tapping outside an element's frame triggers it anyway
- **Value overflow**: Increment past max wraps to min or produces garbled values
- **Layout breakage**: After extreme gestures, elements overlap or disappear
- **Screen edge issues**: Edge swipes trigger unexpected system gestures or app behavior
- **Unclipped content**: Elements visible outside their expected container frames
- **Crashes from extreme values**: Extreme pinch/rotate scales causing numeric overflow

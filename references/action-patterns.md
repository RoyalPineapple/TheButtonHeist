# Reusable Action Sequence Patterns

Composable interaction templates that strategies can reference. Each pattern is a self-contained sequence with a clear purpose. Apply these as building blocks instead of reinventing them per strategy.

## Navigate-Interact-Verify-Return

Test an element on another screen without losing your place.

```
1. Record current screen fingerprint → Origin
2. Navigate to target screen (via known transition)
3. Record target screen state → Before
4. Interact with the target element
5. Record target screen state → After
6. Compare Before and After — record any changes
7. Navigate back to Origin
8. Verify you returned (fingerprint matches Origin)
```

Use this when: You want to test an element on a different screen but need to come back to continue exploring the current one.

## Set-Leave-Return-Check

Test whether values persist across navigation (the Persistence invariant).

```
1. Record element's current value → Original
2. Change the value (activate toggle, increment slider, type text)
3. Record the new value → Changed
4. Navigate to a different screen
5. Navigate back
6. Record the value → Returned
7. Compare Changed and Returned
```

**Expected**: Changed == Returned (value persisted).
**Finding if violated**: ANOMALY — persistence broken.

Use this when: Testing any stateful element (toggles, sliders, text fields, pickers).

## Rapid-Fire

Test element stability under repeated interaction.

```
1. Record the screen state → Before
2. Perform the same action N times (default: 10)
3. Record the screen state → After
4. Compare Before and After
```

Variations:
- **Same action**: `activate` 10 times on the same button
- **Alternating**: `increment` then `decrement` 10 times
- **Mixed**: Alternate between `tap` and `long_press` 10 times

**Expected**: Element still exists, screen still responsive, no unexpected state changes.
**Finding if violated**: ANOMALY (element disappeared, value drifted) or CRASH (app died).

Use this when: Stress-testing an element, or when you suspect timing-sensitive bugs.

## Cross-Product

Try every action type on a single element.

```
1. Record the screen state → Baseline
2. For each action in the element's actions array:
   a. Perform the action
   b. Record the result (screen change, value change, no change)
   c. If the screen changed, navigate back
   d. Verify we're back on the original screen
3. Then try actions NOT in the actions array (as fuzzing):
   a. tap (if not already tried)
   b. long_press
   c. swipe (all 4 directions)
   d. pinch (in and out)
   e. rotate (clockwise and counter)
   f. two_finger_tap
4. Record which actions produced effects and which didn't
```

Use this when: Deep-testing a single element, or when using the gesture-fuzzing strategy.

## Cascade

Test interaction ordering — does interacting with A then B differ from B then A?

```
Sequence 1:
1. Record screen state → S0
2. Interact with element A → record state S1
3. Interact with element B → record state S2

Sequence 2:
4. Reset to S0 (navigate away and back, or undo actions)
5. Interact with element B → record state S3
6. Interact with element A → record state S4

Compare: S2 should equal S4 (if order doesn't matter)
```

**Expected**: Final state is the same regardless of order.
**Finding if violated**: INFO — "Elements [A] and [B] produce different states depending on interaction order." This isn't necessarily a bug, but it's worth noting.

Use this when: Testing forms with multiple fields, screens with multiple toggles, or anywhere interaction order might matter.

## Reset Test

Change a value then undo it — verify the element returns to its original state (the Reversibility invariant).

```
1. Record element value → Original
2. Change the value (activate toggle, increment, type text)
3. Record → Changed
4. Reverse the change (activate toggle again, decrement, delete and retype original)
5. Record → Restored
6. Compare Original and Restored
```

**Expected**: Original == Restored.
**Finding if violated**: ANOMALY — "Element [id] does not return to original state after change+undo"

Use this when: Testing any element with reversible state.

## Scroll-Discover

Explore hidden content by scrolling through containers.

```
1. Record all visible elements → Visible Set
2. Swipe up on the container area
3. Record all elements → New Visible Set
4. Note any newly appeared elements (in New but not in original Visible Set)
5. Repeat swipes until no new elements appear (swipe returned same set)
6. Swipe down repeatedly to return to top
7. Verify original Visible Set is restored
```

Use this when: The screen has lists, scroll views, or any content that might extend beyond the visible area. Always scroll before concluding a screen is "fully explored."

## Double-Tap Divergence

Test if rapid double-tapping produces different behavior from two separate taps.

```
1. Record state → S0
2. Tap element once → record state S1
3. Reset to S0 (navigate away and back if needed)
4. Tap element twice rapidly (minimal delay between taps)
5. Record state → S2
6. Compare S1 and S2
```

**Expected**: S1 == S2 (unless the element explicitly handles double-tap differently, like zoom).
**Finding if violated**: INFO — "Element [id] behaves differently on double-tap vs single tap"

Use this when: Testing buttons that might have accidental double-tap handlers, or list items that might have tap-vs-double-tap ambiguity.

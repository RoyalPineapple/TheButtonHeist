# TheSafecracker

All physical UI interactions — touch injection, text input, and gesture synthesis.

## Files

| File | Purpose |
|------|---------|
| `TheSafecracker.swift` | Single-finger gestures, keyboard wrappers, `InteractionResult` |
| `TheSafecracker+Actions.swift` | Draw path/bezier execution |
| `TheSafecracker+Scroll.swift` | Scroll primitives (setContentOffset + swipe fallback) |
| `TheSafecracker+MultiTouch.swift` | Pinch, rotate, two-finger tap |
| `TheSafecracker+Bezier.swift` | Cubic bezier curve sampling |
| `TheSafecracker+IOHIDEventBuilder.swift` | IOHIDEvent construction for touch injection |
| `SyntheticTouch.swift` | Three-layer touch pipeline: target → touch → event |
| `KeyboardBridge.swift` | `UIKeyboardImpl` private API wrapper |
| `ObjCRuntime.swift` | Typed ObjC runtime dispatch utility |
| `TheFingerprints.swift` | Visual tap/swipe overlay (passthrough window, DEBUG-only) |

## Boundaries

- Owned by TheBrains. Does NOT resolve element targets — receives coordinates, frames, and `UIScrollView`s from TheBrains after TheStash resolves them.
- Owns TheFingerprints (lazy) for visual feedback.
- No reference to TheStash or TheBurglar.

> Full dossiers: [`docs/dossiers/04-THESAFECRACKER.md`](../../../../docs/dossiers/04-THESAFECRACKER.md), [`docs/dossiers/03-THEFINGERPRINTS.md`](../../../../docs/dossiers/03-THEFINGERPRINTS.md)

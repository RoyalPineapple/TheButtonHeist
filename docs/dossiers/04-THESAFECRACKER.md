# TheSafecracker - The Specialist

> **Files:** `ButtonHeist/Sources/TheInsideJob/TheSafecracker*.swift`
> **Platform:** iOS 17.0+ (UIKit, private APIs)
> **Role:** Performs all physical interactions with the UI - touch injection, text input, gestures

## Responsibilities

TheSafecracker is the hands of the operation:

1. **Single-finger gestures** - tap, long press, swipe, drag
2. **Multi-finger gestures** - pinch, rotate, two-finger tap
3. **Path drawing** - polyline (drawPath) and Bezier curves (drawBezier)
4. **Text input** - typing via UIKeyboardImpl injection (KIF pattern)
5. **Keyboard management** - detect visibility, dismiss keyboard
6. **Accessibility actions** - activate, increment, decrement, custom actions
7. **Element resolution** - find UI elements by identifier/label/order from cache

## Architecture Diagram

```mermaid
graph TD
    subgraph TheSafecracker["TheSafecracker (@MainActor)"]
        Actions["TheSafecracker+Actions.swift - High-level executors"]
        Elements["TheSafecracker+Elements.swift - Element resolution"]
        TextEntry["TheSafecracker+TextEntry.swift - Text typing & deletion"]
        Core["TheSafecracker.swift - Touch primitives & text injection"]
    end

    subgraph PrivateAPIs["Private API Layers"]
        IOHID["IOHIDEventBuilder - dlsym-loaded IOKit"]
        TouchFactory["SyntheticTouchFactory - UITouch creation via IMP"]
        EventFactory["SyntheticEventFactory - UIEvent creation via private API"]
    end

    subgraph Support["Support"]
        Bezier["TheSafecracker.BezierSampler - Cubic bezier to polyline"]
        FP["Fingerprints - Visual feedback overlay"]
    end

    Actions --> Core
    Actions --> Elements
    Actions --> TextEntry
    Core --> IOHID
    Core --> TouchFactory
    Core --> EventFactory
    Actions --> Bezier
    Core --> FP
```

## Touch Injection Stack

```mermaid
flowchart TD
    subgraph Layer1["Layer 1: IOHIDEvent (IOKit)"]
        Hand["Create hand event - (kIOHIDDigitizerTransducerTypeHand)"]
        Finger["Create finger event(s) - (index, identity, position, pressure)"]
        Hand --> Finger
        Finger --> Append["IOHIDEventAppendEvent"]
    end

    subgraph Layer2["Layer 2: UITouch (Private UIKit)"]
        Create["UITouch() constructor"]
        Mutate["Set via IMP invocation: - window, view, location, - phase, tapCount, timestamp"]
        HID["_setHidEvent(IOHIDEvent)"]
        Create --> Mutate --> HID
    end

    subgraph Layer3["Layer 3: UIEvent (Private UIKit)"]
        GetEvent["UIApplication._touchesEvent"]
        Clear["_clearTouches"]
        AddTouch["_addTouch:forDelayedDelivery:"]
        SetHID["_setHIDEvent:"]
        Send["UIApplication.shared.sendEvent()"]
        GetEvent --> Clear --> AddTouch --> SetHID --> Send
    end

    Layer1 --> Layer2
    Layer2 --> Layer3
```

## Gesture Catalog

```mermaid
graph LR
    subgraph SingleFinger["Single Finger"]
        Tap["tap(at:)"]
        LongPress["longPress(at:duration:)"]
        Swipe["swipe(from:to:duration:)"]
        Drag["drag(from:to:duration:)"]
    end

    subgraph MultiFinger["Multi Finger"]
        Pinch["pinch(center:startDist:endDist:)"]
        Rotate["rotate(center:radius:startAngle:endAngle:)"]
        TwoTap["twoFingerTap(at:spread:)"]
    end

    subgraph Path["Path Drawing"]
        DrawPath["drawPath(points:duration:)"]
        DrawBezier["drawBezier via TheSafecracker.BezierSampler"]
    end

    subgraph Text["Text Input"]
        Type["typeText(interKeyDelay:)"]
        Delete["deleteText(count:)"]
        Edit["editAction (copy/paste/cut/select)"]
        Dismiss["resignFirstResponder()"]
    end

    subgraph AccessActions["Accessibility Actions"]
        Activate["activate (accessibilityActivate)"]
        Increment["increment (accessibilityIncrement)"]
        Decrement["decrement (accessibilityDecrement)"]
        Custom["performCustomAction(name:)"]
    end
```

## Element Resolution Flow

```mermaid
flowchart TD
    Target["ActionTarget - (identifier? / label? / order?)"]

    Target --> ByIdent{identifier provided?}
    ByIdent -->|yes| SearchIdent["Search elements by - accessibilityIdentifier"]
    ByIdent -->|no| ByLabel{label provided?}
    ByLabel -->|yes| SearchLabel["Search elements by - accessibilityLabel"]
    ByLabel -->|no| ByOrder{order provided?}
    ByOrder -->|yes| SearchOrder["Index into elements array"]
    ByOrder -->|no| Fail["elementNotFound"]

    SearchIdent --> Found{found?}
    SearchLabel --> Found
    SearchOrder --> Found

    Found -->|yes| WeakRef["Retrieve live UIView - from interactiveObjects[order]"]
    Found -->|no| Fail

    WeakRef --> Alive{still alive?}
    Alive -->|yes| UseElement["Return element + live object"]
    Alive -->|no| Dealloc["elementDeallocated"]
```

## Action Execution Pattern (Activate Example)

```mermaid
flowchart TD
    Start["executeActivate(target)"]
    Start --> Resolve["resolveElement(target)"]
    Resolve --> HasObj{has live object?}

    HasObj -->|yes| TryHigh["Try accessibilityActivate()"]
    TryHigh --> HighOk{returned true?}
    HighOk -->|yes| FP1["showFingerprint()"]
    FP1 --> Result1["InteractionResult - method: .activate"]

    HighOk -->|no| FallbackTap["Fallback: tap(at: activationPoint)"]
    FallbackTap --> FP2["showFingerprint()"]
    FP2 --> Result2["InteractionResult - method: .syntheticTap"]

    HasObj -->|no| DirectTap["Direct tap at coordinates"]
    DirectTap --> FP3["showFingerprint()"]
    FP3 --> Result3["InteractionResult - method: .syntheticTap"]
```

## Items Flagged for Review

### HIGH PRIORITY

**Private API usage via `unsafeBitCast`** (`TheSafecracker+SyntheticTouchFactory.swift:93,103,113,125`)
- All UITouch mutation uses `unsafeBitCast(imp, to: Fn.self)` to call private selectors
- The type cast is inherently unsafe if Apple changes a selector's signature
- Guards: `responds(to:)` checks protect against missing selectors but NOT against signature changes
- This is the established KIF pattern and is DEBUG-only, but should be monitored with each iOS release

**`SyntheticEventFactory` creates fresh UIEvent per phase** (`TheSafecracker+SyntheticEventFactory.swift`)
- iOS 26+ requires new UIEvent objects per touch phase (reusing causes validation errors)
- This was a targeted fix for a specific iOS version - needs verification on future versions

**IOHIDEventBuilder uses `dlsym`-loaded IOKit** (`TheSafecracker+IOHIDEventBuilder.swift`)
- All IOKit function pointers are loaded dynamically at first use
- If IOKit reorganizes or removes these symbols, touch injection silently fails
- The `guard` on dlsym returns nil-checks, but no runtime warning is logged on failure

### MEDIUM PRIORITY

**`InteractionResult: Error` conformance appears unused** (`TheSafecracker.swift:31`)
```swift
struct InteractionResult: Error { ... }
```
- `InteractionResult` is returned as a value, never thrown
- The `Error` conformance adds no functionality and may mislead readers

**Text injection depends on `UIKeyboardImpl.activeInstance`** (`TheSafecracker.swift:207`)
- Uses `NSClassFromString("UIKeyboardImpl")` and `perform(NSSelectorFromString("activeInstance"))`
- If the keyboard isn't visible, `activeInstance` returns nil
- `executeTypeText` has a multi-step flow: tap element, wait for keyboard, then type
- The keyboard visibility check looks for `UIInputSetHostView` with height > 100pt

**Duplicate default durations** (`TheSafecracker+Actions.swift` vs `TheSafecracker.swift`)
- `executeTap` at Actions:111 defaults duration via `target.duration ?? 0.15`
- `swipe(from:to:duration:)` at Core:79 has its own `duration: TimeInterval = 0.15`
- Defaults exist at both the high-level and primitive level independently

**`clampDuration` range** (`TheSafecracker+Actions.swift:255`)
```swift
private func clampDuration(_ value: TimeInterval) -> TimeInterval {
    min(max(value, 0.01), 60.0)
}
```
- 60-second max gesture duration seems generous
- No equivalent clamp on `interKeyDelay` for text typing

### LOW PRIORITY

**Fingerprint overlays shown for all gesture types**
- Every successful interaction calls `showFingerprint()` or `beginTrackingFingerprints()`
- This is intentional for recording visibility but adds visual noise during testing
- No configuration to disable fingerprints

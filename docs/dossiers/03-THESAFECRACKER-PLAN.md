# TheSafecracker - Performance Improvement Plan

## Summary

TheSafecracker should be pure fingers — touch injection, text input, keyboard management. Element resolution and live object access move to TheBagman (see InsideJob plan). TheSafecracker receives only screen coordinates and action outcomes, never live UIView pointers.

## Phase 1: Remove Element Resolution

**Goal:** TheSafecracker no longer resolves elements or holds references to live objects.

### What moves out:
- `TheSafecracker+Elements.swift` — entire file moves to TheBagman
- All `interactiveObjects` access — TheBagman handles this
- `resolveElement()`, `hasInteractiveObject()`, `customActionNames()` — all TheBagman

### What TheSafecracker receives instead:
- For activate/increment/decrement: TheBagman calls the accessibility API directly and returns success/failure. TheSafecracker only gets involved on fallback (synthetic tap at coordinates).
- For gestures: TheSafecracker receives `CGPoint` coordinates only
- For text: TheSafecracker receives the text string and keyboard target

### New interaction flow:
```
InsideJob → TheBagman.activate(target) → success? done
                                      → failure? → TheSafecracker.tap(at: activationPoint)
```

- [x] **Delete `TheSafecracker+Elements.swift`**
- [x] **Modify `TheSafecracker+Actions.swift`** — remove element resolution, receive coordinates
- [x] **Modify `InsideJob.swift`** — orchestrate TheBagman → TheSafecracker fallback
- [x] **Build passes** after phase

## Phase 2: Enforce Activation-First Philosophy

- [x] **Update `docs/API.md`** — document activation-first with synthetic tap fallback
- [x] **Document `tap` as low-level escape hatch**
- [x] **Add debug log** in `executeTap` noting fallback path

## Phase 3: Make TheSafecracker Fully Internal

- [x] **TheSafecracker class:** `internal` access level
- [x] **All methods:** `internal`
- [x] **Only InsideJob creates and holds** the instance
- [x] **Build passes** after phase

## Phase 4: Fix Medium Priority Items

- [x] **Remove `Error` conformance on `InteractionResult`** (`TheSafecracker.swift:31`)
- [x] **Remove duplicate default durations** — defaults in one place only
- [x] **Add `interKeyDelay` clamping** to match gesture duration clamping
- [x] **Review 60-second max gesture duration**

## Phase 5: Fix Low Priority Items

- [x] **Fingerprint disable configuration** — coordinate with TheFingerprints plan

## Phase 6: Private API Monitoring

- [x] **Add iOS version comment** to `SyntheticTouchFactory.swift`
- [x] **Add iOS version comment** to `IOHIDEventBuilder.swift`
- [x] **Add iOS version comment** to `SyntheticEventFactory.swift`

## Verification

- [x] `TheSafecracker+Elements.swift` deleted
- [x] TheSafecracker never imports or references `interactiveObjects`
- [x] All TheSafecracker types are `internal` access level
- [x] `InteractionResult` does not conform to `Error`
- [x] No duplicate default durations
- [x] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob -destination 'generic/platform=iOS' build`

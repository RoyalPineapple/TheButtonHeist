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

- [ ] **Delete `TheSafecracker+Elements.swift`**
- [ ] **Modify `TheSafecracker+Actions.swift`** — remove element resolution, receive coordinates
- [ ] **Modify `InsideJob.swift`** — orchestrate TheBagman → TheSafecracker fallback
- [ ] **Build passes** after phase

## Phase 2: Enforce Activation-First Philosophy

- [ ] **Update `docs/API.md`** — document activation-first with synthetic tap fallback
- [ ] **Document `tap` as low-level escape hatch**
- [ ] **Add debug log** in `executeTap` noting fallback path

## Phase 3: Make TheSafecracker Fully Internal

- [ ] **TheSafecracker class:** `internal` access level
- [ ] **All methods:** `internal`
- [ ] **Only InsideJob creates and holds** the instance
- [ ] **Build passes** after phase

## Phase 4: Fix Medium Priority Items

- [ ] **Remove `Error` conformance on `InteractionResult`** (`TheSafecracker.swift:31`)
- [ ] **Remove duplicate default durations** — defaults in one place only
- [ ] **Add `interKeyDelay` clamping** to match gesture duration clamping
- [ ] **Review 60-second max gesture duration**

## Phase 5: Fix Low Priority Items

- [ ] **Fingerprint disable configuration** — coordinate with TheFingerprints plan

## Phase 6: Private API Monitoring

- [ ] **Add iOS version comment** to `SyntheticTouchFactory.swift`
- [ ] **Add iOS version comment** to `IOHIDEventBuilder.swift`
- [ ] **Add iOS version comment** to `SyntheticEventFactory.swift`

## Verification

- [ ] `TheSafecracker+Elements.swift` deleted
- [ ] TheSafecracker never imports or references `interactiveObjects`
- [ ] All TheSafecracker types are `internal` access level
- [ ] `InteractionResult` does not conform to `Error`
- [ ] No duplicate default durations
- [ ] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob -destination 'generic/platform=iOS' build`

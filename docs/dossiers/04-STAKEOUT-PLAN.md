# Stakeout → TheStakeout - Performance Improvement Plan

## Summary

Rename to TheStakeout. Investigate eliminating fingerprint compositing. Fix the file size limit relationship. Minimize interaction log payloads.

## Phase 1: Rename to TheStakeout

- [x] **Rename class** from `Stakeout` to `TheStakeout`
- [x] **Update all references** in `InsideJob.swift`, `InsideJob+Screen.swift`, etc.
- [x] **Update dossier and documentation references**
- [x] **Build passes** after phase

## Phase 2: Eliminate Fingerprint Compositing

**Goal:** Instead of drawing fingerprint circles into video frames via CGContext, rely on TheFingerprints keeping indicators on-screen long enough for frame capture to catch them naturally.

### Prerequisite: TheFingerprints guarantees minimum 0.5s display time (Batch 2)

- [x] **Remove CGContext fingerprint drawing** from `createPixelBuffer(from:)`
- [x] **Remove `activeInteractions` tracking array**
- [x] **Remove `interactionOverlayDuration` and `overlayDiameter` constants**
- [x] **Verify bonus frame after interaction** still captures the fingerprint indicator
- [x] **Build passes** after phase

### Alternative approach (if natural capture is insufficient):
- TheFingerprints signals TheStakeout "ready for picture" after placing indicators
- TheStakeout captures an extra frame on signal
- Still no compositing — just better timing coordination

## Phase 3: File Size Limit — Keep As-Is

**Decision:** Keep the 7MB cap as a safety net. No changes needed.

Real-world data: largest recording 802KB (34.5s), typical 200-400KB. H.264 at ~10-23 KB/sec for UI content. The 7MB cap will never be hit in practice.

- [x] **No code changes needed** — documented decision

## Phase 4: Minimize Interaction Log Payloads

- [x] **Replace `interfaceBefore`/`interfaceAfter` with `interfaceDelta: InterfaceDelta`** in `InteractionEvent`
- [x] **Add max interaction count** (e.g., 500 events) with truncation note
- [x] **Update `InsideJob.swift`** — pass delta instead of full snapshots
- [x] **Update `RecordingPayloadTests.swift`**
- [x] **Build passes** after phase

### Files affected:
- `ServerMessages.swift` — modify `InteractionEvent` to use `InterfaceDelta`
- `InsideJob.swift` — adjust `performInteraction` to pass delta
- `Stakeout.swift` — add max event count guard
- `RecordingPayloadTests.swift` — update tests

## Phase 5: Address High Priority Lint Issues

- [x] **Remove `swiftlint:disable file_length`** — after compositing removal, file should be shorter (387 lines)
- [x] **If still over limit**, extract AVAssetWriter pipeline into a helper type — not needed, well under 600

## Phase 6: Address Medium Priority Items

- [x] **Document inactivity detection** behavior — screen hashing means subtle animations keep recording active (intentional)
- [x] **Document even-dimension rounding** H.264 requirement in code comment
- [ ] **Consider sending recording only to initiating client** — requires tracking which client started

## Verification

- [x] Class renamed to `TheStakeout` throughout codebase
- [x] No CGContext fingerprint compositing in frame capture
- [x] `swiftlint:disable file_length` removed
- [x] File size limit documented alongside `maxBufferSize`
- [x] `InteractionEvent` uses `InterfaceDelta` not full `Interface`
- [x] Interaction log has a max event count
- [x] Build passes: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob -destination 'generic/platform=iOS' build`

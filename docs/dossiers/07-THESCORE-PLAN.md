# TheScore - Performance Improvement Plan

## Summary

Audit all wire types for efficiency. Fix the `InteractionEvent` to use diffs. Fix the `ElementAction` codable edge case. Update test coverage for `ActionMethod`.

## Phase 1: Audit Wire Types

**Goal:** Review every type in TheScore for transmission efficiency and structural clarity.

- [ ] **`HeistElement`** — are all fields needed on every transmission? Could traits/hint/customContent be optional?
- [ ] **`Interface`** — does the optional `tree` add value when `elements` is always present?
- [ ] **`ActionResult`** — is the `animating` flag used?
- [ ] **`ScreenPayload`** — could we offer JPEG for smaller payloads?
- [ ] **`RecordingPayload`** — see Phase 2
- [ ] **`ServerInfo`** — review which fields are actually used
- [ ] **Audit complete, findings documented**

### Files affected:
- All files in `ButtonHeist/Sources/TheScore/`
- This is a review/analysis phase — code changes depend on findings

## Phase 2: Fix InteractionEvent to Use Diffs

**Per Stakeout plan:** Replace full `Interface` snapshots with `InterfaceDelta`.

- [x] **Simplify `InteractionEvent`** — remove `interfaceBefore`/`interfaceAfter`, rely on `result.interfaceDelta`
- [x] **Update `ServerMessages.swift`**
- [x] **Update `RecordingPayloadTests.swift`**
- [x] **Build passes** after phase

## Phase 3: Fix ElementAction Codable Edge Case

**Bug:** A custom action named `"activate"` decodes as built-in `.activate`.

- [x] **Fix Codable implementation** — use tagged encoding for custom actions ({"custom":"name"})
- [x] **Update `Elements.swift`**
- [x] **Build passes** after phase

## Phase 4: Fix ActionMethod Test Coverage

- [x] **Add `.typeText` test case**
- [x] **Add `.editAction` test case**
- [x] **Add `.resignFirstResponder` test case**
- [x] **Add `.waitForIdle` test case**
- [x] **Tests pass** (pre-existing SPM build issue in SimpleSocketServer.swift prevents `swift test`; xcodebuild schemes all pass)

### Files affected:
- `ButtonHeistCLI/Tests/ActionCommandTests.swift`

## Phase 5: Update Documentation

- [x] **`docs/API.md:81`** — remove non-existent `port` parameter from `configure()`
- [x] **`docs/API.md:70`** — fix `isRunning` visibility (private, not public)
- [x] **`docs/WIRE-PROTOCOL.md:1127`** — remove `INSIDEJOB_BIND_ALL` documentation
- [x] **`docs/WIRE-PROTOCOL.md:1014`** — fix token persistence claim (ephemeral) — already fixed in Batch 2A
- [x] **`docs/WIRE-PROTOCOL.md:1141`** — fix ping interval (3s, not 30s) — already fixed in Batch 5

## Phase 6: Protocol Version

No changes needed. Current string version `"3.1"` is fine.

## Verification

- [x] `InteractionEvent` no longer contains full `Interface` snapshots
- [x] `ElementAction` edge case documented or fixed
- [x] All `ActionMethod` cases tested
- [x] API.md and WIRE-PROTOCOL.md match implementation
- [x] Tests pass: `xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScoreTests test`

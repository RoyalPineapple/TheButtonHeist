# TheStash

Single-snapshot screen state, target resolution, wire conversion, and screen capture. No persistent element registry — every parse replaces `currentScreen` wholesale. Exploration accumulates per-page parses into a local union in TheBrains+Exploration and commits the union back as the known semantic snapshot.

## Reading order

1. **`Screen.swift`** — The value type. Fields: `elements: [String: ScreenElement]`, `hierarchy: [AccessibilityHierarchy]`, `containerStableIds: [AccessibilityContainer: String]`, `heistIdByElement: [AccessibilityElement: String]`, `firstResponderHeistId: String?`, `scrollableContainerViews: [ScrollableViewRef]`. Pure value semantics: `.empty` constructor, `merging(_:)` returns a new Screen (last-read-wins — no field-level preservation), `findElement(heistId:)` is O(1), `name`/`id`/`heistIds` are derived. `Equatable`.

2. **`TheStash.swift`** — The `@MainActor final class`. Single mutable field: `var currentScreen: Screen` (plus `lastHierarchyHash` for broadcast tracking and `stakeout` weak back-ref).

   - `ScreenElement` — one tracked element: `heistId`, `contentSpaceOrigin`, `element`, `weak var object`, `weak var scrollView`.
   - `TargetResolution` — three cases: `.resolved(ResolvedTarget)`, `.notFound(diagnostics:)`, `.ambiguous(candidates:, diagnostics:)`.

   **Resolution:** `resolveTarget(_:)` switches on `ElementTarget`:
   - `.heistId` → O(1) dictionary lookup in `currentScreen.elements`.
   - `.matcher` → `resolveMatcher` calls `matchScreenElements(matcher, limit:)`. With ordinal: returns element at index. Without: requires unique match — 0 hits = `.notFound`, 2+ = `.ambiguous` with up to 10 candidates listed.

   **Parse pipeline facades** (delegate to private `TheBurglar`):
   - `refresh()` → `parse()` + `currentScreen = buildScreen(from:)` in one step.
   - `parse()` → read-only, returns `ParseResult`.
   - `buildScreen(from:)` → returns a `Screen` value, does NOT mutate `currentScreen`. Callers decide when to commit.

   **Tree read helpers** — `wireTree()` and `wireTreeHash()` compute the wire tree of `currentScreen` via `WireConversion.toWireTree(from:)`. They are not facades — they read state. Element-level wire conversion (`WireConversion.toWire`, `WireConversion.traitNames`) and delta computation (`InterfaceDiff.computeDelta`) are pure transforms; callers invoke them directly.

   **`selectElements()`** — returns live hierarchy elements in traversal order, then known-only elements (from the post-explore union) sorted by heistId. Deterministic across runs.

3. **`IdAssignment.swift`** — Pure static namespace. `assign(_:)` generates heistIds in two phases: base ID (developer identifier if stable, else synthesized from trait+label), then suffix disambiguation (`_1`, `_2`, ... for all instances of a duplicate). `synthesizeBaseId` picks from a ranked trait list (`backButton` → `tabBarItem` → `searchField` → `textEntry` → `switchButton` → `adjustable` → `header` → `button` → `link` → `image` → `tabBar`) and slugifies the label. Value is excluded for stability. **Wire-format-stable** — agents rely on synthesis being predictable, do not change without a major version bump.

4. **`WireConversion.swift`** — Pure static namespace (caseless `@MainActor enum`). `convert(_:)` and `toWire(_:)` map `AccessibilityElement` / `Screen.ScreenElement` → `HeistElement` (sanitizes NaN/infinity in frames). `toWireTree(from:)` walks a `Screen`'s hierarchy + `containerStableIds` + `heistIdByElement` to emit the canonical wire tree. `traitNames(_:)` maps a `UIAccessibilityTraits` bitmask to `[HeistTrait]`. No delta logic — see `InterfaceDiff`.

4a. **`InterfaceDiff.swift`** — Pure static namespace (caseless `@MainActor enum`). `computeDelta(before:after:beforeTree:beforeTreeHash:afterTree:isScreenChange:)` has three paths: screen changed → full new `Interface`; fast no-change check via hierarchy hash + tree-edit fallback; something changed → lift to wire via `WireConversion.toWire`, then `computeElementEdits` + `computeTreeEdits` (with functional-move pairing inference to collapse churn that's really a move). Owns the four delta-internal types: `WireTreeRecord`, `ElementIdentitySignature`, `ElementStateSignature`, `ElementPairingSignature`.

5. **`TheStash+Matching.swift`** — `matchScreenElements(matcher, limit:)` walks `selectElements()` so matchers see the committed semantic state, not just the live viewport. **Exact-or-miss**: `AccessibilityElement.matches(_:mode:)` defers to `ElementMatcher.stringEquals` (TheScore) for byte-for-byte server/client equivalence: case-insensitive equality with typography folding. Unknown trait names fail-safe to a miss. `MatchMode.substring` is reserved for `Diagnostics.findNearMiss`; resolution itself never uses substring.

6. **`Diagnostics.swift`** — Pure static namespace. `heistIdNotFound` finds similar IDs by bidirectional substring check across `currentScreen.elements`. `matcherNotFound` tries relaxations in order (drop value → traits → label → identifier), checking each against `selectElements()` so suggestions use the same candidate scope as matcher resolution, then falls back to a compact known-element summary.

7. **`Interactivity.swift`** — `isInteractive(element:)` checks three conditions: `respondsToUserInteraction`, interactive trait bitmask, or has custom actions. `checkInteractivity` also checks `.notEnabled` for blocking and surfaces an advisory `warning` when an element has only static traits.

8. **`TheStash+Capture.swift`** — `captureScreen()` composites all traversable windows via `UIGraphicsImageRenderer`. `captureScreenForRecording()` includes the TheFingerprints overlay.

9. **`ArrayHelpers.swift`** — `screenName`/`screenId` computed properties on `[HeistElement]` and `[ScreenElement]`.

## Exploration discipline

`TheBrains+Exploration.exploreAndPrune` owns the union accumulator as a local `var union: Screen`. Each scroll page calls `stash.refresh()` (commits page-only state for termination heuristics), then `union = union.merging(stash.currentScreen)`. After all pages, `stash.currentScreen = union` commits the known semantic tree. No mode flag, no inExploreCycle state.

> Full dossier: [`docs/dossiers/11-THESTASH.md`](../../../../docs/dossiers/11-THESTASH.md)

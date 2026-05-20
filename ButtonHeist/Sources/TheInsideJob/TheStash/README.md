# TheStash

Single-screen state, target resolution, wire conversion, and screen capture. TheStash owns exactly one mutable accessibility belief: the committed `Screen`, which contains targetable known elements plus the latest live interface. No persistent element registry — every parse replaces `currentScreen` wholesale. Container IDs, heistIds, and live refs are current-screen projections, not durable authority. Exploration accumulates per-page parses into a local union in TheBrains+Exploration and commits the union back as the known semantic screen.

## Reading order

1. **`Screen.swift`** — The value type. Fields: `elements: [String: ScreenElement]` for known semantic state and `liveInterface: LiveInterface` for the latest parser tree, live refs, and indexes. Pure value semantics: `.empty` constructor, `visibleOnly` filters to the latest live interface, `orderedElements` returns deterministic matcher order, `merging(_:)` returns a new Screen (last-read-wins — no field-level preservation), `findElement(heistId:)` is O(1), `name`/`id`/`heistIds` are derived. `Equatable`.

2. **`TheStash.swift`** — The `@MainActor final class`. Single mutable accessibility field: `var currentScreen: Screen`. Broadcast memory lives in TheBrains; recording references and pending rotor continuation are boundary state, not accessibility belief.

   - `ScreenElement` — one tracked element: `heistId`, `contentSpaceOrigin`, `element`, `weak var object`, `weak var scrollView`.
   - `TargetResolution` — three cases: `.resolved(ResolvedTarget)`, `.notFound(diagnostics:)`, `.ambiguous(candidates:, diagnostics:)`.

   **Resolution:** `resolveTarget(_:)` switches on `ElementTarget`:
   - `.heistId` → O(1) dictionary lookup in `currentScreen.elements`.
   - `.matcher` → `resolveMatcher` calls `matchScreenElements(matcher, limit:)`. With ordinal: returns element at index. Without: requires unique match — 0 hits = `.notFound`, 2+ = `.ambiguous` with up to 10 candidates listed.

   **Parse pipeline facades** (delegate to private `TheBurglar`):
   - `refresh()` → `parse()` + `currentScreen = screen` in one step.
   - `parse()` → read-only, returns a `Screen` value and does NOT mutate `currentScreen`. Callers decide when to commit.
   - `TheBurglar.buildScreen(from:)` → pure parse-result-to-`Screen` conversion.

   **Interface read helpers** — `interface()` and `interfaceHash()` expose the current parser hierarchy plus Button Heist annotations. They are not facades — they read state. Element-level wire conversion (`WireConversion.toWire`, `WireConversion.traitNames`) is a pure transform. Delta emission projects from `AccessibilityTrace` captures.

   **`selectElements()`** — thin facade over `Screen.orderedElements`: live hierarchy elements in traversal order, then known-only elements (from the post-explore union) sorted by heistId. Deterministic across runs.

3. **`IdAssignment.swift`** — Pure static namespace. `assign(_:)` generates heistIds in two phases: base ID (developer identifier if stable, else synthesized from trait+label), then suffix disambiguation (`_1`, `_2`, ... for all instances of a duplicate). `synthesizeBaseId` picks from a ranked trait list (`backButton` → `tabBarItem` → `searchField` → `textEntry` → `switchButton` → `adjustable` → `header` → `button` → `link` → `image` → `tabBar`) and slugifies the label. Value is excluded for stability. **Wire-format-stable for current payloads** — replay persists minimum matchers, not heistIds.

4. **`WireConversion.swift`** — Pure static namespace (caseless `@MainActor enum`). `convert(_:)` and `toWire(_:)` map `AccessibilityElement` / `Screen.ScreenElement` → `HeistElement` (sanitizes NaN/infinity in frames). `toInterface(from:)` packages a `Screen`'s parser hierarchy + projected `containerStableIds` + `heistIdByElement` as the canonical interface. `traitNames(_:)` maps an `AccessibilityTraits` bitmask to `[HeistTrait]`; the UIKit overload is only a boundary adapter. No delta logic — deltas are capture-derived in TheScore.

5. **`TheStash+Matching.swift`** — `matchScreenElements(matcher, limit:)` walks `selectElements()` so matchers see the committed semantic state, not just the latest live interface. **Exact-or-miss**: `AccessibilityElement.matches(_:mode:)` defers to `ElementMatcher.stringEquals` (TheScore) for byte-for-byte server/client equivalence: case-insensitive equality with typography folding. Unknown trait names fail-safe to a miss. `MatchMode.substring` is reserved for `Diagnostics.findNearMiss`; resolution itself never uses substring.

6. **`Diagnostics.swift`** — Pure static namespace. `heistIdNotFound` finds similar IDs by bidirectional substring check across `currentScreen.elements`. `matcherNotFound` tries relaxations in order (drop value → traits → label → identifier), checking each against `selectElements()` so suggestions use the same candidate scope as matcher resolution, then falls back to a compact known-element summary.

7. **`Interactivity.swift`** — `isInteractive(element:)` checks three conditions: `respondsToUserInteraction`, interactive trait bitmask, or has custom actions. `checkInteractivity` also checks `.notEnabled` for blocking and surfaces an advisory `warning` when an element has only static traits.

8. **`TheStash+Capture.swift`** — `captureScreen()` composites all traversable windows via `UIGraphicsImageRenderer`. `captureScreenForRecording()` includes the TheFingerprints overlay.

9. **`ArrayHelpers.swift`** — `screenName`/`screenId` computed properties on `[HeistElement]` and `[ScreenElement]`.

## Exploration discipline

`TheBrains+Exploration.exploreAndPrune` owns the union accumulator as a local `var union: Screen`. Each scroll page calls `stash.refresh()` (commits page-only state for termination heuristics), then `union = union.merging(stash.currentScreen)`. After all pages, `stash.currentScreen = union` commits the known semantic tree. No mode flag, no inExploreCycle state.

> Full dossier: [`docs/dossiers/11-THESTASH.md`](../../../../docs/dossiers/11-THESTASH.md)

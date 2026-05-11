# TheStash

Element registry, target resolution, wire conversion, and screen capture.

## Reading order

1. **`TheStash.swift`** — The `@MainActor final class`. Key nested types:

   - `ScreenElement` — one tracked element: `heistId`, `contentSpaceOrigin` (scroll-space position, set at creation, never updated), `element` (refreshed each cycle), `weak var object` (nils on cell reuse), `weak var scrollView`.
   - `TargetResolution` — three cases: `.resolved(ResolvedTarget)`, `.notFound(diagnostics:)`, `.ambiguous(candidates:, diagnostics:)`.

   **Resolution:** `resolveTarget(_:)` switches on `ElementTarget`:
   - `.heistId` → O(1) dictionary lookup in `registry.elements`.
   - `.matcher` → `resolveMatcher` calls `matchScreenElements(matcher, limit:)`. With ordinal: returns element at index. Without: requires unique match — 0 hits = `.notFound`, 2+ = `.ambiguous` with up to 10 candidates listed.

   **Parse pipeline facades** (delegate to private `TheBurglar`):
   - `refresh()` → parse + apply in one step
   - `parse()` → read-only, returns `ParseResult` (typealias hiding TheBurglar)
   - `apply(_:)` → mutates registry, returns assigned heistIds

   **Wire conversion facades** (delegate to `WireConversion`):
   - `toWire(_:)`, `convertTree(_:)`, `computeDelta(before:after:afterTree:isScreenChange:)`, `traitNames(_:)`

   **`selectElements()`** — sorts `registry.elements.values` by traversal order from `buildTraversalOrderIndex()` (walks `currentHierarchy`, maps elements to heistIds via `registry.reverseIndex`). Off-screen elements get `Int.max`.

2. **`ElementRegistry.swift`** — Struct with four fields: `elements: [String: ScreenElement]` (persistent), `viewportIds: Set<String>` (rebuilt each refresh), `firstResponderHeistId: String?`, `reverseIndex: [AccessibilityElement: String]`. `apply(parsedElements:heistIds:contexts:)` upserts — existing elements get updated `element`/`object`/`scrollView`; new ones are created with `contentSpaceOrigin` from the context. `prune(keeping:)` filters `elements` to a set of heistIds (post-explore cleanup).

3. **`IdAssignment.swift`** — Pure static namespace. `assign(_:)` generates heistIds in two phases: base ID (developer identifier if stable, else synthesized from trait+label), then suffix disambiguation (`_1`, `_2`, ... for all instances of a duplicate). `synthesizeBaseId` picks from a ranked trait list (`backButton` → `tabBarItem` → `searchField` → `textEntry` → `switchButton` → `adjustable` → `header` → `button` → `link` → `image` → `tabBar`) and slugifies the label. Value is excluded for stability.

4. **`WireConversion.swift`** — Pure static namespace. `convert(_:)` maps `AccessibilityElement` → `HeistElement` (sanitizes NaN/infinity in frames for UIPickerView). `computeDelta` has three paths: screen changed → full new `Interface`; fast no-change check on internal types without wire conversion (the hot path for Pulse); something changed → full wire conversion + `computeElementDelta` (groups by heistId, compares 8 properties).

5. **`TheStash+Matching.swift`** — `matchScreenElements(matcher, limit:)` is hierarchy-first, registry-fallback, **exact-or-miss**. First walks `currentHierarchy` via early-exit `compactMap(first:)`, maps hits through `reverseIndex` to heistIds. If no hierarchy hits, falls back to iterating the full `registry.elements` (catches off-screen explored elements). `AccessibilityElement.matches(_:mode:)` defers to `ElementMatcher.stringEquals` (TheScore) so client-side `HeistElement.matches` and server-side comparison are byte-for-byte equivalent: case-insensitive equality with typography folding (smart quotes/dashes/ellipsis fold to ASCII; emoji, accents, CJK pass through). Unknown trait names are validated against `knownTraitNames` and fail-safe to a miss. `MatchMode.substring` is reserved for the diagnostic suggestion path in `Diagnostics.findNearMiss`; resolution itself never uses substring.

6. **`Diagnostics.swift`** — Pure static namespace. `heistIdNotFound` finds similar IDs by bidirectional substring check. `matcherNotFound` tries relaxations in order (drop value → traits → label → identifier), checking each against the hierarchy. Falls back to a compact element summary (up to 20 on-screen elements).

7. **`Interactivity.swift`** — `isInteractive(element:)` checks three conditions: `respondsToUserInteraction`, interactive trait bitmask (button/link/adjustable/searchField/keyboardKey/backButton/switchButton), or has custom actions. `checkInteractivity` also checks `.notEnabled` for blocking and surfaces an advisory `warning` on `.interactive` when an element has only static traits — the caller decides whether to log it.

8. **`TheStash+Capture.swift`** — `captureScreen()` composites all traversable windows via `UIGraphicsImageRenderer` (bottom-to-top, `afterScreenUpdates: true`). `captureScreenForRecording()` includes all windows including TheFingerprints overlay (`afterScreenUpdates: false`).

9. **`ArrayHelpers.swift`** — `screenName`/`screenId` computed properties on `[HeistElement]` and `[ScreenElement]` (first header element's label and its slug).

> Full dossier: [`docs/dossiers/11-THESTASH.md`](../../../../docs/dossiers/11-THESTASH.md)

# WireConversion structure audit

Scope: `ButtonHeist/Sources/TheInsideJob/TheStash/WireConversion.swift` (653 LOC).
Date: 2026-05-12.
Audit-only — no source changes.

## TL;DR

**Decompose, but only two-way: split the delta computation out of `WireConversion`. Do not split the tree walker.**

The file looks like three concerns from the outside (element wire, tree wire, delta), but the call graph only supports a clean two-way split:

- **Wire conversion** (per-element + tree): ~170 LOC. Tightly coupled — the tree walker is a 56-line case dispatch that calls per-element conversion. Splitting these would just relocate a switch statement away from its leaves.
- **Delta computation**: ~480 LOC. Cleanly separable. Its only dependency on wire conversion is calling `toWire` to lift internal types to wire form before diffing.

Recommended carve-up:

| New file | LOC | Owns |
|---|---|---|
| `TheStash/WireConversion.swift` (slimmed) | ~180 | `traitNames`, `convert`, `buildActions`, `toWire`, `toWireTree`, `convertNode`, `toContainerInfo`, `sanitizedForJSON` extension |
| `TheStash/InterfaceDiff.swift` (new) | ~480 | `computeDelta`, all element + tree edit computation, functional-move pairing inference, `WireTreeRecord`, three signature types, `buildElementUpdate`, `compare`, tree-order helpers |

Both stay as `@MainActor enum` namespaces (no state currently, matches existing pattern). Stay in `TheStash/` directory — same flat-file pattern PR #373 used for the TheBrains decomposition. The `WireConversion` enum is no longer nested inside an `extension TheStash`; the new `InterfaceDiff` enum lives at file scope in the same module.

Net LOC change: ~zero (small shared-import boilerplate added; one ~480-line chunk moves wholesale). The win is **change locality**: edits to the delta algorithm (the bulk of past commits, e.g. #337, #326) no longer scroll past 170 lines of unrelated element/tree conversion, and the trait-policy edits (#371) no longer touch the same file as tree-edit ordering.

## Audit question 1: Is decomposition warranted?

### How tangled are the three "apparent" concerns?

Three apparent concerns:
1. **Element wire** — `traitNames`, `convert`, `buildActions` and the `sanitizedForJSON` extension on `CGFloat`.
2. **Tree walking** — `toWire(_:)` overloads, `toWireTree(from:)`, `convertNode`, `toContainerInfo`.
3. **Delta** — `computeDelta` and its private helpers, plus `WireTreeRecord`, `ElementIdentitySignature`, `ElementStateSignature`, `ElementPairingSignature`, `buildElementUpdate`, the four tree-order helpers, `indexTree`/`collectTreeRecords`/`treeRef`.

Actual coupling (verified by reading the call graph):

- (1) ↔ (2): **fused**. `convertNode` is a 16-line `switch` that calls `toWire(_:)` for elements with heistIds, falls back to `convert(_:)` for ones without, and builds container info via `toContainerInfo`. There is no meaningful seam — the tree walker exists to invoke per-element conversion at the right tree positions. Splitting these would put a 4-case switch in one file and the 3 functions it dispatches to in another, requiring all of them to remain part of the same public surface.
- (1) → (3): one-way dependency. `computeDelta` calls `toWire(_:)` to lift `[ScreenElement]` to `[HeistElement]` before diffing. After that lift, the delta layer never reaches back into per-element conversion.
- (2) → (3): one-way dependency by *type only*. `WireTreeRecord` (delta-internal) wraps `InterfaceNode` (built by the tree walker). The delta layer never calls the tree walker; it consumes pre-built `[InterfaceNode]` arrays as parameters.

The three concerns form a chain (element → tree → delta) where each layer consumes the previous layer's output. Concerns 1 and 2 share leaf utilities and switch dispatch; concern 3 reads upstream outputs but is otherwise self-contained.

### Would splitting reduce total LOC?

Approximate splits, including the file-level boilerplate each new file would need (UIKit / DEBUG guards, three imports, MARK headers):

- Slimmed `WireConversion.swift`: ~180 LOC (was 653).
- New `InterfaceDiff.swift`: ~480 LOC.
- **Net change**: roughly +15-25 LOC of duplicated `#if canImport(UIKit) / #if DEBUG / import` boilerplate plus the namespace declaration. **No real LOC win**, but no real LOC loss either.

This is **not** an "unvibe" net-LOC-reduction win. The justification is purely change-locality, not size. That is acceptable here because:

- The audit explicitly named WireConversion as the second-largest file in the resolution-layer audit (after the now-decomposed TheBrains).
- Past commits show the delta logic and the wire-conversion logic do not co-vary (see next subsection).

### How often do the three concerns change together?

Notable historical commits touching this file (via `git log --follow`):

| Commit | What changed | Element wire | Tree wire | Delta |
|---|---|---|---|---|
| #371 trait policy consolidation | reads `AccessibilityPolicy.transientTraits` | yes (via `traitNames`) | no | yes (`identitySignature`/`stateSignature`) |
| #370 Screen value type | `toWireTree(from: screen)` signature, `convertNode` reads `screen.heistIdByElement` | no | yes | no |
| #337 InterfaceDelta state machine | `InterfaceDelta` cases reshape | no | no | yes |
| #326 persistent registry tree | introduced tree-on-the-wire, full delta rewrite | no | yes | yes (heavy) |
| #292 file structure standardization | reorganization | yes | yes | yes |
| #339 vibe-code cleanup | cross-cutting | yes | yes | yes |

The **only commits that touched all three concerns simultaneously are mechanical cleanups** (#292, #339). The interesting feature commits cleanly localize:

- Trait policy work touches per-element conversion AND the identity/state signatures inside delta — but the signatures are delta-internal and don't need to live next to `traitNames`. Both sites consume the same `AccessibilityPolicy.transientTraits`; they don't need file co-location to stay in sync (the policy module already enforces that).
- Tree-shape work (#326, #370) touches tree wire and delta — these are the two concerns that share types (`InterfaceNode`, `TreeLocation`). They do not need to share a file because the contract is the type, not the implementation.

**Verdict:** decomposition is warranted between (1+2) and (3). Splitting (1) from (2) is not.

## Audit question 2: If yes, what's the carve-up?

### Type names

Recommendation: **`WireConversion`** (slimmed) + **`InterfaceDiff`** (new).

Rationale for "InterfaceDiff" over the brief's candidates (`WireDeltaComputer`, `DeltaWire`):

- The wire type produced is `InterfaceDelta`, not "WireDelta". Naming the producer `InterfaceDiff` keeps the producer/output pair short and parallel: `InterfaceDiff.computeDelta(...) -> InterfaceDelta`.
- "WireDeltaComputer" / "WireDeltaCalculator" is the JavaBeansy name. The codebase prefers nouns-as-namespaces (`WireConversion`, `IdAssignment`, `Interactivity`, `AccessibilityPolicy`) over `*Computer` / `*Builder` / `*Service`.
- Avoids the trap of three suffix-stuttered names (`WireElement` / `WireTree` / `WireDelta`) that imply a deeper taxonomy than exists. There are only two coherent pieces.

The brief proposed crew-metaphor avoidance — both names already comply (neither is a heist persona).

### Layer

`ButtonHeist/Sources/TheInsideJob/TheStash/InterfaceDiff.swift` — same directory as `WireConversion.swift`. **No new subdirectories.** This matches the TheBrains pattern from PR #373: `Actions.swift` and `Navigation*.swift` live flat in `TheBrains/`, not in a `TheBrains/Actions/` subfolder.

### State

Both stay as `@MainActor enum` (caseless namespace, all static methods), same as `WireConversion` today. The brief asked whether to migrate to `final class` — answer: no.

PR #373 chose `final class` for `Actions` and `Navigation` because those types **hold dependencies** (`stash`, `safecracker`, `tripwire`, `navigation`) injected at construction. `WireConversion` and the proposed `InterfaceDiff` are pure transforms with **no dependencies and no state**. A class with no stored properties would just be a namespace with extra ceremony — `enum` is the established pattern in `TheStash/` (`IdAssignment`, `Interactivity`, `Diagnostics`, `AccessibilityPolicy` all do this) and there is no reason to deviate.

The `@MainActor` annotation on both is currently load-bearing for `UIAccessibilityTraits` access in `traitNames` and for the `AccessibilityElement` / `AccessibilityContainer` types in tree walking. The `agent_main_actor_value_type` suppression comment already on `WireConversion` carries over.

### Caller mapping

Every production call site to `WireConversion` (excluding tests):

| Caller | Call | Cluster |
|---|---|---|
| `TheStash.swift:466` `toWire([ScreenElement])` facade | `WireConversion.toWire(entries)` | element/tree |
| `TheStash.swift:470` `toWire(ScreenElement)` facade | `WireConversion.toWire(entry)` | element/tree |
| `TheStash.swift:477` `wireTree()` facade | `WireConversion.toWireTree(from: currentScreen)` | element/tree |
| `TheStash.swift:492` `computeDelta(...)` facade | `WireConversion.computeDelta(...)` | delta |
| `TheStash.swift:502` `traitNames(_:)` facade | `WireConversion.traitNames(traits)` | element/tree |
| `TheBrains.swift:220` transient enrichment | `TheStash.WireConversion.convert($0)` | element/tree |

Of six production call sites, five map to the slimmed `WireConversion` and one maps to `InterfaceDiff`. **No caller spans both subsystems.**

Test callers (`ButtonHeistTests/WireConversionTests.swift`) split the same way: the `traitNames` / `convert` / `toWire` tests stay on `WireConversion`; the `computeDelta` tests (the bulk of that file) move to a `InterfaceDiffTests.swift` companion or stay as-is with two updated imports. The test file itself is large enough to also warrant a split, but that is out of scope for this audit and should follow the source split, not lead it.

The one production caller worth flagging: `TheBrains.swift:220` uses the fully-qualified `TheStash.WireConversion.convert(...)` — this is the only out-of-module access today and depends on `WireConversion` being declared as a nested type of `TheStash`. After decomposition, this site becomes `TheStash.WireConversion.convert(...)` unchanged if `WireConversion` stays nested, or `WireConversion.convert(...)` (file-scope) if it's pulled out of the `extension TheStash` wrapper. I recommend **pulling both out of `extension TheStash`** to match the flat-file pattern of `IdAssignment`, `Interactivity`, `Diagnostics`, and `AccessibilityPolicy` — none of those are nested in `TheStash`, and there's no reason `WireConversion` should be either. This is a separate touchup that can happen in the same PR as the carve-up. The TheBrains call site updates from `TheStash.WireConversion.convert(...)` to `WireConversion.convert(...)`.

### Cluster contents (proposed final shape)

**`TheStash/WireConversion.swift`** (~180 LOC):
- `extension CGFloat { var sanitizedForJSON: CGFloat }`
- `enum WireConversion`
  - `traitNames(_: UIAccessibilityTraits) -> [HeistTrait]`
  - `convert(_: AccessibilityElement) -> HeistElement`
  - `buildActions(for: AccessibilityElement) -> [ElementAction]`
  - `toWire(_: ScreenElement) -> HeistElement`
  - `toWire(_: [ScreenElement]) -> [HeistElement]`
  - `toWireTree(from: Screen) -> [InterfaceNode]`
  - private `convertNode(_: AccessibilityHierarchy, screen: Screen) -> InterfaceNode`
  - private `toContainerInfo(_: AccessibilityContainer, stableId: String?) -> ContainerInfo`

**`TheStash/InterfaceDiff.swift`** (~480 LOC):
- private structs `WireTreeRecord`, `ElementIdentitySignature`, `ElementStateSignature`, `ElementPairingSignature`
- `enum InterfaceDiff`
  - `computeDelta(before:after:beforeTree:beforeTreeHash:afterTree:isScreenChange:) -> InterfaceDelta`
  - private `makeDelta`, `computeElementEdits`, `computeTreeEdits`, `suppressFunctionalMoveElementChurn`
  - private `inferFunctionalTreePairs`, `inferFunctionalHeistElementPairs`, `inferFunctionalTreeRecordPairs`, `inferFunctionalPairs`
  - private `pairingSignature` (two overloads), `identitySignature`, `stateSignature`
  - private `firstNonEmpty`, `normalizedTraits`
  - private `indexTree`, `collectTreeRecords`, `treeRef`
  - private `treeInsertionOrder`, `treeRemovalOrder`, `treeMoveOrder`, `compare`
  - private `buildElementUpdate`

Cross-cluster reference: `InterfaceDiff.computeDelta` calls `WireConversion.toWire(_:)`. That is the only inter-file link.

The `sanitizedForJSON` CGFloat extension stays in `WireConversion.swift` (it's used by both `convert` and `toContainerInfo` in that file). `InterfaceDiff` never touches a CGFloat directly — it operates on already-wire-ified `HeistElement` and `InterfaceNode`. No need to share the helper.

### Facade impact on `TheStash.swift`

The five-line block at `TheStash.swift:463-503` updates as follows: the four `WireConversion.*` calls in the wire-conversion facades stay unchanged; the one `WireConversion.computeDelta(...)` call in `computeDelta(...)` becomes `InterfaceDiff.computeDelta(...)`. Net: one identifier rename. No new facades needed.

### Tests

`WireConversionTests.swift` is 1090 LOC, ~70% of which exercises `computeDelta`. After the source split, this test file should split alongside it: `InterfaceDiffTests.swift` takes the delta tests (~750 LOC) and `WireConversionTests.swift` keeps the `traitNames` / `convert` / `toWire` tests (~340 LOC). This is a follow-on cleanup, not a blocker — leaving the tests in one file with both new types imported works fine and the test file can be split later.

## Audit question 3: Why not also split tree wire from element wire?

Worth stating explicitly because the brief specifically asked.

- Combined LOC is ~170, which is below the "splitting earns its keep" threshold for this codebase (compare: `Interactivity.swift` is 56 LOC, `IdAssignment.swift` is 94 LOC, `Diagnostics.swift` is 205 LOC — all single-concern files that are not candidates for further decomposition).
- The call graph is fused: `convertNode` is the tree walker's only non-trivial function, and its body is dispatch to per-element conversion. Moving it out leaves `WireConversion` with `traitNames` + `convert` + `buildActions` (~85 LOC) and the new `WireTree` file with `toWireTree` + `convertNode` + `toContainerInfo` (~56 LOC) plus boilerplate.
- The historical co-change pattern groups tree wire with delta (#326 added tree on the wire and tree-edit detection together) or with the parser (#370 changed `Screen` and `convertNode` reads `screen.heistIdByElement`). Splitting tree-from-element makes a cut at exactly the boundary that *doesn't* co-vary.

## Sightings (not findings)

- Line 9-14: `WireTreeRecord` is declared at file scope as `private struct`, while `ElementIdentitySignature` / `ElementStateSignature` / `ElementPairingSignature` are also file-scope private structs. They are all delta-internal. After the carve-up, all four live in `InterfaceDiff.swift` and stay file-scope private — no nested-type promotion needed.
- Line 220 in TheBrains.swift fully-qualifies the call as `TheStash.WireConversion.convert(...)`. This is the only out-of-module reference and the only thing forcing `WireConversion` to be nested inside `extension TheStash`. Pulling the type out of that extension (matching `IdAssignment` / `Interactivity` / `Diagnostics` / `AccessibilityPolicy`) makes the call site one identifier shorter. Recommend doing this in the same PR.
- The `enum WireConversion` declaration sits inside `extension TheStash { ... }` even though `TheStash` itself is a class. The nesting is purely a namespacing trick; nothing in `WireConversion` accesses `TheStash` state. Removing the wrapper extension is a no-op for the runtime and an idiom-alignment win.
- `computeDelta` at lines 200-231 has a nested "fast no-change check" that re-implements equality on `[ScreenElement]` instead of using `before == after` directly. `ScreenElement` already conforms to `Equatable` (Screen.swift:127). The hand-rolled loop is presumably a micro-optimization to early-out on first mismatch — worth confirming that `==` doesn't already do that (it does, via synthesized stored-property equality). This is a candidate for "smaller wins" if the carve-up doesn't happen. Either way, the loop can be replaced with `before.elementsEqual(after)` for the same short-circuit semantics.

## Decision and rationale

**Decompose two-way (`WireConversion` + `InterfaceDiff`), not three-way.**

The case for splitting is moderate, not strong: this is not a god-object refactor like TheBrains was. The file reads cleanly in order, and a third of past commits touched it as a coherent unit. But the delta logic is ~75% of the file, has its own four supporting struct types, and historically does not co-vary with the trait/element/tree conversion. Putting it in its own file makes the diff history easier to navigate without sacrificing locality of anything that currently shares a function call.

The case for the three-way split is weak: the tree walker is 56 lines of dispatch into per-element conversion, and the two halves co-vary by call rather than by data. Splitting them would create two too-small files joined at the hip.

Net file count change: +1 (`InterfaceDiff.swift` added; `WireConversion.swift` retained, slimmed).
Net LOC change: ~+20 (boilerplate for the new file).
Net directory change: zero.

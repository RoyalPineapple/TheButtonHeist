# Test Inventory Audit

Walk of `ButtonHeist/Tests/` looking for tests that don't earn their keep. Scope: every `*.swift` file under `ButtonHeist/Tests/{TheInsideJobTests,ButtonHeistTests,TheScoreTests}/` (94 files, ~28k lines).

The bar for "earns its keep" is the **Testing Philosophy** section of `CLAUDE.md`:

- Mock at the network layer, not by reaching into private fields.
- Pass `ElementTarget` / `AccessibilityElement` as currency — no per-test snapshot types.
- Currency types are exact-or-miss; tests must reflect that.
- Tests are deterministic and behavior-focused.

The findings below are grouped by anti-pattern. Severity: **high** (misleading test — wrong target, stale name, or behavior already covered elsewhere), **medium** (clutter — repeated factories, near-duplicate cases), **low** (cosmetic — comment drift, parameter naming).

Totals:
- **Tests to delete: 18**
- **Tests to consolidate: 23 (collapse to 8)**
- **Helpers to extract: 4 (one big factory, three smaller assertion helpers)**
- **Stale comments to fix: 9**

---

## 1. Implementation-detail tests (high severity)

These reach into `brains.navigation.containerExploreStates[...]` directly (a private bookkeeping dictionary) instead of testing the behavior the cache affects (explore outcome differs after `clearCache`).

### 1.1 `containerExploreStates` direct mutation

| File:line | Smell | Action |
|---|---|---|
| `ButtonHeist/Tests/TheInsideJobTests/TheBrainsActionTests.swift:217-234` (`testClearCacheResetsStashAndExploreState`) | Builds a fake `Navigation.ContainerExploreState` in-place, asserts `containerExploreStates.isEmpty` after `clearCache()`. The contract under test is "after `clearCache`, a fresh `explore` starts from zero," not "the dictionary is empty." | **Rewrite** to drive `clearCache()` then run a real `explore` cycle and assert the visible outcome, or **delete** if `testClearCacheResetsExploreState` (below) already covers it via the same path. |
| `ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollTests.swift:417-432` (`testClearCacheResetsExploreState`) | Same internal-state assertion. | **Consolidate** — either keep this or 1.1 above; not both. The TheBrainsScrollTests version is in a worse location (clearCache is not a scroll concern) — prefer keeping the TheBrainsActionTests version and deleting this one. |
| `ButtonHeist/Tests/TheInsideJobTests/TheBrainsScrollTests.swift:405-413` (`testContainerExploreStateStoresValues`) | Asserts that a struct literal stores the values you put into it. Pure language test on a `Sendable` value type. | **Delete.** |

### 1.2 `offViewportRegistryEntry` direct API tests

The function is still called `offViewportRegistryEntry` in source even though "the registry is gone" per the test comments. The tests at `TheBrainsScrollTests.swift:349-401` exercise the function directly, including one (`testOffViewportEntryByMatcherReturnsNilForOffScreenOnlyEntry`) whose docstring admits it can never produce a hit by construction — it's a tautology.

| File:line | Smell | Action |
|---|---|---|
| `TheBrainsScrollTests.swift:378-389` (`testOffViewportEntryByMatcherReturnsNilForOffScreenOnlyEntry`) | The docstring says: "Matcher resolution no longer falls back to off-viewport entries… only returns a hit when the live hierarchy resolves the matcher and the resolved element is not in the live viewport, **which is impossible**." A test that asserts something impossible never fails for the right reason. | **Delete.** |
| `TheBrainsScrollTests.swift:391-401` (`testOffViewportEntryByMatcherReturnsNilWhenOnScreen`) | Same code path; this case is already covered by the resolveTarget tests in `TheStashResolutionTests.swift:404-409`. | **Delete** (or consolidate with `testHasTargetIgnoresOffScreenMatcher`). |
| `TheBrainsScrollTests.swift` MARK at line 313 (`offViewportRegistryEntry`) | Section name leans on the dead "Registry" word. | **Rename the section** to `Off-Viewport Entry` and **rename the source function** to drop "Registry" (out of scope for this audit, but flag it). |

### 1.3 `brains.stash.currentScreen = Screen(…)` poke

Three files build a `Screen` value type by hand and write it directly to `brains.stash.currentScreen` to set up state. This is fine as a fixture pattern, but each file repeats the full memberwise init.

| File | Lines spent on `Screen(...)` init |
|---|---|
| `TheBrainsActionTests.swift` (`installScreen` helper) | ~28 |
| `TheBrainsScrollTests.swift` (`installScreenWithOffViewportEntry`) | ~30 |
| `TheBrainsPipelineTests.swift` (`seedScreen`) | ~25 (similar shape) |

**Action**: extract a shared `Screen.makeForTests(elements:hierarchy:objects:offViewport:)` factory into a `TheInsideJobTests/TestSupport.swift` and delete the three near-duplicates. See section 4 below.

---

## 2. Redundant tests (high/medium severity)

### 2.1 `ElementMatcher` matching covered three times

`HeistElement.matches` (client) and `AccessibilityElement.matches` (server) share `ElementMatcher.stringEquals` per the Currency Types section of CLAUDE.md. The behavior is tested:

- `TheScoreTests/ElementMatcherTests.swift` — 30 tests against `HeistElement.matches` and the helpers (`stringEquals`, `stringContains`, `nonEmpty`, `hasPredicates`)
- `TheInsideJobTests/ElementMatcherTests.swift` — 75+ tests against `AccessibilityElement.matches`, mostly mirroring the same cases (label exact, identifier exact, value exact, trait include/exclude, typography folding)
- `TheScoreTests/WireTypeRoundTripTests.swift` — additional Codable round-trip cases for `ElementMatcher`

The TheScore copy already mirrors the contract on both sides per CLAUDE.md ("the same semantics are evaluated by `HeistElement.matches` on the client and `AccessibilityElement.matches` on the server, via the shared `ElementMatcher.stringEquals` helper"). The TheInsideJob ElementMatcherTests are then mostly redundant — they reverify the exact same predicate via a different call site.

| File:line | Smell | Action |
|---|---|---|
| `TheInsideJobTests/ElementMatcherTests.swift:40-374` | Most of these duplicate `TheScoreTests/ElementMatcherTests.swift` cases on the server side. Worse, they all pass `mode: .substring` — a legacy mode that should no longer reach `resolveTarget` per CLAUDE.md's exact-or-miss contract. Tests of substring mode are useful, but 75 of them is excessive given `mode: .exact` is the production path. | **Consolidate down to ~10 tests**: keep one per match dimension (label exact, label folding, identifier, value, traits include, traits exclude, compound) + one substring-mode sanity test so the unused mode doesn't bit-rot. **Delete** the rest. |
| `TheScoreTests/ElementMatcherTests.swift:42-66` (3x `testEncodeDecode*`) | Three round-trip tests on `ElementMatcher` (empty, minimal, all fields) that are also covered indirectly by `WireTypeRoundTripTests.swift` and every `ClientMessageActionRoundTripTests` case that wraps a matcher. | **Consolidate to one** "all fields" round-trip. |
| `TheInsideJobTests/ElementMatcherTests.swift:389-408` (`testElementTargetMatcherInitializerDropsEmptyMatcher`, `testScrollToVisibleTargetWithElementTarget`) | Verbatim copies of tests in `TheScoreTests/ElementMatcherTests.swift:19-40`. | **Delete from TheInsideJobTests** — these are TheScore wire-type tests that don't belong in the UIKit-hosted bundle. |

### 2.2 `clampDuration` over-specified

`brains.actions.clampDuration` is `max(min(d ?? 0.5, 60), 0.01)` over an optional. `TheBrainsActionTests.swift:22-70` has **8 tests** for it: nil, min, max, valid, at-exact-min, at-exact-max, negative, zero.

| File:line | Smell | Action |
|---|---|---|
| `TheBrainsActionTests.swift:24-70` | 8 tests for a 3-call expression. Below-min, above-max, valid, and nil cover the whole truth table. At-exact-min, at-exact-max, negative, zero are equivalent in behavior. | **Consolidate to 4** — drop the 4 redundant cases. |

### 2.3 `resolveScrollTarget` / `scrollableAxis` / `adaptDirection` covered twice

`ButtonHeist/Tests/TheInsideJobTests/TheStashScrollTests.swift` (151 lines) calls `brains.navigation.resolveScrollTarget`, `Navigation.scrollableAxis(of:)`, and `Navigation.adaptDirection(_:for:)`. `TheBrainsScrollTests.swift` covers the **same APIs** in greater depth at lines 60-310 and 434-484.

| File | Smell | Action |
|---|---|---|
| `TheStashScrollTests.swift` (entire file) | Filename implies it tests TheStash; actually tests `brains.navigation.*`. Every API it covers is also covered in `TheBrainsScrollTests.swift`. | **Delete the file** and check that `TheBrainsScrollTests.swift` has at least one test for `resolveScrollTargetReturnsNilWhenNoScrollView` (it does not — port that one over before deletion). |

### 2.4 Codable round-trips with no custom logic

`WireTypeRoundTripTests.swift` round-trips every wire enum and target through JSON. Most of these have no custom `Codable` implementation; the test is "does Swift's synthesized Codable round-trip a `String`-backed enum?" — the answer is "yes, by language guarantee."

| File:line | Smell | Action |
|---|---|---|
| `WireTypeRoundTripTests.swift:13-19` (`testScrollEdgeAllCasesRoundTrip`) | Round-trips a `String`-backed `CaseIterable` enum. No custom Codable. | **Delete.** |
| `WireTypeRoundTripTests.swift:21-26` (`testScrollEdgeRawValues`) | Asserts hardcoded `rawValue` strings match… the case names. This is useful as a wire-shape lock — **keep**. |
| `WireTypeRoundTripTests.swift:30-35` (`testScrollDirectionAllCasesRoundTrip`) | Same — synthesized round-trip. | **Delete.** |
| `WireTypeRoundTripTests.swift:38-40` (`testScrollDirectionCaseCount`) | Asserts `allCases.count == 6`. Counts-are-counts; brittle to additions, doesn't catch real bugs. | **Delete.** |
| `WireTypeRoundTripTests.swift:49-55` (`testEditActionAllCasesRoundTrip`) | Same shape — synthesized round-trip. | **Delete.** |
| `WireTypeRoundTripTests.swift:57-59` (`testEditActionCaseCount`) | Counts assert. | **Delete.** |
| `WireTypeRoundTripTests.swift:653-655` (`testWireMessageTypeCaseCount`) | Asserts `WireMessageType.allCases.count == 52`. Brittle, no behavioral content. | **Delete.** |
| `ButtonHeist/Tests/ButtonHeistTests/TheFenceTests.swift:48-50` (`testCommandCaseCount`) | Same — `Command.allCases.count == 42`. The companion `testCommandRawValuesMatchWireFormat` does the load-bearing check. | **Delete the count assertion;** keep raw-value lock. |
| `TheScoreTests/HeistTraitTests.swift:6-12` (`testKnownCaseRoundTrip`) | All-cases round-trip on a `String`-backed Codable enum. | **Delete.** The `testUnknownCaseRoundTrip` (custom Codable for `.unknown`) is the load-bearing test — **keep**. |
| `TheScoreTests/HeistTraitTests.swift:33-39` (`testRawValueRoundTrip`) | Asserts `HeistTrait(rawValue: trait.rawValue) == trait` for every case. Synthesized `RawRepresentable`. | **Delete.** |

### 2.5 `ConstantsTests` partly tests the language

| File:line | Smell | Action |
|---|---|---|
| `TheScoreTests/ConstantsTests.swift:10-12` (`testButtonHeistVersionIsNonEmpty`) | Asserts a `let` constant is non-empty. The constant is set at the source file; non-emptiness is structurally guaranteed. | **Delete.** |
| `TheScoreTests/ConstantsTests.swift:6-8, 14-18` | `serviceType` and Bonjour format checks are useful regression guards. | **Keep.** |

### 2.6 `AccessibilityPolicy` non-emptiness

`TheScoreTests/AccessibilityPolicyTests.swift:18-32` has 4 `testXxxIsNonEmpty` tests for static `let` Sets defined in source. Same pattern as 2.5.

| File:line | Smell | Action |
|---|---|---|
| `AccessibilityPolicyTests.swift:18-32` | Non-emptiness of a `static let` is structurally guaranteed; "policy was deleted" would fail compilation. | **Delete all 4.** Keep the `testXxxContainsNoUnknowns`, disjointness, and content-locked tests — those are the load-bearing invariants. |

### 2.7 Discovery registry naming collision

`ButtonHeistTests/DiscoveredDeviceTests.swift:294-380` tests `DiscoveryRegistry` — a different unrelated type (Bonjour device dedupe). The name overlap with the deleted accessibility registry is a maintenance smell but the tests are fine. **No action**, just noting for future readers — possibly rename to `DiscoveredDeviceDedupTests` if `DiscoveryRegistry` ever gets renamed.

---

## 3. Stale comments (low/medium severity)

| File:line | Stale phrase | Fix |
|---|---|---|
| `TheInsideJobTests/TheBrainsPipelineTests.swift:9` | "the stash registry: the failure branch…" | Drop "registry" — the comment was written before 0.2.25. |
| `TheInsideJobTests/TheStashResolutionTests.swift:62-63` | "Post-0.2.25 this also serves the matcher path (the registry is gone — Screen.heistIdByElement is the lookup)." | Drop the "Post-0.2.25" qualifier — 0.2.25 has shipped; comments shouldn't be release-anchored once the release is in the past. |
| `TheInsideJobTests/TheStashResolutionTests.swift:71-74` | "Off-screen entries are now strictly notFound through `resolveTarget` (the strict off-screen rule) so the only places this still matters are `selectElements()` and `findElement(heistId:)` tests asserting the union shape." | Trim — the comment narrates the migration rather than the current contract. |
| `TheInsideJobTests/TheStashResolutionTests.swift:384` | `// MARK: - Strict Off-Screen Rule (post-0.2.25)` | Drop the version qualifier. |
| `TheInsideJobTests/TheStashResolutionTests.swift:386-388` | "After the registry was deleted, matcher-based resolution looks only at the live hierarchy." | Drop the historical framing. |
| `TheInsideJobTests/TheBrainsScrollTests.swift:374-375` | "(the registry is gone — matchers walk the live hierarchy only). `offViewportRegistryEntry(for:.matcher)` therefore only returns a hit when…" | The test these comments support is tautological (section 1.2); fix or delete together. |
| `TheInsideJobTests/TheBrainsScrollTests.swift:388` | XCTAssertion message: `"Matcher resolution does not reach off-viewport entries post-0.2.25"` | Drop the version qualifier. |
| `TheScoreTests/ElementMatcherTests.swift:142-148` | "Old behavior: 'Sav' was a substring of 'Save' and matched. New behavior: exact-or-miss…" | Worth keeping as a contract reminder — but tighten to "Exact-or-miss: 'Sav' must not match 'Save'." Drop "Old behavior." |
| `TheInsideJobTests/ElementMatcherTests.swift:74-80` | Three-line comment explaining "Empty matcher label is a substring of any label — always matches" followed by an assertion that it does **not** match. Comment contradicts the test. | Rewrite the comment to match the actual behavior, or delete. |

No `TODO:` / `FIXME:` / `// when X ships` comments were found in tests — that pattern is already absent.

---

## 4. Setup boilerplate to extract (medium severity)

### 4.1 `makeElement` factory — duplicated in 21 files

A grep for `AccessibilityElement(\n description:` over `Tests/` returns **21 distinct file-local `makeElement` / `element` / `dummyElement` factories**. They differ only in defaults (some pass `respondsToUserInteraction: true`, some `false`; some default to `.frame(.zero)`, some include a y-offset; one varies traits via `[HeistTrait]` enum and one via `UIAccessibilityTraits`).

Sample (representative):

- `TheBrainsActionTests.swift:313-334` — 22 lines
- `TheBrainsScrollTests.swift:677-699` — 23 lines
- `TheStashResolutionTests.swift:24-53` — 30 lines (adds y-offset increment)
- `ElementMatcherTests.swift:12-36` — 25 lines
- `IdAssignmentTests.swift:14-39` — 26 lines (takes `[HeistTrait]`)
- `AccessibilityHierarchyFilterTests.swift:11-37` — 27 lines (returns a node)
- `TheStashScrollTests.swift:130-148` — 19 lines
- `WireConversionTests.swift`, `ScreenTests.swift`, `SettleSessionTests.swift`, `ContainerFingerprintTests.swift`, `TheBurglarApplyTests.swift`, `SynthesisDeterminismTests.swift`, `DiagnosticsTests.swift`, `InteractivityTests.swift`, `TheStashTopologyTests.swift`, `TheBurglarContainerFramesTests.swift`, `ActivateFailureDiagnosticTests.swift`, `AccessibilityHierarchyReconciliationTests.swift`, `TheBrainsPipelineTests.swift`, `IdAssignmentTests.swift`, plus three TheScore files for `HeistElement` factories.

**Action**: extract one canonical factory into a new `ButtonHeist/Tests/TheInsideJobTests/TestSupport/AccessibilityElement+Tests.swift`:

```swift
extension AccessibilityElement {
    static func make(
        label: String? = nil,
        value: String? = nil,
        identifier: String? = nil,
        traits: UIAccessibilityTraits = .none,
        shape: Shape = .frame(.zero),
        respondsToUserInteraction: Bool = true
    ) -> AccessibilityElement
}
```

Estimated lines deleted: **~500** (21 factories × ~25 lines).

### 4.2 Screen fixture factory — duplicated in 3 files

`TheBrainsActionTests.swift:284-311`, `TheBrainsScrollTests.swift:318-347`, `TheBrainsPipelineTests.swift` (similar shape) — each builds a `Screen` value type by hand to seed `brains.stash.currentScreen`.

**Action**: extract `Screen.makeForTests(elements:hierarchy:objects:offViewport:)` into the same TestSupport file. Estimated lines deleted: **~80**.

### 4.3 BookKeeper `tempDirectory` setUp — repeated in 2 files

`TheBookKeeperTests.swift:6-18` and `BookKeeperHeistTests.swift` both stand up a `FileManager.temporaryDirectory.appendingPathComponent("..-\(UUID())")` in `setUp`/`tearDown`. The pattern repeats. **Action**: extract a `XCTestCase.useTemporaryDirectory()` helper. Smaller win — ~20 lines saved.

### 4.4 `withNoTraversableWindows` — useful, kept

`TheBrainsActionTests.swift:336-350` defines a window-hiding scope helper for "accessibility tree unavailable" tests. It's only used in this file, so no extraction needed. Noted as a pattern worth lifting if a second file ever needs the same scope.

---

## 5. Tests that test the language, not the code (high severity)

Beyond the Codable / count assertions covered in section 2, the following are pure-language tests:

| File:line | Test | Why it's a language test |
|---|---|---|
| `TheInsideJobTests/TheBrainsScrollTests.swift:405-413` (`testContainerExploreStateStoresValues`) | Constructs a struct, reads its fields back, asserts they equal the constructor arguments. | Memberwise init guarantee. |
| `TheScoreTests/ElementMatcherTests.swift:83-87` (`testEqualMatchers`), `:89-93` (`testUnequalMatchers`) | Asserts `==` works on a struct whose `Equatable` is synthesized. | Synthesized Equatable guarantee. |
| `TheScoreTests/HeistTraitTests.swift:41-43` (`testUnknownRawValueReturnsNil`) | Asserts `HeistTrait(rawValue: "futureTrait") == nil` for a non-existent case. | This is interesting because `HeistTrait` has a custom `Codable` for `.unknown`, but `RawRepresentable.init(rawValue:)` does **not** decode `.unknown`. The test is correct — but it's asserting that the synthesized initializer behaves as advertised, not that the unknown-handling logic works. **Borderline keep** — useful to document the asymmetry. |
| `TheScoreTests/WireTypeRoundTripTests.swift` various `testXxxCaseCount` | Already covered in 2.4. | Count-of-enum-cases. |
| `TheScoreTests/ConstantsTests.swift:10-12` | Already covered in 2.5. | Non-empty `let`. |
| `TheScoreTests/AccessibilityPolicyTests.swift:18-32` | Already covered in 2.6. | Non-empty `static let`. |

**Action**: delete or consolidate as flagged in the relevant section above.

---

## 6. File-level observations

### 6.1 Two `ElementMatcherTests.swift` files

`TheInsideJobTests/ElementMatcherTests.swift` (789 lines) and `TheScoreTests/ElementMatcherTests.swift` (258 lines) test the same predicate via two call sites. Per section 2.1, consolidate the TheInsideJob copy down to ~10 representative cases.

### 6.2 `TheStashScrollTests.swift` is misnamed

It tests `brains.navigation.*`, not `TheStash`. Coverage is fully duplicated in `TheBrainsScrollTests.swift`. Delete after porting one missing case (2.3).

### 6.3 `TheBookKeeperTests.swift` and `BookKeeperHeistTests.swift`

Two test files for closely-related code paths. Not flagged for consolidation in this audit (the heist-specific tests stand on their own), but the `tempDirectory` setUp duplication is in 4.3.

### 6.4 Test-only `MARK` sections referencing removed concepts

`TheBrainsScrollTests.swift:313` has `// MARK: - offViewportRegistryEntry` — the function still exists but the section name carries the "Registry" baggage flagged elsewhere in this audit. Rename to `// MARK: - Off-Viewport Entry`.

---

## Appendix: methodology

1. Listed all 94 files under `ButtonHeist/Tests/` with line counts (`wc -l`, sorted).
2. Grepped for stale identifiers — `registry`, `RegistryNode`, `ElementRegistry`, `apply(_:to:)`, `register(parsedElements`, `TheBrains+Actions`, `TheBrains+Scroll`, `nodesById`, `heistIdIndex`.
3. Grepped for `containerExploreStates`, `offViewportRegistryEntry`, `stash registry`, `the registry`, `god-class`, `post-0.2.25` to find references to refactored internals.
4. Grepped for `private func makeElement` / `private func element` / `func makeElement(` to count factory duplication (found 21 distinct file-local factories).
5. Grepped for `allCases.count` (5 occurrences across 3 files — all flagged in 2.4).
6. Grepped for `// TODO`, `// FIXME`, `Old behavior`, `previously`, `used to`, `before the`, `post-0.2.25`, `when X ships` to find stale narrative comments.
7. Read the bodies of every file flagged by the greps to verify the smell, distinguishing real findings from false positives (e.g. `DiscoveryRegistry` is a different unrelated type and not stale).

No tests were modified, deleted, or added. The recommendations above are decisions for the maintainers — this audit only inventories the candidates.

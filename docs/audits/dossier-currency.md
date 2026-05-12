# Dossier Currency Audit

> **Scope:** Catalog of stale sections in `docs/dossiers/*.md` vs current source as of branch `RoyalPineapple/0.2.25-eliminate-registry`.
> **Methodology:** Read each dossier; cross-check file paths, type declarations, and architectural claims against `ButtonHeist/Sources/`. Categorize findings.
> **Reference shifts in scope:**
>   - 0.2.24: `TheStakeout` and `TheMuscle` converted from `@MainActor` classes to `actor`s. `AlertPresenter` extracted as a MainActor companion.
>   - 0.2.24: matcher contract resolved to exact-or-miss (#366).
>   - 0.2.24: `ConnectionFailure` consolidated into `ConnectionError` (#354).
>   - 0.2.25: `ElementRegistry` deleted; replaced with `Screen` value type on TheStash. `parse() → Screen` is pure; `currentScreen` is the single mutable slot.
>   - Recent: `TheBrains` decomposed into orchestrator + `Navigation` + `Actions` (PR #373).
>   - Recent: trait policy consolidated into `AccessibilityPolicy` namespace (PR #371).
> **Output:** Per-dossier verdict + flagged sections. No rewrites here.

## Verdict Summary

| # | Dossier | Verdict | Stale sections |
|---|---------|---------|----------------|
| 00 | `README.md` | current | 0 |
| 01 | `01-CLI.md` | current | 0 |
| 02 | `02-MCP.md` | current | 0 |
| 03 | `03-THEFENCE.md` | mostly-current | 1 |
| 04 | `04-THEHANDOFF.md` | current | 0 |
| 05 | `05-THEBOOKKEEPER.md` | mostly-current | 1 |
| 06 | `06-THEINSIDEJOB.md` | current | 0 |
| 07 | `07-THEPLANT.md` | mostly-current | 1 |
| 08 | `08-THEMUSCLE.md` | substantively-stale | 4 |
| 09 | `09-THEGETAWAY.md` | mostly-current | 1 |
| 10 | `10-THEBURGLAR.md` | mostly-current | 1 |
| 11 | `11-THESTASH.md` | current | 0 |
| 12 | `12-UNIFIED-TARGETING.md` | substantively-stale | 8 |
| 13 | `13-THEBRAINS.md` | current | 0 |
| 14 | `14-THESAFECRACKER.md` | substantively-stale | 6 |
| 14a | `14a-SCROLLING.md` | substantively-stale | 5 |
| 14b | `14b-TOUCH-INJECTION.md` | current | 0 |
| 14c | `14c-TEXT-ENTRY.md` | mostly-current | 1 |
| 15 | `15-THETRIPWIRE.md` | mostly-current | 1 |
| 16 | `16-THESTAKEOUT.md` | substantively-stale | 3 |
| 17 | `17-THEFINGERPRINTS.md` | current | 0 |
| 18 | `18-THESCORE.md` | mostly-current | 2 |

**Totals:** Current: 8. Mostly-current: 9. Substantively-stale: 5. **Total stale sections flagged: 35.**

The single worst dossier by impact is **12-UNIFIED-TARGETING.md**. It still describes the pre-0.2.25 registry world end-to-end: `screenElements` dictionary as the heistId registry, `presentedHeistIds` gate, `heistIdByTraversalOrder` reverse index, `cachedElements` flat array, the "scorched earth" wipe-and-rebuild on screen change, and three `TheStash+*` extension files (`+Scroll`, `+Actions`, `+Matching`) — none of which exist on this branch. It is the cross-cutting reference for unified targeting, so its staleness reverberates: nearly every "What it needs" entry in the callers table points at files that have been renamed or merged into `Actions.swift`/`Navigation+Scroll.swift`. A reader trusting this dossier will look in the wrong files and chase a registry that was deleted in 0.2.25.

---

## Per-Dossier Findings

### 03-THEFENCE.md — mostly-current

**3.1 File list at top is incomplete.** Header line 3:
```
Files: TheFence.swift, TheFence+CommandCatalog.swift, TheFence+Handlers.swift, TheFence+Formatting.swift
```
Actual `ButtonHeist/Sources/TheButtonHeist/TheFence/` contains 11 files: `Dictionary+ArgParsing.swift`, `NetDeltaAccumulator.swift`, `TheFence+Batch.swift`, `TheFence+CommandCatalog.swift`, `TheFence+ExpectationParsing.swift`, `TheFence+Formatting+Compact.swift`, `TheFence+Formatting+JSON.swift`, `TheFence+Formatting.swift`, `TheFence+Handlers.swift`, `TheFence+ParameterSpec.swift`, `TheFence.swift`. Severity: low (header only, body is accurate).

### 05-THEBOOKKEEPER.md — mostly-current

**5.1 Header path is correct but file list is implicit.** Directory pointer is fine, but the dossier doesn't enumerate the actual files (`PlaybackFailure.swift`, `SessionManifest.swift`, `TheBookKeeper+Compression.swift`, `TheBookKeeper+Logging.swift`, `TheBookKeeper.swift`). Low-impact omission; only listed for completeness. Severity: low.

### 07-THEPLANT.md — mostly-current

**7.1 Header path wrong.** Line 3:
```
Files: ButtonHeist/Sources/ThePlant/ThePlantAutoStart.m, ButtonHeist/Sources/TheInsideJob/Extensions/AutoStart.swift
```
`AutoStart.swift` is now at `ButtonHeist/Sources/TheInsideJob/Lifecycle/AutoStart.swift`. The `Extensions/` directory does not exist on this branch. Severity: low (single path).

### 08-THEMUSCLE.md — substantively-stale

**8.1 Header path stale.** Line 3 says `ButtonHeist/Sources/TheInsideJob/TheMuscle.swift`. Actual: `ButtonHeist/Sources/TheInsideJob/Server/TheMuscle.swift`. Severity: low.

**8.2 Concurrency annotation wrong.** Architecture diagram (line 23) labels the subgraph `TheMuscle (@MainActor)`. Source declares `actor TheMuscle` (`Server/TheMuscle.swift:33`). Same error repeats in any subgraph or callout that says `@MainActor`. This is the 0.2.24 actor conversion. Severity: high (this is a structural claim about isolation).

**8.3 Doesn't mention AlertPresenter extraction.** 0.2.24 extracted `AlertPresenter` (in `Server/AlertPresenter.swift`) as a MainActor companion because the alert presentation can't live on the actor. The dossier still describes the UI prompt as if TheMuscle itself shows the `UIAlertController` (lines 36-37, 80-81). The dossier needs to acknowledge the actor/MainActor split. Severity: medium.

**8.4 `INSIDEJOB_SESSION_TIMEOUT` default wrong.** Configuration table (line 120) lists "30s" as the default. The current default is 60s (per `feedback_session_timeout_default.md` and source). Severity: medium (configuration users will be misled).

### 09-THEGETAWAY.md — mostly-current

**9.1 Header file path stale.** Line 3 says `TheGetaway.swift`. Actual directory is `TheInsideJob/TheGetaway/` with `TheGetaway.swift`, `TheGetaway+Recording.swift`, and `PingFastPath.swift`. The dossier defers to the directory README for the file-level walkthrough, so this is only a header-level claim about "the file", which is now a directory. Severity: low.

### 10-THEBURGLAR.md — mostly-current

**10.1 References `TheBrains+Exploration` as a file/extension.** Lines 31, 38, 44 talk about `TheBrains+Exploration.exploreAndPrune` and "local var in `TheBrains+Exploration`". Post-PR-#373, the file is `Navigation+Explore.swift` and the function lives on `Navigation`, not on a `TheBrains` extension. The accumulator pattern itself is unchanged (still a local `var union: Screen`), but the file/extension name is wrong. Severity: medium (3 occurrences in a short dossier).

### 12-UNIFIED-TARGETING.md — substantively-stale

This is the most-stale dossier in the set. It describes the resolution layer as the pre-0.2.25 registry-based world end-to-end. Specific flagged sections:

**12.1 "Matching Infrastructure" section (lines 175-196) names a flat-array fallback that no longer exists.** Lines 180-182 describe `cachedElements: [AccessibilityElement]` and `[AccessibilityElement].firstMatch(_:)` as a fallback search surface. There is no `cachedElements` on `TheStash` post-0.2.25 — the single source is `currentScreen.hierarchy`. Severity: high.

**12.2 "Callers" table (lines 198-217) lists files that don't exist.** Every row points at one of `TheStash+Scroll.swift`, `TheStash+Actions.swift`, or `TheStash.swift`. The scroll methods now live on `Navigation+Scroll.swift`; the action methods now live on `Actions.swift`. None of the `TheStash+Scroll.swift` / `TheStash+Actions.swift` files exist on this branch. Severity: high.

**12.3 "CLI Targeting Surface" callers table (line 207) attributes `executeActivate` to `TheStash+Actions.swift`.** Same as 12.2 — `executeActivate` now lives on `Actions.swift` under `TheBrains/`. Severity: high (this is a primary reference for what runs where).

**12.4 "Element Registry" section (lines 256-262) is entirely pre-0.2.25.** Describes `screenElements: [String: ScreenElement]` as "the persistent element registry, keyed by heistId. It lives for the screen's duration and is populated during `updateScreenElements()` (called from `refreshAccessibilityData()`). Screen change = scorched earth (full wipe + rebuild from cached data)." None of this is true on this branch — there is no `screenElements` field, no `updateScreenElements()`, no `refreshAccessibilityData()`, and no scorched-earth wipe (the registry was deleted). Severity: critical.

**12.5 "snapshotElements" / "onScreen" / "presentedHeistIds" references are stale.** Lines 258, 260-262 reference `snapshotElements()`, the `onScreen` set, and `presentedHeistIds` gate. None of these exist on TheStash post-0.2.25. Severity: critical.

**12.6 "heistIdByTraversalOrder" reverse-index reference.** Line 262 cites `heistIdByTraversalOrder` for matcher resolution. The actual reverse index is `currentScreen.heistIdByElement` (keyed on `AccessibilityElement`, not traversal index). Severity: high.

**12.7 Data-flow diagram (lines 30-50) calls `refreshAccessibilityData()`.** Line 41 puts `IJ->>TB: refreshAccessibilityData()` on the sequence diagram. Method no longer exists; the equivalent path is `stash.refresh()` (via TheBurglar.refresh → buildScreen). Severity: medium.

**12.8 Sub-sequence labels `TB` as TheStash but routes scroll there.** Lines 43-49 of the diagram show `TB->>TB: executeActivate(target)` and `TB->>TB: ensureOnScreen(target)` and `TB->>TB: resolveTarget(.matcher)`. `executeActivate` and `ensureOnScreen` live on TheBrains/Navigation now; only `resolveTarget` is still on TheStash. Severity: medium.

### 14-THESAFECRACKER.md — substantively-stale

**14.1 "Source Files" table (lines 22-34) lists `TheSafecracker+Actions.swift` and `TheSafecracker+Scroll.swift`.** Neither exists. The actual `TheSafecracker/` directory contains: `KeyboardBridge.swift`, `ObjCRuntime.swift`, `SyntheticTouch.swift`, `TheFingerprints.swift`, `TheSafecracker+Bezier.swift`, `TheSafecracker+IOHIDEventBuilder.swift`, `TheSafecracker+MultiTouch.swift`, `TheSafecracker+Scroll.swift`, `TheSafecracker+TapDiagnostic.swift`, `TheSafecracker.swift`. Note: `TheSafecracker+Scroll.swift` *does* exist (so the table row for it is accurate); `TheSafecracker+Actions.swift` *does not* (so that row is stale). Severity: high.

**14.2 Architecture diagram (lines 38-71) references `TheSafecracker+Actions.swift`.** Same issue as 14.1, but in the mermaid diagram. Severity: high (same root cause).

**14.3 "Items Flagged for Review" cites duplicate defaults in `TheSafecracker+Actions.swift` vs `TheSafecracker.swift` (line 263).** Since `TheSafecracker+Actions.swift` doesn't exist, this concern needs to be either re-located (the duration helpers moved to `Actions.swift` under TheBrains) or deleted. Severity: medium.

**14.4 "Element Resolution Flow" diagram (lines 230-240) references `ActionTarget` struct.** Per 12-UNIFIED-TARGETING.md the struct was replaced by `ElementTarget` enum some time ago. The diagram label `Target["ActionTarget - (heistId? / match?)"]` is stale. Severity: medium.

**14.5 "Auto-scroll" paragraph (line 212) attributes auto-scroll to TheStash's `ensureOnScreen(for:)`.** Auto-scroll/ensureOnScreen lives on `Navigation` (TheBrains' Navigation component) post-PR-#373. TheStash exposes resolution and live geometry only — it does not perform scroll orchestration. Severity: high.

**14.6 "Crew References" diagram subgroup lists Tripwire only.** Doesn't mention the resolution flow's dependency on TheStash for point resolution (the diagram is fine internally but the narrative throughout the dossier still attributes too much to TheStash post-decomp). Severity: low.

### 14a-SCROLLING.md — substantively-stale

**14a.1 Header source path stale.** Line 3:
```
Source: ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+Scroll.swift (orchestration), TheSafecracker/TheSafecracker+Scroll.swift (scroll primitives)
```
There is no `TheBrains+Scroll.swift`. The orchestration file is `TheBrains/Navigation+Scroll.swift`. Severity: high (front-matter is the first thing a reader sees).

**14a.2 References `presentedHeistIds`, `screenElements`, `onScreen` — all pre-0.2.25 registry concepts.** Line 63 mentions "discovered by a prior full scan (`presentedHeistIds` + `contentSpaceOrigin` + live `scrollView`)"; line 110 calls out "TheStash screenElements registry". None of these fields exist on TheStash post-0.2.25. The equivalent post-0.2.25 path is `currentScreen.elements` / `currentScreen.heistIdByElement` / `currentScreen.scrollableContainerViews`. Severity: high.

**14a.3 "Entry points" table (line 108) attributes `ensureOnScreen` to TheStash.** Post-PR-#373 it lives on `Navigation`. Same drift as 14.5. Severity: medium.

**14a.4 References `cachedElements` in flow descriptions.** Several mid-document references to "refresh the element cache" tracking a `cachedElements` data structure. Post-0.2.25 the cache is `currentScreen.elements` and the refresh is `stash.currentScreen = stash.parse()`. Severity: medium.

**14a.5 "Two-tier dispatch" wording (line 8).** Still accurate ("UIScrollView for direct offset manipulation, synthetic swipe for everything else"), but described as if dispatched from TheBrains directly, when it dispatches from `Navigation`. Cosmetic. Severity: low.

### 14c-TEXT-ENTRY.md — mostly-current

**14c.1 Source path lists `TheStash+Actions.swift`.** Line 3:
```
Source: ButtonHeist/Sources/TheInsideJob/TheStash+Actions.swift (executeTypeText), TheSafecracker/TheSafecracker.swift (raw keyboard methods), TheSafecracker/KeyboardBridge.swift
```
`executeTypeText` lives on `TheBrains/Actions.swift` (post-PR-#373), not `TheStash+Actions.swift` (which never existed as a separate file in TheStash on this branch). Severity: high (this is the front-matter source-of-truth pointer).

### 15-THETRIPWIRE.md — mostly-current

**15.1 Header path stale.** Line 3 says `ButtonHeist/Sources/TheInsideJob/TheTripwire.swift`. Actual: `ButtonHeist/Sources/TheInsideJob/TheTripwire/TheTripwire.swift`. The class is otherwise accurately described. Severity: low (single path).

### 16-THESTAKEOUT.md — substantively-stale

**16.1 Header path stale.** Line 3 says `ButtonHeist/Sources/TheInsideJob/TheStakeout.swift`. Actual: `ButtonHeist/Sources/TheInsideJob/TheStakeout/TheStakeout.swift`. Severity: low.

**16.2 Concurrency annotation wrong throughout.** Architecture diagram (line 24) labels the subgraph `Stakeout (@MainActor)`. Source declares `actor TheStakeout` (`TheStakeout/TheStakeout.swift:23`). The dossier needs to reflect the 0.2.24 actor conversion. The diagram, the "State Machine" section header, and the implicit isolation assumption everywhere in the text are all wrong. Severity: high.

**16.3 Doesn't reflect the actor isolation model.** The current `TheStakeout` source has a substantive comment explaining the isolation model — the single MainActor escape hatch is `captureFrame`, the closure that snapshots the window hierarchy. Every other piece of state lives inside the actor. The dossier doesn't reflect this; it still describes everything as MainActor-isolated. Severity: medium.

### 18-THESCORE.md — mostly-current

**18.1 Source files table (lines 30-39) is missing recent additions.** Actual `TheScore/` contains 14 files including `AccessibilityPolicy.swift`, `ActionExpectation.swift`, `ClientMessages+TouchTargets.swift`, `HeistPlayback.swift`, `InterfaceDelta.swift`, `WireBoundaryTypes.swift` that the dossier does not enumerate. `AccessibilityPolicy.swift` is the home of PR #371's consolidated trait policy. Severity: medium (consumers of the wire protocol need a complete file index).

**18.2 No mention of `AccessibilityPolicy` namespace.** PR #371 consolidated trait policy here, including the trait categorization that used to live as `transientTraits` locals scattered across TheStash. The dossier should mention `AccessibilityPolicy` as a wire-level type family. Severity: medium.

---

## Cross-Cutting Patterns

These appear in multiple dossiers and likely cluster naturally for a single rewrite pass:

1. **File paths assuming flat-file layout** — many dossiers still use `TheInsideJob/TheMuscle.swift`, `TheInsideJob/TheTripwire.swift`, `TheInsideJob/TheStakeout.swift`, `TheInsideJob/TheGetaway.swift`. Most subsystems have been moved into eponymous folders. Affected: 07, 08, 09, 14c, 15, 16.

2. **`@MainActor class` instead of `actor`** — 0.2.24 converted TheStakeout and TheMuscle. Affected: 08, 16.

3. **`TheStash+Actions.swift` / `TheStash+Scroll.swift` as source paths** — these files never existed on this branch (or were renamed long ago). Action code lives in `TheBrains/Actions.swift`; scroll code in `TheBrains/Navigation+Scroll.swift`. Affected: 12, 14, 14a, 14c.

4. **`TheBrains+Exploration` / `TheBrains+Scroll`** — should be `Navigation+Explore` / `Navigation+Scroll` post-PR-#373. Affected: 10, 14a.

5. **Pre-0.2.25 registry terminology** (`screenElements`, `presentedHeistIds`, `cachedElements`, `onScreen`, `heistIdByTraversalOrder`, `updateScreenElements`, `refreshAccessibilityData`, "scorched earth") — these names should be replaced by the Screen-value-type vocabulary (`currentScreen`, `currentScreen.elements`, `currentScreen.heistIdByElement`, `parse()` / `buildScreen(from:)`, `stash.refresh()`). Affected: 12 (heavily), 14, 14a.

6. **No `ConnectionFailure` references found** — the 0.2.24 consolidation into `ConnectionError` is reflected correctly across all dossiers. Nothing to flag here.

7. **No `transientTraits` references in dossiers** — PR #371's `AccessibilityPolicy` consolidation moved the type into source but didn't break any dossier; only impact is the missing mention in `18-THESCORE.md`.

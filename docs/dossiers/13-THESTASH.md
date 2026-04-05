# TheStash - The Score Handler

> **Files:** `TheStash.swift`, `TheStash+Matching.swift`, `TheStash+Capture.swift`, `TheStash/ActionExecution.swift`, `TheStash/ScrollExecution.swift`, `TheStash/ScreenExploration.swift`, `TheStash/WireConversion.swift`, `TheStash/IdAssignment.swift`, `TheStash/ElementRegistry.swift`, `TheStash/Diagnostics.swift`, `TheStash/Interactivity.swift`, `TheStash/ScreenManifest.swift`, `TheStash/ArrayHelpers.swift`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Owns element registry, hierarchy parsing, target resolution, action execution, scroll orchestration, delta computation, and screen capture

## Responsibilities

TheStash handles all the goods during TheInsideJob:

1. **Screen-lifetime element registry** — maintains `screenElements: [String: ScreenElement]` keyed by heistId, persistent across refreshes within the same screen
2. **Parse/apply pipeline** — `parse()` reads the live accessibility tree into an immutable `ParseResult` value; `apply()` mutates the registry. Screen change detection happens between these two steps — no mixed old/new state.
3. **Hierarchy parsing** — drives `AccessibilityHierarchyParser` with `elementVisitor` + `containerVisitor` closures to capture element objects and scroll view refs
4. **Target resolution** — `resolveTarget(_:)` is the single entry point: `.heistId` → O(1) dictionary lookup in `registry.elements`, `.matcher` → `uniqueMatch` tree walk + O(1) reverse index lookup via `registry.reverseIndex`. Returns `TargetResolution` enum (`.resolved(ResolvedTarget)`, `.notFound(diagnostics:)`, `.ambiguous(candidates:diagnostics:)`). See [15-UNIFIED-TARGETING.md](15-UNIFIED-TARGETING.md) for the full targeting system.
5. **Action execution** — Two generic pipelines (`performElementAction` for element-targeted actions, `performPointAction` for coordinate-targeted gestures) handle resolution, interactivity checking, and error reporting. Each `executeXxx` method is a thin closure that feeds the pipeline. TheStash resolves the target, checks interactivity, performs the action, and falls back to TheSafecracker for synthetic touch when accessibility activation fails.
6. **Scroll orchestration** — `executeScroll`, `executeScrollToEdge`, `executeScrollToVisible` (one-shot jump to known position), `executeElementSearch` (iterative page-by-page search for unseen elements). `scroll` and `scrollToEdge` use `resolveScrollTarget` to get the element's stored `screenElement.scrollView` from the accessibility hierarchy. See [04a-SCROLLING.md](04a-SCROLLING.md).
7. **Element matching** — `findMatch(_:)`, `hasMatch(_:)`, `resolveFirstMatch(_:)` search the canonical accessibility hierarchy using `ElementMatcher` predicates with AND semantics and case-insensitive substring matching.
8. **HeistId synthesis** — assigns stable, deterministic `heistId` identifiers directly from `AccessibilityElement` (developer identifier preferred, else synthesized from traits+label; value excluded for stability), with suffix disambiguation for duplicates
9. **Topology-based screen change detection** — detects navigation changes that reuse the same VC by checking back button trait (private `0x8000000`) appearance/disappearance and header label disjointness (`isTopologyChanged`)
10. **Wire conversion at boundary** — `toWire()` converts `ScreenElement` → `HeistElement` only at serialization boundaries (Pulse broadcast, sendInterface, ExploreResult). All internal code operates on `AccessibilityElement`.
11. **Delta computation** — `captureBeforeState()` captures a `BeforeState` token (snapshot + viewport elements + VC identity); after the action, `actionResultWithDelta(before:)` computes the delta through a single codepath for both success and failure. Includes post-action `exploreAndPrune()` so deltas capture off-screen changes.
12. **Container fingerprint caching** — `ContainerExploreState` caches each scrollable container's visible subtree fingerprint, accumulated fingerprint, and discovered heistIds. On re-explore, unchanged containers are skipped via O(1) fingerprint comparison.
13. **Screen capture** — renders traversable windows via `UIGraphicsImageRenderer` (TheStash+Capture.swift)
14. **Resolution diagnostics** — near-miss suggestions, similar heistId hints, compact element summaries (TheStash+Diagnostics.swift)

## Custody Contract

TheStash is the custodian of the live accessibility/UI object world.

- **Exclusive ownership of live object references** — if a subsystem needs to get from a parsed element back to a live `NSObject`, it goes through TheStash
- **Weak references only** — live objects are stored in `ScreenElement.object` and `ScreenElement.scrollView` as `weak` references; TheStash never prolongs the lifetime of app UI objects
- **No exported live handles** — other subsystems should work through Bagman APIs that return values, frames, points, or perform actions on their behalf
- **Parser boundary** — `AccessibilityHierarchyParser` usage belongs to TheStash; TheTripwire handles timing/window observation, and TheSafecracker handles raw gesture synthesis
- **Fail closed on staleness** — if the weak object is gone, TheStash treats it as stale state and re-resolves from a fresh parse instead of pretending the handle is still valid

## Crew Responsibility Boundaries

```mermaid
flowchart LR
    subgraph TheStash ["TheStash (data + dispatch)"]
        direction TB
        B1["Element registry<br/>(screenElements)"]
        B2["Target resolution<br/>(heistId / matcher)"]
        B3["Parse → Apply pipeline"]
        B4["Scroll orchestration<br/>(scroll, scrollToEdge,<br/>scrollToVisible, elementSearch)"]
        B5["Action execution<br/>(activate, increment,<br/>decrement, customAction)"]
        B6["Screen capture<br/>+ recording frames"]
    end

    subgraph TheSafecracker ["TheSafecracker (fingers on glass)"]
        direction TB
        S1["Synthetic touch<br/>(tap, longPress)"]
        S2["Gesture synthesis<br/>(swipe, drag, pinch,<br/>rotate, drawPath)"]
        S3["Scroll primitives<br/>(scrollByPage,<br/>scrollToEdge)"]
        S4["Text entry<br/>(typeText, clearText,<br/>deleteText)"]
        S5["Edit actions<br/>(cut, copy, paste,<br/>selectAll, undo, redo)"]
    end

    B5 -->|"fallback tap"| S1
    B4 -->|"page / edge"| S3
    B1 -.->|"resolves to point"| S2
```

## Architecture Diagram

```mermaid
graph TD
    subgraph TheStash["TheStash (@MainActor, internal)"]
        subgraph Stores["Instance State"]
            Registry["registry.elements: [String: ScreenElement]<br/>Persistent, screen-lifetime"]
            Viewport["registry.viewportIds: Set&lt;String&gt;<br/>Currently visible in device viewport"]
            Hierarchy["currentHierarchy: [AccessibilityHierarchy]<br/>Tree for matchers + scroll discovery"]
            ScrollViews["scrollableContainerViews<br/>[Container: UIView]"]
            ReverseIdx["elementToHeistId: [AccessibilityElement: String]<br/>O(1) matcher → heistId lookup"]
            Hash["lastHierarchyHash: Int"]
            ContainerCache["containerExploreStates<br/>[Container: ContainerExploreState]"]
            ExploreCycle["exploreCycleIds: Set&lt;String&gt;?<br/>Tracks heistIds during explore"]
        end

        subgraph Pipeline["Parse → Apply Pipeline"]
            Parse["parse() → ParseResult<br/>(read-only, no mutation)"]
            Detect["Screen change detection<br/>(before mutation)"]
            Apply["apply(ParseResult)<br/>(mutates registry)"]
            Refresh["refresh() = parse + apply"]
        end

        subgraph Resolution["Element Resolution"]
            ResolveTarget["resolveTarget(_:) → TargetResolution"]
            ResolveFirstMatch["resolveFirstMatch(_:)"]
            HasTarget["hasTarget(_:)"]
        end

        subgraph Wire["Wire Boundary"]
            Select["selectElements(_:) → [ScreenElement]<br/>Pure read, no side effects"]
            Mark["markPresented(_:)<br/>Explicit side effect"]
            ToWire["toWire(_:) → [HeistElement]<br/>Converts at serialization boundary"]
        end

        subgraph Actions["Action Execution (+Actions)"]
            Activate["executeActivate, executeTap,<br/>executeSwipe, executeTypeText, ..."]
        end

        subgraph Scrolling["Scroll Orchestration (+Scroll)"]
            ScrollVis["executeScrollToVisible (one-shot)<br/>executeElementSearch (iterative)"]
            ScrollCmd["executeScroll, executeScrollToEdge"]
        end
    end

    TheInsideJob["TheInsideJob"] --> TheStash
    TheTripwire["TheTripwire"] -.->|injected via init| TheStash
    TheStash -.->|"via ActionExecution/ScrollExecution"| TheSafecracker["TheSafecracker"]
    TheStash -.->|"weak var stakeout"| TheStakeout["TheStakeout"]
```

## Data Flow: Parse → Apply

```mermaid
flowchart TD
    Parse["parse()"] --> PR["ParseResult (value type)<br/>• elements: [AccessibilityElement]<br/>• hierarchy: [AccessibilityHierarchy]<br/>• objects: [AE: NSObject]<br/>• scrollViews: [Container: UIView]"]

    PR --> Detect{"Screen change?<br/>(VC identity OR topology)"}
    Detect -->|Yes| Clear["Clear registry<br/>registry.clearScreen()"]
    Detect -->|No| Apply

    Clear --> Apply["apply(ParseResult)"]
    Apply --> Walk["buildElementContexts()<br/>→ ElementContext per element"]
    Walk --> IDs["assignHeistIds(elements)<br/>→ [String] parallel to elements"]
    IDs --> Upsert["Upsert screenElements<br/>+ build elementToHeistId<br/>+ rebuild viewportHeistIds<br/>+ union into exploreCycleIds"]
```

## Data Flow: Snapshot → Wire

```mermaid
flowchart LR
    Sel["selectElements(.viewport / .all)<br/>(pure read)"] --> SE["[ScreenElement]"]
    SE --> MP["markPresented(_:)<br/>(explicit side effect)"]
    MP -->|"At wire boundary"| TW["toWire() → [HeistElement]"]
    TW --> Interface["Interface payload<br/>(Pulse, sendInterface,<br/>ExploreResult)"]
```

## Action Execution Pipeline

All interactions follow the same pipeline: TheStash resolves the target, executes the action (with optional fallback to TheSafecracker for synthetic touch), then produces a delta.

```mermaid
flowchart TD
    CMD["Client command<br/>(activate, tap, swipe, ...)"] --> DISP["TheInsideJob.dispatchInteraction()"]
    DISP --> SNAP["captureBeforeState()<br/>→ BeforeState token"]
    SNAP --> EXEC["TheStash.executeXxx(target)"]

    EXEC --> ENS["ensureOnScreen(target)<br/>Auto-scroll if element<br/>is off-viewport"]
    ENS --> RES["resolveTarget(target)"]
    RES --> CHK{Resolved?}
    CHK -->|No| ERR["Return .failure<br/>+ diagnostics"]
    CHK -->|Yes| INT{Has interactive<br/>object?}
    INT -->|No| ERR2["Return .failure<br/>'does not support activation'"]
    INT -->|Yes| ACT["Perform action<br/>(accessibilityActivate, increment, etc.)"]
    ACT --> OK{Succeeded?}
    OK -->|Yes| RET["Return InteractionResult"]
    OK -->|No| FALL["Fallback: TheSafecracker.tap()<br/>(synthetic touch at activation point)"]
    FALL --> RET

    RET --> DELTA["actionResultWithDelta(before:)<br/>(parse → detect → apply →<br/>exploreAndPrune → delta)"]
    DELTA --> SEND["Send ActionResult<br/>to client"]
```

## Element Target Resolution

Two resolution strategies: O(1) dictionary lookup for heistIds, predicate search + O(1) reverse index for matchers.

```mermaid
flowchart TD
    A["resolveTarget(ElementTarget)"] --> B{Target type?}
    B -->|".heistId(id)"| C["registry.elements[id]"]
    C --> D{Entry exists?}
    D -->|Yes| E["Return .resolved(ResolvedTarget)"]
    D -->|No| F["Return .notFound(diagnostics)"]

    B -->|".matcher(m, ordinal)"| G{ordinal set?}
    G -->|Yes| ORD["matches(matcher, limit: ordinal+1)<br/>Early-exit collection"]
    ORD --> ORDCHK{ordinal < hits.count?}
    ORDCHK -->|Yes| I["elementToHeistId[element]<br/>→ screenElements[heistId]<br/>(O(1) reverse index)"]
    I --> E
    ORDCHK -->|No| F

    G -->|No| H["matches(matcher, limit: 2)"]
    H --> K{Result?}
    K -->|Exactly 1| I
    K -->|0 matches| F
    K -->|2+ matches| AMB["Return .ambiguous(candidates, diagnostics)<br/>Hint: use ordinal 0–N"]
```

## Post-Action Delta Flow

Screen change detection happens *before* registry mutation — parse returns an immutable value, topology is compared against the old state, then the registry is cleared (if changed) and the new state applied.

```mermaid
flowchart TD
    A["actionResultWithDelta(before:)"] --> B{Action<br/>succeeded?}
    B -->|No| C["Return error ActionResult<br/>(same codepath, errorKind set)"]
    B -->|Yes| D["tripwire.waitForAllClear(1s)"]
    D --> E["parse() → ParseResult<br/>(no mutation yet)"]

    E --> F{Screen change?<br/>VC identity OR topology}
    F -->|Yes| G["Clear registry + containerExploreStates<br/>(before apply)"]
    F -->|No| H["apply(ParseResult)"]
    G --> H

    H --> I["exploreAndPrune()<br/>(fingerprint-cached re-explore)"]
    I --> J["selectElements(.all) + markPresented()"]
    J --> K["computeDelta(before, after)"]
    K --> L["Return ActionResult<br/>with delta + explore stats"]
```

## ScreenElement Structure

```swift
struct ScreenElement {
    let heistId: String
    let contentSpaceOrigin: CGPoint?    // position within scroll container (frozen at creation)
    var element: AccessibilityElement   // updated each refresh when visible
    weak var object: NSObject?          // live UIKit object for actions
    weak var scrollView: UIScrollView?  // parent scroll view (outlives children)
}
```

**5 fields, clear separation:**
- `heistId` and `contentSpaceOrigin` are **immutable identity** — set once when the element is first discovered
- `element`, `object`, `scrollView` are **mutable live state** — updated each refresh when the element is visible

**Lifetime rules:**
- UIKit guarantees the scroll view outlives its children, so if `object != nil` then `scrollView != nil` (when originally set)
- If `object == nil` but `scrollView != nil`, the element was deallocated (cell reuse) but the scroll view is still alive — you can still scroll to its content-space position
- Any element in `registry.elements` is resolvable by heistId — the former `presentedHeistIds` gate has been removed

## Instance State Inventory

| Store | Lifetime | Purpose |
|-------|----------|---------|
| `currentHierarchy` | Refresh | Tree for matcher resolution + scroll target discovery |
| `scrollableContainerViews` | Refresh | Container → UIView for scroll operations |
| `registry.elements` | Screen | The registry — all resolution paths read from here |
| `registry.viewportIds` | Refresh | HeistIds visible in the device viewport |
| `registry.reverseIndex` | Refresh | O(1) reverse index: AccessibilityElement → heistId |
| `lastHierarchyHash` | Screen | Pulse polling dedup memo |
| `lastScreenName` | Screen | First header element label, computed once in `apply()` |
| `lastScreenId` | Screen | Slugified `lastScreenName` (e.g. "controls_demo"), computed alongside it |
| `containerExploreStates` | Screen | Cached fingerprint + heistIds per scrollable container |
| `exploreCycleIds` | Explore cycle | Accumulates heistIds during `exploreAndPrune()`, nil outside |

**Data flows down through two tiers:**
- **Tier 1 (tree)**: `currentHierarchy`, `scrollableContainerViews` — volatile, rebuilt each refresh
- **Tier 2 (registry)**: `registry.elements`, `registry.viewportIds`, `registry.reverseIndex` — persistent, upserted

No store writes to another store. No circular dependencies.

## File Organization

| File | Lines | Responsibility |
|------|-------|----------------|
| `TheStash.swift` | ~800 | Core: ParseResult, parse/apply pipeline, resolution, topology, action result assembly, forwarding accessors |
| `TheStash+Matching.swift` | ~200 | Element matching against ElementMatcher predicates |
| `TheStash+Capture.swift` | ~55 | Screen capture (clean + recording overlay) |
| `TheStash/ActionExecution.swift` | ~420 | Unified pipelines (`performElementAction`, `performPointAction`) + all `executeXxx` methods |
| `TheStash/ScrollExecution.swift` | ~500 | Scroll orchestration, scroll-to-visible (one-shot), element-search (iterative), ensure-on-screen, direction mapping |
| `TheStash/ScreenExploration.swift` | ~170 | Off-screen content discovery; drives scroll-to-explore cycle |
| `TheStash/WireConversion.swift` | ~215 | Caseless enum with static methods: toWire(), delta computation, tree conversion |
| `TheStash/IdAssignment.swift` | ~100 | Caseless enum with static methods: deterministic heistId synthesis from traits/labels |
| `TheStash/ElementRegistry.swift` | ~95 | Element registry storage: elements, viewportIds, reverseIndex |
| `TheStash/Diagnostics.swift` | ~50 | Caseless enum with static methods: resolution error formatting |
| `TheStash/Interactivity.swift` | ~50 | Interactivity predicates (shared by WireConversion and ActionExecution) |
| `TheStash/ScreenManifest.swift` | ~65 | Container exploration bookkeeping |
| `TheStash/ArrayHelpers.swift` | ~45 | [HeistElement] screen name/id helpers |

## Dependencies

- **TheTripwire** (injected via `init(tripwire:)`) — provides window access, timing coordination (`allClear`, `waitForAllClear`), VC identity-based screen change detection, and first responder lookup
- **TheSafecracker** (via ActionExecution and ScrollExecution extensions) — TheStash delegates to TheSafecracker for raw gesture synthesis (fallback tap, scroll primitives, text entry, edit actions)
- **TheStakeout** (`weak var stakeout: TheStakeout?`) — TheStash calls `stakeout?.captureActionFrame()` during action result assembly for recording frame capture
- **AccessibilityHierarchyParser** (from AccessibilitySnapshot submodule) — traverses the accessibility tree with `elementVisitor` and `containerVisitor` closures

## Architectural Rule

If code needs to parse the accessibility hierarchy, hold onto a live accessibility-backed `NSObject`, resolve an element target, or execute an accessibility action, that responsibility belongs to TheStash. TheSafecracker is exclusively "fingers on glass" — it provides raw gesture primitives but never resolves targets or owns element state. Wire types (`HeistElement`) are produced by `toWire()` only at serialization boundaries — all internal code operates on `AccessibilityElement`.

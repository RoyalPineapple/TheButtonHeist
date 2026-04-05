# TheBagman - The Score Handler

> **Files:** `TheBagman.swift`, `TheBagman+Matching.swift`, `TheBagman+Capture.swift`, `Bagman/ActionExecution.swift`, `Bagman/ScrollExecution.swift`, `Bagman/ScreenExploration.swift`, `Bagman/WireConversion.swift`, `Bagman/IdAssignment.swift`, `Bagman/ElementRegistry.swift`, `Bagman/Diagnostics.swift`, `Bagman/Interactivity.swift`, `Bagman/ScreenManifest.swift`, `Bagman/ArrayHelpers.swift`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Owns element registry, hierarchy parsing, target resolution, action execution, scroll orchestration, delta computation, and screen capture

## Responsibilities

TheBagman handles all the goods during TheInsideJob:

1. **Screen-lifetime element registry** — maintains `screenElements: [String: ScreenElement]` keyed by heistId, persistent across refreshes within the same screen
2. **Parse/apply pipeline** — `parse()` reads the live accessibility tree into an immutable `ParseResult` value; `apply()` mutates the registry. Screen change detection happens between these two steps — no mixed old/new state.
3. **Hierarchy parsing** — drives `AccessibilityHierarchyParser` with `elementVisitor` + `containerVisitor` closures to capture element objects and scroll view refs
4. **Target resolution** — `resolveTarget(_:)` is the single entry point: `.heistId` → O(1) dictionary lookup + `presentedHeistIds` gate, `.matcher` → `uniqueMatch` tree walk + O(1) reverse index lookup via `elementToHeistId`. Returns `TargetResolution` enum (`.resolved(ResolvedTarget)`, `.notFound(diagnostics:)`, `.ambiguous(candidates:diagnostics:)`). See [15-UNIFIED-TARGETING.md](15-UNIFIED-TARGETING.md) for the full targeting system.
5. **Action execution** — `executeActivate`, `executeIncrement`, `executeDecrement`, `executeCustomAction`, `executeTap`, `executeSwipe`, `executeTypeText`, etc. TheBagman resolves the target, checks interactivity, performs the action, and falls back to TheSafecracker for synthetic touch when accessibility activation fails.
6. **Scroll orchestration** — `executeScroll`, `executeScrollToEdge`, `executeScrollToVisible`. `scroll` and `scrollToEdge` use `resolveScrollTarget` to get the element's stored `screenElement.scrollView` from the accessibility hierarchy. `scrollToVisible` walks the accessibility hierarchy tree (outermost first via `filteredHierarchy`), scrolls each container with two-tier dispatch (UIScrollView → synthetic swipe), and marks containers exhausted on stagnation. See [04a-SCROLLING.md](04a-SCROLLING.md).
7. **Element matching** — `findMatch(_:)`, `hasMatch(_:)`, `resolveFirstMatch(_:)` search the canonical accessibility hierarchy using `ElementMatcher` predicates with AND semantics and case-insensitive substring matching.
8. **HeistId synthesis** — assigns stable, deterministic `heistId` identifiers directly from `AccessibilityElement` (developer identifier preferred, else synthesized from traits+label; value excluded for stability), with suffix disambiguation for duplicates
9. **Topology-based screen change detection** — detects navigation changes that reuse the same VC by checking back button trait (private `0x8000000`) appearance/disappearance and header label disjointness (`isTopologyChanged`)
10. **Wire conversion at boundary** — `toWire()` converts `ScreenElement` → `HeistElement` only at serialization boundaries (Pulse broadcast, sendInterface, ExploreResult). All internal code operates on `AccessibilityElement`.
11. **Delta computation** — `captureBeforeState()` captures a `BeforeState` token (snapshot + viewport elements + VC identity); after the action, `actionResultWithDelta(before:)` computes the delta through a single codepath for both success and failure. Includes post-action `exploreAndPrune()` so deltas capture off-screen changes.
12. **Container fingerprint caching** — `ContainerExploreState` caches each scrollable container's visible subtree fingerprint, accumulated fingerprint, and discovered heistIds. On re-explore, unchanged containers are skipped via O(1) fingerprint comparison.
13. **Screen capture** — renders traversable windows via `UIGraphicsImageRenderer` (TheBagman+Capture.swift)
14. **Resolution diagnostics** — near-miss suggestions, similar heistId hints, compact element summaries (TheBagman+Diagnostics.swift)

## Custody Contract

TheBagman is the custodian of the live accessibility/UI object world.

- **Exclusive ownership of live object references** — if a subsystem needs to get from a parsed element back to a live `NSObject`, it goes through TheBagman
- **Weak references only** — live objects are stored in `ScreenElement.object` and `ScreenElement.scrollView` as `weak` references; TheBagman never prolongs the lifetime of app UI objects
- **No exported live handles** — other subsystems should work through Bagman APIs that return values, frames, points, or perform actions on their behalf
- **Parser boundary** — `AccessibilityHierarchyParser` usage belongs to TheBagman; TheTripwire handles timing/window observation, and TheSafecracker handles raw gesture synthesis
- **Fail closed on staleness** — if the weak object is gone, TheBagman treats it as stale state and re-resolves from a fresh parse instead of pretending the handle is still valid

## Crew Responsibility Boundaries

```mermaid
flowchart LR
    subgraph TheBagman ["TheBagman (data + dispatch)"]
        direction TB
        B1["Element registry<br/>(screenElements)"]
        B2["Target resolution<br/>(heistId / matcher)"]
        B3["Parse → Apply pipeline"]
        B4["Scroll orchestration<br/>(scroll, scrollToEdge,<br/>scrollToVisible)"]
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
    subgraph TheBagman["TheBagman (@MainActor, internal)"]
        subgraph Stores["Instance State (10 stores)"]
            Registry["screenElements: [String: ScreenElement]<br/>Persistent, screen-lifetime"]
            Viewport["viewportHeistIds: Set&lt;String&gt;<br/>Currently visible in device viewport"]
            Presented["presentedHeistIds: Set&lt;String&gt;<br/>Gate: elements sent to clients"]
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
            ScrollVis["executeScrollToVisible<br/>(hierarchy walk + stagnation)"]
            ScrollCmd["executeScroll, executeScrollToEdge"]
        end
    end

    TheInsideJob["TheInsideJob"] --> TheBagman
    TheTripwire["TheTripwire"] -.->|injected via init| TheBagman
    TheBagman -.->|"via ActionExecution/ScrollExecution"| TheSafecracker["TheSafecracker"]
    TheBagman -.->|"weak var stakeout"| TheStakeout["TheStakeout"]
```

## Data Flow: Parse → Apply

```mermaid
flowchart TD
    Parse["parse()"] --> PR["ParseResult (value type)<br/>• elements: [AccessibilityElement]<br/>• hierarchy: [AccessibilityHierarchy]<br/>• objects: [AE: NSObject]<br/>• scrollViews: [Container: UIView]"]

    PR --> Detect{"Screen change?<br/>(VC identity OR topology)"}
    Detect -->|Yes| Clear["Clear registry<br/>screenElements.removeAll()<br/>presentedHeistIds.removeAll()"]
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

All interactions follow the same pipeline: TheBagman resolves the target, executes the action (with optional fallback to TheSafecracker for synthetic touch), then produces a delta.

```mermaid
flowchart TD
    CMD["Client command<br/>(activate, tap, swipe, ...)"] --> DISP["TheInsideJob.dispatchInteraction()"]
    DISP --> SNAP["captureBeforeState()<br/>→ BeforeState token"]
    SNAP --> EXEC["TheBagman.executeXxx(target)"]

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
    B -->|".heistId(id)"| C["screenElements[id]<br/>+ presentedHeistIds.contains(id)"]
    C --> D{Entry exists<br/>& presented?}
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
- `presentedHeistIds` gates targeting — `resolveTarget(.heistId)` requires the element to have been sent to clients via `markPresented()`

## Instance State Inventory

| Store | Lifetime | Purpose |
|-------|----------|---------|
| `currentHierarchy` | Refresh | Tree for matcher resolution + scroll target discovery |
| `scrollableContainerViews` | Refresh | Container → UIView for scroll operations |
| `screenElements` | Screen | The registry — all resolution paths read from here |
| `viewportHeistIds` | Refresh | HeistIds visible in the device viewport |
| `elementToHeistId` | Refresh | O(1) reverse index: AccessibilityElement → heistId |
| `presentedHeistIds` | Screen | Gate: elements sent to clients. Only `markPresented()` writes it. |
| `lastHierarchyHash` | Screen | Pulse polling dedup memo |
| `lastScreenName` | Screen | First header element label, computed once in `apply()` |
| `lastScreenId` | Screen | Slugified `lastScreenName` (e.g. "controls_demo"), computed alongside it |
| `containerExploreStates` | Screen | Cached fingerprint + heistIds per scrollable container |
| `exploreCycleIds` | Explore cycle | Accumulates heistIds during `exploreAndPrune()`, nil outside |

**Data flows down through three tiers:**
- **Tier 1 (tree)**: `currentHierarchy`, `scrollableContainerViews` — volatile, rebuilt each refresh
- **Tier 2 (registry)**: `screenElements`, `viewportHeistIds`, `elementToHeistId` — persistent, upserted
- **Tier 3 (gate)**: `presentedHeistIds` — append-only within a screen, populated by `markPresented()`

No store writes to another store. No circular dependencies.

## File Organization

| File | Lines | Responsibility |
|------|-------|----------------|
| `TheBagman.swift` | ~300 | Core: ParseResult, parse/apply pipeline, resolution, topology, action result assembly, forwarding accessors |
| `TheBagman+Matching.swift` | ~200 | Element matching against ElementMatcher predicates |
| `TheBagman+Capture.swift` | ~55 | Screen capture (clean + recording overlay) |
| `Bagman/ActionExecutor.swift` | ~420 | All action execution (activate, tap, swipe, type, pinch, etc.) |
| `Bagman/ScrollExecutor.swift` | ~500 | Scroll orchestration, scroll-to-visible, ensure-on-screen, direction mapping |
| `Bagman/ScreenExplorer.swift` | ~170 | Off-screen content discovery; drives scroll-to-explore cycle |
| `Bagman/WireConverter.swift` | ~215 | toWire(), delta computation, tree conversion |
| `Bagman/IdAssigner.swift` | ~100 | Deterministic heistId synthesis from traits/labels |
| `Bagman/ElementRegistry.swift` | ~95 | Element registry storage: screenElements, viewportIds, presentedIds, reverseIndex |
| `Bagman/Diagnostics.swift` | ~50 | Resolution error formatting: near-miss, similar heistIds, compact summary |
| `Bagman/Interactivity.swift` | ~50 | Interactivity predicates (shared by WireConverter and ActionExecutor) |
| `Bagman/ScreenManifest.swift` | ~65 | Container exploration bookkeeping |
| `Bagman/ArrayHelpers.swift` | ~45 | [HeistElement] screen name/id helpers |

## Dependencies

- **TheTripwire** (injected via `init(tripwire:)`) — provides window access, timing coordination (`allClear`, `waitForAllClear`), VC identity-based screen change detection, and first responder lookup
- **TheSafecracker** (via `ActionExecutor` and `ScrollExecutor`) — TheBagman delegates to TheSafecracker for raw gesture synthesis (fallback tap, scroll primitives, text entry, edit actions)
- **TheStakeout** (`weak var stakeout: TheStakeout?`) — TheBagman calls `stakeout?.captureActionFrame()` during action result assembly for recording frame capture
- **AccessibilityHierarchyParser** (from AccessibilitySnapshot submodule) — traverses the accessibility tree with `elementVisitor` and `containerVisitor` closures

## Architectural Rule

If code needs to parse the accessibility hierarchy, hold onto a live accessibility-backed `NSObject`, resolve an element target, or execute an accessibility action, that responsibility belongs to TheBagman. TheSafecracker is exclusively "fingers on glass" — it provides raw gesture primitives but never resolves targets or owns element state. Wire types (`HeistElement`) are produced by `toWire()` only at serialization boundaries — all internal code operates on `AccessibilityElement`.

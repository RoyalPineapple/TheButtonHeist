# TheStash - The Score Handler

> **Files:** `TheStash.swift`, `TheStash+Matching.swift`, `TheStash+Capture.swift`, `TheStash/WireConversion.swift`, `TheStash/IdAssignment.swift`, `TheStash/ElementRegistry.swift`, `TheStash/Diagnostics.swift`, `TheStash/Interactivity.swift`, `TheStash/ScreenManifest.swift`, `TheStash/ArrayHelpers.swift`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Element registry, target resolution, wire conversion, screen capture

## Responsibilities

TheStash holds the goods — pure data, no side effects:

1. **Screen-lifetime element registry** — maintains `screenElements: [String: ScreenElement]` keyed by heistId, persistent across refreshes within the same screen
2. **Target resolution** — `resolveTarget(_:)` is the single entry point: `.heistId` → O(1) dictionary lookup in `registry.elements`, `.matcher` → `uniqueMatch` tree walk + O(1) reverse index lookup via `registry.reverseIndex`. Returns `TargetResolution` enum (`.resolved(ResolvedTarget)`, `.notFound(diagnostics:)`, `.ambiguous(candidates:diagnostics:)`). See [15-UNIFIED-TARGETING.md](15-UNIFIED-TARGETING.md) for the full targeting system.
3. **Element matching** — `findMatch(_:)`, `hasMatch(_:)`, `resolveFirstMatch(_:)` search the canonical accessibility hierarchy using `ElementMatcher` predicates with AND semantics and case-insensitive substring matching.
4. **HeistId synthesis** — `IdAssignment` assigns stable, deterministic `heistId` identifiers directly from `AccessibilityElement` (developer identifier preferred, else synthesized from traits+label; value excluded for stability), with suffix disambiguation for duplicates
5. **Wire conversion at boundary** — `WireConversion.toWire()` converts `ScreenElement` → `HeistElement` only at serialization boundaries (Pulse broadcast, sendInterface, ExploreResult). All internal code operates on `AccessibilityElement`.
6. **Delta computation** — `WireConversion.computeDelta()` computes interface deltas from before/after snapshots
7. **Element actions** — thin wrappers over `accessibilityActivate()`, `accessibilityIncrement()`, `accessibilityDecrement()`, `accessibilityCustomActions` on the live UIKit object
8. **Screen capture** — renders traversable windows via `UIGraphicsImageRenderer` (TheStash+Capture.swift)
9. **Resolution diagnostics** — near-miss suggestions, similar heistId hints, compact element summaries (`Diagnostics`)

**Not TheStash's job** (moved to other crew members):
- Parse pipeline (hierarchy parsing, element context building) → [TheBurglar](13a-THEBURGLAR.md)
- Action execution pipelines, scroll orchestration, delta cycle, explore → [TheBrains](13b-THEBRAINS.md)

## Custody Contract

TheStash is the custodian of the live accessibility/UI object world.

- **Exclusive ownership of live object references** — if a subsystem needs to get from a parsed element back to a live `NSObject`, it goes through TheStash
- **Weak references only** — live objects are stored in `ScreenElement.object` and `ScreenElement.scrollView` as `weak` references; TheStash never prolongs the lifetime of app UI objects
- **No exported live handles** — other subsystems work through TheStash APIs that return values, frames, points, or perform actions on their behalf
- **Parser boundary** — TheBurglar owns `AccessibilityHierarchyParser` usage and populates TheStash via `apply()`
- **Fail closed on staleness** — if the weak object is gone, TheStash treats it as stale state and re-resolves from a fresh parse instead of pretending the handle is still valid

## Crew Responsibility Boundaries

```mermaid
flowchart LR
    subgraph TheBrains ["TheBrains (orchestration)"]
        direction TB
        BR1["Action execution<br/>(activate, increment,<br/>decrement, customAction)"]
        BR2["Scroll orchestration<br/>(scroll, scrollToEdge,<br/>scrollToVisible, elementSearch)"]
        BR3["Delta cycle<br/>(before/after, settle, delta)"]
        BR4["Screen exploration<br/>(exploreAndPrune)"]
    end

    subgraph TheStash ["TheStash (data + resolution)"]
        direction TB
        B1["Element registry<br/>(screenElements)"]
        B2["Target resolution<br/>(heistId / matcher)"]
        B3["Wire conversion<br/>(toWire, computeDelta)"]
        B6["Screen capture<br/>+ recording frames"]
    end

    subgraph TheBurglar ["TheBurglar (acquisition)"]
        direction TB
        BG1["Parse pipeline<br/>(parse → apply)"]
        BG2["Topology detection<br/>(screen change)"]
    end

    subgraph TheSafecracker ["TheSafecracker (fingers on glass)"]
        direction TB
        S1["Synthetic touch<br/>(tap, longPress)"]
        S3["Scroll primitives<br/>(scrollByPage,<br/>scrollToEdge)"]
    end

    BR1 -->|"resolve target"| B2
    BR2 -->|"resolve target"| B2
    BR3 -->|"selectElements"| B1
    BR4 -->|"registry state"| B1
    BG1 -->|"populates"| B1
    BR1 -->|"fallback tap"| S1
    BR2 -->|"page / edge"| S3
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
        end

        subgraph Resolution["Element Resolution"]
            ResolveTarget["resolveTarget(_:) → TargetResolution"]
            ResolveFirstMatch["resolveFirstMatch(_:)"]
            HasTarget["hasTarget(_:)"]
        end

        subgraph Wire["Wire Boundary (static)"]
            ToWire["WireConversion.toWire() → [HeistElement]"]
            Delta["WireConversion.computeDelta()"]
            IDs["IdAssignment.assign() → [String]"]
        end
    end

    TheBurglar["TheBurglar"] -->|"apply(result, to: stash)"| TheStash
    TheBrains["TheBrains"] -->|"resolveTarget, selectElements"| TheStash
    TheInsideJob["TheInsideJob"] --> TheBrains
    TheTripwire["TheTripwire"] -.->|injected via init| TheStash
    TheStash -.->|"weak var stakeout"| TheStakeout["TheStakeout"]
```

## Data Flow: Snapshot → Wire

```mermaid
flowchart LR
    Sel["selectElements()<br/>(pure read)"] --> SE["[ScreenElement]"]
    SE -->|"At wire boundary"| TW["WireConversion.toWire()<br/>→ [HeistElement]"]
    TW --> Interface["Interface payload<br/>(Pulse, sendInterface,<br/>ExploreResult)"]
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
- Any element in `registry.elements` is resolvable by heistId

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

**Data flows down through two tiers:**
- **Tier 1 (tree)**: `currentHierarchy`, `scrollableContainerViews` — volatile, rebuilt each refresh
- **Tier 2 (registry)**: `registry.elements`, `registry.viewportIds`, `registry.reverseIndex` — persistent, upserted

No store writes to another store. No circular dependencies.

## File Organization

| File | Responsibility |
|------|----------------|
| `TheStash.swift` | Core: registry state, resolution, element actions, point/frame resolution, element selection |
| `TheStash+Matching.swift` | Element matching against ElementMatcher predicates |
| `TheStash+Capture.swift` | Screen capture (clean + recording overlay) |
| `TheStash/WireConversion.swift` | Caseless enum with static methods: toWire(), delta computation, tree conversion |
| `TheStash/IdAssignment.swift` | Caseless enum with static methods: deterministic heistId synthesis from traits/labels |
| `TheStash/ElementRegistry.swift` | Element registry storage: elements, viewportIds, reverseIndex |
| `TheStash/Diagnostics.swift` | Caseless enum with static methods: resolution error formatting |
| `TheStash/Interactivity.swift` | Interactivity predicates (shared by WireConversion and ActionExecution) |
| `TheStash/ScreenManifest.swift` | Container exploration bookkeeping |
| `TheStash/ArrayHelpers.swift` | [HeistElement] screen name/id helpers |

## Dependencies

- **TheTripwire** (injected via `init(tripwire:)`) — provides window access for screen capture
- **TheBurglar** (created in `init`) — populates the registry via `apply()`
- **TheStakeout** (`weak var stakeout: TheStakeout?`) — TheStash calls `stakeout?.captureActionFrame()` for recording frame capture

## Architectural Rule

TheStash is pure data — it holds elements, resolves targets, and converts to wire format. It does not orchestrate actions, drive scrolling, or manage the delta cycle. Those responsibilities belong to TheBrains, which coordinates TheStash, TheBurglar, TheSafecracker, and TheTripwire. Wire conversion and ID assignment are static methods on caseless enums (`TheStash.WireConversion`, `TheStash.IdAssignment`) — call them directly, not through instance forwarding.

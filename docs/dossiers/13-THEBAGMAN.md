# TheBagman - The Score Handler

> **Files:** `TheBagman.swift`, `TheBagman+Actions.swift`, `TheBagman+Scroll.swift`, `TheBagman+Conversion.swift`, `TheBagman+Matching.swift`
> **Platform:** iOS 17.0+ (UIKit, DEBUG builds only)
> **Role:** Owns element registry, hierarchy parsing, target resolution, action execution, scroll orchestration, delta computation, and screen capture

## Responsibilities

TheBagman handles all the goods during TheInsideJob:

1. **Screen-lifetime element registry** — maintains `screenElements: [String: ScreenElement]` keyed by heistId, persistent across refreshes within the same screen
2. **Weak object custody** — maps parsed elements to live `NSObject` instances via `elementObjects`, always as weak references
3. **Hierarchy parsing** — drives `AccessibilityHierarchyParser` with `elementVisitor` + `containerVisitor` closures to capture element objects and scroll view refs
4. **Target resolution** — `resolveTarget(_:)` is the single entry point: `.heistId` → O(1) dictionary lookup, `.matcher` → `uniqueMatch` predicate search. Returns `ResolvedTarget(screenElement, element, traversalIndex)`. See [15-UNIFIED-TARGETING.md](15-UNIFIED-TARGETING.md) for the full targeting system.
5. **Action execution** — `executeActivate`, `executeIncrement`, `executeDecrement`, `executeCustomAction`, `executeTap`, `executeSwipe`, `executeTypeText`, etc. TheBagman resolves the target, checks interactivity, performs the action, and falls back to TheSafecracker for synthetic touch when accessibility activation fails.
6. **Scroll orchestration** — `executeScroll`, `executeScrollToEdge`, `executeScrollToVisible` with two-phase bidirectional scan. TheSafecracker provides scroll primitives (`scrollByPage`, `scrollToEdge`); TheBagman drives the search logic.
7. **Element matching** — `findMatch(_:)`, `hasMatch(_:)`, `resolveFirstMatch(_:)` search the canonical accessibility snapshot using `ElementMatcher` predicates with AND semantics and case-insensitive substring matching.
8. **HeistId synthesis** — assigns stable, deterministic `heistId` identifiers to elements (developer identifier preferred, else synthesized from traits+label; value excluded for stability), with suffix disambiguation via content-space position matching for scroll stability
9. **Topology-based screen change detection** — detects navigation changes that reuse the same VC by checking back button trait (private `0x8000000`) appearance/disappearance and header label disjointness (`isTopologyChanged`)
10. **Delta computation** — compares before/after element snapshots to produce `InterfaceDelta` (screen change = VC identity from TheTripwire OR topology change from TheBagman)
11. **Screen capture** — renders traversable windows via `UIGraphicsImageRenderer`
12. **Action result assembly** — orchestrates post-action diffs and frame capture (delegates all timing to TheTripwire's `waitForAllClear`)

## Custody Contract

TheBagman is the custodian of the live accessibility/UI object world.

- **Exclusive ownership of live object references** — if a subsystem needs to get from a parsed element back to a live `NSObject`, it goes through TheBagman
- **Weak references only** — live objects are stored in `ScreenElement.object` and `ScreenElement.scrollView` as `weak` references; TheBagman never prolongs the lifetime of app UI objects
- **No exported live handles** — other subsystems should work through Bagman APIs that return values, frames, points, traversal indices, or perform actions on their behalf
- **Parser boundary** — `AccessibilityHierarchyParser` usage belongs to TheBagman; TheTripwire handles timing/window observation, and TheSafecracker handles raw gesture synthesis
- **Fail closed on staleness** — if the weak object is gone, TheBagman treats it as stale state and re-resolves from a fresh parse instead of pretending the handle is still valid

## Crew Responsibility Boundaries

```mermaid
flowchart LR
    subgraph TheBagman ["TheBagman (data + dispatch)"]
        direction TB
        B1["Element registry<br/>(screenElements)"]
        B2["Target resolution<br/>(heistId / matcher)"]
        B3["Accessibility refresh<br/>(parse → update)"]
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
        Registry["screenElements: [String: ScreenElement]<br/>Persistent, screen-lifetime"]
        OnScreen["onScreen: Set&lt;String&gt;<br/>Currently visible heistIds"]
        Cache["cachedElements: [AccessibilityElement]"]
        Hierarchy["cachedHierarchy: [AccessibilityHierarchy]"]
        WeakRefs["elementObjects: [AccessibilityElement: WeakObject]"]
        Parser["AccessibilityHierarchyParser"]
        Hash["lastHierarchyHash: Int"]
        Tripwire["tripwire: TheTripwire (injected)"]

        subgraph Refresh["Refresh Pipeline"]
            RefreshData["refreshAccessibilityData()"]
            UpdateScreen["updateScreenElements()"]
            WalkHierarchy["walkHierarchy() → ElementContext"]
            RebuildScreen["rebuildScreenElements()"]
            ClearCache["clearCache()"]
        end

        subgraph Resolution["Element Resolution"]
            ResolveTarget["resolveTarget(_: ElementTarget) → ResolvedTarget?"]
            ResolveFirstMatch["resolveFirstMatch(_:) — first-match semantics"]
            HasTarget["hasTarget(_:) — existence check"]
            ResolvePoint["resolvePoint(from:pointX:pointY:)"]
            ResolveFrame["resolveFrame(for:)"]
        end

        subgraph Actions["Action Execution (TheBagman+Actions)"]
            Activate["executeActivate(_:)"]
            Increment["executeIncrement(_:)"]
            Decrement["executeDecrement(_:)"]
            CustomAction["executeCustomAction(_:)"]
            Tap["executeTap(_:)"]
            Swipe["executeSwipe(_:)"]
            TypeText["executeTypeText(_:)"]
        end

        subgraph Scrolling["Scroll Orchestration (TheBagman+Scroll)"]
            Scroll["executeScroll(_:)"]
            ScrollEdge["executeScrollToEdge(_:)"]
            ScrollVisible["executeScrollToVisible(_:)"]
            ScanLoop["scanLoop() — page-by-page search"]
            EnsureOnScreen["ensureOnScreen(for:)"]
        end

        subgraph Conversion["Element Conversion"]
            Snapshot["snapshotElements() → [HeistElement]"]
            Convert["convertElement() → HeistElement"]
            AssignIds["Phase 1-4: heistId assignment + disambiguation"]
        end

        subgraph Delta["Delta Computation"]
            ComputeDelta["computeDelta(before:after:isScreenChange:)"]
            TopoChanged["isTopologyChanged(before:after:)"]
            ActionResult["actionResultWithDelta(...)"]
        end

        subgraph Screen["Screen Capture"]
            CaptureScreen["captureScreen() → (UIImage, CGRect)?"]
            CaptureRecording["captureScreenForRecording() → UIImage?"]
        end
    end

    TheInsideJob["TheInsideJob"] --> TheBagman
    TheTripwire["TheTripwire"] -.->|injected via init| TheBagman
    TheBagman -.->|"weak var safecracker<br/>→ fallback touch + scroll primitives"| TheSafecracker["TheSafecracker"]
    TheBagman -.->|"weak var stakeout → captureActionFrame()"| TheStakeout["TheStakeout"]
```

## Action Execution Pipeline

All interactions follow the same pipeline: TheBagman resolves the target, executes the action (with optional fallback to TheSafecracker for synthetic touch), then produces a delta.

```mermaid
flowchart TD
    CMD["Client command<br/>(activate, tap, swipe, ...)"] --> DISP["TheInsideJob.dispatchInteraction()"]
    DISP --> SNAP["Capture before-snapshot<br/>(snapshotElements + cachedElements + VC identity)"]
    SNAP --> EXEC["TheBagman.executeXxx(target)"]

    EXEC --> ENS["ensureOnScreen(target)<br/>Auto-scroll if element<br/>is off-viewport"]
    ENS --> RES["resolveTarget(target)"]
    RES --> CHK{Resolved?}
    CHK -->|No| ERR["Return .failure<br/>+ elementNotFoundMessage()"]
    CHK -->|Yes| INT{Has interactive<br/>object?}
    INT -->|No| ERR2["Return .failure<br/>'does not support activation'"]
    INT -->|Yes| ACT["Perform action<br/>(accessibilityActivate, increment, etc.)"]
    ACT --> OK{Succeeded?}
    OK -->|Yes| RET["Return InteractionResult"]
    OK -->|No| FALL["Fallback: TheSafecracker.tap()<br/>(synthetic touch at activation point)"]
    FALL --> RET

    RET --> DELTA["actionResultWithDelta()<br/>(see Post-Action Flow)"]
    DELTA --> SEND["Send ActionResult<br/>to client"]
```

## Element Target Resolution

Two resolution strategies: O(1) dictionary lookup for heistIds, predicate search for matchers. Callers use `elementNotFoundMessage()` for tiered diagnostics on nil.

```mermaid
flowchart TD
    A["resolveTarget(ElementTarget)"] --> B{Target type?}
    B -->|".heistId(id)"| C["screenElements[id] lookup"]
    C --> D{Entry exists<br/>& presented<br/>& valid index?}
    D -->|Yes| E["Return ResolvedTarget<br/>(screenElement, element, traversalIndex)"]
    D -->|No| F["Return nil"]

    B -->|".matcher(m)"| G["Build source from<br/>cachedHierarchy"]
    G --> H["uniqueMatch(matcher)<br/>Case-insensitive substring<br/>on label, identifier, value"]
    H --> I{Result?}
    I -->|Exactly 1 match| J["Find matching screenElement<br/>by traversalIndex"]
    J --> E
    I -->|0 or 2+ matches| F

    F -.->|"Caller invokes"| K["elementNotFoundMessage()"]
    K --> T1{"2+ matches?"}
    T1 -->|Yes| L["Tier 1: Ambiguous<br/>List up to 10 candidates"]
    T1 -->|No| T2{"Relaxed predicate<br/>finds match?"}
    T2 -->|Yes| M["Tier 2: Near-miss<br/>'matched all except value —<br/>actual value=7'"]
    T2 -->|No| N["Tier 3: Total miss<br/>Compact summary of all<br/>on-screen elements (cap 20)"]
```

## Accessibility Refresh & Screen Element Update

The core data pipeline. Runs on every interaction cycle and after scroll steps. The `autoreleasepool` per window bounds memory from ObjC accessibility property reads.

```mermaid
flowchart TD
    R["refreshAccessibilityData()"] --> W["tripwire.getTraversableWindows()"]
    W --> LOOP["For each (window, rootView)"]
    LOOP --> AP["autoreleasepool"]
    AP --> PARSE["parser.parseAccessibilityHierarchy()<br/>with elementVisitor + containerVisitor"]
    PARSE --> EV["elementVisitor:<br/>Capture element → WeakObject(NSObject)"]
    PARSE --> CV["containerVisitor:<br/>If .scrollable → store<br/>container → UIScrollView"]
    PARSE --> FLAT["flattenToElements()"]

    EV --> STORE["elementObjects = newElementObjects"]
    CV --> SVL["scrollViewLookup: [Container: UIScrollView]"]
    FLAT --> CACHE["cachedHierarchy + cachedElements"]

    STORE --> USE["updateScreenElements()"]
    SVL --> USE
    CACHE --> USE

    USE --> P1["Phase 1: Assign base heistIds<br/>identifier → use as-is<br/>no identifier → synthesizeBaseId()"]
    P1 --> P2["Phase 2: walkHierarchy()<br/>Derive ElementContext per element:<br/>• contentSpaceOrigin (scrollView.convert)<br/>• parent container<br/>• scrollView weak ref<br/>• object weak ref"]
    P2 --> P3["Phase 3: Disambiguate duplicates<br/>Group by baseId → for each group:<br/>① Match existing suffixes by<br/>   content-space proximity (<2pt)<br/>② Assign new suffixes for unmatched<br/>   (sorted by content-space Y, X)"]
    P3 --> P4["Phase 4: Upsert into screenElements<br/>Existing → update wire, object, scrollView, index<br/>New → insert with presented=false"]
    P4 --> ON["onScreen = visibleThisRefresh"]
```

## Action Result with Delta (Post-Action Flow)

After every interaction, TheBagman waits for the UI to settle, diffs the accessibility tree, and detects screen changes. The delta tells callers exactly what changed.

```mermaid
flowchart TD
    A["actionResultWithDelta()"] --> B{Action<br/>succeeded?}
    B -->|No| C["Return error ActionResult<br/>(errorKind based on method)"]
    B -->|Yes| D["tripwire.waitForAllClear(1s)<br/>(presentation layers settled<br/>+ accessibility tree stable)"]
    D --> E["refreshAccessibilityData()"]

    E --> F{Screen change?}
    F -->|"VC identity changed<br/>OR isTopologyChanged()"| G["Scorched earth:<br/>screenElements.removeAll()<br/>rebuildScreenElements()"]
    F -->|"Same screen"| H["snapshotElements()"]
    G --> H

    H --> I["computeDelta()<br/>(before vs after snapshot)"]
    I --> J["Resolve acted-on element<br/>in post-action state<br/>(label, value, traits)"]
    J --> CAP["captureActionFrame()<br/>(bonus recording frame)"]
    CAP --> K["Return ActionResult<br/>with delta + element state<br/>+ screenName"]
```

## Screen Change Detection

Three-tier detection: VC identity for UIKit navigation, back-button trait for push/pop, header structure for content replacement. Detection is separate from response — `actionResultWithDelta` calls both.

```mermaid
flowchart TD
    SC["Screen change check<br/>(in actionResultWithDelta)"] --> VC["tripwire.isScreenChange()<br/>Compare VC ObjectIdentifier<br/>before vs after"]
    VC --> VCR{VC identity<br/>changed?}
    VCR -->|Yes| YES["Screen change = true"]
    VCR -->|No| TOP["isTopologyChanged()<br/>Compare before/after<br/>AccessibilityElement arrays"]

    TOP --> BB{Back button trait<br/>(bit 27) appeared<br/>or disappeared?}
    BB -->|Yes| YES
    BB -->|No| HD{Header labels<br/>completely replaced?<br/>(disjoint sets)}
    HD -->|Yes| YES
    HD -->|No| NO["Screen change = false"]

    YES --> WIPE["screenElements.removeAll()"]
    WIPE --> REBUILD["rebuildScreenElements()<br/>(re-derive from cached data<br/>without scroll view context)"]
    NO --> KEEP["Keep existing screenElements<br/>(upserted during refresh)"]
```

## Scroll-to-Visible Search Flow

Two-phase scan: scroll in the primary direction, then jump to the opposite edge and scan again. Uses `resolveFirstMatch` (first-match semantics — any match is success, no uniqueness check). Content-size clamp is always disabled (`clampToContentSize: false`) so lazy containers can scroll past the currently-materialized region. Each step settles via `waitForSettle(0.15s, 2 quiet frames)` to let new content render.

```mermaid
flowchart TD
    S["executeScrollToVisible(target)"] --> REF["refreshAccessibilityData()"]
    REF --> CHK{"resolveFirstMatch(target)<br/>Already visible?"}
    CHK -->|Yes| DONE["Return success<br/>(scrollCount: 0)"]
    CHK -->|No| FSV["findFirstScrollView()<br/>(walk onScreen elements<br/>→ scrollableAncestor)"]
    FSV --> SVOK{Found<br/>scroll view?}
    SVOK -->|No| FAIL0["Return failure:<br/>'No scroll view found'"]
    SVOK -->|Yes| PH1["Phase 1: scanLoop()<br/>Primary direction"]

    PH1 --> SLOOP["scrollByPage(animated: false,<br/>clampToContentSize: false)"]
    SLOOP --> SETTLE["waitForSettle(0.15s, 2 quiet frames)"]
    SETTLE --> REFR["refreshAccessibilityData()"]
    REFR --> FM{"resolveFirstMatch(target)"}
    FM -->|Found| END["Return success<br/>+ ScrollSearchResult"]
    FM -->|Not found| NEW{New heistIds<br/>appeared?}
    NEW -->|No new IDs| STALL["Break — content exhausted"]
    NEW -->|Yes| BUDGET{scrollCount<br/>< maxScrolls?}
    BUDGET -->|Yes| SLOOP
    BUDGET -->|No| STALL

    STALL --> PH2["Phase 2: scrollToOppositeEdge()<br/>+ waitForSettle"]
    PH2 --> SCAN2["scanLoop() again<br/>(same direction, remaining budget)"]
    SCAN2 --> RESULT{Found?}
    RESULT -->|Yes| END
    RESULT -->|No| FAILN["Return failure:<br/>'not found after N scrolls'"]
```

## Delta Computation

```mermaid
flowchart TD
    Input["computeDelta(before, after, afterTree, isScreenChange)"]
    Input --> ScreenCheck{isScreenChange?}
    ScreenCheck -->|yes| ScreenChanged[".screenChanged (full new interface)"]
    ScreenCheck -->|no| HashCheck{same hash?}
    HashCheck -->|yes| NoChange[".noChange"]
    HashCheck -->|no| Diff["Compute adds/removes/updates via heistId matching"]
    Diff --> HasChanges{any changes?}
    HasChanges -->|adds, removes, or updates| ElementsChanged[".elementsChanged"]
    HasChanges -->|neither| NoChange
```

Screen change detection uses a two-gate check: TheTripwire's VC identity comparison (primary) OR TheBagman's topology detection (fallback for Workflow-style navigation where the VC is reused). Topology detection checks for back button trait appearance/disappearance and disjoint header labels.

## Screen Capture

Two capture modes:
- **`captureScreen()`** — renders traversable windows bottom-to-top, **excludes** `FingerprintWindow` (clean screenshots)
- **`captureScreenForRecording()`** — renders **all** windows including `FingerprintWindow` (interaction indicators visible in recordings)

Both use `UIGraphicsImageRenderer` with `drawHierarchy(in:afterScreenUpdates:)`.

## ScreenElement Structure

```swift
struct ScreenElement {
    let heistId: String
    let contentSpaceOrigin: CGPoint?    // position within scroll container
    var container: AccessibilityContainer?
    var lastTraversalIndex: Int
    var wire: HeistElement              // updated each refresh
    var presented: Bool                 // true after sent to clients
    weak var object: NSObject?          // live UIKit object for actions
    weak var scrollView: UIScrollView?  // parent scroll view (outlives children)
}
```

**Lifetime rules:**
- UIKit guarantees the scroll view outlives its children, so if `object != nil` then `scrollView != nil` (when originally set)
- If `object == nil` but `scrollView != nil`, the element was deallocated (cell reuse) but the scroll view is still alive — you can still scroll to its content-space position
- `presented` is set to `true` when the element is sent to clients via `get_interface` or delta; `resolveTarget(.heistId)` requires `presented == true`

## Dependencies

- **TheTripwire** (injected via `init(tripwire:)`) — provides window access, timing coordination (`allClear`, `waitForAllClear`), VC identity-based screen change detection, and first responder lookup
- **TheSafecracker** (`weak var safecracker: TheSafecracker?`) — TheBagman calls TheSafecracker for raw gesture synthesis (fallback tap, scroll primitives, text entry, edit actions)
- **TheStakeout** (`weak var stakeout: TheStakeout?`) — TheBagman calls `stakeout?.captureActionFrame()` during action result assembly for recording frame capture
- **AccessibilityHierarchyParser** (from AccessibilitySnapshot submodule) — traverses the accessibility tree with `elementVisitor` and `containerVisitor` closures

## Architectural Rule

If code needs to parse the accessibility hierarchy, hold onto a live accessibility-backed `NSObject`, resolve an element target, or execute an accessibility action, that responsibility belongs to TheBagman. TheSafecracker is exclusively "fingers on glass" — it provides raw gesture primitives but never resolves targets or owns element state.

## Items Flagged for Review

### MEDIUM PRIORITY

**No unit tests for TheBagman**
- Delta computation is pure data transformation — testable without UIKit dependency
- Element resolution and conversion logic could also be unit tested
- HeistId synthesis and suffix disambiguation are deterministic and testable
- Currently untested

### LOW PRIORITY

**Weak object references can go stale**
- `ScreenElement.object` and `ScreenElement.scrollView` hold `weak` references to live objects
- Between refresh and use, an object may be deallocated
- This is handled gracefully (returns nil) but worth knowing

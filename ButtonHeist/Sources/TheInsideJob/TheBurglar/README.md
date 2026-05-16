# TheBurglar

Reads the live accessibility tree and builds a `Screen` value for TheStash to commit. Pure parse → value, no persistent state, no mutation of TheStash from inside the parse.

## The one file

**`TheBurglar.swift`** — `@MainActor final class` with no mutable instance state (stored deps: `AccessibilityHierarchyParser` + `TheTripwire`).

**`parse()`** — the read-only path:
1. `tripwire.getAccessibleWindows()` — top-down window band through the key window.
2. For each window: `parser.parseAccessibilityHierarchy(in: rootView, elementVisitor:, containerVisitor:)`. `elementVisitor` captures `element → object` mappings; `containerVisitor` captures `container → UIView` for scrollable containers and stops parsing lower windows when it sees a modal boundary container.
3. Multi-window: wraps each window's tree in a `.container(semanticGroup)` node with the window class name.
4. Returns `ParseResult(elements:, hierarchy:, objects:, scrollViews:)` — `elements` is the flat traversal-ordered list, `hierarchy` is the tree.

**`buildScreen(from:)`** — the value-producing factory:
1. `buildElementContexts(...)` walks the hierarchy with context propagation (nearest enclosing UIScrollView), computing `contentSpaceOrigin` per element via `scrollView.convert(frame.origin, from: nil)`.
2. `IdAssignment.assign(result.elements)` generates heistIds.
3. Detects first responder by checking `isFirstResponder` on each element's live object.
4. Returns a fresh `Screen` value carrying `elements`, `hierarchy`, `containerStableIds`, `heistIdByElement`, `firstResponderHeistId`, and `scrollableContainerViews`.

Callers decide what to do with the returned `Screen` — assign to `stash.currentScreen` for a fresh snapshot, or merge into a local accumulator during exploration. TheBurglar never reaches into TheStash.

**`isTopologyChanged(before:after:)`** — screen change detection:
- Back-button trait presence change
- Header label set disjointness (both non-empty, no overlap → changed)
- Tab bar content persistence ratio < 0.4 → tab switch detected

**`refresh(into:)`** — convenience that calls `parse()` + `buildScreen(from:)` and assigns the result to `stash.currentScreen`.

> Full dossier: [`docs/dossiers/10-THEBURGLAR.md`](../../../../docs/dossiers/10-THEBURGLAR.md)

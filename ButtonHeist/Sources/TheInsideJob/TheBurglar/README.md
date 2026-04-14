# TheBurglar

Reads the live accessibility tree and populates TheStash's registry. Private implementation detail of TheStash — no external code references TheBurglar directly.

## The one file

**`TheBurglar.swift`** — `@MainActor final class` with no mutable instance state (only the `AccessibilityHierarchyParser`).

**`parse()`** — the read-only path:
1. `tripwire.getAccessibleWindows()` — modal-aware window list
2. `revealHiddenSearchBars()` — temporarily unhides `UISearchController` bars hidden by `hidesSearchBarWhenScrolling`, restores after parsing
3. For each window: `parser.parseAccessibilityHierarchy(in: rootView, elementVisitor:, containerVisitor:)`. The `elementVisitor` captures `element → object` mappings; the `containerVisitor` captures `container → UIView` for scrollable containers.
4. Multi-window: wraps each window's tree in a `.container(semanticGroup)` node with the window class name.
5. Returns `ParseResult(elements:, hierarchy:, objects:, scrollViews:)` — `elements` is the flat traversal-ordered list, `hierarchy` is the tree.

**`apply(_:to:)`** — the mutation path:
1. Sets `stash.currentHierarchy` and `stash.scrollableContainerViews` from the parse result.
2. `buildElementContexts(...)` — walks the hierarchy with context propagation (nearest enclosing UIScrollView), computes `contentSpaceOrigin` per element via `scrollView.convert(frame.origin, from: nil)`.
3. `IdAssignment.assign(result.elements)` — generates heistIds.
4. `stash.registry.apply(parsedElements:heistIds:contexts:)` — upserts into the registry.
5. Detects first responder by checking `isFirstResponder` on each element's live object.
6. Sets `stash.lastScreenName`/`lastScreenId` from the first header-trait element.

**`isTopologyChanged(before:after:)`** — screen change detection:
- Back-button trait presence change
- Header label set disjointness (both non-empty, no overlap → changed)
- Tab bar content persistence ratio < 0.4 → tab switch detected

**`refresh(into:)`** — convenience that calls `parse()` then `apply(_:to:)`.

> Full dossier: [`docs/dossiers/13a-THEBURGLAR.md`](../../../../docs/dossiers/13a-THEBURGLAR.md)

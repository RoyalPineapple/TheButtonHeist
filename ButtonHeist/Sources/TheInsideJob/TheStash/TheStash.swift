#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The stash — holds the goods and answers questions about them.
///
/// TheStash holds the latest committed `Screen` and exposes lookup, matcher
/// resolution, and wire-conversion facades. The persistent element registry
/// is gone — there's exactly one mutable field, `currentScreen`, and a single
/// rule: parse-then-assign. Callers call `parse()` to obtain a Screen value,
/// then decide when to write it back via `currentScreen = ...`. The
/// exploration accumulator lives in TheBrains as a local `var union`.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    // MARK: - Mutable State

    /// The one piece of mutable state — the latest committed screen value.
    ///
    /// **Dual contract — same field, two phases:**
    ///
    /// 1. **Outside an exploration cycle** (and during one, between scrolls)
    ///    `currentScreen` is **page-only**: the result of the most recent
    ///    `parse()`. `heistIds`/`viewportIds` reflect exactly what's on screen
    ///    right now. This is what the settle loop and `scrollOnePageAndSettle`
    ///    termination heuristics need — they compare `stash.viewportIds`
    ///    across frames to detect movement, which only works if the field
    ///    flips with each commit after parse.
    ///
    /// 2. **At the end of `Navigation.exploreAndPrune`** the local `union: Screen`
    ///    accumulator is committed here. The unioned `elements` map now
    ///    includes off-screen heistIds observed during scrolling, but the
    ///    page-only fields (`hierarchy`, `heistIdByElement`,
    ///    `firstResponderHeistId`) still come from the last parse via
    ///    `Screen.merging` semantics. Hence `viewportIds` becomes a superset
    ///    of `liveViewportIds` until the next non-exploration parse.
    ///
    /// **Writer audit** — the call sites that set this field:
    /// - `refresh()` — single parse + commit (page-only)
    /// - `Navigation+Explore.exploreContainer` mid-loop — page-only commits
    ///   per scroll page, required for the termination heuristics above
    /// - `Navigation+Explore.exploreAndPrune` end-of-cycle — union commit
    /// - `clearCache()` / `clearScreen()` — reset to `.empty`
    /// - `TheBrains.actionResultWithDelta` — page-only commit after settle
    ///
    /// Readers that specifically want "what's on screen right now" (vs the
    /// post-exploration union) read `liveViewportIds`, not `viewportIds`.
    var currentScreen: Screen = .empty

    /// Hash of the last hierarchy sent to subscribers (for polling comparison).
    /// Read/written by broadcast paths. Kept as a separate field — it tracks
    /// what was *broadcast*, which is orthogonal to what's *current*.
    var lastHierarchyHash: Int = 0

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Aliases

    typealias ScreenElement = Screen.ScreenElement

    // MARK: - Computed Accessors

    /// Live hierarchy from the most recent parse. Proxy for call-site clarity —
    /// reads, matchers, scroll dispatch, and tab-bar geometry all need it
    /// without spelling out `currentScreen.hierarchy` every time.
    var currentHierarchy: [AccessibilityHierarchy] {
        currentScreen.hierarchy
    }

    /// Scrollable containers paired with their backing UIView.
    /// Unwraps the weak ref wrapper for call sites that need a live UIView.
    var scrollableContainerViews: [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, ref) in currentScreen.scrollableContainerViews {
            if let view = ref.view {
                result[container] = view
            }
        }
        return result
    }

    /// HeistIds of all elements in the current screen value.
    ///
    /// After an exploration commit this includes elements that were observed
    /// during scrolling and are no longer on-screen; after a plain `refresh()`
    /// this is the live viewport. Use `liveViewportIds` when you specifically
    /// need "what's on screen right now".
    var viewportIds: Set<String> {
        heistIds(in: .known)
    }

    /// HeistIds of elements present in the live hierarchy from the most
    /// recent parse — i.e. on-screen right now. Strictly a subset of
    /// `viewportIds` after an exploration union has been committed.
    var liveViewportIds: Set<String> {
        heistIds(in: .visible)
    }

    /// HeistId of the element whose live object is currently first responder.
    var firstResponderHeistId: String? {
        currentScreen.firstResponderHeistId
    }

    /// Screen name from the current screen (first header element by traversal order).
    var lastScreenName: String? {
        currentScreen.name
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    var lastScreenId: String? {
        currentScreen.id
    }

    // MARK: - Element Interactivity

    func isInteractive(element: AccessibilityElement) -> Bool {
        Interactivity.isInteractive(element: element)
    }

    // MARK: - Unified Element Resolution

    /// Result of resolving an ElementTarget to a concrete element.
    struct ResolvedTarget {
        let screenElement: ScreenElement

        var element: AccessibilityElement { screenElement.element }
    }

    /// Which part of the committed interface state a lookup should read.
    enum InterfaceElementScope {
        /// Elements in the live accessibility hierarchy from the most recent parse.
        case visible
        /// Elements retained on the committed screen value, including an exploration union.
        case known
    }

    /// Three-case result from `resolveTarget` — diagnostics are produced
    /// inline during resolution, not via a separate re-scan.
    enum TargetResolution {
        case resolved(ResolvedTarget)
        case notFound(diagnostics: String)
        case ambiguous(candidates: [String], diagnostics: String)

        var resolved: ResolvedTarget? {
            if case .resolved(let resolved) = self { return resolved }
            return nil
        }

        var diagnostics: String {
            switch self {
            case .resolved: return ""
            case .notFound(let message): return message
            case .ambiguous(_, let message): return message
            }
        }
    }

    // MARK: - Element Actions

    func hasInteractiveObject(_ screenElement: ScreenElement) -> Bool {
        Interactivity.isInteractive(element: screenElement.element, object: screenElement.object)
    }

    /// Outcome of `activate(_:)`.
    enum ActivateOutcome {
        case success
        case objectDeallocated
        case refused
    }

    func activate(_ screenElement: ScreenElement) -> ActivateOutcome {
        guard let object = screenElement.object else { return .objectDeallocated }
        return object.accessibilityActivate() ? .success : .refused
    }

    @discardableResult
    func increment(_ screenElement: ScreenElement) -> Bool {
        guard let object = screenElement.object else { return false }
        object.accessibilityIncrement()
        return true
    }

    @discardableResult
    func decrement(_ screenElement: ScreenElement) -> Bool {
        guard let object = screenElement.object else { return false }
        object.accessibilityDecrement()
        return true
    }

    enum CustomActionOutcome {
        case succeeded
        case declined
        case deallocated
        case noSuchAction
    }

    struct LiveGeometry {
        let frame: CGRect
        let activationPoint: CGPoint
        let scrollView: UIScrollView
    }

    /// Jump a recorded element into view by setting its owning scroll view's
    /// content offset to the clamped, centered target.
    @discardableResult
    func jumpToRecordedPosition(_ screenElement: ScreenElement, animated: Bool = true) -> CGPoint? {
        guard let origin = screenElement.contentSpaceOrigin,
              let scrollView = screenElement.scrollView,
              !scrollView.bhIsUnsafeForProgrammaticScrolling else { return nil }
        let savedOffset = scrollView.contentOffset
        let targetOffset = Self.scrollTargetOffset(for: origin, in: scrollView)
        scrollView.setContentOffset(targetOffset, animated: animated)
        return savedOffset
    }

    /// Restore the element's owning scroll view to a previously saved offset.
    func restoreScrollPosition(_ screenElement: ScreenElement, to offset: CGPoint, animated: Bool = true) {
        guard let scrollView = screenElement.scrollView,
              !scrollView.bhIsUnsafeForProgrammaticScrolling else { return }
        scrollView.setContentOffset(offset, animated: animated)
    }

    static func scrollTargetOffset(for contentOrigin: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let visibleSize = scrollView.bounds.size
        let insets = scrollView.adjustedContentInset
        let contentSize = scrollView.contentSize
        let maxX = max(contentSize.width + insets.right - visibleSize.width, -insets.left)
        let maxY = max(contentSize.height + insets.bottom - visibleSize.height, -insets.top)
        let targetX = min(max(contentOrigin.x - visibleSize.width / 2, -insets.left), maxX)
        let targetY = min(max(contentOrigin.y - visibleSize.height / 2, -insets.top), maxY)
        return CGPoint(x: targetX, y: targetY)
    }

    func liveGeometry(for screenElement: ScreenElement) -> LiveGeometry? {
        guard let object = screenElement.object,
              let scrollView = screenElement.scrollView else { return nil }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return nil }
        return LiveGeometry(
            frame: frame,
            activationPoint: object.accessibilityActivationPoint,
            scrollView: scrollView
        )
    }

    func performCustomAction(named name: String, on screenElement: ScreenElement) -> CustomActionOutcome {
        guard let object = screenElement.object else { return .deallocated }
        guard let action = object.accessibilityCustomActions?
            .first(where: { $0.name == name }) else {
            return .noSuchAction
        }
        if let handler = action.actionHandler {
            return handler(action) ? .succeeded : .declined
        }
        if let target = action.target {
            _ = (target as AnyObject).perform(action.selector, with: action)
            return .succeeded
        }
        return .noSuchAction
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    ///
    /// Off-screen behaviour: heistId-targeted lookups are strict. If the id
    /// is not in `currentScreen.elements`, resolution fails with a near-miss
    /// suggestion. There is no fall-back to a previously-seen position.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        switch target {
        case .heistId(let heistId):
            guard let entry = screenElement(heistId: heistId, in: .known) else {
                return .notFound(diagnostics: Diagnostics.heistIdNotFound(
                    heistId,
                    knownIds: currentScreen.elements.keys,
                    viewportCount: currentScreen.elements.count
                ))
            }
            return .resolved(ResolvedTarget(screenElement: entry))
        case .matcher(let matcher, let ordinal):
            return resolveMatcher(matcher, ordinal: ordinal)
        }
    }

    /// HeistIds for either the live hierarchy or the committed known screen.
    func heistIds(in scope: InterfaceElementScope) -> Set<String> {
        switch scope {
        case .visible:
            return Set(currentScreen.heistIdByElement.values)
        case .known:
            return currentScreen.heistIds
        }
    }

    /// Looks up an element by heistId in the selected scope.
    ///
    /// `.known` reads the committed `Screen.elements` map, including any
    /// exploration union. `.visible` only returns ids backed by the latest live
    /// hierarchy parse.
    func screenElement(heistId: String, in scope: InterfaceElementScope) -> ScreenElement? {
        guard let entry = currentScreen.findElement(heistId: heistId) else { return nil }
        switch scope {
        case .visible:
            return currentScreen.heistIdByElement.values.contains(heistId) ? entry : nil
        case .known:
            return entry
        }
    }

    /// Looks up the screen entry for a live accessibility element.
    ///
    /// Because the input is a live element, this first resolves through
    /// `heistIdByElement`. Off-screen known elements cannot be found with this
    /// overload.
    func screenElement(for element: AccessibilityElement, in scope: InterfaceElementScope) -> ScreenElement? {
        guard let heistId = currentScreen.heistIdByElement[element] else { return nil }
        return screenElement(heistId: heistId, in: scope)
    }

    private func resolveMatcher(_ matcher: ElementMatcher, ordinal: Int?) -> TargetResolution {
        if let ordinal {
            guard ordinal >= 0 else {
                return .notFound(diagnostics: "ordinal must be non-negative, got \(ordinal)")
            }
            let matches = matchScreenElements(matcher, limit: ordinal + 1)
            guard ordinal < matches.count else {
                let total = matches.count
                return .notFound(diagnostics: "ordinal \(ordinal) requested but only \(total) match\(total == 1 ? "" : "es") found")
            }
            return .resolved(ResolvedTarget(screenElement: matches[ordinal]))
        }
        let matches = matchScreenElements(matcher, limit: 2)
        switch matches.count {
        case 0:
            return .notFound(diagnostics: matcherNotFoundMessage(matcher))
        case 1:
            return .resolved(ResolvedTarget(screenElement: matches[0]))
        default:
            let capped = matchScreenElements(matcher, limit: 11)
            return ambiguousResolution(matcher, elements: capped.map(\.element))
        }
    }

    /// Resolve a target using first-match semantics (no ambiguity check).
    func resolveFirstMatch(_ target: ElementTarget) -> ResolvedTarget? {
        let effectiveTarget: ElementTarget
        switch target {
        case .heistId:
            effectiveTarget = target
        case .matcher(let matcher, _):
            effectiveTarget = .matcher(matcher, ordinal: 0)
        }
        return resolveTarget(effectiveTarget).resolved
    }

    /// Existence check for wait-style predicates.
    /// Matcher targets are live hierarchy checks; heistIds are known-state checks.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch target {
        case .heistId(let heistId):
            return screenElement(heistId: heistId, in: .known) != nil
        case .matcher(let matcher, _):
            return currentScreen.hierarchy.hasMatch(matcher, mode: .exact)
        }
    }

    func checkElementInteractivity(_ screenElement: ScreenElement) -> InteractivityCheck {
        Interactivity.checkInteractivity(screenElement.element, object: screenElement.object)
    }

    func resolvePoint(
        from elementTarget: ElementTarget?,
        pointX: Double?,
        pointY: Double?
    ) -> PointResolution {
        if let elementTarget {
            let resolution = resolveTarget(elementTarget)
            guard let resolved = resolution.resolved else {
                return .failure(.failure(.elementNotFound, message: resolution.diagnostics))
            }
            return .success(resolved.element.activationPoint)
        } else if let xCoord = pointX, let yCoord = pointY {
            return .success(CGPoint(x: xCoord, y: yCoord))
        } else {
            return .failure(.failure(.elementNotFound, message: "No target specified"))
        }
    }

    func resolveFrame(for elementTarget: ElementTarget) -> CGRect? {
        resolveTarget(elementTarget).resolved?.element.shape.frame
    }

    // MARK: - Traversal Order Index

    /// Build a heistId→traversal-order lookup for diagnostics formatting.
    /// Walks the live hierarchy in DFS order — this matches the order the
    /// agent sees in `get_interface` payloads.
    func buildTraversalOrderIndex() -> [String: Int] {
        var index: [String: Int] = [:]
        var counter = 0
        for (element, _) in currentScreen.hierarchy.elements {
            if let heistId = currentScreen.heistIdByElement[element] {
                index[heistId] = counter
                counter += 1
            }
        }
        return index
    }

    // MARK: - Diagnostics Forwarding

    func matcherNotFoundMessage(_ matcher: ElementMatcher) -> String {
        Diagnostics.matcherNotFound(
            matcher, hierarchy: currentScreen.hierarchy,
            screenElements: selectElements(),
            viewportHeistIds: currentScreen.heistIds,
            traversalOrder: buildTraversalOrderIndex()
        )
    }

    func formatMatcher(_ matcher: ElementMatcher) -> String {
        Diagnostics.formatMatcher(matcher)
    }

    private func ambiguousResolution(
        _ matcher: ElementMatcher,
        elements: [AccessibilityElement]
    ) -> TargetResolution {
        let candidates = elements.prefix(10).map { element -> String in
            var parts: [String] = []
            if let label = element.label, !label.isEmpty { parts.append("\"\(label)\"") }
            if let identifier = element.identifier, !identifier.isEmpty { parts.append("id=\(identifier)") }
            if let value = element.value, !value.isEmpty { parts.append("value=\(value)") }
            return parts.joined(separator: " ")
        }
        let query = formatMatcher(matcher)
        let countLabel = elements.count > 10 ? "10+" : "\(elements.count)"
        let rangeLabel = elements.count > 10 ? "0, 1, 2, ..." : "0–\(elements.count - 1)"
        var lines = ["\(countLabel) elements match: \(query) — use ordinal \(rangeLabel) to select one"]
        lines.append(contentsOf: candidates.map { "  \($0)" })
        if elements.count > 10 {
            lines.append("  ... and more")
        }
        return .ambiguous(candidates: candidates, diagnostics: lines.joined(separator: "\n"))
    }

    // MARK: - Element Selection

    /// All elements in the current screen.
    ///
    /// Live elements appear first in hierarchy (depth-first) traversal order;
    /// any heistIds present in `currentScreen.elements` but not in the live
    /// hierarchy (post-exploration union) appear after, sorted by heistId so
    /// the snapshot order is stable across runs.
    func selectElements() -> [ScreenElement] {
        var seen = Set<String>()
        var ordered: [ScreenElement] = []
        ordered.reserveCapacity(currentScreen.elements.count)
        for (element, _) in currentScreen.hierarchy.elements {
            guard let heistId = currentScreen.heistIdByElement[element],
                  let entry = currentScreen.elements[heistId],
                  seen.insert(heistId).inserted else { continue }
            ordered.append(entry)
        }
        let remaining = currentScreen.elements
            .filter { !seen.contains($0.key) }
            .map(\.value)
            .sorted { $0.heistId < $1.heistId }
        ordered.append(contentsOf: remaining)
        return ordered
    }

    // MARK: - Cache Control

    /// Clear cached element data (used on suspend).
    func clearCache() {
        currentScreen = .empty
        lastHierarchyHash = 0
    }

    /// Clear screen-level state on screen change. Screens are values, so
    /// "clear screen" is identical to "clear everything" — the next parse
    /// produces a fresh screen.
    func clearScreen() {
        currentScreen = .empty
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing.
    private let burglar: TheBurglar

    // MARK: - Parse Pipeline

    /// Read the live accessibility tree and produce a Screen value.
    /// Pure: does not touch `currentScreen`. Returns nil if no accessible
    /// windows exist (loading screen, app backgrounded, etc.).
    func parse() -> Screen? {
        guard let result = burglar.parse() else { return nil }
        return TheBurglar.buildScreen(from: result)
    }

    /// Parse and commit in one step. Most callers use this — exploration
    /// is the one place that wants the value back to merge before committing.
    @discardableResult
    func refresh() -> Screen? {
        guard let screen = parse() else { return nil }
        currentScreen = screen
        return screen
    }

    /// Did the accessibility topology change between two snapshots?
    func isTopologyChanged(
        before: [AccessibilityElement],
        after: [AccessibilityElement],
        beforeHierarchy: [AccessibilityHierarchy],
        afterHierarchy: [AccessibilityHierarchy]
    ) -> Bool {
        burglar.isTopologyChanged(
            before: before, after: after,
            beforeHierarchy: beforeHierarchy, afterHierarchy: afterHierarchy
        )
    }

    // MARK: - Tree Read Helpers

    /// Convert the current screen's hierarchy to canonical wire form. Every
    /// element on screen appears at its tree position; containers carry
    /// stable ids derived once during parse.
    ///
    /// Thin reader over `WireConversion.toWireTree` — exists because callers
    /// need the tree of the *current* screen, not an arbitrary one.
    func wireTree() -> [InterfaceNode] {
        WireConversion.toWireTree(from: currentScreen)
    }

    func wireTreeHash() -> Int {
        wireTree().hashValue
    }

    /// Single-walk variant: returns the tree alongside its hash so callers
    /// that need both (e.g. broadcast-on-change) don't pay for two walks.
    func wireTreeWithHash() -> (tree: [InterfaceNode], hash: Int) {
        let tree = wireTree()
        return (tree, tree.hashValue)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

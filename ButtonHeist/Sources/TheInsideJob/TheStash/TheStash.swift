#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The stash — holds the goods and answers questions about them.
///
/// TheStash is the element registry. It holds every known accessibility element,
/// resolves targets by heistId or matcher, produces wire format, and computes
/// deltas. Pure data — no side effects, no gestures, no scrolling.
/// TheBurglar populates it. TheBrains queries it.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    // MARK: - Volatile State (rebuilt each refresh)

    /// Accessibility hierarchy from the last refresh. Used for matcher resolution,
    /// scroll target discovery, and wire tree construction.
    /// Set by apply(). Tests inject via @testable.
    var currentHierarchy: [AccessibilityHierarchy] = []

    /// Maps scrollable containers from the hierarchy to their backing UIView.
    /// Rebuilt on each accessibility refresh. Check `as? UIScrollView` at point of use.
    var scrollableContainerViews: [AccessibilityContainer: UIView] = [:]

    // MARK: - Screen-Lifetime Element Registry

    /// An element tracked for the current screen's lifetime.
    /// Holds weak references to the live UIKit objects — the element for action dispatch,
    /// the scroll view for coordinate conversion. UIKit guarantees the scroll view outlives
    /// its children, so if `object != nil` then `scrollView != nil` (when originally set).
    /// If `object == nil` but `scrollView != nil`, the element was deallocated (cell reuse)
    /// but the scroll view is still alive — you can still scroll to its content-space position.
    struct ScreenElement {
        let heistId: String
        /// Content-space position within nearest scrollable container (nil if not scrollable).
        var contentSpaceOrigin: CGPoint?
        /// Parsed accessibility element (updated each refresh if element is visible).
        var element: AccessibilityElement
        /// Live UIKit object for action dispatch. Weak — nils on cell reuse.
        weak var object: NSObject?
        /// Parent scroll view for coordinate conversion. Weak — outlives children.
        weak var scrollView: UIScrollView?
    }

    /// The element registry — all known elements, viewport visibility, presentation state.
    var registry = ElementRegistry()

    /// Hash of the last hierarchy sent to subscribers (for polling comparison).
    /// Read/written by Pulse for change detection.
    var lastHierarchyHash: Int = 0

    /// Screen name from the registry (first header element by traversal order).
    /// Computed once in `apply()` from the hierarchy's traversal order.
    var lastScreenName: String?

    /// Slugified screen name for machine use (e.g. "controls_demo").
    /// Computed alongside `lastScreenName` in `apply()`.
    var lastScreenId: String?

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Traversal Order Index

    /// Build a heistId→traversal-order lookup. The registry tree IS the
    /// canonical traversal order — depth-first walk yields elements in
    /// VoiceOver order, with off-screen orphans interleaved by their
    /// content-space Y. Diagnostics still need a `[heistId: Int]` map for
    /// formatting, so we serialize the walk here.
    func buildTraversalOrderIndex() -> [String: Int] {
        let flattened = registry.flattenElements()
        return Dictionary(
            uniqueKeysWithValues: flattened.enumerated().map { ($0.element.heistId, $0.offset) }
        )
    }

    // MARK: - Element Interactivity (forwarded to Interactivity)

    func isInteractive(element: AccessibilityElement) -> Bool {
        Interactivity.isInteractive(element: element)
    }

    // MARK: - Unified Element Resolution

    /// Result of resolving an ElementTarget to a concrete element.
    /// All data lives on `screenElement` — element, wire, spatial, UIKit refs.
    struct ResolvedTarget {
        let screenElement: ScreenElement

        var element: AccessibilityElement { screenElement.element }
    }

    /// Three-case result from `resolveTarget` — diagnostics are produced
    /// inline during resolution, not via a separate re-scan.
    enum TargetResolution {
        case resolved(ResolvedTarget)
        case notFound(diagnostics: String)
        case ambiguous(candidates: [String], diagnostics: String)

        var resolved: ResolvedTarget? {
            if case .resolved(let r) = self { return r }
            return nil
        }

        var diagnostics: String {
            switch self {
            case .resolved: return ""
            case .notFound(let d): return d
            case .ambiguous(_, let d): return d
            }
        }
    }

    // MARK: - Element Actions

    func hasInteractiveObject(_ screenElement: ScreenElement) -> Bool {
        isInteractive(element: screenElement.element)
    }

    /// Outcome of `activate(_:)`. Distinguishes "live object deallocated"
    /// (cell reuse, screen torn down) from "live object refused to activate"
    /// (accessibilityActivate returned false on a non-nil object) so callers
    /// can build precise failure diagnostics.
    enum ActivateOutcome {
        case success
        case objectDeallocated
        case refused
    }

    /// Perform accessibilityActivate, distinguishing deallocated-vs-refused.
    func activate(_ screenElement: ScreenElement) -> ActivateOutcome {
        guard let object = screenElement.object else { return .objectDeallocated }
        return object.accessibilityActivate() ? .success : .refused
    }

    /// Perform accessibilityIncrement.
    @discardableResult
    func increment(_ screenElement: ScreenElement) -> Bool {
        guard let object = screenElement.object else { return false }
        object.accessibilityIncrement()
        return true
    }

    /// Perform accessibilityDecrement.
    @discardableResult
    func decrement(_ screenElement: ScreenElement) -> Bool {
        guard let object = screenElement.object else { return false }
        object.accessibilityDecrement()
        return true
    }

    /// Outcome of a custom-action dispatch.
    ///
    /// Lets callers distinguish "view deallocated before dispatch" from
    /// "view is alive but has no action by that name" without exposing the
    /// underlying NSObject.
    enum CustomActionOutcome {
        case succeeded
        case deallocated
        case noSuchAction
    }

    /// Live geometry derived from the element's backing NSObject.
    ///
    /// Value-typed snapshot so callers can make scroll/viewport decisions
    /// without touching the underlying NSObject. Returned by `liveGeometry(for:)`,
    /// which promotes the weak ref internally.
    struct LiveGeometry {
        let frame: CGRect
        let activationPoint: CGPoint
        let scrollView: UIScrollView
    }

    /// Jump a recorded element into view by setting its owning scroll view's
    /// content offset to the clamped, centered target derived from the
    /// recorded `contentSpaceOrigin`.
    ///
    /// Returns the scroll view's previous content offset so the caller can
    /// revert the jump if the recorded position doesn't produce a usable
    /// match. Returns `nil` if the element has no recorded position, no
    /// owning scroll view, or the scroll view has deallocated.
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
    /// No-op if the scroll view has deallocated.
    func restoreScrollPosition(_ screenElement: ScreenElement, to offset: CGPoint, animated: Bool = true) {
        guard let scrollView = screenElement.scrollView,
              !scrollView.bhIsUnsafeForProgrammaticScrolling else { return }
        scrollView.setContentOffset(offset, animated: animated)
    }

    /// Clamped, centered content offset for a point in scroll-view content space.
    /// Pure math — exposed for testability, used by `jumpToRecordedPosition`.
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

    /// Promote the element's weak object ref to strong, read live geometry,
    /// and pair it with the owning scroll view.
    ///
    /// Returns `nil` if the underlying NSObject has deallocated, the element
    /// has no owning scroll view, or the accessibility frame is null/empty.
    /// Keeps all weak→strong handling inside the stash so callers never touch
    /// the raw NSObject.
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

    /// Perform a named custom action on the element's live object.
    ///
    /// Promotes the weak ref to a local strong ref for the duration of dispatch
    /// so the view cannot deallocate mid-call. Returns `.deallocated` if the
    /// view was already gone, `.noSuchAction` if no matching action exists or
    /// the handler declined, and `.succeeded` otherwise.
    func performCustomAction(named name: String, on screenElement: ScreenElement) -> CustomActionOutcome {
        guard let object = screenElement.object else { return .deallocated }
        guard let action = object.accessibilityCustomActions?
            .first(where: { $0.name == name }) else {
            return .noSuchAction
        }
        if let handler = action.actionHandler {
            return handler(action) ? .succeeded : .noSuchAction
        }
        if let target = action.target {
            _ = (target as AnyObject).perform(action.selector, with: action)
            return .succeeded
        }
        return .noSuchAction
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        switch target {
        case .heistId(let heistId):
            guard let entry = registry.findElement(heistId: heistId) else {
                return .notFound(diagnostics: Diagnostics.heistIdNotFound(
                    heistId, knownIds: registry.elementByHeistId.keys, viewportCount: registry.viewportIds.count
                ))
            }
            return .resolved(ResolvedTarget(screenElement: entry))
        case .matcher(let matcher, let ordinal):
            return resolveMatcher(matcher, ordinal: ordinal)
        }
    }

    /// Single matcher resolution path. Hierarchy-first for traversal order,
    /// registry fallback for off-screen elements, one set of resolution semantics.
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
        // No ordinal — require unique match
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
    /// Used by scroll_to_visible where finding ANY match is success.
    /// Thin wrapper over resolveTarget that forces ordinal 0 for matchers.
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

    /// Live existence check — does any current accessibility-tree element match this target?
    /// Unlike resolveTarget, does NOT require uniqueness for matchers.
    /// For heistId: checks the live viewport set, not the persistent registry.
    /// For matcher: checks currentHierarchy only (not registry). The registry
    /// caches previously-seen elements and would defeat wait_for absent checks.
    /// Uses the same exact-or-miss semantics as `resolveTarget` so wait_for
    /// presence/absence and `activate` agree about what's on screen.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch target {
        case .heistId(let heistId):
            return registry.viewportIds.contains(heistId)
        case .matcher(let matcher, _):
            return currentHierarchy.hasMatch(matcher, mode: .exact)
        }
    }

    func checkElementInteractivity(_ element: AccessibilityElement) -> InteractivityCheck {
        Interactivity.checkInteractivity(element)
    }

    /// Resolve a screen point from an element target or explicit coordinates.
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
        } else if let x = pointX, let y = pointY {
            return .success(CGPoint(x: x, y: y))
        } else {
            return .failure(.failure(.elementNotFound, message: "No target specified"))
        }
    }

    /// Resolve the accessibility frame for an element target.
    func resolveFrame(for elementTarget: ElementTarget) -> CGRect? {
        resolveTarget(elementTarget).resolved?.element.shape.frame
    }

    // MARK: - Diagnostics Forwarding

    func matcherNotFoundMessage(_ matcher: ElementMatcher) -> String {
        Diagnostics.matcherNotFound(
            matcher, hierarchy: currentHierarchy,
            screenElements: registry.flattenElements(),
            viewportHeistIds: registry.viewportIds,
            traversalOrder: buildTraversalOrderIndex()
        )
    }

    func formatMatcher(_ matcher: ElementMatcher) -> String {
        Diagnostics.formatMatcher(matcher)
    }

    /// Build an ambiguous resolution from a list of matching elements.
    /// Shared by both hierarchy and registry matcher paths.
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

    /// All elements in the registry, in tree (depth-first) order. The tree
    /// itself encodes traversal order — visible elements in their incoming
    /// order, off-screen elements interleaved with their last-known siblings
    /// by content-space Y for scrollable containers.
    func selectElements() -> [ScreenElement] {
        registry.flattenElements()
    }

    // MARK: - Refresh Pipeline

    /// Clear all cached element data (used on suspend).
    func clearCache() {
        currentHierarchy.removeAll()
        registry.clear()
        lastHierarchyHash = 0
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing and populating the registry.
    private let burglar: TheBurglar

    // MARK: - Parse Pipeline

    /// Parsed accessibility snapshot. Opaque to callers — TheBurglar is an
    /// implementation detail of TheStash.
    typealias ParseResult = TheBurglar.ParseResult

    /// Parse and apply in one step. Most callers use this.
    @discardableResult
    func refresh() -> ParseResult? {
        burglar.refresh(into: self)
    }

    /// Read the live accessibility tree without mutating state.
    func parse() -> ParseResult? {
        burglar.parse()
    }

    /// Apply a parse result to the registry. Returns assigned heistIds.
    @discardableResult
    func apply(_ result: ParseResult) -> [String] {
        burglar.apply(result, to: self)
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

    // MARK: - Wire Conversion Facades

    /// Convert a snapshot to wire format.
    func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
        WireConversion.toWire(entries)
    }

    /// Convert a single element to wire format.
    func toWire(_ entry: ScreenElement) -> HeistElement {
        WireConversion.toWire(entry)
    }

    /// Convert the persistent registry tree to its canonical wire form.
    func wireTree() -> [InterfaceNode] {
        WireConversion.toWireTree(registry.roots)
    }

    /// Hash of the canonical wire tree, including container topology and
    /// metadata as well as leaf element payloads.
    func wireTreeHash() -> Int {
        wireTree().hashValue
    }

    /// Compute the delta between two snapshots.
    func computeDelta(
        before: [ScreenElement],
        after: [ScreenElement],
        beforeTree: [InterfaceNode]? = nil,
        beforeTreeHash: Int? = nil,
        isScreenChange: Bool
    ) -> InterfaceDelta {
        WireConversion.computeDelta(
            before: before, after: after,
            beforeTree: beforeTree,
            beforeTreeHash: beforeTreeHash,
            afterTree: registry.roots, isScreenChange: isScreenChange
        )
    }

    /// Get trait names for a trait bitmask.
    func traitNames(_ traits: UIAccessibilityTraits) -> [HeistTrait] {
        WireConversion.traitNames(traits)
    }

}

#endif // DEBUG
#endif // canImport(UIKit)

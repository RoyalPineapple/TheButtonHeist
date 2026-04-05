#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

/// The crew member who holds and protects the mcguffin (the live UI/accessibility world).
///
/// TheBagman owns the accessibility data lifecycle: reading the UI, storing
/// element references, computing diffs, and capturing visual state. Live
/// object pointers are kept only as weak references and should never be owned
/// outside TheBagman. Uses TheTripwire for timing
/// signals (when to read) and screen change detection (what kind of read).
@MainActor
final class TheBagman {

    /// The gesture engine. Created and owned by TheBagman.
    /// TheSafecracker is pure "fingers on glass" — it acts on resolved
    /// coordinates and objects, never queries the registry.
    let safecracker = TheSafecracker()

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
        self.safecracker.tripwire = tripwire
    }

    // MARK: - Volatile State (rebuilt each refresh)

    /// Accessibility hierarchy from the last refresh. Used for matcher resolution
    /// (uniqueMatch tree walk), scroll target discovery, and wire tree construction.
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
        let contentSpaceOrigin: CGPoint?
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

    /// Accumulates every heistId seen during an explore cycle.
    /// Populated by `apply()` when non-nil, pruned by `pruneAfterExplore()`.
    /// nil outside of an explore cycle — `apply()` only accumulates when this is set.
    var exploreCycleIds: Set<String>?

    /// Cached state from the last explore of each scrollable container.
    var containerExploreStates: [AccessibilityContainer: ContainerExploreState] = [:]

    /// Screen name from the registry (first header element by traversal order).
    /// Computed once in `apply()` from the hierarchy's traversal order.
    var lastScreenName: String?

    /// Slugified screen name for machine use (e.g. "controls_demo").
    /// Computed alongside `lastScreenName` in `apply()`.
    var lastScreenId: String?

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Traversal Order Index

    /// Build a heistId→traversal-order lookup from the current hierarchy.
    /// Elements discovered via scroll exploration but not in the current viewport
    /// won't appear in currentHierarchy — they get Int.max.
    func buildTraversalOrderIndex() -> [String: Int] {
        let reverseIndex = registry.reverseIndex
        return Dictionary(
            currentHierarchy.compactMap { element, traversalIndex in
                reverseIndex[element].map { ($0, traversalIndex) }
            },
            uniquingKeysWith: { _, latest in latest }
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

    /// Check if the element supports interaction.
    func hasInteractiveObject(_ screenElement: ScreenElement) -> Bool {
        isInteractive(element: screenElement.element)
    }

    /// Perform accessibilityActivate.
    func activate(_ screenElement: ScreenElement) -> Bool {
        screenElement.object?.accessibilityActivate() ?? false
    }

    /// Perform accessibilityIncrement.
    func increment(_ screenElement: ScreenElement) {
        screenElement.object?.accessibilityIncrement()
    }

    /// Perform accessibilityDecrement.
    func decrement(_ screenElement: ScreenElement) {
        screenElement.object?.accessibilityDecrement()
    }

    /// Perform a named custom action.
    func performCustomAction(named name: String, on screenElement: ScreenElement) -> Bool {
        guard let actions = screenElement.object?.accessibilityCustomActions,
              let action = actions.first(where: { $0.name == name }) else {
            return false
        }
        if let handler = action.actionHandler {
            return handler(action)
        }
        if let target = action.target {
            _ = (target as AnyObject).perform(action.selector, with: action)
            return true
        }
        return false
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        switch target {
        case .heistId(let heistId):
            guard let entry = registry.elements[heistId] else {
                return .notFound(diagnostics: Diagnostics.heistIdNotFound(
                    heistId, knownIds: registry.elements.keys, viewportCount: registry.viewportIds.count
                ))
            }
            return .resolved(ResolvedTarget(screenElement: entry))
        case .matcher(let matcher, let ordinal):
            let source = currentHierarchy
            if let ordinal {
                guard ordinal >= 0 else {
                    return .notFound(diagnostics: "ordinal must be non-negative, got \(ordinal)")
                }
                // Ordinal selection: collect matches up to ordinal+1, return the Nth
                let hits = source.matches(matcher, limit: ordinal + 1)
                guard ordinal < hits.count else {
                    let total = hits.count
                    return .notFound(diagnostics: "ordinal \(ordinal) requested but only \(total) match\(total == 1 ? "" : "es") found")
                }
                let selected = hits[ordinal]
                if let heistId = registry.reverseIndex[selected.element],
                   let screenElement = registry.elements[heistId] {
                    return .resolved(ResolvedTarget(screenElement: screenElement))
                }
                return .notFound(diagnostics: matcherNotFoundMessage(matcher))
            }
            // No ordinal — require unique match
            let hits = source.matches(matcher, limit: 2)
            if hits.count == 1 {
                if let heistId = registry.reverseIndex[hits[0].element],
                   let screenElement = registry.elements[heistId] {
                    return .resolved(ResolvedTarget(screenElement: screenElement))
                }
                return .notFound(diagnostics: matcherNotFoundMessage(matcher))
            }
            if hits.count > 1 {
                // Cap at 11 to avoid a full tree scan — we show 10 candidates
                // and indicate "more" if the 11th exists
                let capped = source.matches(matcher, limit: 11)
                let candidates = capped.prefix(10).map { match -> String in
                    var parts: [String] = []
                    if let label = match.element.label, !label.isEmpty { parts.append("\"\(label)\"") }
                    if let id = match.element.identifier, !id.isEmpty { parts.append("id=\(id)") }
                    if let val = match.element.value, !val.isEmpty { parts.append("value=\(val)") }
                    return parts.joined(separator: " ")
                }
                let query = formatMatcher(matcher)
                let countLabel = capped.count > 10 ? "10+" : "\(capped.count)"
                let rangeLabel = capped.count > 10 ? "0, 1, 2, ..." : "0–\(capped.count - 1)"
                var lines = ["\(countLabel) elements match: \(query) — use ordinal \(rangeLabel) to select one"]
                lines.append(contentsOf: candidates.map { "  \($0)" })
                if capped.count > 10 {
                    lines.append("  ... and more")
                }
                return .ambiguous(candidates: candidates, diagnostics: lines.joined(separator: "\n"))
            }
            return .notFound(diagnostics: matcherNotFoundMessage(matcher))
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

    /// Existence check — does any element match this target?
    /// Unlike resolveTarget, does NOT require uniqueness for matchers.
    /// For heistId: checks registry.elements.
    /// For matcher: checks currentHierarchy.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch target {
        case .heistId(let heistId):
            return registry.elements[heistId] != nil
        case .matcher(let matcher, _):
            return hasMatch(matcher)
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
    ) -> TheSafecracker.PointResolution {
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

    func heistIdNotFoundMessage(_ heistId: String) -> String {
        Diagnostics.heistIdNotFound(heistId, knownIds: registry.elements.keys, viewportCount: registry.viewportIds.count)
    }

    func matcherNotFoundMessage(_ matcher: ElementMatcher) -> String {
        Diagnostics.matcherNotFound(
            matcher, hierarchy: currentHierarchy,
            screenElements: registry.elements, viewportHeistIds: registry.viewportIds,
            traversalOrder: buildTraversalOrderIndex()
        )
    }

    func formatMatcher(_ matcher: ElementMatcher) -> String {
        Diagnostics.formatMatcher(matcher)
    }

    // MARK: - Wire Conversion Forwarding

    func traitNames(_ traits: UIAccessibilityTraits) -> [HeistTrait] {
        WireConversion.traitNames(traits)
    }

    func convertElement(_ element: AccessibilityElement) -> HeistElement {
        WireConversion.convert(element)
    }

    func toWire(_ entry: ScreenElement) -> HeistElement {
        WireConversion.toWire(entry)
    }

    func toWire(_ entries: [ScreenElement]) -> [HeistElement] {
        WireConversion.toWire(entries)
    }

    func convertHierarchyNode(_ node: AccessibilityHierarchy) -> ElementNode {
        WireConversion.convertNode(node)
    }

    func computeDelta(
        before: [ScreenElement],
        after: [ScreenElement],
        afterTree: [AccessibilityHierarchy]?,
        isScreenChange: Bool
    ) -> InterfaceDelta {
        WireConversion.computeDelta(before: before, after: after, afterTree: afterTree, isScreenChange: isScreenChange)
    }

    // MARK: - Id Assignment Forwarding

    func assignHeistIds(_ elements: [AccessibilityElement]) -> [String] {
        IdAssignment.assign(elements)
    }

    func synthesizeBaseId(_ element: AccessibilityElement) -> String {
        IdAssignment.synthesizeBaseId(element)
    }

    func stripTraitPrefix(_ text: String?, traitPrefix: String) -> String? {
        IdAssignment.stripTraitPrefix(text, traitPrefix: traitPrefix)
    }

    func slugify(_ text: String?) -> String? {
        IdAssignment.slugify(text)
    }

    // MARK: - Element Selection

    /// All elements in the registry, sorted by traversal order.
    /// Off-screen elements (Int.max) sort to the end, with heistId as tiebreaker.
    func selectElements() -> [ScreenElement] {
        let orderByHeistId = buildTraversalOrderIndex()
        return registry.elements.values
            .sorted {
                let orderA = orderByHeistId[$0.heistId] ?? Int.max
                let orderB = orderByHeistId[$1.heistId] ?? Int.max
                if orderA != orderB { return orderA < orderB }
                return $0.heistId < $1.heistId
            }
    }

    // MARK: - Refresh Pipeline

    /// Clear all cached element data (used on suspend).
    func clearCache() {
        currentHierarchy.removeAll()
        registry.clear()
        containerExploreStates.removeAll()
        exploreCycleIds = nil
        lastHierarchyHash = 0
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    /// TheBurglar handles parsing and populating the registry.
    let burglar: TheBurglar

    /// Convenience: parse and apply in one step via TheBurglar.
    @discardableResult
    func refresh() -> TheBurglar.ParseResult? {
        burglar.refresh(into: self)
    }

    // MARK: - Action Result with Delta

    /// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
    /// Waits for all animations (UIKit and SwiftUI) to settle via presentation layer diffing,
    /// then polls for accessibility tree stability as a safety net.
    ///
    /// State captured before an action for delta computation.
    struct BeforeState {
        let snapshot: [ScreenElement]
        let elements: [AccessibilityElement]
        let viewController: ObjectIdentifier?
    }

    /// Capture the current state for delta computation before an action.
    /// Caller must have called `refresh()` already this frame.
    /// Pure read — does not mutate state or mark elements as presented.
    func captureBeforeState() -> BeforeState {
        BeforeState(
            snapshot: selectElements(),
            elements: currentHierarchy.sortedElements,
            viewController: tripwire.topmostViewController().map(ObjectIdentifier.init)
        )
    }

    /// Screen change detection is three-tier:
    /// 1. VC identity — UIKit navigation (push/pop, modal present/dismiss)
    /// 2. Back button trait — private trait bit 27 appeared/disappeared
    /// 3. Header structure — the set of header labels changed completely
    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        errorKind: ErrorKind? = nil,
        before: BeforeState,
        target: ElementTarget? = nil
    ) async -> ActionResult {
        guard success else {
            let kind = errorKind
                ?? ((method == .elementNotFound || method == .elementDeallocated)
                    ? .elementNotFound : .actionFailed)
            return ActionResult(success: false, method: method, message: message, errorKind: kind,
                                value: value, screenName: before.snapshot.screenName,
                                screenId: before.snapshot.screenId)
        }

        // Wait for all clear: presentation layers settled AND accessibility tree stable.
        let start = CFAbsoluteTimeGetCurrent()
        let settled = await tripwire.waitForAllClear(timeout: 1.0)
        let settleMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        insideJobLogger.info("Post-action settle: \(settled ? "all clear" : "timed out") in \(settleMs)ms")

        // Parse without mutating — detect screen change before touching the registry.
        let afterResult = burglar.parse()

        // Screen change gate: VC identity OR accessibility topology
        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let isScreenChange = tripwire.isScreenChange(before: before.viewController, after: afterVC)
            || burglar.isTopologyChanged(before: before.elements, after: afterResult?.elements ?? [])
        if isScreenChange {
            // Clear the old screen's registry before applying new data.
            // No mixed state — the old registry is gone before new entries arrive.
            registry.clearScreen()
            containerExploreStates.removeAll()
        }
        if let afterResult {
            burglar.apply(afterResult, to: self)
        }

        // Run a full explore after every action so the delta captures off-screen changes.
        // Container fingerprint caching makes this near-instant when nothing changed —
        // the O(1) contentSize + visible-fingerprint check skips unchanged containers.
        // On screen change the cache was just cleared, so every container gets explored.
        let manifest = await exploreAndPrune()
        let afterSnapshot = selectElements()

        let delta = WireConversion.computeDelta(
            before: before.snapshot, after: afterSnapshot,
            afterTree: afterResult?.hierarchy, isScreenChange: isScreenChange
        )

        // Diagnostics only — elements ride on the delta, not duplicated here.
        let exploreResult = ExploreResult(
            elements: [],
            scrollCount: manifest.scrollCount,
            containersExplored: manifest.exploredContainers.count,
            explorationTime: manifest.explorationTime
        )

        // Capture a recording frame after the action completes
        captureActionFrame()

        // Look up the acted-on element in the post-action parsed hierarchy
        var elementLabel: String?
        var elementValue: String?
        var elementTraits: [HeistTrait]?
        if let target {
            let postElement = resolveTarget(target).resolved?.element
            elementLabel = postElement?.label
            elementValue = postElement?.value
            if let traits = postElement?.traits {
                elementTraits = WireConversion.traitNames(traits)
            }
        }

        return ActionResult(
            success: true,
            method: method,
            message: message,
            value: value,
            interfaceDelta: delta,
            elementLabel: elementLabel,
            elementValue: elementValue,
            elementTraits: elementTraits,
            screenName: afterSnapshot.screenName,
            screenId: afterSnapshot.screenId,
            exploreResult: exploreResult
        )
    }
}

// MARK: - Hosting View for Single-Object Parsing

/// Lightweight UIView that presents a single NSObject to the accessibility
/// hierarchy parser. Follows the same pattern as SwiftUI's hosting view —
/// the parser takes a UIView root, so this bridges arbitrary NSObjects
/// (accessibility elements, SwiftUI nodes, etc.) into the parser's pipeline.
final class ButtonHeistHostingView: UIView {
    private let target: NSObject

    init(target: NSObject) {
        self.target = target
        super.init(frame: .zero)
        isAccessibilityElement = false
        accessibilityElements = [target]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

#endif // DEBUG
#endif // canImport(UIKit)

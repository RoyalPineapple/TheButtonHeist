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

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    /// Back-reference to the gesture engine. TheBagman drives TheSafecracker
    /// for synthetic touch when accessibility activation fails.
    weak var safecracker: TheSafecracker?

    // MARK: - Parse Result

    /// Everything the parser produces in a single read. Value type — no mutation,
    /// no instance state. Created by `parse()`, consumed by `apply(_:)`.
    struct ParseResult {
        let elements: [AccessibilityElement]
        let hierarchy: [AccessibilityHierarchy]
        let objects: [AccessibilityElement: NSObject]
        let scrollViews: [AccessibilityContainer: UIView]
    }

    // MARK: - Volatile State (rebuilt each refresh)

    /// Accessibility hierarchy from the last refresh. Used for matcher resolution
    /// (uniqueMatch tree walk), scroll target discovery, and wire tree construction.
    /// Set by apply(). Tests inject via @testable.
    var currentHierarchy: [AccessibilityHierarchy] = []

    /// Maps scrollable containers from the hierarchy to their backing UIView.
    /// Rebuilt on each accessibility refresh. Check `as? UIScrollView` at point of use.
    private(set) var scrollableContainerViews: [AccessibilityContainer: UIView] = [:]

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

    /// Which elements have been sent to clients. Checked by resolveTarget to prevent
    /// targeting elements the caller hasn't seen. Populated by snapshot(_:) — the single
    /// path through which elements leave TheBagman.
    var presentedHeistIds: Set<String> = []

    /// Scope for snapshot: visible (current screen) or all (full scan census).
    enum SnapshotScope {
        case visible
        case all
    }

    /// Persistent element registry keyed by heistId. Lives for the screen's duration.
    /// Populated during apply(), cleared on screen change.
    /// TheBagman-only: mutated by extensions across files. Tests inject via @testable.
    var screenElements: [String: ScreenElement] = [:]

    /// HeistIds currently on screen — rebuilt each refresh cycle.
    /// Elements in screenElements but not in this set have scrolled off screen.
    /// TheBagman-only: mutated by extensions across files.
    var onScreen: Set<String> = []

    /// Reverse index: traversal order → heistId for the current visible set.
    /// Rebuilt each refresh in apply(). Enables O(1) matcher resolution and sort ordering.
    var heistIdByTraversalOrder: [Int: String] = [:]

    /// Hash of the last hierarchy sent to subscribers (for polling comparison).
    /// Read/written by Pulse for change detection.
    var lastHierarchyHash: Int = 0

    /// Screen name from the registry (first header element by traversal order).
    /// Computed once in `apply()` — avoids sorting heistIdByTraversalOrder on every access.
    private(set) var lastScreenName: String?

    private let parser = AccessibilityHierarchyParser()

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Element Interactivity (object-based)

    /// Check if an element is interactive given its parsed data and live object.
    func isInteractive(element: AccessibilityElement, object: NSObject?) -> Bool {
        guard let object else { return false }
        return element.respondsToUserInteraction
            || element.traits.contains(.adjustable)
            || !element.customActions.isEmpty
            || object.accessibilityRespondsToUserInteraction
    }

    /// Return custom action names from a live NSObject.
    func customActionNames(from object: NSObject?) -> [String] {
        object?.accessibilityCustomActions?.map { $0.name } ?? []
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
        isInteractive(element: screenElement.element, object: screenElement.object)
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
        guard let actions = screenElement.object?.accessibilityCustomActions else {
            return false
        }
        for action in actions where action.name == name {
            if let handler = action.actionHandler {
                return handler(action)
            }
            if let target = action.target {
                _ = (target as AnyObject).perform(action.selector, with: action)
                return true
            }
        }
        return false
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        switch target {
        case .heistId(let heistId):
            guard let entry = screenElements[heistId], presentedHeistIds.contains(heistId) else {
                return .notFound(diagnostics: heistIdNotFoundMessage(heistId))
            }
            return .resolved(ResolvedTarget(screenElement: entry))
        case .matcher(let matcher):
            let source = currentHierarchy
            if let unique = source.uniqueMatch(matcher) {
                if let heistId = heistIdByTraversalOrder[unique.traversalIndex],
                   let screenElement = screenElements[heistId] {
                    return .resolved(ResolvedTarget(screenElement: screenElement))
                }
                return .notFound(diagnostics: matcherNotFoundMessage(matcher))
            }
            // uniqueMatch failed — check if ambiguous or truly not found
            let allHits = source.allMatches(matcher)
            if allHits.count > 1 {
                let candidates = allHits.prefix(10).map { match -> String in
                    var parts: [String] = []
                    if let label = match.element.label, !label.isEmpty { parts.append("\"\(label)\"") }
                    if let id = match.element.identifier, !id.isEmpty { parts.append("id=\(id)") }
                    if let val = match.element.value, !val.isEmpty { parts.append("value=\(val)") }
                    return parts.joined(separator: " ")
                }
                let query = formatMatcher(matcher)
                var lines = ["\(allHits.count) elements match: \(query)"]
                lines.append(contentsOf: candidates.map { "  \($0)" })
                if allHits.count > 10 {
                    lines.append("  ... and \(allHits.count - 10) more")
                }
                return .ambiguous(candidates: candidates, diagnostics: lines.joined(separator: "\n"))
            }
            return .notFound(diagnostics: matcherNotFoundMessage(matcher))
        }
    }

    /// Resolve a target using first-match semantics (no ambiguity check).
    /// Used by scroll_to_visible where finding ANY match is success.
    func resolveFirstMatch(_ target: ElementTarget) -> ResolvedTarget? {
        switch target {
        case .heistId(let heistId):
            guard let entry = screenElements[heistId], presentedHeistIds.contains(heistId) else { return nil }
            return ResolvedTarget(screenElement: entry)
        case .matcher(let matcher):
            guard let found = findMatch(matcher) else { return nil }
            guard let heistId = heistIdByTraversalOrder[found.index],
                  let screenElement = screenElements[heistId] else { return nil }
            return ResolvedTarget(screenElement: screenElement)
        }
    }

    /// Existence check — does any element match this target?
    /// Unlike resolveTarget, does NOT require uniqueness for matchers.
    /// For heistId: checks presentedHeistIds (elements sent to clients).
    /// For matcher: checks currentHierarchy.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch target {
        case .heistId(let heistId):
            return presentedHeistIds.contains(heistId)
        case .matcher(let matcher):
            return hasMatch(matcher)
        }
    }

    /// Check if an element is interactive based on traits.
    /// Returns nil if interactive, or an error string if not.
    func checkElementInteractivity(_ element: AccessibilityElement) -> String? {
        if element.traits.contains(.notEnabled) {
            return "Element is disabled (has 'notEnabled' trait)"
        }

        let staticTraitsOnly = element.traits.isSubset(of: [.staticText, .image, .header])
        let hasInteractiveTraits = element.traits.contains(.button) ||
                                   element.traits.contains(.link) ||
                                   element.traits.contains(.adjustable) ||
                                   element.traits.contains(.searchField) ||
                                   element.traits.contains(.keyboardKey)

        if staticTraitsOnly && !hasInteractiveTraits && element.customActions.isEmpty {
            insideJobLogger.warning("Element '\(element.description)' has only static traits, tap may not work")
        }

        return nil
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

    // MARK: - Refresh Pipeline

    /// Trigger a refresh of the accessibility data.
    /// - Returns: true if data was successfully refreshed.
    @discardableResult
    func refreshElements() -> Bool {
        refresh() != nil
    }

    /// Clear all cached element data (used on suspend).
    func clearCache() {
        currentHierarchy.removeAll()
        screenElements.removeAll()
        presentedHeistIds.removeAll()
        onScreen.removeAll()
        heistIdByTraversalOrder.removeAll()
        lastHierarchyHash = 0
    }

    // MARK: - Parse (read-only)

    /// Read the live accessibility tree without mutating any state.
    /// Returns a ParseResult value that can be inspected (e.g., for topology comparison)
    /// before deciding whether to apply it.
    func parse() -> ParseResult? {
        let windows = tripwire.getTraversableWindows()
        guard !windows.isEmpty else { return nil }

        var allHierarchy: [AccessibilityHierarchy] = []
        var allElements: [AccessibilityElement] = []
        var allObjects: [AccessibilityElement: NSObject] = [:]
        var allScrollViews: [AccessibilityContainer: UIView] = [:]

        // Accessibility property reads return autoreleased ObjC objects.
        // Draining per-window keeps high-water mark proportional to one window's tree.
        for (window, rootView) in windows {
            autoreleasepool {
                let baseIndex = allElements.count
                let windowTree = parser.parseAccessibilityHierarchy(
                    in: rootView,
                    rotorResultLimit: 0,
                    elementVisitor: { element, _, object in
                        allObjects[element] = object
                    },
                    containerVisitor: { container, object in
                        if case .scrollable = container.type, let view = object as? UIView {
                            allScrollViews[container] = view
                        }
                    }
                )
                let windowElements = windowTree.flattenToElements()

                if windows.count > 1 {
                    let windowName = NSStringFromClass(type(of: window))
                    let container = AccessibilityContainer(
                        type: .semanticGroup(
                            label: windowName,
                            value: "windowLevel: \(window.windowLevel.rawValue)",
                            identifier: nil
                        ),
                        frame: window.frame
                    )
                    let reindexed = windowTree.reindexed(offset: baseIndex)
                    allHierarchy.append(.container(container, children: reindexed))
                } else {
                    allHierarchy.append(contentsOf: windowTree)
                }

                allElements.append(contentsOf: windowElements)
            }
        }

        return ParseResult(
            elements: allElements,
            hierarchy: allHierarchy,
            objects: allObjects,
            scrollViews: allScrollViews
        )
    }

    // MARK: - Apply (mutates registry)

    /// Apply a parse result to the registry. Sets `currentHierarchy`,
    /// `scrollableContainerViews`, upserts into `screenElements`, rebuilds `onScreen`.
    func apply(_ result: ParseResult) {
        currentHierarchy = result.hierarchy
        scrollableContainerViews = result.scrollViews

        // Track which heistIds are in this refresh's visible set
        var visibleThisRefresh: Set<String> = []

        // Walk hierarchy to gather per-element context (objects, scroll views, content origins)
        var contexts: [Int: ElementContext] = [:]
        walkHierarchy(
            result.hierarchy, scrollView: nil,
            scrollableContainerViews: result.scrollViews, elementObjects: result.objects,
            contexts: &contexts
        )

        // Assign heistIds from AccessibilityElements directly — no wire conversion needed
        let heistIds = assignHeistIds(result.elements)

        // Upsert into screenElements and build reverse index
        heistIdByTraversalOrder.removeAll(keepingCapacity: true)
        for (index, heistId) in heistIds.enumerated() {
            let ctx = contexts[index]
            visibleThisRefresh.insert(heistId)
            heistIdByTraversalOrder[index] = heistId
            let parsedElement = result.elements[index]

            if var existing = screenElements[heistId] {
                existing.element = parsedElement
                existing.object = ctx?.object
                existing.scrollView = ctx?.scrollView
                screenElements[heistId] = existing
            } else {
                screenElements[heistId] = ScreenElement(
                    heistId: heistId,
                    contentSpaceOrigin: ctx?.contentSpaceOrigin,
                    element: parsedElement,
                    object: ctx?.object,
                    scrollView: ctx?.scrollView
                )
            }
        }

        onScreen = visibleThisRefresh

        // Cache screen name — first header by traversal order.
        // Walk heistIds (already in traversal order) to find the first header in O(n).
        var firstHeaderName: String?
        var firstHeaderOrder = Int.max
        for (order, heistId) in heistIdByTraversalOrder {
            guard order < firstHeaderOrder,
                  let entry = screenElements[heistId],
                  entry.element.traits.contains(.header),
                  let label = entry.element.label else { continue }
            firstHeaderName = label
            firstHeaderOrder = order
        }
        lastScreenName = firstHeaderName
    }

    /// Parse and apply in one step. Most callers use this.
    /// Returns the ParseResult for callers that need the hierarchy tree or elements.
    @discardableResult
    func refresh() -> ParseResult? {
        guard let result = parse() else { return nil }
        apply(result)
        return result
    }

    /// Per-element context gathered during the hierarchy walk.
    private struct ElementContext {
        let contentSpaceOrigin: CGPoint?
        weak var scrollView: UIScrollView?
        weak var object: NSObject?
    }

    /// Walk the hierarchy tree to gather per-element context: content-space origins,
    /// scroll view refs, and live element objects. All derived from
    /// the accessibility hierarchy — no view hierarchy walking.
    private func walkHierarchy(
        _ nodes: [AccessibilityHierarchy],
        scrollView: UIScrollView?,
        scrollableContainerViews: [AccessibilityContainer: UIView],
        elementObjects: [AccessibilityElement: NSObject],
        contexts: inout [Int: ElementContext]
    ) {
        for node in nodes {
            switch node {
            case .element(let element, let traversalIndex):
                let origin: CGPoint?
                if let scrollView {
                    let frame = element.shape.frame
                    origin = (!frame.isNull && !frame.isEmpty)
                        ? scrollView.convert(frame.origin, from: nil)
                        : nil
                } else {
                    origin = nil
                }
                contexts[traversalIndex] = ElementContext(
                    contentSpaceOrigin: origin,
                    scrollView: scrollView,
                    object: elementObjects[element]
                )

            case .container(let ctr, let children):
                let childScrollView = (scrollableContainerViews[ctr] as? UIScrollView) ?? scrollView
                walkHierarchy(
                    children, scrollView: childScrollView,
                    scrollableContainerViews: scrollableContainerViews, elementObjects: elementObjects,
                    contexts: &contexts
                )
            }
        }
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    // MARK: - Topology-Based Screen Change

    /// Did the accessibility topology change between two element snapshots?
    /// Checks two signals using the parser's native `AccessibilityElement`:
    /// - Back button trait appeared or disappeared (navigation push/pop)
    /// - Header structure changed completely (all header labels replaced)
    func isTopologyChanged(
        before: [AccessibilityElement],
        after: [AccessibilityElement]
    ) -> Bool {
        let backButtonTrait = UIAccessibilityTraits(rawValue: 1 << 27)
        let hadBackButton = before.contains { $0.traits.contains(backButtonTrait) }
        let hasBackButton = after.contains { $0.traits.contains(backButtonTrait) }
        if hadBackButton != hasBackButton { return true }

        let beforeHeaders = Set(before.compactMap { $0.traits.contains(.header) ? $0.label : nil })
        let afterHeaders = Set(after.compactMap { $0.traits.contains(.header) ? $0.label : nil })
        if !beforeHeaders.isEmpty, !afterHeaders.isEmpty, beforeHeaders.isDisjoint(with: afterHeaders) {
            return true
        }

        return false
    }

    // MARK: - Action Result with Delta

    /// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
    /// Waits for all animations (UIKit and SwiftUI) to settle via presentation layer diffing,
    /// then polls for accessibility tree stability as a safety net.
    ///
    /// Screen change detection is three-tier:
    /// 1. VC identity — UIKit navigation (push/pop, modal present/dismiss)
    /// 2. Back button trait — private trait bit 27 appeared/disappeared
    /// 3. Header structure — the set of header labels changed completely
    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        beforeSnapshot: [ScreenElement],
        beforeElements: [AccessibilityElement],
        beforeVC: ObjectIdentifier? = nil,
        target: ElementTarget? = nil
    ) async -> ActionResult {
        guard success else {
            let kind: ErrorKind = (method == .elementNotFound || method == .elementDeallocated)
                ? .elementNotFound : .actionFailed
            return ActionResult(success: false, method: method, message: message, errorKind: kind,
                                value: value, screenName: beforeSnapshot.screenName)
        }

        // Wait for all clear: presentation layers settled AND accessibility tree stable.
        let start = CFAbsoluteTimeGetCurrent()
        let settled = await tripwire.waitForAllClear(timeout: 1.0)
        let settleMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        insideJobLogger.info("Post-action settle: \(settled ? "all clear" : "timed out") in \(settleMs)ms")

        // Parse without mutating — detect screen change before touching the registry.
        let afterResult = parse()

        // Screen change gate: VC identity OR accessibility topology
        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let isScreenChange = tripwire.isScreenChange(before: beforeVC, after: afterVC)
            || isTopologyChanged(before: beforeElements, after: afterResult?.elements ?? [])
        if isScreenChange {
            // Clear the old screen's registry before applying new data.
            // No mixed state — the old registry is gone before new entries arrive.
            screenElements.removeAll()
            presentedHeistIds.removeAll()
            heistIdByTraversalOrder.removeAll()
        }
        if let afterResult {
            apply(afterResult)
        }
        let afterSnapshot = snapshot(.visible)
        let delta = computeDelta(
            before: beforeSnapshot, after: afterSnapshot,
            afterTree: afterResult?.hierarchy, isScreenChange: isScreenChange
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
                elementTraits = traitNames(traits)
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
            screenName: afterSnapshot.screenName
        )
    }
}

// MARK: - AccessibilityHierarchy Reindexing

extension Array where Element == AccessibilityHierarchy {
    func reindexed(offset: Int) -> [AccessibilityHierarchy] {
        guard offset != 0 else { return self }
        return mappedHierarchy { node in
            guard case let .element(element, index) = node else { return node }
            return .element(element, traversalIndex: index + offset)
        }
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

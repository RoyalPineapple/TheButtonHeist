#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

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

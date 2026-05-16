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
    /// **One field, two shapes:**
    ///
    /// 1. **After a plain parse** `currentScreen` is page-only: its known
    ///    semantic set is exactly the live hierarchy. Scroll-settle heuristics
    ///    compare this shape between frames to detect movement.
    ///
    /// 2. **After `Navigation.exploreAndPrune`** the local `union: Screen`
    ///    accumulator is committed here. `elements` becomes the whole known
    ///    hierarchy discovered by scrolling, while live-only fields (`hierarchy`,
    ///    `heistIdByElement`, `firstResponderHeistId`) still come from the last
    ///    parse via `Screen.merging`.
    ///
    /// **Writer audit** — the call sites that set this field:
    /// - `refresh()` — single parse + commit (page-only)
    /// - `Navigation+Explore.exploreContainer` mid-loop — page-only commits
    ///   per scroll page, required for the termination heuristics above
    /// - `Navigation+Explore.exploreAndPrune` end-of-cycle — union commit
    /// - `clearCache()` / `clearScreen()` — reset to `.empty`
    /// - `TheBrains.actionResultWithDelta` — page-only commit after settle
    ///
    /// Readers that specifically want "what's reachable in the latest parse"
    /// read `visibleIds`; target resolution reads the known semantic set.
    var currentScreen: Screen = .empty

    private var pendingRotorState: PendingRotorState = .none

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

    /// HeistIds of all known elements in the current screen value.
    ///
    /// After an exploration commit this includes elements that were observed
    /// during scrolling and are no longer on-screen; after a plain `refresh()`
    /// this is the live viewport. Use `visibleIds` when you specifically
    /// need "what's on screen right now".
    var knownIds: Set<String> {
        ids(in: .known)
    }

    /// HeistIds of elements present in the live hierarchy from the most
    /// recent parse — i.e. on-screen right now. Strictly a subset of
    /// `knownIds` after an exploration union has been committed.
    var visibleIds: Set<String> {
        ids(in: .visible)
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
        Interactivity.isInteractive(element: screenElement.element, object: dispatchObject(for: screenElement))
    }

    /// Outcome of `activate(_:)`.
    enum ActivateOutcome {
        case success
        case objectDeallocated
        case refused
    }

    func activate(_ screenElement: ScreenElement) -> ActivateOutcome {
        guard let object = dispatchObject(for: screenElement) else { return .objectDeallocated }
        return object.accessibilityActivate() ? .success : .refused
    }

    @discardableResult
    func increment(_ screenElement: ScreenElement) -> Bool {
        guard let object = dispatchObject(for: screenElement) else { return false }
        object.accessibilityIncrement()
        return true
    }

    @discardableResult
    func decrement(_ screenElement: ScreenElement) -> Bool {
        guard let object = dispatchObject(for: screenElement) else { return false }
        object.accessibilityDecrement()
        return true
    }

    enum CustomActionOutcome {
        case succeeded
        case declined
        case deallocated
        case noSuchAction
    }

    struct RotorHit {
        let rotor: String
        let screenElement: ScreenElement?
        let textRange: RotorTextRange?
    }

    private struct PendingRotorResult {
        let token: UUID
        let screenElement: ScreenElement
        /// Strongly retain out-of-tree rotor result objects for exactly one
        /// follow-up command. `ScreenElement.object` is weak, but VoiceOver-style
        /// rotor continuation needs the object to remain alive long enough for
        /// activation or a next/previous step.
        let object: NSObject
    }

    private enum PendingRotorState {
        case none
        case stored(PendingRotorResult)
        case active(PendingRotorResult)
    }

    enum RotorOutcome {
        case succeeded(RotorHit)
        case deallocated
        case noRotors
        case noSuchRotor(available: [String])
        case ambiguousRotor(available: [String])
        case currentItemUnavailable(String)
        case currentTextRangeUnavailable
        case noResult(String)
        case resultTargetUnavailable(String)
        case resultTargetNotParsed(String)
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
        guard let object = dispatchObject(for: screenElement),
              let scrollView = screenElement.scrollView else { return nil }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return nil }
        return LiveGeometry(
            frame: frame,
            activationPoint: object.accessibilityActivationPoint,
            scrollView: scrollView
        )
    }

    func liveActivationPoint(for screenElement: ScreenElement) -> CGPoint? {
        guard let object = dispatchObject(for: screenElement) else { return nil }
        let point = object.accessibilityActivationPoint
        guard point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }

    func liveFrame(for screenElement: ScreenElement) -> CGRect? {
        guard let object = dispatchObject(for: screenElement) else { return nil }
        let frame = object.accessibilityFrame
        guard !frame.isNull,
              !frame.isEmpty,
              frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.size.width.isFinite,
              frame.size.height.isFinite
        else { return nil }
        return frame
    }

    func performCustomAction(named name: String, on screenElement: ScreenElement) -> CustomActionOutcome {
        guard let object = dispatchObject(for: screenElement) else { return .deallocated }
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

    private func dispatchObject(for screenElement: ScreenElement) -> NSObject? {
        if visibleIds.contains(screenElement.heistId) {
            return screenElement.object
        }
        if case .active(let pending) = pendingRotorState,
           pending.screenElement.heistId == screenElement.heistId {
            return pending.object
        }
        if currentScreen.findElement(heistId: screenElement.heistId) == nil {
            return screenElement.object
        }
        return nil
    }

    func performRotor(
        _ target: RotorTarget,
        direction: RotorDirection,
        on screenElement: ScreenElement
    ) -> RotorOutcome {
        guard let object = dispatchObject(for: screenElement) else { return .deallocated }
        let rotors = object.accessibilityCustomRotors ?? []
        guard !rotors.isEmpty else { return .noRotors }

        let availableNames = rotors.map(\.name)
        let selection: UIAccessibilityCustomRotor
        if let rotorIndex = target.rotorIndex {
            guard rotors.indices.contains(rotorIndex) else {
                return .noSuchRotor(available: availableNames)
            }
            selection = rotors[rotorIndex]
        } else if let rotorName = target.rotor {
            let matches = rotors.enumerated().filter { $0.element.name == rotorName }
            switch matches.count {
            case 0:
                return .noSuchRotor(available: availableNames)
            case 1:
                selection = matches[0].element
            default:
                return .ambiguousRotor(available: availableNames)
            }
        } else if rotors.count == 1 {
            selection = rotors[0]
        } else {
            return .ambiguousRotor(available: availableNames)
        }

        let predicate = UIAccessibilityCustomRotorSearchPredicate()
        predicate.searchDirection = direction.uiAccessibilityDirection
        if let currentHeistId = target.currentHeistId {
            guard let current = resolveTarget(.heistId(currentHeistId)).resolved?.screenElement,
                  let currentObject = dispatchObject(for: current) else {
                return .currentItemUnavailable(currentHeistId)
            }
            let currentRange: UITextRange?
            if let currentTextRange = target.currentTextRange {
                guard let input = currentObject as? UITextInput,
                      let range = textRange(from: currentTextRange, in: input) else {
                    return .currentTextRangeUnavailable
                }
                currentRange = range
            } else {
                currentRange = nil
            }
            predicate.currentItem = UIAccessibilityCustomRotorItemResult(targetElement: currentObject, targetRange: currentRange)
        } else if target.currentTextRange != nil {
            return .currentTextRangeUnavailable
        }

        let rotorName = selection.name
        guard let result = selection.itemSearchBlock(predicate) else {
            return .noResult(rotorName)
        }
        let resultObject = result.targetElement as? NSObject
        let textRange = result.targetRange.map { describeTextRange($0, in: resultObject) }
        guard let resultObject else {
            return .resultTargetUnavailable(rotorName)
        }
        let parsed = parseRotorResultObject(resultObject)
        if let parsed, !parsed.isInCurrentHierarchy {
            pendingRotorState = .stored(PendingRotorResult(
                token: UUID(),
                screenElement: parsed.screenElement,
                object: resultObject
            ))
        }
        guard parsed != nil || textRange != nil else {
            return .resultTargetNotParsed(rotorName)
        }
        return .succeeded(RotorHit(rotor: rotorName, screenElement: parsed?.screenElement, textRange: textRange))
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    ///
    /// Resolution reads the committed semantic state. If an element is not in
    /// `currentScreen.elements`, resolution fails with a near-miss suggestion.
    /// Live coordinate revalidation happens later in action execution.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: currentScreen, includePendingRotor: true)
    }

    /// Resolve a target against a supplied screen value. Used by callers that
    /// intentionally preserved a known semantic snapshot across a fresh visible
    /// parse.
    func resolveTarget(_ target: ElementTarget, in screen: Screen) -> TargetResolution {
        resolveTarget(target, in: screen, includePendingRotor: false)
    }

    /// Resolve a target only against the latest live hierarchy. This preserves
    /// full target semantics (ambiguity and explicit ordinal) while excluding
    /// known-only entries retained from exploration.
    func resolveVisibleTarget(_ target: ElementTarget) -> TargetResolution {
        let visibleIds = currentScreen.visibleIds
        let visibleScreen = Screen(
            elements: currentScreen.elements.filter { visibleIds.contains($0.key) },
            hierarchy: currentScreen.hierarchy,
            containerStableIds: currentScreen.containerStableIds,
            heistIdByElement: currentScreen.heistIdByElement,
            firstResponderHeistId: currentScreen.firstResponderHeistId,
            scrollableContainerViews: currentScreen.scrollableContainerViews
        )
        return resolveTarget(target, in: visibleScreen)
    }

    private func resolveTarget(
        _ target: ElementTarget,
        in screen: Screen,
        includePendingRotor: Bool
    ) -> TargetResolution {
        switch target {
        case .heistId(let heistId):
            if includePendingRotor, let pending = activePendingRotorResult(heistId: heistId) {
                return .resolved(ResolvedTarget(screenElement: pending))
            }
            guard let entry = screen.findElement(heistId: heistId) else {
                return .notFound(diagnostics: Diagnostics.heistIdNotFound(
                    heistId,
                    knownIds: screen.elements.keys,
                    knownCount: screen.elements.count
                ))
            }
            return .resolved(ResolvedTarget(screenElement: entry))
        case .matcher(let matcher, let ordinal):
            return resolveMatcher(matcher, ordinal: ordinal, in: screen)
        }
    }

    /// HeistIds for either the live hierarchy or the committed known screen.
    func ids(in scope: InterfaceElementScope) -> Set<String> {
        switch scope {
        case .visible:
            return currentScreen.visibleIds
        case .known:
            return currentScreen.knownIds
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

    private func resolveMatcher(
        _ matcher: ElementMatcher,
        ordinal: Int?,
        in screen: Screen
    ) -> TargetResolution {
        if let ordinal {
            guard ordinal >= 0 else {
                return .notFound(diagnostics: "ordinal must be non-negative, got \(ordinal)")
            }
            let matches = matchScreenElements(matcher, limit: ordinal + 1, in: screen)
            guard ordinal < matches.count else {
                let total = matches.count
                return .notFound(diagnostics: "ordinal \(ordinal) requested but only \(total) match\(total == 1 ? "" : "es") found")
            }
            return .resolved(ResolvedTarget(screenElement: matches[ordinal]))
        }
        let matches = matchScreenElements(matcher, limit: 2, in: screen)
        switch matches.count {
        case 0:
            return .notFound(diagnostics: matcherNotFoundMessage(matcher, in: screen))
        case 1:
            return .resolved(ResolvedTarget(screenElement: matches[0]))
        default:
            let capped = matchScreenElements(matcher, limit: 11, in: screen)
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

    /// Existence check for wait-style predicates. Both heistIds and matchers
    /// read the committed semantic screen; action execution owns any viewport
    /// work needed to make a matched element reachable.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch target {
        case .heistId(let heistId):
            return screenElement(heistId: heistId, in: .known) != nil
        case .matcher(let matcher, _):
            return !matchScreenElements(matcher, limit: 1).isEmpty
        }
    }

    func checkElementInteractivity(_ screenElement: ScreenElement) -> InteractivityCheck {
        Interactivity.checkInteractivity(screenElement.element, object: dispatchObject(for: screenElement))
    }

    // MARK: - Traversal Order Index

    /// Build a heistId→traversal-order lookup for diagnostics formatting.
    /// Walks the live hierarchy in DFS order — this matches the order the
    /// agent sees in `get_interface` payloads.
    func buildTraversalOrderIndex(in screen: Screen? = nil) -> [String: Int] {
        let screen = screen ?? currentScreen
        var index: [String: Int] = [:]
        var counter = 0
        for (element, _) in screen.hierarchy.elements {
            if let heistId = screen.heistIdByElement[element] {
                index[heistId] = counter
                counter += 1
            }
        }
        return index
    }

    // MARK: - Diagnostics Forwarding

    func matcherNotFoundMessage(_ matcher: ElementMatcher, in screen: Screen? = nil) -> String {
        let screen = screen ?? currentScreen
        return Diagnostics.matcherNotFound(
            matcher, hierarchy: screen.hierarchy,
            screenElements: selectElements(in: screen),
            knownHeistIds: screen.knownIds,
            traversalOrder: buildTraversalOrderIndex(in: screen)
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
    func selectElements(in screen: Screen? = nil) -> [ScreenElement] {
        let screen = screen ?? currentScreen
        var seen = Set<String>()
        var ordered: [ScreenElement] = []
        ordered.reserveCapacity(screen.elements.count)
        for (element, _) in screen.hierarchy.elements {
            guard let heistId = screen.heistIdByElement[element],
                  let entry = screen.elements[heistId],
                  seen.insert(heistId).inserted else { continue }
            ordered.append(entry)
        }
        let remaining = screen.elements
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
        clearPendingRotorResult()
        lastHierarchyHash = 0
    }

    /// Clear screen-level state on screen change. Screens are values, so
    /// "clear screen" is identical to "clear everything" — the next parse
    /// produces a fresh screen.
    func clearScreen() {
        currentScreen = .empty
        clearPendingRotorResult()
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

    /// Return the known `ScreenElement` corresponding to a UIKit accessibility
    /// object by live object identity.
    func knownObject(_ object: NSObject) -> ParsedRotorResultObject? {
        guard let cached = currentScreen.elements.values.first(where: { $0.object === object }) else {
            return nil
        }
        return ParsedRotorResultObject(
            screenElement: cached,
            isInCurrentHierarchy: visibleIds.contains(cached.heistId)
        )
    }

    /// Parse the live hierarchy and return the `ScreenElement` corresponding to
    /// a UIKit accessibility object. Used by live custom rotor steps so the
    /// returned rotor target flows through the same parser as `get_interface`.
    func parseLiveObject(_ object: NSObject) -> ScreenElement? {
        guard let result = burglar.parse() else { return nil }
        guard let parsedElement = result.objects.first(where: { pair in
            pair.value === object
        })?.key else {
            return nil
        }
        let screen = TheBurglar.buildScreen(from: result)
        guard let heistId = screen.heistIdByElement[parsedElement] else { return nil }
        return screen.elements[heistId]
    }

    struct ParsedRotorResultObject {
        let screenElement: ScreenElement
        let isInCurrentHierarchy: Bool
    }

    func parseRotorResultObject(_ object: NSObject) -> ParsedRotorResultObject? {
        if let known = knownObject(object) {
            return known
        }

        let standaloneElement = burglar.parseObject(object)
        if let screenElement = parseLiveObject(object) {
            return ParsedRotorResultObject(screenElement: screenElement, isInCurrentHierarchy: true)
        }

        guard let element = standaloneElement else { return nil }
        let heistId = pendingRotorHeistId(for: element)
        return ParsedRotorResultObject(
            screenElement: ScreenElement(
                heistId: heistId,
                contentSpaceOrigin: nil,
                element: element,
                object: object,
                scrollView: nil
            ),
            isInCurrentHierarchy: false
        )
    }

    func preparePendingRotorResult(targetedHeistId: String?) -> UUID? {
        let pending: PendingRotorResult
        switch pendingRotorState {
        case .none:
            return nil
        case .stored(let result), .active(let result):
            pending = result
        }
        guard targetedHeistId == pending.screenElement.heistId else {
            clearPendingRotorResult()
            return nil
        }
        pendingRotorState = .active(pending)
        return pending.token
    }

    func clearPendingRotorResult() {
        pendingRotorState = .none
    }

    func clearPendingRotorResult(consumedToken: UUID) {
        switch pendingRotorState {
        case .none:
            return
        case .stored(let pending):
            if pending.token == consumedToken {
                clearPendingRotorResult()
            }
            return
        case .active(let pending):
            if pending.token == consumedToken {
                clearPendingRotorResult()
            } else {
                pendingRotorState = .stored(pending)
            }
        }
    }

    private func activePendingRotorResult(heistId: String) -> ScreenElement? {
        guard case .active(let pendingRotorResult) = pendingRotorState,
              pendingRotorResult.screenElement.heistId == heistId else {
            return nil
        }
        return pendingRotorResult.screenElement
    }

    private func pendingRotorHeistId(for element: AccessibilityElement) -> String {
        let base = Self.IdAssignment.assign([element]).first ?? "element"
        let root = "rotor_result_\(base)"
        var candidate = root
        var suffix = 2
        while currentScreen.knownIds.contains(candidate) {
            candidate = "\(root)_\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func textRange(from reference: TextRangeReference, in input: UITextInput) -> UITextRange? {
        guard let start = input.position(from: input.beginningOfDocument, offset: reference.startOffset),
              let end = input.position(from: input.beginningOfDocument, offset: reference.endOffset) else {
            return nil
        }
        return input.textRange(from: start, to: end)
    }

    private func describeTextRange(_ range: UITextRange, in object: NSObject?) -> RotorTextRange {
        guard let input = object as? UITextInput else {
            return RotorTextRange(rangeDescription: "\(range)")
        }

        let startOffset = input.offset(from: input.beginningOfDocument, to: range.start)
        let endOffset = input.offset(from: input.beginningOfDocument, to: range.end)
        return RotorTextRange(
            text: input.text(in: range),
            startOffset: startOffset,
            endOffset: endOffset,
            rangeDescription: "[\(startOffset)..<\(endOffset)]"
        )
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

private extension RotorDirection {
    var uiAccessibilityDirection: UIAccessibilityCustomRotor.Direction {
        switch self {
        case .next:
            return .next
        case .previous:
            return .previous
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

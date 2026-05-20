#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The stash — holds the goods and answers questions about them.
///
/// TheStash owns exactly one mutable accessibility belief: the latest
/// committed `Screen`. It exposes lookup, matcher resolution, and
/// wire-conversion facades over that value; parsing, diagnostics, capture,
/// recording, response memory, and UIKit actions are boundary transforms or
/// owned by other crew members. `currentScreen.knownInterface` is targetable
/// semantic state; `currentScreen.liveInterface` is the latest parse
/// used for geometry, live objects, and scrolling. Callers call `parse()` to
/// obtain a Screen value, then decide when to write it back via
/// `currentScreen = ...`. The exploration accumulator lives in TheBrains as
/// a local `var union`.
@MainActor
final class TheStash {

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
        self.burglar = TheBurglar(tripwire: tripwire)
    }

    // MARK: - Mutable State

    /// Latest committed interface state.
    ///
    /// **Writer audit** — the call sites that set this field:
    /// - `refresh()` — single parse + commit (page-only)
    /// - `Navigation+Explore.exploreContainer` mid-loop — page-only commits
    ///   per scroll page, required for the termination heuristics above
    /// - `Navigation+Explore.exploreAndPrune` end-of-cycle — union commit
    /// - `clearCache()` / `clearScreen()` — reset to `.empty`
    /// - `TheBrains.actionResultWithDelta` — page-only commit after settle
    ///
    /// Readers that specifically want "what's on-screen in the latest parse"
    /// read `visibleIds`; target resolution reads the known semantic set.
    var currentScreen: Screen = .empty

    private var pendingRotorState: PendingRotorState = .none

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Aliases

    typealias ScreenElement = Screen.ScreenElement

    // MARK: - Computed Accessors

    /// Hierarchy from the most recent parse. Proxy for call-site clarity —
    /// reads, matchers, scroll dispatch, and tab-bar geometry all need it
    /// without spelling out `currentScreen.liveInterface.hierarchy`
    /// every time.
    var currentHierarchy: [AccessibilityHierarchy] {
        currentScreen.liveInterface.hierarchy
    }

    /// Scrollable containers paired with their backing UIView.
    /// Unwraps the weak ref wrapper for call sites that need a live UIView.
    var scrollableContainerViews: [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, ref) in currentScreen.liveInterface.scrollableContainerViews {
            if let view = ref.view {
                result[container] = view
            }
        }
        return result
    }

    /// HeistIds of all known elements in the current screen value.
    ///
    /// After an exploration commit this includes elements that were observed
    /// during scrolling and are no longer on-screen. Use `visibleIds` when
    /// you specifically need the latest parsed on-screen ids.
    var knownIds: Set<HeistId> {
        ids(in: .known)
    }

    /// HeistIds of elements present in the hierarchy from the most recent
    /// parse. Strictly a subset of `knownIds` after an exploration union has
    /// been committed.
    var visibleIds: Set<HeistId> {
        ids(in: .visible)
    }

    /// HeistId of the element whose live object is currently first responder.
    var firstResponderHeistId: HeistId? {
        currentScreen.liveInterface.firstResponderHeistId
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

    /// Result of resolving an ElementTarget to known semantic target data.
    ///
    /// This does not prove the backing UIKit object, frame, or activation
    /// point are still live. Actions must resolve a `LiveActionTarget`
    /// immediately before dispatch.
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

    enum ResolutionScope: String {
        case known
        case provided
        case visible
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
        /// follow-up command. `LiveInterface` refs are weak, but VoiceOver-style
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

    struct LiveActionTarget {
        let resolvedTarget: ResolvedTarget
        let object: NSObject
        let frame: CGRect
        let activationPoint: CGPoint

        var screenElement: ScreenElement { resolvedTarget.screenElement }
        var element: AccessibilityElement { resolvedTarget.element }
    }

    enum LiveActionTargetResolution {
        case resolved(LiveActionTarget)
        case objectUnavailable
        case geometryUnavailable
    }

    enum KnownTargetInflationFailure: Equatable {
        case missingContentOrigin
        case noLiveScrollableAncestor
        case ambiguousLiveScrollableAncestor
        case unsafeProgrammaticScroll
    }

    enum KnownTargetInflationResolution {
        case resolved(UIScrollView)
        case failed(KnownTargetInflationFailure)
    }

    /// Make a known target live by scrolling a live parent derived from the
    /// current graph. Known-only semantic elements intentionally carry no
    /// scroll path; until `Screen` retains semantic container ancestry, a
    /// known-only target can be inflated only when the current live graph
    /// exposes exactly one plausible scroll parent for its content origin.
    @discardableResult
    func inflateKnownTarget(_ screenElement: ScreenElement, animated: Bool = true) -> KnownTargetInflationResolution {
        switch resolveInflationScrollView(for: screenElement) {
        case .resolved(let scrollView):
            guard let origin = screenElement.contentSpaceOrigin else {
                return .failed(.missingContentOrigin)
            }
            let targetOffset = Self.scrollTargetOffset(for: origin, in: scrollView)
            scrollView.setContentOffset(targetOffset, animated: animated)
            return .resolved(scrollView)
        case .failed(let failure):
            return .failed(failure)
        }
    }

    func resolveInflationScrollView(for screenElement: ScreenElement) -> KnownTargetInflationResolution {
        guard let origin = screenElement.contentSpaceOrigin else {
            return .failed(.missingContentOrigin)
        }

        if let liveScrollView = liveScrollView(for: screenElement) {
            guard !liveScrollView.bhIsUnsafeForProgrammaticScrolling else {
                return .failed(.unsafeProgrammaticScroll)
            }
            return .resolved(liveScrollView)
        }

        var seenScrollViews = Set<ObjectIdentifier>()
        let scrollViews = currentScreen.liveInterface.scrollableContainerViews.values.compactMap {
            $0.view as? UIScrollView
        }.filter {
            seenScrollViews.insert(ObjectIdentifier($0)).inserted
        }
        let safeCandidates = scrollViews.filter {
            !$0.bhIsUnsafeForProgrammaticScrolling && Self.contentOrigin(origin, fitsIn: $0)
        }
        switch safeCandidates.count {
        case 1:
            return .resolved(safeCandidates[0])
        case 0:
            if !scrollViews.isEmpty,
               scrollViews.allSatisfy(\.bhIsUnsafeForProgrammaticScrolling) {
                return .failed(.unsafeProgrammaticScroll)
            }
            return .failed(.noLiveScrollableAncestor)
        default:
            return .failed(.ambiguousLiveScrollableAncestor)
        }
    }

    private static func contentOrigin(_ origin: CGPoint, fitsIn scrollView: UIScrollView) -> Bool {
        let insets = scrollView.adjustedContentInset
        let minX = -insets.left
        let minY = -insets.top
        let maxX = scrollView.contentSize.width + insets.right
        let maxY = scrollView.contentSize.height + insets.bottom
        return origin.x >= minX
            && origin.y >= minY
            && origin.x <= maxX
            && origin.y <= maxY
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
              let scrollView = liveScrollView(for: screenElement) else { return nil }
        let frame = object.accessibilityFrame
        guard !frame.isNull, !frame.isEmpty else { return nil }
        return LiveGeometry(
            frame: frame,
            activationPoint: object.accessibilityActivationPoint,
            scrollView: scrollView
        )
    }

    func resolveLiveActionTarget(for resolvedTarget: ResolvedTarget) -> LiveActionTargetResolution {
        guard let object = dispatchObject(for: resolvedTarget.screenElement) else {
            return .objectUnavailable
        }
        let frame = object.accessibilityFrame
        let activationPoint = object.accessibilityActivationPoint
        guard Self.isUsableFrame(frame),
              Self.isUsablePoint(activationPoint) else {
            return .geometryUnavailable
        }
        return .resolved(LiveActionTarget(
            resolvedTarget: resolvedTarget,
            object: object,
            frame: frame,
            activationPoint: activationPoint
        ))
    }

    func liveActionTarget(for resolvedTarget: ResolvedTarget) -> LiveActionTarget? {
        guard case .resolved(let target) = resolveLiveActionTarget(for: resolvedTarget) else {
            return nil
        }
        return target
    }

    func liveActivationPoint(for screenElement: ScreenElement) -> CGPoint? {
        guard let object = dispatchObject(for: screenElement) else { return nil }
        let point = object.accessibilityActivationPoint
        guard Self.isUsablePoint(point) else { return nil }
        return point
    }

    func liveFrame(for screenElement: ScreenElement) -> CGRect? {
        guard let object = dispatchObject(for: screenElement) else { return nil }
        let frame = object.accessibilityFrame
        guard Self.isUsableFrame(frame) else { return nil }
        return frame
    }

    private static func isUsableFrame(_ frame: CGRect) -> Bool {
        !frame.isNull
            && !frame.isEmpty
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
    }

    private static func isUsablePoint(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    func activate(_ liveTarget: LiveActionTarget) -> ActivateOutcome {
        liveTarget.object.accessibilityActivate() ? .success : .refused
    }

    @discardableResult
    func increment(_ liveTarget: LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityIncrement()
        return true
    }

    @discardableResult
    func decrement(_ liveTarget: LiveActionTarget) -> Bool {
        liveTarget.object.accessibilityDecrement()
        return true
    }

    func performCustomAction(named name: String, on screenElement: ScreenElement) -> CustomActionOutcome {
        guard let object = dispatchObject(for: screenElement) else { return .deallocated }
        return performCustomAction(named: name, on: object)
    }

    func performCustomAction(named name: String, on liveTarget: LiveActionTarget) -> CustomActionOutcome {
        performCustomAction(named: name, on: liveTarget.object)
    }

    private func performCustomAction(named name: String, on object: NSObject) -> CustomActionOutcome {
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
            return currentScreen.liveInterface.object(for: screenElement.heistId)
        }
        if case .active(let pending) = pendingRotorState,
           pending.screenElement.heistId == screenElement.heistId {
            return pending.object
        }
        if currentScreen.knownInterface.findElement(heistId: screenElement.heistId) == nil {
            return currentScreen.liveInterface.object(for: screenElement.heistId)
        }
        return nil
    }

    func liveObject(for screenElement: ScreenElement) -> NSObject? {
        dispatchObject(for: screenElement)
    }

    func liveScrollView(for screenElement: ScreenElement) -> UIScrollView? {
        currentScreen.liveInterface.scrollView(for: screenElement)
    }

    func performRotor(
        _ target: RotorTarget,
        direction: RotorDirection,
        on screenElement: ScreenElement
    ) -> RotorOutcome {
        guard let object = dispatchObject(for: screenElement) else { return .deallocated }
        let rotors = object.accessibilityCustomRotors ?? []
        guard !rotors.isEmpty else { return .noRotors }

        let availableNames = rotors.map { $0.bhInvocableName(locale: object.accessibilityLanguage) }
        let selection: UIAccessibilityCustomRotor
        if let rotorIndex = target.rotorIndex {
            guard rotors.indices.contains(rotorIndex) else {
                return .noSuchRotor(available: availableNames)
            }
            selection = rotors[rotorIndex]
        } else if let rotorName = target.rotor {
            let matches = rotors.enumerated().filter {
                $0.element.bhInvocableName(locale: object.accessibilityLanguage) == rotorName
            }
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

        let rotorName = selection.bhInvocableName(locale: object.accessibilityLanguage)
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
    /// `currentScreen.knownInterface`, resolution fails with a near-miss
    /// suggestion. Live coordinate revalidation happens later in action execution.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: currentScreen, includePendingRotor: true, resolutionScope: .known)
    }

    /// Resolve a target against a supplied screen value. Used by callers that
    /// intentionally preserved a known semantic snapshot across a fresh visible
    /// parse.
    func resolveTarget(_ target: ElementTarget, in screen: Screen) -> TargetResolution {
        resolveTarget(target, in: screen, includePendingRotor: false, resolutionScope: .provided)
    }

    /// Resolve a target only against the latest live hierarchy. This preserves
    /// full target semantics (ambiguity and explicit ordinal) while excluding
    /// known-only entries retained from exploration.
    func resolveVisibleTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: currentScreen.visibleOnly, includePendingRotor: false, resolutionScope: .visible)
    }

    private func resolveTarget(
        _ target: ElementTarget,
        in screen: Screen,
        includePendingRotor: Bool,
        resolutionScope: ResolutionScope
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
            return resolveMatcher(matcher, ordinal: ordinal, in: screen, resolutionScope: resolutionScope)
        }
    }

    /// HeistIds for either the live hierarchy or the committed known screen.
    func ids(in scope: InterfaceElementScope) -> Set<HeistId> {
        switch scope {
        case .visible:
            return currentScreen.liveInterface.heistIds
        case .known:
            return currentScreen.knownInterface.heistIds
        }
    }

    /// Looks up an element by heistId in the selected scope.
    ///
    /// `.known` reads the committed `Screen.elements` map, including any
    /// exploration union. `.visible` only returns ids backed by the latest live
    /// hierarchy parse.
    func screenElement(heistId: HeistId, in scope: InterfaceElementScope) -> ScreenElement? {
        guard let entry = currentScreen.knownInterface.findElement(heistId: heistId) else { return nil }
        switch scope {
        case .visible:
            return currentScreen.liveInterface.contains(heistId: heistId) ? entry : nil
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
        guard let heistId = currentScreen.liveInterface.heistId(for: element) else { return nil }
        return screenElement(heistId: heistId, in: scope)
    }

    private func resolveMatcher(
        _ matcher: ElementMatcher,
        ordinal: Int?,
        in screen: Screen,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        if let ordinal {
            guard ordinal >= 0 else {
                return .notFound(diagnostics: """
                    ordinal must be non-negative, got \(ordinal)
                    Next: remove ordinal, or use ordinal 0 after get_interface shows the exact candidate order.
                    """)
            }
            let matches = matchScreenElements(matcher, limit: ordinal + 1, in: screen)
            guard ordinal < matches.count else {
                let total = matches.count
                let nextMove: String
                if total == 0 {
                    nextMove = "Next: retry with an exact label, identifier, or heistId from get_interface()."
                } else {
                    nextMove = "Next: use ordinal 0...\(total - 1), omit ordinal to inspect ambiguity, "
                        + "or target a listed element by exact label, identifier, or heistId."
                }
                return .notFound(diagnostics: """
                    ordinal \(ordinal) requested but only \(total) match\(total == 1 ? "" : "es") found
                    \(nextMove)
                    """)
            }
            return .resolved(ResolvedTarget(screenElement: matches[ordinal]))
        }
        let matches = matchScreenElements(matcher, limit: 2, in: screen)
        switch matches.count {
        case 0:
            return .notFound(diagnostics: matcherNotFoundMessage(
                matcher,
                in: screen,
                resolutionScope: resolutionScope
            ))
        case 1:
            return .resolved(ResolvedTarget(screenElement: matches[0]))
        default:
            let capped = matchScreenElements(matcher, limit: 11, in: screen)
            return ambiguousResolution(
                matcher,
                screenElements: capped,
                visibleHeistIds: screen.visibleIds,
                resolutionScope: resolutionScope
            )
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

    /// Resolve a target using first-match semantics against only the live hierarchy.
    func resolveFirstVisibleMatch(_ target: ElementTarget) -> ResolvedTarget? {
        let effectiveTarget: ElementTarget
        switch target {
        case .heistId:
            effectiveTarget = target
        case .matcher(let matcher, _):
            effectiveTarget = .matcher(matcher, ordinal: 0)
        }
        return resolveVisibleTarget(effectiveTarget).resolved
    }

    /// Boolean existence check for callers that only need present-vs-missing
    /// target semantics. Ambiguous matches count as present, and explicit
    /// ordinals must resolve at the requested index instead of falling back to
    /// the first match.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch resolveTarget(target) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    func checkElementInteractivity(_ screenElement: ScreenElement) -> InteractivityCheck {
        Interactivity.checkInteractivity(screenElement.element, object: dispatchObject(for: screenElement))
    }

    // MARK: - Diagnostics Forwarding

    func matcherNotFoundMessage(
        _ matcher: ElementMatcher,
        in screen: Screen? = nil,
        resolutionScope: ResolutionScope = .known
    ) -> String {
        let screen = screen ?? currentScreen
        return Diagnostics.matcherNotFound(
            matcher,
            screenElements: selectElements(in: screen),
            visibleHeistIds: screen.visibleIds,
            resolutionScope: resolutionScope
        )
    }

    func formatMatcher(_ matcher: ElementMatcher) -> String {
        Diagnostics.formatMatcher(matcher)
    }

    private func ambiguousResolution(
        _ matcher: ElementMatcher,
        screenElements: [ScreenElement],
        visibleHeistIds: Set<HeistId>,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        let candidates = screenElements.prefix(10).map { screenElement -> String in
            let element = screenElement.element
            var parts: [String] = []
            if let label = element.label, !label.isEmpty { parts.append("\"\(label)\"") }
            if let identifier = element.identifier, !identifier.isEmpty { parts.append("id=\(identifier)") }
            if let value = element.value, !value.isEmpty { parts.append("value=\(value)") }
            parts.append(Diagnostics.availabilityDescription(for: screenElement, visibleHeistIds: visibleHeistIds))
            return parts.joined(separator: " ")
        }
        let query = formatMatcher(matcher)
        let countLabel = screenElements.count > 10 ? "10+" : "\(screenElements.count)"
        let rangeLabel = screenElements.count > 10 ? "0, 1, 2, ..." : "0–\(screenElements.count - 1)"
        var lines = [
            "\(countLabel) elements match: \(query) (scope: \(resolutionScope.rawValue)) — use ordinal \(rangeLabel) to select one"
        ]
        lines.append(contentsOf: candidates.map { "  \($0)" })
        if screenElements.count > 10 {
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
        (screen ?? currentScreen).orderedElements
    }

    // MARK: - Cache Control

    /// Clear cached element data (used on suspend).
    func clearCache() {
        currentScreen = .empty
        clearPendingRotorResult()
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
        guard let heistId = currentScreen.liveInterface.elementRefs.first(where: { _, ref in
            ref.object === object
        })?.key,
            let cached = currentScreen.findElement(heistId: heistId)
        else {
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
        guard let heistId = screen.liveInterface.heistIdByElement[parsedElement] else { return nil }
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

        if let standaloneElement,
           let known = knownCachedRotorResult(matching: standaloneElement) {
            return known
        }

        guard let element = standaloneElement else { return nil }
        let heistId = pendingRotorHeistId(for: element)
        return ParsedRotorResultObject(
            screenElement: ScreenElement(
                heistId: heistId,
                contentSpaceOrigin: nil,
                element: element
            ),
            isInCurrentHierarchy: false
        )
    }

    private func knownCachedRotorResult(matching rotorElement: AccessibilityElement) -> ParsedRotorResultObject? {
        let candidates = selectElements().filter {
            !visibleIds.contains($0.heistId)
                && Self.matchesCachedRotorResult(knownElement: $0.element, rotorElement: rotorElement)
        }
        guard candidates.count == 1, let candidate = candidates.first else { return nil }
        return ParsedRotorResultObject(screenElement: candidate, isInCurrentHierarchy: false)
    }

    private static func matchesCachedRotorResult(
        knownElement: AccessibilityElement,
        rotorElement: AccessibilityElement
    ) -> Bool {
        guard rotorElement.label?.isEmpty == false
                || rotorElement.value?.isEmpty == false
                || rotorElement.identifier?.isEmpty == false else {
            return false
        }
        guard optionalText(knownElement.label, matches: rotorElement.label),
              optionalText(knownElement.value, matches: rotorElement.value),
              stableTraitNames(knownElement.traits) == stableTraitNames(rotorElement.traits),
              framesApproximatelyMatch(knownElement.shape.frame, rotorElement.shape.frame) else {
            return false
        }
        if let knownIdentifier = knownElement.identifier, !knownIdentifier.isEmpty,
           let rotorIdentifier = rotorElement.identifier, !rotorIdentifier.isEmpty {
            return ElementMatcher.stringEquals(knownIdentifier, rotorIdentifier)
        }
        return true
    }

    private static func optionalText(_ lhs: String?, matches rhs: String?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return ElementMatcher.stringEquals(lhs, rhs)
        default:
            return false
        }
    }

    private static func stableTraitNames(_ traits: AccessibilityTraits) -> Set<String> {
        Set(traits.traitNames).subtracting(AccessibilityPolicy.transientTraitNames)
    }

    private static func framesApproximatelyMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        guard !lhs.isNull, !lhs.isEmpty,
              !rhs.isNull, !rhs.isEmpty,
              lhs.origin.x.isFinite,
              lhs.origin.y.isFinite,
              lhs.size.width.isFinite,
              lhs.size.height.isFinite,
              rhs.origin.x.isFinite,
              rhs.origin.y.isFinite,
              rhs.size.width.isFinite,
              rhs.size.height.isFinite else {
            return false
        }
        let tolerance: CGFloat = 1
        return abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    func preparePendingRotorResult(targetedHeistId: HeistId?) -> UUID? {
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

    func activePendingRotorResult(for target: ElementTarget) -> ScreenElement? {
        guard case .heistId(let heistId) = target else { return nil }
        return activePendingRotorResult(heistId: heistId)
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

    private func activePendingRotorResult(heistId: HeistId) -> ScreenElement? {
        guard case .active(let pendingRotorResult) = pendingRotorState,
              pendingRotorResult.screenElement.heistId == heistId else {
            return nil
        }
        return pendingRotorResult.screenElement
    }

    private func pendingRotorHeistId(for element: AccessibilityElement) -> HeistId {
        let base = Self.IdAssignment.assign([element]).first ?? "element"
        let root = "rotor_result_\(base)"
        var candidate = root
        var suffix = 2
        let knownHeistIds = currentScreen.knownInterface.heistIds
        while knownHeistIds.contains(candidate) {
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

    /// Parse and commit in one step. Most callers use this. A visible refresh
    /// updates live interaction evidence without dropping known semantic
    /// elements when it is still observing the same screen.
    @discardableResult
    func refresh() -> Screen? {
        guard let screen = parse() else { return nil }
        currentScreen = currentScreen.refreshingVisibleState(with: screen)
        return screen
    }

    // MARK: - Interface Read Helpers

    /// Current parser hierarchy plus Button Heist annotations.
    ///
    /// Thin reader over `WireConversion.toInterface` — exists because callers
    /// need the interface of the *current* screen, not an arbitrary one.
    func interface(timestamp: Date = Date()) -> Interface {
        WireConversion.toInterface(from: currentScreen, timestamp: timestamp)
    }

    func interfaceHash() -> String {
        AccessibilityTrace.Capture.hash(interface())
    }

    /// Single-build variant: returns the interface alongside its hash so callers
    /// that need both don't pay for two projection passes.
    func interfaceWithHash(timestamp: Date = Date()) -> (interface: Interface, hash: String) {
        let interface = interface(timestamp: timestamp)
        return (interface, AccessibilityTrace.Capture.hash(interface))
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

extension UIAccessibilityCustomRotor {
    func bhInvocableName(locale: String?) -> String {
        guard name.isEmpty else { return name }

        switch systemRotorType {
        case .none:
            return localizedRotorName(defaultValue: "None", key: "rotor.none.description", locale: locale)
        case .link:
            return localizedRotorName(defaultValue: "Links", key: "rotor.link.description", locale: locale)
        case .visitedLink:
            return localizedRotorName(defaultValue: "Visited Links", key: "rotor.visited_link.description", locale: locale)
        case .heading:
            return localizedRotorName(defaultValue: "Headings", key: "rotor.heading.description", locale: locale)
        case .headingLevel1:
            return localizedRotorName(defaultValue: "Heading 1", key: "rotor.heading_level1.description", locale: locale)
        case .headingLevel2:
            return localizedRotorName(defaultValue: "Heading 2", key: "rotor.heading_level2.description", locale: locale)
        case .headingLevel3:
            return localizedRotorName(defaultValue: "Heading 3", key: "rotor.heading_level3.description", locale: locale)
        case .headingLevel4:
            return localizedRotorName(defaultValue: "Heading 4", key: "rotor.heading_level4.description", locale: locale)
        case .headingLevel5:
            return localizedRotorName(defaultValue: "Heading 5", key: "rotor.heading_level5.description", locale: locale)
        case .headingLevel6:
            return localizedRotorName(defaultValue: "Heading 6", key: "rotor.heading_level6.description", locale: locale)
        case .boldText:
            return localizedRotorName(defaultValue: "Bold Text", key: "rotor.bold_text.description", locale: locale)
        case .italicText:
            return localizedRotorName(defaultValue: "Italic Text", key: "rotor.italic_text.description", locale: locale)
        case .underlineText:
            return localizedRotorName(defaultValue: "Underlined Text", key: "rotor.underline_text.description", locale: locale)
        case .misspelledWord:
            return localizedRotorName(defaultValue: "Misspelled Words", key: "rotor.misspelled_word.description", locale: locale)
        case .image:
            return localizedRotorName(defaultValue: "Images", key: "rotor.image.description", locale: locale)
        case .textField:
            return localizedRotorName(defaultValue: "Text Fields", key: "rotor.text_field.description", locale: locale)
        case .table:
            return localizedRotorName(defaultValue: "Tables", key: "rotor.table.description", locale: locale)
        case .list:
            return localizedRotorName(defaultValue: "Lists", key: "rotor.list.description", locale: locale)
        case .landmark:
            return localizedRotorName(defaultValue: "Landmarks", key: "rotor.landmark.description", locale: locale)
        @unknown default:
            let format = localizedRotorName(
                defaultValue: "Unknown Rotor Type, Raw value: %lld",
                key: "rotor.unknown.description_format",
                locale: locale
            )
            return String(format: format, systemRotorType.rawValue)
        }
    }

    private func localizedRotorName(defaultValue: String, key: String, locale: String?) -> String {
        StringLocalization.preferredBundle(for: locale).localizedString(forKey: key, value: defaultValue, table: nil)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

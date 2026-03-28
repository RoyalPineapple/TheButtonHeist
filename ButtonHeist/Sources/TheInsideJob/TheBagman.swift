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

    /// Weak reference wrapper for accessibility objects (element cache).
    struct WeakObject {
        weak var object: NSObject?
    }

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    // MARK: - Element Storage

    /// Parsed accessibility elements from the last hierarchy refresh.
    private(set) var cachedElements: [AccessibilityElement] = []

    /// Parsed accessibility hierarchy from the last refresh.
    private(set) var cachedHierarchy: [AccessibilityHierarchy] = []

    /// Weak references to accessibility objects from the last parse,
    /// keyed by the parsed element.
    private(set) var elementObjects: [AccessibilityElement: WeakObject] = [:]

    /// Last wire snapshot with assigned heistIds.
    var lastSnapshot: [HeistElement] = []

    /// Hash of the last hierarchy sent to subscribers (for polling comparison).
    var lastHierarchyHash: Int = 0

    /// Screen name from the last snapshot (first header element's label).
    var lastScreenName: String? {
        lastSnapshot.first { $0.traits.contains("header") }?.label
    }

    let parser = AccessibilityHierarchyParser()

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    /// Active scroll container for a scroll_to_visible search.
    /// Weak by rule: TheBagman never owns live UI lifetime.
    private weak var activeScrollSearchView: UIScrollView?

    struct ScrollSearchPreparation {
        let totalItems: Int?
    }

    // MARK: - Element Access

    /// Look up the live NSObject for an element at a given traversal index.
    private func object(at index: Int) -> NSObject? {
        guard index >= 0, index < cachedElements.count else { return nil }
        return elementObjects[cachedElements[index]]?.object
    }

    /// Check if an interactive object exists at the given traversal index.
    func hasInteractiveObject(at index: Int) -> Bool {
        guard let obj = object(at: index) else { return false }
        let el = cachedElements[index]
        return el.respondsToUserInteraction
            || el.traits.contains(.adjustable)
            || !el.customActions.isEmpty
            || obj.accessibilityRespondsToUserInteraction
    }

    /// Return custom action names for the interactive object at the given index.
    func customActionNames(elementAt index: Int) -> [String] {
        object(at: index)?.accessibilityCustomActions?.map { $0.name } ?? []
    }

    /// Perform accessibilityActivate on the object at the given index.
    func activate(elementAt index: Int) -> Bool {
        object(at: index)?.accessibilityActivate() ?? false
    }

    /// Perform accessibilityIncrement on the object at the given index.
    func increment(elementAt index: Int) {
        object(at: index)?.accessibilityIncrement()
    }

    /// Perform accessibilityDecrement on the object at the given index.
    func decrement(elementAt index: Int) {
        object(at: index)?.accessibilityDecrement()
    }

    /// Perform a named custom action on the object at the given index.
    func performCustomAction(named name: String, elementAt index: Int) -> Bool {
        guard let actions = object(at: index)?.accessibilityCustomActions else {
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

    // MARK: - Unified Element Resolution

    /// Result of resolving an ActionTarget to a concrete element.
    struct ResolvedTarget {
        let element: AccessibilityElement
        let traversalIndex: Int
    }

    /// Resolution: heistId → match.
    /// Returns the canonical element and its traversal index, or nil on miss.
    func resolveTarget(_ target: ActionTarget) -> ResolvedTarget? {
        if let heistId = target.heistId {
            guard let wire = lastSnapshot.first(where: { $0.heistId == heistId }) else { return nil }
            let index = wire.order
            guard index >= 0, index < cachedElements.count else { return nil }
            return ResolvedTarget(element: cachedElements[index], traversalIndex: index)
        }
        if let matcher = target.match {
            guard let found = findMatch(matcher) else { return nil }
            return ResolvedTarget(element: found.element, traversalIndex: found.index)
        }
        return nil
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

    /// Build a diagnostic message for a failed element lookup.
    ///
    /// Progressive disclosure tiers:
    /// 1. Near-miss: matched all but one field → "found it, but value='7' not '6'"
    /// 2. Substring: no exact label match → "did you mean 'Save Changes'?"
    /// 3. Total miss: nothing close → compact element summary for self-correction
    func elementNotFoundMessage(for target: ActionTarget) -> String {
        if let heistId = target.heistId {
            return heistIdNotFoundMessage(heistId)
        }
        if let matcher = target.match {
            return matcherNotFoundMessage(matcher)
        }
        return "No element target provided"
    }

    private func heistIdNotFoundMessage(_ heistId: String) -> String {
        let similar = lastSnapshot.map(\.heistId).sorted()
            .filter { $0.contains(heistId) || heistId.contains($0) }
        if similar.isEmpty {
            return "Element not found: \"\(heistId)\" (\(cachedElements.count) elements on screen)"
        }
        return "Element not found: \"\(heistId)\"\nsimilar: \(similar.joined(separator: ", "))"
    }

    private func matcherNotFoundMessage(_ matcher: ElementMatcher) -> String {
        let query = formatMatcher(matcher)

        // Tier 1: Relax one predicate at a time — find what diverged.
        if let nearMiss = findNearMiss(for: matcher) {
            return "No match for: \(query)\n\(nearMiss)"
        }

        // Tier 2: Substring match on label or identifier — "did you mean...?"
        if let label = matcher.label {
            let lower = label.lowercased()
            let candidates = cachedElements
                .compactMap { el -> String? in
                    guard let elLabel = el.label,
                          elLabel.lowercased().contains(lower) || lower.contains(elLabel.lowercased()) else { return nil }
                    return "\"\(elLabel)\""
                }
                .prefix(5)
            if !candidates.isEmpty {
                return "No match for: \(query)\nsimilar labels: \(candidates.joined(separator: ", "))"
            }
        }
        if let id = matcher.identifier {
            let lower = id.lowercased()
            let candidates = cachedElements
                .compactMap { el -> String? in
                    guard let elId = el.identifier,
                          elId.lowercased().contains(lower) || lower.contains(elId.lowercased()) else { return nil }
                    return "\"\(elId)\""
                }
                .prefix(5)
            if !candidates.isEmpty {
                return "No match for: \(query)\nsimilar identifiers: \(candidates.joined(separator: ", "))"
            }
        }

        // Tier 3: Nothing close — dump a compact summary so the agent can self-correct.
        return "No match for: \(query)\n\(compactElementSummary())"
    }

    /// Format a matcher's predicates as a human-readable query string.
    private func formatMatcher(_ matcher: ElementMatcher) -> String {
        var fields: [String] = []
        if let l = matcher.label { fields.append("label=\"\(l)\"") }
        if let id = matcher.identifier { fields.append("identifier=\"\(id)\"") }
        if let v = matcher.value { fields.append("value=\"\(v)\"") }
        if let t = matcher.traits { fields.append("traits=[\(t.joined(separator: ","))]") }
        if let e = matcher.excludeTraits { fields.append("excludeTraits=[\(e.joined(separator: ","))]") }
        return fields.joined(separator: " ")
    }

    /// Try relaxing one predicate at a time. Value is relaxed first (most likely
    /// to drift — e.g. slider moved), then traits, label, identifier.
    /// Only considers relaxations that still have at least one remaining predicate —
    /// dropping the only predicate matches everything, which isn't a useful near-miss.
    /// Returns a diagnostic line or nil if no near-miss found.
    private func findNearMiss(for matcher: ElementMatcher) -> String? {
        typealias Relaxation = (field: String, relaxed: ElementMatcher, actual: (AccessibilityElement) -> String)
        var relaxations: [Relaxation] = []

        if matcher.value != nil {
            relaxations.append((
                field: "value",
                relaxed: ElementMatcher(
                    label: matcher.label, identifier: matcher.identifier,
                    traits: matcher.traits, excludeTraits: matcher.excludeTraits                ),
                actual: { $0.value ?? "(nil)" }
            ))
        }
        if matcher.traits != nil {
            relaxations.append((
                field: "traits",
                relaxed: ElementMatcher(
                    label: matcher.label, identifier: matcher.identifier,
                    value: matcher.value, excludeTraits: matcher.excludeTraits                ),
                actual: { el in
                    UIAccessibilityTraits.knownTraits
                        .filter { el.traits.contains($0.trait) }
                        .map(\.name).joined(separator: ", ")
                }
            ))
        }
        if matcher.label != nil {
            relaxations.append((
                field: "label",
                relaxed: ElementMatcher(
                    identifier: matcher.identifier, value: matcher.value,
                    traits: matcher.traits, excludeTraits: matcher.excludeTraits                ),
                actual: { $0.label ?? "(nil)" }
            ))
        }
        if matcher.identifier != nil {
            relaxations.append((
                field: "identifier",
                relaxed: ElementMatcher(
                    label: matcher.label, value: matcher.value,
                    traits: matcher.traits, excludeTraits: matcher.excludeTraits                ),
                actual: { $0.identifier ?? "(nil)" }
            ))
        }

        for r in relaxations where r.relaxed.hasPredicates {
            if let found = findMatch(r.relaxed) {
                let actualValue = r.actual(found.element)
                return "near miss: matched all fields except \(r.field) — actual \(r.field)=\(actualValue)"
            }
        }
        return nil
    }

    /// Compact summary of on-screen elements for total-miss fallback.
    /// Capped at 20 elements to avoid flooding the response.
    private func compactElementSummary() -> String {
        let cap = 20
        let elements = cachedElements.prefix(cap)
        if elements.isEmpty {
            return "screen is empty (0 elements)"
        }
        var lines = ["\(cachedElements.count) elements on screen:"]
        for el in elements {
            var parts: [String] = []
            if let label = el.label, !label.isEmpty { parts.append("label=\"\(label)\"") }
            if let id = el.identifier, !id.isEmpty { parts.append("id=\"\(id)\"") }
            if let val = el.value, !val.isEmpty { parts.append("value=\"\(val)\"") }
            let traitNames = UIAccessibilityTraits.knownTraits
                .filter { el.traits.contains($0.trait) }
                .map(\.name)
            if !traitNames.isEmpty { parts.append("[\(traitNames.joined(separator: ","))]") }
            lines.append("  \(parts.joined(separator: " "))")
        }
        if cachedElements.count > cap {
            lines.append("  ... and \(cachedElements.count - cap) more")
        }
        return lines.joined(separator: "\n")
    }

    /// Resolve a screen point from an element target or explicit coordinates.
    func resolvePoint(
        from elementTarget: ActionTarget?,
        pointX: Double?,
        pointY: Double?
    ) -> TheSafecracker.PointResolution {
        if let elementTarget {
            guard let resolved = resolveTarget(elementTarget) else {
                return .failure(.failure(.elementNotFound, message: elementNotFoundMessage(for: elementTarget)))
            }
            return .success(resolved.element.activationPoint)
        } else if let x = pointX, let y = pointY {
            return .success(CGPoint(x: x, y: y))
        } else {
            return .failure(.failure(.elementNotFound, message: "No target specified"))
        }
    }

    /// Resolve the accessibility frame for an element target.
    func resolveFrame(for elementTarget: ActionTarget) -> CGRect? {
        guard let resolved = resolveTarget(elementTarget) else { return nil }
        return resolved.element.shape.frame
    }

    func ensureOnScreen(for target: ActionTarget) async {
        guard let resolved = resolveTarget(target) else { return }
        await ensureOnScreen(elementAt: resolved.traversalIndex)
    }

    func ensureFirstResponderOnScreen() async {
        guard let responder = tripwire.currentFirstResponder() else { return }
        await ensureOnScreen(object: responder)
    }

    func scroll(elementAt index: Int, direction: UIAccessibilityScrollDirection) -> Bool {
        guard let object = object(at: index),
              let scrollView = scrollableAncestor(of: object, includeSelf: true) else { return false }
        return scrollByPage(scrollView, direction: direction)
    }

    func scrollToVisible(elementAt index: Int) -> Bool {
        guard let object = object(at: index) else { return false }
        let elementFrame = object.accessibilityFrame
        guard !elementFrame.isNull && !elementFrame.isEmpty,
              let scrollView = scrollableAncestor(of: object, includeSelf: true) else { return false }
        return scrollToMakeVisible(elementFrame, in: scrollView)
    }

    func scrollToEdge(elementAt index: Int, edge: ScrollEdge) -> Bool {
        guard let object = object(at: index),
              let scrollView = scrollableAncestor(of: object, includeSelf: true) else { return false }

        let insets = scrollView.adjustedContentInset
        var newOffset = scrollView.contentOffset

        switch edge {
        case .top:
            newOffset.y = -insets.top
        case .bottom:
            newOffset.y = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        case .left:
            newOffset.x = -insets.left
        case .right:
            newOffset.x = scrollView.contentSize.width + insets.right - scrollView.frame.width
        }

        if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y {
            return true
        }
        scrollView.setContentOffset(newOffset, animated: true)
        return true
    }

    func beginScrollSearch() -> ScrollSearchPreparation? {
        guard let scrollView = findFirstScrollView() else {
            activeScrollSearchView = nil
            return nil
        }
        activeScrollSearchView = scrollView
        return ScrollSearchPreparation(totalItems: queryCollectionTotalItems(scrollView))
    }

    func scrollActiveSearchContainer(direction: ScrollSearchDirection) -> Bool {
        guard let scrollView = activeScrollSearchView else { return false }
        return scrollByPage(scrollView, direction: uiScrollDirection(for: direction))
    }

    func moveActiveSearchContainerToOppositeEdge(from direction: ScrollSearchDirection) {
        guard let scrollView = activeScrollSearchView else { return }
        let insets = scrollView.adjustedContentInset

        switch direction {
        case .down:
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -insets.top), animated: false)
        case .up:
            let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: maxY), animated: false)
        case .right:
            scrollView.setContentOffset(CGPoint(x: -insets.left, y: scrollView.contentOffset.y), animated: false)
        case .left:
            let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
            scrollView.setContentOffset(CGPoint(x: maxX, y: scrollView.contentOffset.y), animated: false)
        }
    }

    func endScrollSearch() {
        activeScrollSearchView = nil
    }

    // MARK: - Refresh

    /// Trigger a refresh of the accessibility data.
    /// - Returns: true if data was successfully refreshed.
    @discardableResult
    func refreshElements() -> Bool {
        refreshAccessibilityData() != nil
    }

    // MARK: - Targeted Element Refresh

    /// Re-parse a single element from its backing NSObject without a full tree refresh.
    /// Returns the updated AccessibilityElement, or nil if the object has been deallocated.
    func refreshElement(at index: Int) -> AccessibilityElement? {
        guard let object = object(at: index) else { return nil }
        let probe = ButtonHeistHostingView(target: object)
        let hierarchy = parser.parseAccessibilityHierarchy(in: probe, rotorResultLimit: 0)
        guard let updated = hierarchy.flattenToElements().first else { return nil }

        // Update the cache in place
        let stale = cachedElements[index]
        cachedElements[index] = updated
        elementObjects[stale] = nil
        elementObjects[updated] = WeakObject(object: object)
        return updated
    }

    /// Re-parse a single element identified by its AccessibilityElement key.
    func refreshElement(_ element: AccessibilityElement) -> AccessibilityElement? {
        guard let index = cachedElements.firstIndex(of: element) else { return nil }
        return refreshElement(at: index)
    }

    /// Clear all cached element data (used on suspend).
    func clearCache() {
        cachedHierarchy.removeAll()
        cachedElements.removeAll()
        elementObjects.removeAll()
        lastSnapshot.removeAll()
        lastHierarchyHash = 0
    }

    // MARK: - Accessibility Data Refresh

    /// Refresh the accessibility hierarchy. Provides a visitor closure to the parser
    /// that captures weak references to interactive objects for action dispatch.
    /// Returns the hierarchy tree for callers that need it (e.g., sendInterface).
    @discardableResult
    func refreshAccessibilityData() -> [AccessibilityHierarchy]? {
        let windows = tripwire.getTraversableWindows()
        guard !windows.isEmpty else { return nil }

        var allHierarchy: [AccessibilityHierarchy] = []
        var newElementObjects: [AccessibilityElement: WeakObject] = [:]
        var allElements: [AccessibilityElement] = []

        // Accessibility property reads (label, traits, customActions, etc.) return
        // autoreleased ObjC objects.  Draining per-window keeps the high-water mark
        // proportional to a single window's tree rather than the entire UI.
        for (window, rootView) in windows {
            autoreleasepool {
                let baseIndex = allElements.count
                let windowTree = parser.parseAccessibilityHierarchy(in: rootView, rotorResultLimit: 0) { element, _, object in
                    newElementObjects[element] = WeakObject(object: object)
                }
                let windowElements = windowTree.flattenToElements()

                // Wrap each window's tree in a container node when multiple windows are present
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

        elementObjects = newElementObjects
        cachedHierarchy = allHierarchy
        cachedElements = allElements
        return allHierarchy
    }

    /// TheTripwire handles window access and animation detection.
    let tripwire: TheTripwire

    // MARK: - Topology-Based Screen Change

    /// Private UIAccessibilityTrait for back buttons (bit 27).
    /// Set by UIKit on navigation bar back button items.
    private static let backButtonTrait = UIAccessibilityTraits(rawValue: 0x8000000)

    /// Did the accessibility topology change between two element snapshots?
    /// Checks two signals using the parser's native `AccessibilityElement`:
    /// - Back button trait appeared or disappeared (navigation push/pop)
    /// - Header structure changed completely (all header labels replaced)
    func isTopologyChanged(
        before: [AccessibilityElement],
        after: [AccessibilityElement]
    ) -> Bool {
        let hadBackButton = before.contains { $0.traits.contains(Self.backButtonTrait) }
        let hasBackButton = after.contains { $0.traits.contains(Self.backButtonTrait) }
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
        beforeSnapshot: [HeistElement],
        beforeCachedElements: [AccessibilityElement],
        beforeVC: ObjectIdentifier? = nil,
        target: ActionTarget? = nil
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

        // Single read of the post-settle state
        let afterTree = refreshAccessibilityData()
        let afterSnapshot = snapshotElements()

        // Screen change gate: VC identity OR accessibility topology
        let afterVC = tripwire.topmostViewController().map(ObjectIdentifier.init)
        let isScreenChange = tripwire.isScreenChange(before: beforeVC, after: afterVC)
            || isTopologyChanged(before: beforeCachedElements, after: cachedElements)
        let delta = computeDelta(
            before: beforeSnapshot, after: afterSnapshot,
            afterTree: afterTree, isScreenChange: isScreenChange
        )

        // Capture a recording frame after the action completes
        captureActionFrame()

        // Look up the acted-on element in the post-action parsed hierarchy
        var elementLabel: String?
        var elementValue: String?
        var elementTraits: [String]?
        if let target {
            let postElement = resolveTarget(target)?.element
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

    // MARK: - Screen Capture

    /// Capture the screen by compositing all traversable windows.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = tripwire.getTraversableWindows()
        guard let background = windows.last else { return nil }
        let bounds = background.window.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        let image = renderer.image { _ in
            // Draw windows bottom-to-top (lowest level first) so frontmost paints on top
            for (window, _) in windows.reversed() {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        }
        return (image, bounds)
    }

    /// Capture the screen including the fingerprint overlay (for recordings).
    /// Unlike captureScreen(), this includes TheFingerprints.FingerprintWindow so
    /// tap/swipe indicators are visible in the video.
    func captureScreenForRecording() -> UIImage? {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return nil
        }

        let allWindows = windowScene.windows
            .filter { !$0.isHidden && $0.bounds.size != .zero }
            .sorted { $0.windowLevel < $1.windowLevel }

        guard let background = allWindows.first else { return nil }
        let bounds = background.bounds

        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            for window in allWindows {
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
        }
    }

    /// If recording, capture a bonus frame to ensure the action's visual effect is captured.
    func captureActionFrame() {
        stakeout?.captureActionFrame()
    }

    // MARK: - Scroll Helpers

    private func ensureOnScreen(elementAt index: Int) async {
        guard let object = object(at: index) else { return }
        await ensureOnScreen(object: object)
    }

    private func ensureOnScreen(object: NSObject) async {
        let frame = object.accessibilityFrame
        guard !frame.isNull && !frame.isEmpty else { return }

        let screenBounds = UIScreen.main.bounds
        if screenBounds.contains(frame) { return }

        guard let scrollView = scrollableAncestor(of: object, includeSelf: false) else { return }
        if scrollToMakeVisible(frame, in: scrollView) {
            _ = await tripwire.waitForAllClear(timeout: 1.0)
            refreshAccessibilityData()
        }
    }

    private func findFirstScrollView() -> UIScrollView? {
        for index in cachedElements.indices {
            guard let object = object(at: index),
                  let scrollView = scrollableAncestor(of: object, includeSelf: true) else { continue }
            return scrollView
        }
        return nil
    }

    private func scrollableAncestor(of object: NSObject, includeSelf: Bool) -> UIScrollView? {
        var current: NSObject? = includeSelf ? object : nextAncestor(of: object)
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                return scrollView
            }
            current = nextAncestor(of: candidate)
        }
        return nil
    }

    private func queryCollectionTotalItems(_ scrollView: UIScrollView) -> Int? {
        if let collectionView = scrollView as? UICollectionView {
            let sections = collectionView.numberOfSections
            var total = 0
            for section in 0..<sections {
                total += collectionView.numberOfItems(inSection: section)
            }
            return total
        }
        if let tableView = scrollView as? UITableView {
            let sections = tableView.numberOfSections
            var total = 0
            for section in 0..<sections {
                total += tableView.numberOfRows(inSection: section)
            }
            return total
        }
        return nil
    }

    private func scrollByPage(_ scrollView: UIScrollView, direction: UIAccessibilityScrollDirection) -> Bool {
        let overlap: CGFloat = 44
        let size = scrollView.frame.size
        let offset = scrollView.contentOffset
        let contentSize = scrollView.contentSize
        let insets = scrollView.adjustedContentInset

        var newOffset = offset

        switch direction {
        case .up:
            newOffset.y = max(offset.y - (size.height - overlap), -insets.top)
        case .down:
            newOffset.y = min(offset.y + size.height - overlap,
                             contentSize.height + insets.bottom - size.height)
        case .left:
            newOffset.x = max(offset.x - (size.width - overlap), -insets.left)
        case .right:
            newOffset.x = min(offset.x + size.width - overlap,
                             contentSize.width + insets.right - size.width)
        case .next:
            newOffset.y = min(offset.y + size.height - overlap,
                             contentSize.height + insets.bottom - size.height)
        case .previous:
            newOffset.y = max(offset.y - (size.height - overlap), -insets.top)
        @unknown default:
            return false
        }

        if newOffset.x == offset.x && newOffset.y == offset.y { return false }
        scrollView.setContentOffset(newOffset, animated: true)
        return true
    }

    private func scrollToMakeVisible(_ targetFrame: CGRect, in scrollView: UIScrollView) -> Bool {
        let targetInScrollView = scrollView.convert(targetFrame, from: nil)

        let visibleRect = CGRect(
            x: scrollView.contentOffset.x + scrollView.adjustedContentInset.left,
            y: scrollView.contentOffset.y + scrollView.adjustedContentInset.top,
            width: scrollView.frame.width - scrollView.adjustedContentInset.left - scrollView.adjustedContentInset.right,
            height: scrollView.frame.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom
        )

        if visibleRect.contains(targetInScrollView) { return true }

        var newOffset = scrollView.contentOffset

        if targetInScrollView.minX < visibleRect.minX {
            newOffset.x -= visibleRect.minX - targetInScrollView.minX
        } else if targetInScrollView.maxX > visibleRect.maxX {
            newOffset.x += targetInScrollView.maxX - visibleRect.maxX
        }

        if targetInScrollView.minY < visibleRect.minY {
            newOffset.y -= visibleRect.minY - targetInScrollView.minY
        } else if targetInScrollView.maxY > visibleRect.maxY {
            newOffset.y += targetInScrollView.maxY - visibleRect.maxY
        }

        let insets = scrollView.adjustedContentInset
        let maxX = scrollView.contentSize.width + insets.right - scrollView.frame.width
        let maxY = scrollView.contentSize.height + insets.bottom - scrollView.frame.height
        newOffset.x = max(-insets.left, min(newOffset.x, maxX))
        newOffset.y = max(-insets.top, min(newOffset.y, maxY))

        if newOffset.x == scrollView.contentOffset.x && newOffset.y == scrollView.contentOffset.y {
            return true
        }

        scrollView.setContentOffset(newOffset, animated: true)
        return true
    }

    private func nextAncestor(of candidate: NSObject) -> NSObject? {
        if let view = candidate as? UIView {
            return view.superview
        } else if let element = candidate as? UIAccessibilityElement {
            return element.accessibilityContainer as? NSObject
        } else if candidate.responds(to: Selector(("accessibilityContainer"))) {
            return candidate.value(forKey: "accessibilityContainer") as? NSObject
        }
        return nil
    }

    private func uiScrollDirection(for direction: ScrollSearchDirection) -> UIAccessibilityScrollDirection {
        switch direction {
        case .down: return .down
        case .up: return .up
        case .left: return .left
        case .right: return .right
        }
    }
}

// MARK: - AccessibilityHierarchy Reindexing

extension Array where Element == AccessibilityHierarchy {
    func reindexed(offset: Int) -> [AccessibilityHierarchy] {
        guard offset != 0 else { return self }
        return map { node in
            switch node {
            case let .element(element, index):
                return .element(element, traversalIndex: index + offset)
            case let .container(container, children):
                return .container(container, children: children.reindexed(offset: offset))
            }
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

#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension TheSafecracker {

    // MARK: - Auto-Scroll to Visible

    /// Ensure the targeted element is within the screen bounds before interaction.
    /// If the element's accessibility frame is outside the screen, scrolls the
    /// nearest scrollable ancestor to bring it into view, waits for the scroll
    /// animation to settle via presentation-layer diffing, and refreshes the
    /// element cache so subsequent reads return updated positions.
    ///
    /// Best-effort: does nothing if the element is already visible, cannot be
    /// resolved, or has no scrollable ancestor.
    func ensureOnScreen(for target: ActionTarget) async {
        await bagman?.ensureOnScreen(for: target)
    }

    /// Ensure the current first responder is within the screen bounds.
    /// Used by commands that operate on the responder chain (edit actions,
    /// resign, pasteboard) so the human observer can see the target.
    func ensureFirstResponderOnScreen() async {
        await bagman?.ensureFirstResponderOnScreen()
    }

    // MARK: - Scroll

    func executeScroll(_ target: ScrollTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }

        guard let resolved = bagman.resolveTarget(elementTarget) else {
            return .failure(.elementNotFound, message: bagman.elementNotFoundMessage(for: elementTarget))
        }

        let uiDirection: UIAccessibilityScrollDirection
        switch target.direction {
        case .up:       uiDirection = .up
        case .down:     uiDirection = .down
        case .left:     uiDirection = .left
        case .right:    uiDirection = .right
        case .next:     uiDirection = .next
        case .previous: uiDirection = .previous
        }

        let success = bagman.scroll(elementAt: resolved.traversalIndex, direction: uiDirection)
        return InteractionResult(
            success: success,
            method: .scroll,
            message: success ? nil : "No scrollable ancestor found for element",
            value: nil
        )
    }

    func executeScrollToEdge(_ target: ScrollToEdgeTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let elementTarget = target.elementTarget else {
            return .failure(.scrollToEdge, message: "Element target required for scroll_to_edge")
        }

        guard let resolved = bagman.resolveTarget(elementTarget) else {
            return .failure(.elementNotFound, message: bagman.elementNotFoundMessage(for: elementTarget))
        }

        let success = bagman.scrollToEdge(elementAt: resolved.traversalIndex, edge: target.edge)
        return InteractionResult(
            success: success,
            method: .scrollToEdge,
            message: success ? nil : "No scrollable ancestor found for element",
            value: nil
        )
    }

    func executeScrollToVisible(_ target: ScrollToVisibleTarget) async -> InteractionResult {
        guard let bagman else {
            return .failure(.scrollToVisible, message: "No element store available")
        }

        let searchTarget = ActionTarget(heistId: target.heistId, match: target.match)
        guard searchTarget.heistId != nil || searchTarget.match != nil else {
            return .failure(.scrollToVisible, message: "Element target required for scroll_to_visible")
        }
        let maxScrolls = target.resolvedMaxScrolls
        let primaryDirection = target.resolvedDirection

        // Phase 0: Check current tree for match (no conversion to wire types)
        bagman.refreshAccessibilityData()
        if let found = bagman.resolveTarget(searchTarget) {
            // Already visible — scroll into view if partially off-screen
            _ = bagman.scrollToVisible(elementAt: found.traversalIndex)
            let wireElement = bagman.convertAndAssignId(found.element, index: found.traversalIndex)
            return InteractionResult(
                success: true, method: .scrollToVisible, message: nil, value: nil,
                scrollSearchResult: ScrollSearchResult(
                    scrollCount: 0, uniqueElementsSeen: bagman.cachedElements.count,
                    totalItems: nil, exhaustive: false, foundElement: wireElement
                )
            )
        }

        guard let searchPreparation = bagman.beginScrollSearch() else {
            return .failure(.scrollToVisible, message: "No scroll view found on screen")
        }
        defer { bagman.endScrollSearch() }

        let totalItems = searchPreparation.totalItems

        // Track unique elements by stable identity (label + identifier).
        // AccessibilityElement.Hashable includes frame/activationPoint which change
        // between scroll positions, so we use a geometry-free key instead.
        var seenKeys = Set(bagman.cachedElements.map(\.stableKey))
        var scrollCount = 0

        // Phase 1: Scroll in primary direction
        let result = await scrollSearchLoop(
            target: searchTarget,
            direction: primaryDirection,
            maxScrolls: maxScrolls,
            scrollCount: &scrollCount,
            seenKeys: &seenKeys, totalItems: totalItems
        )
        if let result { return result }

        // Phase 2: Jump to opposite edge, scroll back in primary direction
        // to cover content before the original starting position.
        // Skip if Phase 1 exhausted the scroll budget — no point paying for
        // the edge jump + refresh with zero remaining scrolls.
        if scrollCount < maxScrolls {
            bagman.moveActiveSearchContainerToOppositeEdge(from: primaryDirection)
            if let tripwire {
                _ = await tripwire.waitForAllClear(timeout: 1.0)
            }
            bagman.refreshAccessibilityData()

            let result2 = await scrollSearchLoop(
                target: searchTarget,
                direction: primaryDirection,
                maxScrolls: maxScrolls,
                scrollCount: &scrollCount,
                seenKeys: &seenKeys, totalItems: totalItems
            )
            if let result2 { return result2 }
        }

        // Phase 3: Not found
        let exhaustive = totalItems.map { seenKeys.count >= $0 } ?? false
        return InteractionResult(
            success: false, method: .scrollToVisible,
            message: "Element not found after \(scrollCount) scrolls", value: nil,
            scrollSearchResult: ScrollSearchResult(
                scrollCount: scrollCount, uniqueElementsSeen: seenKeys.count,
                totalItems: totalItems, exhaustive: exhaustive
            )
        )
    }

    // MARK: - Scroll Search Helpers

    /// Run a scroll-and-check loop in one direction. Target resolution happens
    /// on the canonical accessibility snapshot each step — no wire conversion
    /// until a match is found.
    private func scrollSearchLoop(
        target: ActionTarget,
        direction: ScrollSearchDirection,
        maxScrolls: Int,
        scrollCount: inout Int,
        seenKeys: inout Set<AccessibilityElement.StableKey>,
        totalItems: Int?
    ) async -> InteractionResult? {
        while scrollCount < maxScrolls {
            guard let bagman else { return nil }
            let scrolled = bagman.scrollActiveSearchContainer(direction: direction)
            if !scrolled { break }
            scrollCount += 1

            if let tripwire {
                _ = await tripwire.waitForAllClear(timeout: 1.0)
            }
            bagman.refreshAccessibilityData()
            // Match against canonical elements — no HeistElement conversion
            if let found = bagman.resolveTarget(target) {
                let wireElement = bagman.convertAndAssignId(found.element, index: found.traversalIndex)
                return InteractionResult(
                    success: true, method: .scrollToVisible, message: nil, value: nil,
                    scrollSearchResult: ScrollSearchResult(
                        scrollCount: scrollCount, uniqueElementsSeen: seenKeys.count,
                        totalItems: totalItems, exhaustive: false, foundElement: wireElement
                    )
                )
            }

            // Track new elements for scroll-end detection
            let currentKeys = bagman.cachedElements.map(\.stableKey)
            let previousCount = seenKeys.count
            seenKeys.formUnion(currentKeys)

            // No new elements → reached the end in this direction
            if seenKeys.count == previousCount { break }

            // Exhaustive check for collection/table views
            if let totalItems, seenKeys.count >= totalItems {
                return InteractionResult(
                    success: false, method: .scrollToVisible,
                    message: "Element not found (exhaustive search)", value: nil,
                    scrollSearchResult: ScrollSearchResult(
                        scrollCount: scrollCount, uniqueElementsSeen: seenKeys.count,
                        totalItems: totalItems, exhaustive: true
                    )
                )
            }
        }
        return nil
    }

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let resolved = bagman.resolveTarget(target) else {
            return .failure(.elementNotFound, message: bagman.elementNotFoundMessage(for: target))
        }

        if let interactivityError = bagman.checkElementInteractivity(resolved.element) {
            return .failure(.elementNotFound, message: interactivityError)
        }

        let point = resolved.element.activationPoint

        guard bagman.hasInteractiveObject(at: resolved.traversalIndex) else {
            return .failure(.activate, message: "Element does not support activation")
        }

        // Try accessibilityActivate via the live object reference
        let activateResult = bagman.activate(elementAt: resolved.traversalIndex)
        if activateResult {
            fingerprints.showFingerprint(at: point)
            return InteractionResult(success: true, method: .activate, message: nil, value: nil)
        }

        // Fall back to synthetic touch injection
        if await tap(at: point) {
            fingerprints.showFingerprint(at: point)
            return InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
        }

        return .failure(.activate, message: "Activation failed")
    }

    func executeIncrement(_ target: ActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let resolved = bagman.resolveTarget(target) else {
            return .failure(.elementNotFound, message: bagman.elementNotFoundMessage(for: target))
        }

        guard bagman.hasInteractiveObject(at: resolved.traversalIndex) else {
            return .failure(.increment, message: "Element does not support increment")
        }

        bagman.increment(elementAt: resolved.traversalIndex)
        fingerprints.showFingerprint(at: resolved.element.activationPoint)
        return InteractionResult(success: true, method: .increment, message: nil, value: nil)
    }

    func executeDecrement(_ target: ActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let resolved = bagman.resolveTarget(target) else {
            return .failure(.elementNotFound, message: bagman.elementNotFoundMessage(for: target))
        }

        guard bagman.hasInteractiveObject(at: resolved.traversalIndex) else {
            return .failure(.decrement, message: "Element does not support decrement")
        }

        bagman.decrement(elementAt: resolved.traversalIndex)
        fingerprints.showFingerprint(at: resolved.element.activationPoint)
        return InteractionResult(success: true, method: .decrement, message: nil, value: nil)
    }

    func executeCustomAction(_ target: CustomActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target.elementTarget)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let resolved = bagman.resolveTarget(target.elementTarget) else {
            return .failure(.elementNotFound, message: bagman.elementNotFoundMessage(for: target.elementTarget))
        }

        guard bagman.hasInteractiveObject(at: resolved.traversalIndex) else {
            return .failure(.customAction, message: "Element does not support custom actions")
        }

        let success = bagman.performCustomAction(named: target.actionName, elementAt: resolved.traversalIndex)
        return InteractionResult(
            success: success, method: .customAction,
            message: success ? nil : "Action '\(target.actionName)' not found",
            value: nil
        )
    }

    func executeEditAction(_ target: EditActionTarget) async -> InteractionResult {
        await ensureFirstResponderOnScreen()
        let success = performEditAction(target.action)
        return InteractionResult(success: success, method: .editAction, message: nil, value: nil)
    }

    // MARK: - Pasteboard

    func executeSetPasteboard(_ target: SetPasteboardTarget) async -> InteractionResult {
        await ensureFirstResponderOnScreen()
        UIPasteboard.general.string = target.text
        return InteractionResult(
            success: true,
            method: .setPasteboard,
            message: nil,
            value: target.text
        )
    }

    func executeGetPasteboard() async -> InteractionResult {
        let text = UIPasteboard.general.string
        return InteractionResult(
            success: true,
            method: .getPasteboard,
            message: text == nil ? "Pasteboard is empty or contains non-text data" : nil,
            value: text
        )
    }

    func executeResignFirstResponder() async -> InteractionResult {
        await ensureFirstResponderOnScreen()
        let success = resignFirstResponder()
        return InteractionResult(
            success: success, method: .resignFirstResponder,
            message: success ? nil : "No first responder found",
            value: nil
        )
    }

    // MARK: - Touch Gestures

    func executeTap(_ target: TouchTapTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY) {
        case .failure(let result):
            return result
        case .success(let point):
            if await tap(at: point) {
                fingerprints.showFingerprint(at: point)
                return InteractionResult(success: true, method: .syntheticTap, message: nil, value: nil)
            }
            return .failure(.syntheticTap, message: "Touch tap failed")
        }
    }

    func executeLongPress(_ target: LongPressTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.pointX, pointY: target.pointY) {
        case .failure(let result):
            return result
        case .success(let point):
            let success = await longPress(at: point, duration: clampDuration(target.duration))
            if success { fingerprints.showFingerprint(at: point) }
            return InteractionResult(success: success, method: .syntheticLongPress, message: nil, value: nil)
        }
    }

    func executeSwipe(_ target: SwipeTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }

        // Resolution priority:
        // 1. start/end unit points → resolve via element frame
        // 2. direction + element target → expand to unit-point defaults
        // 3. Raw startX/startY/endX/endY or direction → existing absolute behavior

        let resolvedStart: UnitPoint? = target.start
        let resolvedEnd: UnitPoint? = target.end

        // If direction is provided with an element target but no explicit unit points,
        // expand direction to default unit-point pair
        let unitStart: UnitPoint?
        let unitEnd: UnitPoint?
        if let start = resolvedStart, let end = resolvedEnd {
            unitStart = start
            unitEnd = end
        } else if let direction = target.direction, target.elementTarget != nil {
            unitStart = direction.defaultStart
            unitEnd = direction.defaultEnd
        } else {
            unitStart = nil
            unitEnd = nil
        }

        if let unitStart, let unitEnd {
            guard let elementTarget = target.elementTarget else {
                return .failure(.syntheticSwipe, message: "Unit-point swipe requires an element target")
            }
            guard let frame = bagman.resolveFrame(for: elementTarget) else {
                return .failure(.elementNotFound, message: "Element not found")
            }

            let startPoint = CGPoint(
                x: frame.origin.x + unitStart.x * frame.width,
                y: frame.origin.y + unitStart.y * frame.height
            )
            let endPoint = CGPoint(
                x: frame.origin.x + unitEnd.x * frame.width,
                y: frame.origin.y + unitEnd.y * frame.height
            )

            let duration = clampDuration(target.duration ?? 0.15)
            let success = await swipe(from: startPoint, to: endPoint, duration: duration)
            return InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
        }

        // Existing absolute-coordinate path
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result):
            return result
        case .success(let startPoint):
            let endPoint: CGPoint
            if let endX = target.endX, let endY = target.endY {
                endPoint = CGPoint(x: endX, y: endY)
            } else if let direction = target.direction {
                let dist = 200.0
                switch direction {
                case .up:    endPoint = CGPoint(x: startPoint.x, y: startPoint.y - dist)
                case .down:  endPoint = CGPoint(x: startPoint.x, y: startPoint.y + dist)
                case .left:  endPoint = CGPoint(x: startPoint.x - dist, y: startPoint.y)
                case .right: endPoint = CGPoint(x: startPoint.x + dist, y: startPoint.y)
                }
            } else {
                return .failure(.syntheticSwipe, message: "No end point or direction")
            }

            let duration = clampDuration(target.duration ?? 0.15)
            let success = await swipe(from: startPoint, to: endPoint, duration: duration)
            return InteractionResult(success: success, method: .syntheticSwipe, message: nil, value: nil)
        }
    }

    func executeDrag(_ target: DragTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result):
            return result
        case .success(let startPoint):
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await drag(from: startPoint, to: target.endPoint, duration: duration)
            return InteractionResult(success: success, method: .syntheticDrag, message: nil, value: nil)
        }
    }

    func executePinch(_ target: PinchTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result):
            return result
        case .success(let center):
            let spread = target.spread ?? 100.0
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await pinch(center: center, scale: CGFloat(target.scale), spread: CGFloat(spread), duration: duration)
            return InteractionResult(success: success, method: .syntheticPinch, message: nil, value: nil)
        }
    }

    func executeRotate(_ target: RotateTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result):
            return result
        case .success(let center):
            let radius = target.radius ?? 100.0
            let duration = clampDuration(target.duration ?? 0.5)
            let success = await rotate(center: center, angle: CGFloat(target.angle), radius: CGFloat(radius), duration: duration)
            return InteractionResult(success: success, method: .syntheticRotate, message: nil, value: nil)
        }
    }

    func executeTwoFingerTap(_ target: TwoFingerTapTarget) async -> InteractionResult {
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.centerX, pointY: target.centerY) {
        case .failure(let result):
            return result
        case .success(let center):
            let spread = target.spread ?? 40.0
            let success = await twoFingerTap(at: center, spread: CGFloat(spread))
            if success { fingerprints.showFingerprint(at: center) }
            return InteractionResult(success: success, method: .syntheticTwoFingerTap, message: nil, value: nil)
        }
    }

    func executeDrawPath(_ target: DrawPathTarget) async -> InteractionResult {
        let cgPoints = target.points.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Path requires at least 2 points")
        }

        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await drawPath(points: cgPoints, duration: duration)
        return InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    func executeDrawBezier(_ target: DrawBezierTarget) async -> InteractionResult {
        guard !target.segments.isEmpty else {
            return .failure(.syntheticDrawPath, message: "Bezier path requires at least 1 segment")
        }

        let samplesPerSegment = min(target.samplesPerSegment ?? 20, 1000)
        let pathPoints = BezierSampler.sampleBezierPath(
            startPoint: target.startPoint,
            segments: target.segments,
            samplesPerSegment: samplesPerSegment
        )
        let cgPoints = pathPoints.map { $0.cgPoint }

        guard cgPoints.count >= 2 else {
            return .failure(.syntheticDrawPath, message: "Sampled bezier produced fewer than 2 points")
        }

        let duration = resolveDuration(target.duration, velocity: target.velocity, points: cgPoints)
        let success = await drawPath(points: cgPoints, duration: duration)
        return InteractionResult(success: success, method: .syntheticDrawPath, message: nil, value: nil)
    }

    // MARK: - Duration Helpers

    /// Default gesture duration when none is specified (0.5s).
    private static let defaultGestureDuration: Double = 0.5

    /// Minimum allowed gesture duration (10ms).
    private static let minGestureDuration: Double = 0.01

    /// Maximum allowed gesture duration (60s). Prevents runaway gestures
    /// from holding the main thread for unreasonable periods.
    private static let maxGestureDuration: Double = 60.0

    func clampDuration(_ value: Double?) -> Double {
        min(max(value ?? Self.defaultGestureDuration, Self.minGestureDuration), Self.maxGestureDuration)
    }

    func resolveDuration(_ duration: Double?, velocity: Double?, points: [CGPoint]) -> TimeInterval {
        let result: Double
        if let d = duration {
            result = d
        } else if let velocity = velocity, velocity > 0 {
            var totalLength: Double = 0
            for i in 1..<points.count {
                let dx = points[i].x - points[i-1].x
                let dy = points[i].y - points[i-1].y
                totalLength += sqrt(dx * dx + dy * dy)
            }
            result = totalLength / velocity
        } else {
            result = Self.defaultGestureDuration
        }
        return clampDuration(result)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
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
        guard let bagman else { return }
        guard let index = bagman.resolveTraversalIndex(for: target) else { return }
        guard let object = bagman.object(at: index) else { return }
        await ensureOnScreen(object: object)
    }

    /// Ensure the current first responder is within the screen bounds.
    /// Used by commands that operate on the responder chain (edit actions,
    /// resign, pasteboard) so the human observer can see the target.
    func ensureFirstResponderOnScreen() async {
        guard let view = firstResponderView() else { return }
        await ensureOnScreen(object: view)
    }

    /// Shared implementation: check if the object's accessibility frame is
    /// within the screen bounds, and scroll the nearest ancestor if not.
    private func ensureOnScreen(object: NSObject) async {
        let frame = object.accessibilityFrame
        guard !frame.isNull && !frame.isEmpty else { return }

        let screenBounds = UIScreen.main.bounds
        if screenBounds.contains(frame) { return }

        var current: NSObject? = nextAncestor(of: object)
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                if scrollToMakeVisible(frame, in: scrollView) {
                    if let tripwire {
                        _ = await tripwire.waitForAllClear(timeout: 1.0)
                    }
                    bagman?.refreshAccessibilityData()
                }
                return
            }
            current = nextAncestor(of: candidate)
        }
    }

    // MARK: - Scroll

    func executeScroll(_ target: ScrollTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let elementTarget = target.elementTarget else {
            return .failure(.scroll, message: "Element target required for scroll")
        }

        guard let index = bagman.resolveTraversalIndex(for: elementTarget) else {
            return .failure(.elementNotFound, message: "Element not found for scroll target")
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

        let success = scroll(elementAt: index, direction: uiDirection)
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

        guard let index = bagman.resolveTraversalIndex(for: elementTarget) else {
            return .failure(.elementNotFound, message: "Element not found for scroll_to_edge target")
        }

        let success = scrollToEdge(elementAt: index, edge: target.edge)
        return InteractionResult(
            success: success,
            method: .scrollToEdge,
            message: success ? nil : "No scrollable ancestor found for element",
            value: nil
        )
    }

    func executeScrollToVisible(_ target: ActionTarget) -> InteractionResult {
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let index = bagman.resolveTraversalIndex(for: target) else {
            return .failure(.elementNotFound, message: "Element not found for scroll_to_visible target")
        }

        let success = scrollToVisible(elementAt: index)
        return InteractionResult(
            success: success,
            method: .scrollToVisible,
            message: success ? nil : "No scrollable ancestor found for element",
            value: nil
        )
    }

    // MARK: - Scroll Implementation

    /// Walk the view/container hierarchy from an element to find the nearest
    /// scrollable UIScrollView ancestor, then scroll it by one page via `setContentOffset`.
    private func scroll(elementAt index: Int, direction: UIAccessibilityScrollDirection) -> Bool {
        guard let object = bagman?.object(at: index) else { return false }

        var current: NSObject? = object
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                return scrollByPage(scrollView, direction: direction)
            }
            current = nextAncestor(of: candidate)
        }
        return false
    }

    /// Scroll a UIScrollView by approximately one page in the given direction.
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

    /// Scroll the nearest UIScrollView ancestor so the element's accessibility frame
    /// is fully visible within the scroll view's viewport.
    private func scrollToVisible(elementAt index: Int) -> Bool {
        guard let object = bagman?.object(at: index) else { return false }

        let elementFrame = object.accessibilityFrame
        guard !elementFrame.isNull && !elementFrame.isEmpty else { return false }

        var current: NSObject? = object
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
                return scrollToMakeVisible(elementFrame, in: scrollView)
            }
            current = nextAncestor(of: candidate)
        }
        return false
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

    /// Scroll the nearest UIScrollView ancestor to an edge.
    private func scrollToEdge(elementAt index: Int, edge: ScrollEdge) -> Bool {
        guard let object = bagman?.object(at: index) else { return false }

        var current: NSObject? = object
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView,
               scrollView.isScrollEnabled {
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
            current = nextAncestor(of: candidate)
        }
        return false
    }

    /// Walk up one level in the view/container hierarchy.
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

    // MARK: - Accessibility Actions

    func executeActivate(_ target: ActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let element = bagman.findElement(for: target) else {
            return .failure(.elementNotFound, message: "Element not found for target")
        }

        if let interactivityError = bagman.checkElementInteractivity(element) {
            return .failure(.elementNotFound, message: interactivityError)
        }

        let point = element.activationPoint

        guard let index = bagman.resolveTraversalIndex(for: target),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.activate, message: "Element does not support activation")
        }

        // Try accessibilityActivate via the live object reference
        let activateResult = bagman.activate(elementAt: index)
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
        guard let element = bagman.findElement(for: target) else {
            return .failure(.elementNotFound, message: "Element not found")
        }

        guard let index = bagman.resolveTraversalIndex(for: target),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.increment, message: "Element does not support increment")
        }

        bagman.increment(elementAt: index)
        fingerprints.showFingerprint(at: element.activationPoint)
        return InteractionResult(success: true, method: .increment, message: nil, value: nil)
    }

    func executeDecrement(_ target: ActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard let element = bagman.findElement(for: target) else {
            return .failure(.elementNotFound, message: "Element not found")
        }

        guard let index = bagman.resolveTraversalIndex(for: target),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.decrement, message: "Element does not support decrement")
        }

        bagman.decrement(elementAt: index)
        fingerprints.showFingerprint(at: element.activationPoint)
        return InteractionResult(success: true, method: .decrement, message: nil, value: nil)
    }

    func executeCustomAction(_ target: CustomActionTarget) async -> InteractionResult {
        await ensureOnScreen(for: target.elementTarget)
        guard let bagman else {
            return .failure(.elementNotFound, message: "No element store available")
        }
        guard bagman.findElement(for: target.elementTarget) != nil else {
            return .failure(.elementNotFound, message: "Element not found")
        }

        guard let index = bagman.resolveTraversalIndex(for: target.elementTarget),
              bagman.hasInteractiveObject(at: index) else {
            return .failure(.customAction, message: "Element does not support custom actions")
        }

        let success = bagman.performCustomAction(named: target.actionName, elementAt: index)
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
        switch bagman.resolvePoint(from: target.elementTarget, pointX: target.startX, pointY: target.startY) {
        case .failure(let result):
            return result
        case .success(let startPoint):
            let endPoint: CGPoint
            if let endX = target.endX, let endY = target.endY {
                endPoint = CGPoint(x: endX, y: endY)
            } else if let direction = target.direction {
                let dist = target.distance ?? 200.0
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

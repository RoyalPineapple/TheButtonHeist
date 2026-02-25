#if canImport(UIKit)
#if DEBUG
import UIKit
import TheGoods

extension InsideMan {

    // MARK: - Animation Detection

    /// Animation key prefixes to ignore during detection.
    /// These are persistent or internal animations that don't indicate meaningful UI transitions.
    private static let ignoredAnimationKeyPrefixes: [String] = [
        "_UIParallaxMotionEffect",
    ]

    /// Poll interval for checking animation state (10ms).
    private static let animationPollInterval: UInt64 = 10_000_000

    /// Returns true if any layer in the traversable window hierarchy has active animations.
    func hasActiveAnimations() -> Bool {
        getTraversableWindows().contains { layerTreeHasAnimations($0.window.layer) }
    }

    /// Iterative (stack-based) walk of the layer tree checking for animation keys.
    private func layerTreeHasAnimations(_ root: CALayer) -> Bool {
        var stack: [CALayer] = [root]
        while let layer = stack.popLast() {
            if let keys = layer.animationKeys(), !keys.isEmpty {
                let hasRelevantAnimation = keys.contains { key in
                    !Self.ignoredAnimationKeyPrefixes.contains { key.hasPrefix($0) }
                }
                if hasRelevantAnimation {
                    return true
                }
            }
            if let sublayers = layer.sublayers {
                stack.append(contentsOf: sublayers)
            }
        }
        return false
    }

    /// Wait until all animations in the traversable window hierarchy have completed,
    /// or until the timeout expires.
    /// - Returns: true if animations settled before timeout, false if timed out
    func waitForAnimationsToSettle(timeout: TimeInterval = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.animationPollInterval)
            if !hasActiveAnimations() {
                return true
            }
        }
        return false
    }

    // MARK: - Wait For Idle Handler

    func handleWaitForIdle(_ target: WaitForIdleTarget, respond: @escaping (Data) -> Void) async {
        let timeout = min(target.timeout ?? 5.0, 60.0)
        let settled = await waitForAnimationsToSettle(timeout: timeout)

        guard let hierarchyTree = refreshAccessibilityData() else {
            sendMessage(.error("Could not access root view"), respond: respond)
            return
        }

        let elements = cachedElements.enumerated().map { convertElement($0.element, index: $0.offset) }
        let tree = hierarchyTree.map { convertHierarchyNode($0) }
        let payload = Interface(timestamp: Date(), elements: elements, tree: tree)

        let result = ActionResult(
            success: true,
            method: .waitForIdle,
            message: settled ? "UI idle" : "Timed out after \(timeout)s, UI may still be animating",
            interfaceDelta: InterfaceDelta(
                kind: .screenChanged,
                elementCount: elements.count,
                newInterface: payload
            ),
            animating: settled ? nil : true
        )
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Action Result with Delta

    /// Snapshot the hierarchy after an action, diff against before-state, return enriched ActionResult.
    /// Waits briefly for animations to settle (0.5s). If the screen changed and animations
    /// are still active (e.g. navigation spring), waits 1s more and re-snapshots.
    func actionResultWithDelta(
        success: Bool,
        method: ActionMethod,
        message: String? = nil,
        value: String? = nil,
        beforeElements: [HeistElement]
    ) async -> ActionResult {
        guard success else {
            return ActionResult(success: false, method: method, message: message, value: value)
        }

        // Quick check: if no animations, just yield briefly for the tree to update.
        if !hasActiveAnimations() {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        } else {
            // Animations active — wait for them to end (fast for toggles/menus)
            // or cap at 0.5s (avoids blocking on long simulator springs).
            _ = await waitForAnimationsToSettle(timeout: 0.5)
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms layout
        }

        var afterTree = refreshAccessibilityData()
        var afterElements = snapshotElements()
        var delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)

        // If the screen changed and animations are still running (navigation push),
        // the source screen is still sliding out. Wait a fixed 1s for the destination
        // to fully appear, then re-snapshot. This is cheaper than polling
        // refreshAccessibilityData() repeatedly during the transition.
        if delta.kind != .noChange && hasActiveAnimations() {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            afterTree = refreshAccessibilityData()
            afterElements = snapshotElements()
            delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)
        }

        // Capture a recording frame after the action completes
        captureActionFrame()

        return ActionResult(
            success: true,
            method: method,
            message: message,
            value: value,
            interfaceDelta: delta
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

#if canImport(UIKit)
#if DEBUG
import UIKit
import TheScore

extension InsideJob {

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

        let elements = snapshotElements()
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
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        } else {
            // Animations active — wait for them to end (fast for toggles/menus)
            // or cap at 0.25s (avoids blocking on long simulator springs).
            _ = await waitForAnimationsToSettle(timeout: 0.25)
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms layout
        }

        var afterTree = refreshAccessibilityData()
        var afterElements = snapshotElements()
        var delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)

        // If the screen changed and animations are still running (navigation push),
        // wait up to 350ms for the hierarchy to stabilize rather than sleeping a fixed 1s.
        if delta.kind != .noChange && hasActiveAnimations() {
            let pollInterval: UInt64 = 35_000_000 // 35ms
            let maxWait: UInt64 = 350_000_000 // 350ms
            var elapsed: UInt64 = 0
            var stableSamples = 0
            var lastSignature = hierarchySignature(afterElements)

            while elapsed < maxWait {
                try? await Task.sleep(nanoseconds: pollInterval)
                elapsed += pollInterval

                afterTree = refreshAccessibilityData()
                afterElements = snapshotElements()
                delta = computeDelta(before: beforeElements, after: afterElements, afterTree: afterTree)

                let signature = hierarchySignature(afterElements)
                if signature == lastSignature {
                    stableSamples += 1
                } else {
                    stableSamples = 0
                    lastSignature = signature
                }

                if !hasActiveAnimations() || stableSamples >= 2 {
                    break
                }
            }
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

    private func hierarchySignature(_ elements: [HeistElement]) -> Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(element)
        }
        return hasher.finalize()
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

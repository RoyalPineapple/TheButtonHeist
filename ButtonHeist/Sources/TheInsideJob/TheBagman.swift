#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

/// The crew member who holds and manipulates the mcguffin (the UI elements).
///
/// TheBagman owns the full lifecycle of the heist's target: reading the UI,
/// storing element references, computing diffs, detecting animations, and
/// capturing visual state. Live object pointers never leave TheBagman.
@MainActor
final class TheBagman {

    /// Weak reference wrapper for accessibility objects (element cache).
    struct WeakObject {
        weak var object: NSObject?
    }

    // MARK: - Element Storage

    /// Parsed accessibility elements from the last hierarchy refresh.
    private(set) var cachedElements: [AccessibilityElement] = []

    /// Weak references to accessibility objects from the last parse,
    /// keyed by the parsed element.
    private(set) var elementObjects: [AccessibilityElement: WeakObject] = [:]

    /// Hash of the last hierarchy sent to subscribers (for polling comparison).
    var lastHierarchyHash: Int = 0

    let parser = AccessibilityHierarchyParser()

    /// Back-reference to the stakeout for recording frame capture.
    weak var stakeout: TheStakeout?

    // MARK: - Element Access

    /// Look up the live NSObject for an element at a given traversal index.
    func object(at index: Int) -> NSObject? {
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

    // MARK: - Element Resolution

    func findElement(for target: ActionTarget) -> AccessibilityElement? {
        if let identifier = target.identifier {
            return cachedElements.first { $0.identifier == identifier }
        }
        if let index = target.order, index >= 0, index < cachedElements.count {
            return cachedElements[index]
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

    func resolveTraversalIndex(for target: ActionTarget) -> Int? {
        if let index = target.order {
            return index
        }
        if let identifier = target.identifier {
            return cachedElements.firstIndex { $0.identifier == identifier }
        }
        return nil
    }

    /// Resolve a screen point from an element target or explicit coordinates.
    func resolvePoint(
        from elementTarget: ActionTarget?,
        pointX: Double?,
        pointY: Double?
    ) -> TheSafecracker.PointResolution {
        if let elementTarget {
            guard let element = findElement(for: elementTarget) else {
                return .failure(.failure(.elementNotFound, message: "Element not found"))
            }
            return .success(element.activationPoint)
        } else if let x = pointX, let y = pointY {
            return .success(CGPoint(x: x, y: y))
        } else {
            return .failure(.failure(.elementNotFound, message: "No target specified"))
        }
    }

    // MARK: - Refresh

    /// Trigger a refresh of the accessibility data.
    /// - Returns: true if data was successfully refreshed.
    @discardableResult
    func refreshElements() -> Bool {
        refreshAccessibilityData() != nil
    }

    /// Clear all cached element data (used on suspend).
    func clearCache() {
        cachedElements.removeAll()
        elementObjects.removeAll()
        lastHierarchyHash = 0
    }

    // MARK: - Accessibility Data Refresh

    /// Refresh the accessibility hierarchy. Provides a visitor closure to the parser
    /// that captures weak references to interactive objects for action dispatch.
    /// Returns the hierarchy tree for callers that need it (e.g., sendInterface).
    @discardableResult
    func refreshAccessibilityData() -> [AccessibilityHierarchy]? {
        let windows = getTraversableWindows()
        guard !windows.isEmpty else { return nil }

        var allHierarchy: [AccessibilityHierarchy] = []
        var newElementObjects: [AccessibilityElement: WeakObject] = [:]
        var allElements: [AccessibilityElement] = []

        for (window, rootView) in windows {
            let baseIndex = allElements.count
            let windowTree = parser.parseAccessibilityHierarchy(in: rootView) { element, _, object in
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

        elementObjects = newElementObjects
        cachedElements = allElements
        return allHierarchy
    }

    /// Returns all windows that should be included in the accessibility traversal,
    /// sorted by windowLevel descending (frontmost first).
    /// Excludes our own overlay windows (TheFingerprints.FingerprintWindow).
    func getTraversableWindows() -> [(window: UIWindow, rootView: UIView)] {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            return []
        }

        return windowScene.windows
            .filter { window in
                !(window is TheFingerprints.FingerprintWindow) &&
                !window.isHidden &&
                window.bounds.size != .zero
            }
            .sorted { $0.windowLevel > $1.windowLevel }
            .map { ($0, $0 as UIView) }
    }

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

    // MARK: - Screen Capture

    /// Capture the screen by compositing all traversable windows.
    func captureScreen() -> (image: UIImage, bounds: CGRect)? {
        let windows = getTraversableWindows()
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

#endif // DEBUG
#endif // canImport(UIKit)

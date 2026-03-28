#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

/// The crew member who holds and manipulates the mcguffin (the UI elements).
///
/// TheBagman owns the accessibility data lifecycle: reading the UI, storing
/// element references, computing diffs, and capturing visual state. Live
/// object pointers never leave TheBagman. Uses TheTripwire for timing
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

    /// Weak references to accessibility objects from the last parse,
    /// keyed by the parsed element.
    private(set) var elementObjects: [AccessibilityElement: WeakObject] = [:]

    /// Last snapshot with assigned heistIds — used for heistId-based targeting.
    var lastSnapshot: [HeistElement] = []

    /// Hash of the last hierarchy sent to subscribers (for polling comparison).
    var lastHierarchyHash: Int = 0

    /// Screen name from the last snapshot (first header element's label).
    var lastScreenName: String? {
        lastSnapshot.first { $0.traits.contains(.header) }?.label
    }

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
        if let heistId = target.heistId {
            guard let snapshotEl = lastSnapshot.first(where: { $0.heistId == heistId }) else {
                return nil
            }
            let index = snapshotEl.order
            guard index >= 0, index < cachedElements.count else { return nil }
            return cachedElements[index]
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
        if let identifier = target.identifier {
            return cachedElements.firstIndex { $0.identifier == identifier }
        }
        if let heistId = target.heistId {
            return lastSnapshot.first { $0.heistId == heistId }?.order
        }
        if let index = target.order {
            return index
        }
        return nil
    }

    /// Build an error message for a failed element lookup, including substring hints.
    func elementNotFoundMessage(for target: ActionTarget) -> String {
        if let heistId = target.heistId {
            let similar = lastSnapshot
                .filter { $0.heistId.contains(heistId) || heistId.contains($0.heistId) }
                .map(\.heistId)
            if similar.isEmpty {
                return "Element not found: \"\(heistId)\""
            }
            return "Element not found: \"\(heistId)\"\nsimilar: \(similar.joined(separator: ", "))"
        }
        if let identifier = target.identifier {
            return "Element not found: identifier \"\(identifier)\""
        }
        if let order = target.order {
            return "Element not found: order \(order) (snapshot has \(cachedElements.count) elements)"
        }
        return "No element target provided"
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

    /// Resolve the accessibility frame for an element target.
    func resolveFrame(for elementTarget: ActionTarget) -> CGRect? {
        guard let element = findElement(for: elementTarget) else { return nil }
        return element.shape.frame
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
        cachedElements = allElements
        return allHierarchy
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
        let hadBackButton = before.contains { $0.traits.contains(.backButton) }
        let hasBackButton = after.contains { $0.traits.contains(.backButton) }
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
        beforeSnapshot: ElementSnapshot,
        beforeCachedElements: [AccessibilityElement],
        beforeVC: ObjectIdentifier? = nil,
        target: ActionTarget? = nil
    ) async -> ActionResult {
        guard success else {
            return ActionResult(success: false, method: method, message: message, value: value,
                                screenName: beforeSnapshot.screenName)
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
        var elementTraits: [HeistTrait]?
        if let target {
            let postElement = findElement(for: target)
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

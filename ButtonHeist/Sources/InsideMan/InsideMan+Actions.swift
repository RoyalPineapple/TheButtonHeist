#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheGoods

extension InsideMan {

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

    /// Check if an AccessibilityElement element is interactive based on traits
    /// - Returns: nil if interactive, or an error string if not interactive
    func checkElementInteractivity(_ element: AccessibilityElement) -> String? {
        // Check for notEnabled trait (disabled element)
        if element.traits.contains(.notEnabled) {
            return "Element is disabled (has 'notEnabled' trait)"
        }

        // Check for commonly non-interactive element types
        // Note: We don't strictly block static traits because some views
        // may have tap gestures without accessibility traits (e.g., SwiftUI .onTapGesture)
        let staticTraitsOnly = element.traits.isSubset(of: [.staticText, .image, .header])
        let hasInteractiveTraits = element.traits.contains(.button) ||
                                   element.traits.contains(.link) ||
                                   element.traits.contains(.adjustable) ||
                                   element.traits.contains(.searchField) ||
                                   element.traits.contains(.keyboardKey)

        // If element only has static traits and no interactive traits, warn but don't block
        if staticTraitsOnly && !hasInteractiveTraits && element.customActions.isEmpty {
            serverLog("Warning: Element '\(element.description)' has only static traits, tap may not work")
        }

        return nil  // Element is considered interactive
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

    // MARK: - Direct Accessibility Actions

    /// Calls accessibilityActivate() on the live object at the given traversal index.
    func activate(elementAt index: Int) -> Bool {
        interactiveObjects[index]?.object?.accessibilityActivate() ?? false
    }

    /// Calls accessibilityIncrement() on the live object at the given traversal index.
    private func increment(elementAt index: Int) {
        interactiveObjects[index]?.object?.accessibilityIncrement()
    }

    /// Calls accessibilityDecrement() on the live object at the given traversal index.
    private func decrement(elementAt index: Int) {
        interactiveObjects[index]?.object?.accessibilityDecrement()
    }

    /// Performs a custom action by name on the live object at the given traversal index.
    private func performCustomAction(named name: String, elementAt index: Int) -> Bool {
        guard let actions = interactiveObjects[index]?.object?.accessibilityCustomActions else {
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

    /// Returns names of custom actions on the live object at the given traversal index.
    func customActionNames(elementAt index: Int) -> [String] {
        interactiveObjects[index]?.object?.accessibilityCustomActions?.map { $0.name } ?? []
    }

    /// Returns whether a live interactive object exists at the given traversal index.
    func hasInteractiveObject(at index: Int) -> Bool {
        interactiveObjects[index]?.object != nil
    }

    // MARK: - Action Handlers

    func handleActivate(_ target: ActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: "Element not found for target"
            )), respond: respond)
            return
        }

        if let interactivityError = checkElementInteractivity(element) {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .elementNotFound,
                message: interactivityError
            )), respond: respond)
            return
        }

        let point = element.activationPoint

        // Guard: element must be in interactive cache
        guard let index = resolveTraversalIndex(for: target),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .activate,
                message: "Element does not support activation"
            )), respond: respond)
            return
        }

        // Try accessibilityActivate via the live object reference
        if activate(elementAt: index) {
            TapVisualizerView.showTap(at: point)
            let result = await actionResultWithDelta(success: true, method: .activate, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        // Fall back to synthetic touch injection
        if theSafecracker.tap(at: point) {
            TapVisualizerView.showTap(at: point)
            let result = await actionResultWithDelta(success: true, method: .syntheticTap, beforeElements: beforeElements)
            sendMessage(.actionResult(result), respond: respond)
            return
        }

        sendMessage(.actionResult(ActionResult(
            success: false,
            method: .activate,
            message: "Activation failed"
        )), respond: respond)
    }

    func handleIncrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        guard let index = resolveTraversalIndex(for: target),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .increment,
                message: "Element does not support increment"
            )), respond: respond)
            return
        }

        increment(elementAt: index)
        TapVisualizerView.showTap(at: element.activationPoint)
        let result = await actionResultWithDelta(success: true, method: .increment, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleDecrement(_ target: ActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        guard let element = findElement(for: target) else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        guard let index = resolveTraversalIndex(for: target),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .decrement,
                message: "Element does not support decrement"
            )), respond: respond)
            return
        }

        decrement(elementAt: index)
        TapVisualizerView.showTap(at: element.activationPoint)
        let result = await actionResultWithDelta(success: true, method: .decrement, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    func handleCustomAction(_ target: CustomActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        guard findElement(for: target.elementTarget) != nil else {
            sendMessage(.actionResult(ActionResult(success: false, method: .elementNotFound)), respond: respond)
            return
        }

        guard let index = resolveTraversalIndex(for: target.elementTarget),
              hasInteractiveObject(at: index) else {
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .customAction,
                message: "Element does not support custom actions"
            )), respond: respond)
            return
        }

        let success = performCustomAction(named: target.actionName, elementAt: index)
        let result = await actionResultWithDelta(
            success: success,
            method: .customAction,
            message: success ? nil : "Action '\(target.actionName)' not found",
            beforeElements: beforeElements
        )
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Edit Action Handler

    func handleEditAction(_ target: EditActionTarget, respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        guard let action = TheSafecracker.EditAction(rawValue: target.action) else {
            let valid = TheSafecracker.EditAction.allCases.map(\.rawValue).joined(separator: ", ")
            sendMessage(.actionResult(ActionResult(
                success: false,
                method: .editAction,
                message: "Unknown edit action '\(target.action)'. Valid: \(valid)"
            )), respond: respond)
            return
        }

        let success = theSafecracker.performEditAction(action)
        let result = await actionResultWithDelta(success: success, method: .editAction, beforeElements: beforeElements)
        sendMessage(.actionResult(result), respond: respond)
    }

    // MARK: - Resign First Responder Handler

    func handleResignFirstResponder(respond: @escaping (Data) -> Void) async {
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        let success = theSafecracker.resignFirstResponder()
        let result = await actionResultWithDelta(
            success: success, method: .resignFirstResponder,
            message: success ? nil : "No first responder found",
            beforeElements: beforeElements
        )
        sendMessage(.actionResult(result), respond: respond)
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

    // MARK: - Screen Request Handler

    func handleScreen(respond: @escaping (Data) -> Void) {
        serverLog("Screen requested")

        guard let (image, bounds) = captureScreen() else {
            sendMessage(.error("Could not access app window"), respond: respond)
            return
        }

        guard let pngData = image.pngData() else {
            sendMessage(.error("Failed to encode screen as PNG"), respond: respond)
            return
        }

        let payload = ScreenPayload(
            pngData: pngData.base64EncodedString(),
            width: bounds.width,
            height: bounds.height
        )

        sendMessage(.screen(payload), respond: respond)
        serverLog("Screen sent: \(pngData.count) bytes")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

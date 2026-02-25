#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheGoods

extension InsideMan {

    // MARK: - Text Entry Handler

    func handleTypeText(_ target: TypeTextTarget, respond: @escaping (Data) -> Void) async {
        await performTypeText(target, respond: respond)
    }

    private func performTypeText(_ target: TypeTextTarget, respond: @escaping (Data) -> Void) async {
        let interKeyDelay: UInt64 = 30_000_000 // 30ms
        refreshAccessibilityData()
        let beforeElements = snapshotElements()

        // Step 1: If elementTarget provided, tap to focus and wait for keyboard
        if let elementTarget = target.elementTarget {
            refreshAccessibilityData()
            guard let element = findElement(for: elementTarget) else {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .elementNotFound,
                    message: "Target element not found"
                )), respond: respond)
                return
            }

            let point = element.activationPoint
            if !theSafecracker.tap(at: point) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Failed to tap target element to bring up keyboard"
                )), respond: respond)
                return
            }
            TapVisualizerView.showTap(at: point)

            // Wait for keyboard to appear (up to 2 seconds)
            var keyboardAppeared = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if theSafecracker.isKeyboardVisible() {
                    keyboardAppeared = true
                    break
                }
            }

            if !keyboardAppeared {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Keyboard did not appear. Ensure the software keyboard is enabled (Simulator > I/O > Keyboard > uncheck 'Connect Hardware Keyboard')."
                )), respond: respond)
                return
            }
        } else {
            if !theSafecracker.isKeyboardVisible() {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Keyboard not visible. Provide an elementTarget to focus a text field, or ensure the keyboard is already showing."
                )), respond: respond)
                return
            }
        }

        // Step 2: Delete characters if requested
        if let deleteCount = target.deleteCount, deleteCount > 0 {
            if !(await theSafecracker.deleteText(count: deleteCount, interKeyDelay: interKeyDelay)) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Could not get UIKeyboardImpl instance for delete. Keyboard may not be active."
                )), respond: respond)
                return
            }
        }

        // Step 3: Type text if provided
        if let text = target.text, !text.isEmpty {
            if !(await theSafecracker.typeText(text, interKeyDelay: interKeyDelay)) {
                sendMessage(.actionResult(ActionResult(
                    success: false,
                    method: .typeText,
                    message: "Could not get UIKeyboardImpl instance for typing. Keyboard may not be active."
                )), respond: respond)
                return
            }
        }

        // Step 4: Read back value if elementTarget provided
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        var fieldValue: String?
        if let elementTarget = target.elementTarget {
            refreshAccessibilityData()
            if let element = findElement(for: elementTarget) {
                fieldValue = element.value
            }
        }

        let result = await actionResultWithDelta(
            success: true,
            method: .typeText,
            value: fieldValue,
            beforeElements: beforeElements
        )
        sendMessage(.actionResult(result), respond: respond)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

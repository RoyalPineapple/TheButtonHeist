#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

extension TheSafecracker {

    // MARK: - Text Entry

    func executeTypeText(_ target: TypeTextTarget) async -> InteractionResult {
        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)

        // Step 1: If elementTarget provided, tap to focus and wait for keyboard
        if let elementTarget = target.elementTarget {
            guard let element = bagman?.findElement(for: elementTarget) else {
                return .failure(.elementNotFound, message: "Target element not found")
            }

            let point = element.activationPoint
            if !tap(at: point) {
                return .failure(.typeText, message: "Failed to tap target element to bring up keyboard")
            }
            fingerprints.showFingerprint(at: point)

            var keyboardAppeared = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if isKeyboardVisible() {
                    keyboardAppeared = true
                    break
                }
            }

            if !keyboardAppeared {
                return .failure(.typeText, message: "Keyboard did not appear. Ensure the software keyboard is enabled (Simulator > I/O > Keyboard > uncheck 'Connect Hardware Keyboard').")
            }
        } else {
            if !isKeyboardVisible() {
                return .failure(.typeText, message: "Keyboard not visible. Provide an elementTarget to focus a text field, or ensure the keyboard is already showing.")
            }
        }

        // Step 2: Delete characters if requested
        if let deleteCount = target.deleteCount, deleteCount > 0 {
            if !(await deleteText(count: deleteCount, interKeyDelay: interKeyDelay)) {
                return .failure(.typeText, message: "Could not get UIKeyboardImpl instance for delete. Keyboard may not be active.")
            }
        }

        // Step 3: Type text if provided
        if let text = target.text, !text.isEmpty {
            if !(await typeText(text, interKeyDelay: interKeyDelay)) {
                return .failure(.typeText, message: "Could not get UIKeyboardImpl instance for typing. Keyboard may not be active.")
            }
        }

        // Step 4: Refresh accessibility data and read back value
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        bagman?.refreshElements()

        var fieldValue: String?
        if let elementTarget = target.elementTarget {
            if let element = bagman?.findElement(for: elementTarget) {
                fieldValue = element.value
            }
        }

        return InteractionResult(success: true, method: .typeText, message: nil, value: fieldValue)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

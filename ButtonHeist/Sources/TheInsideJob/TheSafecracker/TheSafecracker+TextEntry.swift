#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

extension TheSafecracker {

    // MARK: - Text Entry

    func executeTypeText(_ target: TypeTextTarget) async -> InteractionResult {
        let interKeyDelay = min(TheSafecracker.defaultInterKeyDelay, TheSafecracker.maxInterKeyDelay)

        // Step 0: If elementTarget provided, ensure it's on screen before tapping
        if let elementTarget = target.elementTarget {
            await ensureOnScreen(for: elementTarget)
        }

        // Step 1: If elementTarget provided, tap to focus and wait for keyboard
        if let elementTarget = target.elementTarget {
            guard let element = bagman?.findElement(for: elementTarget) else {
                return .failure(.elementNotFound, message: "Target element not found")
            }

            let point = element.activationPoint
            if await !tap(at: point) {
                return .failure(.typeText, message: "Failed to tap target element to bring up keyboard")
            }
            fingerprints.showFingerprint(at: point)

            var inputReady = false
            for _ in 0..<20 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                if hasActiveTextInput() {
                    inputReady = true
                    break
                }
            }

            if !inputReady {
                let msg = "No active text input after tapping element. " +
                    "The element may not be a text field."
                return .failure(.typeText, message: msg)
            }
        } else {
            if !hasActiveTextInput() {
                let msg = "No active text input. Provide an elementTarget to focus " +
                    "a text field, or ensure a text field is already focused."
                return .failure(.typeText, message: msg)
            }
        }

        // Step 2: Clear existing text if requested
        if target.clearFirst == true {
            if !(await clearText()) {
                return .failure(.typeText, message: "Failed to clear existing text.")
            }
        }

        // Step 3: Delete characters if requested
        if let deleteCount = target.deleteCount, deleteCount > 0 {
            if !(await deleteText(count: deleteCount, interKeyDelay: interKeyDelay)) {
                return .failure(.typeText, message: "No keyboard or focused text input available for delete.")
            }
        }

        // Step 4: Type text if provided
        if let text = target.text, !text.isEmpty {
            if !(await typeText(text, interKeyDelay: interKeyDelay)) {
                return .failure(.typeText, message: "No keyboard or focused text input available for typing.")
            }
        }

        // Step 5: Refresh accessibility data and read back value
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

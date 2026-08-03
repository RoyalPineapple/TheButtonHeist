#if canImport(UIKit)
import UIKit

@MainActor
class DeterministicTextField: UITextField {
    private var hasFocus = false
    private(set) var resignationCount = 0

    override var isFirstResponder: Bool {
        hasFocus
    }

    override func becomeFirstResponder() -> Bool {
        hasFocus = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        resignationCount += 1
        hasFocus = false
        return true
    }
}
#endif

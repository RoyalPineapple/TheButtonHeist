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

@MainActor
final class DeterministicTouchReceiver: UIView {
    private let onTouchEnded: @MainActor () -> Void
    private(set) var completedTouchCount = 0

    init(
        frame: CGRect,
        onTouchEnded: @escaping @MainActor () -> Void
    ) {
        self.onTouchEnded = onTouchEnded
        super.init(frame: frame)
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        completedTouchCount += touches.count
        onTouchEnded()
    }
}
#endif

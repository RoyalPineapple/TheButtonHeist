#if canImport(UIKit)
#if DEBUG
import UIKit
import ButtonHeistSupport

@MainActor
final class SafecrackerKeyboardInput {

    private var keyboardVisibleFlag = false
    private let keyboardBridgeProvider: () -> KeyboardBridge?

    init(keyboardBridgeProvider: @escaping () -> KeyboardBridge? = { KeyboardBridge.shared() }) {
        self.keyboardBridgeProvider = keyboardBridgeProvider
    }

    func startObservation() {
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardFrameDidChange),
                           name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardWillShow),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardDidHide),
                           name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    func stopObservation() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        center.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        center.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    var isKeyboardVisible: Bool {
        keyboardVisibleFlag
    }

    var hasActiveTextInput: Bool {
        activeKeyboardInput() != nil
    }

    func typeText(
        _ text: String,
        interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay
    ) async -> KeyboardTextInjectionOutcome {
        guard let keyboard = activeKeyboardInput() else {
            return .failed(.noActiveInput(strategy: UIKeyboardImplTextInjection.strategyName))
        }
        var iterator = text.makeIterator()
        guard var character = iterator.next() else { return .dispatched }

        while true {
            let result = keyboard.type(character)
            if case .failed = result { return result }
            guard let nextCharacter = iterator.next() else { return .dispatched }
            guard await Task.cancellableSleep(nanoseconds: interKeyDelay) else {
                return .failed(.cancelled(strategy: UIKeyboardImplTextInjection.strategyName))
            }
            character = nextCharacter
        }
    }

    func clearText(
        existingValue: String?,
        interKeyDelay: UInt64 = TheSafecracker.defaultInterKeyDelay
    ) async -> KeyboardTextInjectionOutcome {
        guard let keyboard = activeKeyboardInput() else {
            return .failed(.noActiveInput(strategy: UIKeyboardImplTextInjection.strategyName))
        }

        if keyboard.selectAllTextIfPossible() {
            return keyboard.deleteBackward()
        }

        guard let existingValue else {
            return .failed(.unavailableClearTextValue(strategy: UIKeyboardImplTextInjection.strategyName))
        }

        let deleteCount = existingValue.count
        for index in 0..<deleteCount {
            let result = keyboard.deleteBackward()
            if case .failed = result { return result }
            let isLastCharacter = index == deleteCount - 1
            if !isLastCharacter {
                guard await Task.cancellableSleep(nanoseconds: interKeyDelay) else {
                    return .failed(.cancelled(strategy: UIKeyboardImplTextInjection.strategyName))
                }
            }
        }
        return .dispatched
    }

    @objc private func keyboardFrameDidChange(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let screenBounds = notification.object
            .flatMap { $0 as? UIScreen }?.bounds
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?.screen.bounds
            ?? .zero
        keyboardVisibleFlag = endFrame.intersects(screenBounds)
            && endFrame.height > 0
            && endFrame.origin.y < screenBounds.height
    }

    @objc private func keyboardWillShow() { keyboardVisibleFlag = true }
    @objc private func keyboardDidHide() { keyboardVisibleFlag = false }

    private func activeKeyboardInput() -> KeyboardBridge? {
        guard let keyboard = keyboardBridgeProvider(), keyboard.hasActiveInput else {
            return nil
        }
        return keyboard
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

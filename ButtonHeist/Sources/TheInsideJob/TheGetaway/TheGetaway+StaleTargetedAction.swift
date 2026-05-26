#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheGetaway {

    func staleTargetedActionFailure(for message: ClientMessage, backgroundTrace: AccessibilityTrace?) -> ActionResult? {
        guard let backgroundTrace,
              let backgroundDelta = backgroundTrace.backgroundDelta,
              backgroundDelta.isScreenChanged,
              brains.screenChangedSinceLastSent,
              message.isStaleSensitiveTargetedAction else {
            return nil
        }

        let lastScreen = brains.lastSentScreenId ?? "unknown"
        let currentScreen = brains.screenId ?? "unknown"
        var builder = ActionResultBuilder(
            method: TheBrains.diagnosticMethod(for: message),
            screenName: brains.screenName,
            screenId: brains.screenId
        )
        builder.message = "Action skipped because target became stale after a screen change; "
            + "retry against the current interface. Screen changed while you were thinking "
            + "(\(lastScreen) -> \(currentScreen))."
        builder.accessibilityTrace = backgroundTrace
        return builder.failure(errorKind: .actionFailed)
    }
}

private extension ClientMessage {
    var isStaleSensitiveTargetedAction: Bool {
        switch self {
        case .activate,
             .increment,
             .decrement,
             .rotor:
            return true
        case .touchTap(let target):
            return target.elementTarget != nil
        case .touchLongPress(let target):
            return target.elementTarget != nil
        case .touchSwipe(let target):
            return target.elementTarget != nil
        case .touchDrag(let target):
            return target.elementTarget != nil
        case .touchPinch(let target):
            return target.elementTarget != nil
        case .touchRotate(let target):
            return target.elementTarget != nil
        case .touchTwoFingerTap(let target):
            return target.elementTarget != nil
        case .typeText(let target):
            return target.elementTarget != nil
        case .scroll(let target):
            return target.elementTarget != nil || target.containerTarget != nil
        case .scrollToVisible(let target):
            return target.elementTarget != nil
        case .elementSearch(let target):
            return target.elementTarget != nil
        case .scrollToEdge(let target):
            return target.elementTarget != nil || target.containerTarget != nil
        case .performCustomAction(let target):
            return target.elementTarget != nil || target.containerTarget != nil
        case .clientHello,
             .authenticate,
             .requestInterface,
             .ping,
             .status,
             .touchDrawPath,
             .touchDrawBezier,
             .editAction,
             .setPasteboard,
             .getPasteboard,
             .resignFirstResponder,
             .waitForIdle,
             .waitFor,
             .waitForChange,
             .batchExecutionPlan,
             .requestScreen,
             .explore,
             .startRecording,
             .stopRecording:
            return false
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

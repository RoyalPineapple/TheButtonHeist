#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

protocol CustomActionExecutionInput {
    var customActionSelection: CustomActionSelection { get }
}

protocol RotorExecutionInput {
    var rotorElementTarget: SemanticElementTarget { get }
    var selection: RotorSelection { get }
    var direction: RotorDirection { get }
    var continuation: RotorContinuation { get }
}

protocol PointGestureExecutionInput {
    func pointSelection() throws -> GesturePointSelection
}

protocol TapExecutionInput: PointGestureExecutionInput {}

protocol LongPressExecutionInput: PointGestureExecutionInput {
    var duration: Double { get }
}

protocol SwipeExecutionInput {
    var resolvedDuration: Double { get }
    func swipeGestureSelection() throws -> SwipeGestureSelection
}

protocol DragExecutionInput {
    var end: ScreenPoint { get }
    var resolvedDuration: Double { get }
    func dragStartSelection() throws -> GesturePointSelection
}

protocol PinchExecutionInput {
    var scale: Double { get }
    var resolvedSpread: Double { get }
    var resolvedDuration: Double { get }
    func pinchCenterSelection() throws -> GesturePointSelection
}

protocol RotateExecutionInput {
    var angle: Double { get }
    var resolvedRadius: Double { get }
    var resolvedDuration: Double { get }
    func rotateCenterSelection() throws -> GesturePointSelection
}

protocol TwoFingerTapExecutionInput {
    var resolvedSpread: Double { get }
    func twoFingerTapCenterSelection() throws -> GesturePointSelection
}

protocol TypeTextExecutionInput {
    var text: String { get }
    var typeTextElementTarget: SemanticElementTarget? { get }
}

extension CustomActionTarget: CustomActionExecutionInput {
    var customActionSelection: CustomActionSelection { selection }
}

extension RotorTarget: RotorExecutionInput {
    var rotorElementTarget: SemanticElementTarget { .currentCapture(elementTarget) }
}

extension TapTarget: TapExecutionInput {
    func pointSelection() throws -> GesturePointSelection {
        gesturePointSelection()
    }
}

extension LongPressTarget: LongPressExecutionInput {
    func pointSelection() throws -> GesturePointSelection {
        gesturePointSelection()
    }
}

extension SwipeTarget: SwipeExecutionInput {
    func swipeGestureSelection() throws -> SwipeGestureSelection {
        gestureSelection()
    }
}

extension DragTarget: DragExecutionInput {
    func dragStartSelection() throws -> GesturePointSelection {
        startSelection()
    }
}

extension PinchTarget: PinchExecutionInput {
    func pinchCenterSelection() throws -> GesturePointSelection {
        centerSelection()
    }
}

extension RotateTarget: RotateExecutionInput {
    func rotateCenterSelection() throws -> GesturePointSelection {
        centerSelection()
    }
}

extension TwoFingerTapTarget: TwoFingerTapExecutionInput {
    func twoFingerTapCenterSelection() throws -> GesturePointSelection {
        centerSelection()
    }
}

extension TypeTextTarget: TypeTextExecutionInput {
    var typeTextElementTarget: SemanticElementTarget? { elementTarget.map(SemanticElementTarget.currentCapture) }
}
#endif // DEBUG
#endif // canImport(UIKit)

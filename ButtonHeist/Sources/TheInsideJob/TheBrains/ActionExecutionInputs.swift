#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

protocol CustomActionExecutionInput {
    var actionElementTarget: (any SemanticElementTarget)? { get }
    var actionContainerTarget: ContainerMatcher? { get }
    var actionContainerOrdinal: Int? { get }
    var actionName: String { get }
}

protocol RotorExecutionInput {
    var rotorElementTarget: any SemanticElementTarget { get }
    var rotor: String? { get }
    var rotorIndex: Int? { get }
    var direction: RotorDirection? { get }
    var currentHeistId: HeistId? { get }
    var currentTextRange: TextRangeReference? { get }
}

protocol TapExecutionInput {
    var tapElementTarget: (any SemanticElementTarget)? { get }
    var pointX: Double? { get }
    var pointY: Double? { get }
}

protocol LongPressExecutionInput: TapExecutionInput {
    var duration: Double { get }
}

protocol SwipeExecutionInput {
    var swipeElementTarget: (any SemanticElementTarget)? { get }
    var startX: Double? { get }
    var startY: Double? { get }
    var endX: Double? { get }
    var endY: Double? { get }
    var direction: SwipeDirection? { get }
    var duration: Double? { get }
    var start: UnitPoint? { get }
    var end: UnitPoint? { get }
}

protocol DragExecutionInput {
    var dragElementTarget: (any SemanticElementTarget)? { get }
    var startX: Double? { get }
    var startY: Double? { get }
    var endX: Double { get }
    var endY: Double { get }
    var duration: Double? { get }
}

protocol PinchExecutionInput {
    var pinchElementTarget: (any SemanticElementTarget)? { get }
    var centerX: Double? { get }
    var centerY: Double? { get }
    var scale: Double { get }
    var spread: Double? { get }
    var duration: Double? { get }
}

protocol RotateExecutionInput {
    var rotateElementTarget: (any SemanticElementTarget)? { get }
    var centerX: Double? { get }
    var centerY: Double? { get }
    var angle: Double { get }
    var radius: Double? { get }
    var duration: Double? { get }
}

protocol TwoFingerTapExecutionInput {
    var twoFingerTapElementTarget: (any SemanticElementTarget)? { get }
    var centerX: Double? { get }
    var centerY: Double? { get }
    var spread: Double? { get }
}

protocol TypeTextExecutionInput {
    var text: String { get }
    var typeTextElementTarget: (any SemanticElementTarget)? { get }
}

extension CustomActionTarget: CustomActionExecutionInput {
    var actionElementTarget: (any SemanticElementTarget)? { elementTarget }
    var actionContainerTarget: ContainerMatcher? { containerTarget }
    var actionContainerOrdinal: Int? { containerOrdinal }
}

extension BatchCustomActionTarget: CustomActionExecutionInput {
    var actionElementTarget: (any SemanticElementTarget)? { target }
    var actionContainerTarget: ContainerMatcher? { containerTarget }
    var actionContainerOrdinal: Int? { containerOrdinal }
}

extension RotorTarget: RotorExecutionInput {
    var rotorElementTarget: any SemanticElementTarget { elementTarget }
}

extension BatchRotorTarget: RotorExecutionInput {
    var rotorElementTarget: any SemanticElementTarget { target }
    var currentHeistId: HeistId? { currentSourceHeistId }
}

extension TouchTapTarget: TapExecutionInput {
    var tapElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchTouchTapTarget: TapExecutionInput {
    var tapElementTarget: (any SemanticElementTarget)? { target }
}

extension LongPressTarget: LongPressExecutionInput {
    var tapElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchLongPressTarget: LongPressExecutionInput {
    var tapElementTarget: (any SemanticElementTarget)? { target }
}

extension SwipeTarget: SwipeExecutionInput {
    var swipeElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchSwipeTarget: SwipeExecutionInput {
    var swipeElementTarget: (any SemanticElementTarget)? { target }
}

extension DragTarget: DragExecutionInput {
    var dragElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchDragTarget: DragExecutionInput {
    var dragElementTarget: (any SemanticElementTarget)? { target }
}

extension PinchTarget: PinchExecutionInput {
    var pinchElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchPinchTarget: PinchExecutionInput {
    var pinchElementTarget: (any SemanticElementTarget)? { target }
}

extension RotateTarget: RotateExecutionInput {
    var rotateElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchRotateTarget: RotateExecutionInput {
    var rotateElementTarget: (any SemanticElementTarget)? { target }
}

extension TwoFingerTapTarget: TwoFingerTapExecutionInput {
    var twoFingerTapElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchTwoFingerTapTarget: TwoFingerTapExecutionInput {
    var twoFingerTapElementTarget: (any SemanticElementTarget)? { target }
}

extension TypeTextTarget: TypeTextExecutionInput {
    var typeTextElementTarget: (any SemanticElementTarget)? { elementTarget }
}

extension BatchTypeTextTarget: TypeTextExecutionInput {
    var typeTextElementTarget: (any SemanticElementTarget)? { target }
}
#endif // DEBUG
#endif // canImport(UIKit)

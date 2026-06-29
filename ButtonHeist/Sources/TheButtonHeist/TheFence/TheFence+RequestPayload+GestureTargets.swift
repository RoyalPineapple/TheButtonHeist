import Foundation
import ThePlans

extension TheFence {

    func decodeTapTarget(_ request: CommandArgumentEnvelope) throws -> TapTarget {
        let target = try decodeGestureTarget(request, as: TapTarget.self)
        try target.validatePublicGestureUnitPoints()
        return target
    }

    func decodeLongPressTarget(_ request: CommandArgumentEnvelope) throws -> LongPressTarget {
        let target = try decodeGestureTarget(request, as: LongPressTarget.self)
        try target.validatePublicGestureUnitPoints()
        return target
    }

    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        let target = try decodeGestureTarget(request, as: SwipeTarget.self)
        try target.validatePublicGestureUnitPoints()
        return target
    }

    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        let target = try decodeGestureTarget(request, as: DragTarget.self)
        try target.validatePublicGestureUnitPoints()
        return target
    }

    func decodeGestureTarget<T: HeistValuePayloadExpectationProviding>(
        _ request: CommandArgumentEnvelope,
        as type: T.Type
    ) throws -> T {
        try HeistValuePayloadDecoder.decode(
            .object(request.argumentValues),
            field: "gesture",
            as: type,
            includesRootInField: false
        )
    }
}

extension TapTarget: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .gesturePointSelection
    }
}

extension LongPressTarget: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        .gesturePointSelection.adding(paths: ["duration": .number])
    }
}

extension SwipeTarget: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        HeistValuePayloadExpectation(
            root: .object,
            paths: HeistValuePayloadExpectation.merged([
                [
                    "duration": .number,
                    "elementDirection": .object,
                    "elementDirection.element": .object,
                    "elementDirection.direction": .string,
                    "elementUnitPoints": .object,
                    "elementUnitPoints.element": .object,
                    "elementUnitPoints.start": .object,
                    "elementUnitPoints.start.x": .number,
                    "elementUnitPoints.start.y": .number,
                    "elementUnitPoints.end": .object,
                    "elementUnitPoints.end.x": .number,
                    "elementUnitPoints.end.y": .number,
                    "pointToPoint": .object,
                    "pointToPoint.start": .object,
                    "pointToPoint.start.x": .number,
                    "pointToPoint.start.y": .number,
                    "pointToPoint.end": .object,
                    "pointToPoint.end.x": .number,
                    "pointToPoint.end.y": .number,
                    "pointDirection": .object,
                    "pointDirection.start": .object,
                    "pointDirection.start.x": .number,
                    "pointDirection.start.y": .number,
                    "pointDirection.direction": .string,
                ],
                HeistValuePayloadExpectation.prefixed(
                    "elementDirection.element",
                    HeistValuePayloadExpectation.elementTarget.paths
                ),
                HeistValuePayloadExpectation.prefixed(
                    "elementUnitPoints.element",
                    HeistValuePayloadExpectation.elementTarget.paths
                ),
            ]),
            arrayItems: HeistValuePayloadExpectation.merged([
                HeistValuePayloadExpectation.prefixed(
                    "elementDirection.element",
                    HeistValuePayloadExpectation.elementTarget.arrayItems
                ),
                HeistValuePayloadExpectation.prefixed(
                    "elementUnitPoints.element",
                    HeistValuePayloadExpectation.elementTarget.arrayItems
                ),
            ])
        )
    }
}

extension DragTarget: HeistValuePayloadExpectationProviding {
    static var heistValuePayloadExpectation: HeistValuePayloadExpectation {
        HeistValuePayloadExpectation(
            root: .object,
            paths: HeistValuePayloadExpectation.merged([
                [
                    "duration": .number,
                    "elementToPoint": .object,
                    "elementToPoint.element": .object,
                    "elementToPoint.start": .object,
                    "elementToPoint.start.x": .number,
                    "elementToPoint.start.y": .number,
                    "elementToPoint.end": .object,
                    "elementToPoint.end.x": .number,
                    "elementToPoint.end.y": .number,
                    "pointToPoint": .object,
                    "pointToPoint.start": .object,
                    "pointToPoint.start.x": .number,
                    "pointToPoint.start.y": .number,
                    "pointToPoint.end": .object,
                    "pointToPoint.end.x": .number,
                    "pointToPoint.end.y": .number,
                ],
                HeistValuePayloadExpectation.prefixed(
                    "elementToPoint.element",
                    HeistValuePayloadExpectation.elementTarget.paths
                ),
            ]),
            arrayItems: HeistValuePayloadExpectation.prefixed(
                "elementToPoint.element",
                HeistValuePayloadExpectation.elementTarget.arrayItems
            )
        )
    }
}

private extension HeistValuePayloadExpectation {
    static var gesturePointSelection: HeistValuePayloadExpectation {
        HeistValuePayloadExpectation(
            root: .object,
            paths: merged([
                [
                    "element": .object,
                    "unitPoint": .object,
                    "unitPoint.x": .number,
                    "unitPoint.y": .number,
                    "point": .object,
                    "point.x": .number,
                    "point.y": .number,
                ],
                prefixed("element", HeistValuePayloadExpectation.elementTarget.paths),
            ]),
            arrayItems: prefixed("element", HeistValuePayloadExpectation.elementTarget.arrayItems)
        )
    }

    func adding(paths additionalPaths: [String: HeistValueExpectedType]) -> HeistValuePayloadExpectation {
        HeistValuePayloadExpectation(
            root: root,
            rootArrayItem: rootArrayItem,
            paths: Self.merged([paths, additionalPaths]),
            arrayItems: arrayItems
        )
    }
}

private extension TapTarget {
    func validatePublicGestureUnitPoints() throws {
        try selection.validatePublicGestureUnitPoint(field: "unitPoint")
    }
}

private extension LongPressTarget {
    func validatePublicGestureUnitPoints() throws {
        try selection.validatePublicGestureUnitPoint(field: "unitPoint")
    }
}

private extension SwipeTarget {
    func validatePublicGestureUnitPoints() throws {
        guard case .unitElement(_, let start, let end) = selection else { return }
        try start.validatePublicGestureUnitPoint(field: "elementUnitPoints.start")
        try end.validatePublicGestureUnitPoint(field: "elementUnitPoints.end")
    }
}

private extension DragTarget {
    func validatePublicGestureUnitPoints() throws {
        guard case .elementToPoint(_, let start, _) = selection,
              let start else { return }
        try start.validatePublicGestureUnitPoint(field: "elementToPoint.start")
    }
}

private extension GesturePointSelection {
    func validatePublicGestureUnitPoint(field: String) throws {
        guard case .elementUnitPoint(_, let unitPoint) = self else { return }
        try unitPoint.validatePublicGestureUnitPoint(field: field)
    }
}

private extension UnitPoint {
    func validatePublicGestureUnitPoint(field: String) throws {
        guard (0...1).contains(x) else {
            throw SchemaValidationError(field: "\(field).x", observed: x, expected: "number in 0...1")
        }
        guard (0...1).contains(y) else {
            throw SchemaValidationError(field: "\(field).y", observed: y, expected: "number in 0...1")
        }
    }
}

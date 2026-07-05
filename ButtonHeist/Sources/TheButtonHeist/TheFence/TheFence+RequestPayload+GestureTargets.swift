import Foundation
import ThePlans

extension TheFence {

    func decodeTapTarget(_ request: CommandArgumentEnvelope) throws -> TapTarget {
        try decodeGestureTarget(request, as: TapTarget.self, expectation: .gesturePointSelection) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    func decodeLongPressTarget(_ request: CommandArgumentEnvelope) throws -> LongPressTarget {
        try decodeGestureTarget(request, as: LongPressTarget.self, expectation: .longPressGestureTarget) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        try decodeGestureTarget(request, as: SwipeTarget.self, expectation: .swipeGestureTarget) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        try decodeGestureTarget(request, as: DragTarget.self, expectation: .dragGestureTarget) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    private func decodeGestureTarget<T: Decodable>(
        _ request: CommandArgumentEnvelope,
        as type: T.Type,
        expectation: HeistValuePayloadExpectation,
        validate: (T) throws -> Void
    ) throws -> T {
        let target = try HeistValuePayloadDecoder.decode(
            .object(request.argumentValues),
            field: "gesture",
            as: type,
            expectation: expectation,
            includesRootInField: false
        )
        try validate(target)
        return target
    }
}

private extension HeistValuePayloadExpectation {
    static var gesturePointSelection: HeistValuePayloadExpectation {
        gesturePayloadExpectation(paths: gesturePointSelectionPaths)
    }

    static var longPressGestureTarget: HeistValuePayloadExpectation {
        gesturePayloadExpectation(paths: merged([
            gesturePointSelectionPaths,
            ["duration": .number],
        ]))
    }

    static var swipeGestureTarget: HeistValuePayloadExpectation {
        gesturePayloadExpectation(paths: [
            "duration": .number,
            "elementDirection": .object,
            "elementUnitPoints": .object,
            "pointToPoint": .object,
            "pointDirection": .object,
            "element": .object,
            "start": .object,
            "end": .object,
            "x": .number,
            "y": .number,
            "direction": .string,
        ])
    }

    static var dragGestureTarget: HeistValuePayloadExpectation {
        gesturePayloadExpectation(paths: [
            "duration": .number,
            "elementToPoint": .object,
            "pointToPoint": .object,
            "element": .object,
            "start": .object,
            "end": .object,
            "x": .number,
            "y": .number,
        ])
    }

    static func gesturePayloadExpectation(
        paths: [String: HeistValueExpectedType]
    ) -> HeistValuePayloadExpectation {
        HeistValuePayloadExpectation(
            root: .object,
            paths: merged(
                [paths, HeistValuePayloadExpectation.elementTarget.paths]
            ),
            arrayItems: HeistValuePayloadExpectation.elementTarget.arrayItems
        )
    }

    static let gesturePointSelectionPaths: [String: HeistValueExpectedType] = [
        "element": .object,
        "unitPoint": .object,
        "point": .object,
        "x": .number,
        "y": .number,
    ]
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

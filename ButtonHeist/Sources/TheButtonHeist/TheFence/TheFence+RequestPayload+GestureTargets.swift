import Foundation
import ThePlans

extension TheFence {

    func decodeTapTarget(_ request: CommandArgumentEnvelope) throws -> TapTarget {
        try decodeGestureTarget(request, as: TapTarget.self) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    func decodeLongPressTarget(_ request: CommandArgumentEnvelope) throws -> LongPressTarget {
        try decodeGestureTarget(request, as: LongPressTarget.self) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        try decodeGestureTarget(request, as: SwipeTarget.self) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        try decodeGestureTarget(request, as: DragTarget.self) {
            try $0.validatePublicGestureUnitPoints()
        }
    }

    private func decodeGestureTarget<T: Decodable>(
        _ request: CommandArgumentEnvelope,
        as type: T.Type,
        validate: (T) throws -> Void
    ) throws -> T {
        let target = try HeistValuePayloadDecoder.decode(
            request.objectValue,
            field: "gesture",
            as: type,
            includesRootInField: false
        )
        try validate(target)
        return target
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

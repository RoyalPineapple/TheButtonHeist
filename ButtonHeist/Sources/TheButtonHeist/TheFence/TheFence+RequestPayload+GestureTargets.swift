import Foundation
import ThePlans

extension TheFence {

    func decodeTapTarget(_ request: CommandArgumentEnvelope) throws -> TapTarget {
        try decodeGestureTarget(request, as: TapTarget.self) {
            try $0.validatePublicGestureTarget(command: .oneFingerTap)
        }
    }

    func decodeLongPressTarget(_ request: CommandArgumentEnvelope) throws -> LongPressTarget {
        let duration = try request.value(FenceParameters.gestureDuration) ?? .longPressDefault
        let target = try decodeGestureTarget(request.dropping(.duration), as: LongPressTarget.self) {
            try $0.validatePublicGestureTarget(command: .longPress)
        }
        return LongPressTarget(selection: target.selection, duration: duration)
    }

    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        let duration = try request.value(FenceParameters.gestureDuration)
        let target = try decodeGestureTarget(request.dropping(.duration), as: SwipeTarget.self) {
            try $0.validatePublicGestureTarget(command: .swipe)
        }
        return SwipeTarget(selection: target.selection, duration: duration)
    }

    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        let duration = try request.value(FenceParameters.gestureDuration)
        let target = try decodeGestureTarget(request.dropping(.duration), as: DragTarget.self) {
            try $0.validatePublicGestureTarget(command: .drag)
        }
        return DragTarget(selection: target.selection, duration: duration)
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
    func validatePublicGestureTarget(command: TheFence.Command) throws {
        try selection.validateElementTarget(command: command)
        try selection.validatePublicGestureUnitPoint(field: "unitPoint")
    }
}

private extension LongPressTarget {
    func validatePublicGestureTarget(command: TheFence.Command) throws {
        try selection.validateElementTarget(command: command)
        try selection.validatePublicGestureUnitPoint(field: "unitPoint")
    }
}

private extension SwipeTarget {
    func validatePublicGestureTarget(command: TheFence.Command) throws {
        switch selection {
        case .unitElement(let target, let start, let end):
            _ = try target.resolvedElementTarget(command: command)
            try start.validatePublicGestureUnitPoint(field: "elementUnitPoints.start")
            try end.validatePublicGestureUnitPoint(field: "elementUnitPoints.end")
        case .elementDirection(let target, _):
            _ = try target.resolvedElementTarget(command: command)
        case .point:
            break
        }
    }
}

private extension DragTarget {
    func validatePublicGestureTarget(command: TheFence.Command) throws {
        switch selection {
        case .elementToPoint(let target, let start, _):
            _ = try target.resolvedElementTarget(command: command)
            if let start {
                try start.validatePublicGestureUnitPoint(field: "elementToPoint.start")
            }
        case .pointToPoint:
            break
        }
    }
}

private extension GesturePointSelection {
    func validateElementTarget(command: TheFence.Command) throws {
        switch self {
        case .element(let target), .elementUnitPoint(let target, _):
            _ = try target.resolvedElementTarget(command: command)
        case .coordinate:
            break
        }
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
        _ = try FenceParameters.unitPointX.decode(jsonSchemaNumber(x), field: "\(field).x")
        _ = try FenceParameters.unitPointY.decode(jsonSchemaNumber(y), field: "\(field).y")
    }
}

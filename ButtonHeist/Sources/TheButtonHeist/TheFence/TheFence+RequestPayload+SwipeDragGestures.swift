import Foundation
import ThePlans

import TheScore

extension TheFence {

    @ButtonHeistActor
    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        let (intent, payload) = try request.singleGestureIntent(
            keys: FenceParameterBlocks.swipeIntentKeys,
            field: "swipe",
            expected: "exactly one swipe intent"
        )

        let selection: SwipeGestureSelection
        switch intent {
        case FenceParameterKey.elementDirection.rawValue:
            try payload.rejectUnknownGestureIntentKeys(spec: FenceParameterBlocks.swipeIntentSpec(intent))
            guard let element = try payload.schemaGestureElementTarget("element") else {
                throw SchemaValidationError(field: payload.field("element"), observed: "missing", expected: "object")
            }
            selection = .elementDirection(
                element,
                try payload.requiredSchemaEnum("direction", as: SwipeDirection.self)
            )
        case FenceParameterKey.elementUnitPoints.rawValue:
            try payload.rejectUnknownGestureIntentKeys(spec: FenceParameterBlocks.swipeIntentSpec(intent))
            guard let element = try payload.schemaGestureElementTarget("element") else {
                throw SchemaValidationError(field: payload.field("element"), observed: "missing", expected: "object")
            }
            guard let start = try payload.schemaUnitPoint("start") else {
                throw SchemaValidationError(field: payload.field("start"), observed: "missing", expected: "object")
            }
            guard let end = try payload.schemaUnitPoint("end") else {
                throw SchemaValidationError(field: payload.field("end"), observed: "missing", expected: "object")
            }
            selection = .unitElement(element, start: start, end: end)
        case FenceParameterKey.pointToPoint.rawValue:
            try payload.rejectUnknownGestureIntentKeys(spec: FenceParameterBlocks.swipeIntentSpec(intent))
            selection = .point(
                start: .coordinate(try payload.requiredScreenPoint("start")),
                destination: .coordinate(try payload.requiredScreenPoint("end"))
            )
        case FenceParameterKey.pointDirection.rawValue:
            try payload.rejectUnknownGestureIntentKeys(spec: FenceParameterBlocks.swipeIntentSpec(intent))
            selection = .point(
                start: .coordinate(try payload.requiredScreenPoint("start")),
                destination: .direction(try payload.requiredSchemaEnum("direction", as: SwipeDirection.self))
            )
        default:
            preconditionFailure("Unhandled swipe intent \(intent)")
        }

        return SwipeTarget(selection: selection, duration: try request.gestureDuration())
    }

    @ButtonHeistActor
    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        let (intent, payload) = try request.singleGestureIntent(
            keys: FenceParameterBlocks.dragIntentKeys,
            field: "drag",
            expected: "exactly one drag intent"
        )

        let selection: DragGestureSelection
        switch intent {
        case FenceParameterKey.elementToPoint.rawValue:
            try payload.rejectUnknownGestureIntentKeys(spec: FenceParameterBlocks.dragIntentSpec(intent))
            guard let element = try payload.schemaGestureElementTarget("element") else {
                throw SchemaValidationError(field: payload.field("element"), observed: "missing", expected: "object")
            }
            selection = .elementToPoint(element, end: try payload.requiredScreenPoint("end"))
        case FenceParameterKey.pointToPoint.rawValue:
            try payload.rejectUnknownGestureIntentKeys(spec: FenceParameterBlocks.dragIntentSpec(intent))
            selection = .pointToPoint(
                start: try payload.requiredScreenPoint("start"),
                end: try payload.requiredScreenPoint("end")
            )
        default:
            preconditionFailure("Unhandled drag intent \(intent)")
        }

        return DragTarget(selection: selection, duration: try request.gestureDuration())
    }
}

private extension TheFence.CommandArgumentEnvelope {
    func singleGestureIntent(
        keys: [String],
        field: String,
        expected: String
    ) throws -> (key: String, payload: TheFence.CommandArgumentEnvelope) {
        let present = try keys.compactMap { key -> (String, TheFence.CommandArgumentEnvelope)? in
            guard let payload = try schemaDictionary(key) else { return nil }
            return (key, payload)
        }
        guard present.count == 1, let selected = present.first else {
            throw SchemaValidationError(
                field: field,
                observed: "mixed or missing gesture intent",
                expected: expected
            )
        }
        return selected
    }

    func rejectUnknownGestureIntentKeys(spec: FenceParameterSpec) throws {
        try rejectUnknownKeys(
            allowed: spec.objectPropertyKeys,
            expected: "valid \(spec.key) field"
        )
    }
}

import Foundation
import ThePlans

import TheScore

extension TheFence {

    @ButtonHeistActor
    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        let input = try SwipeInput(request)
        return SwipeTarget(selection: input.selection, duration: try request.gestureDuration())
    }

    @ButtonHeistActor
    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        let input = try DragInput(request)
        return DragTarget(selection: input.selection, duration: try request.gestureDuration())
    }
}

private enum SwipeIntent: String, CaseIterable {
    case elementDirection
    case elementUnitPoints
    case pointToPoint
    case pointDirection
}

private enum DragIntent: String, CaseIterable {
    case elementToPoint
    case pointToPoint
}

private enum SwipeInput {
    case elementDirection(SwipeElementDirectionInput)
    case elementUnitPoints(SwipeElementUnitPointsInput)
    case pointToPoint(SwipePointToPointInput)
    case pointDirection(SwipePointDirectionInput)

    @ButtonHeistActor
    init(_ request: TheFence.CommandArgumentEnvelope) throws {
        let intent = try request.singleObjectPayloadIntent(
            SwipeIntent.self,
            field: "swipe",
            expected: "exactly one swipe intent"
        )

        switch intent.key {
        case .elementDirection:
            self = .elementDirection(try intent.payload.decodeGesturePayload(
                SwipeElementDirectionInput.self,
                intentKey: intent.key.rawValue
            ))
        case .elementUnitPoints:
            self = .elementUnitPoints(try intent.payload.decodeGesturePayload(
                SwipeElementUnitPointsInput.self,
                intentKey: intent.key.rawValue
            ))
        case .pointToPoint:
            self = .pointToPoint(try intent.payload.decodeGesturePayload(
                SwipePointToPointInput.self,
                intentKey: intent.key.rawValue
            ))
        case .pointDirection:
            self = .pointDirection(try intent.payload.decodeGesturePayload(
                SwipePointDirectionInput.self,
                intentKey: intent.key.rawValue
            ))
        }
    }

    var selection: SwipeGestureSelection {
        switch self {
        case .elementDirection(let input):
            return .elementDirection(input.element, input.direction)
        case .elementUnitPoints(let input):
            return .unitElement(input.element, start: input.start, end: input.end)
        case .pointToPoint(let input):
            return .point(
                start: .coordinate(input.start),
                destination: .coordinate(input.end)
            )
        case .pointDirection(let input):
            return .point(
                start: .coordinate(input.start),
                destination: .direction(input.direction)
            )
        }
    }
}

private enum DragInput {
    case elementToPoint(DragElementToPointInput)
    case pointToPoint(DragPointToPointInput)

    @ButtonHeistActor
    init(_ request: TheFence.CommandArgumentEnvelope) throws {
        let intent = try request.singleObjectPayloadIntent(
            DragIntent.self,
            field: "drag",
            expected: "exactly one drag intent"
        )

        switch intent.key {
        case .elementToPoint:
            self = .elementToPoint(try intent.payload.decodeGesturePayload(
                DragElementToPointInput.self,
                intentKey: intent.key.rawValue
            ))
        case .pointToPoint:
            self = .pointToPoint(try intent.payload.decodeGesturePayload(
                DragPointToPointInput.self,
                intentKey: intent.key.rawValue
            ))
        }
    }

    var selection: DragGestureSelection {
        switch self {
        case .elementToPoint(let input):
            return .elementToPoint(input.element, start: input.start, end: input.end)
        case .pointToPoint(let input):
            return .pointToPoint(start: input.start, end: input.end)
        }
    }
}

private struct SwipeElementDirectionInput: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case direction
    }

    let element: ElementTarget
    let direction: SwipeDirection

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element direction swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        element = try container.decodeRequiredElementTarget(forKey: .element)
        direction = try container.decode(SwipeDirection.self, forKey: .direction)
    }
}

private struct SwipeElementUnitPointsInput: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case start
        case end
    }

    let element: ElementTarget
    let start: UnitPoint
    let end: UnitPoint

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element unit-points swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        element = try container.decodeRequiredElementTarget(forKey: .element)
        start = try container.decode(BoundedUnitPoint.self, forKey: .start).unitPoint
        end = try container.decode(BoundedUnitPoint.self, forKey: .end).unitPoint
    }
}

private struct SwipePointToPointInput: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case start
        case end
    }

    let start: ScreenPoint
    let end: ScreenPoint

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "point-to-point swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(ScreenPoint.self, forKey: .start)
        end = try container.decode(ScreenPoint.self, forKey: .end)
    }
}

private struct SwipePointDirectionInput: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case start
        case direction
    }

    let start: ScreenPoint
    let direction: SwipeDirection

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "point direction swipe")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(ScreenPoint.self, forKey: .start)
        direction = try container.decode(SwipeDirection.self, forKey: .direction)
    }
}

private struct DragElementToPointInput: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case element
        case start
        case end
    }

    let element: ElementTarget
    let start: UnitPoint?
    let end: ScreenPoint

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "element-to-point drag")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        element = try container.decodeRequiredElementTarget(forKey: .element)
        start = try container.decodeIfPresent(BoundedUnitPoint.self, forKey: .start)?.unitPoint
        end = try container.decode(ScreenPoint.self, forKey: .end)
    }
}

private struct DragPointToPointInput: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case start
        case end
    }

    let start: ScreenPoint
    let end: ScreenPoint

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "point-to-point drag")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decode(ScreenPoint.self, forKey: .start)
        end = try container.decode(ScreenPoint.self, forKey: .end)
    }
}

private struct BoundedUnitPoint: Decodable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case x
        case y
    }

    let unitPoint: UnitPoint

    init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "unit point")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        guard (0...1).contains(x) else {
            throw DecodingError.dataCorruptedError(
                forKey: .x,
                in: container,
                debugDescription: "number in 0...1"
            )
        }
        guard (0...1).contains(y) else {
            throw DecodingError.dataCorruptedError(
                forKey: .y,
                in: container,
                debugDescription: "number in 0...1"
            )
        }
        unitPoint = UnitPoint(x: x, y: y)
    }
}

private extension TheFence.CommandArgumentEnvelope {
    func singleObjectPayloadIntent<Intent>(
        _: Intent.Type,
        field: String,
        expected: String
    ) throws -> (key: Intent, payload: TheFence.CommandArgumentEnvelope)
    where Intent: CaseIterable & RawRepresentable, Intent.RawValue == String {
        var present: [(key: Intent, payload: TheFence.CommandArgumentEnvelope)] = []
        for intent in Intent.allCases {
            guard let payload = try schemaDictionary(intent.rawValue) else { continue }
            present.append((intent, payload))
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

    func decodeGesturePayload<T: Decodable>(
        _ type: T.Type,
        intentKey: String
    ) throws -> T {
        try TheFence.HeistValuePayloadDecoder.decode(
            .object(argumentValues),
            field: argumentFieldPrefix ?? intentKey,
            as: type
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeRequiredElementTarget(forKey key: Key) throws -> ElementTarget {
        guard contains(key) else {
            throw DecodingError.valueNotFound(
                ElementTarget.self,
                DecodingError.Context(
                    codingPath: codingPath + [key],
                    debugDescription: "missing"
                )
            )
        }
        return try decode(ElementTarget.self, forKey: key)
    }
}

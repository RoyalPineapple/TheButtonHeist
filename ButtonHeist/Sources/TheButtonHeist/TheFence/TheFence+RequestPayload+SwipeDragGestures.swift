import Foundation

import TheScore

extension TheFence {

    func decodeSwipeTarget(_ request: CommandArgumentEnvelope) throws -> SwipeTarget {
        let start = try request.schemaUnitPoint("start")
        let end = try request.schemaUnitPoint("end")
        if (start != nil) != (end != nil) {
            throw FenceError.invalidRequest("Unit-point swipe requires both start and end")
        }
        let elementTarget = try request.decodedElementTarget()
        let direction = try request.schemaEnum("direction", as: SwipeDirection.self)
        let startPoint = try decodeCoordinatePair(request: request, xKey: "startX", yKey: "startY", field: "startX/startY")
        let endPoint = try decodeCoordinatePair(request: request, xKey: "endX", yKey: "endY", field: "endX/endY")
        if start != nil || end != nil, request.hasAny("startX", "startY", "endX", "endY") {
            throw mixedGestureShape(field: "start/end", expected: "unit points or absolute coordinates")
        }
        if start != nil || end != nil, direction != nil {
            throw mixedGestureShape(field: "start/end", expected: "unit points or direction defaults")
        }
        if let start, let end {
            guard let elementTarget else {
                throw FenceError.invalidRequest("Unit-point swipe requires target object")
            }
            return SwipeTarget(
                selection: .unitElement(elementTarget, start: start, end: end, direction: direction),
                duration: try request.gestureDuration()
            )
        }
        if elementTarget != nil, startPoint != nil {
            throw mixedGestureShape(field: "startX/startY", expected: "target object or absolute start coordinates")
        }
        if endPoint != nil, direction != nil {
            throw mixedGestureShape(field: "endX/endY", expected: "end coordinates or direction")
        }
        let startSelection: GesturePointSelection
        if let elementTarget {
            startSelection = .element(elementTarget)
        } else if let startPoint {
            startSelection = .coordinate(ScreenPoint(x: startPoint.x, y: startPoint.y))
        } else {
            throw FenceError.invalidRequest(
                "Swipe requires target object or start coordinates (startX, startY)"
            )
        }
        let endSelection: SwipeDestinationSelection
        if let direction {
            endSelection = .direction(direction)
        } else if let endPoint {
            endSelection = .coordinate(ScreenPoint(x: endPoint.x, y: endPoint.y))
        } else {
            throw FenceError.invalidRequest("Swipe requires end coordinates (endX, endY) or direction")
        }
        let selection = SwipeGestureSelection.point(
            start: startSelection,
            destination: endSelection
        )
        return SwipeTarget(selection: selection, duration: try request.gestureDuration())
    }

    func decodeDragTarget(_ request: CommandArgumentEnvelope) throws -> DragTarget {
        let start = try decodeRequiredPointIntent(
            request: request,
            elementTarget: try request.decodedElementTarget(),
            xKey: "startX",
            yKey: "startY",
            field: "startX/startY",
            missingMessage: "Drag requires target object or start coordinates (startX, startY)"
        )
        return DragTarget(
            start: start,
            end: ScreenPoint(
                x: try request.requiredSchemaNumber("endX"),
                y: try request.requiredSchemaNumber("endY")
            ),
            duration: try request.gestureDuration()
        )
    }
}

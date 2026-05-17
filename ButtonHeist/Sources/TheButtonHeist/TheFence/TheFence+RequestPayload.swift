import Foundation

import TheScore

extension TheFence {

    struct MissingElementTarget: Error {
        let command: String
    }

    enum RequestPayload {
        case none
        case getInterface(GetInterfaceRequest)
        case artifact(ArtifactRequest)
        case gesture(GesturePayload)
        case scroll(ScrollPayload)
        case accessibility(AccessibilityPayload)
        case rotor(RotorTarget)
        case typeText(TypeTextTarget)
        case editAction(EditActionTarget)
        case setPasteboard(SetPasteboardTarget)
        case waitFor(WaitForTarget)
        case waitForChange(ExpectationPayload)
        case startRecording(RecordingConfig)
        case connect(ConnectRequest)
        case runBatch(RunBatchRequest)
        case archiveSession(ArchiveSessionRequest)
        case startHeist(StartHeistRequest)
        case stopHeist(StopHeistRequest)
        case playHeist(PlayHeistRequest)
    }

    struct GetInterfaceRequest {
        let scope: GetInterfaceScope
        let detail: InterfaceDetail
        let matcher: ElementMatcher
        let elementIds: [String]?
    }

    struct ArtifactRequest {
        let outputPath: String?
        let requestId: String
    }

    enum GesturePayload {
        case oneFingerTap(TouchTapTarget)
        case longPress(LongPressTarget)
        case swipe(SwipeTarget)
        case drag(DragTarget)
        case pinch(PinchTarget)
        case rotate(RotateTarget)
        case twoFingerTap(TwoFingerTapTarget)
        case drawPath(DrawPathTarget)
        case drawBezier(DrawBezierTarget)
    }

    enum ScrollPayload {
        case scroll(ScrollTarget)
        case scrollToVisible(ScrollToVisibleTarget)
        case elementSearch(ElementSearchTarget)
        case scrollToEdge(ScrollToEdgeTarget)
    }

    enum AccessibilityPayload {
        case activate(ElementTarget, actionName: String?, count: CountArgument)
        case increment(ElementTarget, count: CountArgument)
        case decrement(ElementTarget, count: CountArgument)
        case performCustomAction(ElementTarget, actionName: String, count: CountArgument)
    }

    struct CountArgument {
        let value: Int?
        let observed: Any?
    }

    struct ConnectRequest {
        let targetName: String?
        let device: String?
        let token: String?
    }

    struct RunBatchRequest {
        let steps: [[String: Any]]
        let policy: BatchPolicy
    }

    struct ArchiveSessionRequest {
        let deleteSource: Bool
    }

    struct StartHeistRequest {
        let app: String
        let identifier: String
    }

    struct StopHeistRequest {
        let outputPath: String
    }

    struct PlayHeistRequest {
        let inputPath: String
    }

    func decodeRequestPayload(
        command: Command,
        request: [String: Any],
        requestId: String
    ) throws -> RequestPayload {
        switch command {
        case .help, .status, .quit, .exit, .listDevices, .getPasteboard,
             .dismissKeyboard, .getSessionState, .listTargets, .getSessionLog:
            return .none
        case .getInterface:
            return .getInterface(try decodeGetInterfaceRequest(request))
        case .getScreen, .stopRecording:
            return .artifact(try decodeArtifactRequest(request, requestId: requestId))
        case .waitForChange:
            return .waitForChange(try parseExpectationPayload(request))
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate,
             .twoFingerTap, .drawPath, .drawBezier:
            return .gesture(try decodeGesturePayload(command: command, request: request))
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge:
            return .scroll(try decodeScrollPayload(command: command, request: request))
        case .activate, .increment, .decrement, .performCustomAction:
            return .accessibility(try decodeAccessibilityPayload(command: command, request: request))
        case .rotor:
            return .rotor(try decodeRotorTarget(request))
        case .typeText:
            return .typeText(try decodeTypeTextTarget(request))
        case .editAction:
            return .editAction(EditActionTarget(
                action: try request.requiredSchemaEnum("action", as: EditAction.self)
            ))
        case .setPasteboard:
            return .setPasteboard(SetPasteboardTarget(
                text: try request.requiredSchemaString("text")
            ))
        case .waitFor:
            return .waitFor(try decodeWaitForTarget(request))
        case .startRecording:
            return .startRecording(try decodeRecordingConfig(request))
        case .runBatch:
            return .runBatch(try decodeRunBatchRequest(request))
        case .connect:
            return .connect(try decodeConnectRequest(request))
        case .archiveSession:
            return .archiveSession(ArchiveSessionRequest(
                deleteSource: try request.schemaBoolean("delete_source") ?? false
            ))
        case .startHeist:
            return .startHeist(StartHeistRequest(
                app: try request.schemaString("app") ?? "com.buttonheist.testapp",
                identifier: try request.schemaString("identifier") ?? "heist"
            ))
        case .stopHeist:
            return .stopHeist(StopHeistRequest(
                outputPath: try request.requiredSchemaString("output")
            ))
        case .playHeist:
            return .playHeist(PlayHeistRequest(
                inputPath: try request.requiredSchemaString("input")
            ))
        }
    }

    private func decodeGetInterfaceRequest(_ request: [String: Any]) throws -> GetInterfaceRequest {
        GetInterfaceRequest(
            scope: try decodeGetInterfaceScope(request),
            detail: try request.schemaEnum("detail", as: InterfaceDetail.self) ?? .summary,
            matcher: try elementMatcher(request),
            elementIds: try request.schemaStringArray("elements")
        )
    }

    private func decodeGetInterfaceScope(_ request: [String: Any]) throws -> GetInterfaceScope {
        if let legacyFull = request["full"] {
            throw SchemaValidationError(
                field: "full",
                observed: legacyFull,
                expected: "removed; omit scope for the full hierarchy or use scope=visible"
            )
        }
        if let rawScope = try request.schemaString("scope") {
            switch rawScope {
            case GetInterfaceScope.visible.rawValue:
                return .visible
            default:
                throw SchemaValidationError(
                    field: "scope",
                    observed: rawScope as Any,
                    expected: "omitted or visible"
                )
            }
        }
        return .full
    }

    private func decodeArtifactRequest(
        _ request: [String: Any],
        requestId: String
    ) throws -> ArtifactRequest {
        ArtifactRequest(
            outputPath: try request.schemaString("output"),
            requestId: requestId
        )
    }

    private func decodeGesturePayload(
        command: Command,
        request: [String: Any]
    ) throws -> GesturePayload {
        switch command {
        case .oneFingerTap:
            return .oneFingerTap(try decodeTouchTapTarget(request))
        case .longPress:
            return .longPress(try decodeLongPressTarget(request))
        case .swipe:
            return .swipe(try decodeSwipeTarget(request))
        case .drag:
            return .drag(try decodeDragTarget(request))
        case .pinch:
            return .pinch(try decodePinchTarget(request))
        case .rotate:
            return .rotate(try decodeRotateTarget(request))
        case .twoFingerTap:
            return .twoFingerTap(try decodeTwoFingerTapTarget(request))
        case .drawPath:
            return .drawPath(try decodeDrawPathTarget(request))
        case .drawBezier:
            return .drawBezier(try decodeDrawBezierTarget(request))
        default:
            throw FenceError.invalidRequest("Unexpected gesture command: \(command.rawValue)")
        }
    }

    private func decodeTouchTapTarget(_ request: [String: Any]) throws -> TouchTapTarget {
        TouchTapTarget(
            elementTarget: try elementTarget(request),
            pointX: try request.schemaNumber("x"),
            pointY: try request.schemaNumber("y")
        )
    }

    private func decodeLongPressTarget(_ request: [String: Any]) throws -> LongPressTarget {
        LongPressTarget(
            elementTarget: try elementTarget(request),
            pointX: try request.schemaNumber("x"),
            pointY: try request.schemaNumber("y"),
            duration: try request.schemaNumber("duration") ?? 0.5
        )
    }

    private func decodeSwipeTarget(_ request: [String: Any]) throws -> SwipeTarget {
        let start = try request.schemaUnitPoint("start")
        let end = try request.schemaUnitPoint("end")
        return SwipeTarget(
            elementTarget: try elementTarget(request),
            startX: try request.schemaNumber("startX"),
            startY: try request.schemaNumber("startY"),
            endX: try request.schemaNumber("endX"),
            endY: try request.schemaNumber("endY"),
            direction: try request.schemaEnum("direction", as: SwipeDirection.self) { $0.lowercased() },
            duration: try request.schemaNumber("duration"),
            start: start,
            end: end
        )
    }

    private func decodeDragTarget(_ request: [String: Any]) throws -> DragTarget {
        DragTarget(
            elementTarget: try elementTarget(request),
            startX: try request.schemaNumber("startX") ?? request.schemaNumber("x"),
            startY: try request.schemaNumber("startY") ?? request.schemaNumber("y"),
            endX: try request.requiredSchemaNumber("endX"),
            endY: try request.requiredSchemaNumber("endY"),
            duration: try request.schemaNumber("duration")
        )
    }

    private func decodePinchTarget(_ request: [String: Any]) throws -> PinchTarget {
        PinchTarget(
            elementTarget: try elementTarget(request),
            centerX: try request.schemaNumber("centerX") ?? request.schemaNumber("x"),
            centerY: try request.schemaNumber("centerY") ?? request.schemaNumber("y"),
            scale: try request.requiredSchemaNumber("scale"),
            spread: try request.schemaNumber("spread"),
            duration: try request.schemaNumber("duration")
        )
    }

    private func decodeRotateTarget(_ request: [String: Any]) throws -> RotateTarget {
        RotateTarget(
            elementTarget: try elementTarget(request),
            centerX: try request.schemaNumber("centerX") ?? request.schemaNumber("x"),
            centerY: try request.schemaNumber("centerY") ?? request.schemaNumber("y"),
            angle: try request.requiredSchemaNumber("angle"),
            radius: try request.schemaNumber("radius"),
            duration: try request.schemaNumber("duration")
        )
    }

    private func decodeTwoFingerTapTarget(_ request: [String: Any]) throws -> TwoFingerTapTarget {
        TwoFingerTapTarget(
            elementTarget: try elementTarget(request),
            centerX: try request.schemaNumber("centerX") ?? request.schemaNumber("x"),
            centerY: try request.schemaNumber("centerY") ?? request.schemaNumber("y"),
            spread: try request.schemaNumber("spread")
        )
    }

    private func decodeDrawPathTarget(_ request: [String: Any]) throws -> DrawPathTarget {
        let pointsArray = try request.requiredSchemaDictionaryArray("points")
        let points = try pointsArray.enumerated().map { index, point -> PathPoint in
            PathPoint(
                x: try schemaNumber(in: point, key: "x", field: "points[\(index)].x"),
                y: try schemaNumber(in: point, key: "y", field: "points[\(index)].y")
            )
        }
        return DrawPathTarget(
            points: points,
            duration: try request.schemaNumber("duration"),
            velocity: try request.schemaNumber("velocity")
        )
    }

    private func decodeDrawBezierTarget(_ request: [String: Any]) throws -> DrawBezierTarget {
        let startX = try request.requiredSchemaNumber("startX")
        let startY = try request.requiredSchemaNumber("startY")
        let segmentsArray = try request.requiredSchemaDictionaryArray("segments")
        let segments = try segmentsArray.enumerated().map { index, segment -> BezierSegment in
            BezierSegment(
                cp1X: try schemaNumber(in: segment, key: "cp1X", field: "segments[\(index)].cp1X"),
                cp1Y: try schemaNumber(in: segment, key: "cp1Y", field: "segments[\(index)].cp1Y"),
                cp2X: try schemaNumber(in: segment, key: "cp2X", field: "segments[\(index)].cp2X"),
                cp2Y: try schemaNumber(in: segment, key: "cp2Y", field: "segments[\(index)].cp2Y"),
                endX: try schemaNumber(in: segment, key: "endX", field: "segments[\(index)].endX"),
                endY: try schemaNumber(in: segment, key: "endY", field: "segments[\(index)].endY")
            )
        }
        return DrawBezierTarget(
            startX: startX,
            startY: startY,
            segments: segments,
            samplesPerSegment: try request.schemaInteger("samplesPerSegment"),
            duration: try request.schemaNumber("duration"),
            velocity: try request.schemaNumber("velocity")
        )
    }

    private func schemaNumber(
        in dictionary: [String: Any],
        key: String,
        field: String
    ) throws -> Double {
        do {
            guard let value = try dictionary.schemaNumber(key) else {
                throw SchemaValidationError(field: field, observed: nil, expected: "number")
            }
            return value
        } catch let error as SchemaValidationError {
            throw SchemaValidationError(field: field, observed: error.observed, expected: error.expected)
        }
    }

    private func decodeScrollPayload(
        command: Command,
        request: [String: Any]
    ) throws -> ScrollPayload {
        switch command {
        case .scroll:
            return .scroll(ScrollTarget(
                elementTarget: try elementTarget(request),
                direction: try request.requiredSchemaEnum("direction", as: ScrollDirection.self) { $0.lowercased() }
            ))
        case .scrollToVisible:
            return .scrollToVisible(ScrollToVisibleTarget(
                elementTarget: try elementTarget(request)
            ))
        case .elementSearch:
            return .elementSearch(ElementSearchTarget(
                elementTarget: try elementTarget(request),
                direction: try request.schemaEnum("direction", as: ScrollSearchDirection.self) { $0.lowercased() }
            ))
        case .scrollToEdge:
            return .scrollToEdge(ScrollToEdgeTarget(
                elementTarget: try elementTarget(request),
                edge: try request.requiredSchemaEnum("edge", as: ScrollEdge.self) { $0.lowercased() }
            ))
        default:
            throw FenceError.invalidRequest("Unexpected scroll command: \(command.rawValue)")
        }
    }

    private func decodeAccessibilityPayload(
        command: Command,
        request: [String: Any]
    ) throws -> AccessibilityPayload {
        guard let target = try elementTarget(request) else {
            throw MissingElementTarget(command: command.rawValue)
        }
        let count = CountArgument(
            value: try request.schemaInteger("count"),
            observed: request["count"]
        )
        switch command {
        case .activate:
            return .activate(
                target,
                actionName: try request.schemaString("action"),
                count: count
            )
        case .increment:
            return .increment(target, count: count)
        case .decrement:
            return .decrement(target, count: count)
        case .performCustomAction:
            return .performCustomAction(
                target,
                actionName: try request.requiredSchemaString("action"),
                count: count
            )
        default:
            throw FenceError.invalidRequest("Unexpected accessibility command: \(command.rawValue)")
        }
    }

    private func decodeRotorTarget(_ request: [String: Any]) throws -> RotorTarget {
        guard let target = try elementTarget(request) else {
            throw MissingElementTarget(command: Command.rotor.rawValue)
        }
        if let rotorIndex = try request.schemaInteger("rotorIndex"), rotorIndex < 0 {
            throw SchemaValidationError(field: "rotorIndex", observed: rotorIndex, expected: "integer >= 0")
        }
        let currentTextStartOffset = try request.schemaInteger("currentTextStartOffset")
        let currentTextEndOffset = try request.schemaInteger("currentTextEndOffset")
        if (currentTextStartOffset == nil) != (currentTextEndOffset == nil) {
            throw FenceError.invalidRequest("currentTextStartOffset and currentTextEndOffset must be provided together")
        }
        let currentTextRange: TextRangeReference?
        if let startOffset = currentTextStartOffset, let endOffset = currentTextEndOffset {
            guard try request.schemaString("currentHeistId") != nil else {
                throw SchemaValidationError(field: "currentHeistId", observed: nil, expected: "string")
            }
            guard startOffset >= 0, endOffset >= startOffset else {
                throw SchemaValidationError(
                    field: "currentTextStartOffset/currentTextEndOffset",
                    observed: "\(startOffset)..<\(endOffset)",
                    expected: "integer range with start >= 0 and end >= start"
                )
            }
            currentTextRange = TextRangeReference(startOffset: startOffset, endOffset: endOffset)
        } else {
            currentTextRange = nil
        }

        return RotorTarget(
            elementTarget: target,
            rotor: try request.schemaString("rotor"),
            rotorIndex: try request.schemaInteger("rotorIndex"),
            direction: try request.schemaEnum("direction", as: RotorDirection.self) { $0.lowercased() } ?? .next,
            currentHeistId: try request.schemaString("currentHeistId"),
            currentTextRange: currentTextRange
        )
    }

    private func decodeTypeTextTarget(_ request: [String: Any]) throws -> TypeTextTarget {
        if let deleteCount = request["deleteCount"] {
            throw SchemaValidationError(
                field: "deleteCount",
                observed: deleteCount,
                expected: "unsupported by type_text; use edit_action delete for destructive edits"
            )
        }
        if let clearFirst = request["clearFirst"] {
            throw SchemaValidationError(
                field: "clearFirst",
                observed: clearFirst,
                expected: "unsupported by type_text; use edit_action selectAll then edit_action delete"
            )
        }
        return TypeTextTarget(
            text: try request.requiredSchemaString("text"),
            elementTarget: try elementTarget(request)
        )
    }

    private func decodeWaitForTarget(_ request: [String: Any]) throws -> WaitForTarget {
        guard let target = try elementTarget(request) else {
            throw MissingElementTarget(command: Command.waitFor.rawValue)
        }
        return WaitForTarget(
            elementTarget: target,
            absent: try request.schemaBoolean("absent"),
            timeout: try request.schemaNumber("timeout")
        )
    }

    private func decodeRecordingConfig(_ request: [String: Any]) throws -> RecordingConfig {
        RecordingConfig(
            fps: try request.schemaInteger("fps"),
            scale: try request.schemaNumber("scale"),
            inactivityTimeout: try request.schemaNumber("inactivity_timeout"),
            maxDuration: try request.schemaNumber("max_duration")
        )
    }

    private func decodeRunBatchRequest(_ request: [String: Any]) throws -> RunBatchRequest {
        let steps = try request.requiredSchemaDictionaryArray("steps")
        guard !steps.isEmpty else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count 0",
                expected: "array count >= 1"
            )
        }
        return RunBatchRequest(
            steps: steps,
            policy: try request.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError
        )
    }

    private func decodeConnectRequest(_ request: [String: Any]) throws -> ConnectRequest {
        ConnectRequest(
            targetName: try request.schemaString("target"),
            device: try request.schemaString("device"),
            token: try request.schemaString("token")
        )
    }
}

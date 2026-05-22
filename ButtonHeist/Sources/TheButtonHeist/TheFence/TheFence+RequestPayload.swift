import Foundation

import TheScore

extension TheFence {

    struct MissingElementTarget: Error {
        let command: String
    }

    enum RequestPayload {
        case none
        case getInterface(GetInterfaceRequest)
        case screen(ScreenRequest)
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
        let detail: InterfaceDetail
        let query: InterfaceQuery
    }

    struct ScreenRequest {
        let outputPath: String?
        let requestId: String
        let inlineData: Bool
        let includeInterface: Bool
    }

    struct ArtifactRequest {
        let outputPath: String?
        let requestId: String
        let inlineData: Bool
        let includeInteractionLog: Bool
    }

    enum GesturePayload {
        case oneFingerTap(TouchTapGesturePayload)
        case longPress(LongPressGesturePayload)
        case swipe(SwipeGesturePayload)
        case drag(DragGesturePayload)
        case pinch(PinchGesturePayload)
        case rotate(RotateGesturePayload)
        case twoFingerTap(TwoFingerTapGesturePayload)
        case drawPath(DrawPathGesturePayload)
        case drawBezier(DrawBezierGesturePayload)
    }

    struct TouchTapGesturePayload {
        let elementTarget: ElementTarget?
        let pointX: Double?
        let pointY: Double?

        var target: TouchTapTarget {
            TouchTapTarget(elementTarget: elementTarget, pointX: pointX, pointY: pointY)
        }
    }

    struct LongPressGesturePayload {
        let elementTarget: ElementTarget?
        let pointX: Double?
        let pointY: Double?
        let duration: Double

        var target: LongPressTarget {
            LongPressTarget(
                elementTarget: elementTarget,
                pointX: pointX,
                pointY: pointY,
                duration: duration
            )
        }
    }

    struct SwipeGesturePayload {
        let elementTarget: ElementTarget?
        let startX: Double?
        let startY: Double?
        let endX: Double?
        let endY: Double?
        let direction: SwipeDirection?
        let duration: Double?
        let start: UnitPoint?
        let end: UnitPoint?

        var target: SwipeTarget {
            SwipeTarget(
                elementTarget: elementTarget,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                direction: direction,
                duration: duration,
                start: start,
                end: end
            )
        }
    }

    struct DragGesturePayload {
        let elementTarget: ElementTarget?
        let startX: Double?
        let startY: Double?
        let endX: Double
        let endY: Double
        let duration: Double?

        var target: DragTarget {
            DragTarget(
                elementTarget: elementTarget,
                startX: startX,
                startY: startY,
                endX: endX,
                endY: endY,
                duration: duration
            )
        }
    }

    struct PinchGesturePayload {
        let elementTarget: ElementTarget?
        let centerX: Double?
        let centerY: Double?
        let scale: Double
        let spread: Double?
        let duration: Double?

        var target: PinchTarget {
            PinchTarget(
                elementTarget: elementTarget,
                centerX: centerX,
                centerY: centerY,
                scale: scale,
                spread: spread,
                duration: duration
            )
        }
    }

    struct RotateGesturePayload {
        let elementTarget: ElementTarget?
        let centerX: Double?
        let centerY: Double?
        let angle: Double
        let radius: Double?
        let duration: Double?

        var target: RotateTarget {
            RotateTarget(
                elementTarget: elementTarget,
                centerX: centerX,
                centerY: centerY,
                angle: angle,
                radius: radius,
                duration: duration
            )
        }
    }

    struct TwoFingerTapGesturePayload {
        let elementTarget: ElementTarget?
        let centerX: Double?
        let centerY: Double?
        let spread: Double?

        var target: TwoFingerTapTarget {
            TwoFingerTapTarget(
                elementTarget: elementTarget,
                centerX: centerX,
                centerY: centerY,
                spread: spread
            )
        }
    }

    struct DrawPathGesturePayload {
        let points: [PathPoint]
        let duration: Double?
        let velocity: Double?

        var target: DrawPathTarget {
            DrawPathTarget(points: points, duration: duration, velocity: velocity)
        }
    }

    struct DrawBezierGesturePayload {
        let startX: Double
        let startY: Double
        let segments: [BezierSegment]
        let samplesPerSegment: Int?
        let duration: Double?
        let velocity: Double?

        var target: DrawBezierTarget {
            DrawBezierTarget(
                startX: startX,
                startY: startY,
                segments: segments,
                samplesPerSegment: samplesPerSegment,
                duration: duration,
                velocity: velocity
            )
        }
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
        case performCustomAction(CustomActionTarget, count: CountArgument)
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
        let steps: [RunBatchStep]
        let policy: BatchPolicy
    }

    enum RunBatchStep {
        case planned(RunBatchPreparedStep)
        case invalid(commandName: String, failure: BatchStepFailure)

        var commandName: String {
            switch self {
            case .planned(let step):
                return step.commandName
            case .invalid(let commandName, _):
                return commandName
            }
        }
    }

    struct RunBatchPreparedStep {
        let originalIndex: Int
        let commandName: String
        let action: TheScore.Action
        let expectation: ActionExpectation
        let deadline: TheScore.Deadline

        init(
            originalIndex: Int,
            commandName: String,
            action: TheScore.Action,
            expectation: ActionExpectation,
            deadline: TheScore.Deadline
        ) {
            self.action = action
            self.expectation = expectation
            self.deadline = deadline
            self.originalIndex = originalIndex
            self.commandName = commandName
        }

        var typedStep: TheScore.BatchStep {
            TheScore.BatchStep(
                action: action,
                expectation: expectation,
                deadline: deadline
            )
        }
    }

    struct BatchStepFailure {
        let message: String
        let details: FailureDetails?
        let includeDetailsInResult: Bool

        var resultResponse: FenceResponse {
            if includeDetailsInResult {
                return .error(message, details: details)
            }
            return .error(message)
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let payload: RequestPayload
        let expectationPayload: ExpectationPayload
        /// Non-nil when the command short-circuits before dispatch (help/quit/exit).
        let immediateResponse: FenceResponse?
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

    /// Parse and validate a raw request dictionary into typed fields.
    /// Returns an ImmediateResponse-bearing `ParsedRequest` for help/quit/exit
    /// so the caller short-circuits without logging or dispatching.
    func parseRequest(_ request: [String: Any]) throws -> ParsedRequest {
        let commandString = try request.requiredSchemaString("command")
        guard let command = Command(rawValue: commandString) else {
            return ParsedRequest(
                command: .help,
                requestId: "",
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: .error("Unknown command: \(commandString). Use 'help' for available commands.")
            )
        }
        var arguments = request
        arguments.removeValue(forKey: "command")
        return try parseRequest(command: command, arguments: arguments)
    }

    func parseRequest(command: Command, request: [String: Any]) throws -> ParsedRequest {
        var arguments = request
        arguments.removeValue(forKey: "command")
        return try parseRequest(command: command, arguments: arguments)
    }

    func parseRequest(command: Command, arguments: [String: Any]) throws -> ParsedRequest {
        try validateRequestKeys(command: command, arguments: arguments)
        if let immediate = handleImmediateCommand(command) {
            return ParsedRequest(
                command: command,
                requestId: "",
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: immediate
            )
        }
        let requestId = (arguments["requestId"] as? String) ?? UUID().uuidString
        let expectationPayload = try parseExpectationPayload(arguments)
        let payload: RequestPayload = if command == .waitForChange {
            .waitForChange(expectationPayload)
        } else {
            try decodeRequestPayload(command: command, request: arguments, requestId: requestId)
        }

        return ParsedRequest(
            command: command,
            requestId: requestId,
            payload: payload,
            expectationPayload: expectationPayload,
            immediateResponse: nil
        )
    }

    func parseRequest(operation: NormalizedOperation) throws -> ParsedRequest {
        try parseRequest(command: operation.command, arguments: operation.arguments)
    }

    private func validateRequestKeys(command: Command, arguments: [String: Any]) throws {
        let metadataKeys = Set(["requestId"])
        let parameterKeys = Set(command.parameters.map(\.key))
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments[unexpectedKey],
            expected: "valid \(command.rawValue) parameter"
        )
    }

    func parsePlaybackOperation(_ operation: PlaybackOperation) throws -> ParsedRequest {
        try parseRequest(operation: operation.normalizedOperation())
    }

    func decodeRequestPayload(
        command: Command,
        request: [String: Any],
        requestId: String
    ) throws -> RequestPayload {
        switch command {
        case .help, .status, .ping, .quit, .exit, .listDevices, .getPasteboard,
             .dismissKeyboard, .getSessionState, .listTargets, .getSessionLog:
            return .none
        case .getInterface, .getScreen, .stopRecording:
            return try decodeObservationPayload(command: command, request: request, requestId: requestId)
        case .waitForChange:
            throw FenceError.invalidRequest("wait_for_change payload is decoded through expectation parsing")
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate,
             .twoFingerTap, .drawPath, .drawBezier:
            return try decodeGestureRequestPayload(command: command, request: request)
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge,
             .activate, .increment, .decrement, .performCustomAction,
             .rotor, .typeText, .editAction, .setPasteboard, .waitFor:
            return try decodeElementActionPayload(command: command, request: request)
        case .startRecording, .runBatch, .connect, .archiveSession, .startHeist,
             .stopHeist, .playHeist:
            return try decodeSessionPayload(command: command, request: request)
        }
    }
}

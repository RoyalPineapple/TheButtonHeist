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
        let steps: [RunBatchStepRequest]
        let policy: BatchPolicy
    }

    enum RunBatchStepRequest {
        case decoded(ParsedRequest)
        case invalid(commandName: String, failure: BatchStepDecodeFailure)

        var commandName: String {
            switch self {
            case .decoded(let request):
                return request.command.rawValue
            case .invalid(let commandName, _):
                return commandName
            }
        }
    }

    struct BatchStepDecodeFailure {
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

    func parsePlaybackOperation(
        _ operation: PlaybackOperation,
        bridgeArguments request: [String: Any]
    ) throws -> ParsedRequest {
        try parseRequest(command: operation.command, request: request)
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

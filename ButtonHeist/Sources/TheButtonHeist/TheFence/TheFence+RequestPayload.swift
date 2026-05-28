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
        case oneFingerTap(TapGesturePayload)
        case longPress(LongPressGesturePayload)
        case swipe(SwipeGesturePayload)
        case drag(DragGesturePayload)
        case pinch(PinchGesturePayload)
        case rotate(RotateGesturePayload)
        case twoFingerTap(TwoFingerTapGesturePayload)
        case drawPath(DrawPathGesturePayload)
        case drawBezier(DrawBezierGesturePayload)
    }

    struct TapGesturePayload {
        let selection: GesturePointSelection

        var target: TapTarget {
            TapTarget(selection: selection)
        }
    }

    struct LongPressGesturePayload {
        let selection: GesturePointSelection
        let duration: Double

        var target: LongPressTarget {
            LongPressTarget(
                selection: selection,
                duration: duration
            )
        }
    }

    struct SwipeGesturePayload {
        let selection: SwipeGestureSelection
        let duration: Double?

        var target: SwipeTarget {
            SwipeTarget(
                selection: selection,
                duration: duration
            )
        }
    }

    struct DragGesturePayload {
        let start: GesturePointSelection
        let endX: Double
        let endY: Double
        let duration: Double?

        var target: DragTarget {
            DragTarget(
                start: start,
                end: ScreenPoint(x: endX, y: endY),
                duration: duration
            )
        }
    }

    struct PinchGesturePayload {
        let center: GesturePointSelection
        let scale: Double
        let spread: Double?
        let duration: Double?

        var target: PinchTarget {
            PinchTarget(
                center: center,
                scale: scale,
                spread: spread,
                duration: duration
            )
        }
    }

    struct RotateGesturePayload {
        let center: GesturePointSelection
        let angle: Double
        let radius: Double?
        let duration: Double?

        var target: RotateTarget {
            RotateTarget(
                center: center,
                angle: angle,
                radius: radius,
                duration: duration
            )
        }
    }

    struct TwoFingerTapGesturePayload {
        let center: GesturePointSelection
        let spread: Double?

        var target: TwoFingerTapTarget {
            TwoFingerTapTarget(
                center: center,
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
    }

    struct CountArgument {
        let value: Int?
        let observed: String?
    }

    struct ConnectRequest {
        let targetName: String?
        let device: String?
        let token: String?
    }

    struct RunBatchRequest {
        let steps: [RunBatchPreparedStep]
        let policy: BatchPolicy
    }

    struct RunBatchPreparedStep {
        let originalIndex: Int
        let commandName: String
        let typedStep: TheScore.BatchStep

        init(
            originalIndex: Int,
            commandName: String,
            typedStep: TheScore.BatchStep
        ) {
            self.originalIndex = originalIndex
            self.commandName = commandName
            self.typedStep = typedStep
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let payload: RequestPayload
        let expectationPayload: ExpectationPayload
        /// Non-nil when the command short-circuits before dispatch (help/quit).
        let immediateResponse: FenceResponse?

        init(
            command: Command,
            requestId: String,
            payload: RequestPayload,
            expectationPayload: ExpectationPayload,
            immediateResponse: FenceResponse?
        ) {
            self.command = command
            self.requestId = requestId
            self.payload = payload
            self.expectationPayload = expectationPayload
            self.immediateResponse = immediateResponse
        }
    }

    struct ClientMessageExecutionPlan {
        let messages: [ClientMessage]
        let timeout: TimeInterval
        let recordsCompletion: Bool
    }

    struct RoutedCommandRequest {
        private let arguments: CommandArgumentEnvelope
        let expectationPayload: ExpectationPayload?

        init(arguments: CommandArgumentEnvelope, expectationPayload: ExpectationPayload? = nil) {
            self.arguments = arguments
            self.expectationPayload = expectationPayload
        }

        func string(_ key: String) -> String? { arguments.string(key) }

        func argumentEnvelopeForRequestDecoding() -> CommandArgumentEnvelope {
            arguments
        }

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
    /// Returns an ImmediateResponse-bearing `ParsedRequest` for help/quit
    /// so the caller short-circuits without logging or dispatching.
    func parseRequest(_ request: [String: Any]) throws -> ParsedRequest {
        let requestEnvelope = try CommandArgumentEnvelope(arguments: request, droppingCommandKey: false)
        let commandString = try requestEnvelope.requiredSchemaString("command")
        guard let command = Command(rawValue: commandString) else {
            return ParsedRequest(
                command: .help,
                requestId: "",
                payload: .none,
                expectationPayload: ExpectationPayload(expectation: nil, timeout: nil),
                immediateResponse: .error("Unknown command: \(commandString). Use 'help' for available commands.")
            )
        }
        return try parseRequest(command: command, arguments: requestEnvelope.dropping("command"))
    }

    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        guard command.descriptor.isPublicRequestContract else {
            throw SchemaValidationError(
                field: "command",
                observed: command.rawValue as Any,
                expected: "public Button Heist command"
            )
        }
        return try parseRequest(
            command: command,
            arguments: arguments,
            expectationPayload: nil
        )
    }

    private func parseRequest(
        command: Command,
        arguments: CommandArgumentEnvelope,
        expectationPayload typedExpectationPayload: ExpectationPayload?
    ) throws -> ParsedRequest {
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
        let requestId = arguments.string("requestId") ?? UUID().uuidString
        let expectationPayload = try typedExpectationPayload ?? parseExpectationPayload(arguments)
        let payload: RequestPayload = if command.requestPayloadKind == .waitForChange {
            .waitForChange(expectationPayload)
        } else {
            try decodeRequestPayload(command: command, arguments: arguments, requestId: requestId)
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
        let request = operation.request
        return try parseRequest(
            command: operation.command,
            arguments: request.argumentEnvelopeForRequestDecoding(),
            expectationPayload: request.expectationPayload
        )
    }

    private func validateRequestKeys(command: Command, arguments: CommandArgumentEnvelope) throws {
        let metadataKeys = Set(["requestId"])
        let parameterKeys = Set(command.parameters.map(\.key))
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments.observedValue(for: unexpectedKey),
            expected: "valid \(command.rawValue) parameter"
        )
    }

    func parsePlaybackOperation(_ operation: PlaybackOperation) throws -> ParsedRequest {
        try parseRequest(operation: operation.normalizedOperation())
    }

    func decodeRequestPayload(
        command: Command,
        arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> RequestPayload {
        switch command.requestPayloadKind {
        case .none:
            return .none
        case .observation:
            return try decodeObservationPayload(command: command, arguments: arguments, requestId: requestId)
        case .waitForChange:
            throw FenceError.invalidRequest("wait_for_change payload is decoded through expectation parsing")
        case .gesture:
            return try decodeGestureRequestPayload(command: command, arguments: arguments)
        case .elementAction:
            return try decodeElementActionPayload(command: command, arguments: arguments)
        case .session:
            return try decodeSessionPayload(command: command, arguments: arguments)
        }
    }
}

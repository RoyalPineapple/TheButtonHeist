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

    enum GesturePointIntent {
        case element(ElementTarget)
        case point(x: Double, y: Double)
        case unspecified

        var elementTarget: ElementTarget? {
            guard case .element(let target) = self else { return nil }
            return target
        }

        var pointX: Double? {
            guard case .point(let x, _) = self else { return nil }
            return x
        }

        var pointY: Double? {
            guard case .point(_, let y) = self else { return nil }
            return y
        }
    }

    enum SwipeGestureEndIntent {
        case point(x: Double, y: Double)
        case direction(SwipeDirection)
        case unspecified

        var endX: Double? {
            guard case .point(let x, _) = self else { return nil }
            return x
        }

        var endY: Double? {
            guard case .point(_, let y) = self else { return nil }
            return y
        }

        var direction: SwipeDirection? {
            guard case .direction(let direction) = self else { return nil }
            return direction
        }
    }

    enum SwipeGestureIntent {
        case absolute(start: GesturePointIntent, end: SwipeGestureEndIntent)
        case unit(elementTarget: ElementTarget?, start: UnitPoint, end: UnitPoint, direction: SwipeDirection?)

        var elementTarget: ElementTarget? {
            switch self {
            case .absolute(let start, _):
                return start.elementTarget
            case .unit(let elementTarget, _, _, _):
                return elementTarget
            }
        }

        var startX: Double? {
            guard case .absolute(let start, _) = self else { return nil }
            return start.pointX
        }

        var startY: Double? {
            guard case .absolute(let start, _) = self else { return nil }
            return start.pointY
        }

        var endX: Double? {
            guard case .absolute(_, let end) = self else { return nil }
            return end.endX
        }

        var endY: Double? {
            guard case .absolute(_, let end) = self else { return nil }
            return end.endY
        }

        var direction: SwipeDirection? {
            switch self {
            case .absolute(_, let end):
                return end.direction
            case .unit(_, _, _, let direction):
                return direction
            }
        }

        var start: UnitPoint? {
            guard case .unit(_, let start, _, _) = self else { return nil }
            return start
        }

        var end: UnitPoint? {
            guard case .unit(_, _, let end, _) = self else { return nil }
            return end
        }
    }

    struct TouchTapGesturePayload {
        let intent: GesturePointIntent

        var elementTarget: ElementTarget? { intent.elementTarget }
        var pointX: Double? { intent.pointX }
        var pointY: Double? { intent.pointY }

        var target: TouchTapTarget {
            TouchTapTarget(elementTarget: elementTarget, pointX: pointX, pointY: pointY)
        }
    }

    struct LongPressGesturePayload {
        let intent: GesturePointIntent
        let duration: Double

        var elementTarget: ElementTarget? { intent.elementTarget }
        var pointX: Double? { intent.pointX }
        var pointY: Double? { intent.pointY }

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
        let intent: SwipeGestureIntent
        let duration: Double?

        var elementTarget: ElementTarget? { intent.elementTarget }
        var startX: Double? { intent.startX }
        var startY: Double? { intent.startY }
        var endX: Double? { intent.endX }
        var endY: Double? { intent.endY }
        var direction: SwipeDirection? { intent.direction }
        var start: UnitPoint? { intent.start }
        var end: UnitPoint? { intent.end }

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
        let start: GesturePointIntent
        let endX: Double
        let endY: Double
        let duration: Double?

        var elementTarget: ElementTarget? { start.elementTarget }
        var startX: Double? { start.pointX }
        var startY: Double? { start.pointY }

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
        let center: GesturePointIntent
        let scale: Double
        let spread: Double?
        let duration: Double?

        var elementTarget: ElementTarget? { center.elementTarget }
        var centerX: Double? { center.pointX }
        var centerY: Double? { center.pointY }

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
        let center: GesturePointIntent
        let angle: Double
        let radius: Double?
        let duration: Double?

        var elementTarget: ElementTarget? { center.elementTarget }
        var centerX: Double? { center.pointX }
        var centerY: Double? { center.pointY }

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
        let center: GesturePointIntent
        let spread: Double?

        var elementTarget: ElementTarget? { center.elementTarget }
        var centerX: Double? { center.pointX }
        var centerY: Double? { center.pointY }

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
        /// Element target metadata decoded at the public request edge for batch lowering.
        let routedBatchTarget: BatchExecutionTarget?
        /// Non-nil when the command short-circuits before dispatch (help/quit/exit).
        let immediateResponse: FenceResponse?

        init(
            command: Command,
            requestId: String,
            payload: RequestPayload,
            expectationPayload: ExpectationPayload,
            routedBatchTarget: BatchExecutionTarget? = nil,
            immediateResponse: FenceResponse?
        ) {
            self.command = command
            self.requestId = requestId
            self.payload = payload
            self.expectationPayload = expectationPayload
            self.routedBatchTarget = routedBatchTarget
            self.immediateResponse = immediateResponse
        }
    }

    struct RoutedCommandRequest {
        private let arguments: CommandArgumentEnvelope
        let expectationPayload: ExpectationPayload?

        init(arguments: CommandArgumentEnvelope, expectationPayload: ExpectationPayload? = nil) {
            self.arguments = arguments
            self.expectationPayload = expectationPayload
        }

        func string(_ key: String) -> String? { arguments.string(key) }

        func batchExecutionTarget() throws -> BatchExecutionTarget? {
            try Self.batchExecutionTarget(from: arguments)
        }

        func argumentEnvelopeForRequestDecoding() -> CommandArgumentEnvelope {
            arguments
        }

        private static func batchExecutionTarget(from arguments: CommandArgumentEnvelope) throws -> BatchExecutionTarget? {
            let sourceHeistId = try arguments.schemaString("heistId")
            let ordinal = try arguments.schemaNonNegativeInteger("ordinal")
            let matcher = ElementMatcher(
                label: try arguments.schemaString("label"),
                identifier: try arguments.schemaString("identifier"),
                value: try arguments.schemaString("value"),
                traits: try TheFence.parseTraitNames(
                    try arguments.schemaStringArray("traits"),
                    field: arguments.field("traits")
                ),
                excludeTraits: try TheFence.parseTraitNames(
                    try arguments.schemaStringArray("excludeTraits"),
                    field: arguments.field("excludeTraits")
                )
            )
            guard sourceHeistId != nil || matcher.hasPredicates || ordinal != nil else { return nil }
            return BatchExecutionTarget(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
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
        return try parseRequest(command: command, arguments: CommandArgumentEnvelope(arguments: arguments))
    }

    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        try parseRequest(
            command: command,
            arguments: arguments,
            expectationPayload: nil
        )
    }

    private func parseRequest(
        command: Command,
        arguments: CommandArgumentEnvelope,
        expectationPayload typedExpectationPayload: ExpectationPayload?,
        routedBatchTarget: BatchExecutionTarget? = nil
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
        let payload: RequestPayload = if command == .waitForChange {
            .waitForChange(expectationPayload)
        } else {
            try decodeRequestPayload(command: command, arguments: arguments, requestId: requestId)
        }

        return ParsedRequest(
            command: command,
            requestId: requestId,
            payload: payload,
            expectationPayload: expectationPayload,
            routedBatchTarget: routedBatchTarget,
            immediateResponse: nil
        )
    }

    func parseRequest(operation: NormalizedOperation) throws -> ParsedRequest {
        let request = operation.request
        return try parseRequest(
            command: operation.command,
            arguments: request.argumentEnvelopeForRequestDecoding(),
            expectationPayload: request.expectationPayload,
            routedBatchTarget: try request.batchExecutionTarget()
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
        switch command {
        case .help, .status, .ping, .quit, .exit, .listDevices, .getPasteboard,
             .dismissKeyboard, .getSessionState, .listTargets, .getSessionLog:
            return .none
        case .getInterface, .getScreen, .stopRecording:
            return try decodeObservationPayload(command: command, arguments: arguments, requestId: requestId)
        case .waitForChange:
            throw FenceError.invalidRequest("wait_for_change payload is decoded through expectation parsing")
        case .oneFingerTap, .longPress, .swipe, .drag, .pinch, .rotate,
             .twoFingerTap, .drawPath, .drawBezier:
            return try decodeGestureRequestPayload(command: command, arguments: arguments)
        case .scroll, .scrollToVisible, .elementSearch, .scrollToEdge,
             .activate, .increment, .decrement, .performCustomAction,
             .rotor, .typeText, .editAction, .setPasteboard, .waitFor:
            return try decodeElementActionPayload(command: command, arguments: arguments)
        case .startRecording, .runBatch, .connect, .archiveSession, .startHeist,
             .stopHeist, .playHeist:
            return try decodeSessionPayload(command: command, arguments: arguments)
        }
    }
}

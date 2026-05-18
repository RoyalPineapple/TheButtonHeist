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

        var resultDictionary: [String: Any] {
            if includeDetailsInResult {
                return FenceResponse.error(message, details: details).jsonDict() ?? fallbackResultDictionary
            }
            return fallbackResultDictionary
        }

        private var fallbackResultDictionary: [String: Any] {
            [
                "status": "error",
                "message": message,
            ]
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let originalRequest: [String: Any]
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
}

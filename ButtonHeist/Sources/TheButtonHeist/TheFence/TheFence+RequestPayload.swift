import Foundation
import ThePlans

import TheScore

extension TheFence {

    struct MissingAccessibilityTarget: Error {
        let command: Command
    }

    struct ContainerTargetRequiresElement: Error, Sendable, Equatable {
        let command: Command
    }

    typealias ParsedRequestHandler = @ButtonHeistActor @Sendable (TheFence) async throws -> FenceResponse

    struct DurableHeistActionCommands: Sendable {
        private let actions: NonEmptyArray<HeistActionCommand>

        init?(_ actions: NonEmptyArray<HeistActionCommand>) {
            guard actions.allSatisfy({ $0.durableHeistActionFailure == nil }) else {
                return nil
            }
            self.actions = actions
        }

        var first: HeistActionCommand {
            actions.first
        }

        var count: Int {
            actions.count
        }

        var values: [HeistActionCommand] {
            actions.elements
        }
    }

    enum SingleStepHeistRequest: Sendable {
        case actions(command: Command, DurableHeistActionCommands, expectation: ExpectationPayload)
        case wait(command: Command, WaitStep)
    }

    struct DirectActionRequest: Sendable {
        let command: Command
        let action: HeistActionCommand
    }

    enum DecodedRequestDispatch: Sendable {
        case singleStepHeist(SingleStepHeistRequest)
        case directAction(DirectActionRequest)
        case handler(ParsedRequestHandler)

        init(handler: @escaping ParsedRequestHandler) {
            self = .handler(handler)
        }
    }

    fileprivate struct CommandAdmission: Sendable {
        let command: Command
        let requestId: String
        let dispatch: DecodedRequestDispatch

        @ButtonHeistActor
        init(
            fence: TheFence,
            input: FenceCommandInput
        ) throws {
            let command = input.command
            let arguments = input.arguments
            try Self.validateBoundaryShape(command: command, arguments: arguments)
            let requestId = try Self.requestId(arguments: arguments)
            let expectationPayload = try ExpectationPayload(arguments: arguments)
            let dispatch: DecodedRequestDispatch
            switch command {
            case .ping:
                dispatch = DecodedRequestDispatch { fence in try await fence.handlePing() }
            case .listDevices:
                dispatch = DecodedRequestDispatch { fence in try await fence.handleListDevices() }
            case .getInterface:
                let request = try fence.makeGetInterfaceRequest(arguments)
                dispatch = DecodedRequestDispatch { fence in try await fence.handleGetInterface(request) }
            case .getScreen:
                let request = try fence.makeScreenRequest(arguments, requestId: requestId)
                dispatch = DecodedRequestDispatch { fence in try await fence.handleGetScreen(request) }
            case .getPasteboard:
                dispatch = DecodedRequestDispatch { fence in try await fence.handleGetPasteboard() }
            case .getAnnouncements:
                dispatch = DecodedRequestDispatch { fence in try await fence.handleGetAnnouncements() }
            case .wait:
                dispatch = try Self.admitWait(arguments, expectation: expectationPayload)
            case .oneFingerTap:
                dispatch = try TheFence.appInteractionDispatch(
                    .oneFingerTap, .mechanicalTap(try fence.decodeTapTarget(arguments)),
                    expectationPayload: expectationPayload
                )
            case .longPress:
                dispatch = try TheFence.appInteractionDispatch(
                    .longPress, .mechanicalLongPress(try fence.decodeLongPressTarget(arguments)),
                    expectationPayload: expectationPayload
                )
            case .swipe:
                dispatch = try TheFence.appInteractionDispatch(
                    .swipe, .mechanicalSwipe(try fence.decodeSwipeTarget(arguments)),
                    expectationPayload: expectationPayload
                )
            case .drag:
                dispatch = try TheFence.appInteractionDispatch(
                    .drag, .mechanicalDrag(try fence.decodeDragTarget(arguments)),
                    expectationPayload: expectationPayload
                )
            case .scroll:
                dispatch = try Self.admitScroll(arguments, expectation: expectationPayload)
            case .scrollToVisible:
                dispatch = try TheFence.appInteractionDispatch(
                    .scrollToVisible, .viewportScrollToVisible(try arguments.requiredAccessibilityTarget(command: .scrollToVisible)),
                    expectationPayload: expectationPayload
                )
            case .scrollToEdge:
                dispatch = try Self.admitScrollToEdge(arguments, expectation: expectationPayload)
            case .activate:
                dispatch = try Self.admitActivate(arguments, expectation: expectationPayload)
            case .rotor:
                dispatch = try Self.admitRotor(arguments, expectation: expectationPayload)
            case .typeText:
                dispatch = try Self.admitTypeText(arguments, expectation: expectationPayload)
            case .editAction:
                dispatch = try Self.admitEditAction(arguments, expectation: expectationPayload)
            case .setPasteboard:
                dispatch = try Self.admitSetPasteboard(arguments, expectation: expectationPayload)
            case .dismissKeyboard:
                dispatch = try TheFence.appInteractionDispatch(
                    .dismissKeyboard, .dismissKeyboard,
                    expectationPayload: expectationPayload
                )
            case .perform:
                let request = try fence.decodePerformRequest(arguments)
                dispatch = DecodedRequestDispatch { fence in try await fence.handlePerform(request) }
            case .runHeist:
                let request = try fence.decodeRunHeistRequest(arguments)
                dispatch = DecodedRequestDispatch { fence in try await fence.handleRunHeist(request) }
            case .listHeists:
                let request = try fence.decodeListHeistsRequest(arguments)
                dispatch = DecodedRequestDispatch { fence in fence.handleListHeists(request) }
            case .describeHeist:
                let request = try fence.decodeDescribeHeistRequest(arguments)
                dispatch = DecodedRequestDispatch { fence in fence.handleDescribeHeist(request) }
            case .getSessionState:
                dispatch = DecodedRequestDispatch { fence in .sessionState(payload: fence.currentSessionState()) }
            case .connect:
                let request = try fence.decodeConnectRequest(arguments)
                dispatch = DecodedRequestDispatch { fence in try await fence.handleConnect(request) }
            case .listTargets:
                dispatch = DecodedRequestDispatch { fence in fence.handleListTargets() }
            }

            self.command = command
            self.requestId = requestId
            self.dispatch = dispatch
        }

        private static func validateBoundaryShape(
            command: Command,
            arguments: CommandArgumentEnvelope
        ) throws {
            guard command.descriptor.isPublicRequestContract else {
                throw SchemaValidationError(
                    field: "command",
                    observed: "string \"\(command.rawValue)\"",
                    expected: "public command for The Button Heist"
                )
            }
            let allowedKeys = command.descriptor.topLevelParameterKeys.union([FenceParameterKey.requestId.rawValue])
            if let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
                throw SchemaValidationError(
                    field: arguments.field(forUnknownKey: unexpectedKey),
                    observed: arguments.observedDescription(forUnknownKey: unexpectedKey) ?? "missing",
                    expected: "valid \(command.rawValue) parameter"
                )
            }
        }

        private static func requestId(arguments: CommandArgumentEnvelope) throws -> String {
            try arguments.value(FenceParameters.requestId) ?? UUID().uuidString
        }

        @ButtonHeistActor
        private static func admitWait(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            let predicate = try ExpectationPayload.parseRequiredPredicate(arguments.value(for: .predicate))
            return TheFence.waitDispatch(.wait, WaitStep(
                predicate: predicate,
                timeout: expectation.timeout ?? defaultWaitTimeout
            ))
        }

        @ButtonHeistActor
        private static func admitScroll(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            let direction = try arguments.value(
                FenceParameters.scrollDirection,
                defaultFrom: Command.scroll.descriptor
            )
            return try TheFence.appInteractionDispatch(
                .scroll,
                .viewportScroll(ScrollTarget(
                    selection: try arguments.scrollContainerSelection(),
                    direction: direction
                )),
                expectationPayload: expectation
            )
        }

        @ButtonHeistActor
        private static func admitScrollToEdge(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            let edge = try arguments.value(
                FenceParameters.scrollEdge,
                defaultFrom: Command.scrollToEdge.descriptor
            )
            return try TheFence.appInteractionDispatch(
                .scrollToEdge,
                .viewportScrollToEdge(ScrollToEdgeTarget(
                    selection: try arguments.scrollContainerSelection(),
                    edge: edge
                )),
                expectationPayload: expectation
            )
        }

        @ButtonHeistActor
        private static func admitActivate(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            let target = try arguments.requiredAccessibilityTarget(command: .activate)
            let actionName = try arguments.value(FenceParameters.actionName)
            return try TheFence.appInteractionDispatch(
                .activate,
                TheFence.accessibilityActionCommand(target: target, actionName: actionName),
                expectationPayload: expectation
            )
        }

        @ButtonHeistActor
        private static func admitRotor(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            let rotor = try arguments.value(FenceParameters.rotorName)
            let rotorIndex = try arguments.value(FenceParameters.rotorIndex)
            if rotor != nil, rotorIndex != nil {
                throw SchemaValidationError(
                    field: "rotor/rotorIndex",
                    observed: arguments.observedDescription,
                    expected: "either rotor or rotorIndex"
                )
            }
            let selection: RotorSelection = if let rotor {
                .named(rotor)
            } else if let rotorIndex {
                .index(rotorIndex)
            } else {
                .automatic
            }
            return try TheFence.appInteractionDispatch(
                .rotor,
                .rotor(
                    selection: selection,
                    target: try arguments.requiredAccessibilityTarget(command: .rotor),
                    direction: try arguments.value(
                        FenceParameters.rotorDirection,
                        defaultFrom: Command.rotor.descriptor
                    )
                ),
                expectationPayload: expectation
            )
        }

        @ButtonHeistActor
        private static func admitTypeText(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            let replacingExisting = try arguments.value(
                FenceParameters.replacingExisting,
                defaultFrom: Command.typeText.descriptor
            )
            let text = try arguments.requiredValue(FenceParameters.text)
            if text.isEmpty, !replacingExisting {
                throw SchemaValidationError(
                    field: arguments.field(.text),
                    observed: "string \"\"",
                    expected: "non-empty string"
                )
            }
            return try TheFence.appInteractionDispatch(
                .typeText,
                .typeText(
                    text: .literal(text),
                    target: try arguments.decodedAccessibilityTarget().map {
                        try $0.resolvedElementTarget(command: .typeText)
                    },
                    replacingExisting: replacingExisting
                ),
                expectationPayload: expectation
            )
        }

        @ButtonHeistActor
        private static func admitEditAction(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            try TheFence.appInteractionDispatch(
                .editAction,
                .editAction(EditActionTarget(
                    action: try arguments.requiredValue(FenceParameters.editAction)
                )),
                expectationPayload: expectation
            )
        }

        @ButtonHeistActor
        private static func admitSetPasteboard(
            _ arguments: CommandArgumentEnvelope,
            expectation: ExpectationPayload
        ) throws -> DecodedRequestDispatch {
            try TheFence.appInteractionDispatch(
                .setPasteboard,
                .setPasteboard(SetPasteboardTarget(
                    text: try arguments.requiredValue(FenceParameters.pasteboardText)
                )),
                expectationPayload: expectation
            )
        }
    }

    struct ParsedRequest: Sendable {
        fileprivate let admission: CommandAdmission

        fileprivate init(admission: CommandAdmission) {
            self.admission = admission
        }

        var command: Command { admission.command }

        var requestId: String { admission.requestId }

        var dispatch: DecodedRequestDispatch { admission.dispatch }

        var singleStepHeistRequest: SingleStepHeistRequest? {
            guard case .singleStepHeist(let request) = dispatch else { return nil }
            return request
        }

        var directActionRequest: DirectActionRequest? {
            guard case .directAction(let request) = dispatch else { return nil }
            return request
        }
    }

    static func waitDispatch(_ command: Command, _ step: WaitStep) -> DecodedRequestDispatch {
        .singleStepHeist(.wait(command: command, step))
    }

    static func appInteractionDispatch(
        _ command: Command,
        _ firstCommand: HeistActionCommand,
        _ additionalCommands: HeistActionCommand...,
        expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        precondition(command.dispatchesAppInteraction, "\(command.rawValue) is not registered as an app interaction command")
        let actions = NonEmptyArray(firstCommand, rest: additionalCommands)
        if let durableActions = DurableHeistActionCommands(actions) {
            return .singleStepHeist(.actions(command: command, durableActions, expectation: expectationPayload))
        }

        guard actions.count == 1 else {
            throw FenceError.invalidRequest(
                "command \"\(command.rawValue)\" direct dispatch requires exactly one action command"
            )
        }
        guard expectationPayload.expectation == nil else {
            throw FenceError.invalidRequest(
                "command \"\(command.rawValue)\" direct dispatch does not support expect"
            )
        }
        return .directAction(DirectActionRequest(command: command, action: actions.first))
    }

    /// Admit a routed public command input into TheFence's typed runtime.
    @_spi(ButtonHeistTooling) public func admit(_ input: FenceCommandInput) throws -> FenceOperationRequest {
        FenceOperationRequest(parsed: ParsedRequest(admission: try CommandAdmission(fence: self, input: input)))
    }

}

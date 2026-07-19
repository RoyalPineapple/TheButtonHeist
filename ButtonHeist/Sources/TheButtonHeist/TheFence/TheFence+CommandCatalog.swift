import Foundation
import ThePlans
import TheScore

@_spi(ButtonHeistTooling) public enum FenceCommandFamily: String, Sendable, CaseIterable {
    case session
    case observation
    case assertion
    case semanticAction
    case spatialAction
    case viewportDebug
    case heistRuntime
}

@_spi(ButtonHeistTooling) public enum FenceCommandFixedTimeout: String, Sendable, Equatable, CaseIterable {
    case health
    case standardAction
    case longAction
    case explore
    case screenCapture

    public var seconds: TimeInterval {
        switch self {
        case .health:
            return 3
        case .standardAction:
            return 15
        case .longAction:
            return 30
        case .explore:
            return 60
        case .screenCapture:
            return 30
        }
    }
}

@_spi(ButtonHeistTooling) public enum FenceCommandTimeoutSemantics: Sendable, Equatable {
    case none
    case fixed(FenceCommandFixedTimeout)
    case wait
    case singleStepAction(base: FenceCommandFixedTimeout)
    case performStep

    public var fixedSeconds: TimeInterval? {
        guard case .fixed(let timeout) = self else { return nil }
        return timeout.seconds
    }

    public var singleStepBaseSeconds: TimeInterval? {
        guard case .singleStepAction(let timeout) = self else { return nil }
        return timeout.seconds
    }
}

@_spi(ButtonHeistTooling) public struct FenceCommandDescriptor: Sendable, Equatable {
    public let command: TheFence.Command
    public let family: FenceCommandFamily
    public let requiresConnectionBeforeDispatch: Bool
    public let parameters: FenceCommandParameters
    public let timeout: FenceCommandTimeoutSemantics
    public let cliExposure: CLIExposure
    public let mcpExposure: MCPExposure
    public let mcpAnnotations: MCPToolAnnotationSpec?
    public let description: String

    public var isPublicRequestContract: Bool {
        cliExposure != .notExposed || mcpExposure != .notExposed
    }

    public var topLevelParameterKeys: Set<String> {
        Set(parameters.map(\.key))
    }

    public func parameter(named key: FenceParameterKey) -> FenceParameterSpec? {
        let matches = parameters.flatMap { $0.parameters(named: key) }
        guard let first = matches.first,
              matches.dropFirst().allSatisfy({ $0 == first }) else {
            return nil
        }
        return first
    }

    public func defaultValue<Value>(for parameter: FenceParameter<Value>) -> Value? {
        _ = resolvedParameter(for: parameter)
        return parameter.defaultValue
    }

    public func requiredDefaultValue<Value>(for parameter: FenceParameter<Value>) -> Value {
        guard let value = defaultValue(for: parameter) else {
            preconditionFailure("No default registered for \(command.rawValue).\(parameter.key.rawValue)")
        }
        return value
    }

    public func allowedRawValues<Value>(for parameter: FenceParameter<Value>) -> [String] {
        _ = resolvedParameter(for: parameter)
        guard let values = parameter.allowedRawValues else {
            preconditionFailure("No enum values registered for \(command.rawValue).\(parameter.key.rawValue)")
        }
        return values
    }

    private func resolvedParameter<Value>(for parameter: FenceParameter<Value>) -> FenceParameterSpec {
        guard let spec = self.parameter(named: parameter.key),
              spec == parameter.spec else {
            preconditionFailure("No matching parameter registered for \(command.rawValue).\(parameter.key.rawValue)")
        }
        return spec
    }
}

typealias FenceCommandAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.Command,
    TheFence.CommandArgumentEnvelope
) throws -> TheFence.CommandExecution
typealias FenceFixedResponseAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.CommandArgumentEnvelope,
    TimeInterval
) throws -> TheFence.CommandExecution
typealias FenceResponseAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.CommandArgumentEnvelope
) throws -> TheFence.CommandExecution
typealias FenceActionAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.CommandArgumentEnvelope
) throws -> HeistActionCommand
extension TheFence {
    public enum Command: String, CaseIterable, Hashable, Sendable {
        case ping
        case listDevices = "list_devices"
        case getInterface = "get_interface"
        case getScreen = "get_screen"
        case getAnnouncements = "get_announcements"
        case wait
        case oneFingerTap = "one_finger_tap"
        case longPress = "long_press"
        case swipe
        case drag
        case scroll
        case scrollToVisible = "scroll_to_visible"
        case scrollToEdge = "scroll_to_edge"
        case activate
        case rotor
        case typeText = "type_text"
        case editAction = "edit_action"
        case setPasteboard = "set_pasteboard"
        case getPasteboard = "get_pasteboard"
        case dismissKeyboard = "dismiss_keyboard"
        case perform
        case runHeist = "run_heist"
        case validateHeist = "validate_heist"
        case listHeists = "list_heists"
        case describeHeist = "describe_heist"
        case getSessionState = "get_session_state"
        case connect
        case listTargets = "list_targets"
    }

}

extension TheFence.Command {
    struct Contract: Sendable {
        let descriptor: FenceCommandDescriptor
        let admission: FenceCommandAdmission

        init(
            command: TheFence.Command,
            family: FenceCommandFamily,
            requiresConnectionBeforeDispatch: Bool,
            parameters: FenceCommandParameters,
            timeout: FenceCommandTimeoutSemantics,
            description: String,
            cliExposure: CLIExposure,
            mcpExposure: MCPExposure,
            mcpAnnotations: MCPToolAnnotationSpec?,
            admission: @escaping FenceCommandAdmission
        ) {
            descriptor = FenceCommandDescriptor(
                command: command,
                family: family,
                requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
                parameters: parameters,
                timeout: timeout,
                cliExposure: cliExposure,
                mcpExposure: mcpExposure,
                mcpAnnotations: mcpAnnotations,
                description: description
            )
            self.admission = admission
        }
    }
}

@_spi(ButtonHeistTooling) public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor {
        contract.descriptor
    }

    static var descriptors: [FenceCommandDescriptor] {
        allCases.map(\.descriptor)
    }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }
}

extension TheFence.Command {
    private func responseContract(
        family: FenceCommandFamily,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: FenceCommandParameters = [],
        timeout: FenceCommandTimeoutSemantics = .none,
        description: String,
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .notExposed,
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        admission: @escaping FenceResponseAdmission
    ) -> Contract {
        Contract(
            command: self,
            family: family,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            timeout: timeout,
            description: description,
            cliExposure: cliExposure,
            mcpExposure: mcpExposure,
            mcpAnnotations: mcpAnnotations,
            admission: { fence, _, arguments in try admission(fence, arguments) }
        )
    }

    private func fixedResponseContract(
        family: FenceCommandFamily,
        requiresConnectionBeforeDispatch: Bool = true,
        parameters: FenceCommandParameters = [],
        timeout: FenceCommandFixedTimeout,
        description: String,
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .notExposed,
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        admission: @escaping FenceFixedResponseAdmission
    ) -> Contract {
        responseContract(
            family: family,
            requiresConnectionBeforeDispatch: requiresConnectionBeforeDispatch,
            parameters: parameters,
            timeout: .fixed(timeout),
            description: description,
            cliExposure: cliExposure,
            mcpExposure: mcpExposure,
            mcpAnnotations: mcpAnnotations,
            admission: { fence, arguments in try admission(fence, arguments, timeout.seconds) }
        )
    }

    private func singleStepActionContract(
        family: FenceCommandFamily,
        parameters: FenceCommandParameters,
        baseTimeout: FenceCommandFixedTimeout,
        description: String,
        admission: @escaping FenceActionAdmission
    ) -> Contract {
        Contract(
            command: self,
            family: family,
            requiresConnectionBeforeDispatch: true,
            parameters: parameters,
            timeout: .singleStepAction(base: baseTimeout),
            description: description,
            cliExposure: .directCommand,
            mcpExposure: .notExposed,
            mcpAnnotations: nil,
            admission: { fence, command, arguments in
                try TheFence.appInteractionExecution(
                    command,
                    try admission(fence, arguments),
                    actionTimeout: baseTimeout.seconds,
                    expectationPayload: try TheFence.ExpectationPayload(arguments: arguments)
                )
            }
        )
    }

    private func directActionContract(
        family: FenceCommandFamily,
        parameters: FenceCommandParameters,
        timeout: FenceCommandFixedTimeout,
        description: String,
        admission: @escaping FenceActionAdmission
    ) -> Contract {
        Contract(
            command: self,
            family: family,
            requiresConnectionBeforeDispatch: true,
            parameters: parameters,
            timeout: .fixed(timeout),
            description: description,
            cliExposure: .directCommand,
            mcpExposure: .notExposed,
            mcpAnnotations: nil,
            admission: { fence, command, arguments in
                try TheFence.directActionExecution(
                    command,
                    try admission(fence, arguments),
                    timeout: timeout.seconds,
                    expectationPayload: try TheFence.ExpectationPayload(arguments: arguments)
                )
            }
        )
    }

    // This exhaustive switch is the canonical command contract and policy table.
    var contract: Contract {
        switch self {
        case .ping:
            return fixedResponseContract(
                family: .session,
                requiresConnectionBeforeDispatch: false,
                timeout: .health,
                description: "Check connection health without reading accessibility state.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { _, _, timeout in
                .init { fence in try await fence.handlePing(timeout: timeout) }
            }
        case .listDevices:
            return responseContract(
                family: .session,
                requiresConnectionBeforeDispatch: false,
                description: "List discovered iOS devices and configured connection targets.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { _, _ in
                .init { fence in try await fence.handleListDevices() }
            }
        case .getInterface:
            return fixedResponseContract(
                family: .observation,
                parameters: [
                    FenceParameterBlocks.interfaceSubtree,
                    FenceParameters.interfaceDetail.spec,
                    FenceParameters.maxScrollsPerContainer.spec,
                    FenceParameters.maxScrollsPerDiscovery.spec,
                ],
                timeout: .explore,
                description: Self.getInterfaceDescription,
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { fence, arguments, timeout in
                let request = try fence.makeGetInterfaceRequest(arguments)
                return .init { fence in try await fence.handleGetInterface(request, timeout: timeout) }
            }
        case .getScreen:
            return fixedResponseContract(
                family: .observation,
                parameters: [
                    FenceParameters.output.spec,
                    FenceParameters.inlineData.spec,
                    FenceParameters.screenMode.spec,
                ],
                timeout: .screenCapture,
                description: "Capture a PNG screenshot with visible interface state. Pass mode=accessibility to render accessibility markers and legend.",
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { fence, arguments, timeout in
                let request = try fence.makeScreenRequest(arguments)
                return .init { fence in try await fence.handleGetScreen(request, timeout: timeout) }
            }
        case .getAnnouncements:
            return fixedResponseContract(
                family: .observation,
                timeout: .health,
                description: "Read recent spoken accessibility text captured from announcement, elementChanged, valueChanged, or screenChanged notifications.",
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { _, _, timeout in
                .init { fence in try await fence.handleGetAnnouncements(timeout: timeout) }
            }
        case .wait:
            return responseContract(
                family: .assertion,
                parameters: FenceCommandParameters(FenceParameterBlocks.wait),
                timeout: .wait,
                description: "Assert that an accessibility predicate is satisfied within timeout "
                    + "by evaluating settled accessibility state.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
            ) { _, arguments in
                let expectation = try TheFence.ExpectationPayload(arguments: arguments)
                return .singleStepHeist(.wait(WaitStep(
                    predicate: try TheFence.ExpectationPayload.parseRequiredPredicate(
                        arguments.value(for: .predicate)
                    ),
                    timeout: expectation.timeout ?? defaultWaitTimeout
                )))
            }
        case .oneFingerTap:
            return singleStepActionContract(
                family: .spatialAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.gesturePointSelection + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Explicit spatial oneFingerTap action. Element targets dispatch at their activation point "
                    + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. "
                    + "Use activate for ordinary accessible controls."
            ) { fence, arguments in
                .oneFingerTap(try fence.decodeTapTarget(arguments))
            }
        case .longPress:
            return singleStepActionContract(
                family: .spatialAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.gesturePointSelection
                        + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Explicit spatial longPress action. Element targets dispatch at their activation point "
                    + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate."
            ) { fence, arguments in
                .longPress(try fence.decodeLongPressTarget(arguments))
            }
        case .swipe:
            return singleStepActionContract(
                family: .spatialAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.swipeIntents
                        + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Explicit spatial swipe action using exactly one typed intent: "
                    + "elementDirection, elementUnitPoints, pointToPoint, or pointDirection."
            ) { fence, arguments in
                .swipe(try fence.decodeSwipeTarget(arguments))
            }
        case .drag:
            return singleStepActionContract(
                family: .spatialAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.dragIntents
                        + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Explicit spatial drag action using exactly one typed intent: "
                    + "elementToPoint (activation point or unit start override) or pointToPoint."
            ) { fence, arguments in
                .drag(try fence.decodeDragTarget(arguments))
            }
        case .scroll:
            return directActionContract(
                family: .viewportDebug,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.target + [
                        FenceParameters.containerName.spec,
                        FenceParameters.scrollDirection.spec,
                    ] + FenceParameterBlocks.expectation
                ),
                timeout: .standardAction,
                description: "Explicit viewport/debug operation: scroll one page in the visible viewport, "
                    + "within a semantic target's owning scroll ancestor, or for direct debug requests, "
                    + "within a current containerName."
            ) { fence, arguments in
                .scroll(try fence.decodeScrollTarget(arguments))
            }
        case .scrollToVisible:
            return directActionContract(
                family: .viewportDebug,
                parameters: FenceCommandParameters(FenceParameterBlocks.target + FenceParameterBlocks.expectation),
                timeout: .standardAction,
                description: "Explicit viewport/debug operation: move the viewport until a "
                    + "semantic target is visible and report its fresh geometry."
            ) { _, arguments in
                .scrollToVisible(try arguments.requiredAccessibilityTarget(command: .scrollToVisible))
            }
        case .scrollToEdge:
            return directActionContract(
                family: .viewportDebug,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.target + [
                        FenceParameters.containerName.spec,
                        FenceParameters.scrollEdge.spec,
                    ] + FenceParameterBlocks.expectation
                ),
                timeout: .standardAction,
                description: "Explicit viewport/debug operation: scroll the visible viewport, "
                    + "a semantic target's owning scroll ancestor, or for direct debug requests, "
                    + "a current containerName, to a requested edge."
            ) { fence, arguments in
                .scrollToEdge(try fence.decodeScrollToEdgeTarget(arguments))
            }
        case .activate:
            return singleStepActionContract(
                family: .semanticAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.target
                        + [FenceParameters.actionName.spec] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Perform primary accessibility activation on a semantic UI element, "
                    + "or one of its named accessibility actions."
            ) { fence, arguments in
                try fence.decodeAccessibilityAction(arguments)
            }
        case .rotor:
            return singleStepActionContract(
                family: .semanticAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.target + [
                        FenceParameters.rotorName.spec,
                        FenceParameters.rotorIndex.spec,
                        FenceParameters.rotorDirection.spec,
                    ] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Move through an element rotor by direction. The server holds the rotor cursor "
                    + "while in rotor mode (entering at the first item); any other interaction exits rotor mode "
                    + "and drops the cursor."
            ) { fence, arguments in
                try fence.decodeRotorAction(arguments)
            }
        case .typeText:
            return singleStepActionContract(
                family: .semanticAction,
                parameters: FenceCommandParameters(
                    FenceParameterBlocks.target + [
                        FenceParameters.text.spec,
                        FenceParameters.textInputMode.spec,
                    ] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .longAction,
                description: "Type text. Replace mode clears the focused field before typing."
            ) { fence, arguments in
                try fence.decodeTypeTextAction(arguments)
            }
        case .editAction:
            return singleStepActionContract(
                family: .semanticAction,
                parameters: FenceCommandParameters(
                    [FenceParameters.editAction.spec] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Perform an edit action on the current first responder."
            ) { _, arguments in
                .editAction(EditActionTarget(
                    action: try arguments.requiredValue(FenceParameters.editAction)
                ))
            }
        case .setPasteboard:
            return singleStepActionContract(
                family: .semanticAction,
                parameters: FenceCommandParameters(
                    [FenceParameters.pasteboardText.spec] + FenceParameterBlocks.expectation
                ),
                baseTimeout: .standardAction,
                description: "Write text to the general pasteboard from within the app."
            ) { _, arguments in
                .setPasteboard(SetPasteboardTarget(
                    text: try PasteboardText(validating: arguments.requiredValue(FenceParameters.pasteboardText))
                ))
            }
        case .getPasteboard:
            return fixedResponseContract(
                family: .observation,
                timeout: .health,
                description: "Read text from the general pasteboard.",
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
            ) { _, _, timeout in
                .init { fence in try await fence.handleGetPasteboard(timeout: timeout) }
            }
        case .dismissKeyboard:
            return singleStepActionContract(
                family: .semanticAction,
                parameters: FenceCommandParameters(FenceParameterBlocks.expectation),
                baseTimeout: .standardAction,
                description: "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
            ) { _, _ in
                .dismissKeyboard
            }
        case .perform:
            return responseContract(
                family: .heistRuntime,
                parameters: [FenceParameters.performStep.spec],
                timeout: .performStep,
                description: Self.performDescription,
                cliExposure: .notExposed,
                mcpExposure: .directTool
            ) { fence, arguments in
                let request = try fence.decodePerformRequest(arguments)
                return .init { fence in try await fence.handlePerform(request) }
            }
        case .runHeist:
            return fixedResponseContract(
                family: .heistRuntime,
                parameters: FenceCommandParameters([Self.rootArgumentParameter] + Self.planSourceParameters),
                timeout: .longAction,
                description: Self.runHeistDescription,
                mcpExposure: .directTool
            ) { fence, arguments, timeout in
                let request = try fence.decodeRunHeistRequest(arguments)
                return .init { fence in try await fence.handleRunHeist(request, timeout: timeout) }
            }
        case .validateHeist:
            return responseContract(
                family: .heistRuntime,
                requiresConnectionBeforeDispatch: false,
                parameters: FenceCommandParameters([
                    Self.rootArgumentParameter,
                    FenceParameters.heistValidationLint.spec,
                ] + Self.planSourceParameters),
                description: Self.validateHeistDescription,
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { fence, arguments in
                let request = try fence.decodeValidateHeistRequest(arguments)
                return .init { fence in try fence.handleValidateHeist(request) }
            }
        case .listHeists:
            return responseContract(
                family: .heistRuntime,
                requiresConnectionBeforeDispatch: false,
                parameters: FenceCommandParameters([
                    FenceParameters.heistCatalogDetail.spec,
                ] + Self.planSourceParameters),
                description: "List the root entry and reusable heists in a plan. Use `detail: \"detailed\"` "
                    + "when composing against available capabilities.",
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { fence, arguments in
                let request = try fence.decodeListHeistsRequest(arguments)
                return .init { fence in fence.handleListHeists(request) }
            }
        case .describeHeist:
            return responseContract(
                family: .heistRuntime,
                requiresConnectionBeforeDispatch: false,
                parameters: FenceCommandParameters([FenceParameters.heistName.spec] + Self.planSourceParameters),
                description: "Describe one root entry or reusable heist from a plan so an agent can call it safely.",
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { fence, arguments in
                let request = try fence.decodeDescribeHeistRequest(arguments)
                return .init { fence in fence.handleDescribeHeist(request) }
            }
        case .getSessionState:
            return responseContract(
                family: .session,
                requiresConnectionBeforeDispatch: false,
                description: "Inspect connection, device, and last-action session state.",
                mcpExposure: .directTool,
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { _, _ in
                .init { fence in .sessionState(payload: fence.currentSessionState()) }
            }
        case .connect:
            return responseContract(
                family: .session,
                requiresConnectionBeforeDispatch: false,
                parameters: [
                    FenceParameters.connectionTarget.spec,
                    FenceParameters.device.spec,
                    FenceParameters.token.spec,
                ],
                description: "Establish or switch the active connection to an app running The Button Heist.",
                mcpExposure: .directTool
            ) { fence, arguments in
                let request = try fence.decodeConnectRequest(arguments)
                return .init { fence in try await fence.handleConnect(request) }
            }
        case .listTargets:
            return responseContract(
                family: .session,
                requiresConnectionBeforeDispatch: false,
                description: "List configured connection targets and the default target.",
                mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
            ) { _, _ in
                .init { fence in fence.handleListTargets() }
            }
        }
    }

    private static let getInterfaceDescription = """
        Read the app accessibility hierarchy, optionally scoped to a subtree.

        Build DSL targets from returned accessibility language: `.label("Pay")`,
        `.identifier("pay_button")`, `.value("Milk")`, `.element(.label("Pay"),
        .traits([.button]))`, or `.target(..., ordinal: n)` for duplicates.
        Pass `subtree` a canonical accessibility target. Element target checks use
        `{ "kind": "label|identifier|value|hint|customContent", "match": ... }`,
        `{ "kind": "traits|actions|rotors", "values": [...] }`, or
        `{ "kind": "exclude", "check": { ... } }`.
        Custom actions use `{ "custom": "Sub" }`.
        `containerName` is for inspection and viewport/debug commands only; it is
        not a semantic target or durable heist selector.
        `maxScrollsPerContainer` and `maxScrollsPerDiscovery` bound the command-owned
        interface discovery pass; omit them to use Inside Job runtime defaults.
        """
}

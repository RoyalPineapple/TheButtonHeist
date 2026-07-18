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
    public let parameters: [FenceParameterSpec]
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

struct FenceCommandProjection: Sendable, Equatable {
    let cliExposure: CLIExposure
    let mcpExposure: MCPExposure
    let mcpAnnotations: MCPToolAnnotationSpec?
    let description: String

    init(
        cliExposure: CLIExposure = .directCommand,
        mcpExposure: MCPExposure = .directTool,
        mcpAnnotations: MCPToolAnnotationSpec? = nil,
        description: String
    ) {
        self.cliExposure = cliExposure
        self.mcpExposure = mcpExposure
        self.mcpAnnotations = mcpAnnotations
        self.description = description
    }

    static func cliAndMCP(
        _ description: String,
        mcpAnnotations: MCPToolAnnotationSpec? = nil
    ) -> Self {
        Self(mcpAnnotations: mcpAnnotations, description: description)
    }

    static func cliOnly(
        _ description: String,
        mcpAnnotations: MCPToolAnnotationSpec? = nil
    ) -> Self {
        Self(mcpExposure: .notExposed, mcpAnnotations: mcpAnnotations, description: description)
    }

    static func mcpOnly(
        _ description: String,
        mcpAnnotations: MCPToolAnnotationSpec? = nil
    ) -> Self {
        Self(cliExposure: .notExposed, mcpAnnotations: mcpAnnotations, description: description)
    }
}

typealias FenceCommandAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.Command,
    TheFence.CommandArgumentEnvelope
) throws -> TheFence.DecodedRequestDispatch
typealias FenceFixedHandlerAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.CommandArgumentEnvelope,
    TimeInterval
) throws -> TheFence.DecodedRequestDispatch
typealias FenceHandlerAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.CommandArgumentEnvelope
) throws -> TheFence.DecodedRequestDispatch
typealias FenceActionAdmission = @ButtonHeistActor @Sendable (
    TheFence,
    TheFence.CommandArgumentEnvelope
) throws -> HeistActionCommand
extension TheFence {
    public enum Command: CaseIterable, Hashable, RawRepresentable, Sendable {
        case ping
        case listDevices
        case getInterface
        case getScreen
        case getAnnouncements
        case wait
        case oneFingerTap
        case longPress
        case swipe
        case drag
        case scroll
        case scrollToVisible
        case scrollToEdge
        case activate
        case rotor
        case typeText
        case editAction
        case setPasteboard
        case getPasteboard
        case dismissKeyboard
        case perform
        case runHeist
        case validateHeist
        case listHeists
        case describeHeist
        case getSessionState
        case connect
        case listTargets

        public init?(rawValue: String) {
            guard let command = Self.allCases.first(where: { $0.definition.name == rawValue }) else {
                return nil
            }
            self = command
        }

        public var rawValue: String {
            definition.name
        }
    }

    enum CommandConnectionRequirement: Equatable, Sendable {
        case activeSession
        case none
    }

    struct CommandDefinition: Sendable {
        let name: String
        let family: FenceCommandFamily
        let connectionRequirement: CommandConnectionRequirement
        let parameters: [FenceParameterSpec]
        let timeout: FenceCommandTimeoutSemantics
        let projection: FenceCommandProjection
        let admission: FenceCommandAdmission

        func descriptor(for command: Command) -> FenceCommandDescriptor {
            FenceCommandDescriptor(
                command: command,
                family: family,
                requiresConnectionBeforeDispatch: connectionRequirement == .activeSession,
                parameters: parameters,
                timeout: timeout,
                cliExposure: projection.cliExposure,
                mcpExposure: projection.mcpExposure,
                mcpAnnotations: projection.mcpAnnotations,
                description: projection.description
            )
        }

        static func handler(
            name: String,
            family: FenceCommandFamily,
            connectionRequirement: CommandConnectionRequirement = .activeSession,
            parameters: [FenceParameterSpec] = [],
            timeout: FenceCommandTimeoutSemantics = .none,
            projection: FenceCommandProjection,
            admission: @escaping FenceHandlerAdmission
        ) -> Self {
            Self(
                name: name,
                family: family,
                connectionRequirement: connectionRequirement,
                parameters: parameters,
                timeout: timeout,
                projection: projection,
                admission: { fence, _, arguments in
                    try admission(fence, arguments)
                }
            )
        }

        static func fixedHandler(
            name: String,
            family: FenceCommandFamily,
            connectionRequirement: CommandConnectionRequirement = .activeSession,
            parameters: [FenceParameterSpec] = [],
            timeout: FenceCommandFixedTimeout,
            projection: FenceCommandProjection,
            admission: @escaping FenceFixedHandlerAdmission
        ) -> Self {
            Self(
                name: name,
                family: family,
                connectionRequirement: connectionRequirement,
                parameters: parameters,
                timeout: .fixed(timeout),
                projection: projection,
                admission: { fence, _, arguments in
                    try admission(fence, arguments, timeout.seconds)
                }
            )
        }

        static func singleStepAction(
            name: String,
            family: FenceCommandFamily,
            parameters: [FenceParameterSpec],
            baseTimeout: FenceCommandFixedTimeout,
            projection: FenceCommandProjection,
            admission: @escaping FenceActionAdmission
        ) -> Self {
            Self(
                name: name,
                family: family,
                connectionRequirement: .activeSession,
                parameters: parameters,
                timeout: .singleStepAction(base: baseTimeout),
                projection: projection,
                admission: { fence, command, arguments in
                    try TheFence.appInteractionDispatch(
                        command,
                        try admission(fence, arguments),
                        actionTimeout: baseTimeout.seconds,
                        expectationPayload: try ExpectationPayload(arguments: arguments)
                    )
                }
            )
        }

        static func directAction(
            name: String,
            family: FenceCommandFamily,
            parameters: [FenceParameterSpec],
            timeout: FenceCommandFixedTimeout,
            projection: FenceCommandProjection,
            admission: @escaping FenceActionAdmission
        ) -> Self {
            Self(
                name: name,
                family: family,
                connectionRequirement: .activeSession,
                parameters: parameters,
                timeout: .fixed(timeout),
                projection: projection,
                admission: { fence, command, arguments in
                    try TheFence.directActionDispatch(
                        command,
                        try admission(fence, arguments),
                        timeout: timeout.seconds,
                        expectationPayload: try ExpectationPayload(arguments: arguments)
                    )
                }
            )
        }

    }
}

@_spi(ButtonHeistTooling) public extension TheFence.Command {
    var descriptor: FenceCommandDescriptor {
        definition.descriptor(for: self)
    }

    static var descriptors: [FenceCommandDescriptor] {
        allCases.map(\.descriptor)
    }

    static var cliDirectCommandDescriptors: [FenceCommandDescriptor] {
        descriptors.filter { $0.cliExposure == .directCommand }
    }
}

extension TheFence.Command {
    // This exhaustive switch is the canonical command definition and policy table.
    var definition: TheFence.CommandDefinition {
        switch self {
        case .ping:
            return .fixedHandler(
                name: "ping",
                family: .session,
                connectionRequirement: .none,
                timeout: .health,
                projection: .cliOnly(
                    "Check connection health without reading accessibility state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { _, _, timeout in
                .init { fence in try await fence.handlePing(timeout: timeout) }
            }
        case .listDevices:
            return .handler(
                name: "list_devices",
                family: .session,
                connectionRequirement: .none,
                projection: .cliOnly(
                    "List discovered iOS devices and configured connection targets.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { _, _ in
                .init { fence in try await fence.handleListDevices() }
            }
        case .getInterface:
            return .fixedHandler(
                name: "get_interface",
                family: .observation,
                parameters: [
                    FenceParameterBlocks.interfaceSubtree,
                    FenceParameters.interfaceDetail.spec,
                    FenceParameters.maxScrollsPerContainer.spec,
                    FenceParameters.maxScrollsPerDiscovery.spec,
                ],
                timeout: .explore,
                projection: .cliAndMCP(
                    Self.getInterfaceDescription,
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { fence, arguments, timeout in
                let request = try fence.makeGetInterfaceRequest(arguments)
                return .init { fence in try await fence.handleGetInterface(request, timeout: timeout) }
            }
        case .getScreen:
            return .fixedHandler(
                name: "get_screen",
                family: .observation,
                parameters: [
                    FenceParameters.output.spec,
                    FenceParameters.inlineData.spec,
                    FenceParameters.screenMode.spec,
                ],
                timeout: .screenCapture,
                projection: .cliAndMCP(
                    "Capture a PNG screenshot with visible interface state. Pass mode=accessibility to render accessibility markers and legend.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { fence, arguments, timeout in
                let request = try fence.makeScreenRequest(arguments)
                return .init { fence in try await fence.handleGetScreen(request, timeout: timeout) }
            }
        case .getAnnouncements:
            return .fixedHandler(
                name: "get_announcements",
                family: .observation,
                timeout: .health,
                projection: .cliAndMCP(
                    "Read recent spoken accessibility text captured from announcement, elementChanged, valueChanged, or screenChanged notifications.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { _, _, timeout in
                .init { fence in try await fence.handleGetAnnouncements(timeout: timeout) }
            }
        case .wait:
            return .init(
                name: "wait",
                family: .assertion,
                connectionRequirement: .activeSession,
                parameters: FenceParameterBlocks.wait,
                timeout: .wait,
                projection: .cliOnly(
                    "Assert that an accessibility predicate is satisfied within timeout "
                        + "by evaluating settled accessibility state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
                ),
                admission: { _, _, arguments in
                    let expectation = try TheFence.ExpectationPayload(arguments: arguments)
                    return .singleStepHeist(.wait(WaitStep(
                        predicate: try TheFence.ExpectationPayload.parseRequiredPredicate(
                            arguments.value(for: .predicate)
                        ),
                        timeout: expectation.timeout ?? defaultWaitTimeout
                    )))
                }
            )
        case .oneFingerTap:
            return .singleStepAction(
                name: "one_finger_tap",
                family: .spatialAction,
                parameters: FenceParameterBlocks.gesturePointSelection + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Explicit mechanical/spatial tap. Element targets dispatch at their activation point "
                        + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate. "
                        + "ordinary accessible controls should use the semantic command path."
                )
            ) { fence, arguments in
                .mechanicalTap(try fence.decodeTapTarget(arguments))
            }
        case .longPress:
            return .singleStepAction(
                name: "long_press",
                family: .spatialAction,
                parameters: FenceParameterBlocks.gesturePointSelection
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Explicit mechanical/spatial long press. Element targets dispatch at their activation point "
                        + "unless unitPoint supplies an element-frame override; point supplies a raw screen coordinate."
                )
            ) { fence, arguments in
                .mechanicalLongPress(try fence.decodeLongPressTarget(arguments))
            }
        case .swipe:
            return .singleStepAction(
                name: "swipe",
                family: .spatialAction,
                parameters: FenceParameterBlocks.swipeIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Explicit mechanical/spatial swipe using exactly one typed intent: "
                        + "elementDirection, elementUnitPoints, pointToPoint, or pointDirection."
                )
            ) { fence, arguments in
                .mechanicalSwipe(try fence.decodeSwipeTarget(arguments))
            }
        case .drag:
            return .singleStepAction(
                name: "drag",
                family: .spatialAction,
                parameters: FenceParameterBlocks.dragIntents
                    + [FenceParameterBlocks.gestureDuration] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Explicit mechanical/spatial drag using exactly one typed intent: "
                        + "elementToPoint (activation point or unit start override) or pointToPoint."
                )
            ) { fence, arguments in
                .mechanicalDrag(try fence.decodeDragTarget(arguments))
            }
        case .scroll:
            return .directAction(
                name: "scroll",
                family: .viewportDebug,
                parameters: FenceParameterBlocks.target + [
                    FenceParameters.containerName.spec,
                    FenceParameters.scrollDirection.spec,
                ] + FenceParameterBlocks.expectation,
                timeout: .standardAction,
                projection: .cliOnly(
                    "Explicit viewport/debug operation: scroll one page in the visible viewport, "
                        + "within a semantic target's owning scroll ancestor, or for direct debug requests, "
                        + "within a current containerName."
                )
            ) { fence, arguments in
                .viewportScroll(try fence.decodeScrollTarget(arguments))
            }
        case .scrollToVisible:
            return .directAction(
                name: "scroll_to_visible",
                family: .viewportDebug,
                parameters: FenceParameterBlocks.target + FenceParameterBlocks.expectation,
                timeout: .standardAction,
                projection: .cliOnly(
                    "Explicit viewport/debug operation: move the viewport until a "
                        + "semantic target is visible and report its fresh geometry."
                )
            ) { _, arguments in
                .viewportScrollToVisible(try arguments.requiredAccessibilityTarget(command: .scrollToVisible))
            }
        case .scrollToEdge:
            return .directAction(
                name: "scroll_to_edge",
                family: .viewportDebug,
                parameters: FenceParameterBlocks.target + [
                    FenceParameters.containerName.spec,
                    FenceParameters.scrollEdge.spec,
                ] + FenceParameterBlocks.expectation,
                timeout: .standardAction,
                projection: .cliOnly(
                    "Explicit viewport/debug operation: scroll the visible viewport, "
                        + "a semantic target's owning scroll ancestor, or for direct debug requests, "
                        + "a current containerName, to a requested edge."
                )
            ) { fence, arguments in
                .viewportScrollToEdge(try fence.decodeScrollToEdgeTarget(arguments))
            }
        case .activate:
            return .singleStepAction(
                name: "activate",
                family: .semanticAction,
                parameters: FenceParameterBlocks.target
                    + [FenceParameters.actionName.spec] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Perform primary accessibility activation on a semantic UI element, "
                        + "or one of its named accessibility actions."
                )
            ) { fence, arguments in
                try fence.decodeAccessibilityAction(arguments)
            }
        case .rotor:
            return .singleStepAction(
                name: "rotor",
                family: .semanticAction,
                parameters: FenceParameterBlocks.target + [
                    FenceParameters.rotorName.spec,
                    FenceParameters.rotorIndex.spec,
                    FenceParameters.rotorDirection.spec,
                ] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Move through an element rotor by direction. The server holds the rotor cursor "
                        + "while in rotor mode (entering at the first item); any other interaction exits rotor mode "
                        + "and drops the cursor."
                )
            ) { fence, arguments in
                try fence.decodeRotorAction(arguments)
            }
        case .typeText:
            return .singleStepAction(
                name: "type_text",
                family: .semanticAction,
                parameters: FenceParameterBlocks.target + [
                    FenceParameters.text.spec,
                    FenceParameters.textInputMode.spec,
                ] + FenceParameterBlocks.expectation,
                baseTimeout: .longAction,
                projection: .cliOnly("Type text. Replace mode clears the focused field before typing.")
            ) { fence, arguments in
                try fence.decodeTypeTextAction(arguments)
            }
        case .editAction:
            return .singleStepAction(
                name: "edit_action",
                family: .semanticAction,
                parameters: [FenceParameters.editAction.spec] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly("Perform an edit action on the current first responder.")
            ) { _, arguments in
                .editAction(EditActionTarget(
                    action: try arguments.requiredValue(FenceParameters.editAction)
                ))
            }
        case .setPasteboard:
            return .singleStepAction(
                name: "set_pasteboard",
                family: .semanticAction,
                parameters: [FenceParameters.pasteboardText.spec] + FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly("Write text to the general pasteboard from within the app.")
            ) { _, arguments in
                .setPasteboard(SetPasteboardTarget(
                    text: try PasteboardText(validating: arguments.requiredValue(FenceParameters.pasteboardText))
                ))
            }
        case .getPasteboard:
            return .fixedHandler(
                name: "get_pasteboard",
                family: .observation,
                timeout: .health,
                projection: .cliAndMCP(
                    "Read text from the general pasteboard.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true)
                )
            ) { _, _, timeout in
                .init { fence in try await fence.handleGetPasteboard(timeout: timeout) }
            }
        case .dismissKeyboard:
            return .singleStepAction(
                name: "dismiss_keyboard",
                family: .semanticAction,
                parameters: FenceParameterBlocks.expectation,
                baseTimeout: .standardAction,
                projection: .cliOnly(
                    "Dismiss the on-screen keyboard through the current first responder or keyboard action path."
                )
            ) { _, _ in
                .dismissKeyboard
            }
        case .perform:
            return .handler(
                name: "perform",
                family: .heistRuntime,
                parameters: [FenceParameters.performStep.spec],
                timeout: .performStep,
                projection: .mcpOnly(Self.performDescription)
            ) { fence, arguments in
                let request = try fence.decodePerformRequest(arguments)
                return .init { fence in try await fence.handlePerform(request) }
            }
        case .runHeist:
            return .fixedHandler(
                name: "run_heist",
                family: .heistRuntime,
                parameters: [Self.rootArgumentParameter] + Self.planSourceParameters,
                timeout: .longAction,
                projection: .cliAndMCP(Self.runHeistDescription)
            ) { fence, arguments, timeout in
                let request = try fence.decodeRunHeistRequest(arguments)
                return .init { fence in try await fence.handleRunHeist(request, timeout: timeout) }
            }
        case .validateHeist:
            return .handler(
                name: "validate_heist",
                family: .heistRuntime,
                connectionRequirement: .none,
                parameters: [
                    Self.rootArgumentParameter,
                    FenceParameters.heistValidationLint.spec,
                ] + Self.planSourceParameters,
                projection: .cliAndMCP(
                    Self.validateHeistDescription,
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { fence, arguments in
                let request = try fence.decodeValidateHeistRequest(arguments)
                return .init { fence in try fence.handleValidateHeist(request) }
            }
        case .listHeists:
            return .handler(
                name: "list_heists",
                family: .heistRuntime,
                connectionRequirement: .none,
                parameters: [
                    FenceParameters.heistCatalogDetail.spec,
                ] + Self.planSourceParameters,
                projection: .cliAndMCP(
                    "List the root entry and reusable heists in a plan. Use `detail: \"detailed\"` "
                        + "when composing against available capabilities.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { fence, arguments in
                let request = try fence.decodeListHeistsRequest(arguments)
                return .init { fence in fence.handleListHeists(request) }
            }
        case .describeHeist:
            return .handler(
                name: "describe_heist",
                family: .heistRuntime,
                connectionRequirement: .none,
                parameters: [FenceParameters.heistName.spec] + Self.planSourceParameters,
                projection: .cliAndMCP(
                    "Describe one root entry or reusable heist from a plan so an agent can call it safely.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { fence, arguments in
                let request = try fence.decodeDescribeHeistRequest(arguments)
                return .init { fence in fence.handleDescribeHeist(request) }
            }
        case .getSessionState:
            return .handler(
                name: "get_session_state",
                family: .session,
                connectionRequirement: .none,
                projection: .cliAndMCP(
                    "Inspect connection, device, and last-action session state.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
            ) { _, _ in
                .init { fence in .sessionState(payload: fence.currentSessionState()) }
            }
        case .connect:
            return .handler(
                name: "connect",
                family: .session,
                connectionRequirement: .none,
                parameters: [
                    FenceParameters.connectionTarget.spec,
                    FenceParameters.device.spec,
                    FenceParameters.token.spec,
                ],
                projection: .cliAndMCP("Establish or switch the active connection to an app running The Button Heist.")
            ) { fence, arguments in
                let request = try fence.decodeConnectRequest(arguments)
                return .init { fence in try await fence.handleConnect(request) }
            }
        case .listTargets:
            return .handler(
                name: "list_targets",
                family: .session,
                connectionRequirement: .none,
                projection: .cliOnly(
                    "List configured connection targets and the default target.",
                    mcpAnnotations: MCPToolAnnotationSpec(readOnlyHint: true, idempotentHint: true)
                )
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

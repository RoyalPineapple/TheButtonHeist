import XCTest
import ThePlans
@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class WireCommandParityTests: XCTestCase {

    func testDescriptorsCoverEveryCommandExactlyOnce() {
        let descriptors = TheFence.Command.descriptors
        let descriptorCommands = descriptors.map(\.command)

        XCTAssertEqual(descriptorCommands.count, TheFence.Command.allCases.count)
        XCTAssertEqual(Set(descriptorCommands), Set(TheFence.Command.allCases))
        XCTAssertEqual(descriptorCommands.count, Set(descriptorCommands).count)
    }

    func testCommandFamilyMembership() {
        XCTAssertEqual(TheFence.Command.ping.descriptor.family, .session)
        XCTAssertEqual(TheFence.Command.getInterface.descriptor.family, .observation)
        XCTAssertEqual(TheFence.Command.wait.descriptor.family, .assertion)
        XCTAssertEqual(TheFence.Command.activate.descriptor.family, .semanticAction)
        XCTAssertEqual(TheFence.Command.oneFingerTap.descriptor.family, .spatialAction)
        XCTAssertEqual(TheFence.Command.scroll.descriptor.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.scrollToVisible.descriptor.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.scrollToEdge.descriptor.family, .viewportDebug)
        XCTAssertEqual(TheFence.Command.perform.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.runHeist.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.validateHeist.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.listHeists.descriptor.family, .heistRuntime)
        XCTAssertEqual(TheFence.Command.describeHeist.descriptor.family, .heistRuntime)

        XCTAssertEqual(TheFence.Command.wait.descriptor.command, .wait)
        XCTAssertEqual(TheFence.Command.wait.descriptor.family, .assertion)
    }

    func testDescriptorBackedCLIHelpDisplaysFamilyGrouping() {
        let help = TheFence.Command.cliJSONLinesHelp

        XCTAssertTrue(help.contains("wait"), help)
        XCTAssertTrue(help.contains("[assertion]"), help)
        XCTAssertTrue(help.contains("scroll"), help)
        XCTAssertTrue(help.contains("[viewportDebug]"), help)
        XCTAssertFalse(help.contains("Recordable"), help)
        XCTAssertFalse(help.contains("Durable"), help)
    }

    func testRunHeistDescriptorDoesNotAdvertiseRawJSONIRFields() {
        let descriptor = TheFence.Command.runHeist.descriptor
        let keys = Set(descriptor.parameters.map(\.key))

        XCTAssertTrue(keys.contains("path"))
        XCTAssertTrue(keys.contains("plan"))
        XCTAssertTrue(keys.contains("argument"))
        XCTAssertFalse(keys.contains("version"))
        XCTAssertFalse(keys.contains("name"))
        XCTAssertFalse(keys.contains("parameter"))
        XCTAssertFalse(keys.contains("definitions"))
        XCTAssertFalse(keys.contains("body"))
    }

    func testValidateHeistDescriptorIsOfflineAndUsesCanonicalPlanSources() {
        let descriptor = TheFence.Command.validateHeist.descriptor
        let keys = Set(descriptor.parameters.map(\.key))

        XCTAssertFalse(descriptor.requiresConnectionBeforeDispatch)
        XCTAssertTrue(keys.isSuperset(of: ["path", "plan", "argument", "lint"]))
        XCTAssertFalse(keys.contains("body"))
        XCTAssertEqual(
            descriptor.requiredDefaultValue(for: FenceParameters.heistValidationLint),
            .compositionQuality
        )
    }

    func testDescriptorLookupFindsEquivalentNestedParameters() {
        let direction = TheFence.Command.swipe.descriptor.parameter(named: .direction)

        XCTAssertEqual(direction?.enumValues, fenceEnumValues(SwipeDirection.self))
    }

    func testDescriptorDefaultsOwnCommandDefaultValues() {
        XCTAssertEqual(
            TheFence.Command.scroll.descriptor.requiredDefaultValue(for: FenceParameters.scrollDirection),
            .down
        )
        XCTAssertEqual(
            TheFence.Command.scrollToEdge.descriptor.requiredDefaultValue(for: FenceParameters.scrollEdge),
            .top
        )
        XCTAssertEqual(
            TheFence.Command.rotor.descriptor.requiredDefaultValue(for: FenceParameters.rotorDirection),
            .next
        )
        XCTAssertEqual(
            TheFence.Command.listHeists.descriptor.requiredDefaultValue(for: FenceParameters.heistCatalogDetail),
            .summary
        )
    }

    func testDescriptorTimeoutSemanticsOwnCommandTimeouts() {
        XCTAssertEqual(TheFence.Command.ping.descriptor.timeout, .fixed(.health))
        XCTAssertEqual(TheFence.Command.getInterface.descriptor.timeout, .fixed(.explore))
        XCTAssertEqual(TheFence.Command.getScreen.descriptor.timeout, .fixed(.screenCapture))
        XCTAssertEqual(TheFence.Command.runHeist.descriptor.timeout, .fixed(.longAction))
        XCTAssertEqual(TheFence.Command.wait.descriptor.timeout, .wait)
        XCTAssertEqual(TheFence.Command.activate.descriptor.timeout, .singleStepAction(base: .standardAction))
        XCTAssertEqual(TheFence.Command.typeText.descriptor.timeout, .singleStepAction(base: .longAction))
        XCTAssertEqual(TheFence.Command.perform.descriptor.timeout, .performStep)
    }

    @ButtonHeistActor
    func testTransientSingleStepDirectActionsUseDescriptorDispatchTimeout() async throws {
        let (fence, _) = makeConnectedFence()
        let request = try fence.parseRequest(command: .rotor, values: [
            "target": targetArgumentValue(identifier: "target"),
            "rotorIndex": .int(0),
        ])

        guard case .directAction(let directAction) = request.dispatch else {
            return XCTFail("Indexed rotor should decode as transient direct action")
        }
        XCTAssertEqual(directAction.command, .rotor)
        XCTAssertNotNil(directAction.action.durableHeistActionFailure)
        XCTAssertEqual(
            TheFence.Command.rotor.descriptor.timeout.requiredDirectDispatchSeconds,
            FenceCommandFixedTimeout.standardAction.seconds
        )
    }

    func testCommandHelpKeepsAccessibilitySemanticAndMechanicalBoundaries() {
        let activate = TheFence.Command.activate.descriptor.description
        let tap = TheFence.Command.oneFingerTap.descriptor.description
        let scroll = TheFence.Command.scroll.descriptor.description
        let scrollToVisible = TheFence.Command.scrollToVisible.descriptor.description
        let scrollToEdge = TheFence.Command.scrollToEdge.descriptor.description

        XCTAssertTrue(activate.localizedCaseInsensitiveContains("primary accessibility activation"), activate)
        XCTAssertTrue(activate.localizedCaseInsensitiveContains("semantic UI element"), activate)
        XCTAssertFalse(activate.localizedCaseInsensitiveContains("tap"), activate)

        XCTAssertTrue(tap.localizedCaseInsensitiveContains("explicit mechanical/spatial tap"), tap)
        XCTAssertTrue(tap.localizedCaseInsensitiveContains("ordinary accessible controls should use the semantic command path"), tap)

        XCTAssertTrue(scroll.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scroll)
        XCTAssertTrue(scrollToVisible.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scrollToVisible)
        XCTAssertTrue(scrollToEdge.localizedCaseInsensitiveContains("explicit viewport/debug operation"), scrollToEdge)
    }

    @ButtonHeistActor
    func testEveryPublicCommandHasOneRuntimeAdmission() async throws {
        let (fence, _) = makeConnectedFence()

        for descriptor in TheFence.Command.descriptors where descriptor.isPublicRequestContract {
            let input = FenceCommandInput(
                command: descriptor.command,
                arguments: .init(values: sampleArguments(for: descriptor.command))
            )
            let request = try fence.admit(input)

            XCTAssertEqual(request.command, descriptor.command, descriptor.command.rawValue)
        }
    }

    @ButtonHeistActor
    func testEveryProjectedParameterMutationIsEnforcedByRuntimeAdmission() async throws {
        let (fence, _) = makeConnectedFence()

        for descriptor in TheFence.Command.descriptors where descriptor.isPublicRequestContract {
            for parameter in descriptor.parameters {
                for mutation in invalidValues(for: parameter) {
                    var arguments = sampleArguments(for: descriptor.command)
                    arguments[parameter.key] = mutation

                    XCTAssertThrowsError(
                        try fence.admit(FenceCommandInput(
                            command: descriptor.command,
                            arguments: .init(values: arguments)
                        )),
                        "\(descriptor.command.rawValue).\(parameter.key): \(mutation)"
                    )
                }
            }
        }
    }

    @ButtonHeistActor
    func testEveryRequiredProjectedParameterIsRequiredByRuntimeAdmission() async throws {
        let (fence, _) = makeConnectedFence()

        for descriptor in TheFence.Command.descriptors where descriptor.isPublicRequestContract {
            for parameter in descriptor.parameters where parameter.required {
                var arguments = sampleArguments(for: descriptor.command)
                XCTAssertNotNil(
                    arguments.removeValue(forKey: parameter.key),
                    "Missing required sample for \(descriptor.command.rawValue).\(parameter.key)"
                )

                XCTAssertThrowsError(
                    try fence.admit(FenceCommandInput(
                        command: descriptor.command,
                        arguments: .init(values: arguments)
                    )),
                    "\(descriptor.command.rawValue).\(parameter.key)"
                ) { error in
                    XCTAssertEqual(
                        (error as? SchemaValidationError)?.field,
                        parameter.key,
                        "\(descriptor.command.rawValue).\(parameter.key): \(error)"
                    )
                }
            }
        }
    }

    @ButtonHeistActor
    func testEveryPublicCommandRejectsUnknownParametersAtRuntimeAdmission() async throws {
        let (fence, _) = makeConnectedFence()
        let unknownKey = "__unknown_parameter__"

        for descriptor in TheFence.Command.descriptors where descriptor.isPublicRequestContract {
            var arguments = sampleArguments(for: descriptor.command)
            arguments[unknownKey] = .bool(true)

            XCTAssertThrowsError(
                try fence.admit(FenceCommandInput(
                    command: descriptor.command,
                    arguments: .init(values: arguments)
                )),
                descriptor.command.rawValue
            ) { error in
                XCTAssertEqual((error as? SchemaValidationError)?.field, unknownKey)
            }
        }
    }

    @ButtonHeistActor
    func testCLIAndMCPAdaptersPreserveRepresentativeAdmissionFailures() async throws {
        let (fence, _) = makeConnectedFence()
        let missingStep = try TheFence.Command.routeToolRequest(
            named: TheFence.Command.perform.rawValue,
            arguments: .init(values: [:])
        ).get()
        XCTAssertThrowsError(try fence.admit(missingStep)) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.field, FenceParameterKey.step.rawValue)
        }

        let malformedDirection = try TheFence.Command.routeCLICommandEnvelope(
            .init(values: [
                FenceParameterKey.command.rawValue: .string(TheFence.Command.scroll.rawValue),
                FenceParameterKey.direction.rawValue: .string("sideways"),
            ]),
            context: "test"
        ).get()
        XCTAssertThrowsError(try fence.admit(malformedDirection)) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.field, FenceParameterKey.direction.rawValue)
        }

        let unknownKey = "__unknown_parameter__"
        let unknownParameter = try TheFence.Command.routeCLICommandEnvelope(
            .init(values: [
                FenceParameterKey.command.rawValue: .string(TheFence.Command.ping.rawValue),
                unknownKey: .bool(true),
            ]),
            context: "test"
        ).get()
        XCTAssertThrowsError(try fence.admit(unknownParameter)) { error in
            XCTAssertEqual((error as? SchemaValidationError)?.field, unknownKey)
        }
    }

    @ButtonHeistActor
    func testEveryProjectedDefaultIsAcceptedOmittedAndExplicitly() async throws {
        let (fence, _) = makeConnectedFence()

        for descriptor in TheFence.Command.descriptors where descriptor.isPublicRequestContract {
            for parameter in descriptor.parameters {
                guard let defaultValue = parameter.defaultValue else { continue }
                var omittedArguments = sampleArguments(for: descriptor.command)
                omittedArguments.removeValue(forKey: parameter.key)
                var explicitArguments = omittedArguments
                explicitArguments[parameter.key] = defaultValue

                XCTAssertNoThrow(
                    try fence.admit(FenceCommandInput(
                        command: descriptor.command,
                        arguments: .init(values: omittedArguments)
                    )),
                    "\(descriptor.command.rawValue).\(parameter.key) omitted"
                )
                XCTAssertNoThrow(
                    try fence.admit(FenceCommandInput(
                        command: descriptor.command,
                        arguments: .init(values: explicitArguments)
                    )),
                    "\(descriptor.command.rawValue).\(parameter.key) explicit"
                )
            }
        }
    }

    @ButtonHeistActor
    func testAdmissionRejectsMissingSemanticRequirements() async throws {
        let (fence, _) = makeConnectedFence()

        XCTAssertThrowsError(try fence.admit(FenceCommandInput(
            command: .activate,
            arguments: .init(values: [:])
        ))) { error in
            XCTAssertEqual((error as? TheFence.MissingAccessibilityTarget)?.command, .activate)
        }
    }

    @ButtonHeistActor
    func testDurableExecutableSingleCommandsLowerToTheSameRuntimeActionAsSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in TheFence.Command.allCases {
            let arguments = sampleArguments(for: command)
            let singleRequest = try fence.parseRequest(command: command, values: arguments)

            switch singleRequest.dispatch {
            case .singleStepHeist(let heistRequest):
                let plan = try fence.singleStepHeistPlan(for: heistRequest)
                if case .wait(_, let wait) = heistRequest {
                    XCTAssertEqual(plan.body, [.wait(wait)], command.rawValue)
                    continue
                }

                guard case .actions(_, let actions, _) = heistRequest else {
                    XCTFail("Unknown single-step request for \(command.rawValue)")
                    continue
                }
                let singleCommands = actions.values
                let heistCommands = plan.body.flatMap(actionCommands(for:))

                XCTAssertEqual(
                    String(reflecting: heistCommands),
                    String(reflecting: singleCommands),
                    command.rawValue
                )
            case .directAction(let directAction):
                XCTAssertNotNil(directAction.action.durableHeistActionFailure, command.rawValue)
            case .handler:
                continue
            }
        }
    }

    @ButtonHeistActor
    func testViewportDebugCommandsAreCLIDirectOnlyAndDoNotRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in [TheFence.Command.scroll, .scrollToVisible, .scrollToEdge] {
            let descriptor = command.descriptor
            XCTAssertEqual(descriptor.family, .viewportDebug, command.rawValue)
            XCTAssertEqual(descriptor.cliExposure, .directCommand, command.rawValue)
            XCTAssertEqual(descriptor.mcpExposure, .notExposed, command.rawValue)

            let request = try fence.parseRequest(command: command, values: sampleArguments(for: command))
            guard case .directAction(let directAction) = request.dispatch else {
                return XCTFail("\(command.rawValue) should decode as direct action")
            }
            XCTAssertNotNil(directAction.action.durableHeistActionFailure, command.rawValue)
        }
    }

    @ButtonHeistActor
    func testDurableRuntimeActionCommandsRouteThroughSingleStepPlan() async throws {
        let (fence, _) = makeConnectedFence()

        for command in [TheFence.Command.activate, .oneFingerTap, .typeText, .setPasteboard] {
            let request = try fence.parseRequest(command: command, values: sampleArguments(for: command))
            guard case .singleStepHeist(let heistRequest) = request.dispatch,
                  case .actions(_, let actions, _) = heistRequest else {
                return XCTFail("\(command.rawValue) should decode as single-step action command")
            }
            let singleCommands = actions.values
            let plan = try fence.singleStepHeistPlan(for: heistRequest)
            let heistCommands = plan.body.flatMap(actionCommands(for:))

            XCTAssertEqual(String(reflecting: heistCommands), String(reflecting: singleCommands), command.rawValue)
        }
    }

    func testEveryPublicTypedClientMessageOwnsItsWireIdentity() throws {
        let samples = try sampleClientMessages()
        XCTAssertEqual(
            Set(samples.map(\.wireType)),
            Set(ClientWireMessageType.allCases)
        )

        for message in samples {
            XCTAssertEqual(try encodedWireType(for: message), message.wireType, "\(message)")
        }
    }

    @ButtonHeistActor
    private func sampleArguments(for command: TheFence.Command) -> [String: HeistValue] {
        let target = targetArgumentValue(identifier: "target")
        switch command {
        case .ping, .listDevices, .getInterface, .getScreen, .getPasteboard, .getAnnouncements, .getSessionState,
             .listTargets, .dismissKeyboard:
            return [:]
        case .perform:
            return ["step": .string(#"Activate(.label("Pay"))"#)]
        case .oneFingerTap:
            return ["point": .object(["x": .double(12), "y": .double(34)])]
        case .longPress:
            return ["point": .object(["x": .double(12), "y": .double(34)])]
        case .swipe:
            return [
                "elementDirection": .object([
                    "element": target,
                    "direction": .string(SwipeDirection.left.rawValue),
                ]),
            ]
        case .drag:
            return [
                "elementToPoint": .object([
                    "element": target,
                    "end": .object(["x": .double(120), "y": .double(240)]),
                ]),
            ]
        case .scroll:
            return ["direction": .string(ScrollDirection.down.rawValue)]
        case .scrollToVisible, .activate:
            return ["target": target]
        case .wait:
            return [
                "predicate": .object([
                    "type": .string("changed"),
                    "scope": .string("elements"),
                    "assertions": .array([]),
                ]),
                "timeout": .double(10),
            ]
        case .scrollToEdge:
            return ["edge": .string(ScrollEdge.bottom.rawValue)]
        case .rotor:
            return ["target": target, "rotor": .string("Headings")]
        case .typeText:
            return ["text": .string("hello")]
        case .editAction:
            return ["action": .string(EditAction.paste.rawValue)]
        case .setPasteboard:
            return ["text": .string("clipboard")]
        case .runHeist, .validateHeist, .listHeists:
            return [
                "plan": .string("""
                HeistPlan("entry") {
                    Warn("ready")
                }
                """),
            ]
        case .describeHeist:
            return [
                "heist": .string("entry"),
                "plan": .string("""
                HeistPlan("entry") {
                    Warn("ready")
                }
                """),
            ]
        case .connect:
            return ["target": .string("default")]
        }
    }

    private func invalidValues(for parameter: FenceParameterSpec) -> [HeistValue] {
        var values = [incompatibleValue(for: parameter.type)]
        if parameter.enumValues != nil {
            values.append(.string("__invalid_enum_value__"))
        }
        if let minLength = parameter.minLength {
            values.append(.string(String(repeating: "x", count: max(0, minLength - 1))))
        }
        if let minimum = parameter.minimum {
            values.append(parameter.type == .integer ? .int(Int(minimum) - 1) : .double(minimum - 1))
        }
        if let exclusiveMinimum = parameter.exclusiveMinimum {
            values.append(.double(exclusiveMinimum))
        }
        if let maximum = parameter.maximum {
            values.append(parameter.type == .integer ? .int(Int(maximum) + 1) : .double(maximum + 1))
        }
        if let minItems = parameter.minItems {
            values.append(.array(Array(repeating: .string("item"), count: max(0, minItems - 1))))
        }
        if let maxItems = parameter.maxItems {
            values.append(.array(Array(repeating: .string("item"), count: maxItems + 1)))
        }
        return values
    }

    private func incompatibleValue(for type: FenceParameterSpec.ParamType) -> HeistValue {
        switch type {
        case .string:
            .object([:])
        case .integer, .number, .boolean:
            .string("wrong type")
        case .stringArray, .array:
            .object([:])
        case .stringMatch, .object:
            .string("wrong type")
        }
    }

    private func sampleClientMessages() throws -> [ClientMessage] {
        return [
            .clientHello,
            .authenticate(AuthenticatePayload(token: "token")),
            .requestInterface(InterfaceQuery()),
            .ping,
            .status,
            .getPasteboard,
            .getAnnouncements,
            .requestScreen(),
            .runtimeAction(.viewportScroll(ScrollTarget(direction: .down))),
            .heistPlan(HeistPlanRun(plan: try HeistPlan(body: [
                .action(ActionStep(command: .activate(.identifier("target")))),
            ]))),
        ]
    }

    private func encodedWireType(for message: ClientMessage) throws -> ClientWireMessageType {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(EncodedClientType.self, from: data).type
    }

    private func heistStepValue(type: String, payload: [String: HeistValue]) -> HeistValue {
        .object([
            "type": .string(type),
            type: .object(payload),
        ])
    }

    private func actionCommands(for step: HeistStep) -> [HeistActionCommand] {
        switch step {
        case .action(let action):
            return [action.command]
        case .wait, .conditional, .forEachElement, .forEachString, .repeatUntil, .warn, .fail, .heist, .invoke:
            return []
        }
    }
}

private struct EncodedClientType: Decodable {
    let type: ClientWireMessageType
}

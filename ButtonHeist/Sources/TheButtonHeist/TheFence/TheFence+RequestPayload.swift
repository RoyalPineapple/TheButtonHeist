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

    typealias ResponseOperation = @ButtonHeistActor @Sendable (TheFence) async throws -> FenceResponse

    struct DurableHeistActionCommand: Sendable {
        let action: HeistActionCommand

        init?(_ action: HeistActionCommand) {
            guard action.durableHeistActionFailure == nil else { return nil }
            self.action = action
        }
    }

    enum SingleStepHeistExecution: Sendable {
        case action(
            DurableHeistActionCommand,
            expectation: ExpectationPayload,
            actionTimeout: TimeInterval
        )
        case wait(WaitStep)
    }

    struct DirectActionExecution: Sendable {
        let action: HeistActionCommand
        let timeout: TimeInterval

        init?(_ action: HeistActionCommand, timeout: TimeInterval) {
            guard action.durableHeistActionFailure != nil else { return nil }
            self.action = action
            self.timeout = timeout
        }
    }

    enum CommandExecution: Sendable {
        case singleStepHeist(SingleStepHeistExecution)
        case directAction(DirectActionExecution)
        case response(ResponseOperation)

        init(response: @escaping ResponseOperation) {
            self = .response(response)
        }
    }

    private static func validateBoundaryShape(
        command: Command,
        arguments: CommandArgumentEnvelope
    ) throws {
        let descriptor = command.descriptor
        guard descriptor.isPublicRequestContract else {
            throw SchemaValidationError(
                field: "command",
                observed: "string \"\(command.rawValue)\"",
                expected: "public command for The Button Heist"
            )
        }
        let allowedKeys = descriptor.topLevelParameterKeys
        if let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) {
            throw SchemaValidationError(
                field: arguments.field(forUnknownKey: unexpectedKey),
                observed: arguments.observedDescription(forUnknownKey: unexpectedKey) ?? "missing",
                expected: "valid \(command.rawValue) parameter"
            )
        }
        for parameter in descriptor.parameters {
            guard let value = arguments.values[parameter.key] else {
                guard parameter.required else { continue }
                throw SchemaValidationError(
                    field: arguments.field(forUnknownKey: parameter.key),
                    observed: "missing",
                    expected: parameter.expectedTypeDescription
                )
            }
            try parameter.validatePayload(
                value,
                field: arguments.field(forUnknownKey: parameter.key)
            )
        }
    }

    func decodeScrollTarget(_ arguments: CommandArgumentEnvelope) throws -> ScrollTarget {
        ScrollTarget(
            selection: try arguments.scrollContainerSelection(),
            direction: try arguments.value(
                FenceParameters.scrollDirection,
                defaultFrom: Command.scroll.descriptor
            )
        )
    }

    func decodeScrollToEdgeTarget(_ arguments: CommandArgumentEnvelope) throws -> ScrollToEdgeTarget {
        ScrollToEdgeTarget(
            selection: try arguments.scrollContainerSelection(),
            edge: try arguments.value(
                FenceParameters.scrollEdge,
                defaultFrom: Command.scrollToEdge.descriptor
            )
        )
    }

    func decodeAccessibilityAction(_ arguments: CommandArgumentEnvelope) throws -> HeistActionCommand {
        try Self.accessibilityActionCommand(
            target: arguments.requiredAccessibilityTarget(command: .activate),
            actionName: arguments.value(FenceParameters.actionName)
        )
    }

    func decodeRotorAction(_ arguments: CommandArgumentEnvelope) throws -> HeistActionCommand {
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
            .named(try RotorName(validating: rotor))
        } else if let rotorIndex {
            .index(rotorIndex)
        } else {
            .automatic
        }
        return .rotor(
            selection: selection,
            target: try arguments.requiredAccessibilityTarget(command: .rotor),
            direction: try arguments.value(
                FenceParameters.rotorDirection,
                defaultFrom: Command.rotor.descriptor
            )
        )
    }

    func decodeTypeTextAction(_ arguments: CommandArgumentEnvelope) throws -> HeistActionCommand {
        let mode = try arguments.value(
            FenceParameters.textInputMode,
            defaultFrom: Command.typeText.descriptor
        )
        let text = try arguments.requiredValue(FenceParameters.text)
        let input: TextInputText
        do {
            input = try TextInputText(validating: text, mode: mode)
        } catch TextInputTextError.emptyAppend {
            throw SchemaValidationError(
                field: arguments.field(.text),
                observed: "string \"\(text)\"",
                expected: "non-empty string"
            )
        }
        return .typeText(
            text: input,
            target: try arguments.decodedAccessibilityTarget().map {
                try $0.validatedElementTarget(command: .typeText)
            }
        )
    }

    static func directActionExecution(
        _ command: Command,
        _ action: HeistActionCommand,
        timeout: TimeInterval,
        expectationPayload: ExpectationPayload
    ) throws -> CommandExecution {
        guard expectationPayload.expectation == nil else {
            throw FenceError.invalidRequest(
                "command \"\(command.rawValue)\" direct dispatch does not support expect"
            )
        }
        guard let execution = DirectActionExecution(action, timeout: timeout) else {
            preconditionFailure("\(command.rawValue) contract classified a durable action as direct execution")
        }
        return .directAction(execution)
    }

    static func appInteractionExecution(
        _ command: Command,
        _ action: HeistActionCommand,
        actionTimeout: TimeInterval,
        expectationPayload: ExpectationPayload
    ) throws -> CommandExecution {
        if let durableAction = DurableHeistActionCommand(action) {
            return .singleStepHeist(.action(
                durableAction,
                expectation: expectationPayload,
                actionTimeout: actionTimeout
            ))
        }
        return try directActionExecution(
            command,
            action,
            timeout: actionTimeout,
            expectationPayload: expectationPayload
        )
    }

    /// Admit a routed public command input into TheFence's typed runtime.
    @_spi(ButtonHeistTooling) public func admit(_ input: FenceCommandInput) throws -> AdmittedFenceCommand {
        try Self.validateBoundaryShape(command: input.command, arguments: input.arguments)
        return AdmittedFenceCommand(
            command: input.command,
            execution: try input.command.contract.admission(self, input.command, input.arguments)
        )
    }
}

import Foundation
import ThePlans

import TheScore

extension TheFence {

    typealias RequestDecoder = @ButtonHeistActor @Sendable (
        TheFence,
        CommandArgumentEnvelope,
        String,
        ExpectationPayload
    ) throws -> DecodedRequestDispatch

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

    struct ParsedRequest: Sendable {
        let command: Command
        let requestId: String
        let dispatch: DecodedRequestDispatch
        let expectationPayload: ExpectationPayload

        init(
            command: Command,
            requestId: String,
            dispatch: DecodedRequestDispatch,
            expectationPayload: ExpectationPayload
        ) {
            self.command = command
            self.requestId = requestId
            self.dispatch = dispatch
            self.expectationPayload = expectationPayload
        }

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

    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        try FenceCommandInput(command: command, arguments: arguments).validatePublicContract()
        let requestId = arguments.string(.requestId) ?? UUID().uuidString
        let expectationPayload = try ExpectationPayload(arguments: arguments)
        let dispatch = try command.descriptor.requestDecoder(self, arguments, requestId, expectationPayload)

        return ParsedRequest(
            command: command,
            requestId: requestId,
            dispatch: dispatch,
            expectationPayload: expectationPayload
        )
    }

}

extension FenceCommandDescriptor {
    func validatePublicRequestArguments(_ arguments: TheFence.CommandArgumentEnvelope) throws {
        for parameter in parameters {
            guard let value = arguments.value(forRawKey: parameter.key) else { continue }
            try validate(parameter, value: value, field: parameter.key)
        }
        for parameter in parameters where arguments.value(forRawKey: parameter.key) == nil {
            try validate(parameter, value: nil, field: parameter.key)
        }
    }

    func validate(_ parameter: FenceParameterSpec, value: HeistValue?, field: String) throws {
        guard let value else {
            guard parameter.required else { return }
            throw SchemaValidationError(field: field, observed: "missing", expected: parameter.expectedTypeDescription)
        }

        guard !ownsCustomPayloadValidation(for: parameter) else {
            return
        }

        try validateSchema(parameter.schema, value: value, field: field)
    }

    func ownsCustomPayloadValidation(for parameter: FenceParameterSpec) -> Bool {
        parameter.usesCustomPayloadValidation || ownsRunHeistArgumentPayloadValidation(for: parameter)
    }

    private func ownsRunHeistArgumentPayloadValidation(for parameter: FenceParameterSpec) -> Bool {
        command == .runHeist && parameter.key == FenceParameterKey.argument.rawValue
    }

    func validateSchema(
        _ schema: FenceParameterSchema,
        value: HeistValue,
        field: String
    ) throws {
        guard schema != .unconstrained else { return }
        try validateType(schema.type, value: value, field: field)

        switch schema {
        case .unconstrained:
            return
        case .scalar(let scalar):
            try validateEnum(scalar, value: value, field: field)
            try validateScalarBounds(scalar, value: value, field: field)
        case .object(let objectSpec):
            guard case .object(let object) = value else { return }
            try validateObject(object, spec: objectSpec, field: field)
        case .array(let arraySpec):
            guard case .array(let array) = value else { return }
            try validateArrayBounds(arraySpec, value: value, field: field)
            try validateArrayItems(array, spec: arraySpec, field: field)
        }
    }

    func validateObject(
        _ object: [String: HeistValue],
        spec: FenceParameterObjectSpec,
        field: String
    ) throws {
        guard let properties = spec.properties else { return }

        for child in properties {
            guard let value = object[child.key] else { continue }
            try validate(child, value: value, field: "\(field).\(child.key)")
        }
        for child in properties where object[child.key] == nil {
            try validate(child, value: nil, field: "\(field).\(child.key)")
        }

        guard spec.additionalProperties != true else { return }
        let knownKeys = Set(properties.map(\.key))
        guard let unknownKey = object.keys.sorted().first(where: { !knownKeys.contains($0) }) else {
            return
        }
        let unknownField = "\(field).\(unknownKey)"
        throw SchemaValidationError(
            field: unknownField,
            observed: object[unknownKey]?.schemaObservedDescription ?? "missing",
            expected: "valid \(field) property"
        )
    }

    func validateArrayItems(
        _ array: [HeistValue],
        spec: FenceParameterArraySpec,
        field: String
    ) throws {
        guard let itemSchema = spec.items else { return }
        for (index, item) in array.enumerated() {
            let itemField = "\(field)[\(index)]"
            try validateSchema(itemSchema, value: item, field: itemField)
        }
    }

    func validateType(
        _ type: FenceParameterSpec.ParamType,
        value: HeistValue,
        field: String
    ) throws {
        let isValid: Bool
        switch type {
        case .string:
            if case .string = value { isValid = true } else { isValid = false }
        case .integer:
            isValid = value.integerValue != nil
        case .number:
            isValid = value.numberValue != nil
        case .boolean:
            if case .bool = value { isValid = true } else { isValid = false }
        case .stringArray, .array:
            if case .array = value { isValid = true } else { isValid = false }
        case .object:
            if case .object = value { isValid = true } else { isValid = false }
        case .stringMatch:
            isValid = true
        }
        guard isValid else {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: type.expectedDescription
            )
        }
    }

    func validateEnum(
        _ scalar: FenceParameterScalarSpec,
        value: HeistValue,
        field: String
    ) throws {
        guard let enumValues = scalar.constraints.enumValues,
              case .string(let string) = value,
              !enumValues.contains(string) else {
            return
        }
        throw SchemaValidationError(
            field: field,
            observed: value.schemaObservedDescription,
            expected: SchemaValidationError.expectedEnumValues(enumValues)
        )
    }

    func validateScalarBounds(
        _ scalar: FenceParameterScalarSpec,
        value: HeistValue,
        field: String
    ) throws {
        switch scalar.kind.type {
        case .integer:
            guard let integer = value.integerValue else { return }
            try validateNumberBounds(
                Double(integer),
                type: .integer,
                constraints: scalar.constraints,
                value: value,
                field: field
            )
        case .number:
            guard let number = value.numberValue else { return }
            try validateNumberBounds(
                number,
                type: .number,
                constraints: scalar.constraints,
                value: value,
                field: field
            )
        case .string:
            guard let minLength = scalar.constraints.minLength,
                  case .string(let string) = value,
                  string.count < minLength else {
                return
            }
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: minLength == 1 ? "non-empty string" : "string with length >= \(minLength)"
            )
        default:
            break
        }
    }

    func validateArrayBounds(
        _ spec: FenceParameterArraySpec,
        value: HeistValue,
        field: String
    ) throws {
        guard case .array(let array) = value else { return }
        if let minItems = spec.constraints.minItems, array.count < minItems {
            throw SchemaValidationError(
                field: field,
                observed: "array count \(array.count)",
                expected: "array with at least \(minItems) items"
            )
        }
        if let maxItems = spec.constraints.maxItems, array.count > maxItems {
            throw SchemaValidationError(
                field: field,
                observed: "array count \(array.count)",
                expected: "array with at most \(maxItems) items"
            )
        }
    }

    func validateNumberBounds(
        _ number: Double,
        type: FenceParameterSpec.ParamType,
        constraints: FenceParameterScalarConstraints,
        value: HeistValue,
        field: String
    ) throws {
        if let exclusiveMinimum = constraints.exclusiveMinimum, number <= exclusiveMinimum {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "\(numericTypeDescription(type)) > \(formatConstraintNumber(exclusiveMinimum))"
            )
        }
        if let minimum = constraints.minimum, number < minimum {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: numericLowerBoundDescription(type: type, constraints: constraints)
            )
        }
        if let maximum = constraints.maximum, number > maximum {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: numericUpperBoundDescription(type: type, constraints: constraints)
            )
        }
    }

    func numericTypeDescription(_ type: FenceParameterSpec.ParamType) -> String {
        type == .integer ? "integer" : "number"
    }

    func numericLowerBoundDescription(
        type: FenceParameterSpec.ParamType,
        constraints: FenceParameterScalarConstraints
    ) -> String {
        let numericType = numericTypeDescription(type)
        guard let minimum = constraints.minimum else { return numericType }
        if let maximum = constraints.maximum {
            return "\(numericType) between \(formatConstraintNumber(minimum)) and \(formatConstraintNumber(maximum))"
        }
        return "\(numericType) >= \(formatConstraintNumber(minimum))"
    }

    func numericUpperBoundDescription(
        type: FenceParameterSpec.ParamType,
        constraints: FenceParameterScalarConstraints
    ) -> String {
        let numericType = numericTypeDescription(type)
        guard let maximum = constraints.maximum else { return numericType }
        if let exclusiveMinimum = constraints.exclusiveMinimum {
            return "\(numericType) in \(formatConstraintNumber(exclusiveMinimum))...\(formatUpperConstraintNumber(maximum, type: type))"
        }
        if let minimum = constraints.minimum {
            return "\(numericType) between \(formatConstraintNumber(minimum)) and \(formatUpperConstraintNumber(maximum, type: type))"
        }
        return "\(numericType) <= \(formatUpperConstraintNumber(maximum, type: type))"
    }

    func formatUpperConstraintNumber(_ value: Double, type: FenceParameterSpec.ParamType) -> String {
        if type == .number, value != 0, value.rounded(.towardZero) == value {
            return String(format: "%.1f", value)
        }
        return formatConstraintNumber(value)
    }

    func formatConstraintNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}

private extension FenceParameterSpec {
    var expectedTypeDescription: String {
        if let enumValues {
            return SchemaValidationError.expectedEnumValues(enumValues)
        }
        return type.expectedDescription
    }
}

private extension FenceParameterSpec.ParamType {
    var expectedDescription: String {
        switch self {
        case .string:
            return "string"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        case .stringArray:
            return "array of strings"
        case .stringMatch:
            return "StringMatch object with mode and optional value"
        case .object:
            return "object"
        case .array:
            return "array"
        }
    }
}

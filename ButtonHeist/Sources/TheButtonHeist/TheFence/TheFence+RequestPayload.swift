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

    struct MissingElementTarget: Error {
        let command: String
    }

    typealias ParsedRequestHandler = @ButtonHeistActor (TheFence, ParsedRequest) async throws -> FenceResponse

    struct NonEmptyHeistActionCommands {
        let first: HeistActionCommand
        private let additional: [HeistActionCommand]

        init(_ first: HeistActionCommand, additional: [HeistActionCommand] = []) {
            self.first = first
            self.additional = additional
        }

        var count: Int {
            1 + additional.count
        }

        var values: [HeistActionCommand] {
            [first] + additional
        }
    }

    enum ExecutableRequest {
        case actions(NonEmptyHeistActionCommands)
        case wait(WaitStep)
    }

    enum DecodedRequestDispatch {
        case executable(ExecutableRequest)
        case handler(ParsedRequestHandler)

        init(handler: @escaping ParsedRequestHandler) {
            self = .handler(handler)
        }

        var executableRequest: ExecutableRequest? {
            guard case .executable(let request) = self else { return nil }
            return request
        }

        var handler: ParsedRequestHandler {
            switch self {
            case .executable:
                return { fence, request in
                    try await fence.handleClientActionRequest(request)
                }
            case .handler(let handler):
                return handler
            }
        }
    }

    struct ParsedRequest {
        let command: Command
        let requestId: String
        let arguments: CommandArgumentEnvelope
        let dispatch: DecodedRequestDispatch
        let expectationPayload: ExpectationPayload

        init(
            command: Command,
            requestId: String,
            arguments: CommandArgumentEnvelope,
            dispatch: DecodedRequestDispatch,
            expectationPayload: ExpectationPayload
        ) {
            self.command = command
            self.requestId = requestId
            self.arguments = arguments
            self.dispatch = dispatch
            self.expectationPayload = expectationPayload
        }

        var executableRequest: ExecutableRequest? {
            dispatch.executableRequest
        }

        var handler: ParsedRequestHandler {
            dispatch.handler
        }
    }

    static func waitDispatch(_ step: WaitStep) -> DecodedRequestDispatch {
        .executable(.wait(step))
    }

    static func appInteractionDispatch(
        _ command: Command,
        _ firstCommand: HeistActionCommand,
        _ additionalCommands: HeistActionCommand...
    ) -> DecodedRequestDispatch {
        precondition(command.dispatchesAppInteraction, "\(command.rawValue) is not registered as an app interaction command")
        return .executable(.actions(NonEmptyHeistActionCommands(firstCommand, additional: additionalCommands)))
    }

    func parseRequest(command: Command, arguments: CommandArgumentEnvelope) throws -> ParsedRequest {
        guard command.descriptor.isPublicRequestContract else {
            throw SchemaValidationError(
                field: "command",
                observed: "string \"\(command.rawValue)\"",
                expected: "public command for The Button Heist"
            )
        }
        try validateRequestKeys(command: command, arguments: arguments)
        try command.descriptor.validatePublicRequestArguments(arguments)
        let requestId = arguments.string("requestId") ?? UUID().uuidString
        let expectationPayload = try ExpectationPayload(arguments: arguments)
        let dispatch = try command.descriptor.requestDecoder(self, arguments, requestId, expectationPayload)

        return ParsedRequest(
            command: command,
            requestId: requestId,
            arguments: arguments,
            dispatch: dispatch,
            expectationPayload: expectationPayload
        )
    }

    private func validateRequestKeys(command: Command, arguments: CommandArgumentEnvelope) throws {
        let metadataKeys = Set(["requestId"])
        let parameterKeys = command.descriptor.topLevelParameterKeys
        let allowedKeys = metadataKeys.union(parameterKeys)
        guard let unexpectedKey = arguments.keys.sorted().first(where: { !allowedKeys.contains($0) }) else {
            return
        }
        throw SchemaValidationError(
            field: unexpectedKey,
            observed: arguments.observedDescription(for: unexpectedKey) ?? "missing",
            expected: "valid \(command.rawValue) parameter"
        )
    }

}

extension FenceCommandDescriptor {
    func validatePublicRequestArguments(_ arguments: TheFence.CommandArgumentEnvelope) throws {
        for parameter in parameters {
            guard let value = arguments.argumentValues[parameter.key] else { continue }
            try validate(parameter, value: value, field: parameter.key)
        }
        for parameter in parameters where arguments.argumentValues[parameter.key] == nil {
            try validate(parameter, value: nil, field: parameter.key)
        }
    }

    func validate(_ parameter: FenceParameterSpec, value: HeistValue?, field: String) throws {
        guard let value else {
            guard parameter.required else { return }
            throw SchemaValidationError(field: field, observed: "missing", expected: parameter.expectedTypeDescription)
        }

        guard !parameter.usesCustomPayloadValidation else {
            return
        }

        try validateType(parameter.type, value: value, field: field)
        try validateEnum(parameter, value: value, field: field)
        try validateScalarBounds(parameter, value: value, field: field)

        switch parameter.type {
        case .object:
            guard case .object(let object) = value,
                  !parameter.skipsNestedDescriptorValidation else {
                return
            }
            try validateObject(object, parameter: parameter, field: field)
        case .array:
            guard case .array(let array) = value,
                  !parameter.skipsNestedDescriptorValidation else {
                return
            }
            try validateArrayItems(array, parameter: parameter, field: field)
        case .stringArray:
            guard case .array(let array) = value else { return }
            try validateStringArrayItems(array, field: field)
        default:
            break
        }
    }

    func validateObject(
        _ object: [String: HeistValue],
        parameter: FenceParameterSpec,
        field: String
    ) throws {
        for child in parameter.objectProperties {
            guard let value = object[child.key] else { continue }
            try validate(child, value: value, field: "\(field).\(child.key)")
        }
        for child in parameter.objectProperties where object[child.key] == nil {
            try validate(child, value: nil, field: "\(field).\(child.key)")
        }

        guard !parameter.objectAdditionalProperties else { return }
        let knownKeys = Set(parameter.objectProperties.map(\.key))
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
        parameter: FenceParameterSpec,
        field: String
    ) throws {
        guard let itemType = parameter.arrayItemType else { return }
        for (index, item) in array.enumerated() {
            let itemField = "\(field)[\(index)]"
            try validateType(itemType, value: item, field: itemField)
            guard itemType == .object, case .object(let object) = item else { continue }
            let itemParameter = FenceParameterSpec(
                key: parameter.key,
                type: .object,
                required: true,
                enumValues: nil,
                defaultValue: nil,
                minimum: nil,
                maximum: nil,
                exclusiveMinimum: nil,
                minLength: nil,
                minItems: nil,
                maxItems: nil,
                jsonSchemaProperty: .object([:]),
                objectProperties: parameter.arrayItemProperties,
                objectAdditionalProperties: parameter.arrayItemAdditionalProperties,
                arrayItemType: nil,
                arrayItemProperties: [],
                arrayItemAdditionalProperties: false
            )
            try validateObject(object, parameter: itemParameter, field: itemField)
        }
    }

    func validateStringArrayItems(_ array: [HeistValue], field: String) throws {
        for (index, item) in array.enumerated() {
            guard case .string = item else {
                throw SchemaValidationError(
                    field: "\(field)[\(index)]",
                    observed: item.schemaObservedDescription,
                    expected: "string"
                )
            }
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
        _ parameter: FenceParameterSpec,
        value: HeistValue,
        field: String
    ) throws {
        guard let enumValues = parameter.enumValues,
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
        _ parameter: FenceParameterSpec,
        value: HeistValue,
        field: String
    ) throws {
        switch parameter.type {
        case .integer:
            guard let integer = value.integerValue else { return }
            try validateNumberBounds(Double(integer), parameter: parameter, value: value, field: field)
        case .number:
            guard let number = value.numberValue else { return }
            try validateNumberBounds(number, parameter: parameter, value: value, field: field)
        case .string:
            guard let minLength = parameter.minLength,
                  case .string(let string) = value,
                  string.count < minLength else {
                return
            }
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: minLength == 1 ? "non-empty string" : "string with length >= \(minLength)"
            )
        case .array, .stringArray:
            guard case .array(let array) = value else { return }
            if let minItems = parameter.minItems, array.count < minItems {
                throw SchemaValidationError(
                    field: field,
                    observed: "array count \(array.count)",
                    expected: "array with at least \(minItems) items"
                )
            }
            if let maxItems = parameter.maxItems, array.count > maxItems {
                throw SchemaValidationError(
                    field: field,
                    observed: "array count \(array.count)",
                    expected: "array with at most \(maxItems) items"
                )
            }
        default:
            break
        }
    }

    func validateNumberBounds(
        _ number: Double,
        parameter: FenceParameterSpec,
        value: HeistValue,
        field: String
    ) throws {
        if let exclusiveMinimum = parameter.exclusiveMinimum, number <= exclusiveMinimum {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: "\(parameter.numericTypeDescription) > \(formatConstraintNumber(exclusiveMinimum))"
            )
        }
        if let minimum = parameter.minimum, number < minimum {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: parameter.numericLowerBoundDescription
            )
        }
        if let maximum = parameter.maximum, number > maximum {
            throw SchemaValidationError(
                field: field,
                observed: value.schemaObservedDescription,
                expected: parameter.numericUpperBoundDescription
            )
        }
    }

    func formatConstraintNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(value)
    }
}

private extension FenceParameterSpec {
    var usesCustomPayloadValidation: Bool {
        switch key {
        case FenceParameterKey.target.rawValue,
             FenceParameterKey.element.rawValue,
             FenceParameterKey.predicate.rawValue,
             FenceParameterKey.expect.rawValue,
             FenceParameterKey.argument.rawValue:
            return true
        default:
            return type == .stringMatch
        }
    }

    var skipsNestedDescriptorValidation: Bool {
        switch key {
        case FenceParameterKey.target.rawValue,
             FenceParameterKey.element.rawValue,
             FenceParameterKey.predicate.rawValue,
             FenceParameterKey.expect.rawValue,
             FenceParameterKey.argument.rawValue:
            return true
        default:
            return false
        }
    }

    var expectedTypeDescription: String {
        if let enumValues {
            return SchemaValidationError.expectedEnumValues(enumValues)
        }
        return type.expectedDescription
    }

    var numericTypeDescription: String {
        type == .integer ? "integer" : "number"
    }

    var numericLowerBoundDescription: String {
        guard let minimum else { return numericTypeDescription }
        if let maximum {
            return "\(numericTypeDescription) between \(formatConstraintNumber(minimum)) and \(formatConstraintNumber(maximum))"
        }
        return "\(numericTypeDescription) >= \(formatConstraintNumber(minimum))"
    }

    var numericUpperBoundDescription: String {
        guard let maximum else { return numericTypeDescription }
        if let exclusiveMinimum {
            return "\(numericTypeDescription) in \(formatConstraintNumber(exclusiveMinimum))...\(formatUpperConstraintNumber(maximum))"
        }
        if let minimum {
            return "\(numericTypeDescription) between \(formatConstraintNumber(minimum)) and \(formatUpperConstraintNumber(maximum))"
        }
        return "\(numericTypeDescription) <= \(formatUpperConstraintNumber(maximum))"
    }

    func formatConstraintNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(format: "%.0f", value)
        }
        return String(value)
    }

    func formatUpperConstraintNumber(_ value: Double) -> String {
        if type == .number, value != 0, value.rounded(.towardZero) == value {
            return String(format: "%.1f", value)
        }
        return formatConstraintNumber(value)
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
            return "StringMatch object with mode and value"
        case .object:
            return "object"
        case .array:
            return "array"
        }
    }
}

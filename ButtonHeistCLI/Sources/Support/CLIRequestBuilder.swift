@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation

struct CLIParsedRequest {
    let operation: FenceOperationRequest
    let requestId: PublicRequestId?

    var command: TheFence.Command {
        operation.command
    }

    var arguments: TheFence.CommandArgumentEnvelope {
        operation.arguments
    }
}

struct CLIRequestBuildError: Error, CustomStringConvertible {
    let diagnosticFailure: DiagnosticFailure
    let requestId: PublicRequestId?

    init(
        diagnosticFailure: DiagnosticFailure,
        requestId: PublicRequestId?
    ) {
        self.diagnosticFailure = diagnosticFailure
        self.requestId = requestId
    }

    var message: String { diagnosticFailure.message }
    var description: String { diagnosticFailure.displayMessage }
}

enum CLIRequestBuilder {

    static func arguments(
        parameters: CLIRequestParameters = [:],
        target: ElementTarget? = nil
    ) -> TheFence.CommandArgumentEnvelope {
        var values = Dictionary(
            parameters.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, newest in newest }
        )
        if let target {
            values[FenceParameterKey.target.rawValue] = targetValue(target)
        }
        return TheFence.CommandArgumentEnvelope(values: values)
    }

    static func parsedRequest(from line: String) throws -> CLIParsedRequest {
        try parseMachineRequest(line)
    }

    static func parseMachineRequest(_ line: String) throws -> CLIParsedRequest {
        let envelope: CLIMachineRequestEnvelope
        do {
            envelope = try CLIMachineRequestEnvelope.decode(from: line)
        } catch let error as CLIRequestBuildError {
            throw error
        } catch {
            throw CLIRequestBuildError(
                diagnosticFailure: diagnosticFailure(for: error),
                requestId: nil
            )
        }
        let requestId = envelope.requestId
        do {
            switch TheFence.Command.routeCLICommandEnvelope(envelope.arguments, context: "JSON input") {
            case .success(let routed):
                return CLIParsedRequest(
                    operation: routed,
                    requestId: requestId
                )
            case .failure(let error):
                throw CLIRequestBuildError(
                    diagnosticFailure: DiagnosticFailure(message: error.message, details: error.details),
                    requestId: requestId
                )
            }
        } catch let error as CLIRequestBuildError {
            throw error
        } catch let error as SchemaValidationError {
            throw CLIRequestBuildError(
                diagnosticFailure: DiagnosticFailure(
                    message: error.message,
                    details: FailureDetails(code: .requestValidationError)
                ),
                requestId: requestId
            )
        } catch {
            throw CLIRequestBuildError(
                diagnosticFailure: diagnosticFailure(for: error),
                requestId: requestId
            )
        }
    }

    fileprivate static func diagnosticFailure(
        for error: Error,
        details: FailureDetails = FailureDetails(code: .requestInvalid)
    ) -> DiagnosticFailure {
        if let buildError = error as? CLIRequestBuildError {
            return buildError.diagnosticFailure
        }
        if let inputError = error as? PublicJSONInputError {
            return DiagnosticFailure(message: inputError.message, details: details)
        }
        let description = String(describing: error)
        let message = description.isEmpty ? error.localizedDescription : description
        return DiagnosticFailure(message: message, details: details)
    }

    static func targetValue(_ target: ElementTarget) -> HeistValue {
        .object(targetObject(target))
    }

    static func targetObject(_ target: ElementTarget) -> [String: HeistValue] {
        switch target {
        case .predicate(let predicate, let ordinal):
            var object = predicateArgumentValues(predicate)
            if let ordinal {
                object[FenceParameterKey.ordinal.rawValue] = .int(ordinal)
            }
            return object
        }
    }

    private static func predicateArgumentValues(_ predicate: ElementPredicate) -> [String: HeistValue] {
        var object: [String: HeistValue] = [:]
        for check in predicate.checks {
            switch check {
            case .label(let match):
                appendStringMatch(match, to: FenceParameterKey.label.rawValue, in: &object)
            case .identifier(let match):
                appendStringMatch(match, to: FenceParameterKey.identifier.rawValue, in: &object)
            case .value(let match):
                appendStringMatch(match, to: FenceParameterKey.value.rawValue, in: &object)
            case .traits(let traits):
                appendTraits(traits, to: FenceParameterKey.traits.rawValue, in: &object)
            case .excludeTraits(let traits):
                appendTraits(traits, to: FenceParameterKey.excludeTraits.rawValue, in: &object)
            }
        }
        return object
    }

    private static func appendStringMatch(
        _ match: StringMatch<String>,
        to key: String,
        in object: inout [String: HeistValue]
    ) {
        appendOneOrManyValue(stringMatchValue(match), to: key, in: &object)
    }

    private static func appendTraits(
        _ traits: Set<HeistTrait>,
        to key: String,
        in object: inout [String: HeistValue]
    ) {
        guard !traits.isEmpty else { return }
        var values: [HeistValue]
        if case .array(let existing)? = object[key] {
            values = existing
        } else {
            values = []
        }
        values.append(contentsOf: traits.sorted { $0.rawValue < $1.rawValue }.map { .string($0.rawValue) })
        object[key] = .array(values)
    }

    private static func appendOneOrManyValue(
        _ value: HeistValue,
        to key: String,
        in object: inout [String: HeistValue]
    ) {
        switch object[key] {
        case nil:
            object[key] = value
        case .array(let existing)?:
            object[key] = .array(existing + [value])
        case let existing?:
            object[key] = .array([existing, value])
        }
    }

    private static func stringMatchValue(_ match: StringMatch<String>) -> HeistValue {
        .object([
            FenceParameterKey.mode.rawValue: .string(match.mode.rawValue),
            FenceParameterKey.value.rawValue: .string(match.value),
        ])
    }
}

private struct CLIMachineRequestEnvelope: Decodable {
    let requestId: PublicRequestId?
    let arguments: TheFence.CommandArgumentEnvelope

    static func decode(from line: String) throws -> Self {
        do {
            return try PublicJSONInputDecoder.decode(
                Self.self,
                from: line,
                root: .object,
                context: "Public JSON request",
                rootMismatchMessage: "Expected JSON object input"
            )
        } catch let error as DecodingError {
            throw CLIRequestBuildError(
                diagnosticFailure: CLIRequestBuilder.diagnosticFailure(for: error),
                requestId: nil
            )
        } catch {
            throw CLIRequestBuildError(
                diagnosticFailure: CLIRequestBuilder.diagnosticFailure(for: error),
                requestId: nil
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        let idKey = DynamicCodingKey(stringValue: "id")
        requestId = if let idKey, container.contains(idKey) {
            try container.decode(PublicRequestId.self, forKey: idKey)
        } else {
            nil
        }
        var values: [String: HeistValue] = [:]
        for key in container.allKeys {
            if key.stringValue == "id" {
                continue
            }
            values[key.stringValue] = try container.decode(HeistValue.self, forKey: key)
        }
        arguments = TheFence.CommandArgumentEnvelope(values: values, fieldPrefix: nil)
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

import ArgumentParser
import ButtonHeist
import Foundation

struct CLIParsedRequest {
    let command: TheFence.Command
    let arguments: TheFence.CommandArgumentEnvelope
    let requestId: PublicRequestId?
}

struct CLIRequestBuildError: Error, CustomStringConvertible {
    let message: String
    let requestId: PublicRequestId?

    var description: String { message }
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
            values[FenceParameterKey.target.rawValue] = targetArgumentValue(target)
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
        } catch let error as DecodingError {
            throw ValidationError(diagnosticMessage(for: error))
        }
        let requestId = envelope.requestId
        do {
            switch TheFence.Command.routeCLICommandEnvelope(envelope.arguments, context: "JSON input") {
            case .success(let routed):
                return CLIParsedRequest(
                    command: routed.command,
                    arguments: routed.arguments,
                    requestId: requestId
                )
            case .failure(let error):
                throw ValidationError(error.message)
            }
        } catch let error as CLIRequestBuildError {
            throw error
        } catch {
            throw CLIRequestBuildError(
                message: diagnosticMessage(for: error),
                requestId: requestId
            )
        }
    }

    static func diagnosticMessage(for error: Error) -> String {
        let description = String(describing: error)
        return description.isEmpty ? error.localizedDescription : description
    }

    private static func targetArgumentValue(_ target: ElementTarget) -> HeistValue {
        switch target {
        case .predicate(let predicate, let ordinal):
            var object = predicateArgumentValues(predicate)
            if let ordinal {
                object[FenceParameterKey.ordinal.rawValue] = .int(ordinal)
            }
            return .object(object)
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
        _ traits: [HeistTrait],
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
        values.append(contentsOf: traits.map { .string($0.rawValue) })
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
                message: CLIRequestBuilder.diagnosticMessage(for: error),
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

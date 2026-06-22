import ArgumentParser
import ButtonHeist
import Foundation
import ThePlans

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
        let values = Dictionary(
            parameters.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: { _, newest in newest }
        )
        return TheFence.CommandArgumentEnvelope(values: values, elementTarget: target)
    }

    static func parsedRequest(from line: String) throws -> CLIParsedRequest {
        guard line.hasPrefix("{") else {
            throw ValidationError("Expected JSON object input")
        }
        return try parseMachineRequest(line)
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
            switch TheFence.Command.routeCommandEnvelope(envelope.arguments, context: "JSON input") {
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
}

private struct CLIMachineRequestEnvelope: Decodable {
    let requestId: PublicRequestId?
    let arguments: TheFence.CommandArgumentEnvelope

    static func decode(from line: String) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: Data(line.utf8))
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

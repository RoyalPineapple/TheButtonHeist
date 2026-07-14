@_spi(ButtonHeistTooling) import ButtonHeist
import Foundation

struct CLIParsedRequest {
    let input: FenceCommandInput
    let requestId: PublicRequestId?

    var command: TheFence.Command {
        input.command
    }
}

struct CLIMachineRequestError: Error, CustomStringConvertible {
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

enum CLIMachineRequestParser {
    static func parsedRequest(from line: String) throws -> CLIParsedRequest {
        let envelope: CLIMachineRequestEnvelope
        do {
            envelope = try CLIMachineRequestEnvelope.decode(from: line)
        } catch let error as CLIMachineRequestError {
            throw error
        } catch {
            throw CLIMachineRequestError(
                diagnosticFailure: diagnosticFailure(for: error),
                requestId: nil
            )
        }
        let requestId = envelope.requestId
        switch TheFence.Command.routeCLICommandEnvelope(envelope.arguments, context: "JSON input") {
        case .success(let input):
            return CLIParsedRequest(input: input, requestId: requestId)
        case .failure(let error):
            throw CLIMachineRequestError(
                diagnosticFailure: DiagnosticFailure(message: error.message, details: error.details),
                requestId: requestId
            )
        }
    }

    fileprivate static func diagnosticFailure(
        for error: Error,
        details: FailureDetails = FailureDetails(code: .requestInvalid)
    ) -> DiagnosticFailure {
        if let requestError = error as? CLIMachineRequestError {
            return requestError.diagnosticFailure
        }
        if let inputError = error as? PublicJSONInputError {
            return DiagnosticFailure(message: inputError.message, details: details)
        }
        let description = String(describing: error)
        let message = description.isEmpty ? error.localizedDescription : description
        return DiagnosticFailure(message: message, details: details)
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
            throw CLIMachineRequestError(
                diagnosticFailure: CLIMachineRequestParser.diagnosticFailure(for: error),
                requestId: nil
            )
        } catch {
            throw CLIMachineRequestError(
                diagnosticFailure: CLIMachineRequestParser.diagnosticFailure(for: error),
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

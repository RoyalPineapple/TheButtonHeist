import Foundation

enum HeistPlanJSONCodec {
    static func canonicalJSONData(for plan: HeistPlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(plan)
    }

    static func decodeValidatedPlan(
        _ data: Data,
        sourceURL: URL = URL(fileURLWithPath: "inline-heist-plan.json")
    ) throws -> HeistPlan {
        let raw = try decodeAdmissionCandidate(data, sourceURL: sourceURL)
        return try raw.validatedForRuntimeSafety()
    }

    static func decodeAdmissionCandidate(
        _ data: Data,
        sourceURL: URL
    ) throws -> HeistPlanAdmissionCandidate {
        let version = try decodePlanVersion(from: data, sourceURL: sourceURL)
        try requireSupportedPlanVersion(version, sourceURL: sourceURL)
        do {
            return try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: data)
        } catch {
            throw HeistPlanJSONCodecError.invalidPlan(
                source: sourceURL.path,
                reason: String(describing: error)
            )
        }
    }

    static func decodePlanVersion(from data: Data, sourceURL: URL) throws -> Int {
        do {
            return try JSONDecoder().decode(HeistPlanVersionPayload.self, from: data).version
        } catch HeistPlanVersionPayloadError.expectedJSONObject {
            throw HeistPlanJSONCodecError.invalidPlan(source: sourceURL.path, reason: "expected JSON object")
        } catch HeistPlanVersionPayloadError.missingVersion {
            throw HeistPlanJSONCodecError.missingVersion(source: sourceURL.path)
        } catch HeistPlanVersionPayloadError.invalidVersion(let observed) {
            throw HeistPlanJSONCodecError.invalidVersion(
                source: sourceURL.path,
                observed: observed
            )
        } catch {
            throw HeistPlanJSONCodecError.invalidPlan(
                source: sourceURL.path,
                reason: String(describing: error)
            )
        }
    }

    static func requireSupportedPlanVersion(_ version: Int, sourceURL: URL) throws {
        guard version == currentHeistPlanVersion else {
            throw HeistPlanJSONCodecError.unsupportedVersion(
                source: sourceURL.path,
                observed: version
            )
        }
    }
}

public extension HeistPlan {
    func canonicalHeistJSONData() throws -> Data {
        try HeistPlanJSONCodec.canonicalJSONData(for: self)
    }
}

enum HeistPlanJSONCodecError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalidPlan(source: String, reason: String)
    case missingVersion(source: String)
    case invalidVersion(source: String, observed: String)
    case unsupportedVersion(source: String, observed: Int)

    var description: String {
        switch self {
        case .invalidPlan(let source, let reason):
            return "Invalid heist plan at \(source): \(reason)"
        case .missingVersion(let source):
            return "Invalid heist plan at \(source): missing version."
        case .invalidVersion(let source, let observed):
            return "Invalid heist plan at \(source): version must be an integer, got \(observed)."
        case .unsupportedVersion(let source, let observed):
            return """
            Invalid heist plan at \(source): unsupported version \(observed). \
            This Button Heist build supports version \(currentHeistPlanVersion).
            """
        }
    }

}

private struct HeistPlanVersionPayload: Decodable {
    let version: Int

    private enum CodingKeys: String, CodingKey {
        case version
    }

    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys>
        do {
            container = try decoder.container(keyedBy: CodingKeys.self)
        } catch {
            throw HeistPlanVersionPayloadError.expectedJSONObject
        }

        guard container.contains(.version) else {
            throw HeistPlanVersionPayloadError.missingVersion
        }

        do {
            version = try container.decode(Int.self, forKey: .version)
        } catch {
            let observed = (try? container.decode(HeistPlanJSONValue.self, forKey: .version))?.description
                ?? String(describing: error)
            throw HeistPlanVersionPayloadError.invalidVersion(observed)
        }
    }
}

private enum HeistPlanVersionPayloadError: Error, Sendable, Equatable {
    case expectedJSONObject
    case missingVersion
    case invalidVersion(String)
}

private enum HeistPlanJSONValue: Decodable, CustomStringConvertible {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([HeistPlanJSONValue])
    case object([String: HeistPlanJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .number(String(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(String(value))
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([HeistPlanJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: HeistPlanJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "unsupported JSON value"
            )
        }
    }

    var description: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return String(value)
        case .number(let value):
            return value
        case .string(let value):
            return quoted(value)
        case .array(let values):
            return "[" + values.map(\.description).joined(separator: ", ") + "]"
        case .object(let fields):
            let body = fields.keys.sorted().map { key in
                "\(quoted(key)): \(fields[key]?.description ?? "null")"
            }.joined(separator: ", ")
            return "{\(body)}"
        }
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: #"\"#, with: #"\\"#)
            .replacingOccurrences(of: #"""#, with: #"\""#)
        return #""\#(escaped)""#
    }
}

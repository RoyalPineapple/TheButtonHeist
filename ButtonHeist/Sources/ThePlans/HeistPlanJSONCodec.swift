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
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw HeistPlanJSONCodecError.invalidPlan(
                source: sourceURL.path,
                reason: String(describing: error)
            )
        }

        guard let dictionary = object as? [String: Any] else {
            throw HeistPlanJSONCodecError.invalidPlan(source: sourceURL.path, reason: "expected JSON object")
        }
        guard let version = dictionary["version"] else {
            throw HeistPlanJSONCodecError.missingVersion(source: sourceURL.path)
        }
        guard let intVersion = version as? Int else {
            throw HeistPlanJSONCodecError.invalidVersion(
                source: sourceURL.path,
                observed: String(describing: version)
            )
        }
        return intVersion
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

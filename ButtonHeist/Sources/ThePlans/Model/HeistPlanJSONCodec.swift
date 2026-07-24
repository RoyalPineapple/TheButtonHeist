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
        do {
            return try JSONDecoder().decode(HeistPlan.self, from: data)
        } catch DecodingError.typeMismatch(_, let context) where context.codingPath.isEmpty {
            throw HeistPlanJSONCodecError.invalidPlan(source: sourceURL.path, reason: "expected JSON object")
        } catch DecodingError.keyNotFound(let key, _) where key.stringValue == "version" {
            throw HeistPlanJSONCodecError.missingVersion(source: sourceURL.path)
        } catch DecodingError.typeMismatch(_, let context) where context.codingPath.last?.stringValue == "version" {
            throw HeistPlanJSONCodecError.invalidVersion(
                source: sourceURL.path,
                observed: context.debugDescription
            )
        } catch let error as HeistPlanVersionAdmissionError {
            throw HeistPlanJSONCodecError.unsupportedVersion(
                source: sourceURL.path,
                observed: error.observed
            )
        } catch {
            throw HeistPlanJSONCodecError.invalidPlan(
                source: sourceURL.path,
                reason: String(describing: error)
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

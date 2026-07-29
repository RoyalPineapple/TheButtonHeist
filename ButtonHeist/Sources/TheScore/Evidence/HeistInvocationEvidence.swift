import Foundation

private enum InvocationOutcomeKind: String, Codable {
    case completed
    case childFailed = "child_failed"
}

private enum InvocationOutcomeCodingKey: String, CodingKey, CaseIterable {
    case type
    case path
}

/// Facts owned by the invocation node itself.
///
/// Its children retain their own action and expectation evidence; the
/// invocation does not copy either currency.
public enum HeistInvocationEvidence: Codable, Sendable, Equatable {
    case completed
    case childFailed(path: HeistExecutionPath)

    public var childFailedPath: HeistExecutionPath? {
        guard case .childFailed(let path) = self else { return nil }
        return path
    }

    var provesInvocationFailure: Bool {
        if case .childFailed = self { return true }
        return false
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(
            allowed: InvocationOutcomeCodingKey.self,
            typeName: "heist invocation evidence"
        )
        let container = try decoder.container(keyedBy: InvocationOutcomeCodingKey.self)
        switch try container.decode(InvocationOutcomeKind.self, forKey: .type) {
        case .completed:
            self = .completed
            try container.rejectIncompatibleFields(
                allowing: [.type],
                typeName: "completed invocation evidence"
            )
        case .childFailed:
            self = .childFailed(path: try container.decode(HeistExecutionPath.self, forKey: .path))
            try container.rejectIncompatibleFields(
                allowing: [.type, .path],
                typeName: "child_failed invocation evidence"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: InvocationOutcomeCodingKey.self)
        switch self {
        case .completed:
            try container.encode(InvocationOutcomeKind.completed, forKey: .type)
        case .childFailed(let path):
            try container.encode(InvocationOutcomeKind.childFailed, forKey: .type)
            try container.encode(path, forKey: .path)
        }
    }
}

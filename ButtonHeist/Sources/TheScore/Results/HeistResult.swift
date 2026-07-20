import Foundation

/// Complete typed result of one heist-plan execution.
public struct HeistResult: Codable, Sendable, Equatable {
    public let steps: [HeistExecutionStepResult]
    /// End-to-end wall-clock observation for the heist. Child durations can
    /// overlap this interval and are not additive inputs to it.
    public let durationMs: ElapsedMilliseconds

    public var outcome: HeistExecutionOutcome {
        if let failed = steps.firstFailedStepInResultOrder {
            return .failed(abortedAtPath: failed.path)
        }
        return .passed
    }

    public var abortedAtPath: HeistExecutionPath? {
        guard case .failed(let abortedAtPath) = outcome else { return nil }
        return abortedAtPath
    }

    package init(steps: [HeistExecutionStepResult], durationMs: ElapsedMilliseconds) throws {
        try Self.admitStructure(steps, limits: .default)
        self.steps = steps
        self.durationMs = durationMs
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case steps
        case durationMs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist result")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let steps = try container.decode([HeistExecutionStepResult].self, forKey: .steps)
        let durationMs = try container.decode(ElapsedMilliseconds.self, forKey: .durationMs)
        let limits = decoder.userInfo[.heistResultCodecLimits] as? HeistResultCodecLimits ?? .default
        do {
            try Self.admitStructure(steps, limits: limits)
        } catch {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: String(describing: error)
            ))
        }
        self.steps = steps
        self.durationMs = durationMs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encode(durationMs, forKey: .durationMs)
    }

    private static func admitStructure(
        _ roots: [HeistExecutionStepResult],
        limits: HeistResultCodecLimits
    ) throws {
        var pending = roots.reversed().map {
            (step: $0, depth: 1, parentPath: Optional<HeistExecutionPath>.none)
        }
        var paths: Set<HeistExecutionPath> = []
        var nodeCount = 0
        while let current = pending.popLast() {
            nodeCount += 1
            guard nodeCount <= limits.maxNodeCount else {
                throw HeistResultCodecError.nodeCountExceeded(limit: limits.maxNodeCount, observed: nodeCount)
            }
            guard current.depth <= limits.maxNestingDepth else {
                throw HeistResultCodecError.nestingDepthExceeded(
                    limit: limits.maxNestingDepth,
                    observed: current.depth
                )
            }
            guard paths.insert(current.step.path).inserted else {
                throw HeistResultCodecError.duplicateExecutionPath(current.step.path)
            }
            if let parentPath = current.parentPath,
               !current.step.path.isDescendant(of: parentPath) {
                throw HeistResultCodecError.nonDescendantChildPath(
                    parent: parentPath,
                    child: current.step.path
                )
            }
            pending.append(contentsOf: current.step.children.reversed().map {
                (step: $0, depth: current.depth + 1, parentPath: current.step.path)
            })
        }
    }

}

public enum HeistExecutionOutcome: Sendable, Equatable {
    case passed
    case failed(abortedAtPath: HeistExecutionPath)
}

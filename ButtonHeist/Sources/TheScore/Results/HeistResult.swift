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
            (
                step: $0,
                depth: 1,
                parent: Optional<HeistExecutionStepResult>.none,
                childOrdinal: Optional<Int>.none
            )
        }
        var paths: Set<HeistExecutionPath> = []
        var admittedStepsByPath: [HeistExecutionPath: HeistExecutionStepResult] = [:]
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
            if let parent = current.parent {
                guard current.step.path.isDescendant(of: parent.path) else {
                    throw HeistResultCodecError.nonDescendantChildPath(
                        parent: parent.path,
                        child: current.step.path
                    )
                }
                guard let childOrdinal = current.childOrdinal else {
                    throw HeistResultCodecError.illegalChildExecutionPath(
                        parent: parent.path,
                        child: current.step.path,
                        parentKind: parent.kind
                    )
                }
                guard current.step.path.isLegalChild(
                    of: parent,
                    child: current.step,
                    childOrdinal: childOrdinal
                ) else {
                    throw HeistResultCodecError.illegalChildExecutionPath(
                        parent: parent.path,
                        child: current.step.path,
                        parentKind: parent.kind
                    )
                }
            } else if current.step.path.isRootStepPath() {
                // Top-level result fragments may carry their original body index.
            } else if let failureAction = current.step.path.failureActionAncestor,
                      let parent = admittedStepsByPath[failureAction.path],
                      parent.status == .failed,
                      current.step.path.isLegalChild(
                        of: parent,
                        child: current.step,
                        childOrdinal: failureAction.actionIndex
                      ) {
                // Auxiliary failure-action roots are emitted beside top-level roots,
                // but their path must still be owned by an admitted failed step.
            } else {
                throw HeistResultCodecError.illegalRootExecutionPath(current.step.path)
            }
            admittedStepsByPath[current.step.path] = current.step
            var branchCounts: [HeistExecutionPath.ChildBranch: Int] = [:]
            let children = current.step.children.map { child in
                let branch = child.path.childBranch(after: current.step.path)
                let childOrdinal = branch.map { branch in
                    defer { branchCounts[branch, default: 0] += 1 }
                    return branchCounts[branch, default: 0]
                }
                return (
                    step: child,
                    depth: current.depth + 1,
                    parent: Optional(current.step),
                    childOrdinal: childOrdinal
                )
            }
            pending.append(contentsOf: children.reversed())
        }
    }

}

public enum HeistExecutionOutcome: Sendable, Equatable {
    case passed
    case failed(abortedAtPath: HeistExecutionPath)
}

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
                let edge = child.path.childEdge(after: current.step.path)
                let childOrdinal = edge.map { edge in
                    defer { branchCounts[edge.branch, default: 0] += 1 }
                    return branchCounts[edge.branch, default: 0]
                }
                return (
                    step: child,
                    depth: current.depth + 1,
                    parent: Optional(current.step),
                    childOrdinal: childOrdinal,
                    edge: edge
                )
            }
            try admitAggregateEvidence(
                current.step,
                childEdges: children.compactMap { child in
                    child.edge.map { (child.step, $0) }
                }
            )
            pending.append(contentsOf: children.reversed().map {
                (
                    step: $0.step,
                    depth: $0.depth,
                    parent: $0.parent,
                    childOrdinal: $0.childOrdinal
                )
            })
        }
        try admitRootIndices(roots)
    }

    private static func admitRootIndices(_ roots: [HeistExecutionStepResult]) throws {
        let rootIndices = roots.compactMap(\.path.rootStepIndex)
        guard rootIndices == Array(0..<rootIndices.count) else {
            throw HeistResultCodecError.incoherentExecutionEvidence(
                path: .body,
                reason: "top-level body root indices must be contiguous and in result order"
            )
        }
    }

    private static func admitAggregateEvidence(
        _ step: HeistExecutionStepResult,
        childEdges: [(step: HeistExecutionStepResult, edge: HeistExecutionPath.ChildEdge)]
    ) throws {
        switch step.kind {
        case .conditional:
            try admitConditionalEvidence(step, childEdges: childEdges)
        case .forEachElement:
            try admitLoopIterationCount(
                step,
                observed: childEdges.count { $0.edge.branch == .forEachElementIterations },
                expected: step.forEachElementEvidence?.iterationCount,
                loopName: "for_each_element"
            )
        case .forEachString:
            try admitLoopIterationCount(
                step,
                observed: childEdges.count { $0.edge.branch == .forEachStringIterations },
                expected: step.forEachStringEvidence?.iterationCount,
                loopName: "for_each_string"
            )
        case .repeatUntil:
            try admitRepeatUntilEvidence(step, childEdges: childEdges)
        case .action,
             .wait,
             .forEachIteration,
             .repeatUntilIteration,
             .warn,
             .fail,
             .heist,
             .invoke:
            break
        }
    }

    private static func admitConditionalEvidence(
        _ step: HeistExecutionStepResult,
        childEdges: [(step: HeistExecutionStepResult, edge: HeistExecutionPath.ChildEdge)]
    ) throws {
        guard let outcome = step.caseSelectionEvidence?.selection.outcome else { return }
        let executionEdges = childEdges.filter(\.edge.isConditionalExecutionBranch)
        let accepts: (HeistExecutionPath.ChildEdge) -> Bool
        switch outcome {
        case .matchedCase(let index):
            guard let matchedIndex = Int(exactly: index) else {
                throw incoherent(step, "matched_case index \(index) is not representable")
            }
            accepts = { $0.branch == .conditionalCase(matchedIndex) }
        case .elseBranch:
            accepts = { $0.branch == .conditionalElse }
        case .timedOut, .noMatch:
            accepts = { _ in false }
        }
        guard executionEdges.allSatisfy({ accepts($0.edge) }) else {
            throw incoherent(step, "conditional children do not match selected branch \(outcome)")
        }
    }

    private static func admitLoopIterationCount(
        _ step: HeistExecutionStepResult,
        observed: Int,
        expected: Int?,
        loopName: String
    ) throws {
        guard let expected else { return }
        guard observed == expected else {
            throw incoherent(
                step,
                "\(loopName) evidence iterationCount \(expected) does not match \(observed) iteration child node(s)"
            )
        }
    }

    private static func admitRepeatUntilEvidence(
        _ step: HeistExecutionStepResult,
        childEdges: [(step: HeistExecutionStepResult, edge: HeistExecutionPath.ChildEdge)]
    ) throws {
        guard let evidence = step.repeatUntilEvidence else { return }
        let iterationCount = childEdges.count { $0.edge.branch == .repeatUntilIterations }
        guard iterationCount == evidence.iterationCount else {
            throw incoherent(
                step,
                "repeat_until evidence iterationCount \(evidence.iterationCount) "
                    + "does not match \(iterationCount) iteration child node(s)"
            )
        }
        let elseCount = childEdges.count { $0.edge.branch == .repeatUntilElse }
        switch evidence.outcome {
        case .matched, .continued:
            guard elseCount == 0 else {
                throw incoherent(step, "repeat_until \(evidence.outcome) evidence cannot contain else_body children")
            }
        case .handledElse:
            guard elseCount > 0 else {
                throw incoherent(step, "repeat_until handled_else evidence requires else_body children")
            }
        case .failed:
            break
        }
    }

    private static func incoherent(
        _ step: HeistExecutionStepResult,
        _ reason: String
    ) -> HeistResultCodecError {
        .incoherentExecutionEvidence(path: step.path, reason: reason)
    }

}

private extension Sequence {
    func count(where isIncluded: (Element) throws -> Bool) rethrows -> Int {
        try reduce(into: 0) { count, element in
            if try isIncluded(element) {
                count += 1
            }
        }
    }
}

public enum HeistExecutionOutcome: Sendable, Equatable {
    case passed
    case failed(abortedAtPath: HeistExecutionPath)
}

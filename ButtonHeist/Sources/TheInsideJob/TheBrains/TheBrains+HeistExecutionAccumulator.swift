#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
import ThePlans
import TheScore

extension TheBrains {

    internal enum HeistExecutionAccumulator {
        case executing([HeistExecutionStepResult])
        case aborted([HeistExecutionStepResult], failedPath: HeistExecutionPath)

        internal init() { self = .executing([]) }

        internal var steps: [HeistExecutionStepResult] {
            switch self {
            case .executing(let steps), .aborted(let steps, _): steps
            }
        }

        internal var abortedPath: HeistExecutionPath? {
            guard case .aborted(_, let path) = self else { return nil }
            return path
        }

        internal mutating func append(_ result: HeistExecutionStepResult) {
            switch self {
            case .executing(let steps):
                let values = steps + [result]
                if let failed = result.firstFailedStep {
                    self = .aborted(values, failedPath: failed.path)
                } else {
                    self = .executing(values)
                }
            case .aborted(let steps, let failedPath):
                self = .aborted(steps + [result], failedPath: failedPath)
            }
        }
    }

    internal func skippedHeistReceipt(
        for step: HeistStep,
        path: HeistExecutionPath
    ) -> HeistExecutionStepResult {
        var algebra = SkippedHeistReceiptAlgebra(
            rootPath: path,
            makeReceipt: { path, step, children in
                guard let children = HeistSkippedChildren(children) else {
                    preconditionFailure("skipped receipt traversal produced a non-skipped child")
                }
                switch step {
                case .action(let action):
                    return .action(
                        path: path,
                        durationMs: 0,
                        command: action.command,
                        completion: .skipped(children: children)
                    )
                case .wait(let wait):
                    return .wait(
                        path: path,
                        durationMs: 0,
                        predicate: wait.predicate,
                        timeout: wait.timeout,
                        completion: .skipped(children: children)
                    )
                case .conditional:
                    return .conditional(path: path, durationMs: 0, completion: .skipped(children: children))
                case .forEachElement(let loop):
                    return .forEachElement(
                        path: path,
                        durationMs: 0,
                        parameter: loop.parameter,
                        matching: loop.matching,
                        limit: loop.limit,
                        completion: .skipped(children: children)
                    )
                case .forEachString(let loop):
                    return .forEachString(
                        path: path,
                        durationMs: 0,
                        parameter: loop.parameter,
                        count: loop.values.count,
                        completion: .skipped(children: children)
                    )
                case .repeatUntil(let loop):
                    return .repeatUntil(
                        path: path,
                        durationMs: 0,
                        predicate: loop.predicate,
                        timeout: loop.timeout,
                        completion: .skipped(children: children)
                    )
                case .warn(let warning):
                    return .warning(
                        path: path,
                        durationMs: 0,
                        message: warning.message,
                        completion: .skipped(children: children)
                    )
                case .fail(let failure):
                    return .failure(
                        path: path,
                        durationMs: 0,
                        message: failure.message,
                        completion: .skipped(children: children)
                    )
                case .heist(let plan):
                    return .heist(
                        path: path,
                        durationMs: 0,
                        name: plan.name,
                        completion: .skipped(children: children)
                    )
                case .invoke(let invocation):
                    return .invocation(
                        path: path,
                        durationMs: 0,
                        invocationPath: invocation.path,
                        argument: invocation.argument,
                        completion: .skipped(children: children)
                    )
                }
            }
        )
        HeistPlanTraversal.walk(step, visitor: &algebra)
        return algebra.receipt
    }
}

private struct SkippedHeistReceiptAlgebra: HeistPlanTraversalVisitor {
    private struct Frame {
        let path: HeistExecutionPath?
        let step: HeistStep
        var children: [HeistExecutionStepResult] = []
    }

    private let rootPath: HeistExecutionPath
    private let makeReceipt: (
        _ path: HeistExecutionPath,
        _ step: HeistStep,
        _ children: [HeistExecutionStepResult]
    ) -> HeistExecutionStepResult
    private var frames: [Frame] = []
    private var definitionsDepth = 0
    private var rootReceipt: HeistExecutionStepResult?

    init(
        rootPath: HeistExecutionPath,
        makeReceipt: @escaping (
            _ path: HeistExecutionPath,
            _ step: HeistStep,
            _ children: [HeistExecutionStepResult]
        ) -> HeistExecutionStepResult
    ) {
        self.rootPath = rootPath
        self.makeReceipt = makeReceipt
    }

    var receipt: HeistExecutionStepResult {
        guard let rootReceipt else {
            preconditionFailure("Skipped heist receipt traversal must produce a root receipt")
        }
        return rootReceipt
    }

    fileprivate mutating func visitDefinitions(_: [HeistPlan], context _: HeistTraversalContext) {
        definitionsDepth += 1
    }

    fileprivate mutating func leaveDefinitions(_: [HeistPlan], context _: HeistTraversalContext) {
        definitionsDepth -= 1
    }

    fileprivate mutating func visitStep(_ step: HeistStep, context _: HeistTraversalContext) {
        let path: HeistExecutionPath?
        if frames.isEmpty {
            path = rootPath
        } else if definitionsDepth == 0,
                  let parentPath = frames[frames.count - 1].path,
                  case .heist = frames[frames.count - 1].step {
            path = parentPath.heistBody().step(at: frames[frames.count - 1].children.count)
        } else {
            path = nil
        }
        frames.append(Frame(path: path, step: step))
    }

    fileprivate mutating func leaveStep(_: HeistStep, context _: HeistTraversalContext) {
        let frame = frames.removeLast()
        guard let path = frame.path else { return }
        let receipt = makeReceipt(path, frame.step, frame.children)
        guard !frames.isEmpty else {
            rootReceipt = receipt
            return
        }
        frames[frames.count - 1].children.append(receipt)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

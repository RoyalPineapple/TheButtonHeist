#if canImport(UIKit)
#if DEBUG
import ButtonHeistSupport
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
}

#endif // DEBUG
#endif // canImport(UIKit)

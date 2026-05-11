import TheScore

/// Diagnostic context captured when a heist playback step fails.
/// Each case carries exactly the data produced by that failure mode.
public enum PlaybackFailure: Sendable {
    /// TheFence returned a .error response (unknown command, invalid request, etc.)
    case fenceError(step: FailedStep, message: String, interface: Interface?)
    /// The action executed but returned a non-success ActionResult
    case actionFailed(step: FailedStep, result: ActionResult, expectation: ExpectationResult?, interface: Interface?)
    /// The execute call threw an exception
    case thrown(step: FailedStep, error: String, interface: Interface?)

    /// The step that failed — command name and element target.
    public struct FailedStep: Sendable {
        public let command: String
        public let target: ElementMatcher?

        public init(command: String, target: ElementMatcher?) {
            self.command = command
            self.target = target
        }
    }

    public var step: FailedStep {
        switch self {
        case .fenceError(let step, _, _): return step
        case .actionFailed(let step, _, _, _): return step
        case .thrown(let step, _, _): return step
        }
    }

    public var errorMessage: String {
        switch self {
        case .fenceError(_, let message, _): return message
        case .actionFailed(_, let result, _, _): return result.message ?? "action failed"
        case .thrown(_, let error, _): return error
        }
    }

    /// Return a copy with the interface snapshot attached.
    func withInterface(_ interface: Interface?) -> PlaybackFailure {
        switch self {
        case .fenceError(let step, let message, _):
            return .fenceError(step: step, message: message, interface: interface)
        case .actionFailed(let step, let result, let expectation, _):
            return .actionFailed(step: step, result: result, expectation: expectation, interface: interface)
        case .thrown(let step, let error, _):
            return .thrown(step: step, error: error, interface: interface)
        }
    }
}

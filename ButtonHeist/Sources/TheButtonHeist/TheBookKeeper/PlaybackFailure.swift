import TheScore

/// Diagnostic context captured when a heist playback step fails.
/// Each case carries exactly the data produced by that failure mode.
public enum PlaybackFailure: Sendable {
    /// TheFence returned a .error response (unknown command, invalid request, etc.)
    case fenceError(step: FailedStep, message: String, interface: Interface?, diagnosticCaptureFailure: String?)
    /// The action executed but returned a non-success ActionResult
    case actionFailed(
        step: FailedStep,
        result: ActionResult,
        expectation: ExpectationResult?,
        interface: Interface?,
        diagnosticCaptureFailure: String?
    )
    /// The execute call threw an exception
    case thrown(step: FailedStep, error: String, interface: Interface?, diagnosticCaptureFailure: String?)

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
        case .fenceError(let step, _, _, _): return step
        case .actionFailed(let step, _, _, _, _): return step
        case .thrown(let step, _, _, _): return step
        }
    }

    public var errorMessage: String {
        switch self {
        case .fenceError(_, let message, _, _): return message
        case .actionFailed(_, let result, _, _, _): return result.message ?? "action failed"
        case .thrown(_, let error, _, _): return error
        }
    }

    public var diagnosticCaptureFailure: String? {
        switch self {
        case .fenceError(_, _, _, let diagnosticCaptureFailure):
            return diagnosticCaptureFailure
        case .actionFailed(_, _, _, _, let diagnosticCaptureFailure):
            return diagnosticCaptureFailure
        case .thrown(_, _, _, let diagnosticCaptureFailure):
            return diagnosticCaptureFailure
        }
    }

    /// Return a copy with the interface snapshot attached.
    func withInterface(_ interface: Interface?) -> PlaybackFailure {
        switch self {
        case .fenceError(let step, let message, _, let diagnosticCaptureFailure):
            return .fenceError(
                step: step,
                message: message,
                interface: interface,
                diagnosticCaptureFailure: diagnosticCaptureFailure
            )
        case .actionFailed(let step, let result, let expectation, _, let diagnosticCaptureFailure):
            return .actionFailed(
                step: step,
                result: result,
                expectation: expectation,
                interface: interface,
                diagnosticCaptureFailure: diagnosticCaptureFailure
            )
        case .thrown(let step, let error, _, let diagnosticCaptureFailure):
            return .thrown(
                step: step,
                error: error,
                interface: interface,
                diagnosticCaptureFailure: diagnosticCaptureFailure
            )
        }
    }

    /// Return a copy with a typed diagnostic-capture failure attached.
    func withDiagnosticCaptureFailure(_ message: String) -> PlaybackFailure {
        switch self {
        case .fenceError(let step, let errorMessage, let interface, _):
            return .fenceError(
                step: step,
                message: errorMessage,
                interface: interface,
                diagnosticCaptureFailure: message
            )
        case .actionFailed(let step, let result, let expectation, let interface, _):
            return .actionFailed(
                step: step,
                result: result,
                expectation: expectation,
                interface: interface,
                diagnosticCaptureFailure: message
            )
        case .thrown(let step, let error, let interface, _):
            return .thrown(
                step: step,
                error: error,
                interface: interface,
                diagnosticCaptureFailure: message
            )
        }
    }
}

import Foundation

/// Product rule for auto-reconnect recovery: retry the selected target at a
/// jittered fixed interval, then stop with operator-facing guidance.
struct AutoReconnectRecoveryPolicy: Equatable {
    let maxAttempts: Int
    let baseInterval: TimeInterval

    private let jitterRatio: TimeInterval = 0.2

    var attempts: Range<Int> {
        0..<maxAttempts
    }

    func sleepDuration() -> TimeInterval {
        baseInterval + Double.random(in: 0...(baseInterval * jitterRatio))
    }

    func terminalFailure(targetDisplayName: String) -> HandoffConnectionError {
        .connectionFailed(terminalFailureMessage(targetDisplayName: targetDisplayName))
    }

    func terminalFailureMessage(targetDisplayName: String) -> String {
        "Auto-reconnect gave up after \(maxAttempts) attempts to \(targetDisplayName). " +
            "Retry the connection or choose a new target."
    }
}

import Foundation

/// Product rule for auto-reconnect recovery:
/// recover only the selected target, back off while it is not visible, and
/// stop after a bounded attempt budget with operator-facing guidance.
struct AutoReconnectRecoveryPolicy: Equatable {
    let maxAttempts: Int
    let baseInterval: TimeInterval

    private let maximumDiscoveryMissExponent = 5
    private let maximumDelay: TimeInterval = 30.0
    private let jitterRatio: TimeInterval = 0.2

    var attempts: Range<Int> {
        0..<maxAttempts
    }

    func delay(afterConsecutiveDiscoveryMisses consecutiveMisses: Int) -> TimeInterval {
        min(
            baseInterval * pow(2.0, Double(min(consecutiveMisses, maximumDiscoveryMissExponent))),
            maximumDelay
        )
    }

    func sleepDuration(afterConsecutiveDiscoveryMisses consecutiveMisses: Int) -> TimeInterval {
        let delay = delay(afterConsecutiveDiscoveryMisses: consecutiveMisses)
        return delay + Double.random(in: 0...(delay * jitterRatio))
    }

    func terminalFailure(targetDisplayName: String) -> TheHandoff.ConnectionError {
        .connectionFailed(terminalFailureMessage(targetDisplayName: targetDisplayName))
    }

    func terminalFailureMessage(targetDisplayName: String) -> String {
        "Auto-reconnect gave up after \(maxAttempts) attempts to \(targetDisplayName). " +
            "Retry the connection or choose a new target."
    }
}

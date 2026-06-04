import Foundation

import TheScore

extension FenceResponse {

    func compactHeistFormatted(_ projection: PublicHeistExecutionProjection) -> String {
        var text = "heist: \(projection.completedSteps) steps in \(projection.totalTimingMs)ms"
        if let failedIndex = projection.failedIndex {
            text += " (failed at \(failedIndex))"
        }
        if let expectations = projection.expectations {
            text += " [expectations: \(expectations.met)/\(expectations.checked)]"
        }
        if let netDelta = projection.netDelta {
            text += " [net: \(Self.compactDeltaKind(netDelta))]"
        }
        if let lastScreenId = projection.finalScreenId {
            text = "\(lastScreenId) | \(text)"
        }
        for row in projection.compactLines {
            var line = "  [\(row.index)] \(row.commandName)"
            if let failureMessage = row.failureMessage {
                line += " -> error: \(failureMessage)"
            }
            else if let delta = row.delta {
                line += " -> \(Self.compactDeltaKind(delta))"
            }
            if let expectation = row.expectation {
                line += expectation.met ? " ✓" : " ✗"
            }
            text += "\n\(line)"
        }
        return text
    }

}

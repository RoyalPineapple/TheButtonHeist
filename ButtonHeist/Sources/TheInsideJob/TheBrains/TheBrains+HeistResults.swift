#if canImport(UIKit)
#if DEBUG
import Foundation
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {
    internal func heistExecutionMessage(
        completedCount: Int,
        abortedAtPath: HeistExecutionPath?
    ) -> String {
        if let abortedAtPath {
            return "Heist execution stopped at \(abortedAtPath) after \(completedCount) executed step(s)"
        }
        return "Heist execution completed \(completedCount) step(s)"
    }

    internal func elapsedMilliseconds(
        since start: RuntimeElapsed.Instant
    ) -> ElapsedMilliseconds {
        RuntimeElapsed.milliseconds(since: start)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

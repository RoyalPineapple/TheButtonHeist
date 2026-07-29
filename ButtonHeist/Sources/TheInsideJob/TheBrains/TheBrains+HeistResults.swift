#if canImport(UIKit)
#if DEBUG
import Foundation
@_spi(ButtonHeistInternals) import TheScore

extension TheBrains {
    internal func elapsedMilliseconds(
        since start: RuntimeElapsed.Instant
    ) -> ElapsedMilliseconds {
        RuntimeElapsed.milliseconds(since: start)
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

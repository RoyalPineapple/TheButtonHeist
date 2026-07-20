#if canImport(UIKit)
#if DEBUG
import Foundation
import TheScore

enum RuntimeElapsed {
    typealias Instant = ContinuousClock.Instant

    static var now: Instant {
        ContinuousClock.now
    }

    static func seconds(
        since start: Instant,
        endedAt end: Instant = now
    ) -> Double {
        start.duration(to: end) / .seconds(1)
    }

    static func milliseconds(
        since start: Instant,
        endedAt end: Instant = now
    ) -> ElapsedMilliseconds {
        let duration = start.duration(to: end)
        guard duration >= .zero else {
            preconditionFailure("runtime elapsed measurement ended before it started")
        }
        let rawMilliseconds = duration / .milliseconds(1)
        guard rawMilliseconds <= Double(Int.max) else {
            preconditionFailure("runtime elapsed measurement exceeds Int capacity")
        }
        return admit(milliseconds: Int(rawMilliseconds))
    }

    static func admit(milliseconds: Int) -> ElapsedMilliseconds {
        do {
            return try ElapsedMilliseconds(validatingMilliseconds: milliseconds)
        } catch {
            preconditionFailure("runtime elapsed measurement must not be negative")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

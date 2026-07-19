import Foundation
import Testing

@testable import TheInsideJob

struct MessageRateLimiterTests {

    @Test func `accepts through the configured one-second window limit`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.admitMessage(at: now) == .accept)
        #expect(limiter.admitMessage(at: now) == .accept)
        #expect(limiter.admitMessage(at: now) == .drop(shouldNotify: true))
    }

    @Test func `notifies only once while the same window remains limited`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.admitMessage(at: now) == .accept)
        #expect(limiter.admitMessage(at: now) == .accept)

        #expect(limiter.admitMessage(at: now) == .drop(shouldNotify: true))

        #expect(limiter.admitMessage(at: now) == .drop(shouldNotify: false))
    }

    @Test func `resets notification after the active window rolls forward`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let firstWindow = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.admitMessage(at: firstWindow) == .accept)
        #expect(limiter.admitMessage(at: firstWindow) == .accept)
        #expect(limiter.admitMessage(at: firstWindow) == .drop(shouldNotify: true))

        let nextWindow = firstWindow.addingTimeInterval(1.1)
        #expect(limiter.admitMessage(at: nextWindow) == .accept)
        #expect(limiter.admitMessage(at: nextWindow) == .accept)

        #expect(limiter.admitMessage(at: nextWindow) == .drop(shouldNotify: true))
    }

    @Test func `drops timestamps exactly one second old from the active window`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let first = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.admitMessage(at: first) == .accept)
        #expect(limiter.admitMessage(at: first.addingTimeInterval(0.5)) == .accept)
        #expect(limiter.admitMessage(at: first.addingTimeInterval(1.0)) == .accept)
        #expect(limiter.admitMessage(at: first.addingTimeInterval(1.0)) == .drop(shouldNotify: true))
    }
}

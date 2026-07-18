import Foundation
import Testing

@testable import TheInsideJob

struct MessageRateLimiterTests {

    @Test func `accepts through the configured one-second window limit`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.recordMessage(at: now) == false)
        #expect(limiter.recordMessage(at: now) == false)
        #expect(limiter.recordMessage(at: now) == true)
    }

    @Test func `notifies only once while the same window remains limited`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let now = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.recordMessage(at: now) == false)
        #expect(limiter.recordMessage(at: now) == false)

        #expect(limiter.recordMessage(at: now) == true)
        #expect(limiter.markNotifiedIfNeeded() == true)

        #expect(limiter.recordMessage(at: now) == true)
        #expect(limiter.markNotifiedIfNeeded() == false)
    }

    @Test func `resets notification after the active window rolls forward`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let firstWindow = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.recordMessage(at: firstWindow) == false)
        #expect(limiter.recordMessage(at: firstWindow) == false)
        #expect(limiter.recordMessage(at: firstWindow) == true)
        #expect(limiter.markNotifiedIfNeeded() == true)

        let nextWindow = firstWindow.addingTimeInterval(1.1)
        #expect(limiter.recordMessage(at: nextWindow) == false)
        #expect(limiter.recordMessage(at: nextWindow) == false)

        #expect(limiter.recordMessage(at: nextWindow) == true)
        #expect(limiter.markNotifiedIfNeeded() == true)
    }

    @Test func `drops timestamps exactly one second old from the active window`() {
        var limiter = ClientAdmission.RateLimiter(maxMessagesPerSecond: 2)
        let first = Date(timeIntervalSince1970: 1_000)

        #expect(limiter.recordMessage(at: first) == false)
        #expect(limiter.recordMessage(at: first.addingTimeInterval(0.5)) == false)
        #expect(limiter.recordMessage(at: first.addingTimeInterval(1.0)) == false)
        #expect(limiter.recordMessage(at: first.addingTimeInterval(1.0)) == true)
    }
}

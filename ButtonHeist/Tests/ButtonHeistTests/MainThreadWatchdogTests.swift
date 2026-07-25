import XCTest

@_spi(ButtonHeistTooling) @testable import ButtonHeist
@_spi(ButtonHeistInternals) import TheScore

final class MainThreadWatchdogTests: XCTestCase {
    func testConfigurationAdmitsPositiveFiniteDurationsWithoutProductCap() throws {
        let settings = try TheFence.MainThreadWatchdogSettings(
            initialDelay: 10_000,
            cadence: 20_000,
            probeResponseTimeout: 30_000,
            responsivenessTimeout: 40_000,
            workTimeout: 50_000
        )

        XCTAssertEqual(settings.initialDelay, 10_000)
        XCTAssertEqual(settings.workTimeout, 50_000)
        XCTAssertThrowsError(try TheFence.MainThreadWatchdogSettings(
            initialDelay: 0,
            cadence: 1,
            probeResponseTimeout: 1,
            responsivenessTimeout: 1,
            workTimeout: 1
        ))
        XCTAssertThrowsError(try TheFence.MainThreadWatchdogSettings(
            initialDelay: 1,
            cadence: .infinity,
            probeResponseTimeout: 1,
            responsivenessTimeout: 1,
            workTimeout: 1
        ))
        XCTAssertThrowsError(try TheFence.MainThreadWatchdogSettings(
            initialDelay: .greatestFiniteMagnitude,
            cadence: 1,
            probeResponseTimeout: 1,
            responsivenessTimeout: 1,
            workTimeout: 1
        ))
        XCTAssertThrowsError(try TheFence.MainThreadWatchdogSettings(
            initialDelay: 1,
            cadence: 1,
            probeResponseTimeout: 1,
            responsivenessTimeout: .greatestFiniteMagnitude,
            workTimeout: 1
        ))
    }

    func testOnlyOffMainControlMessagesSkipWatchdog() throws {
        let probe = try XCTUnwrap(MainThreadProbeRequest.admit(
            responsivenessTimeoutMilliseconds: 1,
            workTimeoutMilliseconds: 1
        ))
        let token = try SessionAuthToken(validating: "test-token")
        let excluded: [ClientMessage] = [
            .clientHello,
            .authenticate(AuthenticatePayload(token: token)),
            .ping,
            .mainThreadProbe(probe),
        ]

        XCTAssertTrue(excluded.allSatisfy { !$0.requiresMainThread })
        XCTAssertTrue(ClientMessage.status.requiresMainThread)
    }

    func testLivenessErrorsHaveDistinctPublicFailureCodes() throws {
        let cases: [(FenceError, KnownFailureCode)] = [
            (.mainThreadUnresponsive, .requestMainThreadUnresponsive),
            (.mainThreadWorkTimedOut, .requestMainThreadWorkTimedOut),
        ]

        for (error, code) in cases {
            let failure = try XCTUnwrap(FenceResponse.failure(error).diagnosticFailure)
            XCTAssertEqual(failure.failureCode, code)
            XCTAssertEqual(failure.phase, .request)
            XCTAssertTrue(failure.retryable)
        }
    }

    @ButtonHeistActor
    func testTerminalProbeOutcomesFailOriginalRequestWithDistinctErrors() async throws {
        let cases: [(MainThreadProbeOutcome, KnownFailureCode)] = [
            (.mainThreadUnresponsive, .requestMainThreadUnresponsive),
            (.workTimedOut, .requestMainThreadWorkTimedOut),
        ]
        for (outcome, failureCode) in cases {
            try await assertTerminalProbe(outcome, failureCode: failureCode)
        }
    }

    @ButtonHeistActor
    private func assertTerminalProbe(
        _ outcome: MainThreadProbeOutcome,
        failureCode: KnownFailureCode
    ) async throws {
        let schedule = ManualWatchdogSchedule()
        let (fence, connection) = try connectedFence(schedule: schedule)
        let originalSent = expectation(description: "original request sent")
        let probeSent = expectation(description: "probe sent")
        connection.responseScript = { message in
            switch message {
            case .requestInterface:
                originalSent.fulfill()
                return nil
            case .mainThreadProbe(let request):
                XCTAssertEqual(request.responsivenessTimeoutMilliseconds, 3_000)
                XCTAssertEqual(request.workTimeoutMilliseconds, 4_000)
                probeSent.fulfill()
                return .mainThreadProbe(MainThreadProbeResponse(outcome: outcome))
            default:
                return nil
            }
        }

        let request = Task { @ButtonHeistActor in
            try await fence.sendAndAwaitInterface(.requestInterface(.init()), timeout: 60)
        }
        await fulfillment(of: [originalSent], timeout: 1)
        schedule.advance()
        await fulfillment(of: [probeSent], timeout: 1)

        do {
            _ = try await request.value
            XCTFail("Expected \(outcome.rawValue)")
        } catch let error as FenceError {
            XCTAssertEqual(
                error.failureDescriptor.details.code,
                failureCode
            )
        } catch {
            XCTFail("Expected \(outcome.rawValue), got \(error)")
        }
    }

    @ButtonHeistActor
    func testResponsiveProbeKeepsWaitingAtConfiguredCadence() async throws {
        let schedule = ManualWatchdogSchedule()
        let (fence, connection) = try connectedFence(schedule: schedule)
        let originalSent = expectation(description: "original request sent")
        let probesSent = expectation(description: "two probes sent")
        probesSent.expectedFulfillmentCount = 2
        var originalRequestID: RequestID?
        connection.responseScript = { message in
            switch message {
            case .requestInterface:
                originalRequestID = connection.sent.last?.1
                originalSent.fulfill()
                return nil
            case .mainThreadProbe:
                probesSent.fulfill()
                return .mainThreadProbe(MainThreadProbeResponse(outcome: .responsive))
            default:
                return nil
            }
        }

        let request = Task { @ButtonHeistActor in
            try await fence.sendAndAwaitInterface(.requestInterface(.init()), timeout: 60)
        }
        await fulfillment(of: [originalSent], timeout: 1)
        schedule.advance()
        schedule.advance()
        await fulfillment(of: [probesSent], timeout: 1)

        connection.onEvent?(.message(
            .interface(Interface(timestamp: Date(), tree: [])),
            requestId: try XCTUnwrap(originalRequestID)
        ))
        _ = try await request.value
    }

    @ButtonHeistActor
    func testCompletingOriginalRequestCancelsAndRemovesProbeWaiter() async throws {
        let schedule = ManualWatchdogSchedule()
        let (fence, connection) = try connectedFence(schedule: schedule)
        let originalSent = expectation(description: "original request sent")
        let probeSent = expectation(description: "probe sent")
        var originalRequestID: RequestID?
        var probeRequestID: RequestID?
        connection.responseScript = { message in
            switch message {
            case .requestInterface:
                originalRequestID = connection.sent.last?.1
                originalSent.fulfill()
            case .mainThreadProbe:
                probeRequestID = connection.sent.last?.1
                probeSent.fulfill()
            default:
                break
            }
            return nil
        }

        let request = Task { @ButtonHeistActor in
            try await fence.sendAndAwaitInterface(.requestInterface(.init()), timeout: 60)
        }
        await fulfillment(of: [originalSent], timeout: 1)
        schedule.advance()
        await fulfillment(of: [probeSent], timeout: 1)

        connection.onEvent?(.message(
            .interface(Interface(timestamp: Date(), tree: [])),
            requestId: try XCTUnwrap(originalRequestID)
        ))
        _ = try await request.value

        let releasedProbeRequestID = try XCTUnwrap(probeRequestID)
        let replacementRegistered = expectation(description: "probe request ID released")
        let replacement = Task { @ButtonHeistActor in
            try await fence.pendingRequests.waitForResponse(
                .mainThreadProbe,
                requestId: releasedProbeRequestID,
                timeout: 5,
                afterRegister: { replacementRegistered.fulfill() }
            )
        }
        await fulfillment(of: [replacementRegistered], timeout: 1)
        XCTAssertTrue(fence.pendingRequests.resolveTransientResponse(
            .mainThreadProbe(MainThreadProbeResponse(outcome: .responsive)),
            requestId: releasedProbeRequestID
        ))
        _ = try await replacement.value
    }

    @ButtonHeistActor
    private func connectedFence(
        schedule: ManualWatchdogSchedule
    ) throws -> (TheFence, MockConnection) {
        var configuration = TheFence.Configuration()
        configuration.mainThreadWatchdog = .enabled(try .init(
            initialDelay: 1,
            cadence: 2,
            probeResponseTimeout: 5,
            responsivenessTimeout: 3,
            workTimeout: 4
        ))
        let (fence, connection) = makeConnectedFence(configuration: configuration)
        fence.sleepForMainThreadWatchdog = { _ in await schedule.sleep() }
        fence.handoff.connect(to: TheFenceFixtures.testDevice)
        return (fence, connection)
    }
}

private final class ManualWatchdogSchedule: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() {
        (stream, continuation) = AsyncStream.makeStream()
    }

    func sleep() async -> Bool {
        for await _ in stream {
            return !Task.isCancelled
        }
        return false
    }

    func advance() {
        continuation.yield()
    }
}

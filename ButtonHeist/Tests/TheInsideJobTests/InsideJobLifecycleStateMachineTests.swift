#if canImport(UIKit)
import XCTest

@testable import TheInsideJob

@MainActor
final class InsideJobLifecycleStateMachineTests: XCTestCase {
    func testStartTransitionCarriesTransportWithoutClaimingSendability() {
        let transport = ServerTransport()
        let attempt = TheInsideJob.InsideJobStartAttempt(id: UUID(), transport: transport)

        let change = InsideJobLifecycleMachine().advance(
            .stopped,
            with: .startRequested(attempt, idleTimerBaseline: false)
        )

        guard case .changed(to: .starting(let currentAttempt), effects: let effects) = change,
              effects.count == 1,
              case .startTransport(let request) = effects[0] else {
            return XCTFail("Expected stopped to transition to starting")
        }
        XCTAssertEqual(currentAttempt, attempt)
        XCTAssertEqual(request.id, attempt.id)
        XCTAssertTrue(request.transport === transport)
    }

    func testLifecycleMachineSourceKeepsTransportStateOnMainActor() throws {
        let source = try String(contentsOf: lifecycleSourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("struct InsideJobLifecycleMachine: @MainActor SimpleStateMachine"))
        XCTAssertFalse(source.contains("@unchecked Sendable"))
        [
            "enum ServerPhase: Equatable {",
            "struct InsideJobRuntimeResources: Equatable {",
            "struct InsideJobStartAttempt: Equatable {",
            "struct InsideJobSuspension: Equatable {",
            "struct InsideJobTransportStartRequest: Equatable {",
            "enum Event: Equatable {",
            "enum Effect: Equatable {",
        ].forEach { declaration in
            XCTAssertTrue(source.contains(declaration), "Missing declaration: \(declaration)")
        }
    }

    private var lifecycleSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/TheInsideJob/InsideJobLifecycleState.swift")
    }
}
#endif

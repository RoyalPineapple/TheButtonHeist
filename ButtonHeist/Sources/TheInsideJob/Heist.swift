#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

// Package contract: app-hosted tests import TheInsideJob and assert against
// execution receipt types from TheScore. This intentional re-export is
// allowlisted by scripts/check-buttonheist-import-contract.sh.
@_exported import TheScore

/// Completed in-process heist execution receipt for app and UI tests.
///
/// Constructing a `Heist` builds or accepts a runtime-validated `HeistPlan`,
/// runs it directly against `TheInsideJob` in the app process, and then exposes
/// the execution result for assertions and reporting.
public struct Heist: Sendable {
    public let result: HeistExecutionResult

    @MainActor
    public init(
        _ plan: HeistPlan,
        argument: HeistArgument = .none
    ) async throws {
        self.result = try await Self.execute(plan, argument: argument, runtime: .shared)
    }

    @MainActor
    init(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        runtime: InAppHeistRuntime
    ) async throws {
        self.result = try await Self.execute(plan, argument: argument, runtime: runtime)
    }

    @MainActor
    public init(
        @HeistBuilder _ content: () throws -> some HeistContent
    ) async throws {
        let plan = try HeistPlan(content)
        self.result = try await Self.execute(plan, argument: .none, runtime: .shared)
    }

    @MainActor
    init(
        runtime: InAppHeistRuntime,
        @HeistBuilder _ content: () throws -> some HeistContent
    ) async throws {
        let plan = try HeistPlan(content)
        self.result = try await Self.execute(plan, argument: .none, runtime: runtime)
    }

    @MainActor
    public init(
        _ input: String,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: (HeistReferenceName) throws -> some HeistContent
    ) async throws {
        let plan = try HeistPlan(parameter: parameter, content)
        self.result = try await Self.execute(
            plan,
            argument: .string(input),
            runtime: .shared
        )
    }

    @MainActor
    init(
        _ input: String,
        parameter: HeistReferenceName = "input",
        runtime: InAppHeistRuntime,
        @HeistBuilder _ content: (HeistReferenceName) throws -> some HeistContent
    ) async throws {
        let plan = try HeistPlan(parameter: parameter, content)
        self.result = try await Self.execute(
            plan,
            argument: .string(input),
            runtime: runtime
        )
    }

    @MainActor
    public init(
        _ input: AccessibilityTarget,
        parameter: HeistReferenceName = "input",
        @HeistBuilder _ content: (AccessibilityTarget) throws -> some HeistContent
    ) async throws {
        try await self.init(
            input,
            parameter: parameter,
            runtime: .shared,
            content
        )
    }

    @MainActor
    init(
        _ input: AccessibilityTarget,
        parameter: HeistReferenceName = "input",
        runtime: InAppHeistRuntime,
        @HeistBuilder _ content: (AccessibilityTarget) throws -> some HeistContent
    ) async throws {
        let plan = try HeistPlan(targetParameter: parameter, content)
        self.result = try await Self.execute(
            plan,
            argument: .accessibilityTarget(input),
            runtime: runtime
        )
    }

    @MainActor
    private static func execute(
        _ plan: HeistPlan,
        argument: HeistArgument,
        runtime: InAppHeistRuntime
    ) async throws -> HeistExecutionResult {
        let actionResult = await runtime.execute(plan, argument)
        guard case .heistExecution(let result) = actionResult.payload else {
            throw RuntimeError(actionResult: actionResult)
        }
        HeistReceiptRecorder.recordIfEnabled(result, plan: plan)
        guard !result.isFailure else {
            throw Failure(result)
        }
        return result
    }
}

public extension Heist {
    struct Failure: Error, Sendable, LocalizedError, CustomStringConvertible {
        public let failedStepPath: String
        public let failedStepKind: HeistExecutionStepKind
        public let message: String
        public let diagnostic: String?
        public let result: HeistExecutionResult

        public init(_ result: HeistExecutionResult) {
            let failedStep = result.firstFailedStep
            self.failedStepPath = failedStep?.path ?? "$"
            self.failedStepKind = failedStep?.kind ?? .fail
            self.message = failedStep?.reportFailureMessage
                ?? failedStep?.reportMessage
                ?? "heist failed"
            self.diagnostic = failedStep?.failure.map(Self.diagnostic)
            self.result = result
        }

        public var errorDescription: String? { description }

        public var description: String {
            var parts = [
                "Heist failed",
                "path=\(failedStepPath)",
                "kind=\(failedStepKind.rawValue)",
                "message=\(message)",
            ]
            if let diagnostic {
                parts.append("diagnostic=\(diagnostic)")
            }
            var text = parts.joined(separator: " ")
            if let screenshot = result.failureScreenshotSummary {
                text += "\n\(screenshot)"
            }
            if let interfaceDump = result.failureInterfaceDump(elementLimit: .max) {
                text += "\n\(interfaceDump)"
            }
            return text
        }

        private static func diagnostic(_ failure: HeistFailureDetail) -> String {
            [
                "category=\(failure.category.rawValue)",
                "contract=\(failure.contract)",
                "observed=\(failure.observed)",
                failure.expected.map { "expected=\($0)" },
            ].compactMap { $0 }.joined(separator: " ")
        }
    }

    private struct RuntimeError: Error, Sendable, LocalizedError, CustomStringConvertible {
        let actionResult: ActionResult

        var errorDescription: String? { description }

        var description: String {
            let message = actionResult.message ?? "heist execution did not return a heist result"
            return "Heist runtime failed: \(message)"
        }
    }
}

struct InAppHeistRuntime {
    let execute: @MainActor (HeistPlan, HeistArgument) async -> ActionResult

    @MainActor
    static var shared: InAppHeistRuntime {
        insideJob(.shared)
    }

    @MainActor
    static func insideJob(_ job: TheInsideJob) -> InAppHeistRuntime {
        InAppHeistRuntime { plan, argument in
            await job.executeInAppHeist(plan, argument: argument)
        }
    }
}

@MainActor
extension TheInsideJob {
    func executeInAppHeist(
        _ plan: HeistPlan,
        argument: HeistArgument = .none
    ) async -> ActionResult {
        let shouldRestoreRuntime = !brains.semanticObservationIsActive
        if shouldRestoreRuntime {
            tripwire.startPulse()
            brains.startSemanticObservation()
            brains.safecracker.startKeyboardObservation()
        }
        defer {
            if shouldRestoreRuntime {
                brains.stopSemanticObservation()
                tripwire.stopPulse()
                brains.safecracker.stopKeyboardObservation()
            }
        }
        // Each top-level heist starts from a fresh live visible state. This
        // keeps conditionals, waits, and first actions from inheriting the
        // previous run's settled semantic world when the app is already on
        // another screen.
        brains.stash.clearInterfaceForHeistBootstrap()
        _ = await brains.interactionObservation.observeVisibleState(
            timeout: SemanticObservationTiming.defaultTimeout
        )
        let result = await brains.executeHeistPlan(plan, argument: argument)
        if shouldRestoreRuntime {
            _ = await tripwire.waitForAllClear(timeout: SemanticObservationTiming.defaultTimeout)
        }
        return result
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

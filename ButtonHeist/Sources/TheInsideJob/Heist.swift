#if canImport(UIKit)
#if DEBUG
import Foundation
import ThePlans

// Package contract: app-hosted tests import TheInsideJob and assert against
// execution result types from TheScore. This intentional re-export is
// allowlisted by scripts/check-buttonheist-import-contract.sh.
@_exported import TheScore

/// Completed in-process heist result for app and UI tests.
///
/// Constructing a `Heist` builds or accepts a runtime-validated `HeistPlan`,
/// runs it directly against `TheInsideJob` in the app process, and then exposes
/// the result for assertions and reporting.
public struct Heist: Sendable {
    public let result: HeistResult

    @MainActor
    public init(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: HeistTimeout = .default
    ) async throws {
        self.result = try await Self.execute(
            plan,
            argument: argument,
            timeout: timeout
        )
    }

    @MainActor
    public init(
        timeout: HeistTimeout = .default,
        @HeistBuilder _ content: () throws -> HeistContent
    ) async throws {
        let plan = try HeistPlan(content)
        self.result = try await Self.execute(
            plan,
            argument: .none,
            timeout: timeout
        )
    }

    @MainActor
    public init(
        _ input: String,
        parameter: HeistReferenceName = "input",
        timeout: HeistTimeout = .default,
        @HeistBuilder _ content: (HeistReferenceName) throws -> HeistContent
    ) async throws {
        let plan = try HeistPlan(parameter: parameter, content)
        self.result = try await Self.execute(
            plan,
            argument: .string(input),
            timeout: timeout
        )
    }

    @MainActor
    public init(
        _ input: AccessibilityTarget,
        parameter: HeistReferenceName = "input",
        timeout: HeistTimeout = .default,
        @HeistBuilder _ content: (AccessibilityTarget) throws -> HeistContent
    ) async throws {
        let plan = try HeistPlan(targetParameter: parameter, content)
        self.result = try await Self.execute(
            plan,
            argument: .accessibilityTarget(input),
            timeout: timeout
        )
    }

    @MainActor
    private static func execute(
        _ plan: HeistPlan,
        argument: HeistArgument,
        timeout: HeistTimeout
    ) async throws -> HeistResult {
        let result = try await TheInsideJob.shared.executeInAppHeist(
            plan,
            argument: argument,
            timeout: timeout
        )
        HeistResultRecording.recordIfEnabled(result, plan: plan)
        guard !result.isFailure else {
            throw Failure(result)
        }
        return result
    }
}

public extension Heist {
    struct Failure: Error, Sendable, LocalizedError, CustomStringConvertible {
        public let failedStepPath: HeistExecutionPath
        public let failedStepKind: HeistExecutionStepKind
        public let message: String
        public let diagnostic: String?
        public let result: HeistResult

        public init(_ result: HeistResult) {
            let failedStep = result.firstFailedStep
            self.failedStepPath = failedStep?.path ?? "$"
            self.failedStepKind = failedStep?.kind ?? .fail
            self.message = failedStep?.reportActionResult?.message
                ?? failedStep?.reportMessage
                ?? "heist failed"
            self.diagnostic = failedStep?.failure.map(Self.diagnostic)
            self.result = result
        }

        public var errorDescription: String? { description }

        public var description: String {
            var lines = [
                "Heist failed at \(failedStepPath) (\(failedStepKind.rawValue))",
                "Cause: \(message)",
            ]
            if let failure = result.firstFailedStep?.failure {
                if !failure.contract.isEmpty,
                   failure.contract != message {
                    lines.append("Contract: \(failure.contract)")
                }
                if let expected = failure.expected, !expected.isEmpty {
                    lines.append("\(expectedLabel(for: failure)): \(expected)")
                }
            }
            if let screenshot = result.failureScreenshotSummary {
                lines.append(screenshot)
            }
            if let interfaceDump = result.failureInterfaceDump(elementLimit: .max) {
                lines.append(interfaceDump)
            }
            return lines.joined(separator: "\n")
        }

        private func expectedLabel(for failure: HeistFailureDetail) -> String {
            guard failedStepKind == .action else { return "Expected" }
            switch failure.category {
            case .action, .targetResolution:
                return "Target"
            case .explicitFailure,
                 .internalInvariant,
                 .invocation,
                 .loop,
                 .runtimeUnavailable,
                 .timeout,
                 .validation,
                 .expectation,
                 .wait:
                return "Expected"
            }
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

}

@MainActor
extension TheInsideJob {
    func executeInAppHeist(
        _ plan: HeistPlan,
        argument: HeistArgument = .none,
        timeout: HeistTimeout = .default
    ) async throws -> HeistResult {
        switch await brains.executeInAppRequest({ [self] in
            await executeAdmittedInAppHeist(
                plan,
                argument: argument,
                timeout: timeout
            )
        }) {
        case .completed(let result):
            return try result.get()
        case .cancelled:
            throw HeistExecution.Failure.submissionCancelled
        case .rejected(.busy):
            throw HeistExecution.Failure.interactionQueueFull
        case .rejected(.cleanupTimedOut):
            throw HeistExecution.Failure.cleanupTimedOut
        case .rejected(.stopping):
            throw HeistExecution.Failure.runtimeStopping
        }
    }

    private func executeAdmittedInAppHeist(
        _ plan: HeistPlan,
        argument: HeistArgument,
        timeout: HeistTimeout
    ) async -> Result<HeistResult, HeistExecution.Failure> {
        let shouldRestoreRuntime = !brains.semanticObservationIsActive
        if shouldRestoreRuntime {
            tripwire.startPulse()
            brains.vault.semanticObservationStream.start()
            brains.safecracker.startKeyboardObservation()
        }
        defer {
            if shouldRestoreRuntime {
                brains.vault.semanticObservationStream.stop()
                tripwire.stopPulse()
                brains.safecracker.stopKeyboardObservation()
            }
        }
        // Each top-level heist starts from a fresh live visible state. This
        // keeps conditionals, waits, and first actions from inheriting the
        // previous run's settled semantic world when the app is already on
        // another screen.
        await brains.vault.resetInterfaceForLifecycle()
        guard case .committed = await brains.vault.semanticObservationStream
            .refreshedVisibleObservation(boundary: .cancellation) else {
            return .failure(.accessibilityTreeUnavailable)
        }
        let result = await brains.executeHeistPlan(
            plan,
            argument: argument,
            timeout: timeout
        )
        return result
    }
}

#endif // DEBUG
#endif // canImport(UIKit)

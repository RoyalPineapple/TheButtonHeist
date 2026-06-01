import Foundation

import TheScore

/// Level of detail for interface responses.
public enum InterfaceDetail: String, CaseIterable, Sendable {
    case summary
    case full
}

public struct ScreenshotResponseOptions: Sendable, Equatable {
    public let includeInterface: Bool

    public init(includeInterface: Bool = false) {
        self.includeInterface = includeInterface
    }
}

extension HeistExecutionStepResult {
    func actionResponse(command: TheFence.Command, step: HeistStep) -> FenceResponse? {
        guard skipped == nil else { return nil }
        guard let finalResult = expectationActionResult ?? actionResult else {
            switch step {
            case .action, .wait:
                return .error("typed heist step produced no action result")
            case .conditional, .waitForCases, .repeatCount, .repeatUntil, .warn, .fail:
                return nil
            }
        }
        return .action(
            command: command,
            result: finalResult,
            expectation: expectation ?? step.expectedPredicate?.validate(against: finalResult)
        )
    }

    func finalActionResult() -> ActionResult? {
        expectationActionResult ?? actionResult
    }

    func expectationResult(for step: HeistStep) -> ExpectationResult? {
        if let expectation { return expectation }
        guard let plannedExpectation = step.expectedPredicate else { return nil }
        return finalActionResult().map { plannedExpectation.validate(against: $0) }
    }

    func expectationCounted(for step: HeistStep) -> Bool {
        expectationResult(for: step)?.predicate != nil
    }

    func expectationMet(for step: HeistStep) -> Bool? {
        guard expectationCounted(for: step) else { return nil }
        return expectationResult(for: step)?.met
    }
}

private extension HeistStep {
    var expectedPredicate: AccessibilityPredicate? {
        switch self {
        case .action(let step):
            return step.expectation?.predicate
        case .wait(let step):
            return step.predicate
        case .conditional, .waitForCases, .repeatCount, .repeatUntil:
            return nil
        case .warn, .fail:
            return nil
        }
    }
}

extension HeistExecutionResult {
    var completedStepCount: Int {
        flattenedStepResults.count { !$0.isSkipped }
    }

    var stoppedFailedIndex: Int? {
        failedIndex ?? steps.first { $0.stopsHeist }?.index
    }

    func expectationsChecked(steps plannedSteps: [HeistStep]) -> Int {
        executedStepPairs(plannedSteps: plannedSteps).count { pair in
            pair.result.expectationCounted(for: pair.plannedStep)
        }
    }

    func expectationsMet(steps plannedSteps: [HeistStep]) -> Int {
        executedStepPairs(plannedSteps: plannedSteps).count { pair in
            pair.result.expectationMet(for: pair.plannedStep) == true
        }
    }

    var flattenedStepResults: [HeistExecutionStepResult] {
        steps.flatMap(\.flattenedWithChildren)
    }

    func executedStepPairs(plannedSteps: [HeistStep]) -> [HeistExecutedStepPair] {
        Self.executedStepPairs(plannedSteps: plannedSteps, outcomes: steps)
    }

    private static func executedStepPairs(
        plannedSteps: [HeistStep],
        outcomes: [HeistExecutionStepResult]
    ) -> [HeistExecutedStepPair] {
        var pairs: [HeistExecutedStepPair] = []
        for outcome in outcomes {
            guard plannedSteps.indices.contains(outcome.index) else { continue }
            let plannedStep = plannedSteps[outcome.index]
            pairs.append(HeistExecutedStepPair(plannedStep: plannedStep, result: outcome))
            guard
                let childResults = outcome.childResults,
                let childSteps = plannedStep.childSteps(for: outcome)
            else { continue }
            pairs.append(contentsOf: executedStepPairs(plannedSteps: childSteps, outcomes: childResults))
        }
        return pairs
    }
}

struct HeistExecutedStepPair {
    let plannedStep: HeistStep
    let result: HeistExecutionStepResult
}

extension HeistExecutionStepResult {
    var flattenedWithChildren: [HeistExecutionStepResult] {
        [self] + (childResults?.flatMap(\.flattenedWithChildren) ?? [])
    }
}

extension HeistStep {
    func childSteps(for outcome: HeistExecutionStepResult) -> [HeistStep]? {
        switch self {
        case .conditional(let conditional):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex {
                return conditional.cases[safe: selectedCaseIndex]?.steps
            }
            if outcome.caseSelection?.elseRan == true {
                return conditional.elseSteps
            }
            return nil
        case .waitForCases(let waitForCases):
            if let selectedCaseIndex = outcome.caseSelection?.selectedCaseIndex {
                return waitForCases.cases[safe: selectedCaseIndex]?.steps
            }
            if outcome.caseSelection?.elseRan == true {
                return waitForCases.elseSteps
            }
            return nil
        case .repeatCount(let repeatCount):
            return repeatedSteps(repeatCount.steps, iterationCount: outcome.repeatResult?.iterationCount ?? 0)
        case .repeatUntil(let repeatUntil):
            return repeatedSteps(repeatUntil.steps, iterationCount: outcome.repeatResult?.iterationCount ?? 0)
        case .action, .wait, .warn, .fail:
            return nil
        }
    }

    func repeatedSteps(_ steps: [HeistStep], iterationCount: Int) -> [HeistStep]? {
        guard iterationCount > 0 else { return nil }
        return Array(repeating: steps, count: iterationCount).flatMap { $0 }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum SessionConnectionPhase: String, Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case failed
}

public struct SessionDevicePayload: Sendable, Equatable {
    public let deviceName: String
    public let appName: String
    public let connectionType: ConnectionScope
    public let shortId: String?

    public init(
        deviceName: String,
        appName: String,
        connectionType: ConnectionScope,
        shortId: String?
    ) {
        self.deviceName = deviceName
        self.appName = appName
        self.connectionType = connectionType
        self.shortId = shortId
    }
}

public struct SessionFailurePayload: Sendable, Equatable {
    public let errorCode: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let message: String?
    public let hint: String?

    public init(
        errorCode: String,
        phase: FailurePhase,
        retryable: Bool,
        message: String?,
        hint: String?
    ) {
        self.errorCode = errorCode
        self.phase = phase
        self.retryable = retryable
        self.message = message
        self.hint = hint
    }
}

public struct SessionStatePayload: Sendable, Equatable {
    public let connected: Bool
    public let phase: SessionConnectionPhase
    public let device: SessionDevicePayload?
    public let actionTimeoutSeconds: TimeInterval
    public let longActionTimeoutSeconds: TimeInterval
    public let lastFailure: SessionFailurePayload?

    public init(
        connected: Bool,
        phase: SessionConnectionPhase,
        device: SessionDevicePayload?,
        actionTimeoutSeconds: TimeInterval,
        longActionTimeoutSeconds: TimeInterval,
        lastFailure: SessionFailurePayload?
    ) {
        self.connected = connected
        self.phase = phase
        self.device = device
        self.actionTimeoutSeconds = actionTimeoutSeconds
        self.longActionTimeoutSeconds = longActionTimeoutSeconds
        self.lastFailure = lastFailure
    }
}

enum FenceRequestErrorCode {
    static let missingTarget = "request.missing_target"
}

/// Typed response from TheFence command execution.
///
/// Cases marked `…Data` carry the raw payload in memory (base64-encoded).
/// Screenshot data is opt-in.
/// Cases without the `Data` suffix carry a filesystem path where the artifact
/// has been written.
public enum FenceResponse {
    case ok(message: String)
    case error(String, details: FailureDetails? = nil)
    case status(connected: Bool, deviceName: String?)
    case pong(PongPayload)
    case devices([DiscoveredDevice])
    case interface(Interface, detail: InterfaceDetail = .summary)
    case action(command: TheFence.Command, result: ActionResult, expectation: ExpectationResult? = nil)
    /// Screenshot written to disk. `path` is the resolved filesystem location.
    case screenshot(path: String, payload: ScreenPayload, options: ScreenshotResponseOptions = ScreenshotResponseOptions())
    /// Screenshot held in memory as base64 PNG. Returned only when inline data
    /// is explicitly requested.
    case screenshotData(payload: ScreenPayload, options: ScreenshotResponseOptions = ScreenshotResponseOptions())
    case heistExecution(
        plan: HeistPlan,
        result: HeistExecutionResult,
        accessibilityTrace: AccessibilityTrace? = nil
    )
    case sessionState(payload: SessionStatePayload)
    case targets([String: TargetConfig], defaultTarget: String?)
    case heistStarted
    case heistStopped(path: String, stepCount: Int)
    case heistPlayback(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure? = nil, report: HeistPlaybackReport? = nil)

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    var actionResult: ActionResult? {
        if case .action(_, let result, _) = self { return result }
        return nil
    }

    /// Builds an error response with typed metadata when the error belongs to TheFence.
    public static func failure(_ error: Error) -> FenceResponse {
        if let fenceError = error as? FenceError {
            return .error(fenceError.coreMessage, details: fenceError.failureDetails)
        }
        return .error(error.displayMessage)
    }

    /// Whether callers should treat this response as a failed command.
    public var isFailure: Bool {
        switch self {
        case .error:
            return true
        case .action(_, let result, let expectation):
            return !result.success || expectation?.met == false
        case .heistExecution(_, let result, _):
            return result.stoppedFailedIndex != nil
        case .heistPlayback(_, let failedIndex, _, _, _):
            return failedIndex != nil
        default:
            return false
        }
    }

    static func actionFailureDetails(_ result: ActionResult) -> FailureDetails? {
        guard !result.success,
              result.errorKind == nil || result.errorKind == .actionFailed,
              result.message == Self.accessibilityTreeUnavailableMessage
        else {
            return nil
        }

        return FailureDetails(
            errorCode: "request.accessibility_tree_unavailable",
            phase: .request,
            retryable: true,
            hint: "Wait for a traversable app window, then refresh the interface or retry the command."
        )
    }

    // Keep this literal in sync with `TheBrains.treeUnavailableMessage`; this
    // bridges tree-unavailable `actionFailed` wire results to local diagnostics.
    private static let accessibilityTreeUnavailableMessage =
        "Could not access accessibility tree: no traversable app windows"

}

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

extension BatchExecutionStepResult {
    func actionResponse(command: TheFence.Command, step: TheScore.BatchStep) -> FenceResponse? {
        guard skipped == nil else { return nil }
        guard let finalResult = expectationActionResult ?? actionResult else {
            return .error("typed batch step produced no action result")
        }
        return .action(
            command: command,
            result: finalResult,
            expectation: expectation ?? step.expectation.validate(against: finalResult)
        )
    }

    func finalActionResult() -> ActionResult? {
        expectationActionResult ?? actionResult
    }

    func expectationResult(for step: TheScore.BatchStep) -> ExpectationResult? {
        if let expectation { return expectation }
        return finalActionResult().map { step.expectation.validate(against: $0) }
    }

    func expectationCounted(for step: TheScore.BatchStep) -> Bool {
        guard let checked = expectationResult(for: step)?.expectation else { return false }
        return checked != .delivery
    }

    func expectationMet(for step: TheScore.BatchStep) -> Bool? {
        guard expectationCounted(for: step) else { return nil }
        return expectationResult(for: step)?.met
    }
}

extension BatchExecutionResult {
    var completedStepCount: Int {
        steps.count { !$0.isSkipped }
    }

    var stoppedFailedIndex: Int? {
        failedIndex ?? steps.first(where: \.stopsBatch)?.index
    }

    func expectationsChecked(steps plannedSteps: [TheScore.BatchStep]) -> Int {
        steps.count { step in
            guard plannedSteps.indices.contains(step.index) else { return false }
            return step.expectationCounted(for: plannedSteps[step.index])
        }
    }

    func expectationsMet(steps plannedSteps: [TheScore.BatchStep]) -> Int {
        steps.count { step in
            guard plannedSteps.indices.contains(step.index) else { return false }
            return step.expectationMet(for: plannedSteps[step.index]) == true
        }
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

public struct SessionLastActionPayload: Sendable, Equatable {
    public let method: ActionMethod
    public let success: Bool
    public let message: String?
    public let latencyMs: Int

    public init(method: ActionMethod, success: Bool, message: String?, latencyMs: Int) {
        self.method = method
        self.success = success
        self.message = message
        self.latencyMs = latencyMs
    }
}

public struct SessionStatePayload: Sendable, Equatable {
    public let connected: Bool
    public let phase: SessionConnectionPhase
    public let device: SessionDevicePayload?
    public let actionTimeoutSeconds: TimeInterval
    public let longActionTimeoutSeconds: TimeInterval
    public let lastFailure: SessionFailurePayload?
    public let lastAction: SessionLastActionPayload?

    public init(
        connected: Bool,
        phase: SessionConnectionPhase,
        device: SessionDevicePayload?,
        actionTimeoutSeconds: TimeInterval,
        longActionTimeoutSeconds: TimeInterval,
        lastFailure: SessionFailurePayload?,
        lastAction: SessionLastActionPayload?
    ) {
        self.connected = connected
        self.phase = phase
        self.device = device
        self.actionTimeoutSeconds = actionTimeoutSeconds
        self.longActionTimeoutSeconds = longActionTimeoutSeconds
        self.lastFailure = lastFailure
        self.lastAction = lastAction
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
    case help(commands: [String])
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
    case batch(
        commands: [TheFence.Command],
        steps: [TheScore.BatchStep],
        result: BatchExecutionResult,
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
        case .batch(_, _, let result, _):
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

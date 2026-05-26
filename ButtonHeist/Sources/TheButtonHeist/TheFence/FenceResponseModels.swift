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

public struct RecordingResponseOptions: Sendable, Equatable {
    public let inlineData: Bool
    public let includeInteractionLog: Bool

    public init(inlineData: Bool = false, includeInteractionLog: Bool = false) {
        self.inlineData = inlineData
        self.includeInteractionLog = includeInteractionLog
    }
}

/// Summary of a single step within a batch execution.
///
/// Consumed by batch formatters to build per-step human/JSON rows. `deltaKind`
/// is the wire-level `kind` discriminator from the step's `AccessibilityTrace.Delta`;
/// `expectationMet` is nil when the step had no expectation attached.
public struct BatchStepSummary: Sendable {
    public let command: String
    public let deltaKind: String?
    public let screenName: String?
    public let screenId: String?
    public let expectationMet: Bool?
    public let elementCount: Int?
    public let error: String?
    public let errorCode: String?
    public let phase: String?
    public let nextCommand: String?

    public init(
        command: String,
        deltaKind: String?,
        screenName: String?,
        screenId: String?,
        expectationMet: Bool?,
        elementCount: Int?,
        error: String?,
        errorCode: String? = nil,
        phase: String? = nil,
        nextCommand: String? = nil
    ) {
        self.command = command
        self.deltaKind = deltaKind
        self.screenName = screenName
        self.screenId = screenId
        self.expectationMet = expectationMet
        self.elementCount = elementCount
        self.error = error
        self.errorCode = errorCode
        self.phase = phase
        self.nextCommand = nextCommand
    }
}

public struct BatchStepOutcome {
    public enum Result {
        case response(FenceResponse)
        case skipped(reason: String, afterFailedIndex: Int)
    }

    public let command: String
    public let result: Result
    public let diagnosticDetails: FailureDetails?
    public let stopsBatch: Bool

    public init(
        command: String,
        response: FenceResponse,
        diagnosticDetails: FailureDetails? = nil,
        stopsBatch: Bool = false
    ) {
        self.command = command
        self.result = .response(response)
        self.diagnosticDetails = diagnosticDetails
        self.stopsBatch = stopsBatch
    }

    private init(
        command: String,
        result: Result,
        diagnosticDetails: FailureDetails? = nil,
        stopsBatch: Bool = false
    ) {
        self.command = command
        self.result = result
        self.diagnosticDetails = diagnosticDetails
        self.stopsBatch = stopsBatch
    }

    public static func skipped(command: String, afterFailedIndex failedIndex: Int) -> BatchStepOutcome {
        BatchStepOutcome(
            command: command,
            result: .skipped(reason: "skipped: stop_on_error stopped batch after step \(failedIndex)", afterFailedIndex: failedIndex)
        )
    }
}

extension BatchStepOutcome {
    var response: FenceResponse? {
        guard case .response(let response) = result else { return nil }
        return response
    }

    var isCompleted: Bool {
        response != nil
    }

    var isFailed: Bool {
        response?.isFailure == true
    }

    var hasActionResult: Bool {
        guard case .action = response else { return false }
        return true
    }

    var accessibilityTrace: AccessibilityTrace? {
        guard case .action(let result, _) = response else { return nil }
        return result.accessibilityTrace
    }

    var expectationCounted: Bool {
        guard case .action(_, let expectation) = response else { return false }
        guard let checked = expectation?.expectation else { return false }
        return checked != .delivery
    }

    var expectationMet: Bool? {
        guard expectationCounted, case .action(_, let expectation) = response else { return nil }
        return expectation?.met
    }

    var stepSummary: BatchStepSummary {
        switch result {
        case .response(let response):
            return Self.makeStepSummary(
                command: command,
                response: response,
                diagnosticDetails: diagnosticDetails,
                expectationMet: expectationCounted ? expectationMet : nil
            )
        case .skipped(let reason, _):
            return BatchStepSummary(
                command: command,
                deltaKind: nil,
                screenName: nil,
                screenId: nil,
                expectationMet: nil,
                elementCount: nil,
                error: reason
            )
        }
    }

    private static func makeStepSummary(
        command: String,
        response: FenceResponse,
        diagnosticDetails: FailureDetails?,
        expectationMet: Bool?
    ) -> BatchStepSummary {
        switch response {
        case .action(let result, _):
            return BatchStepSummary(
                command: command,
                deltaKind: result.accessibilityDelta?.kindRawValue,
                screenName: result.screenName,
                screenId: result.screenId,
                expectationMet: expectationMet,
                elementCount: nil,
                error: result.success ? nil : result.message
            )
        case .interface(let iface, _):
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: iface.elements.count, error: nil
            )
        case .error(let message, let details):
            let details = details ?? diagnosticDetails
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: message,
                errorCode: details?.errorCode,
                phase: details?.phase.rawValue,
                nextCommand: batchNextCommand(from: details)
            )
        default:
            return BatchStepSummary(
                command: command, deltaKind: nil, screenName: nil, screenId: nil,
                expectationMet: nil, elementCount: nil, error: nil
            )
        }
    }

    private static func batchNextCommand(from details: FailureDetails?) -> String? {
        guard details?.errorCode == FenceRequestErrorCode.missingTarget else { return nil }
        return details?.hint
    }
}

extension Array where Element == BatchStepOutcome {
    var completedStepCount: Int {
        count(where: \.isCompleted)
    }

    var stoppedFailedIndex: Int? {
        firstIndex(where: \.stopsBatch)
    }

    var expectationsChecked: Int {
        count(where: \.expectationCounted)
    }

    var expectationsMet: Int {
        count(where: { $0.expectationMet == true })
    }

    var stepSummaries: [BatchStepSummary] {
        map(\.stepSummary)
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
    public let isRecording: Bool
    public let actionTimeoutSeconds: TimeInterval
    public let longActionTimeoutSeconds: TimeInterval
    public let lastFailure: SessionFailurePayload?
    public let lastAction: SessionLastActionPayload?

    public init(
        connected: Bool,
        phase: SessionConnectionPhase,
        device: SessionDevicePayload?,
        isRecording: Bool,
        actionTimeoutSeconds: TimeInterval,
        longActionTimeoutSeconds: TimeInterval,
        lastFailure: SessionFailurePayload?,
        lastAction: SessionLastActionPayload?
    ) {
        self.connected = connected
        self.phase = phase
        self.device = device
        self.isRecording = isRecording
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
/// Screenshot data and expanded recording data are opt-in.
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
    case action(result: ActionResult, expectation: ExpectationResult? = nil)
    /// Screenshot written to disk. `path` is the resolved filesystem location.
    case screenshot(path: String, payload: ScreenPayload, options: ScreenshotResponseOptions = ScreenshotResponseOptions())
    /// Screenshot held in memory as base64 PNG. Returned only when inline data
    /// is explicitly requested.
    case screenshotData(payload: ScreenPayload, options: ScreenshotResponseOptions = ScreenshotResponseOptions())
    /// Recording written to disk. `path` is the resolved filesystem location.
    case recording(path: String, payload: RecordingPayload)
    /// Recording written to disk with explicitly requested expanded response fields.
    case recordingExpanded(path: String, payload: RecordingPayload, options: RecordingResponseOptions)
    /// Recording held in memory. Kept for callers that explicitly work with
    /// in-memory recording payloads.
    case recordingData(payload: RecordingPayload)
    case batch(
        outcomes: [BatchStepOutcome],
        totalTimingMs: Int,
        accessibilityTrace: AccessibilityTrace? = nil
    )
    case sessionState(payload: SessionStatePayload)
    case targets([String: TargetConfig], defaultTarget: String?)
    case sessionLog(snapshot: SessionLogSnapshot)
    case archiveResult(path: String, snapshot: SessionLogSnapshot)
    case heistStarted
    case heistStopped(path: String, stepCount: Int)
    case heistPlayback(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure? = nil, report: HeistPlaybackReport? = nil)

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    var actionResult: ActionResult? {
        if case .action(let result, _) = self { return result }
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
        case .action(let result, let expectation):
            return !result.success || expectation?.met == false
        case .batch(let outcomes, _, _):
            return outcomes.stoppedFailedIndex != nil
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

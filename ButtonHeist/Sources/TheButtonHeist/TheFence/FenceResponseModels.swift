import Foundation
import ThePlans

import TheScore

/// Level of detail for interface responses.
public enum InterfaceDetail: String, CaseIterable, Sendable {
    case summary
    case full
}

public struct ScreenshotResponseOptions: Sendable, Equatable {
    public let includeInterface: Bool

    public init(includeInterface: Bool = true) {
        self.includeInterface = includeInterface
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
    public let code: String
    public let phase: FailurePhase
    public let retryable: Bool
    public let message: String?
    public let hint: String?

    public init(
        code: String,
        phase: FailurePhase,
        retryable: Bool,
        message: String?,
        hint: String?
    ) {
        self.code = code
        self.phase = phase
        self.retryable = retryable
        self.message = message
        self.hint = hint
    }
}

public enum SessionConnectionState: Sendable, Equatable {
    case disconnected(lastFailure: SessionFailurePayload?)
    case connecting(lastFailure: SessionFailurePayload?)
    case connected(device: SessionDevicePayload)
    case failed(SessionFailurePayload)

    public var connected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var phase: SessionConnectionPhase {
        switch self {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .failed:
            return .failed
        }
    }

    public var device: SessionDevicePayload? {
        guard case .connected(let device) = self else { return nil }
        return device
    }

    public var lastFailure: SessionFailurePayload? {
        switch self {
        case .disconnected(let failure), .connecting(let failure):
            return failure
        case .failed(let failure):
            return failure
        case .connected:
            return nil
        }
    }
}

public struct SessionStatePayload: Sendable, Equatable {
    public let state: SessionConnectionState
    public let actionTimeoutSeconds: TimeInterval
    public let longActionTimeoutSeconds: TimeInterval

    public init(
        state: SessionConnectionState,
        actionTimeoutSeconds: TimeInterval,
        longActionTimeoutSeconds: TimeInterval
    ) {
        self.state = state
        self.actionTimeoutSeconds = actionTimeoutSeconds
        self.longActionTimeoutSeconds = longActionTimeoutSeconds
    }

    public var connected: Bool { state.connected }
    public var phase: SessionConnectionPhase { state.phase }
    public var device: SessionDevicePayload? { state.device }
    public var lastFailure: SessionFailurePayload? { state.lastFailure }
}

extension DiagnosticFailure {
    init(_ error: Error) {
        switch error {
        case let fenceError as FenceError:
            self.init(fenceError)
        case let connectionError as HandoffConnectionError:
            self.init(FenceError(connectionError))
        case let configError as TargetConfigLoadError:
            self.init(
                message: configError.displayMessage,
                details: configError.failureDetails
            )
        case let validationError as SchemaValidationError:
            self.init(
                message: validationError.message,
                details: FailureDetails(code: .requestValidationError)
            )
        case let inputError as PublicJSONInputError:
            self.init(
                message: inputError.message,
                details: FailureDetails(code: .requestInvalid)
            )
        case let missingTarget as TheFence.MissingAccessibilityTarget:
            self.init(missingAccessibilityTargetCommand: missingTarget.command)
        case let containerTarget as TheFence.ContainerTargetRequiresElement:
            self.init(containerTargetRequiresElementCommand: containerTarget.command)
        case let routingError as FenceOperationRoutingError:
            self.init(message: routingError.message, details: routingError.details)
        default:
            self.init(
                message: error.displayMessage,
                details: FailureDetails(code: .clientUnknown)
            )
        }
    }

    init(_ fenceError: FenceError) {
        self.init(
            message: fenceError.coreMessage,
            details: fenceError.failureDetails,
            buildDiagnostics: fenceError.buildDiagnostics
        )
    }

    init(failureKind: ActionFailure.Kind, message: String) {
        self.init(message: message, details: Self.failureDetails(for: failureKind))
    }

    init(reportFailure: HeistFailureDetail, message: String? = nil) {
        self.init(
            message: message ?? reportFailure.observed,
            details: Self.failureDetails(for: reportFailure)
        )
    }

    private static func failureDetails(for failureKind: ActionFailure.Kind) -> FailureDetails {
        failureKind.failureDetails
    }

    private static func failureDetails(for reportFailure: HeistFailureDetail) -> FailureDetails {
        switch reportFailure.category {
        case .internalInvariant:
            return FailureDetails(code: .requestActionFailed)
        case .validation:
            return FailureDetails(code: .requestValidationError)
        case .runtimeUnavailable:
            return FailureDetails(code: .connectionNotConnected)
        case .targetResolution:
            return FailureDetails(code: .requestElementNotFound)
        case .wait:
            return FailureDetails(code: .requestTimeout)
        case .action,
             .expectation,
             .invocation,
             .loop,
             .explicitFailure:
            return FailureDetails(code: .requestActionFailed)
        }
    }

    private init(missingAccessibilityTargetCommand command: TheFence.Command) {
        let commandName = command.rawValue
        let contract = "requires target object with checks"
        let next = "get_interface()"
        let targetHint = "target.checks"
        let message = "\(commandName) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(commandName) with \(targetHint)."
        self.init(
            message: message,
            details: FailureDetails(
                code: .requestMissingTarget,
                hint: next
            )
        )
    }

    private init(containerTargetRequiresElementCommand command: TheFence.Command) {
        self.init(
            message: "Command \"\(command.rawValue)\" requires an accessibility element target; container-only targets are not valid",
            details: FailureDetails(code: .requestValidationError)
        )
    }
}

/// Typed response from TheFence command execution.
///
/// Cases marked `…Data` carry the raw payload in memory (base64-encoded).
/// Screenshot data is opt-in.
/// Cases without the `Data` suffix carry a filesystem path where the artifact
/// has been written.
public enum FenceResponse {
    case ok(message: String)
    case error(DiagnosticFailure)
    case status(connected: Bool, deviceName: String?)
    case pong(PongPayload)
    case devices([DiscoveredDevice])
    case interface(Interface, detail: InterfaceDetail = .summary)
    case announcements([CapturedAnnouncement])
    case action(command: TheFence.Command, result: ActionResult, expectation: ExpectationResult? = nil)
    /// Screenshot written to disk. `path` is the resolved filesystem location.
    case screenshot(path: String, payload: ScreenPayload, options: ScreenshotResponseOptions = ScreenshotResponseOptions())
    /// Screenshot held in memory as base64 PNG. Returned only when inline data
    /// is explicitly requested.
    case screenshotData(payload: ScreenPayload, options: ScreenshotResponseOptions = ScreenshotResponseOptions())
    case heistExecution(
        plan: HeistPlan,
        report: HeistReport
    )
    case heistValidation(HeistValidation.Report)
    case heistCatalog(HeistDiscoveryCatalog)
    case heistDescription(HeistDescription)
    case sessionState(payload: SessionStatePayload)
    case targets([TargetName: TargetConfig], defaultTarget: TargetName?)

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    var actionResult: ActionResult? {
        if case .action(_, let result, _) = self { return result }
        return nil
    }

    /// Builds an error response with typed metadata when the error belongs to TheFence.
    public static func failure(_ error: Error) -> FenceResponse {
        let failure = DiagnosticFailure(error)
        return .error(failure)
    }

    /// Canonical public failure payload when this response is an error.
    public var diagnosticFailure: DiagnosticFailure? {
        guard case .error(let failure) = self else { return nil }
        return failure
    }

    /// Whether callers should treat this response as a failed command.
    public var isFailure: Bool {
        switch self {
        case .ok, .status, .pong, .devices, .interface, .announcements, .screenshot, .screenshotData,
             .heistCatalog, .heistDescription,
             .sessionState, .targets:
            return false
        case .error:
            return true
        case .action(_, let result, let expectation):
            if !result.outcome.isSuccess { return true }
            if let expectation, !expectation.met { return true }
            return false
        case .heistExecution(_, let report):
            return report.failure != nil
        case .heistValidation(let report):
            return !report.commandPassed
        }
    }

}

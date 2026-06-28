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

enum DiagnosticFailureMapper {
    static func map(_ error: Error) -> DiagnosticFailure {
        switch error {
        case let fenceError as FenceError:
            return map(fenceError)
        case let connectionError as HandoffConnectionError:
            return map(FenceError(connectionError))
        case let configError as TargetConfigLoadError:
            return DiagnosticFailure(
                message: configError.displayMessage,
                details: configError.failureDetails
            )
        case let validationError as SchemaValidationError:
            return DiagnosticFailure(
                message: validationError.message,
                details: FailureDetails(code: .requestValidationError)
            )
        case let inputError as PublicJSONInputError:
            return DiagnosticFailure(
                message: inputError.message,
                details: FailureDetails(code: .requestInvalid)
            )
        case let missingTarget as TheFence.MissingElementTarget:
            return missingElementTargetFailure(command: missingTarget.command)
        case let routingError as FenceOperationRoutingError:
            return DiagnosticFailure(message: routingError.message, details: routingError.details)
        default:
            return DiagnosticFailure(message: error.displayMessage, details: nil)
        }
    }

    static func map(_ fenceError: FenceError) -> DiagnosticFailure {
        DiagnosticFailure(message: fenceError.coreMessage, details: fenceError.failureDetails)
    }

    static func map(message: String, details: FailureDetails?) -> DiagnosticFailure {
        DiagnosticFailure(message: message, details: details)
    }

    static func map(errorKind: ErrorKind, message: String) -> DiagnosticFailure {
        DiagnosticFailure(message: message, details: failureDetails(for: errorKind))
    }

    static func map(reportFailure: HeistFailureDetail, message: String? = nil) -> DiagnosticFailure {
        DiagnosticFailure(
            message: message ?? reportFailure.observed,
            details: failureDetails(for: reportFailure)
        )
    }

    static func failureDetails(for errorKind: ErrorKind) -> FailureDetails {
        errorKind.failureDetails
    }

    static func failureDetails(for reportFailure: HeistFailureDetail) -> FailureDetails {
        switch reportFailure.category {
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

    private static func missingElementTargetFailure(command: String) -> DiagnosticFailure {
        let contract = "requires target object with predicate fields"
        let next = "get_interface()"
        let matcherFields = ElementTarget.predicateFieldNames.map { "target.\($0)" }
        let matcherHint: String
        if let last = matcherFields.last {
            matcherHint = matcherFields.dropLast().joined(separator: ", ") + ", or \(last)"
        } else {
            matcherHint = ""
        }
        let targetHint = matcherHint
        let message = "\(command) request contract failed: missing target; \(contract). " +
            "Next: \(next) to inspect the current app accessibility state, then retry \(command) with \(targetHint)."
        return DiagnosticFailure(
            message: message,
            details: FailureDetails(
                code: .requestMissingTarget,
                hint: next
            )
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
    case heistCatalog(HeistDiscoveryCatalog)
    case heistDescription(HeistDescription)
    case sessionState(payload: SessionStatePayload)
    case targets([String: TargetConfig], defaultTarget: String?)

    /// Extract the ActionResult if this response wraps one (for expectation checking).
    var actionResult: ActionResult? {
        if case .action(_, let result, _) = self { return result }
        return nil
    }

    /// Builds an error response with typed metadata when the error belongs to TheFence.
    public static func failure(_ error: Error) -> FenceResponse {
        let failure = DiagnosticFailureMapper.map(error)
        return .error(failure)
    }

    /// Builds an error response from the canonical public failure value.
    public static func error(_ failure: DiagnosticFailure) -> FenceResponse {
        .error(failure.message, details: failure.details)
    }

    /// Canonical public failure payload when this response is an error.
    public var diagnosticFailure: DiagnosticFailure? {
        guard case .error(let message, let details) = self else { return nil }
        return DiagnosticFailureMapper.map(message: message, details: details)
    }

    /// Whether callers should treat this response as a failed command.
    public var isFailure: Bool {
        switch self {
        case .ok, .status, .pong, .devices, .interface, .screenshot, .screenshotData,
             .heistCatalog, .heistDescription,
             .sessionState, .targets:
            return false
        case .error:
            return true
        case .action(_, let result, let expectation):
            if !result.success { return true }
            if let expectation, !expectation.met { return true }
            return false
        case .heistExecution(_, let result, _):
            return result.isFailure
        }
    }

}

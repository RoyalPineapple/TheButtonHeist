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

/// Stable public category for a command failure.
public enum PublicFailureKind: String, Sendable, Equatable {
    case request
    case discovery
    case connection
    case authentication = "auth"
    case session
    case configuration
    case server
    case client
    case unknown
}

/// Canonical public failure shape used by CLI and MCP responses.
public struct PublicFailure: Sendable, Equatable {
    /// Stable machine-readable failure code.
    public let code: String
    /// Broad public category for the failure.
    public let kind: PublicFailureKind
    /// User-facing failure message.
    public let message: String
    /// Lifecycle metadata and recovery hint for the failure.
    public let details: FailureDetails

    private static let unknownDetails = FailureDetails(
        errorCode: "client.unknown",
        phase: .client,
        retryable: false,
        hint: nil
    )

    /// Creates a public failure from fully typed metadata.
    public init(message: String, details: FailureDetails, kind: PublicFailureKind? = nil) {
        self.code = details.errorCode
        self.kind = kind ?? PublicFailureKind(details: details)
        self.message = message
        self.details = details
    }

    /// Creates a public failure, falling back to the unknown client error shape when details are absent.
    public init(message: String, details: FailureDetails?, kind: PublicFailureKind? = nil) {
        let resolvedKind: PublicFailureKind?
        if let kind {
            resolvedKind = kind
        } else if details == nil {
            resolvedKind = .unknown
        } else {
            resolvedKind = nil
        }
        self.init(
            message: message,
            details: details ?? Self.unknownDetails,
            kind: resolvedKind
        )
    }
}

enum FenceRequestErrorCode {
    static let missingTarget = "request.missing_target"
}

private enum PublicFailureMapper {
    static func map(_ error: Error) -> PublicFailure {
        switch error {
        case let fenceError as FenceError:
            return map(fenceError)
        case let connectionError as HandoffConnectionError:
            return map(FenceError(connectionError))
        case let configError as TargetConfigLoadError:
            return PublicFailure(
                message: configError.displayMessage,
                details: configError.failureDetails
            )
        case let validationError as SchemaValidationError:
            return map(FenceError.invalidRequest(validationError.message))
        case let missingTarget as TheFence.MissingElementTarget:
            return missingElementTargetFailure(command: missingTarget.command)
        case let routingError as FenceOperationRoutingError:
            return map(FenceError.invalidRequest(routingError.message))
        default:
            return PublicFailure(message: error.displayMessage, details: nil)
        }
    }

    static func map(_ fenceError: FenceError) -> PublicFailure {
        PublicFailure(message: fenceError.coreMessage, details: fenceError.failureDetails)
    }

    static func map(message: String, details: FailureDetails?) -> PublicFailure {
        PublicFailure(message: message, details: details)
    }

    private static func missingElementTargetFailure(command: String) -> PublicFailure {
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
        return PublicFailure(
            message: message,
            details: FailureDetails(
                errorCode: FenceRequestErrorCode.missingTarget,
                phase: .request,
                retryable: false,
                hint: next
            )
        )
    }
}

private extension PublicFailureKind {
    init(details: FailureDetails) {
        if let prefix = details.errorCode.split(separator: ".").first.map(String.init) {
            switch prefix {
            case "request":
                self = .request
                return
            case "discovery":
                self = .discovery
                return
            case "setup", "connection", "protocol", "tls":
                self = .connection
                return
            case "auth":
                self = .authentication
                return
            case "session":
                self = .session
                return
            case "config":
                self = .configuration
                return
            case "server":
                self = .server
                return
            case "client", "formatting", "screen":
                self = .client
                return
            default:
                break
            }
        }

        switch details.phase {
        case .discovery:
            self = .discovery
        case .setup, .transport, .protocolNegotiation, .tls:
            self = .connection
        case .authentication:
            self = .authentication
        case .session:
            self = .session
        case .server:
            self = .server
        case .request:
            self = .request
        case .client:
            self = .client
        }
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
        let failure = PublicFailureMapper.map(error)
        return .error(failure.message, details: failure.details)
    }

    /// Canonical public failure payload when this response is an error.
    public var publicFailure: PublicFailure? {
        guard case .error(let message, let details) = self else { return nil }
        return PublicFailureMapper.map(message: message, details: details)
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

import Foundation
import ThePlans
import TheScore

struct PublicErrorResponse: Encodable {
    let status = PublicResponseStatus.error
    let message: String
    let code: KnownFailureCode
    let details: PublicErrorDetails

    init(failure: DiagnosticFailure) {
        self.message = failure.message
        self.code = failure.failureCode
        self.details = PublicErrorDetails(failure: failure)
    }
}

struct PublicErrorDetails: Encodable {
    let kind: DiagnosticFailureKind
    let phase: FailurePhase
    let retryable: Bool
    let hint: String?
    let buildDiagnostics: [PublicHeistBuildDiagnostic]?

    init(failure: DiagnosticFailure) {
        self.kind = failure.kind
        self.phase = failure.details.phase
        self.retryable = failure.details.retryable
        self.hint = failure.details.hint
        self.buildDiagnostics = failure.buildDiagnostics.isEmpty
            ? nil
            : failure.buildDiagnostics.map(PublicHeistBuildDiagnostic.init)
    }
}

struct PublicHeistBuildDiagnostic: Encodable {
    let code: String
    let kind: String
    let phase: String
    let message: String
    let hint: String?
    let path: String?
    let sourceSpan: PublicHeistBuildSourceSpan?

    init(_ diagnostic: HeistBuildDiagnostic) {
        self.code = diagnostic.code.rawValue
        self.kind = diagnostic.kind.rawValue
        self.phase = diagnostic.phase.rawValue
        self.message = diagnostic.message
        self.hint = diagnostic.hint
        self.path = diagnostic.path
        self.sourceSpan = diagnostic.sourceSpan.map(PublicHeistBuildSourceSpan.init)
    }
}

struct PublicHeistBuildSourceSpan: Encodable {
    let sourceName: String
    let offset: Int
    let line: Int
    let column: Int
    let length: Int?

    init(_ sourceSpan: HeistBuildSourceSpan) {
        self.sourceName = sourceSpan.sourceName
        self.offset = sourceSpan.offset
        self.line = sourceSpan.line
        self.column = sourceSpan.column
        self.length = sourceSpan.length
    }
}

struct PublicResponseModel: Encodable {
    let response: FenceResponse
    let profile: ProjectionProfile

    init(response: FenceResponse, profile: ProjectionProfile = .summary) {
        self.response = response
        self.profile = profile
    }

    func encode(to encoder: Encoder) throws {
        switch response {
        case .ok(let message):
            try PublicOKResponse(message: message).encode(to: encoder)
        case .error(let failure):
            try PublicErrorResponse(failure: failure).encode(to: encoder)
        case .status(let connected, let deviceName):
            try PublicStatusResponse(connected: connected, device: deviceName).encode(to: encoder)
        case .pong(let payload):
            try PublicPongResponse(payload: payload).encode(to: encoder)
        case .devices(let devices):
            try PublicDevicesResponse(devices: devices).encode(to: encoder)
        case .interface(let interface, let detail):
            try PublicInterfaceResponse(interface: interface, detail: detail, profile: profile).encode(to: encoder)
        case .announcements(let announcements):
            try PublicAnnouncementsResponse(announcements: announcements).encode(to: encoder)
        case .action(let command, let result, let expectation):
            let expectationHint = expectation.flatMap {
                FenceResponse.expectationFailureHint($0, command: command, result: result)
            }
            try PublicActionResponse(projection: ActionProjection(
                actionMethod: .fence(command),
                result: result,
                expectation: expectation,
                expectationHint: expectationHint,
                profile: profile
            )).encode(to: encoder)
        case .screenshot(let path, let payload, let options):
            try PublicScreenshotResponse(projection: ScreenshotProjection(
                storage: .artifact(path: path),
                payload: payload,
                includeInterface: options.includeInterface,
                profile: profile
            )).encode(to: encoder)
        case .screenshotData(let payload, let options):
            try PublicScreenshotResponse(projection: ScreenshotProjection(
                storage: .inlinePNG(payload.pngData),
                payload: payload,
                includeInterface: options.includeInterface,
                profile: profile
            )).encode(to: encoder)
        case .heistExecution(_, let report):
            try PublicHeistExecutionResponse(
                report: report,
                profile: profile
            ).encode(to: encoder)
        case .heistValidation(let report):
            try PublicHeistValidationResponse(report: report).encode(to: encoder)
        case .heistCatalog(let catalog):
            try PublicHeistCatalogResponse(catalog: catalog).encode(to: encoder)
        case .heistDescription(let description):
            try PublicHeistDescriptionResponse(heist: description).encode(to: encoder)
        case .sessionState(let payload):
            try PublicSessionStateResponse(payload: payload).encode(to: encoder)
        case .targets(let targets, let defaultTarget):
            try PublicTargetsResponse(targets: targets, defaultTarget: defaultTarget).encode(to: encoder)
        }
    }
}

struct PublicAnnouncementsResponse: Encodable {
    let status = PublicResponseStatus.ok
    let announcements: [CapturedAnnouncement]
}

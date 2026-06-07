import Foundation

protocol FencePublicJSONResponse: Encodable {}

struct PublicStatus: Encodable {
    static let ok = PublicStatus(value: "ok")
    static let error = PublicStatus(value: "error")

    let value: String

    init(value: String) {
        self.value = value
    }

    init(_ status: PublicResponseStatus) {
        self.value = status.rawValue
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct PublicErrorResponse: FencePublicJSONResponse {
    let status = PublicStatus.error
    let message: String
    let errorCode: String?
    let phase: String?
    let retryable: Bool?
    let hint: String?

    init(message: String, details: FailureDetails?) {
        self.message = message
        self.errorCode = details?.errorCode
        self.phase = details?.phase.rawValue
        self.retryable = details?.retryable
        self.hint = details?.hint
    }
}

struct PublicResponseModel: FencePublicJSONResponse {
    let response: FenceResponse

    func encode(to encoder: Encoder) throws {
        switch response {
        case .ok(let message):
            try PublicOKResponse(message: message).encode(to: encoder)
        case .error(let message, let details):
            try PublicErrorResponse(message: message, details: details).encode(to: encoder)
        case .status(let connected, let deviceName):
            try PublicStatusResponse(connected: connected, device: deviceName).encode(to: encoder)
        case .pong(let payload):
            try PublicPongResponse(payload: payload).encode(to: encoder)
        case .devices(let devices):
            try PublicDevicesResponse(devices: devices).encode(to: encoder)
        case .interface(let interface, let detail):
            try PublicInterfaceResponse(interface: interface, detail: detail).encode(to: encoder)
        case .action(let command, let result, let expectation):
            try PublicActionResponse(
                method: command.rawValue,
                result: result,
                expectation: expectation
            ).encode(to: encoder)
        case .screenshot(let path, let payload, let options):
            try PublicScreenshotResponse(
                path: path,
                payload: payload,
                includePNGData: false,
                includeInterface: options.includeInterface
            ).encode(to: encoder)
        case .screenshotData(let payload, let options):
            try PublicScreenshotResponse(
                path: nil,
                payload: payload,
                includePNGData: true,
                includeInterface: options.includeInterface
            ).encode(to: encoder)
        case .heistExecution(_, let result, let accessibilityTrace):
            if let single = response.singleLeafActionRendering {
                try PublicActionResponse(
                    method: single.command.rawValue,
                    result: single.result,
                    expectation: single.expectation
                ).encode(to: encoder)
            } else {
                try PublicHeistExecutionResponse(
                    result: result,
                    netDelta: accessibilityTrace?.meaningfulEndpointDelta
                ).encode(to: encoder)
            }
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

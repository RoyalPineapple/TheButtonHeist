import Foundation
import ThePlans

import TheScore

extension TheFence {

    struct GetInterfaceRequest {
        let detail: InterfaceDetail
        let query: InterfaceQuery
    }

    struct ScreenRequest {
        let destination: ScreenshotDestination
        let mode: ScreenCaptureMode
        let requestId: String
    }

    package enum ScreenshotDestination: Sendable, Equatable {
        case artifact(outputPath: String?)
        case inlineData
    }

    static func decodeGetInterfaceRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.makeGetInterfaceRequest(arguments)
        return DecodedRequestDispatch { fence in try await fence.handleGetInterface(request) }
    }

    static func decodeGetScreenRequest(
        _ fence: TheFence,
        _ arguments: CommandArgumentEnvelope,
        _ requestId: String,
        _ expectationPayload: ExpectationPayload
    ) throws -> DecodedRequestDispatch {
        let request = try fence.makeScreenRequest(arguments, requestId: requestId)
        return DecodedRequestDispatch { fence in try await fence.handleGetScreen(request) }
    }

    private func makeGetInterfaceRequest(_ arguments: CommandArgumentEnvelope) throws -> GetInterfaceRequest {
        return GetInterfaceRequest(
            detail: try arguments.value(FenceParameters.interfaceDetail) ?? .summary,
            query: InterfaceQuery(
                subtree: try decodeInterfaceSubtreeTarget(arguments),
                maxScrollsPerContainer: try interfaceDiscoveryLimit(arguments, .maxScrollsPerContainer),
                maxScrollsPerDiscovery: try interfaceDiscoveryLimit(arguments, .maxScrollsPerDiscovery)
            )
        )
    }

    private func interfaceDiscoveryLimit(
        _ arguments: CommandArgumentEnvelope,
        _ key: FenceParameterKey
    ) throws -> Int? {
        let parameter: FenceParameter<Int>
        if key == .maxScrollsPerContainer {
            parameter = FenceParameters.maxScrollsPerContainer
        } else if key == .maxScrollsPerDiscovery {
            parameter = FenceParameters.maxScrollsPerDiscovery
        } else {
            preconditionFailure("Unsupported interface discovery limit parameter \(key.rawValue)")
        }
        guard let value = try arguments.value(parameter) else { return nil }
        guard (1...2_000).contains(value) else {
            throw SchemaValidationError(
                field: arguments.field(key),
                observed: value,
                expected: "integer between 1 and 2000"
            )
        }
        return value
    }

    private func makeScreenRequest(
        _ arguments: CommandArgumentEnvelope,
        requestId: String
    ) throws -> ScreenRequest {
        return ScreenRequest(
            destination: try screenshotDestination(arguments),
            mode: try arguments.value(FenceParameters.screenMode) ?? .raw,
            requestId: requestId
        )
    }

    private func screenshotDestination(_ arguments: CommandArgumentEnvelope) throws -> ScreenshotDestination {
        let outputPath = try arguments.value(FenceParameters.output)
        let inlineData = try arguments.value(FenceParameters.inlineData) ?? false
        switch (inlineData, outputPath) {
        case (true, nil):
            return .inlineData
        case (false, let outputPath):
            return .artifact(outputPath: outputPath)
        case (true, .some):
            throw SchemaValidationError(
                field: "inlineData/output",
                observed: "inlineData=true with output",
                expected: "choose output for an artifact path or inlineData=true for inline PNG data, not both"
            )
        }
    }

    private func decodeInterfaceSubtreeTarget(_ arguments: CommandArgumentEnvelope) throws -> AccessibilityTarget? {
        guard let subtree = arguments.value(for: .subtree) else { return nil }
        guard case .object(let object) = subtree else {
            throw SchemaValidationError(
                field: arguments.field(.subtree),
                observed: subtree.schemaObservedDescription,
                expected: "object"
            )
        }
        return try CommandArgumentEnvelope(
            values: object,
            fieldPrefix: arguments.field(.subtree)
        ).decodeAccessibilityTargetPayload()
    }

}

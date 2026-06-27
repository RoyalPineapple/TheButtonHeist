import Foundation

import TheScore

extension FenceResponse {

    // MARK: - Compact Text Format

    /// Token-efficient tree output for LLM agents. Omits geometry.
    public func compactFormatted() -> String {
        FenceResponsePresenter(profile: .summary).compactText(for: self)
    }

    func compactFormatted(profile: ProjectionProfile) -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message, let details):
            return Self.compactError(message, details: details)
        case .status(let connected, let deviceName):
            if connected, let name = deviceName { return "connected: \(name)" }
            return "not connected"
        case .pong(let payload):
            let name = payload.appName.isEmpty ? "App" : payload.appName
            let bundle = payload.bundleIdentifier.isEmpty ? "unknown" : payload.bundleIdentifier
            return "pong: \(name) \(bundle) [ButtonHeist \(payload.buttonHeistVersion)]"
        case .devices(let devices):
            if devices.isEmpty { return "no devices" }
            return devices.map {
                let name = $0.deviceName.isEmpty ? $0.appName : "\($0.appName) (\($0.deviceName))"
                return "\(name) [\($0.connectionType.rawValue)]"
            }
                .joined(separator: "\n")
        case .interface(let interface, let detail):
            let projectionProfile = ProjectionProfile(
                kind: detail == .full ? .full : profile.kind,
                limits: profile.limits
            )
            let projection = InterfaceProjection(interface: interface, profile: projectionProfile)
            var lines: [String] = [projection.screenDescription]
            lines.append(Self.compactInterface(projection))
            return lines.joined(separator: "\n")
        case .action(let command, let result, let expectation):
            return compactActionResult(command: command, result, expectation: expectation, profile: profile)
        case .screenshot(let path, let payload, let options):
            return Self.compactScreenshot(
                summary: "screenshot: \(path) (\(Int(payload.width))x\(Int(payload.height)))",
                payload: payload,
                options: options,
                profile: profile
            )
        case .screenshotData(let payload, let options):
            return Self.compactScreenshot(
                summary: "screenshot: \(Int(payload.width))x\(Int(payload.height))",
                payload: payload,
                options: options,
                profile: profile
            )
        case .heistExecution(_, let result, let accessibilityTrace):
            return compactHeistFormatted(
                result,
                netDelta: accessibilityTrace?.meaningfulEndpointDelta,
                profile: profile.kind == .summary ? .mcp : profile
            )
        case .heistCatalog(let catalog):
            return compactHeistCatalog(catalog)
        case .heistDescription(let description):
            return compactHeistDescription(description)
        case .sessionState(let payload):
            return Self.compactSessionState(payload)
        case .targets(let targets, let defaultTarget):
            if targets.isEmpty { return "no targets configured" }
            return targets.sorted(by: { $0.key < $1.key }).map { name, target in
                let isDefault = name == defaultTarget ? " *" : ""
                return "\(name): \(target.device)\(isDefault)"
            }.joined(separator: "\n")
        }
    }

    private static func compactError(_ message: String, details: FailureDetails?) -> String {
        guard let details else {
            return "error: \(message)"
        }
        var text = "error[\(details.errorCode) \(details.phase.rawValue) retryable=\(details.retryable)]: \(message)"
        if let hint = details.hint {
            text += "\nhint: \(hint)"
        }
        return text
    }

    private static func compactScreenshot(
        summary: String,
        payload: ScreenPayload,
        options: ScreenshotResponseOptions,
        profile: ProjectionProfile
    ) -> String {
        guard options.includeInterface else { return summary }
        var lines = [summary]
        if let interface = payload.interface {
            let projection = InterfaceProjection(
                interface: interface,
                profile: ProjectionProfile(kind: .full, limits: profile.limits)
            )
            lines.append(compactInterface(projection))
        } else {
            lines.append("interface: unavailable")
        }
        return lines.joined(separator: "\n")
    }

}

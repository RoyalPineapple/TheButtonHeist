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
        case .error(let failure):
            return Self.compactError(failure)
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
            return Self.compactInterface(projection)
        case .announcements(let announcements):
            return Self.compactAnnouncements(announcements)
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
            return compactHeistFormatted(HeistReportProjection(
                result: result,
                accessibilityTrace: accessibilityTrace,
                profile: profile
            ))
        case .heistValidation(let report):
            return compactHeistValidation(report)
        case .heistCatalog(let catalog):
            return compactHeistCatalog(catalog)
        case .heistDescription(let description):
            return compactHeistDescription(description)
        case .sessionState(let payload):
            return Self.compactSessionState(payload)
        case .targets(let targets, let defaultTarget):
            if targets.isEmpty { return "no targets configured" }
            return targets.sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { name, target in
                let isDefault = name == defaultTarget ? " *" : ""
                return "\(name.rawValue): \(target.device)\(isDefault)"
            }.joined(separator: "\n")
        }
    }

    private static func compactError(_ failure: DiagnosticFailure) -> String {
        let details = failure.details
        let message = failure.message
        var lines = ["error[\(details.errorCode) \(details.phase.rawValue) retryable=\(details.retryable)]: \(message)"]
        if let hint = details.hint {
            lines.append("hint: \(hint)")
        }
        lines.append(contentsOf: failure.buildDiagnostics.map { diagnostic in
            "diagnostic[\(diagnostic.code.rawValue) \(diagnostic.phase.rawValue) \(diagnostic.kind.rawValue)]: " +
                diagnostic.message
        })
        return lines.joined(separator: "\n")
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

    private static func compactAnnouncements(_ announcements: [CapturedAnnouncement]) -> String {
        guard !announcements.isEmpty else { return "announcements: none" }
        let now = Date()
        return announcements.enumerated().map { index, announcement in
            let age = max(0, now.timeIntervalSince(announcement.timestamp))
            return "[\(index)] \(String(format: "%.1f", age))s ago \(announcement.kind): \"\(announcement.text)\""
        }.joined(separator: "\n")
    }

}

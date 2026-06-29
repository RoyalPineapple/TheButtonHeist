import Foundation
import ThePlans

import AccessibilitySnapshotModel
import TheScore

extension FenceResponse {

    // MARK: - Human Formatting

    public func humanFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let failure):
            return "Error: \(failure.message)"
        case .status(let connected, let deviceName):
            if connected, let name = deviceName {
                return "Connected to \(name)"
            }
            return "Not connected"
        case .pong(let payload):
            return Self.formatPongHuman(payload)
        case .devices(let devices):
            return formatDeviceList(devices)
        case .interface(let interface, let detail):
            return formatInterface(interface, detail: detail)
        case .action(let command, let result, let expectation):
            var text = formatActionResult(command: command, result: result)
            if result.success, let expectation {
                if expectation.met {
                    text += "  [expectation met]"
                } else {
                    let tier = expectation.predicate.map(String.init(describing:)) ?? "delivery"
                    text += "  [expectation FAILED: expected \(tier), got \(expectation.actual ?? "nil")]"
                    if let hint = Self.expectationFailureHint(expectation, command: command, result: result) {
                        text += "  [hint: \(hint)]"
                    }
                }
            }
            return text
        case .screenshot(let path, let payload, let options):
            return formatScreenshot(
                summary: "✓ Screenshot saved: \(path)  (\(Int(payload.width)) × \(Int(payload.height)))",
                payload: payload,
                options: options
            )
        case .screenshotData(let payload, let options):
            return formatScreenshot(
                summary: "✓ Screenshot captured (\(Int(payload.width)) × \(Int(payload.height))) — base64 PNG follows\n\(payload.pngData)",
                payload: payload,
                options: options
            )
        case .heistExecution(_, let result, _):
            var text = "Heist: \(result.executedTopLevelStepCount) top-level step(s) executed in \(result.durationMs)ms"
            if let abortedAtPath = result.abortedAtPath { text += " (stopped at \(abortedAtPath))" }
            let checked = result.expectationsChecked
            if checked > 0 {
                text += " [expectations: \(result.expectationsMet)/\(checked) met]"
            }
            return text
        case .heistCatalog(let catalog):
            return formatHeistCatalogHuman(catalog)
        case .heistDescription(let description):
            return formatHeistDescriptionHuman(description)
        case .sessionState(let payload):
            return Self.formatSessionStateHuman(payload)
        case .targets(let targets, let defaultTarget):
            return formatTargetList(targets, defaultTarget: defaultTarget)
        }
    }

    private static func formatSessionStateHuman(_ payload: SessionStatePayload) -> String {
        let device = payload.device?.deviceName ?? "unknown"
        switch payload.phase {
        case .connected:
            return "Session: connected to \(device)"
        case .connecting:
            return "Session: connecting"
        case .failed:
            if let failure = sessionStateFailureSummary(payload.lastFailure) {
                return "Session: failed (\(failure))"
            }
            return "Session: failed"
        case .disconnected:
            if let failure = sessionStateFailureSummary(payload.lastFailure) {
                return "Session: disconnected (\(failure))"
            }
            return "Session: not connected"
        }
    }

    private static func formatPongHuman(_ payload: PongPayload) -> String {
        var parts = [
            payload.appName.isEmpty ? "App" : payload.appName,
            "bundle: \(payload.bundleIdentifier.isEmpty ? "unknown" : payload.bundleIdentifier)",
            "ButtonHeist: \(payload.buttonHeistVersion)",
        ]
        if let version = payload.appVersion, !version.isEmpty {
            parts.append("version: \(version)")
        }
        if let build = payload.appBuild, !build.isEmpty {
            parts.append("build: \(build)")
        }
        if let identifier = payload.serverInstanceIdentifier, !identifier.isEmpty {
            parts.append("server: \(identifier)")
        }
        if let timestamp = payload.serverTimestampMs {
            parts.append("serverTimestampMs: \(timestamp)")
        }
        return "Pong: " + parts.joined(separator: ", ")
    }

    private static func sessionStateFailureSummary(_ failure: SessionFailurePayload?) -> String? {
        guard let failure else { return nil }
        if let hint = failure.hint {
            return "\(failure.errorCode): \(hint)"
        }
        if let message = failure.message {
            return "\(failure.errorCode): \(message)"
        }
        return failure.errorCode
    }

    private func formatTargetList(_ targets: [String: TargetConfig], defaultTarget: String?) -> String {
        if targets.isEmpty { return "No targets configured" }
        var output = "\(targets.count) target(s):\n"
        for name in targets.keys.sorted() {
            guard let target = targets[name] else { continue }
            let isDefault = name == defaultTarget ? " (default)" : ""
            output += "  \(name): \(target.device)\(isDefault)\n"
        }
        return output.trimmingCharacters(in: .newlines)
    }

    private func formatDeviceList(_ devices: [DiscoveredDevice]) -> String {
        if devices.isEmpty { return "No devices found" }
        var output = "\(devices.count) device(s):\n"
        for (index, device) in devices.enumerated() {
            let id = device.shortId ?? "----"
            let typeLabel = switch device.connectionType {
            case .simulator: "sim"
            case .usb: "usb"
            case .network: "network"
            }
            let name = device.deviceName.isEmpty ? device.appName : "\(device.appName)  (\(device.deviceName))"
            output += "  [\(index)] \(id)  \(name)  [\(typeLabel)]\n"
        }
        return output.trimmingCharacters(in: .newlines)
    }

    // MARK: - Human Format Helpers

    private func formatInterface(_ interface: Interface, detail: InterfaceDetail) -> String {
        let profile = ProjectionProfile(
            kind: detail == .full ? .full : .summary,
            limits: .current()
        )
        return formatInterface(InterfaceProjection(interface: interface, profile: profile))
    }

    private func formatInterface(_ projection: InterfaceProjection) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = "\(projection.elementCount) elements (\(formatter.string(from: projection.timestamp)))\n"
        if let discovery = projection.diagnostics?.discovery {
            output += formatDiscoveryDiagnostics(discovery).joined(separator: "\n")
            output += "\n"
        }
        output += String(repeating: "-", count: 60) + "\n"

        if projection.elementCount == 0 {
            output += "  (no elements)\n"
        } else {
            output += formatTreeLines(projection).joined(separator: "\n")
            output += "\n"
        }
        output += String(repeating: "-", count: 60)
        return output
    }

    private func formatDiscoveryDiagnostics(_ diagnostics: InterfaceDiscoveryDiagnostics) -> [String] {
        let reasonCodes = diagnostics.reasonCodes.map(\.rawValue)
        let reason = reasonCodes.isEmpty ? "" : " [\(reasonCodes.joined(separator: ", "))]"
        var lines = [
            """
            discovery: \(diagnostics.state.rawValue)\(reason), included elements: \(diagnostics.includedElementCount), \
            scroll attempts: \(diagnostics.scrollAttempts)/\(diagnostics.maxScrollsPerDiscovery), \
            explored containers: \(diagnostics.exploredScrollableContainerCount), \
            omitted containers: \(diagnostics.omittedScrollableContainerCount)
            """,
        ]
        if let nextAction = diagnostics.nextAction {
            lines.append("next: \(nextAction)")
        }
        return lines
    }

    private func formatTreeLines(_ interface: Interface, detail: InterfaceDetail) -> [String] {
        let profile = ProjectionProfile(
            kind: detail == .full ? .full : .summary,
            limits: .current()
        )
        return formatTreeLines(InterfaceProjection(interface: interface, profile: profile))
    }

    private func formatTreeLines(_ projection: InterfaceProjection) -> [String] {
        projection.tree.flatMap { formatTreeLines($0, depth: 0, detail: projection.detail) }
    }

    private func formatTreeLines(
        _ node: InterfaceNodeProjection,
        depth: Int,
        detail: InterfaceDetail
    ) -> [String] {
        let prefix = String(repeating: "  ", count: depth)
        switch node {
        case .element(let projection):
            return [prefix + formatElement(
                projection.element,
                displayIndex: projection.order ?? 0,
                detail: detail
            )]
        case .container(let projection):
            let containerLines = formatContainerLines(
                projection.container,
                containerName: projection.containerName,
                detail: detail
            ).map { prefix + $0 }
            let childLines = projection.children.flatMap { child in
                formatTreeLines(
                    child,
                    depth: depth + 1,
                    detail: detail
                )
            }
            return containerLines + childLines
        }
    }

    private func formatElement(_ element: HeistElement, displayIndex: Int, detail: InterfaceDetail) -> String {
        var parts: [String] = [String(format: "[%2d]", displayIndex)]
        var labelValue = Self.quotedString(Self.nonEmpty(element.label) ?? element.description)
        if let value = Self.nonEmpty(element.value) {
            labelValue += " value=\(Self.quotedString(value))"
        }
        parts.append(labelValue)

        let traits = element.traits.filter { $0.rawValue != "none" }
        if !traits.isEmpty {
            parts.append("traits=\(traits.map(\.rawValue).joined(separator: " | "))")
        }
        if !element.actions.isEmpty {
            parts.append("actions=\(element.actions.map(\.description).joined(separator: ", "))")
        }
        if let rotors = element.rotors?.compactMap({ Self.nonEmpty($0.name) }), !rotors.isEmpty {
            parts.append("rotors=\(rotors.map(Self.quotedString).joined(separator: ", "))")
        }
        if let hint = Self.nonEmpty(element.hint) {
            parts.append("hint=\(Self.quotedString(hint))")
        }
        if let identifier = Self.nonEmpty(element.identifier) {
            parts.append("id=\(Self.quotedString(identifier))")
        }
        if detail == .full {
            parts.append("frame=(\(Int(element.frameX)),\(Int(element.frameY)),\(Int(element.frameWidth)),\(Int(element.frameHeight)))")
            parts.append("activation=(\(Int(element.activationPointX)),\(Int(element.activationPointY)))")
        }
        return parts.joined(separator: " ")
    }

    private func formatContainerLines(
        _ container: AccessibilityContainer,
        annotation: InterfaceContainerAnnotation?,
        detail: InterfaceDetail
    ) -> [String] {
        var parts: [String]
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            parts = ["group"]
            if let label = Self.nonEmpty(label) { parts.append(Self.quotedString(label)) }
            if let value = Self.nonEmpty(value) { parts.append("value=\(Self.quotedString(value))") }
            if let identifier = Self.nonEmpty(identifier) { parts.append("id=\(Self.quotedString(identifier))") }
            if let containerName = Self.nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName: \(containerName)")
            }
        case .list:
            parts = ["list"]
            if let containerName = Self.nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName: \(containerName)")
            }
        case .landmark:
            parts = ["landmark"]
            if let containerName = Self.nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName: \(containerName)")
            }
        case .dataTable(let rowCount, let columnCount):
            parts = ["table", "rows=\(rowCount)", "columns=\(columnCount)"]
            if let containerName = Self.nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName: \(containerName)")
            }
        case .tabBar:
            parts = ["tab_bar"]
            if let containerName = Self.nonEmpty(annotation?.containerName?.rawValue) {
                parts.append("containerName: \(containerName)")
            }
        case .scrollable(let contentSize):
            let frame = container.frame
            var lines = ["scrollable"]
            if let containerName = Self.nonEmpty(annotation?.containerName?.rawValue) {
                lines.append("  containerName: \(containerName)")
            }
            lines.append("  viewport: \(Int(frame.size.width))x\(Int(frame.size.height))")
            lines.append("  content: \(Int(contentSize.width))x\(Int(contentSize.height))")
            if container.isModalBoundary {
                lines.append("  modal: true")
            }
            if detail == .full {
                lines.append(
                    "  frame: (\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width)),\(Int(frame.size.height)))"
                )
            }
            return lines
        }
        if container.isModalBoundary {
            parts.append("modal=true")
        }
        if detail == .full {
            let frame = container.frame
            parts.append(
                "frame=(\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.size.width)),\(Int(frame.size.height)))"
            )
        }
        return [parts.joined(separator: " ")]
    }

    private func formatContainerLines(
        _ container: AccessibilityContainer,
        containerName: String?,
        detail: InterfaceDetail
    ) -> [String] {
        formatContainerLines(
            container,
            annotation: containerName.map {
                InterfaceContainerAnnotation(path: .root, containerName: ContainerName(rawValue: $0))
            },
            detail: detail
        )
    }

    private func formatScreenshot(
        summary: String,
        payload: ScreenPayload,
        options: ScreenshotResponseOptions
    ) -> String {
        guard options.includeInterface else { return summary }
        var lines = [summary]
        if let interface = payload.interface {
            lines.append(formatInterface(interface, detail: .full))
        } else {
            lines.append("interface: unavailable")
        }
        return lines.joined(separator: "\n")
    }

    private func formatActionResult(command: TheFence.Command, result: ActionResult) -> String {
        let methodName = command.rawValue
        let projection = ActionProjection(actionMethod: .fence(command), result: result, profile: .summary)
        guard projection.failure == nil else {
            return "Error: \(projection.message ?? methodName)"
        }
        var output = "✓ \(methodName)"
        if case .value(let value) = projection.payload {
            output += "  value: \"\(value)\""
        }
        if case .rotor(let search) = projection.payload {
            output += "  rotor: \"\(search.rotor)\" \(search.direction.rawValue)"
            if let foundElement = search.foundElement {
                output += " → \(foundElement.label ?? foundElement.description)"
            }
            if let textRange = search.textRange {
                output += "  range: \(textRange.rangeDescription)"
                if let text = textRange.text {
                    output += " \"\(text)\""
                }
            }
        }
        if let delta = projection.delta {
            output += "  \(formatDelta(delta))"
        }
        if let activationTrace = projection.activationTrace {
            output += "  [activate: \(Self.compactActivationTrace(activationTrace))]"
        }
        return output
    }

    /// Actions that aren't implied by the element's traits.
    /// `activate` is implied by `.button`; `increment`/`decrement` by `.adjustable`.
    static func meaningfulActions(_ element: HeistElement) -> [ElementAction] {
        element.actions.filter { action in
            switch action {
            case .activate: return !element.traits.contains(.button)
            case .increment, .decrement: return !element.traits.contains(.adjustable)
            case .custom: return true
            }
        }
    }

    private func formatDelta(_ delta: AccessibilityTrace.Delta) -> String {
        formatDelta(DeltaProjection(delta: delta, profile: .summary, includeScreenInterface: true))
    }

    private func formatDelta(_ projection: DeltaProjection) -> String {
        switch projection.kind {
        case .noChange:
            guard !projection.transient.elements.isEmpty else {
                return "[\(projection.elementCount) elements, no change]"
            }
            let transients = projection.transient.elements
                .map { "+- \(Self.compactElementLine($0))" }
                .joined(separator: "; ")
            return "[\(projection.elementCount) elements, no net change: \(transients)]"
        case .elementsChanged:
            var parts: [String] = ["\(projection.elementCount) elements"]
            if let addedCount = projection.edits?.added.elements.count, addedCount > 0 {
                parts.append("+\(addedCount) added")
            }
            if let removedCount = projection.edits?.removed.elements.count, removedCount > 0 {
                parts.append("-\(removedCount) removed")
            }
            if let updatedCount = projection.edits?.updated.updates.count, updatedCount > 0 {
                parts.append("~\(updatedCount) updated")
            }
            let detail = Self.compactElementEditLines(
                edits: projection.edits,
                transient: projection.transient.elements
            )
            guard !detail.isEmpty else {
                return "[" + parts.joined(separator: ", ") + "]"
            }
            return "[" + parts.joined(separator: ", ") + ": " + detail.joined(separator: "; ") + "]"
        case .screenChanged:
            let compactInterface = projection.screen?.interface.map {
                Self.compactInterface($0)
            } ?? ""
            return "[\(projection.elementCount) elements, screen changed]\n" + compactInterface
        }
    }

    private static func compactElementEditLines(edits: DeltaEditsProjection?, transient: [HeistElement]) -> [String] {
        var lines: [String] = []
        lines.append(contentsOf: edits?.added.elements.map { "+ \(compactElementLine($0))" } ?? [])
        lines.append(contentsOf: edits?.removed.elements.map { "- \(compactElementLine($0))" } ?? [])
        for update in edits?.updated.updates ?? [] {
            let name = nonEmpty(update.after.label)
                ?? nonEmpty(update.after.value)
                ?? nonEmpty(update.after.identifier)
                ?? update.after.description
            for change in update.changes where !change.property.isGeometry {
                lines.append("~ \(name): \(change.property.rawValue) \"\(display(change.oldValue))\" -> \"\(display(change.newValue))\"")
            }
        }
        lines.append(contentsOf: transient.map { "+- \(compactElementLine($0))" })
        return lines
    }

    private static func display(_ value: ElementPropertyValue?) -> String {
        value?.displayText ?? "nil"
    }
}

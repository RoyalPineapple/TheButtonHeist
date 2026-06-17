import Foundation

import AccessibilitySnapshotModel
import TheScore

extension FenceResponse {

    // MARK: - Human Formatting

    public func humanFormatted() -> String {
        switch self {
        case .ok(let message):
            return message
        case .error(let message, _):
            return "Error: \(message)"
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
        case .heistExecution(_, let result, _, _):
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
        let formatter = DateFormatter()
        formatter.timeStyle = .medium

        var output = "\(interface.projectedElements.count) elements (\(formatter.string(from: interface.timestamp)))\n"
        output += String(repeating: "-", count: 60) + "\n"

        if interface.projectedElements.isEmpty {
            output += "  (no elements)\n"
        } else {
            output += formatTreeLines(interface, detail: detail).joined(separator: "\n")
            output += "\n"
        }
        output += String(repeating: "-", count: 60)
        return output
    }

    private final class HumanLineIndexCounter {
        var value = 0
    }

    private func formatTreeLines(_ interface: Interface, detail: InterfaceDetail) -> [String] {
        let counter = HumanLineIndexCounter()
        let elementAnnotations = interface.annotations.elementByPath
        let containerAnnotations = interface.annotations.containerByPath
        return interface.tree.enumerated().flatMap { index, node in
            formatTreeLines(
                node,
                path: TreePath([index]),
                depth: 0,
                detail: detail,
                counter: counter,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations
            )
        }
    }

    private func formatTreeLines(
        _ node: AccessibilityHierarchy,
        path: TreePath,
        depth: Int,
        detail: InterfaceDetail,
        counter: HumanLineIndexCounter,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [String] {
        let prefix = String(repeating: "  ", count: depth)
        switch node {
        case .element(let element, _):
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            let displayIndex = counter.value
            counter.value += 1
            return [prefix + formatElement(projected, displayIndex: displayIndex, detail: detail)]
        case .container(let container, let children):
            let containerLines = formatContainerLines(
                container,
                annotation: containerAnnotations[path],
                detail: detail
            ).map { prefix + $0 }
            let childLines = children.enumerated().flatMap { index, child in
                formatTreeLines(
                    child,
                    path: path.appending(index),
                    depth: depth + 1,
                    detail: detail,
                    counter: counter,
                    elementAnnotations: elementAnnotations,
                    containerAnnotations: containerAnnotations
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
            if let containerName = Self.nonEmpty(annotation?.containerName) {
                parts.append("containerName: \(containerName)")
            }
        case .list:
            parts = ["list"]
            if let containerName = Self.nonEmpty(annotation?.containerName) {
                parts.append("containerName: \(containerName)")
            }
        case .landmark:
            parts = ["landmark"]
            if let containerName = Self.nonEmpty(annotation?.containerName) {
                parts.append("containerName: \(containerName)")
            }
        case .dataTable(let rowCount, let columnCount):
            parts = ["table", "rows=\(rowCount)", "columns=\(columnCount)"]
            if let containerName = Self.nonEmpty(annotation?.containerName) {
                parts.append("containerName: \(containerName)")
            }
        case .tabBar:
            parts = ["tab_bar"]
            if let containerName = Self.nonEmpty(annotation?.containerName) {
                parts.append("containerName: \(containerName)")
            }
        case .scrollable(let contentSize):
            let frame = container.frame
            var lines = ["scrollable"]
            if let containerName = Self.nonEmpty(annotation?.containerName) {
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
        guard result.success else {
            return "Error: \(result.message ?? methodName)"
        }
        var output = "✓ \(methodName)"
        if case .value(let value) = result.payload {
            output += "  value: \"\(value)\""
        }
        if case .rotor(let search) = result.payload {
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
        if let delta = result.accessibilityTrace?.endpointDelta {
            output += "  \(formatDelta(delta))"
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
        switch delta {
        case .noChange(let payload):
            return "[\(payload.elementCount) elements, no change]"
        case .elementsChanged(let payload):
            let edits = payload.edits
            var parts: [String] = ["\(payload.elementCount) elements"]
            if !edits.added.isEmpty { parts.append("+\(edits.added.count) added") }
            if !edits.removed.isEmpty { parts.append("-\(edits.removed.count) removed") }
            if !edits.updated.isEmpty { parts.append("~\(edits.updated.count) updated") }
            return "[" + parts.joined(separator: ", ") + "]"
        case .screenChanged(let payload):
            return "[\(payload.elementCount) elements, screen changed]"
        }
    }
}

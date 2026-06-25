import Foundation
import ThePlans

public enum HeistFailureDiagnostics {
    public static let defaultElementLimit = 20

    public static func screenshotSummary(
        _ screenshot: ScreenPayload,
        receiptPath: String? = nil
    ) -> String {
        var parts = [
            "failure screenshot: \(Int(screenshot.width))x\(Int(screenshot.height))",
        ]
        if let receiptPath {
            parts.append("receipt=\(receiptPath)")
        }
        if let interface = screenshot.interface {
            parts.append("interface=\(interface.projectedElements.count) elements")
        } else {
            parts.append("interface=unavailable")
        }
        return parts.joined(separator: " ")
    }

    public static func unavailableScreenshotSummary(
        receiptPath: String,
        message: String?
    ) -> String {
        var parts = ["failure screenshot: unavailable", "receipt=\(receiptPath)"]
        if let message, !message.isEmpty {
            parts.append("message=\(quotedString(message))")
        }
        return parts.joined(separator: " ")
    }

    public static func interfaceDump(
        _ interface: Interface,
        elementLimit: Int = defaultElementLimit
    ) -> String {
        let elements = interface.projectedElements
        let limit = max(0, elementLimit)
        var lines = ["failure interface: \(elements.count) elements"]
        if elements.isEmpty {
            lines.append("  (no elements)")
        } else {
            lines.append(contentsOf: elements.prefix(limit).enumerated().map { index, element in
                "  " + elementLine(element, displayIndex: index, includeGeometry: true)
            })
            let omitted = elements.count - min(elements.count, limit)
            if omitted > 0 {
                lines.append("  ... and \(omitted) more")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func elementLine(
        _ element: HeistElement,
        displayIndex: Int? = nil,
        includeGeometry: Bool = false
    ) -> String {
        var parts: [String] = []
        if let displayIndex { parts.append("[\(displayIndex)]") }

        var labelValue = quotedString(nonEmpty(element.label) ?? "")
        if let value = nonEmpty(element.value) {
            labelValue += ":\(quotedString(value))"
        }
        parts.append(labelValue)

        let traits = element.traits.filter { $0.rawValue != "none" }
        if !traits.isEmpty {
            parts.append(traits.map(\.rawValue).joined(separator: " | "))
        }

        let actions = meaningfulActions(element)
        if !actions.isEmpty {
            parts.append("{\(actions.map(\.description).joined(separator: ", "))}")
        }
        if let rotors = element.rotors?.compactMap({ nonEmpty($0.name) }), !rotors.isEmpty {
            parts.append("[\(rotors.joined(separator: ", "))]")
        }
        if let hint = nonEmpty(element.hint) {
            parts.append("hint=\(quotedString(hint))")
        }
        if let identifier = nonEmpty(element.identifier) {
            parts.append("id=\(quotedString(identifier))")
        }
        if includeGeometry {
            parts.append("frame=(\(Int(element.frameX)),\(Int(element.frameY)),\(Int(element.frameWidth)),\(Int(element.frameHeight)))")
            parts.append("activation=(\(Int(element.activationPointX)),\(Int(element.activationPointY)))")
        }

        return parts.joined(separator: " ")
    }

    public static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    public static func quotedString(_ value: String) -> String {
        if let data = try? JSONEncoder().encode(value),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func meaningfulActions(_ element: HeistElement) -> [ElementAction] {
        element.actions.filter { action in
            switch action {
            case .activate: return !element.traits.contains(.button)
            case .increment, .decrement: return !element.traits.contains(.adjustable)
            case .custom: return true
            }
        }
    }
}

public extension HeistExecutionResult {
    var failureScreenshotStep: HeistExecutionStepResult? {
        steps.firstFailureScreenshotStep
    }

    var failureScreenshotPayload: ScreenPayload? {
        failureScreenshotStep?.screenshotPayload
    }

    var settledInterfaceAtFailure: Interface? {
        firstFailedStep?.settledInterfaceAtStep
    }

    var failureDiagnosticInterface: Interface? {
        failureScreenshotPayload?.interface ?? settledInterfaceAtFailure
    }

    var failureScreenshotSummary: String? {
        guard let step = failureScreenshotStep else { return nil }
        if let screenshot = step.screenshotPayload {
            return HeistFailureDiagnostics.screenshotSummary(screenshot, receiptPath: step.path)
        }
        return HeistFailureDiagnostics.unavailableScreenshotSummary(
            receiptPath: step.path,
            message: step.reportActionResult?.message
        )
    }

    func failureInterfaceDump(
        elementLimit: Int = HeistFailureDiagnostics.defaultElementLimit
    ) -> String? {
        failureDiagnosticInterface.map {
            HeistFailureDiagnostics.interfaceDump($0, elementLimit: elementLimit)
        }
    }
}

public extension HeistExecutionStepResult {
    var settledInterfaceAtStep: Interface? {
        traceEvidenceResult?.accessibilityTrace?.captures.last?.interface
    }

    var screenshotPayload: ScreenPayload? {
        guard case .screenshot(let screenshot) = actionEvidence?.actionResult?.payload else {
            return nil
        }
        return screenshot
    }
}

private extension Array where Element == HeistExecutionStepResult {
    var firstFailureScreenshotStep: HeistExecutionStepResult? {
        for step in self {
            if let screenshotStep = step.firstFailureScreenshotStep {
                return screenshotStep
            }
        }
        return nil
    }
}

private extension HeistExecutionStepResult {
    var firstFailureScreenshotStep: HeistExecutionStepResult? {
        if isFailureScreenshotAction {
            return self
        }
        return children.firstFailureScreenshotStep
    }

    var isFailureScreenshotAction: Bool {
        path.contains(".failure.actions[") && actionEvidence?.command?.wireType == .takeScreenshot
    }
}

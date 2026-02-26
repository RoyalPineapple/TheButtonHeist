import Foundation
import Darwin
import ButtonHeist

// MARK: - Output Helpers

/// Write to stderr (status messages)
func logStatus(_ message: String) {
    fputs("\(message)\n", stderr)
}

/// Write to stdout (data output)
func writeOutput(_ message: String) {
    print(message)
    fflush(stdout)
}

/// Build a JSON-compatible dictionary from an ActionResult.
func actionResultDict(_ result: ActionResult) -> [String: Any] {
    var d: [String: Any] = [
        "status": result.success ? "ok" : "error",
        "method": result.method.rawValue,
    ]
    if let msg = result.message { d["message"] = msg }
    if let value = result.value { d["value"] = value }
    if result.animating == true { d["animating"] = true }
    if let delta = result.interfaceDelta {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(delta),
           let deltaObj = try? JSONSerialization.jsonObject(with: data) {
            d["delta"] = deltaObj
        }
    }
    return d
}

/// Format an ActionResult as a JSON string matching the session protocol format.
func formatActionResultJSON(_ result: ActionResult) -> String {
    let d = actionResultDict(result)
    if let data = try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return "{\"status\":\"error\",\"message\":\"Serialization failed\"}"
}

// MARK: - Exit Codes

enum ExitCode: Int32 {
    case success = 0
    case connectionFailed = 1
    case noDeviceFound = 2
    case timeout = 3
    case authFailed = 4
    case unknown = 99
}

// MARK: - Action Result Output

/// Shared output handler for action results used by action, touch, type, edit, and dismiss commands.
@MainActor
func outputActionResult(_ result: ActionResult, format: OutputFormat?, quiet: Bool, verb: String = "Action") {
    switch format ?? .auto {
    case .json:
        writeOutput(formatActionResultJSON(result))
        if !result.success { Darwin.exit(1) }
    case .human:
        if result.success {
            if !quiet { logStatus("\(verb) succeeded (method: \(result.method.rawValue))") }
            writeOutput(result.value ?? "success")
        } else {
            let msg = result.message ?? result.method.rawValue
            if !quiet { logStatus("\(verb) failed: \(msg)") }
            writeOutput("failed: \(msg)")
            Darwin.exit(1)
        }
    }
}

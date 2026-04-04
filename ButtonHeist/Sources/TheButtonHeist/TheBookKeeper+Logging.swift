import Foundation

extension TheBookKeeper {

    /// Keys that carry binary data and should be excluded from session logs.
    private static let binaryKeys: Set<String> = ["pngData", "videoData"]

    func buildCommandLogEntry(
        requestId: String,
        command: TheFence.Command,
        arguments: [String: Any]
    ) -> [String: Any] {
        var sanitizedArgs: [String: Any] = [:]
        for (key, value) in arguments where key != "command" {
            if Self.binaryKeys.contains(key) {
                continue
            }
            if let stringValue = value as? String, stringValue.count > 1000 {
                sanitizedArgs[key] = "<\(stringValue.count) chars>"
                continue
            }
            sanitizedArgs[key] = Self.jsonSafeValue(value)
        }

        var entry: [String: Any] = [
            "t": iso8601Now(),
            "type": "command",
            "requestId": requestId,
            "command": command.rawValue,
        ]
        if !sanitizedArgs.isEmpty {
            entry["args"] = sanitizedArgs
        }
        return entry
    }

    func buildResponseLogEntry(
        requestId: String,
        status: ResponseStatus,
        durationMilliseconds: Int,
        artifact: String?,
        error: String?
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "t": iso8601Now(),
            "type": "response",
            "requestId": requestId,
            "status": status.rawValue,
            "duration_ms": durationMilliseconds,
        ]
        if let artifact {
            entry["artifact"] = artifact
        }
        if let error {
            entry["error"] = error
        }
        return entry
    }

    func appendLogLine(_ entry: [String: Any], to handle: FileHandle) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
        var lineData = jsonData
        lineData.append(contentsOf: [0x0A]) // newline
        try handle.write(contentsOf: lineData)
    }

    // MARK: - Private Helpers

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    private static func jsonSafeValue(_ value: Any) -> Any {
        if value is String || value is Int || value is Double || value is Bool {
            return value
        }
        if let array = value as? [Any] {
            return array.map { jsonSafeValue($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.mapValues { jsonSafeValue($0) }
        }
        return String(describing: value)
    }
}

import Foundation

extension TheBookKeeper {

    // MARK: - Session Log Construction

    /// Keys that carry binary data and should be excluded from session logs.
    private static let binaryKeys: Set<String> = ["pngData", "videoData"]
    private static let maxLoggedStringLength = 1000

    /// Build a sanitized log entry for an incoming command.
    func buildCommandLogEntry(
        requestId: String,
        command: TheFence.Command,
        arguments: [String: Any]
    ) -> [String: Any] {
        var sanitizedArgs: [String: Any] = [:]
        for (key, value) in arguments where key != "command" && !key.hasPrefix("_") {
            guard let sanitized = Self.jsonSafeValue(value, key: key) else {
                continue
            }
            sanitizedArgs[key] = sanitized
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

    /// Build a sanitized log entry for a command response.
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

    /// Serialize a log entry as JSON and append it to the session log file.
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

    private static func jsonSafeValue(_ value: Any, key: String? = nil) -> Any? {
        if let key, binaryKeys.contains(key) {
            return nil
        }
        if let string = value as? String {
            if string.count > maxLoggedStringLength {
                return "<\(string.count) chars>"
            }
            return string
        }
        if value is Int || value is Double || value is Bool {
            return value
        }
        if let array = value as? [Any] {
            return array.compactMap { jsonSafeValue($0) }
        }
        if let dict = value as? [String: Any] {
            return dict.reduce(into: [String: Any]()) { result, pair in
                if let nested = jsonSafeValue(pair.value, key: pair.key) {
                    result[pair.key] = nested
                }
            }
        }
        let fallback = String(describing: value)
        if fallback.count > maxLoggedStringLength {
            return "<\(fallback.count) chars>"
        }
        return fallback
    }
}

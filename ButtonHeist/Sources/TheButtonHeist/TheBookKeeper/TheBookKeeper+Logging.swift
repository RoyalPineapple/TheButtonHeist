import Foundation

import TheScore

// MARK: - Typed Command Records

/// Command argument keys BookKeeper treats specially while recording logs and heists.
enum BookKeeperCommandArgumentKey {
    static let command = "command"
    static let heistId = "heistId"
    static let label = "label"
    static let identifier = "identifier"
    static let value = "value"
    static let traits = "traits"
    static let excludeTraits = "excludeTraits"
    static let x = "x"
    static let startX = "startX"
    static let centerX = "centerX"
    static let points = "points"
    static let pngData = "pngData"
    static let videoData = "videoData"
    static let hiddenPrefix = "_"

    static let binaryKeys: Set<String> = [pngData, videoData]
}

/// Typed command data recorded by BookKeeper before JSON serialization.
struct BookKeeperCommandRecord: Sendable, Equatable {
    let requestId: String
    let command: TheFence.Command
    let arguments: [String: HeistValue]
    let unsupportedArguments: [RecordedUnsupportedInput]

    init(
        requestId: String,
        command: TheFence.Command,
        arguments: [String: HeistValue] = [:],
        unsupportedArguments: [RecordedUnsupportedInput] = []
    ) {
        self.requestId = requestId
        self.command = command
        self.arguments = arguments
        self.unsupportedArguments = unsupportedArguments
    }

    init(requestId: String, command: TheFence.Command, rawArguments: [String: Any]) {
        var convertedArguments: [String: HeistValue] = [:]
        var unsupportedArguments: [RecordedUnsupportedInput] = []

        for key in rawArguments.keys.sorted() where Self.shouldRecordTopLevelKey(key) {
            guard let rawValue = rawArguments[key] else { continue }
            switch Self.heistValue(from: rawValue, key: key) {
            case .value(let value):
                convertedArguments[key] = value
            case .omitted:
                continue
            case .unsupported:
                unsupportedArguments.append(RecordedUnsupportedInput(
                    name: key,
                    valueType: Self.typeDescription(of: rawValue),
                    reason: "not JSON-compatible; omitted from replay arguments"
                ))
            }
        }

        self.init(
            requestId: requestId,
            command: command,
            arguments: convertedArguments,
            unsupportedArguments: unsupportedArguments
        )
    }

    func contains(_ key: String) -> Bool {
        arguments[key] != nil
    }

    func string(for key: String) -> String? {
        guard case .string(let value) = arguments[key] else { return nil }
        return value
    }

    func stringArray(for key: String) -> [String]? {
        guard case .array(let values) = arguments[key] else { return nil }
        var strings: [String] = []
        for value in values {
            guard case .string(let string) = value else { return nil }
            strings.append(string)
        }
        return strings
    }

    func sortedPairs() -> [(key: String, value: HeistValue)] {
        arguments.sorted { $0.key < $1.key }
    }

    func logJSONObject(maxStringLength: Int) -> [String: Any] {
        arguments.reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value.logJSONValue(maxStringLength: maxStringLength)
        }
    }

    private static func shouldRecordTopLevelKey(_ key: String) -> Bool {
        key != BookKeeperCommandArgumentKey.command &&
            !key.hasPrefix(BookKeeperCommandArgumentKey.hiddenPrefix) &&
            !BookKeeperCommandArgumentKey.binaryKeys.contains(key)
    }

    private static func heistValue(from rawValue: Any, key: String? = nil) -> ArgumentConversion {
        // Top-level binary keys are filtered before conversion; this also handles nested payloads.
        if let key, BookKeeperCommandArgumentKey.binaryKeys.contains(key) {
            return .omitted
        }

        switch rawValue {
        case let arrayValue as [Any]:
            return heistArray(from: arrayValue)
        case let objectValue as [String: Any]:
            return heistObject(from: objectValue)
        case let doubleValue as Double where !doubleValue.isFinite:
            return .unsupported
        default:
            return HeistValue.from(rawValue).map(ArgumentConversion.value) ?? .unsupported
        }
    }

    private static func heistArray(from rawValues: [Any]) -> ArgumentConversion {
        var values: [HeistValue] = []
        for rawValue in rawValues {
            switch heistValue(from: rawValue) {
            case .value(let value):
                values.append(value)
            case .omitted:
                continue
            case .unsupported:
                return .unsupported
            }
        }
        return .value(.array(values))
    }

    private static func heistObject(from rawValues: [String: Any]) -> ArgumentConversion {
        var values: [String: HeistValue] = [:]
        for key in rawValues.keys.sorted() {
            guard let rawValue = rawValues[key] else { continue }
            switch heistValue(from: rawValue, key: key) {
            case .value(let value):
                values[key] = value
            case .omitted:
                continue
            case .unsupported:
                return .unsupported
            }
        }
        return .value(.object(values))
    }

    private static func typeDescription(of value: Any) -> String {
        String(describing: Swift.type(of: value))
    }

    private enum ArgumentConversion {
        case value(HeistValue)
        case omitted
        case unsupported
    }
}

private extension HeistValue {
    func logJSONValue(maxStringLength: Int) -> Any {
        switch self {
        case .string(let value):
            return value.logJSONValue(maxStringLength: maxStringLength)
        case .int(let value):
            return value
        case .double(let value):
            return value
        case .bool(let value):
            return value
        case .array(let values):
            return values.map { $0.logJSONValue(maxStringLength: maxStringLength) }
        case .object(let values):
            return values.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = pair.value.logJSONValue(maxStringLength: maxStringLength)
            }
        }
    }
}

private extension String {
    func logJSONValue(maxStringLength: Int) -> String {
        if count > maxStringLength {
            return "<\(count) chars>"
        }
        return self
    }
}

extension TheBookKeeper {

    // MARK: - Session Log Construction

    private static let maxLoggedStringLength = 1000

    /// Build the header entry that identifies a session log stream.
    func buildHeaderLogEntry(sessionId: String) -> [String: Any] {
        [
            "type": "header",
            "formatVersion": SessionFormatVersion.current,
            "sessionId": sessionId,
        ]
    }

    /// Build a sanitized log entry for an incoming command.
    func buildCommandLogEntry(_ record: BookKeeperCommandRecord) -> [String: Any] {
        var entry: [String: Any] = [
            "t": iso8601Now(),
            "type": "command",
            "requestId": record.requestId,
            "command": record.command.rawValue,
        ]
        let sanitizedArgs = record.logJSONObject(maxStringLength: Self.maxLoggedStringLength)
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
}

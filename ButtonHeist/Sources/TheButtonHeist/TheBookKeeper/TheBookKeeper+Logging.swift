import Foundation

import TheScore

private extension Dictionary where Key == String, Value == HeistValue {
    mutating func appendExpectation(_ expectation: ActionExpectation?, timeout: Double?) {
        if let expectation {
            self["expect"] = .encoded(expectation)
        }
        if let timeout {
            self["timeout"] = .encoded(timeout)
        }
    }
}

extension TheFence.ParsedRequest {
    var heistEvidenceArguments: [String: HeistValue] {
        var arguments = heistRecordingArguments
        if command != .waitForChange {
            let timeout = expectationPayload.expectation == nil ? nil : expectationPayload.timeout
            arguments.appendExpectation(expectationPayload.expectation, timeout: timeout)
        }
        return arguments
    }
}

struct HeaderLogEntry: Encodable {
    let type = "header"
    let formatVersion: String
    let sessionId: String
}

struct CommandLogEntry: Encodable {
    let t: String
    let type = "command"
    let requestId: String
    let command: String
}

struct ResponseLogEntry: Encodable {
    let t: String
    let type = "response"
    let requestId: String
    let status: ResponseStatus
    let durationMilliseconds: Int
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case t
        case type
        case requestId
        case status
        case durationMilliseconds = "duration_ms"
        case error
    }
}

struct ArtifactLogEntry: Encodable {
    let t: String
    let type = "artifact"
    let artifactType: ArtifactType
    let path: String
    let size: Int
    let requestId: String
    let command: String
    let metadata: [String: Double]?
}

extension TheBookKeeper {

    // MARK: - Session Log Construction

    /// Serialize a log entry as JSON and append it to the session log file.
    private static let sessionLogEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func appendLogLine<Entry: Encodable>(_ entry: Entry, to handle: FileHandle) throws {
        let jsonData = try Self.sessionLogEncoder.encode(entry)
        var lineData = jsonData
        lineData.append(contentsOf: [0x0A]) // newline
        try handle.write(contentsOf: lineData)
    }

    func iso8601Now() -> String {
        iso8601String(from: Date())
    }

    func iso8601String(from date: Date) -> String {
        Self.iso8601Formatter().string(from: date)
    }

    private static func iso8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

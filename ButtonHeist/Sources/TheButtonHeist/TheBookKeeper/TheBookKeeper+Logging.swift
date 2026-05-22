import Foundation

import TheScore

// MARK: - Typed Request Recording

private extension HeistValue {
    static func encoded<T: Encodable>(_ value: T) -> HeistValue {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(HeistValue.self, from: data)
        } catch {
            return .object([
                "type": .string("encoding_failed"),
                "error": .string(String(describing: error)),
            ])
        }
    }
}

private extension Dictionary where Key == String, Value == HeistValue {
    subscript(_ key: FenceParameterKey) -> HeistValue? {
        get { self[key.rawValue] }
        set { self[key.rawValue] = newValue }
    }

    mutating func set(_ key: String, _ value: String?) {
        guard let value else { return }
        self[key] = .string(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: String?) {
        set(key.rawValue, value)
    }

    mutating func set(_ key: String, _ value: Int?) {
        guard let value else { return }
        self[key] = .int(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: Int?) {
        set(key.rawValue, value)
    }

    mutating func set(_ key: String, _ value: Double?) {
        guard let value else { return }
        self[key] = .double(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: Double?) {
        set(key.rawValue, value)
    }

    mutating func set(_ key: String, _ value: Bool?) {
        guard let value else { return }
        self[key] = .bool(value)
    }

    mutating func set(_ key: FenceParameterKey, _ value: Bool?) {
        set(key.rawValue, value)
    }

    mutating func set<E: RawRepresentable>(_ key: String, _ value: E?) where E.RawValue == String {
        guard let value else { return }
        self[key] = .string(value.rawValue)
    }

    mutating func set<E: RawRepresentable>(_ key: FenceParameterKey, _ value: E?) where E.RawValue == String {
        set(key.rawValue, value)
    }

    mutating func appendExpectation(_ expectation: ActionExpectation?, timeout: Double?) {
        if let expectation {
            self[.expect] = HeistValue.encoded(expectation)
        }
        set(.timeout, timeout)
    }
}

extension TheFence {
    struct HeistEvidenceProjection {
        let command: Command
        let arguments: [String: HeistValue]
        let elementTarget: ElementTarget?
        let coordinateOnly: Bool
    }
}

extension TheFence.ParsedRequest {
    var heistEvidenceProjection: TheFence.HeistEvidenceProjection {
        TheFence.HeistEvidenceProjection(
            command: command,
            arguments: heistEvidenceArguments,
            elementTarget: payload.bookKeeperElementTarget,
            coordinateOnly: payload.bookKeeperCoordinateOnly
        )
    }

    private var heistEvidenceArguments: [String: HeistValue] {
        var arguments = payload.heistEvidenceArguments
        if command != .waitForChange {
            let timeout = expectationPayload.expectation == nil ? nil : expectationPayload.timeout
            arguments.appendExpectation(expectationPayload.expectation, timeout: timeout)
        }
        return arguments
    }
}

private extension TheFence.RequestPayload {
    var heistEvidenceArguments: [String: HeistValue] {
        switch self {
        case .gesture(let payload):
            return payload.bookKeeperArguments
        case .scroll(let payload):
            return payload.bookKeeperArguments
        case .accessibility(let payload):
            return payload.bookKeeperArguments
        case .rotor(let target):
            return target.bookKeeperArguments
        case .typeText(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.text, target.text)
            return arguments
        case .editAction(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.action, target.action)
            return arguments
        case .setPasteboard(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.text, target.text)
            return arguments
        case .waitFor(let target):
            return target.bookKeeperArguments
        case .waitForChange(let payload):
            var arguments: [String: HeistValue] = [:]
            arguments.appendExpectation(payload.expectation, timeout: payload.timeout)
            return arguments
        case .none, .getInterface, .screen, .artifact, .startRecording, .connect,
             .runBatch, .archiveSession, .startHeist, .stopHeist, .playHeist:
            return [:]
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .gesture(let payload):
            return payload.bookKeeperElementTarget
        case .scroll(let payload):
            return payload.bookKeeperElementTarget
        case .accessibility(let payload):
            return payload.bookKeeperElementTarget
        case .rotor(let target):
            return target.elementTarget
        case .typeText(let target):
            return target.elementTarget
        case .waitFor(let target):
            return target.elementTarget
        case .none, .getInterface, .screen, .artifact, .editAction, .setPasteboard,
             .waitForChange, .startRecording, .connect, .runBatch, .archiveSession,
             .startHeist, .stopHeist, .playHeist:
            return nil
        }
    }

    var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .gesture(let payload):
            return payload.bookKeeperCoordinateOnly
        default:
            return false
        }
    }
}

private extension TheFence.GesturePayload {
    var bookKeeperArguments: [String: HeistValue] {
        switch self {
        case .oneFingerTap(let payload):
            return payload.target.bookKeeperArguments
        case .longPress(let payload):
            return payload.target.bookKeeperArguments
        case .swipe(let payload):
            return payload.target.bookKeeperArguments
        case .drag(let payload):
            return payload.target.bookKeeperArguments
        case .pinch(let payload):
            return payload.target.bookKeeperArguments
        case .rotate(let payload):
            return payload.target.bookKeeperArguments
        case .twoFingerTap(let payload):
            return payload.target.bookKeeperArguments
        case .drawPath(let payload):
            return payload.target.bookKeeperArguments
        case .drawBezier(let payload):
            return payload.target.bookKeeperArguments
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .oneFingerTap(let payload):
            return payload.elementTarget
        case .longPress(let payload):
            return payload.elementTarget
        case .swipe(let payload):
            return payload.elementTarget
        case .drag(let payload):
            return payload.elementTarget
        case .pinch(let payload):
            return payload.elementTarget
        case .rotate(let payload):
            return payload.elementTarget
        case .twoFingerTap(let payload):
            return payload.elementTarget
        case .drawPath, .drawBezier:
            return nil
        }
    }

    var bookKeeperCoordinateOnly: Bool {
        switch self {
        case .oneFingerTap(let payload):
            return payload.elementTarget == nil && payload.target.point != nil
        case .longPress(let payload):
            return payload.elementTarget == nil && payload.target.point != nil
        case .swipe(let payload):
            return payload.elementTarget == nil
        case .drag(let payload):
            return payload.elementTarget == nil
        case .pinch(let payload):
            return payload.elementTarget == nil
        case .rotate(let payload):
            return payload.elementTarget == nil
        case .twoFingerTap(let payload):
            return payload.elementTarget == nil
        case .drawPath, .drawBezier:
            return true
        }
    }
}

private extension TouchTapTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.x, pointX)
        arguments.set(.y, pointY)
        return arguments
    }
}

private extension LongPressTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.x, pointX)
        arguments.set(.y, pointY)
        arguments.set(.duration, duration)
        return arguments
    }
}

private extension SwipeTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.direction, direction)
        arguments.set(.startX, startX)
        arguments.set(.startY, startY)
        arguments.set(.endX, endX)
        arguments.set(.endY, endY)
        arguments.set(.duration, duration)
        if let start {
            arguments[.start] = HeistValue.encoded(start)
        }
        if let end {
            arguments[.end] = HeistValue.encoded(end)
        }
        return arguments
    }
}

private extension DragTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.startX, startX)
        arguments.set(.startY, startY)
        arguments.set(.endX, endX)
        arguments.set(.endY, endY)
        arguments.set(.duration, duration)
        return arguments
    }
}

private extension PinchTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.centerX, centerX)
        arguments.set(.centerY, centerY)
        arguments.set(.scale, scale)
        arguments.set(.spread, spread)
        arguments.set(.duration, duration)
        return arguments
    }
}

private extension RotateTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.centerX, centerX)
        arguments.set(.centerY, centerY)
        arguments.set(.angle, angle)
        arguments.set(.radius, radius)
        arguments.set(.duration, duration)
        return arguments
    }
}

private extension TwoFingerTapTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.centerX, centerX)
        arguments.set(.centerY, centerY)
        arguments.set(.spread, spread)
        return arguments
    }
}

private extension DrawPathTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments[.points] = .array(points.map { HeistValue.encoded($0) })
        arguments.set(.duration, duration)
        arguments.set(.velocity, velocity)
        return arguments
    }
}

private extension DrawBezierTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.startX, startX)
        arguments.set(.startY, startY)
        arguments[.segments] = .array(segments.map { HeistValue.encoded($0) })
        arguments.set(.samplesPerSegment, samplesPerSegment)
        arguments.set(.duration, duration)
        arguments.set(.velocity, velocity)
        return arguments
    }
}

private extension TheFence.ScrollPayload {
    var bookKeeperArguments: [String: HeistValue] {
        switch self {
        case .scroll(let target):
            return target.bookKeeperArguments
        case .scrollToVisible:
            return [:]
        case .elementSearch(let target):
            var arguments: [String: HeistValue] = [:]
            arguments.set(.direction, target.direction)
            return arguments
        case .scrollToEdge(let target):
            return target.bookKeeperArguments
        }
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .scroll(let target):
            return target.elementTarget
        case .scrollToVisible(let target):
            return target.elementTarget
        case .elementSearch(let target):
            return target.elementTarget
        case .scrollToEdge(let target):
            return target.elementTarget
        }
    }
}

private extension ScrollTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.direction, direction)
        return arguments
    }
}

private extension ScrollToEdgeTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.edge, edge)
        return arguments
    }
}

private extension TheFence.AccessibilityPayload {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        switch self {
        case .activate(_, let actionName, let count):
            arguments.set(.action, actionName)
            arguments.set(.count, count.value)
        case .increment(_, let count),
             .decrement(_, let count):
            arguments.set(.count, count.value)
        case .performCustomAction(let target, let count):
            arguments.set(.action, target.actionName)
            arguments.set(.count, count.value)
        }
        return arguments
    }

    var bookKeeperElementTarget: ElementTarget? {
        switch self {
        case .activate(let target, _, _),
             .increment(let target, _),
             .decrement(let target, _):
            return target
        case .performCustomAction(let target, _):
            return target.elementTarget
        }
    }
}

private extension RotorTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.rotor, rotor)
        arguments.set(.rotorIndex, rotorIndex)
        arguments.set(.direction, direction)
        arguments.set(.currentHeistId, currentHeistId)
        arguments.set(.currentTextStartOffset, currentTextRange?.startOffset)
        arguments.set(.currentTextEndOffset, currentTextRange?.endOffset)
        return arguments
    }
}

private extension WaitForTarget {
    var bookKeeperArguments: [String: HeistValue] {
        var arguments: [String: HeistValue] = [:]
        arguments.set(.absent, absent)
        arguments.set(.timeout, timeout)
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
    let artifact: String?
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case t
        case type
        case requestId
        case status
        case durationMilliseconds = "duration_ms"
        case artifact
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

private struct SessionLogProjectionLine: Decodable {
    let type: String?
    let t: String?
    let status: String?
    let artifactType: String?
    let path: String?
    let size: Int?
    let requestId: String?
    let command: String?
    let metadata: [String: Double]?

    var artifact: ArtifactEntry? {
        guard type == "artifact",
              let artifactType,
              let type = ArtifactType(rawValue: artifactType),
              let path,
              let size,
              let t,
              let timestamp = Self.date(from: t),
              let requestId,
              let command else {
            return nil
        }

        return ArtifactEntry(
            type: type,
            path: path,
            size: size,
            timestamp: timestamp,
            requestId: requestId,
            command: command,
            metadata: metadata ?? [:]
        )
    }

    private static func date(from string: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
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

    /// Derive metadata projections from the append-only session log.
    func sessionLogProjection(
        in directory: URL
    ) throws -> (counts: SessionLogCounts, artifacts: [ArtifactEntry], status: SessionLogProjectionStatus) {
        let data = try sessionLogData(in: directory)
        return Self.sessionLogProjection(in: data)
    }

    /// Derive metadata projections from the session log stored in an archive.
    func sessionLogProjection(
        inArchive archivePath: URL
    ) throws -> (counts: SessionLogCounts, artifacts: [ArtifactEntry], status: SessionLogProjectionStatus) {
        let data = try Self.archivedSessionLogData(from: archivePath)
        return Self.sessionLogProjection(in: data)
    }

    // MARK: - Private Helpers

    private func sessionLogData(in directory: URL) throws -> Data {
        let logPath = directory.appendingPathComponent("session.jsonl")
        if FileManager.default.fileExists(atPath: logPath.path) {
            return try Data(contentsOf: logPath)
        }

        let compressedPath = directory.appendingPathComponent("session.jsonl.gz")
        if FileManager.default.fileExists(atPath: compressedPath.path) {
            return try Self.gunzippedData(at: compressedPath)
        }

        throw CocoaError(.fileReadNoSuchFile, userInfo: [
            NSFilePathErrorKey: logPath.path,
        ])
    }

    private static func sessionLogProjection(
        in data: Data
    ) -> (counts: SessionLogCounts, artifacts: [ArtifactEntry], status: SessionLogProjectionStatus) {
        var commandCount = 0
        var errorCount = 0
        var artifacts: [ArtifactEntry] = []
        var malformedLineCount = 0
        var firstMalformedLineNumber: Int?
        var firstMalformedLineCause: String?
        var malformedArtifactCount = 0

        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
        for (lineOffset, line) in lines.enumerated() {
            let lineNumber = lineOffset + 1
            if line.isEmpty {
                if lineOffset == lines.count - 1 && data.last == 0x0A {
                    continue
                }
                recordMalformedLine(
                    lineNumber: lineNumber,
                    cause: "empty line",
                    malformedLineCount: &malformedLineCount,
                    firstMalformedLineNumber: &firstMalformedLineNumber,
                    firstMalformedLineCause: &firstMalformedLineCause
                )
                continue
            }

            let entry: SessionLogProjectionLine
            do {
                entry = try JSONDecoder().decode(SessionLogProjectionLine.self, from: Data(line))
            } catch {
                recordMalformedLine(
                    lineNumber: lineNumber,
                    cause: "invalid JSON: \(error.localizedDescription)",
                    malformedLineCount: &malformedLineCount,
                    firstMalformedLineNumber: &firstMalformedLineNumber,
                    firstMalformedLineCause: &firstMalformedLineCause
                )
                continue
            }

            guard let type = entry.type else {
                recordMalformedLine(
                    lineNumber: lineNumber,
                    cause: "missing type",
                    malformedLineCount: &malformedLineCount,
                    firstMalformedLineNumber: &firstMalformedLineNumber,
                    firstMalformedLineCause: &firstMalformedLineCause
                )
                continue
            }

            switch type {
            case "command":
                commandCount += 1
            case "response" where entry.status == ResponseStatus.error.rawValue:
                errorCount += 1
            case "artifact":
                if let artifact = entry.artifact {
                    artifacts.append(artifact)
                } else {
                    malformedArtifactCount += 1
                }
            default:
                continue
            }
        }

        let counts = SessionLogCounts(commandCount: commandCount, errorCount: errorCount)
        let status = SessionLogProjectionStatus(
            malformedLineCount: malformedLineCount,
            firstMalformedLineNumber: firstMalformedLineNumber,
            firstMalformedLineCause: firstMalformedLineCause,
            malformedArtifactCount: malformedArtifactCount
        )
        return (counts: counts, artifacts: artifacts, status: status)
    }

    private static func recordMalformedLine(
        lineNumber: Int,
        cause: String,
        malformedLineCount: inout Int,
        firstMalformedLineNumber: inout Int?,
        firstMalformedLineCause: inout String?
    ) {
        malformedLineCount += 1
        guard firstMalformedLineNumber == nil else { return }
        firstMalformedLineNumber = lineNumber
        firstMalformedLineCause = cause
    }

    private static func gunzippedData(at path: URL) throws -> Data {
        try processOutput(
            executablePath: "/usr/bin/gzip",
            arguments: ["-dc", path.path],
            failureContext: "gzip -dc",
            failure: BookKeeperError.compressionFailed
        )
    }

    private static func gunzippedData(_ data: Data) throws -> Data {
        let temporaryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).session.jsonl.gz")
        try data.write(to: temporaryPath, options: .atomic)
        defer {
            try? FileManager.default.removeItem(at: temporaryPath)
        }
        return try gunzippedData(at: temporaryPath)
    }

    private static func archivedSessionLogData(from archivePath: URL) throws -> Data {
        let listingData = try processOutput(
            executablePath: "/usr/bin/tar",
            arguments: ["-tzf", archivePath.path],
            failureContext: "tar -tzf",
            failure: BookKeeperError.archiveFailed
        )
        let listing = String(data: listingData, encoding: .utf8) ?? ""
        let entries = listing.split(separator: "\n").map(String.init)

        if let logEntry = entries.first(where: { $0.hasSuffix("/session.jsonl") || $0 == "session.jsonl" }) {
            return try archivedEntryData(logEntry, from: archivePath)
        }

        if let compressedEntry = entries.first(where: { $0.hasSuffix("/session.jsonl.gz") || $0 == "session.jsonl.gz" }) {
            let compressedData = try archivedEntryData(compressedEntry, from: archivePath)
            return try gunzippedData(compressedData)
        }

        throw BookKeeperError.archiveFailed("Expected session log not found in archive \(archivePath.path)")
    }

    private static func archivedEntryData(_ entry: String, from archivePath: URL) throws -> Data {
        try processOutput(
            executablePath: "/usr/bin/tar",
            arguments: ["-xOzf", archivePath.path, entry],
            failureContext: "tar -xOzf",
            failure: BookKeeperError.archiveFailed
        )
    }

    private static func processOutput(
        executablePath: String,
        arguments: [String],
        failureContext: String,
        failure: (String) -> BookKeeperError
    ) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).process.stderr")
        FileManager.default.createFile(atPath: errorPath.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errorPath)
        defer {
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: errorPath)
        }
        process.standardOutput = outputPipe
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            try? errorHandle.close()
            let errorOutput = try Data(contentsOf: errorPath)
            let detail = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw failure(
                "\(failureContext) exited with status \(process.terminationStatus): \(detail ?? "unknown error")"
            )
        }

        return output
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

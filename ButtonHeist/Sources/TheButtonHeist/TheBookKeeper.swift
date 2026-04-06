import Foundation

// MARK: - Session Phase State Machine

@ButtonHeistActor
public enum SessionPhase: Sendable {
    case idle
    case active(ActiveSession)
    case closing(ClosingSession)
    case closed(ClosedSession)
    case archived(ArchivedSession)
}

@ButtonHeistActor
public struct ActiveSession: Sendable {
    public let sessionId: String
    public let directory: URL
    public let logHandle: FileHandle
    public var manifest: SessionManifest
    public let startTime: Date
    public var nextSequenceNumber: Int
}

@ButtonHeistActor
public struct ClosingSession: Sendable {
    public let sessionId: String
    public let directory: URL
    public var manifest: SessionManifest
    public let startTime: Date
    public let endTime: Date
}

@ButtonHeistActor
public struct ClosedSession: Sendable {
    public let sessionId: String
    public let directory: URL
    public let compressedLogPath: URL
    public let manifest: SessionManifest
    public let startTime: Date
    public let endTime: Date
}

@ButtonHeistActor
public struct ArchivedSession: Sendable {
    public let archivePath: URL
    public let manifest: SessionManifest
    public let startTime: Date
    public let endTime: Date
}

// MARK: - BookKeeper Errors

public enum BookKeeperError: Error, LocalizedError {
    case invalidPhase(expected: String, actual: String)
    case unsafePath(String)
    case base64DecodingFailed
    case compressionFailed(String)
    case archiveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPhase(let expected, let actual):
            return "Invalid session phase: expected \(expected), currently \(actual)"
        case .unsafePath(let path):
            return "Unsafe output path: \(path)"
        case .base64DecodingFailed:
            return "Failed to decode base64 data"
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        case .archiveFailed(let reason):
            return "Archive failed: \(reason)"
        }
    }
}

// MARK: - TheBookKeeper

@ButtonHeistActor
public final class TheBookKeeper {

    public private(set) var phase: SessionPhase = .idle
    private let baseDirectory: URL

    public init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? Self.resolveBaseDirectory()
    }

    public var manifest: SessionManifest? {
        switch phase {
        case .idle:
            return nil
        case .active(let session):
            return session.manifest
        case .closing(let session):
            return session.manifest
        case .closed(let session):
            return session.manifest
        case .archived(let session):
            return session.manifest
        }
    }

    // MARK: - Lifecycle

    public func beginSession(identifier: String) throws {
        switch phase {
        case .idle, .closing, .closed, .archived:
            break
        case .active:
            throw BookKeeperError.invalidPhase(expected: "idle, closed, or archived", actual: "active")
        }

        guard !identifier.contains("/"), !identifier.contains("..") else {
            throw BookKeeperError.unsafePath(identifier)
        }

        let timestamp = Self.timestampString()
        let sessionId = "\(identifier)-\(timestamp)"
        let directory = baseDirectory.appendingPathComponent(sessionId)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let logPath = directory.appendingPathComponent("session.jsonl")
        FileManager.default.createFile(atPath: logPath.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logPath)

        let headerEntry: [String: Any] = [
            "type": "header",
            "formatVersion": SessionFormatVersion.current,
            "sessionId": sessionId,
        ]
        try appendLogLine(headerEntry, to: logHandle)

        let startTime = Date()
        let manifest = SessionManifest(sessionId: sessionId, startTime: startTime)
        phase = .active(ActiveSession(
            sessionId: sessionId,
            directory: directory,
            logHandle: logHandle,
            manifest: manifest,
            startTime: startTime,
            nextSequenceNumber: 1
        ))
    }

    public func closeSession() async throws {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        let endTime = Date()
        session.manifest.endTime = endTime
        try flushManifest(session: session)

        let closingSession = ClosingSession(
            sessionId: session.sessionId,
            directory: session.directory,
            manifest: session.manifest,
            startTime: session.startTime,
            endTime: endTime
        )
        phase = .closing(closingSession)
        session.logHandle.closeFile()

        // If compressLog throws, phase stays .closing — session data is
        // preserved and a fresh beginSession is still allowed.
        let compressedPath = try await compressLog(in: session.directory)

        phase = .closed(ClosedSession(
            sessionId: session.sessionId,
            directory: session.directory,
            compressedLogPath: compressedPath,
            manifest: session.manifest,
            startTime: session.startTime,
            endTime: endTime
        ))
    }

    public func archiveSession(deleteSource: Bool = false) async throws -> (URL, SessionManifest) {
        guard case .closed(let session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "closed", actual: phaseName)
        }

        let archivePath = try await createArchive(session: session)
        let manifest = session.manifest

        if deleteSource {
            try FileManager.default.removeItem(at: session.directory)
        }

        phase = .archived(ArchivedSession(
            archivePath: archivePath,
            manifest: manifest,
            startTime: session.startTime,
            endTime: session.endTime
        ))

        return (archivePath, manifest)
    }

    // MARK: - Logging

    public func logCommand(
        requestId: String,
        command: TheFence.Command,
        arguments: [String: Any]
    ) throws {
        guard case .active(var session) = phase else { return }
        let entry = buildCommandLogEntry(
            requestId: requestId,
            command: command,
            arguments: arguments
        )
        try appendLogLine(entry, to: session.logHandle)
        session.manifest.commandCount += 1
        phase = .active(session)
    }

    public func logResponse(
        requestId: String,
        status: ResponseStatus,
        durationMilliseconds: Int,
        artifact: String? = nil,
        error: String? = nil
    ) throws {
        guard case .active(var session) = phase else { return }
        let entry = buildResponseLogEntry(
            requestId: requestId,
            status: status,
            durationMilliseconds: durationMilliseconds,
            artifact: artifact,
            error: error
        )
        try appendLogLine(entry, to: session.logHandle)
        if status == .error {
            session.manifest.errorCount += 1
        }
        phase = .active(session)
    }

    // MARK: - Artifact Storage

    public func writeScreenshot(
        base64Data: String,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard let data = Data(base64Encoded: base64Data) else {
            throw BookKeeperError.base64DecodingFailed
        }

        let sequenceNumber = session.nextSequenceNumber
        session.nextSequenceNumber += 1
        let filename = String(format: "%03d-%@.png", sequenceNumber, command.rawValue)
        let subdirectory = session.directory.appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        let entry = ArtifactEntry(
            type: .screenshot,
            path: "screenshots/\(filename)",
            size: data.count,
            timestamp: Date(),
            requestId: requestId,
            command: command.rawValue,
            metadata: ["width": metadata.width, "height": metadata.height]
        )
        session.manifest.artifacts.append(entry)
        try flushManifest(session: session)
        phase = .active(session)

        return fileURL
    }

    public func writeRecording(
        base64Data: String,
        requestId: String,
        command: TheFence.Command,
        metadata: RecordingMetadata
    ) throws -> URL {
        guard case .active(var session) = phase else {
            throw BookKeeperError.invalidPhase(expected: "active", actual: phaseName)
        }
        guard let data = Data(base64Encoded: base64Data) else {
            throw BookKeeperError.base64DecodingFailed
        }

        let sequenceNumber = session.nextSequenceNumber
        session.nextSequenceNumber += 1
        let filename = String(format: "%03d-%@.mp4", sequenceNumber, command.rawValue)
        let subdirectory = session.directory.appendingPathComponent("recordings")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        let entry = ArtifactEntry(
            type: .recording,
            path: "recordings/\(filename)",
            size: data.count,
            timestamp: Date(),
            requestId: requestId,
            command: command.rawValue,
            metadata: [
                "width": Double(metadata.width),
                "height": Double(metadata.height),
                "duration": metadata.duration,
                "fps": Double(metadata.fps),
                "frameCount": Double(metadata.frameCount),
            ]
        )
        session.manifest.artifacts.append(entry)
        try flushManifest(session: session)
        phase = .active(session)

        return fileURL
    }

    public func writeToPath(_ data: Data, outputPath: String) throws -> URL {
        guard let resolvedURL = validateOutputPath(outputPath) else {
            throw BookKeeperError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
    }

    // MARK: - Path Safety

    public func validateOutputPath(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let components = path.split(separator: "/")
        guard !components.contains("..") else { return nil }
        return URL(fileURLWithPath: path).standardized
    }

    // MARK: - Private Helpers

    private var phaseName: String {
        switch phase {
        case .idle: return "idle"
        case .active: return "active"
        case .closing: return "closing"
        case .closed: return "closed"
        case .archived: return "archived"
        }
    }

    private static func resolveBaseDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["BUTTONHEIST_SESSIONS_DIR"] {
            return URL(fileURLWithPath: override)
        }
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: xdgDataHome)
                .appendingPathComponent("buttonheist")
                .appendingPathComponent("sessions")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/buttonheist/sessions")
    }

    private static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private func flushManifest(session: ActiveSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(session.manifest)
        let manifestPath = session.directory.appendingPathComponent("manifest.json")
        try data.write(to: manifestPath, options: .atomic)
    }
}

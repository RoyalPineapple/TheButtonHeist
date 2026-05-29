import Foundation

import TheScore

private enum BookKeeperArtifactKind {
    case screenshot(ScreenshotMetadata)
    case recording(RecordingMetadata)

    var type: ArtifactType {
        switch self {
        case .screenshot: return .screenshot
        case .recording: return .recording
        }
    }

    var subdirectoryName: String {
        switch self {
        case .screenshot: return "screenshots"
        case .recording: return "recordings"
        }
    }

    var fileExtension: String {
        switch self {
        case .screenshot: return "png"
        case .recording: return "mp4"
        }
    }

    var metadata: [String: Double] {
        switch self {
        case .screenshot(let metadata):
            return ["width": metadata.width, "height": metadata.height]
        case .recording(let metadata):
            return [
                "width": Double(metadata.width),
                "height": Double(metadata.height),
                "duration": metadata.duration,
                "fps": Double(metadata.fps),
                "frameCount": Double(metadata.frameCount),
            ]
        }
    }
}

extension TheBookKeeper {

    // MARK: - Artifact Storage

    func writeScreenshot(
        base64Data: String,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL {
        try writeSessionArtifact(
            kind: .screenshot(metadata),
            base64Data: base64Data,
            requestId: requestId,
            command: command
        )
    }

    func writeRecording(
        base64Data: String,
        requestId: String,
        command: TheFence.Command,
        metadata: RecordingMetadata
    ) throws -> URL {
        try writeSessionArtifact(
            kind: .recording(metadata),
            base64Data: base64Data,
            requestId: requestId,
            command: command
        )
    }

    func writeToPath(_ data: Data, outputPath: String) throws -> URL {
        guard let resolvedURL = outputPath.validatedOutputURL() else {
            throw BookKeeperError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
    }

    /// Write a screenshot to whichever sink is available, or return `nil` if
    /// neither a session is active nor an explicit outputPath was supplied.
    ///
    /// Resolution rules:
    /// - `outputPath` supplied: write raw bytes to that path via `writeToPath`
    ///   without appending a session log artifact event.
    /// - No `outputPath`, session active: write into the session artifact
    ///   directory and append an artifact event.
    /// - No `outputPath`, no session: return `nil`; caller returns the
    ///   in-memory payload.
    func writeScreenshotIfSinkAvailable(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL? {
        try writeArtifactIfSinkAvailable(
            kind: .screenshot(metadata),
            base64Data: base64Data,
            outputPath: outputPath,
            requestId: requestId,
            command: command
        )
    }

    /// Write a screenshot to an explicit path, active session artifact
    /// directory, or standalone artifact directory when no session exists.
    func writeScreenshotArtifact(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: ScreenshotMetadata
    ) throws -> URL {
        try writeArtifact(
            kind: .screenshot(metadata),
            base64Data: base64Data,
            outputPath: outputPath,
            requestId: requestId,
            command: command
        )
    }

    func writeRecordingIfSinkAvailable(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: RecordingMetadata
    ) throws -> URL? {
        try writeArtifactIfSinkAvailable(
            kind: .recording(metadata),
            base64Data: base64Data,
            outputPath: outputPath,
            requestId: requestId,
            command: command
        )
    }

    /// Write a recording to an explicit path, active session artifact
    /// directory, or standalone artifact directory when no session exists.
    func writeRecordingArtifact(
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command,
        metadata: RecordingMetadata
    ) throws -> URL {
        try writeArtifact(
            kind: .recording(metadata),
            base64Data: base64Data,
            outputPath: outputPath,
            requestId: requestId,
            command: command
        )
    }

    private func writeArtifactIfSinkAvailable(
        kind: BookKeeperArtifactKind,
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command
    ) throws -> URL? {
        if let outputPath {
            let data = try decodeArtifactData(base64Data)
            return try writeToPath(data, outputPath: outputPath)
        }
        guard hasActiveSession else { return nil }
        return try writeSessionArtifact(
            kind: kind,
            base64Data: base64Data,
            requestId: requestId,
            command: command
        )
    }

    private func writeArtifact(
        kind: BookKeeperArtifactKind,
        base64Data: String,
        outputPath: String?,
        requestId: String,
        command: TheFence.Command
    ) throws -> URL {
        if let url = try writeArtifactIfSinkAvailable(
            kind: kind,
            base64Data: base64Data,
            outputPath: outputPath,
            requestId: requestId,
            command: command
        ) {
            return url
        }
        let data = try decodeArtifactData(base64Data)
        return try writeStandaloneArtifact(kind: kind, data: data, command: command)
    }

    private func writeSessionArtifact(
        kind: BookKeeperArtifactKind,
        base64Data: String,
        requestId: String,
        command: TheFence.Command
    ) throws -> URL {
        let data = try decodeArtifactData(base64Data)
        return try mutateActiveSession { session in
            let sequenceNumber = session.nextSequenceNumber
            session.nextSequenceNumber += 1

            let filename = String(format: "%03d-%@.%@", sequenceNumber, command.rawValue, kind.fileExtension)
            let subdirectory = session.directory.appendingPathComponent(kind.subdirectoryName)
            try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
            let fileURL = subdirectory.appendingPathComponent(filename)
            try data.write(to: fileURL)

            try appendLogLine(ArtifactLogEntry(
                t: iso8601Now(),
                artifactType: kind.type,
                path: "\(kind.subdirectoryName)/\(filename)",
                size: data.count,
                requestId: requestId,
                command: command.rawValue,
                metadata: kind.metadata.isEmpty ? nil : kind.metadata
            ), to: session.logHandle)

            return fileURL
        }
    }

    private func writeStandaloneArtifact(
        kind: BookKeeperArtifactKind,
        data: Data,
        command: TheFence.Command
    ) throws -> URL {
        let subdirectory = artifactBaseDirectory.appendingPathComponent(kind.subdirectoryName)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let filename = "\(Self.timestampString())-\(UUID().uuidString)-\(command.rawValue).\(kind.fileExtension)"
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func decodeArtifactData(_ base64Data: String) throws -> Data {
        guard let data = Data(base64Encoded: base64Data) else {
            throw BookKeeperError.base64DecodingFailed
        }
        return data
    }
}

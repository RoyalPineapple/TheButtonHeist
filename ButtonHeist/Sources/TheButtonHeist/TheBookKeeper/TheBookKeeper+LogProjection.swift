import Foundation

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

    // MARK: - Session Log Projection

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
            failureContext: "gzip -dc"
        ) { failure in
            BookKeeperError.compressionFailed(.process(failure))
        }
    }

    private static func gunzippedData(_ data: Data) throws -> Data {
        let temporaryPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).session.jsonl.gz")
        try data.write(to: temporaryPath, options: .atomic)
        defer {
            BookKeeperCleanup.removeTemporaryItem(at: temporaryPath, operation: .removeTemporaryFile)
        }
        return try gunzippedData(at: temporaryPath)
    }

    private static func archivedSessionLogData(from archivePath: URL) throws -> Data {
        let listingData = try processOutput(
            executablePath: "/usr/bin/tar",
            arguments: ["-tzf", archivePath.path],
            failureContext: "tar -tzf"
        ) { failure in
            BookKeeperError.archiveFailed(.process(failure))
        }
        let listing = String(data: listingData, encoding: .utf8) ?? ""
        let entries = listing.split(separator: "\n").map(String.init)

        if let logEntry = entries.first(where: { $0.hasSuffix("/session.jsonl") || $0 == "session.jsonl" }) {
            return try archivedEntryData(logEntry, from: archivePath)
        }

        if let compressedEntry = entries.first(where: { $0.hasSuffix("/session.jsonl.gz") || $0 == "session.jsonl.gz" }) {
            let compressedData = try archivedEntryData(compressedEntry, from: archivePath)
            return try gunzippedData(compressedData)
        }

        throw BookKeeperError.archiveFailed(.sessionLogMissing(path: archivePath.path))
    }

    private static func archivedEntryData(_ entry: String, from archivePath: URL) throws -> Data {
        try processOutput(
            executablePath: "/usr/bin/tar",
            arguments: ["-xOzf", archivePath.path, entry],
            failureContext: "tar -xOzf"
        ) { failure in
            BookKeeperError.archiveFailed(.process(failure))
        }
    }

    private static func processOutput(
        executablePath: String,
        arguments: [String],
        failureContext: String,
        failure: (BookKeeperProcessFailure) -> BookKeeperError
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
            BookKeeperCleanup.close(errorHandle)
            BookKeeperCleanup.removeTemporaryItem(at: errorPath, operation: .removeTemporaryProcessStderr)
        }
        process.standardOutput = outputPipe
        process.standardError = errorHandle
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw failure(.launchFailed(context: failureContext, reason: String(describing: error)))
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            BookKeeperCleanup.close(errorHandle)
            let errorOutput = try Data(contentsOf: errorPath)
            let detail = String(data: errorOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw failure(.exited(context: failureContext, status: process.terminationStatus, detail: detail))
        }

        return output
    }
}

import Foundation

import TheScore

private enum BookKeeperArtifactKind {
    case screenshot

    var subdirectoryName: String {
        switch self {
        case .screenshot: return "screenshots"
        }
    }

    var fileExtension: String {
        switch self {
        case .screenshot: return "png"
        }
    }

}

extension TheBookKeeper {

    // MARK: - Artifact Storage

    func writeToPath(_ data: Data, outputPath: String) throws -> URL {
        guard let resolvedURL = outputPath.validatedOutputURL() else {
            throw BookKeeperError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
    }

    /// Write a screenshot to an explicit output path, or return `nil` when the
    /// caller requested inline data with no filesystem sink.
    ///
    /// Resolution rules:
    /// - `outputPath` supplied: write raw bytes to that path via `writeToPath`.
    /// - No `outputPath`: return `nil`; caller returns the in-memory payload.
    func writeScreenshotIfSinkAvailable(
        base64Data: String,
        outputPath: String?,
        command: TheFence.Command
    ) throws -> URL? {
        try writeArtifactIfSinkAvailable(
            kind: .screenshot,
            base64Data: base64Data,
            outputPath: outputPath,
            command: command
        )
    }

    /// Write a screenshot to an explicit path or standalone artifact directory.
    func writeScreenshotArtifact(
        base64Data: String,
        outputPath: String?,
        command: TheFence.Command
    ) throws -> URL {
        try writeArtifact(
            kind: .screenshot,
            base64Data: base64Data,
            outputPath: outputPath,
            command: command
        )
    }

    private func writeArtifactIfSinkAvailable(
        kind: BookKeeperArtifactKind,
        base64Data: String,
        outputPath: String?,
        command: TheFence.Command
    ) throws -> URL? {
        if let outputPath {
            let data = try decodeArtifactData(base64Data)
            return try writeToPath(data, outputPath: outputPath)
        }
        return nil
    }

    private func writeArtifact(
        kind: BookKeeperArtifactKind,
        base64Data: String,
        outputPath: String?,
        command: TheFence.Command
    ) throws -> URL {
        if let url = try writeArtifactIfSinkAvailable(
            kind: kind,
            base64Data: base64Data,
            outputPath: outputPath,
            command: command
        ) {
            return url
        }
        let data = try decodeArtifactData(base64Data)
        return try writeStandaloneArtifact(kind: kind, data: data, command: command)
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

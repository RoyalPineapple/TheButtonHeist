import Foundation

import TheScore

private enum ScreenshotArtifactKind {
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

@ButtonHeistActor
final class ScreenshotStore {

    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? PrivateStorage.resolveBaseDirectory()
    }

    // MARK: - Artifact Storage

    private func writeToPath(_ data: Data, outputPath: String) throws -> URL {
        guard let resolvedURL = outputPath.validatedOutputURL() else {
            throw StorageError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
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
        kind: ScreenshotArtifactKind,
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
        kind: ScreenshotArtifactKind,
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
        kind: ScreenshotArtifactKind,
        data: Data,
        command: TheFence.Command
    ) throws -> URL {
        let subdirectory = baseDirectory.appendingPathComponent(kind.subdirectoryName)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let filename = "\(PrivateStorage.timestampString())-\(UUID().uuidString)-\(command.rawValue).\(kind.fileExtension)"
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func decodeArtifactData(_ base64Data: String) throws -> Data {
        guard let data = Data(base64Encoded: base64Data) else {
            throw StorageError.base64DecodingFailed
        }
        return data
    }
}

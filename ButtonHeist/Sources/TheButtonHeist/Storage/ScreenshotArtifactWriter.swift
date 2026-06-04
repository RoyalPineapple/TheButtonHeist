import Foundation

import TheScore

@ButtonHeistActor
final class ScreenshotArtifactWriter {

    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? PrivateStorage.resolveBaseDirectory()
    }

    func writeScreenshot(
        base64Data: String,
        outputPath: String?,
        command: TheFence.Command
    ) throws -> URL {
        let data = try decodeScreenshotData(base64Data)
        if let outputPath {
            return try write(data, toOutputPath: outputPath)
        }
        return try writeStandaloneScreenshot(data, command: command)
    }

    private func write(_ data: Data, toOutputPath outputPath: String) throws -> URL {
        guard let resolvedURL = outputPath.validatedOutputURL() else {
            throw StorageError.unsafePath(outputPath)
        }
        try data.write(to: resolvedURL)
        return resolvedURL
    }

    private func writeStandaloneScreenshot(_ data: Data, command: TheFence.Command) throws -> URL {
        let subdirectory = baseDirectory.appendingPathComponent("screenshots")
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        let filename = "\(PrivateStorage.timestampString())-\(UUID().uuidString)-\(command.rawValue).png"
        let fileURL = subdirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)
        return fileURL
    }

    private func decodeScreenshotData(_ base64Data: String) throws -> Data {
        guard let data = Data(base64Encoded: base64Data) else {
            throw StorageError.base64DecodingFailed
        }
        return data
    }
}

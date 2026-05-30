import Foundation

import TheScore

enum HeistRecordingPhase: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    case idle
    case recording(HeistRecording)
}

/// Heist recording handle. Marked `@unchecked Sendable` because `fileHandle`
/// is confined to the `@ButtonHeistActor`-isolated `TheBookKeeper`.
struct HeistRecording: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    let app: String
    let fileHandle: FileHandle
    let filePath: URL
}

// MARK: - TheBookKeeper

/// Stores heist recordings and screenshot artifacts.
@ButtonHeistActor
final class TheBookKeeper {

    private var heistRecording: HeistRecordingPhase = .idle
    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? Self.resolveBaseDirectory()
    }

    var isRecordingHeist: Bool {
        guard case .recording = heistRecording else { return false }
        return true
    }

    var recordingFilePath: URL? {
        guard case .recording(let recording) = heistRecording else { return nil }
        return recording.filePath
    }

    func startRecording(identifier: String, app: String) throws {
        guard case .idle = heistRecording else {
            throw BookKeeperError.heistRecording(.alreadyRecording)
        }
        guard Self.isSafePathSegment(identifier) else {
            throw BookKeeperError.unsafePath(identifier)
        }

        let directory = baseDirectory
            .appendingPathComponent("heists")
            .appendingPathComponent("\(identifier)-\(Self.timestampString())")
        try Self.createPrivateDirectory(at: directory)

        let heistPath = directory.appendingPathComponent("heist.jsonl")
        do {
            try Self.createPrivateFile(at: heistPath)
        } catch {
            throw BookKeeperError.heistRecording(.fileCreationFailed(
                path: heistPath.path,
                reason: String(describing: error)
            ))
        }

        let heistHandle: FileHandle
        do {
            heistHandle = try FileHandle(forWritingTo: heistPath)
        } catch {
            throw BookKeeperError.heistRecording(.fileOpenFailed(
                path: heistPath.path,
                reason: String(describing: error)
            ))
        }

        heistRecording = .recording(HeistRecording(
            app: app,
            fileHandle: heistHandle,
            filePath: heistPath
        ))
    }

    func finishRecording() throws -> HeistPlayback {
        let recording = try currentRecording()
        heistRecording = .idle

        recording.fileHandle.closeFile()
        let steps = try readSteps(from: recording.filePath)
        guard !steps.isEmpty else {
            throw BookKeeperError.heistRecording(.noValidSteps(path: recording.filePath.path))
        }

        return HeistPlayback(app: recording.app, steps: steps)
    }

    func abandonRecording() {
        guard case .recording(let recording) = heistRecording else { return }
        recording.fileHandle.closeFile()
        heistRecording = .idle
    }

    func appendStep(_ step: HeistStep) throws {
        let recording = try currentRecording()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var lineData = try encoder.encode(step)
        lineData.append(contentsOf: [0x0A])
        recording.fileHandle.write(lineData)
    }

    private func currentRecording() throws -> HeistRecording {
        guard case .recording(let recording) = heistRecording else {
            throw BookKeeperError.heistRecording(.notRecording)
        }
        return recording
    }

    static func isSafePathSegment(_ identifier: String) -> Bool {
        guard !identifier.isEmpty,
              !identifier.hasPrefix("-"),
              !identifier.contains("/"),
              !identifier.contains("..") else { return false }

        return !identifier.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0)
        }
    }

    var artifactBaseDirectory: URL {
        baseDirectory
    }

    private static func resolveBaseDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["BUTTONHEIST_STORAGE_DIR"] {
            return URL(fileURLWithPath: override)
        }
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"] {
            return URL(fileURLWithPath: xdgDataHome)
                .appendingPathComponent("buttonheist")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/buttonheist")
    }

    static func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

}

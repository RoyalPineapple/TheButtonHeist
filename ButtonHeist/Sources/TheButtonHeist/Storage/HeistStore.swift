import Foundation

import TheScore

enum HeistRecordingPhase: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    case idle
    case recording(HeistRecording)
}

/// Heist recording handle. Marked `@unchecked Sendable` because `fileHandle`
/// is confined to the `@ButtonHeistActor`-isolated `HeistStore`.
struct HeistRecording: @unchecked Sendable { // swiftlint:disable:this agent_unchecked_sendable_no_comment
    let app: String
    let planName: String
    let fileHandle: FileHandle
    let filePath: URL
}

// MARK: - HeistStore

/// Stores deterministic heist recordings.
///
/// The store appends recording effects handed to it. It does not classify
/// commands, infer semantic intent, or resolve targets.
@ButtonHeistActor
final class HeistStore {

    private var heistRecording: HeistRecordingPhase = .idle
    private let baseDirectory: URL

    init(baseDirectory: URL? = nil) {
        self.baseDirectory = baseDirectory ?? PrivateStorage.resolveBaseDirectory()
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
            throw StorageError.heistRecording(.alreadyRecording)
        }
        guard PrivateStorage.isSafePathSegment(identifier) else {
            throw StorageError.unsafePath(identifier)
        }

        let directory = baseDirectory
            .appendingPathComponent("heists")
            .appendingPathComponent("\(identifier)-\(PrivateStorage.timestampString())")
        try PrivateStorage.createPrivateDirectory(at: directory)

        let heistPath = directory.appendingPathComponent("heist.jsonl")
        do {
            try PrivateStorage.createPrivateFile(at: heistPath)
        } catch {
            throw StorageError.heistRecording(.fileCreationFailed(
                path: heistPath.path,
                reason: String(describing: error)
            ))
        }

        let heistHandle: FileHandle
        do {
            heistHandle = try FileHandle(forWritingTo: heistPath)
        } catch {
            throw StorageError.heistRecording(.fileOpenFailed(
                path: heistPath.path,
                reason: String(describing: error)
            ))
        }

        heistRecording = .recording(HeistRecording(
            app: app,
            planName: Self.rootPlanName(from: identifier),
            fileHandle: heistHandle,
            filePath: heistPath
        ))
    }

    func finishRecording() throws -> HeistPlan {
        let recording = try currentRecording()
        heistRecording = .idle

        recording.fileHandle.closeFile()
        let steps = try readSteps(from: recording.filePath)
        guard !steps.isEmpty else {
            throw StorageError.heistRecording(.noValidSteps(path: recording.filePath.path))
        }

        return try HeistPlan(name: recording.planName, body: steps)
    }

    func abandonRecording() {
        guard case .recording(let recording) = heistRecording else { return }
        recording.fileHandle.closeFile()
        heistRecording = .idle
    }

    func appendStep(_ step: HeistStep) throws {
        let recording = try currentRecording()
        try appendStep(step, to: recording)
    }

    func appendSteps(_ steps: [HeistStep]) throws {
        for step in steps {
            try appendStep(step)
        }
    }

    private func appendStep(_ step: HeistStep, to recording: HeistRecording) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var lineData = try encoder.encode(step)
        lineData.append(contentsOf: [0x0A])
        recording.fileHandle.write(lineData)
    }

    private func currentRecording() throws -> HeistRecording {
        guard case .recording(let recording) = heistRecording else {
            throw StorageError.heistRecording(.notRecording)
        }
        return recording
    }

    private static func rootPlanName(from identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if HeistParameterName.isValid(trimmed) {
            return trimmed
        }
        return "recordedHeist"
    }

}

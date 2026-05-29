import Foundation
import os.log

import TheScore

private let heistRecordingLogger = Logger(subsystem: "com.buttonheist.bookkeeper", category: "heist")

extension TheBookKeeper {

    // MARK: - Heist Recording Lifecycle

    var isRecordingHeist: Bool {
        guard case .active(let session) = phase,
              case .recording = session.heistRecording else { return false }
        return true
    }

    func startHeistRecording(app: String) throws {
        try mutateActiveSession { session in
            guard case .idle = session.heistRecording else {
                throw BookKeeperError.heistRecording(.alreadyRecording)
            }

            let heistPath = session.directory.appendingPathComponent("heist.jsonl")
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

            session.heistRecording = .recording(HeistRecording(
                app: app,
                startTime: Date(),
                fileHandle: heistHandle,
                filePath: heistPath
            ))
        }
    }

    func stopHeistRecording() throws -> HeistPlayback {
        let recording = try mutateActiveSession { session in
            guard case .recording(let recording) = session.heistRecording else {
                throw BookKeeperError.heistRecording(.notRecording)
            }
            session.heistRecording = .idle
            return recording
        }

        recording.fileHandle.closeFile()
        let steps = try readEvidenceFromFile(recording.filePath)
        guard !steps.isEmpty else {
            throw BookKeeperError.heistRecording(.noValidSteps(path: recording.filePath.path))
        }

        return HeistPlayback(
            recorded: recording.startTime,
            app: recording.app,
            steps: steps
        )
    }

    /// Record a successfully executed command for heist playback.
    /// Only records commands that succeeded. Failed actions and unmet
    /// expectations are skipped.
    func recordHeistEvidence(
        _ request: TheFence.ParsedRequest,
        actionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        targetCapture: AccessibilityTrace.Capture?
    ) {
        guard case .active(let session) = phase,
              case .recording(let recording) = session.heistRecording else { return }
        guard request.command.isHeistRecordable else { return }
        guard actionResult?.success != false else { return }
        guard expectation?.met != false else { return }

        let step: HeistEvidence?
        do {
            step = try buildStep(
                request: request,
                targetCapture: targetCapture,
                actionResult: actionResult,
                expectation: expectation
            )
        } catch {
            heistRecordingLogger.error(
                "Skipped heist evidence for \(request.command.rawValue): projection failed: \(String(describing: error))"
            )
            return
        }

        guard let step else {
            heistRecordingLogger.error(
                "Skipped heist evidence for \(request.command.rawValue): target has no durable semantic replay identity"
            )
            return
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            var lineData = try encoder.encode(step)
            lineData.append(contentsOf: [0x0A])
            recording.fileHandle.write(lineData)
        } catch {
            heistRecordingLogger.error(
                "Failed to encode heist evidence for \(request.command.rawValue): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Heist File I/O

    static func writeHeist(_ script: HeistPlayback, to path: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(script)
            try writePrivateData(data, to: path)
        } catch {
            throw BookKeeperError.heistRecording(.scriptWriteFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }
    }

    static func readHeist(from path: URL) throws -> HeistPlayback {
        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HeistPlayback.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            throw BookKeeperError.heistRecording(.scriptReadFailed(
                path: path.path,
                reason: context.debugDescription
            ))
        } catch {
            throw BookKeeperError.heistRecording(.scriptReadFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }
    }

    // MARK: - Private Heist I/O

    private func readEvidenceFromFile(_ path: URL) throws -> [HeistEvidence] {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw BookKeeperError.heistRecording(.evidenceReadFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }

        let lines = data.split(separator: 0x0A)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try lines.enumerated().map { index, lineData in
            do {
                return try decoder.decode(HeistEvidence.self, from: Data(lineData))
            } catch {
                throw BookKeeperError.heistRecording(.evidenceReadFailed(
                    path: path.path,
                    reason: "line \(index + 1) is malformed: \(String(describing: error))"
                ))
            }
        }
    }

    private func buildStep(
        request: TheFence.ParsedRequest,
        targetCapture: AccessibilityTrace.Capture?,
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) throws -> HeistEvidence? {
        let projection = try request.heistRecordingProjection()
        let elementTarget = projection.elementTarget
        var target: SemanticActionTarget?
        var recordedHeistId: HeistId?
        var recordedFrame: RecordedFrame?
        var coordinateOnly: Bool?

        if case .heistId(let heistId)? = elementTarget {
            guard let targetCapture,
                  let element = targetCapture.interface.elements.last(where: { $0.heistId == heistId }),
                  let minimumMatcher = MinimumMatcher.build(element: element, in: targetCapture)
            else { return nil }
            target = SemanticActionTarget(minimumMatcher)
            recordedHeistId = heistId
            recordedFrame = RecordedFrame(
                x: element.frameX, y: element.frameY,
                width: element.frameWidth, height: element.frameHeight
            )
        } else if case .matcher(let matcher, let matchedOrdinal)? = elementTarget {
            guard matcher.hasPredicates else { return nil }
            target = SemanticActionTarget(matcher: matcher, ordinal: matchedOrdinal)
        } else if projection.coordinateOnly {
            coordinateOnly = true
        }

        let accessibilityTrace = actionResult?.accessibilityTrace
        let recorded = recordedHeistId != nil ||
            recordedFrame != nil ||
            coordinateOnly != nil ||
            accessibilityTrace != nil ||
            expectation != nil
            ? RecordedMetadata(
                heistId: recordedHeistId,
                frame: recordedFrame,
                coordinateOnly: coordinateOnly,
                accessibilityTrace: accessibilityTrace,
                expectation: expectation
            )
            : nil

        return HeistEvidence(
            command: request.command.rawValue,
            target: target,
            arguments: projection.arguments,
            recorded: recorded
        )
    }
}

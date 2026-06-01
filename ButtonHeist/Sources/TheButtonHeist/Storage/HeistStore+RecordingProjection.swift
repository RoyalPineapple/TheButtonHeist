import Foundation
import os.log

import TheScore

private let heistRecordingLogger = Logger(subsystem: "com.buttonheist.storage", category: "heist")

extension HeistStore {

    /// Record a successfully executed command for heist playback.
    /// Only records commands that succeeded. Failed actions and unmet
    /// expectations are skipped.
    func recordHeistStep(
        _ request: TheFence.ParsedRequest,
        actionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        targetCapture: AccessibilityTrace.Capture?
    ) {
        guard isRecordingHeist else { return }
        guard request.command.descriptor.isBatchExecutable else { return }
        guard actionResult?.success != false else { return }
        guard expectation?.met != false else { return }

        let step: HeistStep?
        do {
            step = try buildStep(
                request: request,
                targetCapture: targetCapture,
                actionResult: actionResult,
                expectation: expectation
            )
        } catch {
            heistRecordingLogger.error(
                "Skipped heist step for \(request.command.rawValue): projection failed: \(String(describing: error))"
            )
            return
        }

        guard let step else {
            heistRecordingLogger.error(
                "Skipped heist step for \(request.command.rawValue): target has no durable semantic replay identity"
            )
            return
        }

        do {
            try appendStep(step)
        } catch {
            heistRecordingLogger.error(
                "Failed to encode heist step for \(request.command.rawValue): \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Heist File I/O

    static func writeHeist(_ heist: HeistPlayback, to path: URL) throws {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(heist)
            try PrivateStorage.writePrivateData(data, to: path)
        } catch {
            throw StorageError.heistRecording(.heistWriteFailed(
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
            throw StorageError.heistRecording(.heistReadFailed(
                path: path.path,
                reason: context.debugDescription
            ))
        } catch {
            throw StorageError.heistRecording(.heistReadFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }
    }

    // MARK: - Private Heist I/O

    func readSteps(from path: URL) throws -> [HeistStep] {
        let data: Data
        do {
            data = try Data(contentsOf: path)
        } catch {
            throw StorageError.heistRecording(.stepReadFailed(
                path: path.path,
                reason: String(describing: error)
            ))
        }

        let lines = data.split(separator: 0x0A)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try lines.enumerated().map { index, lineData in
            do {
                return try decoder.decode(HeistStep.self, from: Data(lineData))
            } catch {
                throw StorageError.heistRecording(.stepReadFailed(
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
    ) throws -> HeistStep? {
        let projection = try request.heistStepProjection()
        let elementTarget = projection.elementTarget
        var target: ElementTarget?

        if case .heistId(let heistId)? = elementTarget {
            guard let targetCapture,
                  let element = targetCapture.interface.projectedElements.last(where: { $0.heistId == heistId }),
                  let minimumMatcher = MinimumMatcher.build(element: element, in: targetCapture)
            else { return nil }
            target = .predicate(minimumMatcher.predicate, ordinal: minimumMatcher.ordinal)
        } else if case .predicate(let predicate, let matchedOrdinal)? = elementTarget {
            guard predicate.hasPredicates else { return nil }
            target = .predicate(predicate, ordinal: matchedOrdinal)
        }

        return try HeistStepProjection(
            elementTarget: target,
            arguments: projection.arguments,
            expectation: projection.expectation
        ).heistStep(command: request.command)
    }
}

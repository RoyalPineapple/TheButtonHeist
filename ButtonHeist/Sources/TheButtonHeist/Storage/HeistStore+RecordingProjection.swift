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
        expectation: ExpectationResult? = nil
    ) {
        guard isRecordingHeist else { return }
        guard request.command.descriptor.isHeistExecutable else { return }
        guard actionResult?.success != false else { return }
        guard expectation?.met != false else { return }

        let step: HeistStep?
        do {
            step = try buildStep(
                request: request,
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

    static func writeHeist(_ heist: HeistPlan, to path: URL) throws {
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

    static func readHeist(from path: URL) throws -> HeistPlan {
        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(HeistPlan.self, from: data)
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
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) throws -> HeistStep? {
        guard let messages = request.executableMessages,
              let message = messages.first,
              messages.count == 1
        else {
            throw TheFence.HeistStepPlanBuildError(
                message: """
                heist action command "\(request.command.rawValue)" expands to \
                \(request.executableMessages?.count ?? 0) actions; express repeats as separate ordered steps
                """
            )
        }
        if case .wait(let target) = message {
            return .wait(WaitStep(predicate: target.predicate, timeout: target.resolvedTimeout))
        }
        return .action(try ActionStep(
            command: message,
            expectation: request.expectationPayload.expectation.map {
                WaitStep(
                    predicate: $0,
                    timeout: request.expectationPayload.postActionValidationTimeout ?? 10
                )
            }
        ))
    }
}

import Foundation

import TheScore

extension TheFence {
    struct HeistPlaybackContract {
        let app: String
        let steps: [HeistPlaybackStepContract]

        var batchRequest: RunBatchRequest {
            RunBatchRequest(
                steps: steps.map(\.preparedStep),
                policy: .stopOnError
            )
        }
    }

    struct HeistPlaybackStepContract {
        let index: Int
        let reportTarget: ElementTarget?
        let preparedStep: RunBatchPreparedStep

        var command: Command { preparedStep.command }
    }

    @ButtonHeistActor
    func readHeistPlayback(contentsOf url: URL) throws -> HeistPlaybackContract {
        do {
            let playback = try HeistStore.readHeist(from: url)
            return try validateHeistPlayback(playback)
        } catch StorageError.heistRecording(.heistReadFailed(_, let reason))
            where reason.contains("Unsupported heist file version") {
            throw FenceError.invalidRequest(reason)
        }
    }

    @ButtonHeistActor
    func validateHeistPlayback(_ playback: HeistPlayback) throws -> HeistPlaybackContract {
        guard playback.version == HeistPlayback.currentVersion else {
            throw FenceError.invalidRequest(
                "Unsupported heist file version \(playback.version). " +
                    "This Button Heist build supports version \(HeistPlayback.currentVersion). " +
                    "Re-record the heist with the current format."
            )
        }

        let steps = try playback.steps.enumerated().map { index, sourceStep in
            do {
                let parsedRequest = try playbackRequest(fromDiskStep: sourceStep, stepIndex: index)
                return HeistPlaybackStepContract(
                    index: index,
                    reportTarget: parsedRequest.arguments.elementTarget,
                    preparedStep: try batchPreparedStep(originalIndex: index, request: parsedRequest)
                )
            } catch let error as SchemaValidationError {
                throw FenceError.invalidRequest("Invalid heist step \(index): \(error.message)")
            } catch let error as MissingElementTarget {
                throw FenceError.invalidRequest(
                    "Invalid heist step \(index): command \"\(error.command)\" requires target object with heistId or matcher fields"
                )
            } catch let error as BatchStepPlanBuildError {
                throw FenceError.invalidRequest("Invalid heist step \(index): \(error.message)")
            }
        }
        return HeistPlaybackContract(
            app: playback.app,
            steps: steps
        )
    }

    @ButtonHeistActor
    private func playbackRequest(fromDiskStep sourceStep: HeistStep, stepIndex: Int) throws -> ParsedRequest {
        let prefix = "Invalid heist step \(stepIndex): "
        guard let command = Command(rawValue: sourceStep.command) else {
            throw FenceError.invalidRequest(
                prefix + "heist step command must be a canonical TheFence.Command; unknown command \"\(sourceStep.command)\""
            )
        }
        guard command.descriptor.isBatchExecutable else {
            throw FenceError.invalidRequest(prefix + "heist step command \"\(command.rawValue)\" is not supported")
        }
        var values = sourceStep.arguments
        if let expectation = sourceStep.expectation {
            values["expect"] = try heistValue(expectation)
        }
        let parsedRequest = try parseRequest(
            command: command,
            arguments: CommandArgumentEnvelope(values: values, elementTarget: sourceStep.target)
        )
        let canonicalStep: HeistStep
        do {
            canonicalStep = try parsedRequest.heistStepProjection().heistStep(command: command)
        } catch is HeistStepError {
            throw FenceError.invalidRequest(
                prefix + "heist step must match descriptor-owned recording projection"
            )
        }
        guard canonicalStep == sourceStep else {
            throw FenceError.invalidRequest(
                prefix + "heist step must match descriptor-owned recording projection"
            )
        }
        return parsedRequest
    }

    private func heistValue(_ expectation: AccessibilityPredicate) throws -> HeistValue {
        let data = try JSONEncoder().encode(expectation)
        return try JSONDecoder().decode(HeistValue.self, from: data)
    }
}

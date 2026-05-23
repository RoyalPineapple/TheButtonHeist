import Foundation

extension TheFence {

    @ButtonHeistActor
    struct BatchCommandParser {
        private let fence: TheFence

        init(fence: TheFence) {
            self.fence = fence
        }

        func decode(_ routedStep: FenceOperationCatalog.RoutedBatchStep, index: Int) -> RunBatchStep {
            switch routedStep.normalizedOperation {
            case .success(let operation):
                return decode(operation: operation, index: index)

            case .failure(let error):
                let fenceError = FenceError.invalidRequest("run_batch step \(index): \(error.message)")
                return .invalid(
                    commandName: routedStep.diagnosticCommandName,
                    failure: BatchStepFailure(
                        message: fenceError.coreMessage,
                        details: fenceError.failureDetails,
                        includeDetailsInResult: false
                    )
                )
            }
        }

        private func decode(operation: NormalizedOperation, index: Int) -> RunBatchStep {
            do {
                let request = try fence.parseRequest(operation: operation)
                return .planned(try BatchStepConstructor().plan(
                    index: index,
                    request: request
                ))
            } catch let error as SchemaValidationError {
                return invalid(operation, message: error.message, includeDetailsInResult: true)
            } catch let error as MissingElementTarget {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepFailureMapper.failure(
                        from: fence.missingElementTargetResponse(command: error.command)
                    )
                )
            } catch let error as FenceError {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepFailure(
                        message: error.coreMessage,
                        details: error.failureDetails,
                        includeDetailsInResult: true
                    )
                )
            } catch let error as BatchStepPlanBuildError {
                return invalid(operation, message: error.message)
            } catch {
                return invalid(operation, message: error.localizedDescription)
            }
        }

        private func invalid(
            _ operation: NormalizedOperation,
            message: String,
            includeDetailsInResult: Bool = false
        ) -> RunBatchStep {
            .invalid(
                commandName: operation.command.rawValue,
                failure: BatchStepFailure(
                    message: message,
                    details: nil,
                    includeDetailsInResult: includeDetailsInResult
                )
            )
        }
    }

    enum BatchStepFailureMapper {
        static func failure(from response: FenceResponse) -> BatchStepFailure {
            guard case .error(let message, let details) = response else {
                return BatchStepFailure(
                    message: response.humanFormatted(),
                    details: nil,
                    includeDetailsInResult: false
                )
            }
            return BatchStepFailure(
                message: message,
                details: details,
                includeDetailsInResult: true
            )
        }
    }
}

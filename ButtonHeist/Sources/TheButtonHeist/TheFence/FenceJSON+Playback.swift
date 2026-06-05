import Foundation

import TheScore

struct PublicPlaybackResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let completedSteps: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let failure: PublicPlaybackFailure?

    init(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure?) {
        self.status = PublicStatus(failedIndex == nil ? .ok : .error)
        self.completedSteps = completedSteps
        self.failedIndex = failedIndex
        self.totalTimingMs = totalTimingMs
        self.failure = failure.map(PublicPlaybackFailure.init(failure:))
    }
}

struct PublicPlaybackFailure: Encodable {
    let command: String
    let error: String
    let target: ElementTarget?
    let actionResult: PublicActionResponse?
    let expectation: PublicExpectationResult?
    let interface: PublicInterface?
    let diagnosticCaptureFailure: String?

    init(failure: PlaybackFailure) {
        self.command = failure.step.commandName
        self.error = failure.errorMessage
        self.target = failure.step.target
        self.diagnosticCaptureFailure = failure.diagnosticCaptureFailure

        switch failure {
        case .actionFailed(_, let result, let expectation, let interface, _):
            self.actionResult = PublicActionResponse(
                method: failure.step.commandName,
                result: result,
                expectation: expectation
            )
            let surfacedExpectation = result.success ? expectation : nil
            self.expectation = surfacedExpectation.flatMap { surfaced in
                surfaced.met ? nil : PublicExpectationResult(result: surfaced)
            }
            self.interface = interface.map { PublicInterface(interface: $0, detail: .summary) }
        case .fenceError(_, _, let interface, _), .thrown(_, _, let interface, _):
            self.actionResult = nil
            self.expectation = nil
            self.interface = interface.map { PublicInterface(interface: $0, detail: .summary) }
        }
    }
}

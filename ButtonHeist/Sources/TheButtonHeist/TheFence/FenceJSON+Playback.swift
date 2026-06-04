import Foundation

import TheScore

struct PublicPlaybackResponse: FencePublicJSONResponse {
    let status: PublicStatus
    let completedSteps: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let failure: PublicPlaybackFailure?

    init(projection: PublicPlaybackProjection) {
        self.status = PublicStatus(projection.status)
        self.completedSteps = projection.completedSteps
        self.failedIndex = projection.failedIndex
        self.totalTimingMs = projection.totalTimingMs
        self.failure = projection.failure.map(PublicPlaybackFailure.init(projection:))
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

    init(projection: PublicPlaybackFailureProjection) {
        self.command = projection.command
        self.error = projection.error
        self.target = projection.target
        self.actionResult = projection.action.map(PublicActionResponse.init(projection:))
        self.expectation = projection.expectation.map(PublicExpectationResult.init(projection:))
        self.interface = projection.interface.map { PublicInterface(interface: $0, detail: .summary) }
        self.diagnosticCaptureFailure = projection.diagnosticCaptureFailure
    }
}

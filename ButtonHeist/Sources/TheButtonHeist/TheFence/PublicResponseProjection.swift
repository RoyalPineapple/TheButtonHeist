import Foundation

import TheScore

enum PublicResponseStatus: String {
    case ok
    case error
    case expectationFailed = "expectation_failed"
    case partial
}

struct PublicResponseProjection {
    let status: PublicResponseStatus
    let action: PublicActionProjection?
    let heist: PublicHeistExecutionProjection?
    let playback: PublicPlaybackProjection?

    init(response: FenceResponse) {
        switch response {
        case .ok:
            self.init(status: .ok)
        case .error:
            self.init(status: .error)
        case .status:
            self.init(status: .ok)
        case .pong:
            self.init(status: .ok)
        case .devices:
            self.init(status: .ok)
        case .interface:
            self.init(status: .ok)
        case .action(let command, let result, let expectation):
            let action = PublicActionProjection(
                commandName: command.rawValue,
                result: result,
                expectation: expectation
            )
            self.init(status: action.status, action: action)
        case .screenshot, .screenshotData:
            self.init(status: .ok)
        case .heistExecution(let plan, let result, let accessibilityTrace):
            let heist = PublicHeistExecutionProjection(
                plan: plan,
                result: result,
                accessibilityTrace: accessibilityTrace
            )
            self.init(status: heist.status, heist: heist)
        case .sessionState:
            self.init(status: .ok)
        case .targets:
            self.init(status: .ok)
        case .heistStarted:
            self.init(status: .ok)
        case .heistStopped:
            self.init(status: .ok)
        case .heistPlayback(let completedSteps, let failedIndex, let totalTimingMs, let failure, _):
            let playback = PublicPlaybackProjection(
                completedSteps: completedSteps,
                failedIndex: failedIndex,
                totalTimingMs: totalTimingMs,
                failure: failure
            )
            self.init(status: playback.status, playback: playback)
        }
    }

    var isFailure: Bool {
        switch status {
        case .ok:
            return false
        case .error, .expectationFailed, .partial:
            return true
        }
    }

    private init(
        status: PublicResponseStatus,
        action: PublicActionProjection? = nil,
        heist: PublicHeistExecutionProjection? = nil,
        playback: PublicPlaybackProjection? = nil
    ) {
        self.status = status
        self.action = action
        self.heist = heist
        self.playback = playback
    }
}

struct PublicActionProjection {
    let status: PublicResponseStatus
    let commandName: String
    let message: String?
    let value: String?
    let rotor: RotorResult?
    let heistExecution: HeistExecutionResult?
    let delta: AccessibilityTrace.Delta?
    let screenName: String?
    let screenId: String?
    let failure: PublicActionFailureProjection?
    let expectation: PublicExpectationProjection?

    init(commandName: String, result: ActionResult, expectation: ExpectationResult?) {
        self.commandName = commandName
        self.message = result.message
        switch result.payload {
        case .value(let value):
            self.value = value
            self.rotor = nil
            self.heistExecution = nil
        case .rotor(let rotor):
            self.value = nil
            self.rotor = rotor
            self.heistExecution = nil
        case .heistExecution(let heistExecution):
            self.value = nil
            self.rotor = nil
            self.heistExecution = heistExecution
        case .none:
            self.value = nil
            self.rotor = nil
            self.heistExecution = nil
        }
        self.delta = result.accessibilityTrace?.endpointDeltaProjection
        self.screenName = result.accessibilityTrace?.endpointScreenNameProjection
        self.screenId = result.accessibilityTrace?.endpointScreenIdProjection
        self.failure = PublicActionFailureProjection(result: result)

        let projectedExpectation = result.success
            ? expectation.map(PublicExpectationProjection.init(result:))
            : nil
        self.expectation = projectedExpectation

        if !result.success {
            self.status = .error
        } else if projectedExpectation?.status == .failed {
            self.status = .expectationFailed
        } else {
            self.status = .ok
        }
    }

    var isFailure: Bool {
        status != .ok
    }
}

struct PublicActionFailureProjection {
    let errorKind: ErrorKind
    let details: FailureDetails?

    var errorClass: String {
        errorKind.rawValue
    }

    var errorCode: String? {
        details?.errorCode
    }

    var phase: FailurePhase? {
        details?.phase
    }

    var retryable: Bool? {
        details?.retryable
    }

    var hint: String? {
        details?.hint
    }

    var compactCode: String {
        errorCode ?? errorClass
    }

    init?(result: ActionResult) {
        guard !result.success else { return nil }
        self.errorKind = result.errorKind ?? .actionFailed
        self.details = Self.failureDetails(for: result)
    }

    private static func failureDetails(for result: ActionResult) -> FailureDetails? {
        guard result.errorKind == nil || result.errorKind == .actionFailed,
              result.message == accessibilityTreeUnavailableMessage
        else {
            return nil
        }

        return FailureDetails(
            errorCode: "request.accessibility_tree_unavailable",
            phase: .request,
            retryable: true,
            hint: "Wait for a traversable app window, then refresh the interface or retry the command."
        )
    }

    // Keep this literal in sync with `TheBrains.treeUnavailableMessage`; this
    // bridges tree-unavailable `actionFailed` wire results to local diagnostics.
    private static let accessibilityTreeUnavailableMessage =
        "Could not access accessibility tree: no traversable app windows"
}

struct PublicExpectationProjection {
    enum Status {
        case passed
        case failed
    }

    let status: Status
    let met: Bool
    let actual: String?
    let expected: AccessibilityPredicate?
    let failureHint: String?

    init(result: ExpectationResult) {
        self.met = result.met
        self.actual = result.actual
        self.expected = result.predicate
        self.status = result.met ? .passed : .failed
        self.failureHint = result.met ? nil : Self.failureHint(for: result)
    }

    private static func failureHint(for result: ExpectationResult) -> String? {
        guard result.predicate == .changed(.screen()), result.actual == "elementsChanged" else {
            return nil
        }
        return "screen_changed requires a screen-level transition; " +
            "use elements_changed for same-screen element updates " +
            "or wait when the UI may settle asynchronously"
    }
}

struct PublicHeistExecutionProjection {
    let status: PublicResponseStatus
    let report: HeistReportProjection
    let netDelta: AccessibilityTrace.Delta?

    var summary: HeistReportSummary {
        report.summary
    }

    var completedSteps: Int {
        summary.completedStepCount
    }

    var failedIndex: Int? {
        summary.failedIndex
    }

    var totalTimingMs: Int {
        summary.totalTimingMs
    }

    var expectations: PublicHeistExpectationsProjection? {
        guard summary.expectationsChecked > 0 else { return nil }
        return PublicHeistExpectationsProjection(
            checked: summary.expectationsChecked,
            met: summary.expectationsMet
        )
    }

    var finalScreenId: String? {
        report.finalActionProjectionsInExecutionOrder.compactMap(\.screenId).last
    }

    var compactLines: [PublicHeistReportLineProjection] {
        report.compactLines
    }

    init(plan: HeistPlan, result: HeistExecutionResult, accessibilityTrace: AccessibilityTrace?) {
        self.report = HeistReportProjection(plan: plan, result: result)
        self.netDelta = accessibilityTrace?.meaningfulEndpointDeltaProjection
        self.status = report.summary.failedIndex == nil ? .ok : .partial
    }
}

struct PublicHeistExpectationsProjection {
    let checked: Int
    let met: Int

    var allMet: Bool {
        checked == met
    }
}

struct PublicHeistReportLineProjection {
    let index: Int
    let depth: Int
    let commandName: String
    let status: HeistReportStepStatus
    let action: PublicActionProjection?
    let failureMessage: String?
    let delta: AccessibilityTrace.Delta?
    let expectation: PublicExpectationProjection?

    init(index: Int, depth: Int, node: HeistReportNode) {
        self.index = index
        self.depth = depth
        self.commandName = node.action?.commandName ?? node.kind.reportName
        self.status = node.status
        self.action = node.action?.finalActionProjection
        self.failureMessage = node.publicFailureMessage
        self.delta = action?.delta
        self.expectation = node.expectationProjection
    }
}

struct PublicPlaybackProjection {
    let status: PublicResponseStatus
    let completedSteps: Int
    let failedIndex: Int?
    let totalTimingMs: Int
    let failure: PublicPlaybackFailureProjection?

    init(completedSteps: Int, failedIndex: Int?, totalTimingMs: Int, failure: PlaybackFailure?) {
        self.status = failedIndex == nil ? .ok : .error
        self.completedSteps = completedSteps
        self.failedIndex = failedIndex
        self.totalTimingMs = totalTimingMs
        self.failure = failure.map(PublicPlaybackFailureProjection.init(failure:))
    }
}

struct PublicPlaybackFailureProjection {
    let command: String
    let error: String
    let target: ElementTarget?
    let action: PublicActionProjection?
    let expectation: PublicExpectationProjection?
    let interface: Interface?
    let diagnosticCaptureFailure: String?

    init(failure: PlaybackFailure) {
        self.command = failure.step.commandName
        self.error = failure.errorMessage
        self.target = failure.step.target
        self.diagnosticCaptureFailure = failure.diagnosticCaptureFailure

        switch failure {
        case .actionFailed(_, let result, let expectation, let interface, _):
            let action = PublicActionProjection(
                commandName: failure.step.commandName,
                result: result,
                expectation: expectation
            )
            self.action = action
            self.expectation = action.expectation?.status == .failed ? action.expectation : nil
            self.interface = interface
        case .fenceError(_, _, let interface, _), .thrown(_, _, let interface, _):
            self.action = nil
            self.expectation = nil
            self.interface = interface
        }
    }
}

import ThePlans
import Foundation

// MARK: - Heist Execution Results

/// Typed result for executing a `HeistPlan`.
public struct HeistExecutionResult: Codable, Sendable {
    public let steps: [HeistExecutionStepResult]
    public let totalTimingMs: Int
    public let failedIndex: Int?

    public init(
        steps: [HeistExecutionStepResult],
        totalTimingMs: Int,
        failedIndex: Int? = nil
    ) {
        self.steps = steps
        self.totalTimingMs = totalTimingMs
        self.failedIndex = failedIndex
    }
}

public enum HeistExecutionStepKind: String, Codable, Sendable {
    case action
    case wait
    case conditional
    case waitForCases
    case forEach = "for_each"
    case forEachElement = "for_each_element"
    case forEachString = "for_each_string"
    case forEachIteration = "for_each_iteration"
    case warn
    case fail
    case heist
    case invoke
    case skipped
}

/// One typed step result from a `HeistPlan`.
public struct HeistExecutionStepResult: Codable, Sendable {
    /// JSON-style path to this execution node in the heist program tree.
    public let path: String
    /// Sibling-local step index retained for compact summaries and older adapters.
    public let index: Int
    public let kind: HeistExecutionStepKind
    public let actionCommand: HeistActionCommand?
    /// The named-capability run for an `.invoke` step: which capability ran and
    /// with what argument. The frame is the product — reports surface this as
    /// `RunHeist("Name", argument)` rather than a bare `invoke`.
    public let invocation: HeistInvocationStep?
    public let actionResult: ActionResult?
    public let expectationActionResult: ActionResult?
    public let expectation: ExpectationResult?
    public let message: String?
    public let durationMs: Int
    public let stopsHeist: Bool
    public let skipped: HeistExecutionSkippedStepResult?
    public let caseSelection: HeistCaseSelectionResult?
    public let forEachResult: HeistForEachResult?
    public let children: [HeistExecutionStepResult]

    public init(
        index: Int,
        path: String? = nil,
        kind: HeistExecutionStepKind,
        actionCommand: HeistActionCommand? = nil,
        invocation: HeistInvocationStep? = nil,
        actionResult: ActionResult? = nil,
        expectationActionResult: ActionResult? = nil,
        expectation: ExpectationResult? = nil,
        message: String? = nil,
        durationMs: Int,
        stopsHeist: Bool = false,
        skipped: HeistExecutionSkippedStepResult? = nil,
        caseSelection: HeistCaseSelectionResult? = nil,
        forEachResult: HeistForEachResult? = nil,
        children: [HeistExecutionStepResult] = []
    ) {
        self.path = path ?? "$.body[\(index)]"
        self.index = index
        self.kind = kind
        self.actionCommand = actionCommand
        self.invocation = invocation
        self.actionResult = actionResult
        self.expectationActionResult = expectationActionResult
        self.expectation = expectation
        self.message = message
        self.durationMs = durationMs
        self.stopsHeist = stopsHeist
        self.skipped = skipped
        self.caseSelection = caseSelection
        self.forEachResult = forEachResult
        self.children = children
    }

    public var isSkipped: Bool {
        skipped != nil
    }

    public var isFailure: Bool {
        guard skipped == nil else { return false }
        if stopsHeist { return true }
        if kind == .fail { return true }
        if actionResult?.success == false { return true }
        if expectationActionResult?.success == false { return true }
        if expectation?.met == false { return true }
        if kind == .action, actionResult == nil { return true }
        if kind == .wait, actionResult?.success != true { return true }
        if kind == .waitForCases, caseSelection?.timedOut == true, caseSelection?.elseRan != true { return true }
        if [.forEach, .forEachElement, .forEachString].contains(kind), forEachResult?.failureReason != nil { return true }
        if children.contains(where: \.isFailure) { return true }
        return false
    }

    private enum CodingKeys: String, CodingKey {
        case path
        case index
        case kind
        case actionCommand
        case invocation
        case actionResult
        case expectationActionResult
        case expectation
        case message
        case durationMs
        case stopsHeist
        case skipped
        case caseSelection
        case forEachResult
        case children
        case decodedChildResults = "childResults"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? "$.body[\(index)]"
        kind = try container.decode(HeistExecutionStepKind.self, forKey: .kind)
        actionCommand = try container.decodeIfPresent(HeistActionCommand.self, forKey: .actionCommand)
        invocation = try container.decodeIfPresent(HeistInvocationStep.self, forKey: .invocation)
        actionResult = try container.decodeIfPresent(ActionResult.self, forKey: .actionResult)
        expectationActionResult = try container.decodeIfPresent(ActionResult.self, forKey: .expectationActionResult)
        expectation = try container.decodeIfPresent(ExpectationResult.self, forKey: .expectation)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        durationMs = try container.decode(Int.self, forKey: .durationMs)
        stopsHeist = try container.decodeIfPresent(Bool.self, forKey: .stopsHeist) ?? false
        skipped = try container.decodeIfPresent(HeistExecutionSkippedStepResult.self, forKey: .skipped)
        caseSelection = try container.decodeIfPresent(HeistCaseSelectionResult.self, forKey: .caseSelection)
        forEachResult = try container.decodeIfPresent(HeistForEachResult.self, forKey: .forEachResult)
        children = try container.decodeIfPresent([HeistExecutionStepResult].self, forKey: .children)
            ?? container.decodeIfPresent([HeistExecutionStepResult].self, forKey: .decodedChildResults)
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(index, forKey: .index)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(actionCommand, forKey: .actionCommand)
        try container.encodeIfPresent(invocation, forKey: .invocation)
        try container.encodeIfPresent(actionResult, forKey: .actionResult)
        try container.encodeIfPresent(expectationActionResult, forKey: .expectationActionResult)
        try container.encodeIfPresent(expectation, forKey: .expectation)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encode(durationMs, forKey: .durationMs)
        if stopsHeist { try container.encode(stopsHeist, forKey: .stopsHeist) }
        try container.encodeIfPresent(skipped, forKey: .skipped)
        try container.encodeIfPresent(caseSelection, forKey: .caseSelection)
        try container.encodeIfPresent(forEachResult, forKey: .forEachResult)
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }
}

public struct HeistCaseSelectionResult: Codable, Sendable {
    public let cases: [HeistCaseMatchResult]
    public let selectedCaseIndex: Int?
    public let elapsedMs: Int
    public let timeout: Double?
    public let timedOut: Bool
    public let elseRan: Bool
    public let lastObservedSummary: String?

    public init(
        cases: [HeistCaseMatchResult],
        selectedCaseIndex: Int?,
        elapsedMs: Int,
        timeout: Double? = nil,
        timedOut: Bool = false,
        elseRan: Bool = false,
        lastObservedSummary: String? = nil
    ) {
        self.cases = cases
        self.selectedCaseIndex = selectedCaseIndex
        self.elapsedMs = elapsedMs
        self.timeout = timeout
        self.timedOut = timedOut
        self.elseRan = elseRan
        self.lastObservedSummary = lastObservedSummary
    }
}

public struct HeistCaseMatchResult: Codable, Sendable {
    public let predicate: AccessibilityPredicate
    public let result: ExpectationResult

    public init(
        predicate: AccessibilityPredicate,
        result: ExpectationResult
    ) {
        self.predicate = predicate
        self.result = result
    }
}

public struct HeistForEachResult: Codable, Sendable {
    public let matchedCount: Int
    public let limit: Int
    public let iterationCount: Int
    public let failureReason: String?

    public init(
        matchedCount: Int,
        limit: Int,
        iterationCount: Int,
        failureReason: String? = nil
    ) {
        self.matchedCount = matchedCount
        self.limit = limit
        self.iterationCount = iterationCount
        self.failureReason = failureReason
    }
}

public struct HeistExecutionSkippedStepResult: Codable, Sendable {
    public let index: Int
    public let reason: String
    public let afterFailedIndex: Int

    public init(
        index: Int,
        reason: String,
        afterFailedIndex: Int
    ) {
        self.index = index
        self.reason = reason
        self.afterFailedIndex = afterFailedIndex
    }
}

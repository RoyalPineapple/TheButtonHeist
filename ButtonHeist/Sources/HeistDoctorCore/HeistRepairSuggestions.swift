import Foundation
import ThePlans
import TheScore

// MARK: - Heist Repair Evidence

public struct HeistStepRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let actionKind: String
    public let target: ElementTarget
    /// Parsed Interface hierarchy captured before the action. This is the
    /// durable world-model snapshot repair uses to rerun predicates and recover
    /// local semantic context around the original target; it is not raw AX data.
    public let beforeSnapshot: Interface
    /// Compact parsed-world-model transition evidence captured after the action.
    public let afterDelta: AccessibilityTrace.Delta?
    /// Parsed Interface fallback when a compact transition delta is unavailable.
    public let afterSnapshot: Interface?
    public let result: HeistStepRepairResult

    public init(
        heistFingerprint: String? = nil,
        stepPath: String,
        actionKind: String,
        target: ElementTarget,
        beforeSnapshot: Interface,
        afterDelta: AccessibilityTrace.Delta? = nil,
        afterSnapshot: Interface? = nil,
        result: HeistStepRepairResult
    ) {
        self.heistFingerprint = heistFingerprint
        self.stepPath = stepPath
        self.actionKind = actionKind
        self.target = target
        self.beforeSnapshot = beforeSnapshot
        self.afterDelta = afterDelta
        self.afterSnapshot = afterSnapshot
        self.result = result
    }
}

public struct HeistStepRepairResult: Codable, Sendable, Equatable {
    public let succeeded: Bool
    public let method: ActionMethod?
    public let errorKind: ErrorKind?
    public let message: String?
    public let expectation: ExpectationResult?

    public init(
        succeeded: Bool,
        method: ActionMethod? = nil,
        errorKind: ErrorKind? = nil,
        message: String? = nil,
        expectation: ExpectationResult? = nil
    ) {
        self.succeeded = succeeded
        self.method = method
        self.errorKind = errorKind
        self.message = message
        self.expectation = expectation
    }

    public init(actionResult: ActionResult, expectation: ExpectationResult? = nil) {
        self.init(
            succeeded: actionResult.success,
            method: actionResult.method,
            errorKind: actionResult.errorKind,
            message: actionResult.message,
            expectation: expectation
        )
    }
}

public struct HeistRepairRequest: Codable, Sendable, Equatable {
    public let lastSuccess: HeistStepRepairEvidence
    public let currentFailure: HeistStepRepairEvidence

    public init(
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) {
        self.lastSuccess = lastSuccess
        self.currentFailure = currentFailure
    }
}

// MARK: - Heist Repair Suggestion

public enum HeistRepairFailureKind: String, Codable, Sendable, Equatable {
    case missingTarget
    case ambiguousTarget
    case wrongCapability
}

public enum RepairConfidence: String, Codable, Sendable, Equatable {
    case high
    case medium
    case low
}

public struct ElementSummary: Codable, Sendable, Equatable {
    public let description: String
    public let label: String?
    public let value: String?
    public let identifier: String?
    public let hint: String?
    public let traits: [HeistTrait]
    public let actions: [ElementAction]
    public let rotors: [String]
    public let siblingText: [String]
    public let headerText: [String]

    public init(
        description: String,
        label: String?,
        value: String?,
        identifier: String?,
        hint: String?,
        traits: [HeistTrait],
        actions: [ElementAction],
        rotors: [String],
        siblingText: [String] = [],
        headerText: [String] = []
    ) {
        self.description = description
        self.label = label
        self.value = value
        self.identifier = identifier
        self.hint = hint
        self.traits = traits
        self.actions = actions
        self.rotors = rotors
        self.siblingText = siblingText
        self.headerText = headerText
    }
}

public struct HeistRepairSuggestion: Codable, Sendable, Equatable {
    public let stepPath: String
    public let failureKind: HeistRepairFailureKind
    public let oldTarget: ElementTarget
    public let oldResolvedElement: ElementSummary
    public let newTarget: ElementTarget
    public let newResolvedElement: ElementSummary
    public let confidence: RepairConfidence
    public let reasons: [String]
    public let caveats: [String]

    public init(
        stepPath: String,
        failureKind: HeistRepairFailureKind,
        oldTarget: ElementTarget,
        oldResolvedElement: ElementSummary,
        newTarget: ElementTarget,
        newResolvedElement: ElementSummary,
        confidence: RepairConfidence,
        reasons: [String],
        caveats: [String] = []
    ) {
        self.stepPath = stepPath
        self.failureKind = failureKind
        self.oldTarget = oldTarget
        self.oldResolvedElement = oldResolvedElement
        self.newTarget = newTarget
        self.newResolvedElement = newResolvedElement
        self.confidence = confidence
        self.reasons = reasons
        self.caveats = caveats
    }
}

// MARK: - Heist Repair Suggester

public enum HeistRepairSuggester {
    public static func suggestions(for request: HeistRepairRequest) -> [HeistRepairSuggestion] {
        guard request.lastSuccess.result.succeeded,
              !request.currentFailure.result.succeeded,
              request.lastSuccess.stepPath == request.currentFailure.stepPath,
              fingerprintsAreCompatible(request.lastSuccess.heistFingerprint, request.currentFailure.heistFingerprint)
        else {
            return []
        }

        let lastScreen = RepairScreen(interface: request.lastSuccess.beforeSnapshot)
        let currentScreen = RepairScreen(interface: request.currentFailure.beforeSnapshot)
        guard case .resolved(let oldResolved, _) = lastScreen.resolve(request.lastSuccess.target) else {
            return []
        }

        let actionFamily = RepairActionFamily(
            actionKind: request.currentFailure.actionKind,
            method: request.currentFailure.result.method ?? request.lastSuccess.result.method
        )
        let currentResolution = currentScreen.resolve(request.lastSuccess.target)
        let failureKind: HeistRepairFailureKind
        let preferredCandidates: Set<String>

        switch currentResolution {
        case .resolved(let element, _):
            guard !actionFamily.isKnown || actionFamily.isSupported(by: element.element) == false else {
                return []
            }
            failureKind = .wrongCapability
            preferredCandidates = []

        case .notFound:
            failureKind = .missingTarget
            preferredCandidates = []

        case .ambiguous(let matches, _):
            failureKind = .ambiguousTarget
            preferredCandidates = Set(matches.map(\.id))
        }

        let ranked = rankedSuccessorCandidates(
            oldResolved: oldResolved,
            currentScreen: currentScreen,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionFamily: actionFamily,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )
        guard let bestScore = ranked.first?.score, bestScore >= 55 else {
            return []
        }

        let tiedBest = ranked.prefix { $0.score == bestScore }
        return tiedBest.prefix(3).compactMap { candidate in
            suggestion(
                for: candidate,
                oldResolved: oldResolved,
                currentScreen: currentScreen,
                request: request,
                failureKind: failureKind,
                currentResolution: currentResolution,
                actionFamily: actionFamily,
                tiedBestCount: tiedBest.count
            )
        }
    }

    public static func noSuggestionReason(for request: HeistRepairRequest) -> String {
        if !request.lastSuccess.result.succeeded {
            return "last receipt step did not pass"
        }
        if request.currentFailure.result.succeeded {
            return "current receipt step did not fail"
        }
        if request.lastSuccess.stepPath != request.currentFailure.stepPath {
            return "receipts refer to different step paths"
        }
        if !fingerprintsAreCompatible(request.lastSuccess.heistFingerprint, request.currentFailure.heistFingerprint) {
            return "heist fingerprints are incompatible"
        }

        let lastScreen = RepairScreen(interface: request.lastSuccess.beforeSnapshot)
        let currentScreen = RepairScreen(interface: request.currentFailure.beforeSnapshot)
        guard case .resolved = lastScreen.resolve(request.lastSuccess.target) else {
            return "old target did not resolve exactly once in the last successful before snapshot"
        }

        let actionFamily = RepairActionFamily(
            actionKind: request.currentFailure.actionKind,
            method: request.currentFailure.result.method ?? request.lastSuccess.result.method
        )
        switch currentScreen.resolve(request.lastSuccess.target) {
        case .resolved(let element, _):
            if !actionFamily.isKnown || actionFamily.isSupported(by: element.element) {
                return "old target still resolves and supports the requested action; no target repair needed"
            }
            return """
                old target still resolves but does not support the requested action; \
                no safe compatible successor satisfied semantic continuity and unique-matcher requirements
                """

        case .notFound:
            return """
                old target is missing in the current before snapshot; \
                no safe successor satisfied semantic continuity and unique-matcher requirements
                """

        case .ambiguous:
            return """
                old target is ambiguous in the current before snapshot; \
                no candidate could be safely disambiguated
                """
        }
    }

    private static func fingerprintsAreCompatible(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }

    private static func rankedSuccessorCandidates(
        oldResolved: RepairScreen.Element,
        currentScreen: RepairScreen,
        preferredCandidates: Set<String>,
        failureKind: HeistRepairFailureKind,
        actionFamily: RepairActionFamily,
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) -> [ScoredCandidate] {
        let old = oldResolved.element
        let context = CandidateScoringContext(
            old: old,
            oldStableTraits: stableTraits(old),
            oldSiblingText: normalizedSet(oldResolved.siblingText),
            oldHeaderText: normalizedSet(oldResolved.headerText),
            afterEvidence: deltaEvidenceStrings(lastSuccess.afterDelta)
                .union(deltaEvidenceStrings(currentFailure.afterDelta)),
            expectationEvidence: expectationEvidenceStrings(lastSuccess.result.expectation)
                .union(expectationEvidenceStrings(currentFailure.result.expectation)),
            compatibleCandidateCount: currentScreen.elements
                .filter { !actionFamily.isKnown || actionFamily.isSupported(by: $0.element) }
                .count,
            currentElementCount: currentScreen.elements.count,
            preferredCandidates: preferredCandidates,
            failureKind: failureKind,
            actionFamily: actionFamily
        )

        return currentScreen.elements.compactMap { scoredCandidate($0, context: context) }
        .sorted(by: ScoredCandidate.precedes)
    }

    private static func scoredCandidate(
        _ candidate: RepairScreen.Element,
        context: CandidateScoringContext
    ) -> ScoredCandidate? {
        var score = CandidateScore()
        let element = candidate.element

        scorePreferredMatch(candidate, context: context, into: &score)
        scoreIdentifierContinuity(element, context: context, into: &score)
        scoreTextContinuity(element, context: context, into: &score)
        scoreCapabilityOverlap(element, context: context, into: &score)
        scoreNeighborContext(candidate, context: context, into: &score)
        scoreOutcomeEvidence(element, context: context, into: &score)
        scoreActionFamily(element, context: context, into: &score)

        if context.failureKind == .wrongCapability, element == context.old {
            score.add(-30)
        }
        guard score.value > 0 else { return nil }
        if context.failureKind == .missingTarget, !hasStrongContinuity(score.continuitySignals) {
            return nil
        }
        return ScoredCandidate(
            element: candidate,
            score: score.value,
            reasons: unique(score.reasons),
            caveats: unique(score.caveats),
            continuitySignals: score.continuitySignals
        )
    }

    private static func scorePreferredMatch(
        _ candidate: RepairScreen.Element,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        guard context.preferredCandidates.contains(candidate.id) else { return }
        score.add(25, reason: "Old target is one of the current matches.")
    }

    private static func scoreIdentifierContinuity(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        guard let identifier = stableIdentifier(element.identifier),
              let oldIdentifier = stableIdentifier(context.old.identifier),
              ElementPredicate.stringEquals(identifier, oldIdentifier)
        else { return }
        score.add(90, reason: "Accessibility identifier is unchanged.", signal: .identifier)
    }

    private static func scoreTextContinuity(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        scoreTextPair(
            value: element.label,
            oldValue: context.old.label,
            exactPoints: 50,
            renamePoints: 35,
            exactReason: "Label is unchanged.",
            renameReason: "Label is a close semantic rename.",
            into: &score
        )
        scoreTextPair(
            value: element.value,
            oldValue: context.old.value,
            exactPoints: 20,
            renamePoints: 20,
            exactReason: "Value is unchanged.",
            renameReason: "Value is a close semantic rename.",
            into: &score
        )
    }

    private static func scoreTextPair(
        value: String?,
        oldValue: String?,
        exactPoints: Int,
        renamePoints: Int,
        exactReason: String,
        renameReason: String,
        into score: inout CandidateScore
    ) {
        guard let value = nonEmpty(value), let oldValue = nonEmpty(oldValue) else { return }
        if ElementPredicate.stringEquals(value, oldValue) {
            score.add(exactPoints, reason: exactReason, signal: .text)
            return
        }
        let similarity = stringSimilarity(value, oldValue)
        guard similarity >= 0.62 else { return }
        score.add(Int((similarity * Double(renamePoints)).rounded()), reason: renameReason, signal: .text)
    }

    private static func scoreCapabilityOverlap(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        let traitOverlap = context.oldStableTraits.intersection(stableTraits(element))
        if !traitOverlap.isEmpty {
            score.add(min(30, traitOverlap.count * 15), reason: "Control role traits are compatible.")
        }

        let actionOverlap = Set(context.old.actions).intersection(element.actions)
        if !actionOverlap.isEmpty {
            score.add(10, reason: "Element actions are compatible.")
        }

        let rotorOverlap = Set((context.old.rotors ?? []).map(\.name)).intersection((element.rotors ?? []).map(\.name))
        if !rotorOverlap.isEmpty {
            score.add(5, reason: "Rotor capability is compatible.")
        }
    }

    private static func scoreNeighborContext(
        _ candidate: RepairScreen.Element,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        let siblingOverlap = context.oldSiblingText.intersection(normalizedSet(candidate.siblingText))
        if !siblingOverlap.isEmpty {
            score.add(
                min(45, siblingOverlap.count * 35),
                reason: "Sibling row context is preserved.",
                signal: .neighborContext
            )
        }

        let headerOverlap = context.oldHeaderText.intersection(normalizedSet(candidate.headerText))
        if !headerOverlap.isEmpty {
            score.add(
                min(20, headerOverlap.count * 10),
                reason: "Header context is preserved.",
                signal: .neighborContext
            )
        }
    }

    private static func scoreOutcomeEvidence(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        let identityText = normalizedIdentityText(element)
        if !context.afterEvidence.isDisjoint(with: identityText) {
            score.add(5, reason: "After-diff evidence mentions the same semantic element.", signal: .afterEvidence)
        }
        if !context.expectationEvidence.isDisjoint(with: identityText) {
            score.add(
                5,
                reason: "Expectation evidence mentions the same semantic element.",
                signal: .expectationEvidence
            )
        }
    }

    private static func scoreActionFamily(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        if context.actionFamily.isKnown {
            scoreKnownActionFamily(element, context: context, into: &score)
        } else if context.failureKind == .missingTarget, context.currentElementCount == 1 {
            score.add(25, reason: "It is the only current semantic candidate.")
        }
    }

    private static func scoreKnownActionFamily(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        guard context.actionFamily.isSupported(by: element) else {
            score.add(-40)
            score.caveats.append("Candidate does not expose the same action family.")
            return
        }
        score.add(15, reason: "Element supports the same action family.")
        if context.failureKind == .missingTarget, context.compatibleCandidateCount == 1 {
            score.add(25, reason: "It is the only current element with a compatible action family.")
        }
    }

    private static func suggestion(
        for candidate: ScoredCandidate,
        oldResolved: RepairScreen.Element,
        currentScreen: RepairScreen,
        request: HeistRepairRequest,
        failureKind: HeistRepairFailureKind,
        currentResolution: RepairTargetResolution,
        actionFamily: RepairActionFamily,
        tiedBestCount: Int
    ) -> HeistRepairSuggestion? {
        let selectionContext = currentScreen.selectionContext()
        guard let selection = minimumUniquePredicate(for: candidate.element.id, in: selectionContext),
              case .resolved(let validation, _) = currentScreen.resolve(selection.target),
              validation.id == candidate.element.id
        else {
            return nil
        }

        if actionFamily.isKnown, !actionFamily.isSupported(by: candidate.element.element) {
            return nil
        }

        var reasons = baseReasons(
            failureKind: failureKind,
            currentResolution: currentResolution,
            selection: selection,
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        )
        reasons.append(contentsOf: candidate.reasons)
        reasons.append(contentsOf: afterEvidenceReasons(
            lastSuccess: request.lastSuccess,
            currentFailure: request.currentFailure
        ))

        var caveats = candidate.caveats
        if selection.candidate.tier == .ordinalDisambiguation,
           !request.lastSuccess.target.hasOrdinal {
            caveats.append("Suggested matcher uses ordinal as last-resort disambiguation.")
        }
        if tiedBestCount > 1 {
            caveats.append("Multiple candidates have the same semantic score.")
        }
        if request.lastSuccess.afterDelta == nil, request.lastSuccess.afterSnapshot != nil {
            caveats.append("Last successful evidence used a full after snapshot because compact diff was unavailable.")
        }
        if request.currentFailure.afterDelta == nil, request.currentFailure.afterSnapshot != nil {
            caveats.append("Current failure evidence used a full after snapshot because compact diff was unavailable.")
        }

        return HeistRepairSuggestion(
            stepPath: request.currentFailure.stepPath,
            failureKind: failureKind,
            oldTarget: request.lastSuccess.target,
            oldResolvedElement: oldResolved.summary,
            newTarget: selection.target,
            newResolvedElement: candidate.element.summary,
            confidence: confidence(
                score: candidate.score,
                selection: selection,
                oldTargetHadOrdinal: request.lastSuccess.target.hasOrdinal,
                tiedBestCount: tiedBestCount,
                failureKind: failureKind
            ),
            reasons: unique(reasons),
            caveats: unique(caveats)
        )
    }

    private static func baseReasons(
        failureKind: HeistRepairFailureKind,
        currentResolution: RepairTargetResolution,
        selection: MinimumPredicateSelection,
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) -> [String] {
        var reasons = [
            "Old target resolved to one element in the last successful before snapshot.",
        ]
        switch currentResolution {
        case .resolved:
            reasons.append("Old target still resolves, but the resolved element does not support the requested action.")
        case .notFound(let matchCount):
            reasons.append("Old target resolves to \(matchCount) elements in the new before snapshot.")
        case .ambiguous(_, let matchCount):
            reasons.append("Old target resolves to \(matchCount) elements in the new before snapshot.")
        }
        reasons.append("Suggested matcher resolves exactly one element in the new before snapshot.")
        if selection.candidate.tier == .ordinalDisambiguation {
            reasons.append("No semantic-only matcher was unique for the successor element.")
        }
        if lastSuccess.target != currentFailure.target {
            reasons.append("Current failure evidence supplied a different target; repair compared against the last successful target.")
        }
        if failureKind == .missingTarget {
            reasons.append("Best successor was selected from semantic continuity after the old target went missing.")
        }
        if failureKind == .ambiguousTarget {
            reasons.append("Best successor was selected from the ambiguous current matches.")
        }
        return reasons
    }

    private static func afterEvidenceReasons(
        lastSuccess: HeistStepRepairEvidence,
        currentFailure: HeistStepRepairEvidence
    ) -> [String] {
        var reasons: [String] = []
        if let reason = deltaReason(prefix: "Last successful after diff", delta: lastSuccess.afterDelta) {
            reasons.append(reason)
        }
        if let reason = deltaReason(prefix: "Current failure after diff", delta: currentFailure.afterDelta) {
            reasons.append(reason)
        }
        if let expectation = lastSuccess.result.expectation, expectation.met {
            reasons.append("Last successful result met its expectation.")
        }
        if let expectation = currentFailure.result.expectation, !expectation.met {
            reasons.append("Current failure result did not meet its expectation.")
        }
        return reasons
    }

    private static func deltaReason(prefix: String, delta: AccessibilityTrace.Delta?) -> String? {
        guard let delta else { return nil }
        switch delta {
        case .noChange:
            return "\(prefix) observed no semantic change."
        case .screenChanged:
            return "\(prefix) observed a screen change."
        case .elementsChanged(let payload):
            if let valueChange = payload.edits.updated
                .flatMap(\.changes)
                .first(where: { $0.property == .value }) {
                let old = valueChange.old ?? "nil"
                let new = valueChange.new ?? "nil"
                return "\(prefix) observed value change from \(old) to \(new)."
            }
            if !payload.edits.added.isEmpty {
                return "\(prefix) observed semantic elements added."
            }
            if !payload.edits.removed.isEmpty {
                return "\(prefix) observed semantic elements removed."
            }
            return "\(prefix) observed element changes."
        }
    }

    private static func confidence(
        score: Int,
        selection: MinimumPredicateSelection,
        oldTargetHadOrdinal: Bool,
        tiedBestCount: Int,
        failureKind: HeistRepairFailureKind
    ) -> RepairConfidence {
        if selection.candidate.tier == .ordinalDisambiguation, !oldTargetHadOrdinal {
            return .low
        }
        if tiedBestCount > 1 {
            return .low
        }
        if failureKind == .wrongCapability {
            return score >= 75 ? .medium : .low
        }
        if score >= 120 {
            return .high
        }
        if score >= 75 {
            return .medium
        }
        return .low
    }
}

// MARK: - Repair Screen

private struct RepairScreen {
    struct Element: Sendable, Equatable {
        let id: String
        let element: HeistElement
        let path: TreePath
        let traversalIndex: Int
        let ordinal: Int
        let siblingText: [String]
        let headerText: [String]

        var summary: ElementSummary {
            ElementSummary(
                description: element.description,
                label: nonEmpty(element.label),
                value: nonEmpty(element.value),
                identifier: stableIdentifier(element.identifier),
                hint: nonEmpty(element.hint),
                traits: element.traits,
                actions: element.actions,
                rotors: element.rotors?.map(\.name) ?? [],
                siblingText: siblingText,
                headerText: headerText
            )
        }
    }

    let elements: [Element]

    init(interface: Interface) {
        let annotationsByPath = interface.annotations.elementByPath
        let indexed = interface.tree.pathIndexedElements.enumerated().map { ordinal, item in
            ElementCore(
                id: "element-\(ordinal)",
                element: HeistElement(
                    accessibilityElement: item.element,
                    annotation: annotationsByPath[item.path]
                ),
                path: item.path,
                traversalIndex: item.traversalIndex,
                ordinal: ordinal
            )
        }
        let siblingsByParent = Dictionary(grouping: indexed) { parentPath($0.path) }
        var headers: [String] = []
        var elements: [Element] = []
        elements.reserveCapacity(indexed.count)

        for core in indexed {
            let siblings = (siblingsByParent[parentPath(core.path)] ?? [])
                .filter { $0.id != core.id }
                .compactMap { primaryText($0.element) }
            let element = Element(
                id: core.id,
                element: core.element,
                path: core.path,
                traversalIndex: core.traversalIndex,
                ordinal: core.ordinal,
                siblingText: unique(siblings),
                headerText: Array(headers.suffix(3))
            )
            if core.element.traits.contains(.header), let header = primaryText(core.element) {
                headers.append(header)
            }
            elements.append(element)
        }
        self.elements = elements
    }

    func resolve(_ target: ElementTarget) -> RepairTargetResolution {
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = elements.filter { $0.element.matches(predicate) }
            if let ordinal {
                guard matches.indices.contains(ordinal) else {
                    return .notFound(matchCount: matches.count)
                }
                return .resolved(matches[ordinal], matchCount: matches.count)
            }
            switch matches.count {
            case 0:
                return .notFound(matchCount: 0)
            case 1:
                return .resolved(matches[0], matchCount: 1)
            default:
                return .ambiguous(matches, matchCount: matches.count)
            }
        }
    }

    func selectionContext() -> PredicateSelectionContext {
        PredicateSelectionContext(
            elements: elements.map {
                PredicateSelectionContext.Element(id: $0.id, element: $0.element)
            },
            scope: .discovery
        )
    }
}

private struct ElementCore {
    let id: String
    let element: HeistElement
    let path: TreePath
    let traversalIndex: Int
    let ordinal: Int
}

private enum RepairTargetResolution {
    case resolved(RepairScreen.Element, matchCount: Int)
    case notFound(matchCount: Int)
    case ambiguous([RepairScreen.Element], matchCount: Int)
}

// MARK: - Candidate Scoring

private struct CandidateScoringContext: Sendable, Equatable {
    let old: HeistElement
    let oldStableTraits: Set<HeistTrait>
    let oldSiblingText: Set<String>
    let oldHeaderText: Set<String>
    let afterEvidence: Set<String>
    let expectationEvidence: Set<String>
    let compatibleCandidateCount: Int
    let currentElementCount: Int
    let preferredCandidates: Set<String>
    let failureKind: HeistRepairFailureKind
    let actionFamily: RepairActionFamily
}

private struct CandidateScore: Sendable, Equatable {
    private(set) var value = 0
    var reasons: [String] = []
    var caveats: [String] = []
    private(set) var continuitySignals = Set<CandidateContinuitySignal>()

    mutating func add(
        _ points: Int,
        reason: String? = nil,
        signal: CandidateContinuitySignal? = nil
    ) {
        value += points
        if let reason {
            reasons.append(reason)
        }
        if let signal {
            continuitySignals.insert(signal)
        }
    }
}

private struct ScoredCandidate: Sendable, Equatable {
    let element: RepairScreen.Element
    let score: Int
    let reasons: [String]
    let caveats: [String]
    let continuitySignals: Set<CandidateContinuitySignal>

    static func precedes(_ lhs: ScoredCandidate, _ rhs: ScoredCandidate) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        if lhs.element.traversalIndex != rhs.element.traversalIndex {
            return lhs.element.traversalIndex < rhs.element.traversalIndex
        }
        return semanticSortKey(lhs.element.element) < semanticSortKey(rhs.element.element)
    }
}

private enum CandidateContinuitySignal: Sendable, Hashable {
    case identifier
    case text
    case neighborContext
    case afterEvidence
    case expectationEvidence
}

private enum RepairActionFamily: Sendable, Equatable {
    case activate
    case increment
    case decrement
    case customAction(String?)
    case rotor
    case textInput
    case unknown

    init(actionKind: String, method: ActionMethod?) {
        if let method {
            self = Self(method: method, actionKind: actionKind)
            return
        }
        self = Self(actionKind: actionKind)
    }

    private init(method: ActionMethod, actionKind: String) {
        switch method {
        case .activate, .syntheticTap, .syntheticLongPress:
            self = .activate
        case .increment:
            self = .increment
        case .decrement:
            self = .decrement
        case .customAction:
            self = .customAction(Self.customActionName(from: actionKind))
        case .rotor:
            self = .rotor
        case .typeText:
            self = .textInput
        default:
            self = Self(actionKind: actionKind)
        }
    }

    private init(actionKind: String) {
        let normalized = actionKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "activate"
            || normalized == "onefingertap"
            || normalized == "one_finger_tap"
            || normalized == "longpress"
            || normalized == "long_press" {
            self = .activate
        } else if normalized == "increment" {
            self = .increment
        } else if normalized == "decrement" {
            self = .decrement
        } else if normalized == "performcustomaction"
            || normalized == "perform_custom_action"
            || normalized == "customaction"
            || normalized == "custom_action" {
            self = .customAction(nil)
        } else if normalized.hasPrefix("custom:") {
            self = .customAction(String(actionKind.dropFirst("custom:".count)))
        } else if normalized == "rotor" {
            self = .rotor
        } else if normalized == "typetext" || normalized == "type_text" {
            self = .textInput
        } else {
            self = .unknown
        }
    }

    var isKnown: Bool {
        self != .unknown
    }

    func isSupported(by element: HeistElement) -> Bool {
        switch self {
        case .activate:
            return element.actions.contains(.activate)
                || element.respondsToUserInteraction
                || !Set(element.traits).isDisjoint(with: AccessibilityPolicy.interactiveTraits)
        case .increment:
            return element.actions.contains(.increment) || element.traits.contains(.adjustable)
        case .decrement:
            return element.actions.contains(.decrement) || element.traits.contains(.adjustable)
        case .customAction(let name):
            let customActions = element.actions.compactMap { action -> String? in
                if case .custom(let name) = action { return name }
                return nil
            }
            guard let name, !name.isEmpty else {
                return !customActions.isEmpty
            }
            return customActions.contains { ElementPredicate.stringEquals($0, name) }
        case .rotor:
            return element.rotors?.isEmpty == false
        case .textInput:
            return element.traits.contains(.textEntry)
                || element.traits.contains(.searchField)
                || element.traits.contains(.textArea)
                || element.traits.contains(.secureTextField)
        case .unknown:
            return true
        }
    }

    private static func customActionName(from actionKind: String) -> String? {
        let separators = [":", "#"]
        for separator in separators where actionKind.contains(separator) {
            let suffix = actionKind.split(separator: Character(separator), maxSplits: 1).dropFirst().first
            return suffix.map(String.init)
        }
        return nil
    }
}

// MARK: - Semantic Helpers

private extension ElementTarget {
    var hasOrdinal: Bool {
        if case .predicate(_, let ordinal) = self {
            return ordinal != nil
        }
        return false
    }
}

private func stableTraits(_ element: HeistElement) -> Set<HeistTrait> {
    Set(element.traits.filter { !AccessibilityPolicy.transientTraits.contains($0) })
}

private func hasStrongContinuity(_ signals: Set<CandidateContinuitySignal>) -> Bool {
    signals.contains(.identifier)
        || signals.contains(.text)
        || signals.contains(.neighborContext)
        || signals.contains(.afterEvidence)
        || signals.contains(.expectationEvidence)
}

private func normalizedIdentityText(_ element: HeistElement) -> Set<String> {
    normalizedSet([stableIdentifier(element.identifier), element.label, element.value, element.hint].compactMap { $0 })
}

private func normalizedSet(_ values: [String]) -> Set<String> {
    Set(values.compactMap(normalizedNonEmpty))
}

private func stableIdentifier(_ identifier: String?) -> String? {
    guard let identifier = nonEmpty(identifier), isStableIdentifier(identifier) else { return nil }
    return identifier
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    return value
}

private func normalizedNonEmpty(_ value: String?) -> String? {
    guard let value = nonEmpty(value) else { return nil }
    let normalized = ElementPredicate.normalizeTypography(value).lowercased()
    return normalized.isEmpty ? nil : normalized
}

private func primaryText(_ element: HeistElement) -> String? {
    nonEmpty(element.label) ?? nonEmpty(element.value) ?? stableIdentifier(element.identifier)
}

private func parentPath(_ path: TreePath) -> TreePath {
    guard !path.indices.isEmpty else { return TreePath.root }
    return TreePath(Array(path.indices.dropLast()))
}

private func unique<T: Hashable>(_ values: [T]) -> [T] {
    var seen = Set<T>()
    return values.filter { seen.insert($0).inserted }
}

private func semanticSortKey(_ element: HeistElement) -> String {
    [
        stableIdentifier(element.identifier),
        element.label,
        element.value,
        element.traits.map(\.rawValue).sorted().joined(separator: ","),
    ]
    .compactMap { $0 }
    .joined(separator: "\u{1F}")
}

private func stringSimilarity(_ lhs: String, _ rhs: String) -> Double {
    let left = Array(ElementPredicate.normalizeTypography(lhs).lowercased())
    let right = Array(ElementPredicate.normalizeTypography(rhs).lowercased())
    guard !left.isEmpty, !right.isEmpty else { return 0 }
    let distance = levenshtein(left, right)
    return 1 - (Double(distance) / Double(max(left.count, right.count)))
}

private func levenshtein(_ left: [Character], _ right: [Character]) -> Int {
    var previous = Array(0...right.count)
    var current = Array(repeating: 0, count: right.count + 1)
    for leftIndex in 1...left.count {
        current[0] = leftIndex
        for rightIndex in 1...right.count {
            let cost = left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1
            current[rightIndex] = min(
                previous[rightIndex] + 1,
                current[rightIndex - 1] + 1,
                previous[rightIndex - 1] + cost
            )
        }
        swap(&previous, &current)
    }
    return previous[right.count]
}

private func deltaEvidenceStrings(_ delta: AccessibilityTrace.Delta?) -> Set<String> {
    guard let delta else { return [] }
    switch delta {
    case .noChange(let payload):
        return normalizedSet(payload.transient.flatMap(identityStrings))
    case .screenChanged(let payload):
        return normalizedSet(payload.newInterface.projectedElements.flatMap(identityStrings))
            .union(normalizedSet(payload.transient.flatMap(identityStrings)))
    case .elementsChanged(let payload):
        var strings = payload.edits.added.flatMap(identityStrings)
        strings.append(contentsOf: payload.edits.removed.flatMap(identityStrings))
        strings.append(contentsOf: payload.edits.updated.flatMap { update in
            identityStrings(update.element) + update.changes.flatMap { [$0.old, $0.new].compactMap { $0 } }
        })
        strings.append(contentsOf: payload.transient.flatMap(identityStrings))
        return normalizedSet(strings)
    }
}

private func expectationEvidenceStrings(_ expectation: ExpectationResult?) -> Set<String> {
    normalizedSet([expectation?.actual].compactMap { $0 })
}

private func identityStrings(_ element: HeistElement) -> [String] {
    [stableIdentifier(element.identifier), element.label, element.value, element.hint, element.description]
        .compactMap { $0 }
}

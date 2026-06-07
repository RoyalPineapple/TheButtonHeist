import Foundation
import ThePlans
import TheScore

// MARK: - Heist Repair Evidence

public struct HeistStepRepairEvidence: Codable, Sendable, Equatable {
    public let heistFingerprint: String?
    public let stepPath: String
    public let actionKind: String
    public let target: ElementTarget
    public let beforeSnapshot: Interface
    public let afterDelta: AccessibilityTrace.Delta?
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
        let oldStableTraits = stableTraits(old)
        let oldSiblingText = normalizedSet(oldResolved.siblingText)
        let oldHeaderText = normalizedSet(oldResolved.headerText)
        let afterEvidence = deltaEvidenceStrings(lastSuccess.afterDelta)
            .union(deltaEvidenceStrings(currentFailure.afterDelta))
        let compatibleCandidateCount = currentScreen.elements
            .filter { !actionFamily.isKnown || actionFamily.isSupported(by: $0.element) }
            .count

        return currentScreen.elements.compactMap { candidate -> ScoredCandidate? in
            var score = 0
            var reasons: [String] = []
            var caveats: [String] = []
            let element = candidate.element

            if preferredCandidates.contains(candidate.id) {
                score += 25
                reasons.append("Old target is one of the current matches.")
            }

            if let identifier = stableIdentifier(element.identifier),
               let oldIdentifier = stableIdentifier(old.identifier),
               ElementPredicate.stringEquals(identifier, oldIdentifier) {
                score += 90
                reasons.append("Accessibility identifier is unchanged.")
            }

            if let label = nonEmpty(element.label), let oldLabel = nonEmpty(old.label) {
                if ElementPredicate.stringEquals(label, oldLabel) {
                    score += 50
                    reasons.append("Label is unchanged.")
                } else {
                    let similarity = stringSimilarity(label, oldLabel)
                    if similarity >= 0.62 {
                        score += Int((similarity * 35).rounded())
                        reasons.append("Label is a close semantic rename.")
                    }
                }
            }

            if let value = nonEmpty(element.value), let oldValue = nonEmpty(old.value),
               ElementPredicate.stringEquals(value, oldValue) {
                score += 20
                reasons.append("Value is unchanged.")
            }

            let traitOverlap = oldStableTraits.intersection(stableTraits(element))
            if !traitOverlap.isEmpty {
                score += min(30, traitOverlap.count * 15)
                reasons.append("Control role traits are compatible.")
            }

            let actionOverlap = Set(old.actions).intersection(element.actions)
            if !actionOverlap.isEmpty {
                score += 10
                reasons.append("Element actions are compatible.")
            }

            let rotorOverlap = Set((old.rotors ?? []).map(\.name)).intersection((element.rotors ?? []).map(\.name))
            if !rotorOverlap.isEmpty {
                score += 5
                reasons.append("Rotor capability is compatible.")
            }

            let siblingOverlap = oldSiblingText.intersection(normalizedSet(candidate.siblingText))
            if !siblingOverlap.isEmpty {
                score += min(45, siblingOverlap.count * 35)
                reasons.append("Sibling row context is preserved.")
            }

            let headerOverlap = oldHeaderText.intersection(normalizedSet(candidate.headerText))
            if !headerOverlap.isEmpty {
                score += min(20, headerOverlap.count * 10)
                reasons.append("Header context is preserved.")
            }

            if !afterEvidence.isDisjoint(with: normalizedIdentityText(element)) {
                score += 5
                reasons.append("After-diff evidence mentions the same semantic element.")
            }

            if actionFamily.isKnown {
                if actionFamily.isSupported(by: element) {
                    score += 15
                    reasons.append("Element supports the same action family.")
                    if failureKind == .missingTarget, compatibleCandidateCount == 1 {
                        score += 25
                        reasons.append("It is the only current element with a compatible action family.")
                    }
                } else {
                    score -= 40
                    caveats.append("Candidate does not expose the same action family.")
                }
            } else if failureKind == .missingTarget, currentScreen.elements.count == 1 {
                score += 25
                reasons.append("It is the only current semantic candidate.")
            }

            if failureKind == .wrongCapability, candidate.element == old {
                score -= 30
            }

            guard score > 0 else { return nil }
            return ScoredCandidate(
                element: candidate,
                score: score,
                reasons: unique(reasons),
                caveats: unique(caveats)
            )
        }
        .sorted(by: ScoredCandidate.precedes)
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

private struct ScoredCandidate: Sendable, Equatable {
    let element: RepairScreen.Element
    let score: Int
    let reasons: [String]
    let caveats: [String]

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

private func identityStrings(_ element: HeistElement) -> [String] {
    [stableIdentifier(element.identifier), element.label, element.value, element.hint, element.description]
        .compactMap { $0 }
}

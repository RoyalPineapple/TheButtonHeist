import ThePlans
import TheScore

// MARK: - Candidate Scoring

enum RepairCandidateScorer {
    static func scoredCandidate(
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
            reasons: score.reasons,
            caveats: score.caveats,
            continuitySignals: score.continuitySignals
        )
    }

    private static func scorePreferredMatch(
        _ candidate: RepairScreen.Element,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        guard context.preferredCandidates.contains(candidate.id) else { return }
        score.add(25, reason: .oldTargetIsCurrentMatch)
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
        score.add(90, reason: .identifierUnchanged, signal: .identifier)
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
            exactReason: .labelUnchanged,
            renameReason: .labelSemanticRename,
            into: &score
        )
        scoreTextPair(
            value: element.value,
            oldValue: context.old.value,
            exactPoints: 20,
            renamePoints: 20,
            exactReason: .valueUnchanged,
            renameReason: .valueSemanticRename,
            into: &score
        )
    }

    private static func scoreTextPair(
        value: String?,
        oldValue: String?,
        exactPoints: Int,
        renamePoints: Int,
        exactReason: RepairScoringReason,
        renameReason: RepairScoringReason,
        into score: inout CandidateScore
    ) {
        guard let value = nonEmpty(value), let oldValue = nonEmpty(oldValue) else { return }
        if ElementPredicate.stringEquals(value, oldValue) {
            score.add(exactPoints, reason: exactReason, signal: .text)
            return
        }
        if containsNormalizedTokenPhrase(value, oldValue) || containsNormalizedTokenPhrase(oldValue, value) {
            score.add(renamePoints, reason: renameReason, signal: .text)
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
            score.add(min(30, traitOverlap.count * 15), reason: .controlRoleTraitsCompatible)
        }

        let actionOverlap = Set(context.old.actions).intersection(element.actions)
        if !actionOverlap.isEmpty {
            score.add(10, reason: .elementActionsCompatible)
        }

        let oldRotors = Set((context.old.rotors ?? []).map { HeistRepairRotorIdentity(rawValue: $0.name) })
        let currentRotors = Set((element.rotors ?? []).map { HeistRepairRotorIdentity(rawValue: $0.name) })
        let rotorOverlap = oldRotors.intersection(currentRotors)
        if !rotorOverlap.isEmpty {
            score.add(5, reason: .rotorCapabilityCompatible)
        }
    }

    private static func scoreNeighborContext(
        _ candidate: RepairScreen.Element,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        let candidateSiblingText = normalizedSet(candidate.siblingText)
        let siblingOverlap = context.oldSiblingText.intersection(candidateSiblingText)
        if !siblingOverlap.isEmpty,
           siblingContextIsLocal(oldCount: context.oldSiblingText.count, candidateCount: candidateSiblingText.count) {
            score.add(
                min(45, siblingOverlap.count * 35),
                reason: .siblingRowContextPreserved,
                signal: .neighborContext
            )
        }

        let headerOverlap = context.oldHeaderText.intersection(normalizedSet(candidate.headerText))
        if !headerOverlap.isEmpty {
            let isDiscriminatingHeader = context.compatibleCandidateCount <= 3
            score.add(
                min(20, headerOverlap.count * 10),
                reason: .headerContextPreserved,
                signal: isDiscriminatingHeader ? .neighborContext : nil
            )
        }
    }

    private static func scoreOutcomeEvidence(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        if context.afterEvidence.matchesIdentityText(of: element) {
            score.add(5, reason: .changeFactEvidenceMatchesElement, signal: .afterEvidence)
        }
        if context.expectationEvidence.matchesIdentityText(of: element) {
            score.add(
                5,
                reason: .expectationEvidenceMatchesElement,
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
            score.add(25, reason: .onlyCurrentSemanticCandidate)
        }
    }

    private static func scoreKnownActionFamily(
        _ element: HeistElement,
        context: CandidateScoringContext,
        into score: inout CandidateScore
    ) {
        guard context.actionFamily.isSupported(by: element) else {
            score.add(-40)
            score.caveats.append(.candidateDoesNotExposeSameActionFamily)
            return
        }
        score.add(15, reason: .elementSupportsSameActionFamily)
        if context.failureKind == .missingTarget, context.compatibleCandidateCount == 1 {
            score.add(25, reason: .onlyCurrentElementWithCompatibleActionFamily)
        }
    }
}

struct CandidateScoringContext: Sendable, Equatable {
    let old: HeistElement
    let oldStableTraits: Set<HeistTrait>
    let oldSiblingText: Set<String>
    let oldHeaderText: Set<String>
    let afterEvidence: RepairSemanticEvidence
    let expectationEvidence: RepairSemanticEvidence
    let compatibleCandidateCount: Int
    let currentElementCount: Int
    let preferredCandidates: Set<PredicateSelectionElementId>
    let failureKind: HeistRepairFailureKind
    let actionFamily: RepairActionFamily
}

struct RepairSemanticEvidence: Sendable, Equatable {
    private let values: Set<String>

    init(_ values: [String]) {
        self.values = normalizedSet(values)
    }

    private init(normalized values: Set<String>) {
        self.values = values
    }

    func union(_ other: Self) -> Self {
        Self(normalized: values.union(other.values))
    }

    func matchesIdentityText(of element: HeistElement) -> Bool {
        let identityText = normalizedSet([
            stableIdentifier(element.identifier),
            element.label,
            element.value,
            element.hint,
        ].compactMap { $0 })
        return !values.isDisjoint(with: identityText)
    }
}

private struct CandidateScore: Sendable, Equatable {
    private(set) var value = 0
    var reasons: [RepairScoringReason] = []
    var caveats: [RepairCaveat] = []
    private(set) var continuitySignals = Set<CandidateContinuitySignal>()

    mutating func add(
        _ points: Int,
        reason: RepairScoringReason? = nil,
        signal: CandidateContinuitySignal? = nil
    ) {
        value += points
        if let reason, !reasons.contains(reason) {
            reasons.append(reason)
        }
        if let signal {
            continuitySignals.insert(signal)
        }
    }
}

struct ScoredCandidate: Sendable, Equatable {
    let element: RepairScreen.Element
    let score: Int
    let reasons: [RepairScoringReason]
    let caveats: [RepairCaveat]
    let continuitySignals: Set<CandidateContinuitySignal>

    struct Rank: Sendable, Equatable, Comparable {
        let score: Int
        let traversalIndex: Int
        let semanticKey: String

        static func < (lhs: Rank, rhs: Rank) -> Bool {
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.traversalIndex != rhs.traversalIndex {
                return lhs.traversalIndex < rhs.traversalIndex
            }
            return lhs.semanticKey < rhs.semanticKey
        }
    }

    var rank: Rank {
        Rank(
            score: score,
            traversalIndex: element.traversalIndex,
            semanticKey: semanticSortKey(element.element)
        )
    }
}

enum CandidateContinuitySignal: Sendable, Hashable {
    case identifier
    case text
    case neighborContext
    case afterEvidence
    case expectationEvidence
}

func stableTraits(_ element: HeistElement) -> Set<HeistTrait> {
    Set(element.traits.filter { !AccessibilityPolicy.transientTraits.contains($0) })
}

func normalizedSet(_ values: [String]) -> Set<String> {
    Set(values.compactMap(normalizedNonEmpty))
}

private func hasStrongContinuity(_ signals: Set<CandidateContinuitySignal>) -> Bool {
    signals.contains(.identifier)
        || signals.contains(.text)
        || signals.contains(.neighborContext)
        || signals.contains(.afterEvidence)
        || signals.contains(.expectationEvidence)
}

private func containsNormalizedTokenPhrase(_ value: String, _ possiblePhrase: String) -> Bool {
    guard let normalizedValue = normalizedNonEmpty(value),
          let normalizedPhrase = normalizedNonEmpty(possiblePhrase)
    else { return false }

    let valueTokens = semanticTokens(normalizedValue)
    let phraseTokens = semanticTokens(normalizedPhrase)
    guard !valueTokens.isEmpty, !phraseTokens.isEmpty, phraseTokens.count <= valueTokens.count else {
        return false
    }

    for start in 0...(valueTokens.count - phraseTokens.count) {
        let end = start + phraseTokens.count
        if Array(valueTokens[start..<end]) == phraseTokens {
            return true
        }
    }
    return false
}

private func semanticTokens(_ value: String) -> [String] {
    value
        .split { !$0.isLetter && !$0.isNumber }
        .map(String.init)
}

private func siblingContextIsLocal(oldCount: Int, candidateCount: Int) -> Bool {
    oldCount <= 8 && candidateCount <= 8
}

private func normalizedNonEmpty(_ value: String?) -> String? {
    guard let value = nonEmpty(value) else { return nil }
    let normalized = ElementPredicate.normalizeTypography(value).lowercased()
    return normalized.isEmpty ? nil : normalized
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

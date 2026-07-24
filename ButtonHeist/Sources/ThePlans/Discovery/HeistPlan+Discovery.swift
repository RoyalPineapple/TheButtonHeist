import Foundation

public enum HeistCatalogRole: String, Codable, Sendable, Equatable {
    case entry
    case capability
}

public enum HeistValidationStatus: String, Codable, Sendable, Equatable {
    case validated
}

public enum HeistCatalogDetail: String, Codable, CaseIterable, Sendable, Equatable {
    case summary
    case detailed
}

public enum HeistCatalogTag: String, Codable, Sendable, Equatable {
    case entry
    case capability
    case parameterized
    case composed
    case assertion
    case textInput = "text-input"
    case scroll
    case gesture
    case semanticAction = "semantic-action"
}

public enum HeistTargetPredicateFact: Sendable, Equatable, Hashable {
    case predicate(ElementPredicate)
    case container(ContainerPredicate)
    case targetReference(HeistReferenceName)
}

public enum HeistSemanticSurfaceFact: Sendable, Equatable, Hashable {
    case label(HeistSemanticStringMatch)
    case identifier(HeistSemanticStringMatch)
    case value(HeistSemanticStringMatch)
    case hint(HeistSemanticStringMatch)
    case traits([HeistTrait])
    case actions([ElementAction])
    case customContent(HeistSemanticCustomContentMatch)
    case rotors([HeistSemanticStringMatch])
    indirect case exclude(HeistSemanticSurfaceFact)
}

public struct HeistSemanticCustomContentMatch: Sendable, Equatable, Hashable {
    public let label: HeistSemanticStringMatch?
    public let value: HeistSemanticStringMatch?
    public let isImportant: Bool?

    public init(label: HeistSemanticStringMatch? = nil, value: HeistSemanticStringMatch? = nil, isImportant: Bool? = nil) {
        self.label = label
        self.value = value
        self.isImportant = isImportant
    }

    init(_ match: CustomContentMatch) {
        self.label = match.label.map(HeistSemanticStringMatch.init)
        self.value = match.value.map(HeistSemanticStringMatch.init)
        self.isImportant = match.isImportant
    }
}

public struct HeistSemanticStringMatch: Sendable, Equatable, Hashable {
    public let mode: StringMatch.Mode
    public let value: HeistSemanticStringValue?

    public init(mode: StringMatch.Mode, value: HeistSemanticStringValue?) {
        self.mode = mode
        self.value = value
    }

    init(_ match: StringMatch) {
        mode = match.mode
        value = match.value.map(HeistSemanticStringValue.init)
    }
}

public enum HeistSemanticStringValue: Sendable, Equatable, Hashable {
    case literal(String)
    case reference(HeistReferenceName)

    init(_ expression: AuthoredString) {
        switch expression {
        case .literal(let literal):
            self = .literal(literal)
        case .ref(let reference):
            self = .reference(reference)
        }
    }
}

public enum HeistCatalogIdentity: Sendable, Equatable, Hashable {
    case entry(HeistPlanName?)
    case capability(HeistDefinitionPath)

    public var role: HeistCatalogRole {
        switch self {
        case .entry: .entry
        case .capability: .capability
        }
    }

    public var displayName: String {
        switch self {
        case .entry(let name): name?.description ?? "entry"
        case .capability(let path): path.description
        }
    }

    package var lookupPath: HeistDefinitionPath? {
        switch self {
        case .entry(let name): name.map { HeistDefinitionPath(first: $0) }
        case .capability(let path): path
        }
    }
}

public struct HeistCatalogEntry: Sendable, Equatable {
    public let identity: HeistCatalogIdentity
    public var role: HeistCatalogRole { identity.role }
    public let parameterKind: HeistParameterKind
    public let requiresArgument: Bool
    public let summary: String?
    public let tags: [HeistCatalogTag]
    public let parameterName: HeistReferenceName?
    public let nestedRunHeists: [HeistInvocationPath]?
    public let actionCommands: [HeistActionCommandType]?
    public let waitCount: Int?
    public let expectationCount: Int?
    public let semanticSurfaces: [HeistSemanticSurfaceFact]?
    public let validationStatus: HeistValidationStatus?

    public init(
        identity: HeistCatalogIdentity,
        parameterKind: HeistParameterKind,
        requiresArgument: Bool,
        summary: String? = nil,
        tags: [HeistCatalogTag] = [],
        parameterName: HeistReferenceName? = nil,
        nestedRunHeists: [HeistInvocationPath]? = nil,
        actionCommands: [HeistActionCommandType]? = nil,
        waitCount: Int? = nil,
        expectationCount: Int? = nil,
        semanticSurfaces: [HeistSemanticSurfaceFact]? = nil,
        validationStatus: HeistValidationStatus? = nil
    ) {
        self.identity = identity
        self.parameterKind = parameterKind
        self.requiresArgument = requiresArgument
        self.summary = summary
        self.tags = tags
        self.parameterName = parameterName
        self.nestedRunHeists = nestedRunHeists
        self.actionCommands = actionCommands
        self.waitCount = waitCount
        self.expectationCount = expectationCount
        self.semanticSurfaces = semanticSurfaces
        self.validationStatus = validationStatus
    }
}

public struct HeistCatalogSource: Codable, Sendable, Equatable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}

public struct HeistCatalog: Codable, Sendable, Equatable {
    public let source: HeistCatalogSource?
    public let capabilities: [HeistPlan]

    public init(source: HeistCatalogSource? = nil, capabilities: [HeistPlan]) {
        self.source = source
        self.capabilities = capabilities
    }
}

public struct HeistSemanticSurface: Sendable, Equatable {
    public let actionCommands: [HeistActionCommandType]
    public let targetPredicates: [HeistTargetPredicateFact]
    package let waits: [AccessibilityPredicate]
    package let expectations: [AccessibilityPredicate]
    public let nestedRunHeists: [HeistInvocationPath]
    package let expectedEffects: [AccessibilityPredicate]
    public let semanticSurfaces: [HeistSemanticSurfaceFact]

    package init(
        actionCommands: [HeistActionCommandType] = [],
        targetPredicates: [HeistTargetPredicateFact] = [],
        waits: [AccessibilityPredicate] = [],
        expectations: [AccessibilityPredicate] = [],
        nestedRunHeists: [HeistInvocationPath] = [],
        expectedEffects: [AccessibilityPredicate] = [],
        semanticSurfaces: [HeistSemanticSurfaceFact] = []
    ) {
        self.actionCommands = actionCommands
        self.targetPredicates = targetPredicates
        self.waits = waits
        self.expectations = expectations
        self.nestedRunHeists = nestedRunHeists
        self.expectedEffects = expectedEffects
        self.semanticSurfaces = semanticSurfaces
    }
}

public struct HeistDescription: Sendable, Equatable {
    public let identity: HeistCatalogIdentity
    public var role: HeistCatalogRole { identity.role }
    public let parameterKind: HeistParameterKind
    public let parameterName: HeistReferenceName?
    public let requiresArgument: Bool
    public let summary: String?
    public let validationStatus: HeistValidationStatus
    public let semanticSurface: HeistSemanticSurface

    public init(
        identity: HeistCatalogIdentity,
        parameterKind: HeistParameterKind,
        parameterName: HeistReferenceName?,
        requiresArgument: Bool,
        summary: String?,
        validationStatus: HeistValidationStatus,
        semanticSurface: HeistSemanticSurface
    ) {
        self.identity = identity
        self.parameterKind = parameterKind
        self.parameterName = parameterName
        self.requiresArgument = requiresArgument
        self.summary = summary
        self.validationStatus = validationStatus
        self.semanticSurface = semanticSurface
    }
}

public struct HeistDescriptionLookupError: Error, Sendable, Equatable, CustomStringConvertible {
    public let requestedPath: HeistDefinitionPath
    public let availableIdentities: [HeistCatalogIdentity]

    public init(requestedPath: HeistDefinitionPath, availableIdentities: [HeistCatalogIdentity]) {
        self.requestedPath = requestedPath
        self.availableIdentities = availableIdentities
    }

    public var description: String {
        let available = availableIdentities.isEmpty
            ? "none"
            : availableIdentities.map(\.displayName).joined(separator: ", ")
        return "heist \"\(requestedPath)\" was not found. Available heists: \(available)"
    }
}

public struct HeistCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    public let duplicateIdentities: [HeistCatalogIdentity]

    public init(duplicateIdentities: [HeistCatalogIdentity]) {
        self.duplicateIdentities = duplicateIdentities
    }

    public var description: String {
        "heist catalog has duplicate names: \(duplicateIdentities.map(\.displayName).joined(separator: ", "))"
    }
}

public extension HeistPlan {
    func heistCatalog(detail: HeistCatalogDetail = .summary) throws -> [HeistCatalogEntry] {
        return try uncheckedHeistCatalog(detail: detail)
    }

    func describeHeist(at requestedPath: HeistDefinitionPath) throws -> HeistDescription {
        return try uncheckedDescribeHeist(at: requestedPath)
    }
}

private extension HeistPlan {
    func uncheckedHeistCatalog(detail: HeistCatalogDetail = .summary) throws -> [HeistCatalogEntry] {
        let resolved = try catalogResolvedHeists()
        return resolved.map { catalogEntry(for: $0, detail: detail) }
    }

    func uncheckedDescribeHeist(at requestedPath: HeistDefinitionPath) throws -> HeistDescription {
        let resolved = try catalogResolvedHeists()
        guard let heist = resolved.first(where: { $0.identity.lookupPath == requestedPath }) else {
            throw HeistDescriptionLookupError(
                requestedPath: requestedPath,
                availableIdentities: resolved.map(\.identity)
            )
        }
        return HeistDescription(
            identity: heist.identity,
            parameterKind: heist.plan.parameter.kind,
            parameterName: heist.plan.parameter.name,
            requiresArgument: heist.plan.parameter.kind != .none,
            summary: nil,
            validationStatus: .validated,
            semanticSurface: HeistSemanticSurfaceCollector.surface(for: heist)
        )
    }

    func catalogResolvedHeists() throws -> [ResolvedCatalogHeist] {
        var heists: [ResolvedCatalogHeist] = []
        HeistPlanTraversal().walkCatalogHeists(self) { projection in
            heists.append(ResolvedCatalogHeist(
                identity: catalogIdentity(for: projection),
                plan: projection.plan,
                context: projection.context
            ))
        }
        try validateUniqueCatalogPaths(heists.map(\.identity))
        return heists
    }

    func catalogIdentity(for projection: HeistPlanTraversal.CatalogHeistProjection) -> HeistCatalogIdentity {
        switch projection.kind {
        case .entry(let name):
            return .entry(name)
        case .capability(let nameComponents):
            guard let first = nameComponents.first else {
                preconditionFailure("definition catalog paths must not be empty")
            }
            return .capability(HeistDefinitionPath(first: first, remaining: Array(nameComponents.dropFirst())))
        }
    }

    func validateUniqueCatalogPaths(_ identities: [HeistCatalogIdentity]) throws {
        var seen = Set<HeistDefinitionPath>()
        var duplicates: [HeistCatalogIdentity] = []
        for identity in identities {
            guard let path = identity.lookupPath else { continue }
            if !seen.insert(path).inserted {
                duplicates.appendIfMissing(identity)
            }
        }
        guard duplicates.isEmpty else {
            throw HeistCatalogError(duplicateIdentities: duplicates)
        }
    }

    func catalogEntry(
        for resolved: ResolvedCatalogHeist,
        detail: HeistCatalogDetail
    ) -> HeistCatalogEntry {
        let parameterKind = resolved.plan.parameter.kind
        let requiresArgument = parameterKind != .none
        let surface = HeistSemanticSurfaceCollector.surface(for: resolved)
        let tags = catalogTags(for: resolved, surface: surface)
        guard detail == .detailed else {
            return HeistCatalogEntry(
                identity: resolved.identity,
                parameterKind: parameterKind,
                requiresArgument: requiresArgument,
                summary: catalogSummary(for: resolved),
                tags: tags
            )
        }
        return HeistCatalogEntry(
            identity: resolved.identity,
            parameterKind: parameterKind,
            requiresArgument: requiresArgument,
            summary: catalogSummary(for: resolved),
            tags: tags,
            parameterName: resolved.plan.parameter.name,
            nestedRunHeists: surface.nestedRunHeists.isEmpty ? nil : surface.nestedRunHeists,
            actionCommands: surface.actionCommands.isEmpty ? nil : surface.actionCommands,
            waitCount: surface.waits.count,
            expectationCount: surface.expectations.count,
            semanticSurfaces: surface.semanticSurfaces.isEmpty ? nil : surface.semanticSurfaces,
            validationStatus: .validated
        )
    }

    func catalogSummary(for resolved: ResolvedCatalogHeist) -> String {
        var summary = resolved.identity.role == .entry ? "Root entry heist" : "Reusable heist capability"
        if resolved.plan.parameter.kind != .none {
            summary += " requiring \(resolved.plan.parameter.kind.rawValue) argument"
        }
        return summary
    }

    func catalogTags(for resolved: ResolvedCatalogHeist, surface: HeistSemanticSurface) -> [HeistCatalogTag] {
        var tags: [HeistCatalogTag] = []
        tags.appendIfMissing(resolved.identity.role == .entry ? .entry : .capability)
        if resolved.plan.parameter.kind != .none {
            tags.appendIfMissing(.parameterized)
        }
        if !surface.nestedRunHeists.isEmpty {
            tags.appendIfMissing(.composed)
        }
        if !surface.waits.isEmpty || !surface.expectations.isEmpty {
            tags.appendIfMissing(.assertion)
        }
        for command in surface.actionCommands {
            switch command {
            case .typeText:
                tags.appendIfMissing(.textInput)
            case .scroll, .scrollToVisible, .scrollToEdge:
                tags.appendIfMissing(.scroll)
            case .oneFingerTap, .longPress, .swipe, .drag:
                tags.appendIfMissing(.gesture)
            case .activate, .increment, .decrement, .performCustomAction, .rotor, .dismiss, .magicTap,
                    .editAction, .setPasteboard, .dismissKeyboard:
                tags.appendIfMissing(.semanticAction)
            case .takeScreenshot:
                break
            }
        }
        return tags
    }
}

private struct ResolvedCatalogHeist {
    let identity: HeistCatalogIdentity
    let plan: HeistPlan
    let context: HeistTraversalContext
}

private struct HeistSemanticSurfaceCollector {
    private var actionCommands: [HeistActionCommandType] = []
    private var targetPredicates: [HeistTargetPredicateFact] = []
    private var waits: [AccessibilityPredicate] = []
    private var expectations: [AccessibilityPredicate] = []
    private var nestedRunHeists: [HeistInvocationPath] = []
    private var expectedEffects: [AccessibilityPredicate] = []
    private var semanticFacets: [ElementPredicateCheck] = []

    static func surface(for resolved: ResolvedCatalogHeist) -> HeistSemanticSurface {
        var collector = Self()
        let definitionComponents: [HeistPlanName]
        switch resolved.identity {
        case .entry:
            definitionComponents = []
        case .capability(let path):
            definitionComponents = path.components
        }
        HeistPlanTraversal().walkSemanticSurfaceObservations(
            steps: resolved.plan.body,
            path: .root.child(.body),
            depth: 1,
            referenceBindings: resolved.context.referenceBindings,
            definitionScope: HeistDefinitionScope(
                definitions: resolved.plan.definitions,
                pathPrefix: definitionComponents
            ),
            rootDefinitionScope: resolved.context.rootDefinitionScope,
            invocationStack: definitionComponents.isEmpty
                ? []
                : [HeistInvocationPath(namePath: definitionComponents)]
        ) { observation in
            collector.collect(observation)
        }
        return collector.surface
    }

    var surface: HeistSemanticSurface {
        HeistSemanticSurface(
            actionCommands: actionCommands,
            targetPredicates: targetPredicates,
            waits: waits,
            expectations: expectations,
            nestedRunHeists: nestedRunHeists,
            expectedEffects: expectedEffects,
            semanticSurfaces: semanticFacets.map(HeistSemanticSurfaceFact.init)
        )
    }

    mutating func collect(_ observation: HeistPlanTraversal.SemanticSurfaceObservation) {
        switch observation {
        case .action(let action):
            actionCommands.appendIfMissing(action.command.wireType)
            for occurrence in action.command.targetOccurrences {
                appendTargetPredicate(occurrence.target)
            }
            if let expectation = action.expectationPolicy.expectedStep {
                collectExpectation(expectation.predicate)
            }
        case .wait(let wait, let context):
            guard !context.path.ends(in: .expectation) else { return }
            collectWait(wait.predicate)
        case .forEachElement(let step):
            appendTargetPredicate(.predicate(step.matching))
        case .invoke(let invocation, let context):
            if let expectation = invocation.expectation {
                collectExpectation(expectation.predicate)
            }
            guard let resolved = context.resolveInvocation(path: invocation.path) else { return }
            nestedRunHeists.appendIfMissing(resolved.invocationPath)
        }
    }

    mutating func collectWait(_ predicate: AccessibilityPredicate) {
        waits.appendIfMissing(predicate)
        expectedEffects.appendIfMissing(predicate)
        appendPredicateTargets(predicate.core)
    }

    mutating func collectExpectation(_ predicate: AccessibilityPredicate) {
        expectations.appendIfMissing(predicate)
        expectedEffects.appendIfMissing(predicate)
        appendPredicateTargets(predicate.core)
    }

    mutating func appendTargetPredicate(_ target: AccessibilityTarget) {
        switch target {
        case .predicate(let predicate, _):
            targetPredicates.appendIfMissing(.predicate(predicate))
            appendSemanticSurfaces(predicate)
        case .container(let predicate, _):
            targetPredicates.appendIfMissing(.container(predicate))
        case .ref(let reference):
            targetPredicates.appendIfMissing(.targetReference(reference))
        case .within(_, let target):
            appendTargetPredicate(target)
        }
    }

    mutating func appendSemanticSurfaces(_ predicate: ElementPredicate) {
        for check in predicate.checks where check.hasPredicateLiteral {
            semanticFacets.appendIfMissing(check)
        }
    }

    mutating func appendPredicateTargets(
        _ value: AccessibilityPredicate.Value
    ) {
        switch value {
        case .presence(let presence):
            switch presence {
            case .exists(let target), .missing(let target):
                appendTargetPredicate(target)
            }
        case .announcement:
            break
        case .changed(let declaration):
            switch declaration {
            case .screen(let assertions):
                for assertion in assertions {
                    switch assertion {
                    case .exists(let target), .missing(let target):
                        appendTargetPredicate(target)
                    }
                }
            case .elements(let assertions):
                for assertion in assertions {
                    switch assertion {
                    case .exists(let target), .missing(let target),
                         .appeared(let target), .disappeared(let target), .updated(let target, _):
                        appendTargetPredicate(target)
                    }
                }
            }
        case .noChange:
            break
        }
    }

}

private extension HeistSemanticSurfaceFact {
    init(_ check: ElementPredicateCheck) {
        switch check {
        case .label(let match):
            self = .label(HeistSemanticStringMatch(match))
        case .identifier(let match):
            self = .identifier(HeistSemanticStringMatch(match))
        case .value(let match):
            self = .value(HeistSemanticStringMatch(match))
        case .hint(let match):
            self = .hint(HeistSemanticStringMatch(match))
        case .traits(let traits):
            self = .traits(traits.canonicalHeistTraitArray)
        case .actions(let actions):
            self = .actions(actions.canonicalElementActionArray)
        case .customContent(let match):
            self = .customContent(HeistSemanticCustomContentMatch(match))
        case .rotors(let matches):
            self = .rotors(matches.map(HeistSemanticStringMatch.init))
        case .exclude(let check):
            self = .exclude(HeistSemanticSurfaceFact(check))
        }
    }
}

private extension Array where Element: Equatable {
    mutating func appendIfMissing(_ value: Element) {
        guard !contains(value) else { return }
        append(value)
    }
}

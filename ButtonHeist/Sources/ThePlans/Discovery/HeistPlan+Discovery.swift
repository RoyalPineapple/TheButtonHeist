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
    case predicate(ElementPredicateTemplate)
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

    init(_ match: CustomContentMatchCore<Expr<String>>) {
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

    init(_ match: StringMatchCore<Expr<String>>) {
        switch match.mode {
        case .exact:
            self.mode = .exact
        case .contains:
            self.mode = .contains
        case .prefix:
            self.mode = .prefix
        case .suffix:
            self.mode = .suffix
        case .isEmpty:
            self.mode = .isEmpty
        }
        self.value = match.payload.map(HeistSemanticStringValue.init)
    }
}

public enum HeistSemanticStringValue: Sendable, Equatable, Hashable {
    case literal(String)
    case reference(HeistReferenceName)

    init(_ expression: Expr<String>) {
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

public struct HeistDiscoveryCatalog: Sendable, Equatable {
    public let heists: [HeistCatalogEntry]

    public init(heists: [HeistCatalogEntry]) {
        self.heists = heists
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
    func heistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistDiscoveryCatalog {
        return try uncheckedHeistCatalog(detail: detail)
    }

    func describeHeist(at requestedPath: HeistDefinitionPath) throws -> HeistDescription {
        return try uncheckedDescribeHeist(at: requestedPath)
    }
}

private extension HeistPlan {
    func uncheckedHeistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistDiscoveryCatalog {
        let resolved = try catalogResolvedHeists()
        return HeistDiscoveryCatalog(heists: resolved.map { catalogEntry(for: $0, detail: detail) })
    }

    func uncheckedDescribeHeist(at requestedPath: HeistDefinitionPath) throws -> HeistDescription {
        let resolved = try catalogResolvedHeists()
        guard let heist = resolved.first(where: { $0.entry.identity.lookupPath == requestedPath }) else {
            throw HeistDescriptionLookupError(
                requestedPath: requestedPath,
                availableIdentities: resolved.map(\.entry.identity)
            )
        }
        return HeistDescription(
            identity: heist.entry.identity,
            parameterKind: heist.entry.parameterKind,
            parameterName: heist.entry.parameterName,
            requiresArgument: heist.entry.requiresArgument,
            summary: nil,
            validationStatus: .validated,
            semanticSurface: HeistSemanticSurfaceBuilder.surface(for: heist)
        )
    }

    func catalogResolvedHeists() throws -> [ResolvedCatalogHeist] {
        var collector = HeistCatalogCollector()
        HeistPlanTraversal(expandsInvocations: false).walk(self, visitor: &collector)
        try validateUniqueCatalogPaths(collector.heists.map(\.entry.identity))
        return collector.heists
    }

    func validateUniqueCatalogPaths(_ identities: [HeistCatalogIdentity]) throws {
        var seen = Set<HeistDefinitionPath>()
        var duplicates: [HeistCatalogIdentity] = []
        for identity in identities {
            guard let path = identity.lookupPath else { continue }
            if !seen.insert(path).inserted {
                appendUnique(identity, to: &duplicates)
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
        let base = resolved.entry
        let surface = HeistSemanticSurfaceBuilder.surface(for: resolved)
        let tags = catalogTags(for: base, surface: surface)
        guard detail == .detailed else {
            return HeistCatalogEntry(
                identity: base.identity,
                parameterKind: base.parameterKind,
                requiresArgument: base.requiresArgument,
                summary: catalogSummary(for: base),
                tags: tags
            )
        }
        return HeistCatalogEntry(
            identity: base.identity,
            parameterKind: base.parameterKind,
            requiresArgument: base.requiresArgument,
            summary: catalogSummary(for: base),
            tags: tags,
            parameterName: base.parameterName,
            nestedRunHeists: surface.nestedRunHeists.isEmpty ? nil : surface.nestedRunHeists,
            actionCommands: surface.actionCommands.isEmpty ? nil : surface.actionCommands,
            waitCount: surface.waits.count,
            expectationCount: surface.expectations.count,
            semanticSurfaces: surface.semanticSurfaces.isEmpty ? nil : surface.semanticSurfaces,
            validationStatus: .validated
        )
    }

    func catalogSummary(for entry: HeistCatalogEntry) -> String {
        var summary = entry.role == .entry ? "Root entry heist" : "Reusable heist capability"
        if entry.requiresArgument {
            summary += " requiring \(entry.parameterKind.rawValue) argument"
        }
        return summary
    }

    func catalogTags(for entry: HeistCatalogEntry, surface: HeistSemanticSurface) -> [HeistCatalogTag] {
        var tags: [HeistCatalogTag] = []
        appendUnique(entry.role == .entry ? .entry : .capability, to: &tags)
        if entry.requiresArgument {
            appendUnique(.parameterized, to: &tags)
        }
        if !surface.nestedRunHeists.isEmpty {
            appendUnique(.composed, to: &tags)
        }
        if !surface.waits.isEmpty || !surface.expectations.isEmpty {
            appendUnique(.assertion, to: &tags)
        }
        for command in surface.actionCommands {
            switch command {
            case .typeText:
                appendUnique(.textInput, to: &tags)
            case .scroll, .scrollToVisible, .scrollToEdge:
                appendUnique(.scroll, to: &tags)
            case .oneFingerTap, .longPress, .swipe, .drag:
                appendUnique(.gesture, to: &tags)
            case .activate, .increment, .decrement, .performCustomAction, .rotor, .dismiss, .magicTap,
                    .editAction, .setPasteboard, .dismissKeyboard:
                appendUnique(.semanticAction, to: &tags)
            case .takeScreenshot:
                break
            }
        }
        return tags
    }
}

struct ResolvedCatalogHeist {
    let entry: HeistCatalogEntry
    let plan: HeistPlan
    let definitionScope: HeistDefinitionScope
    let rootDefinitionScope: HeistDefinitionScope
    let referenceBindings: HeistReferenceBindingContext
    let invocationStack: [HeistCallGraph.Node]
}

private struct HeistCatalogCollector: HeistPlanTraversalVisitor {
    var heists: [ResolvedCatalogHeist] = []

    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext) {
        append(
            plan,
            identity: .entry(plan.name),
            definitionComponents: [],
            context: context
        )
    }

    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        guard let localName = plan.name else {
            preconditionFailure("admitted heist definitions must have names")
        }
        let nameComponents = context.definitionScope.pathPrefix + [localName]
        guard let first = nameComponents.first else {
            preconditionFailure("definition catalog paths must not be empty")
        }
        let definitionPath = HeistDefinitionPath(first: first, remaining: Array(nameComponents.dropFirst()))
        append(
            plan,
            identity: .capability(definitionPath),
            definitionComponents: nameComponents,
            context: context
        )
    }

    private mutating func append(
        _ plan: HeistPlan,
        identity: HeistCatalogIdentity,
        definitionComponents: [HeistPlanName],
        context: HeistTraversalContext
    ) {
        let invocationStack = definitionComponents.isEmpty
            ? []
            : [HeistCallGraph.Node(namePath: definitionComponents)]
        heists.append(ResolvedCatalogHeist(
            entry: HeistCatalogEntry(
                identity: identity,
                parameterKind: plan.parameter.kind,
                requiresArgument: plan.parameter.kind != .none,
                parameterName: plan.parameter.name
            ),
            plan: plan,
            definitionScope: HeistDefinitionScope(
                definitions: plan.definitions,
                pathPrefix: definitionComponents
            ),
            rootDefinitionScope: context.rootDefinitionScope,
            referenceBindings: context.referenceBindings,
            invocationStack: invocationStack
        ))
    }
}

private struct HeistSemanticSurfaceBuilder: HeistPlanTraversalVisitor {
    var actionCommands: [HeistActionCommandType] = []
    var targetPredicateFacts: [HeistTargetPredicateFact] = []
    var waits: [AccessibilityPredicate] = []
    var expectations: [AccessibilityPredicate] = []
    var nestedRunHeists: [HeistInvocationPath] = []
    var expectedEffects: [AccessibilityPredicate] = []
    var semanticFacets: [ElementPredicateCheckCore<Expr<String>>] = []

    static func surface(for resolved: ResolvedCatalogHeist) -> HeistSemanticSurface {
        var builder = Self()
        HeistPlanTraversal().walk(
            steps: resolved.plan.body,
            path: .root.child(.body),
            depth: 1,
            referenceBindings: resolved.referenceBindings,
            definitionScope: resolved.definitionScope,
            rootDefinitionScope: resolved.rootDefinitionScope,
            invocationStack: resolved.invocationStack,
            visitor: &builder
        )
        return HeistSemanticSurface(
            actionCommands: builder.actionCommands,
            targetPredicates: builder.targetPredicateFacts,
            waits: builder.waits,
            expectations: builder.expectations,
            nestedRunHeists: builder.nestedRunHeists,
            expectedEffects: builder.expectedEffects,
            semanticSurfaces: builder.semanticFacets.map(HeistSemanticSurfaceFact.init)
        )
    }

    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {
        appendUnique(action.command.wireType, to: &actionCommands)
        collectTargets(from: action.command)
        if let expectation = action.expectationPolicy.expectedStep {
            collectExpectation(expectation.predicate)
        }
    }

    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {
        guard !context.path.ends(in: .expectation) else { return }
        collectWait(wait.predicate)
    }

    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {
        appendTargetPredicate(.predicate(step.matching))
    }

    mutating func visitInvoke(_ invocation: HeistInvocationStep, context: HeistTraversalContext) {
        if let expectation = invocation.expectation {
            collectExpectation(expectation.predicate)
        }
        guard let resolved = context.resolveInvocation(path: invocation.path) else { return }
        appendUnique(resolved.invocationPath, to: &nestedRunHeists)
    }

    mutating func collectTargets(from command: HeistActionCommand) {
        for occurrence in command.targetOccurrences {
            appendTargetPredicate(occurrence)
        }
    }

    mutating func collectWait(_ predicate: AccessibilityPredicate) {
        appendUnique(predicate, to: &waits)
        appendUnique(predicate, to: &expectedEffects)
        appendPredicateTargets(predicate)
    }

    mutating func collectExpectation(_ predicate: AccessibilityPredicate) {
        appendUnique(predicate, to: &expectations)
        appendUnique(predicate, to: &expectedEffects)
        appendPredicateTargets(predicate)
    }

    mutating func appendTargetPredicate(_ target: AccessibilityTarget) {
        switch target {
        case .predicate(let predicate, _):
            appendUnique(.predicate(predicate), to: &targetPredicateFacts)
            appendSemanticSurfaces(predicate)
        case .container(let predicate, _):
            appendUnique(.container(predicate), to: &targetPredicateFacts)
        case .ref(let reference):
            appendUnique(.targetReference(reference), to: &targetPredicateFacts)
        case .within(_, let target):
            appendTargetPredicate(target)
        }
    }

    mutating func appendTargetPredicate(_ occurrence: HeistActionCommandTargetOccurrence) {
        appendTargetPredicate(occurrence.target)
    }

    mutating func appendSemanticSurfaces(_ predicate: ElementPredicateTemplate) {
        for check in predicate.core.checks where check.hasPredicateLiteral {
            appendUnique(check, to: &semanticFacets)
        }
    }

    mutating func appendPredicateTargets(_ predicate: AccessibilityPredicate) {
        appendPredicateTargets(predicate.core)
    }

    mutating func appendPredicateTargets(
        _ core: AccessibilityPredicateCore<AuthoredAccessibilityPredicatePhase>
    ) {
        switch core {
        case .presence(let presence):
            appendPredicateTargets(presence)
        case .announcement:
            break
        case .changed(let declaration):
            appendPredicateTargets(declaration)
        case .noChange:
            break
        }
    }

    mutating func appendPredicateTargets(
        _ core: PresencePredicateCore<AuthoredAccessibilityPredicatePhase>
    ) {
        switch core {
        case .exists(let target), .missing(let target):
            appendTargetPredicate(target)
        }
    }

    mutating func appendPredicateTargets(
        _ core: ChangeDeclarationCore<AuthoredAccessibilityPredicatePhase>
    ) {
        switch core {
        case .screen(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        case .elements(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        }
    }

    mutating func appendPredicateTargets(
        _ core: ScreenAssertionCore<AuthoredAccessibilityPredicatePhase>
    ) {
        switch core {
        case .presence(let presence):
            appendPredicateTargets(presence)
        }
    }

    mutating func appendPredicateTargets(
        _ core: ElementAssertionCore<AuthoredAccessibilityPredicatePhase>
    ) {
        switch core {
        case .presence(let presence):
            appendPredicateTargets(presence)
        case .appeared(let target), .disappeared(let target):
            appendTargetPredicate(target)
        case .updated(let target, _):
            appendTargetPredicate(target)
        }
    }
}

private extension HeistSemanticSurfaceFact {
    init(_ check: ElementPredicateCheckCore<Expr<String>>) {
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

private func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
    guard !values.contains(value) else { return }
    values.append(value)
}

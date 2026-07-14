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
    case viewport
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

public struct HeistCatalogEntry: Sendable, Equatable {
    public let name: String
    public let role: HeistCatalogRole
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
        name: String,
        role: HeistCatalogRole,
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
        self.name = name
        self.role = role
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
    public let name: String
    public let role: HeistCatalogRole
    public let parameterKind: HeistParameterKind
    public let parameterName: HeistReferenceName?
    public let requiresArgument: Bool
    public let summary: String?
    public let validationStatus: HeistValidationStatus
    public let semanticSurface: HeistSemanticSurface

    public init(
        name: String,
        role: HeistCatalogRole,
        parameterKind: HeistParameterKind,
        parameterName: HeistReferenceName?,
        requiresArgument: Bool,
        summary: String?,
        validationStatus: HeistValidationStatus,
        semanticSurface: HeistSemanticSurface
    ) {
        self.name = name
        self.role = role
        self.parameterKind = parameterKind
        self.parameterName = parameterName
        self.requiresArgument = requiresArgument
        self.summary = summary
        self.validationStatus = validationStatus
        self.semanticSurface = semanticSurface
    }
}

public struct HeistDescriptionLookupError: Error, Sendable, Equatable, CustomStringConvertible {
    public let requestedName: String
    public let availableNames: [String]

    public init(requestedName: String, availableNames: [String]) {
        self.requestedName = requestedName
        self.availableNames = availableNames
    }

    public var description: String {
        let available = availableNames.isEmpty ? "none" : availableNames.joined(separator: ", ")
        return "heist \"\(requestedName)\" was not found. Available heists: \(available)"
    }
}

public struct HeistCatalogError: Error, Sendable, Equatable, CustomStringConvertible {
    public let duplicateNames: [String]

    public init(duplicateNames: [String]) {
        self.duplicateNames = duplicateNames
    }

    public var description: String {
        "heist catalog has duplicate names: \(duplicateNames.joined(separator: ", "))"
    }
}

public extension HeistPlan {
    func heistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistDiscoveryCatalog {
        return try uncheckedHeistCatalog(detail: detail)
    }

    func describeHeist(named requestedName: String) throws -> HeistDescription {
        return try uncheckedDescribeHeist(named: requestedName)
    }
}

private extension HeistPlan {
    func uncheckedHeistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistDiscoveryCatalog {
        let resolved = try catalogResolvedHeists()
        return HeistDiscoveryCatalog(heists: resolved.map { catalogEntry(for: $0, detail: detail) })
    }

    func uncheckedDescribeHeist(named requestedName: String) throws -> HeistDescription {
        let trimmedName = requestedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = try catalogResolvedHeists()
        guard let heist = resolved.first(where: { $0.entry.name == trimmedName }) else {
            throw HeistDescriptionLookupError(
                requestedName: requestedName,
                availableNames: resolved.map(\.entry.name)
            )
        }
        return HeistDescription(
            name: heist.entry.name,
            role: heist.entry.role,
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
        try validateUniqueCatalogNames(collector.heists.map(\.entry.name))
        return collector.heists
    }

    func validateUniqueCatalogNames(_ names: [String]) throws {
        var seen = Set<String>()
        var duplicates: [String] = []
        for name in names where !seen.insert(name).inserted {
            appendUnique(name, to: &duplicates)
        }
        guard duplicates.isEmpty else {
            throw HeistCatalogError(duplicateNames: duplicates)
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
                name: base.name,
                role: base.role,
                parameterKind: base.parameterKind,
                requiresArgument: base.requiresArgument,
                summary: catalogSummary(for: base),
                tags: tags
            )
        }
        return HeistCatalogEntry(
            name: base.name,
            role: base.role,
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
                appendUnique(.viewport, to: &tags)
            case .oneFingerTap, .longPress, .swipe, .drag:
                appendUnique(.gesture, to: &tags)
            case .activate, .increment, .decrement, .performCustomAction, .rotor, .dismiss, .magicTap,
                    .editAction, .setPasteboard, .resignFirstResponder:
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
            name: plan.name?.isEmpty == false ? plan.name ?? "entry" : "entry",
            role: .entry,
            definitionPath: [],
            context: context
        )
    }

    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        guard let localName = plan.name, !localName.isEmpty else { return }
        let namePath = context.definitionScope.pathPrefix + [localName]
        append(
            plan,
            name: namePath.joined(separator: "."),
            role: .capability,
            definitionPath: namePath,
            context: context
        )
    }

    private mutating func append(
        _ plan: HeistPlan,
        name: String,
        role: HeistCatalogRole,
        definitionPath: [String],
        context: HeistTraversalContext
    ) {
        let invocationStack = definitionPath.isEmpty
            ? []
            : [HeistCallGraph.Node(namePath: definitionPath)]
        heists.append(ResolvedCatalogHeist(
            entry: HeistCatalogEntry(
                name: name,
                role: role,
                parameterKind: plan.parameter.kind,
                requiresArgument: plan.parameter.kind != .none,
                parameterName: plan.parameter.name
            ),
            plan: plan,
            definitionScope: HeistDefinitionScope(
                definitions: plan.definitions,
                pathPrefix: definitionPath
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
        guard !context.path.description.hasSuffix(".expectation") else { return }
        collectWait(wait.predicate)
    }

    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {
        appendTargetPredicate(.predicate(step.matching))
    }

    mutating func visitInvoke(_ invocation: HeistInvocationStep, context: HeistTraversalContext) {
        if let expectation = invocation.expectation {
            collectExpectation(expectation.predicate)
        }
        guard let resolved = context.resolveInvocation(path: invocation.invocationPath) else { return }
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

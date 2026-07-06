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

public struct HeistCatalogEntry: Codable, Sendable, Equatable {
    public let name: String
    public let role: HeistCatalogRole
    public let parameterKind: HeistParameterKind
    public let requiresArgument: Bool
    public let summary: String?
    public let tags: [String]
    public let parameterName: HeistReferenceName?
    public let nestedRunHeists: [String]?
    public let actionCommands: [String]?
    public let waitCount: Int?
    public let expectationCount: Int?
    public let semanticSurfaces: [String]?
    public let validationStatus: HeistValidationStatus?

    public init(
        name: String,
        role: HeistCatalogRole,
        parameterKind: HeistParameterKind,
        requiresArgument: Bool,
        summary: String? = nil,
        tags: [String] = [],
        parameterName: HeistReferenceName? = nil,
        nestedRunHeists: [String]? = nil,
        actionCommands: [String]? = nil,
        waitCount: Int? = nil,
        expectationCount: Int? = nil,
        semanticSurfaces: [String]? = nil,
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

public struct HeistDiscoveryCatalog: Codable, Sendable, Equatable {
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

public struct HeistSemanticSurface: Codable, Sendable, Equatable {
    public let actionCommands: [String]
    public let targetPredicates: [String]
    public let waits: [String]
    public let expectations: [String]
    public let nestedRunHeists: [String]
    public let expectedEffects: [String]
    public let semanticSurfaces: [String]

    public init(
        actionCommands: [String] = [],
        targetPredicates: [String] = [],
        waits: [String] = [],
        expectations: [String] = [],
        nestedRunHeists: [String] = [],
        expectedEffects: [String] = [],
        semanticSurfaces: [String] = []
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

public struct HeistDescription: Codable, Sendable, Equatable {
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
            semanticSurface: HeistSemanticSurfaceBuilder.surface(for: heist).projectedSurface
        )
    }

    func catalogResolvedHeists() throws -> [ResolvedCatalogHeist] {
        let rootName: String
        if let name, !name.isEmpty {
            rootName = name
        } else {
            rootName = "entry"
        }
        let rootScope = HeistDefinitionScope(definitions: definitions)
        var heists: [ResolvedCatalogHeist] = [
            ResolvedCatalogHeist(
                entry: catalogEntry(name: rootName, role: .entry, parameter: parameter),
                plan: self,
                definitionScope: rootScope,
                rootDefinitionScope: rootScope,
                environment: Self.discoveryEnvironment(for: parameter),
                invocationStack: []
            ),
        ]

        collectCatalogDefinitions(
            definitions,
            pathPrefix: [],
            rootDefinitionScope: rootScope,
            into: &heists
        )
        try validateUniqueCatalogNames(heists.map(\.entry.name))
        return heists
    }

    func collectCatalogDefinitions(
        _ definitions: [HeistPlan],
        pathPrefix: [String],
        rootDefinitionScope: HeistDefinitionScope,
        into heists: inout [ResolvedCatalogHeist]
    ) {
        for definition in definitions {
            guard let localName = definition.name, !localName.isEmpty else { continue }
            let namePath = pathPrefix + [localName]
            let definitionNode = HeistCallGraph.Node(namePath: namePath)
            let environment = Self.discoveryEnvironment(for: definition.parameter)
            heists.append(ResolvedCatalogHeist(
                entry: catalogEntry(
                    name: definitionNode.name,
                    role: .capability,
                    parameter: definition.parameter
                ),
                plan: definition,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: namePath),
                rootDefinitionScope: rootDefinitionScope,
                environment: environment,
                invocationStack: [definitionNode]
            ))
            collectCatalogDefinitions(
                definition.definitions,
                pathPrefix: namePath,
                rootDefinitionScope: rootDefinitionScope,
                into: &heists
            )
        }
    }

    static func discoveryEnvironment(for parameter: HeistParameter) -> HeistExecutionEnvironment {
        HeistReferenceBindingContext.runtimeSafetyPlaceholder(for: parameter).environment
    }

    func catalogEntry(
        name: String,
        role: HeistCatalogRole,
        parameter: HeistParameter
    ) -> HeistCatalogEntry {
        HeistCatalogEntry(
            name: name,
            role: role,
            parameterKind: parameter.kind,
            requiresArgument: parameter.kind != .none,
            parameterName: parameter.name
        )
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
            actionCommands: surface.actionCommands.isEmpty ? nil : surface.catalogActionCommands,
            waitCount: surface.waits.count,
            expectationCount: surface.expectations.count,
            semanticSurfaces: surface.semanticFacets.isEmpty ? nil : surface.catalogSemanticSurfaces,
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

    func catalogTags(for entry: HeistCatalogEntry, surface: HeistCollectedSemanticSurface) -> [String] {
        var tags: [String] = []
        appendUnique(entry.role.rawValue, to: &tags)
        if entry.requiresArgument {
            appendUnique("parameterized", to: &tags)
        }
        if !surface.nestedRunHeists.isEmpty {
            appendUnique("composed", to: &tags)
        }
        if !surface.waits.isEmpty || !surface.expectations.isEmpty {
            appendUnique("assertion", to: &tags)
        }
        for command in surface.actionCommands {
            switch command {
            case .typeText:
                appendUnique("text-input", to: &tags)
            case .scroll, .scrollToVisible, .scrollToEdge:
                appendUnique("viewport", to: &tags)
            case .oneFingerTap, .longPress, .swipe, .drag:
                appendUnique("gesture", to: &tags)
            case .activate, .increment, .decrement, .performCustomAction, .rotor, .dismiss, .magicTap,
                    .editAction, .setPasteboard, .resignFirstResponder:
                appendUnique("semantic-action", to: &tags)
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
    let environment: HeistExecutionEnvironment
    let invocationStack: [HeistCallGraph.Node]
}

private struct HeistCollectedSemanticSurface {
    let actionCommands: [HeistActionCommandType]
    let targetPredicates: [String]
    let waits: [String]
    let expectations: [String]
    let nestedRunHeists: [String]
    let expectedEffects: [String]
    let semanticFacets: [HeistSemanticSurfaceFacet]

    var catalogActionCommands: [String] {
        actionCommands.map(\.rawValue)
    }

    var catalogSemanticSurfaces: [String] {
        semanticFacets.map(\.catalogValue)
    }

    var projectedSurface: HeistSemanticSurface {
        HeistSemanticSurface(
            actionCommands: catalogActionCommands,
            targetPredicates: targetPredicates,
            waits: waits,
            expectations: expectations,
            nestedRunHeists: nestedRunHeists,
            expectedEffects: expectedEffects,
            semanticSurfaces: catalogSemanticSurfaces
        )
    }
}

private enum HeistSemanticSurfaceFacet: Sendable, Equatable, Hashable {
    case label(HeistSemanticStringMatch)
    case identifier(HeistSemanticStringMatch)
    case value(HeistSemanticStringMatch)
    case hint(HeistSemanticStringMatch)
    case traits(Set<HeistTrait>)
    case actions(Set<ElementAction>)
    case customContent(HeistSemanticCustomContentMatch)
    case rotors([HeistSemanticStringMatch])
    indirect case exclude(HeistSemanticSurfaceFacet)

    var catalogValue: String {
        switch self {
        case .label(let match):
            return "label=\(match.catalogValue)"
        case .identifier(let match):
            return "identifier=\(match.catalogValue)"
        case .value(let match):
            return "value=\(match.catalogValue)"
        case .hint(let match):
            return "hint=\(match.catalogValue)"
        case .traits(let traits):
            return "traits=\(traits.catalogValue)"
        case .actions(let actions):
            return "actions=\(actions.catalogValue)"
        case .customContent(let match):
            return "customContent=\(match.catalogValue)"
        case .rotors(let matches):
            return "rotors=\(matches.catalogValue)"
        case .exclude(let facet):
            return "exclude(\(facet.catalogValue))"
        }
    }
}

private struct HeistSemanticCustomContentMatch: Sendable, Equatable, Hashable {
    let label: HeistSemanticStringMatch?
    let value: HeistSemanticStringMatch?
    let isImportant: Bool?

    init(_ match: CustomContentMatch<String>) {
        self.label = match.label.map(HeistSemanticStringMatch.init)
        self.value = match.value.map(HeistSemanticStringMatch.init)
        self.isImportant = match.isImportant
    }

    init(_ match: CustomContentMatch<StringExpr>) {
        self.label = match.label.map(HeistSemanticStringMatch.init)
        self.value = match.value.map(HeistSemanticStringMatch.init)
        self.isImportant = match.isImportant
    }

    var catalogValue: String {
        [
            label.map { "label=\($0.catalogValue)" },
            value.map { "value=\($0.catalogValue)" },
            isImportant.map { "isImportant=\($0)" },
        ].compactMap { $0 }.joined(separator: ",")
    }
}

private struct HeistSemanticStringMatch: Sendable, Equatable, Hashable {
    let mode: StringMatch<String>.Mode
    let value: HeistSemanticStringValue?

    init(_ match: StringMatch<String>) {
        self.mode = match.mode
        self.value = match.valueIfPresent.map(HeistSemanticStringValue.literal)
    }

    init(_ match: StringMatch<StringExpr>) {
        self.mode = StringMatch<String>.Mode(rawValue: match.mode.rawValue) ?? .exact
        self.value = match.valueIfPresent.map(HeistSemanticStringValue.init)
    }

    var catalogValue: String {
        guard let value else { return mode.rawValue }
        guard mode != .exact else { return value.catalogValue }
        return "\(mode.rawValue)(\(value.catalogValue))"
    }
}

private enum HeistSemanticStringValue: Sendable, Equatable, Hashable {
    case literal(String)
    case reference(HeistReferenceName)

    init(_ expression: StringExpr) {
        switch expression {
        case .literal(let literal):
            self = .literal(literal)
        case .ref(let reference):
            self = .reference(reference)
        }
    }

    var catalogValue: String {
        switch self {
        case .literal(let literal):
            return literal
        case .reference(let reference):
            return "\(reference.rawValue)_ref"
        }
    }
}

private extension Set where Element == HeistTrait {
    var catalogValue: String {
        canonicalHeistTraitArray.map(\.rawValue).joined(separator: "|")
    }
}

private extension Array where Element == HeistSemanticStringMatch {
    var catalogValue: String {
        map(\.catalogValue).joined(separator: "|")
    }
}

private extension Set where Element == ElementAction {
    var catalogValue: String {
        canonicalElementActionArray.map(\.catalogValue).joined(separator: "|")
    }
}

private extension ElementAction {
    var catalogValue: String {
        switch self {
        case .activate:
            return "activate"
        case .increment:
            return "increment"
        case .decrement:
            return "decrement"
        case .custom(let name):
            return "custom(\(name))"
        }
    }
}

private struct HeistSemanticSurfaceBuilder {
    var actionCommands: [HeistActionCommandType] = []
    var targetPredicates: [String] = []
    var waits: [String] = []
    var expectations: [String] = []
    var nestedRunHeists: [String] = []
    var expectedEffects: [String] = []
    var semanticFacets: [HeistSemanticSurfaceFacet] = []

    static func surface(for resolved: ResolvedCatalogHeist) -> HeistCollectedSemanticSurface {
        var builder = Self()
        builder.collect(
            steps: resolved.plan.body,
            definitionScope: resolved.definitionScope,
            rootDefinitionScope: resolved.rootDefinitionScope,
            environment: resolved.environment,
            invocationStack: resolved.invocationStack
        )
        return HeistCollectedSemanticSurface(
            actionCommands: builder.actionCommands,
            targetPredicates: builder.targetPredicates,
            waits: builder.waits,
            expectations: builder.expectations,
            nestedRunHeists: builder.nestedRunHeists,
            expectedEffects: builder.expectedEffects,
            semanticFacets: builder.semanticFacets
        )
    }

    mutating func collect(
        steps: [HeistStep],
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        environment: HeistExecutionEnvironment,
        invocationStack: [HeistCallGraph.Node]
    ) {
        for step in steps {
            collect(
                step: step,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                environment: environment,
                invocationStack: invocationStack
            )
        }
    }

    mutating func collect(
        step: HeistStep,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        environment: HeistExecutionEnvironment,
        invocationStack: [HeistCallGraph.Node]
    ) {
        switch step {
        case .action(let action):
            appendUnique(action.command.wireType, to: &actionCommands)
            collectTargets(from: action.command)
            if let expectation = action.expectationPolicy.expectedStep {
                collectExpectation(expectation.predicate)
            }

        case .wait(let wait):
            collectWait(wait.predicate)
            if let elseBody = wait.elseBody {
                collect(
                    steps: elseBody,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }

        case .conditional(let conditional):
            for predicateCase in conditional.cases {
                collect(
                    steps: predicateCase.body,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }
            if let elseBody = conditional.elseBody {
                collect(
                    steps: elseBody,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }

        case .forEachElement(let forEach):
            appendTargetPredicate(forEach.matching)
            let nestedEnvironment = environment.binding(target: .predicate(forEach.matching), to: forEach.parameter)
            collect(
                steps: forEach.body,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                environment: nestedEnvironment,
                invocationStack: invocationStack
            )

        case .forEachString(let forEach):
            let nestedEnvironment = environment.binding(string: forEach.values.first ?? "", to: forEach.parameter)
            collect(
                steps: forEach.body,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                environment: nestedEnvironment,
                invocationStack: invocationStack
            )

        case .repeatUntil(let repeatUntil):
            collectWait(repeatUntil.predicate)
            collect(
                steps: repeatUntil.body,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                environment: environment,
                invocationStack: invocationStack
            )
            if let elseBody = repeatUntil.elseBody {
                collect(
                    steps: elseBody,
                    definitionScope: definitionScope,
                    rootDefinitionScope: rootDefinitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }

        case .warn, .fail:
            break

        case .heist(let plan):
            let nestedScope = HeistDefinitionScope(definitions: plan.definitions)
            collect(
                steps: plan.body,
                definitionScope: nestedScope,
                rootDefinitionScope: nestedScope,
                environment: environment,
                invocationStack: invocationStack
            )

        case .invoke(let invocation):
            collectInvocation(
                invocation,
                definitionScope: definitionScope,
                rootDefinitionScope: rootDefinitionScope,
                environment: environment,
                invocationStack: invocationStack
            )
        }
    }

    mutating func collectInvocation(
        _ invocation: HeistInvocationStep,
        definitionScope: HeistDefinitionScope,
        rootDefinitionScope: HeistDefinitionScope,
        environment: HeistExecutionEnvironment,
        invocationStack: [HeistCallGraph.Node]
    ) {
        guard let resolved = definitionScope.resolveInvocation(
            path: invocation.invocationPath,
            rootScope: rootDefinitionScope
        ) else { return }
        let resolvedNode = resolved.callGraphNode
        appendUnique(resolvedNode.name, to: &nestedRunHeists)
        guard HeistCallGraph.nodeCycle(closing: resolvedNode, in: invocationStack) == nil,
              let nestedEnvironment = try? environment.binding(
                argument: invocation.argument,
                to: resolved.definition.parameter
              )
        else { return }
        collect(
            steps: resolved.definition.body,
            definitionScope: HeistDefinitionScope(
                definitions: resolved.definition.definitions,
                pathPrefix: resolved.namePath
            ),
            rootDefinitionScope: rootDefinitionScope,
            environment: nestedEnvironment,
            invocationStack: invocationStack + [resolvedNode]
        )
    }

    mutating func collectTargets(from command: HeistActionCommand) {
        for occurrence in command.targetOccurrences {
            appendTargetPredicate(occurrence)
        }
    }

    mutating func collectWait(_ predicate: AccessibilityPredicateExpr) {
        let description = predicate.description
        appendUnique(description, to: &waits)
        appendUnique(description, to: &expectedEffects)
        appendPredicateTargets(predicate)
    }

    mutating func collectExpectation(_ predicate: AccessibilityPredicateExpr) {
        let description = predicate.description
        appendUnique(description, to: &expectations)
        appendUnique(description, to: &expectedEffects)
        appendPredicateTargets(predicate)
    }

    mutating func appendTargetPredicate(_ target: ElementTargetExpr) {
        switch target {
        case .target(let target):
            appendTargetPredicate(target)
        case .predicate(let predicate, _):
            appendUnique(predicate.description, to: &targetPredicates)
            appendSemanticSurfaces(predicate)
        case .ref(let reference):
            appendUnique("target_ref(\(reference))", to: &targetPredicates)
        }
    }

    mutating func appendTargetPredicate(_ target: ElementTarget) {
        switch target {
        case .predicate(let predicate, _):
            appendTargetPredicate(predicate)
        }
    }

    mutating func appendTargetPredicate(_ occurrence: HeistActionCommandTargetOccurrence) {
        switch occurrence.target {
        case .expression(let target):
            appendTargetPredicate(target)
        case .element(let target):
            appendTargetPredicate(target)
        }
    }

    mutating func appendTargetPredicate(_ predicate: ElementPredicate) {
        appendUnique(predicate.description, to: &targetPredicates)
        appendSemanticSurfaces(predicate)
    }

    mutating func appendSemanticSurfaces(_ predicate: ElementPredicate) {
        for check in predicate.checks {
            if let facet = semanticSurfaceFacet(for: check) {
                appendUnique(facet, to: &semanticFacets)
            }
        }
    }

    mutating func appendSemanticSurfaces(_ predicate: ElementPredicateTemplate) {
        for check in predicate.checks {
            if let facet = semanticSurfaceFacet(for: check) {
                appendUnique(facet, to: &semanticFacets)
            }
        }
    }

    func semanticSurfaceFacet(for check: ElementPredicateCheck<String>) -> HeistSemanticSurfaceFacet? {
        switch check {
        case .label(let label) where label.hasPredicateLiteral:
            return .label(HeistSemanticStringMatch(label))
        case .identifier(let identifier) where identifier.hasPredicateLiteral:
            return .identifier(HeistSemanticStringMatch(identifier))
        case .value(let value) where value.hasPredicateLiteral:
            return .value(HeistSemanticStringMatch(value))
        case .hint(let hint) where hint.hasPredicateLiteral:
            return .hint(HeistSemanticStringMatch(hint))
        case .traits(let traits) where !traits.isEmpty:
            return .traits(traits)
        case .actions(let actions) where !actions.isEmpty:
            return .actions(actions)
        case .customContent(let match) where match.hasPredicateLiteral:
            return .customContent(HeistSemanticCustomContentMatch(match))
        case .rotors(let matches) where matches.contains(where: \.hasPredicateLiteral):
            return .rotors(matches.map(HeistSemanticStringMatch.init))
        case .exclude(let check):
            return semanticSurfaceFacet(for: check).map(HeistSemanticSurfaceFacet.exclude)
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return nil
        }
    }

    func semanticSurfaceFacet(for check: ElementPredicateCheck<StringExpr>) -> HeistSemanticSurfaceFacet? {
        switch check {
        case .label(let label) where label.hasPredicateLiteral:
            return .label(HeistSemanticStringMatch(label))
        case .identifier(let identifier) where identifier.hasPredicateLiteral:
            return .identifier(HeistSemanticStringMatch(identifier))
        case .value(let value) where value.hasPredicateLiteral:
            return .value(HeistSemanticStringMatch(value))
        case .hint(let hint) where hint.hasPredicateLiteral:
            return .hint(HeistSemanticStringMatch(hint))
        case .traits(let traits) where !traits.isEmpty:
            return .traits(traits)
        case .actions(let actions) where !actions.isEmpty:
            return .actions(actions)
        case .customContent(let match) where match.hasPredicateLiteral:
            return .customContent(HeistSemanticCustomContentMatch(match))
        case .rotors(let matches) where matches.contains(where: \.hasPredicateLiteral):
            return .rotors(matches.map(HeistSemanticStringMatch.init))
        case .exclude(let check):
            return semanticSurfaceFacet(for: check).map(HeistSemanticSurfaceFacet.exclude)
        case .label, .identifier, .value, .hint, .traits, .actions, .customContent, .rotors:
            return nil
        }
    }

    mutating func appendPredicateTargets(_ predicate: AccessibilityPredicateExpr) {
        switch predicate {
        case .predicate(let predicate):
            appendPredicateTargets(predicate)
        case .state(let state):
            appendPredicateTargets(state)
        case .changePredicate(let change):
            appendPredicateTargets(change)
        case .noChangePredicate:
            break
        }
    }

    mutating func appendPredicateTargets(_ predicate: AccessibilityPredicate) {
        switch predicate {
        case .state(let state):
            appendPredicateTargets(state)
        case .changePredicate(let change):
            appendPredicateTargets(change)
        case .noChangePredicate:
            break
        }
    }

    mutating func appendPredicateTargets(_ state: AccessibilityPredicate.State) {
        switch state {
        case .exists(let predicate), .missing(let predicate):
            appendTargetPredicate(predicate)
        case .existsTarget(let target), .missingTarget(let target):
            appendTargetPredicate(target)
        case .all(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        }
    }

    mutating func appendPredicateTargets(_ state: StatePredicateExpr) {
        switch state {
        case .exists(let predicate), .missing(let predicate):
            appendUnique(predicate.description, to: &targetPredicates)
            appendSemanticSurfaces(predicate)
        case .existsTarget(let target), .missingTarget(let target):
            appendTargetPredicate(target)
        case .all(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        }
    }

    mutating func appendPredicateTargets(_ change: AccessibilityPredicate.Change) {
        switch change {
        case .any:
            break
        case .screenScope(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        case .elementsScope(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        case .allScopes(let changes):
            for change in changes {
                appendPredicateTargets(change)
            }
        }
    }

    mutating func appendPredicateTargets(_ change: AccessibilityPredicate.ChangeScope) {
        switch change {
        case .screen(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        case .elements(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        case .all(let changes):
            for change in changes {
                appendPredicateTargets(change)
            }
        }
    }

    mutating func appendPredicateTargets(_ change: ChangePredicateExpr) {
        switch change {
        case .any:
            break
        case .screenScope(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        case .elementsScope(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        case .allScopes(let changes):
            for change in changes {
                appendPredicateTargets(change)
            }
        }
    }

    mutating func appendPredicateTargets(_ change: ChangeScopePredicateExpr) {
        switch change {
        case .screen(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        case .elements(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        case .all(let changes):
            for change in changes {
                appendPredicateTargets(change)
            }
        }
    }

    mutating func appendPredicateTargets(_ predicate: ElementDeltaPredicate) {
        switch predicate {
        case .appearedElement(let element), .disappearedElement(let element):
            appendTargetPredicate(element)
        case .updatedElement(let update):
            if let element = update.element {
                appendTargetPredicate(element)
            }
        }
    }

    mutating func appendPredicateTargets(_ predicate: ElementDeltaPredicateExpr) {
        switch predicate {
        case .appearedElement(let element), .disappearedElement(let element):
            appendUnique(element.description, to: &targetPredicates)
            appendSemanticSurfaces(element)
        case .updatedElement(let update):
            if let element = update.element {
                appendUnique(element.description, to: &targetPredicates)
                appendSemanticSurfaces(element)
            }
        }
    }
}

private func appendUnique<T: Equatable>(_ value: T, to values: inout [T]) {
    guard !values.contains(value) else { return }
    values.append(value)
}

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
    case predicate(ElementPredicate)
    case template(ElementPredicateTemplate)
    case container(ContainerPredicateExpr)
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

    init(_ match: CustomContentMatch<StringExpr>) {
        self.label = match.label.map(HeistSemanticStringMatch.init)
        self.value = match.value.map(HeistSemanticStringMatch.init)
        self.isImportant = match.isImportant
    }
}

public struct HeistSemanticStringMatch: Sendable, Equatable, Hashable {
    public let mode: StringMatch<String>.Mode
    public let value: HeistSemanticStringValue?

    public init(mode: StringMatch<String>.Mode, value: HeistSemanticStringValue?) {
        self.mode = mode
        self.value = value
    }

    init(_ match: StringMatch<StringExpr>) {
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
        self.value = match.valueIfPresent.map(HeistSemanticStringValue.init)
    }
}

public enum HeistSemanticStringValue: Sendable, Equatable, Hashable {
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
    public let waits: [AccessibilityPredicate<RootContext>]
    public let expectations: [AccessibilityPredicate<RootContext>]
    public let nestedRunHeists: [HeistInvocationPath]
    public let expectedEffects: [AccessibilityPredicate<RootContext>]
    public let semanticSurfaces: [HeistSemanticSurfaceFact]

    public init(
        actionCommands: [HeistActionCommandType] = [],
        targetPredicates: [HeistTargetPredicateFact] = [],
        waits: [AccessibilityPredicate<RootContext>] = [],
        expectations: [AccessibilityPredicate<RootContext>] = [],
        nestedRunHeists: [HeistInvocationPath] = [],
        expectedEffects: [AccessibilityPredicate<RootContext>] = [],
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
    let environment: HeistExecutionEnvironment
    let invocationStack: [HeistCallGraph.Node]
}

private struct HeistSemanticSurfaceBuilder {
    var actionCommands: [HeistActionCommandType] = []
    var targetPredicateFacts: [HeistTargetPredicateFact] = []
    var waits: [AccessibilityPredicate<RootContext>] = []
    var expectations: [AccessibilityPredicate<RootContext>] = []
    var nestedRunHeists: [HeistInvocationPath] = []
    var expectedEffects: [AccessibilityPredicate<RootContext>] = []
    var semanticFacets: [ElementPredicateCheck<StringExpr>] = []

    static func surface(for resolved: ResolvedCatalogHeist) -> HeistSemanticSurface {
        var builder = Self()
        builder.collect(
            steps: resolved.plan.body,
            definitionScope: resolved.definitionScope,
            rootDefinitionScope: resolved.rootDefinitionScope,
            environment: resolved.environment,
            invocationStack: resolved.invocationStack
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
            let target = AccessibilityTarget.predicate(ElementPredicateTemplate(forEach.matching))
            appendTargetPredicate(target)
            let nestedEnvironment = environment.binding(target: target, to: forEach.parameter)
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
        appendUnique(HeistInvocationPath.preconditionValidated(dottedName: resolvedNode.name), to: &nestedRunHeists)
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

    mutating func collectWait(_ predicate: AccessibilityPredicate<RootContext>) {
        appendUnique(predicate, to: &waits)
        appendUnique(predicate, to: &expectedEffects)
        appendPredicateTargets(predicate)
    }

    mutating func collectExpectation(_ predicate: AccessibilityPredicate<RootContext>) {
        appendUnique(predicate, to: &expectations)
        appendUnique(predicate, to: &expectedEffects)
        appendPredicateTargets(predicate)
    }

    mutating func appendTargetPredicate(_ target: AccessibilityTarget) {
        switch target {
        case .predicate(let predicate, _):
            appendUnique(.template(predicate), to: &targetPredicateFacts)
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
        for check in predicate.checks where check.hasPredicateLiteral {
            appendUnique(check, to: &semanticFacets)
        }
    }

    mutating func appendPredicateTargets<Context>(
        _ predicate: AccessibilityPredicate<Context>
    ) {
        appendPredicateTargets(predicate.node)
    }

    mutating func appendPredicateTargets(_ node: AccessibilityPredicateNode) {
        switch node {
        case .exists(let target), .missing(let target),
             .appeared(let target), .disappeared(let target):
            appendTargetPredicate(target)
        case .announcement:
            break
        case .changed(let predicate):
            appendPredicateTargets(predicate)
        case .noChange:
            break
        case .screen(let assertions), .elements(let assertions):
            for assertion in assertions {
                appendPredicateTargets(assertion)
            }
        case .updated(let target, _):
            appendTargetPredicate(target)
        }
    }
}

private extension HeistSemanticSurfaceFact {
    init(_ check: ElementPredicateCheck<StringExpr>) {
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

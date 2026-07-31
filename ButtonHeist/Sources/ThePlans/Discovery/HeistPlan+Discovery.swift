import Foundation

public enum HeistCatalogRole: String, Codable, Sendable, Equatable {
    case entry
    case capability
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
    public var requiresArgument: Bool { parameterKind.requiresArgument }
    public let summary: String?
    public let tags: [HeistCatalogTag]
    public let parameterName: HeistReferenceName?
    public let nestedRunHeists: [HeistInvocationPath]?
    public let actionCommands: [HeistActionCommandType]?
    public let waitCount: Int?
    public let expectationCount: Int?
    public let semanticSurfaces: [ElementPredicateCheck]?

    public init(
        identity: HeistCatalogIdentity,
        parameterKind: HeistParameterKind,
        summary: String? = nil,
        tags: [HeistCatalogTag] = [],
        parameterName: HeistReferenceName? = nil,
        nestedRunHeists: [HeistInvocationPath]? = nil,
        actionCommands: [HeistActionCommandType]? = nil,
        waitCount: Int? = nil,
        expectationCount: Int? = nil,
        semanticSurfaces: [ElementPredicateCheck]? = nil
    ) {
        self.identity = identity
        self.parameterKind = parameterKind
        self.summary = summary
        self.tags = tags
        self.parameterName = parameterName
        self.nestedRunHeists = nestedRunHeists
        self.actionCommands = actionCommands
        self.waitCount = waitCount
        self.expectationCount = expectationCount
        self.semanticSurfaces = semanticSurfaces
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
    public let semanticSurfaces: [ElementPredicateCheck]

    package init(
        actionCommands: [HeistActionCommandType] = [],
        targetPredicates: [HeistTargetPredicateFact] = [],
        waits: [AccessibilityPredicate] = [],
        expectations: [AccessibilityPredicate] = [],
        nestedRunHeists: [HeistInvocationPath] = [],
        expectedEffects: [AccessibilityPredicate] = [],
        semanticSurfaces: [ElementPredicateCheck] = []
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
    public var requiresArgument: Bool { parameterKind.requiresArgument }
    public let summary: String?
    public let semanticSurface: HeistSemanticSurface

    public init(
        identity: HeistCatalogIdentity,
        parameterKind: HeistParameterKind,
        parameterName: HeistReferenceName?,
        summary: String?,
        semanticSurface: HeistSemanticSurface
    ) {
        self.identity = identity
        self.parameterKind = parameterKind
        self.parameterName = parameterName
        self.summary = summary
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
        var identities: [HeistCatalogIdentity] = []
        var entries: [HeistCatalogEntry] = []
        HeistPlanTraversal(expandsInvocations: false).walk(self) { event in
            let plan: HeistPlan
            let context: HeistTraversalContext
            let identity: HeistCatalogIdentity
            let definitionComponents: [HeistPlanName]
            switch event {
            case .enterPlan(let observedPlan, let observedContext):
                plan = observedPlan
                context = observedContext
                identity = .entry(plan.name)
                definitionComponents = []
            case .enterDefinition(let observedPlan, let observedContext):
                guard let name = observedPlan.name else {
                    preconditionFailure("admitted heist definitions must have names")
                }
                plan = observedPlan
                context = observedContext
                definitionComponents = context.definitionScope.pathPrefix + [name]
                guard let first = definitionComponents.first else {
                    preconditionFailure("definition catalog paths must not be empty")
                }
                identity = .capability(HeistDefinitionPath(first: first, remaining: Array(definitionComponents.dropFirst())))
            default:
                return
            }
            identities.append(identity)

            let parameterKind = plan.parameter.kind
            let surface = semanticSurface(
                plan: plan,
                context: context,
                definitionComponents: definitionComponents
            )
            var summary = identity.role == .entry ? "Root entry heist" : "Reusable heist capability"
            if parameterKind.requiresArgument {
                summary += " requiring \(parameterKind.rawValue) argument"
            }

            var tags = [identity.role == .entry ? HeistCatalogTag.entry : .capability]
            var tagSet = Set(tags)
            if parameterKind.requiresArgument, tagSet.insert(.parameterized).inserted { tags.append(.parameterized) }
            if !surface.nestedRunHeists.isEmpty, tagSet.insert(.composed).inserted { tags.append(.composed) }
            if !surface.waits.isEmpty || !surface.expectations.isEmpty,
               tagSet.insert(.assertion).inserted { tags.append(.assertion) }
            for command in surface.actionCommands {
                let tag: HeistCatalogTag?
                switch command {
                case .typeText:
                    tag = .textInput
                case .scroll, .scrollToVisible, .scrollToEdge:
                    tag = .scroll
                case .oneFingerTap, .longPress, .swipe, .drag:
                    tag = .gesture
                case .activate, .increment, .decrement, .performCustomAction, .rotor, .dismiss, .magicTap,
                        .editAction, .setPasteboard, .dismissKeyboard:
                    tag = .semanticAction
                case .takeScreenshot:
                    tag = nil
                }
                if let tag, tagSet.insert(tag).inserted {
                    tags.append(tag)
                }
            }

            guard detail == .detailed else {
                entries.append(HeistCatalogEntry(
                    identity: identity,
                    parameterKind: parameterKind,
                    summary: summary,
                    tags: tags
                ))
                return
            }
            entries.append(HeistCatalogEntry(
                identity: identity,
                parameterKind: parameterKind,
                summary: summary,
                tags: tags,
                parameterName: plan.parameter.name,
                nestedRunHeists: surface.nestedRunHeists.isEmpty ? nil : surface.nestedRunHeists,
                actionCommands: surface.actionCommands.isEmpty ? nil : surface.actionCommands,
                waitCount: surface.waits.count,
                expectationCount: surface.expectations.count,
                semanticSurfaces: surface.semanticSurfaces.isEmpty ? nil : surface.semanticSurfaces
            ))
        }
        try validateUniqueCatalogPaths(identities)
        return entries
    }

    func describeHeist(at requestedPath: HeistDefinitionPath) throws -> HeistDescription {
        var identities: [HeistCatalogIdentity] = []
        var description: HeistDescription?
        HeistPlanTraversal(expandsInvocations: false).walk(self) { event in
            let plan: HeistPlan
            let context: HeistTraversalContext
            let identity: HeistCatalogIdentity
            let definitionComponents: [HeistPlanName]
            switch event {
            case .enterPlan(let observedPlan, let observedContext):
                plan = observedPlan
                context = observedContext
                identity = .entry(plan.name)
                definitionComponents = []
            case .enterDefinition(let observedPlan, let observedContext):
                guard let name = observedPlan.name else {
                    preconditionFailure("admitted heist definitions must have names")
                }
                plan = observedPlan
                context = observedContext
                definitionComponents = context.definitionScope.pathPrefix + [name]
                guard let first = definitionComponents.first else {
                    preconditionFailure("definition catalog paths must not be empty")
                }
                identity = .capability(HeistDefinitionPath(first: first, remaining: Array(definitionComponents.dropFirst())))
            default:
                return
            }
            identities.append(identity)
            guard description == nil, identity.lookupPath == requestedPath else { return }
            description = HeistDescription(
                identity: identity,
                parameterKind: plan.parameter.kind,
                parameterName: plan.parameter.name,
                summary: nil,
                semanticSurface: semanticSurface(
                    plan: plan,
                    context: context,
                    definitionComponents: definitionComponents
                )
            )
        }
        try validateUniqueCatalogPaths(identities)
        guard let description else {
            throw HeistDescriptionLookupError(
                requestedPath: requestedPath,
                availableIdentities: identities
            )
        }
        return description
    }
}

private extension HeistPlan {
    func validateUniqueCatalogPaths(_ identities: [HeistCatalogIdentity]) throws {
        var seen = Set<HeistDefinitionPath>()
        var duplicateSet = Set<HeistCatalogIdentity>()
        var duplicates: [HeistCatalogIdentity] = []
        for identity in identities {
            guard let path = identity.lookupPath else { continue }
            if !seen.insert(path).inserted, duplicateSet.insert(identity).inserted {
                duplicates.append(identity)
            }
        }
        guard duplicates.isEmpty else {
            throw HeistCatalogError(duplicateIdentities: duplicates)
        }
    }

    func semanticSurface(
        plan: HeistPlan,
        context: HeistTraversalContext,
        definitionComponents: [HeistPlanName]
    ) -> HeistSemanticSurface {
        var actionCommands: [HeistActionCommandType] = [], actionCommandSet = Set<HeistActionCommandType>()
        var targetPredicates: [HeistTargetPredicateFact] = [], targetPredicateSet = Set<HeistTargetPredicateFact>()
        var waits: [AccessibilityPredicate] = [], waitIndexes = Set<Int>()
        var expectations: [AccessibilityPredicate] = [], expectationIndexes = Set<Int>()
        var nestedRunHeists: [HeistInvocationPath] = [], nestedRunHeistSet = Set<HeistInvocationPath>()
        var expectedEffects: [AccessibilityPredicate] = [], expectedEffectIndexes = Set<Int>()
        var semanticFacets: [ElementPredicateCheck] = [], semanticFacetSet = Set<ElementPredicateCheck>()

        let definitionScope = HeistDefinitionScope(definitions: plan.definitions, pathPrefix: definitionComponents)
        HeistPlanTraversal().walk(
            steps: plan.body,
            path: .root.child(.body),
            depth: 1,
            referenceBindings: context.referenceBindings,
            definitionScope: definitionScope,
            rootDefinitionScope: context.rootDefinitionScope,
            invocationStack: definitionComponents.isEmpty ? [] : [HeistInvocationPath(namePath: definitionComponents)]
        ) { event in
            var observedTargets: [AccessibilityTarget] = []
            var observedPredicate: AccessibilityPredicate?
            var isWait = false
            switch event {
            case .action(let action, _):
                if actionCommandSet.insert(action.command.wireType).inserted { actionCommands.append(action.command.wireType) }
                observedTargets = action.command.targetOccurrences.map(\.target)
                observedPredicate = action.expectationPolicy.expectedExpectation?.predicate
            case .wait(let wait, let context):
                guard !context.path.ends(in: .expectation) else { return }
                observedPredicate = wait.predicate
                isWait = true
            case .forEachElement(let step, _):
                observedTargets = [.predicate(step.matching)]
            case .invoke(let invocation, let context):
                observedPredicate = invocation.expectation?.predicate
                if let resolved = context.resolveInvocation(path: invocation.path),
                   nestedRunHeistSet.insert(resolved.invocationPath).inserted {
                    nestedRunHeists.append(resolved.invocationPath)
                }
            default:
                return
            }
            if let predicate = observedPredicate {
                if isWait {
                    if waitIndexes.insert(waits.firstIndex(of: predicate) ?? waits.endIndex).inserted { waits.append(predicate) }
                } else {
                    if expectationIndexes.insert(expectations.firstIndex(of: predicate) ?? expectations.endIndex).inserted { expectations.append(predicate) }
                }
                if expectedEffectIndexes.insert(expectedEffects.firstIndex(of: predicate) ?? expectedEffects.endIndex).inserted {
                    expectedEffects.append(predicate)
                }
                switch predicate.core {
                case .presence(.exists(let target)), .presence(.missing(let target)):
                    observedTargets.append(target)
                // A screen boundary names no elements, so it observes no targets.
                case .screenChanged: break
                case .elementsChanged(let assertions):
                    for assertion in assertions {
                        switch assertion {
                        case .exists(let target), .missing(let target),
                             .appeared(let target), .disappeared(let target):
                            observedTargets.append(target)
                        case .updated(let target, _):
                            observedTargets.append(target.accessibilityTarget)
                        }
                    }
                case .notification(let notification):
                    if let element = notification.element {
                        observedTargets.append(.predicate(element))
                    }
                }
            }
            for var target in observedTargets {
                targetTraversal: while true {
                    let fact: HeistTargetPredicateFact
                    switch target {
                    case .predicate(let predicate, _):
                        fact = .predicate(predicate)
                        for check in predicate.checks where check.hasPredicateLiteral && semanticFacetSet.insert(check).inserted {
                            semanticFacets.append(check)
                        }
                    case .container(let predicate, _): fact = .container(predicate)
                    case .ref(let reference): fact = .targetReference(reference)
                    case .within(_, let nestedTarget):
                        target = nestedTarget
                        continue targetTraversal
                    }
                    if targetPredicateSet.insert(fact).inserted { targetPredicates.append(fact) }
                    break targetTraversal
                }
            }
        }
        return HeistSemanticSurface(
            actionCommands: actionCommands,
            targetPredicates: targetPredicates,
            waits: waits,
            expectations: expectations,
            nestedRunHeists: nestedRunHeists,
            expectedEffects: expectedEffects,
            semanticSurfaces: semanticFacets
        )
    }
}

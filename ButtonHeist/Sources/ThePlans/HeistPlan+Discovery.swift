import Foundation

public enum HeistCatalogRole: String, Codable, Sendable, Equatable {
    case entry
    case capability
}

public enum HeistAdmissionStatus: String, Codable, Sendable, Equatable {
    case admitted
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
    public let admissionStatus: HeistAdmissionStatus?

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
        admissionStatus: HeistAdmissionStatus? = nil
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
        self.admissionStatus = admissionStatus
    }
}

public struct HeistCatalog: Codable, Sendable, Equatable {
    public let heists: [HeistCatalogEntry]

    public init(heists: [HeistCatalogEntry]) {
        self.heists = heists
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
    public let admissionStatus: HeistAdmissionStatus
    public let semanticSurface: HeistSemanticSurface

    public init(
        name: String,
        role: HeistCatalogRole,
        parameterKind: HeistParameterKind,
        parameterName: HeistReferenceName?,
        requiresArgument: Bool,
        summary: String?,
        admissionStatus: HeistAdmissionStatus,
        semanticSurface: HeistSemanticSurface
    ) {
        self.name = name
        self.role = role
        self.parameterKind = parameterKind
        self.parameterName = parameterName
        self.requiresArgument = requiresArgument
        self.summary = summary
        self.admissionStatus = admissionStatus
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
    func admittedHeistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistCatalog {
        try heistCatalog(detail: detail)
    }

    func describeAdmittedHeist(named requestedName: String) throws -> HeistDescription {
        try describeHeist(named: requestedName)
    }

    func heistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistCatalog {
        try assertRuntimeAdmissible()
        return try uncheckedHeistCatalog(detail: detail)
    }

    func describeHeist(named requestedName: String) throws -> HeistDescription {
        try assertRuntimeAdmissible()
        return try uncheckedDescribeHeist(named: requestedName)
    }
}

private extension HeistPlan {
    func uncheckedHeistCatalog(detail: HeistCatalogDetail = .summary) throws -> HeistCatalog {
        let resolved = try catalogResolvedHeists()
        return HeistCatalog(heists: resolved.map { catalogEntry(for: $0, detail: detail) })
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
            admissionStatus: .admitted,
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
                entry: catalogEntry(name: rootName, role: .entry, parameter: .none),
                plan: self,
                definitionScope: rootScope,
                environment: .empty,
                invocationStack: []
            ),
        ]

        collectCatalogDefinitions(
            definitions,
            pathPrefix: [],
            into: &heists
        )
        try validateUniqueCatalogNames(heists.map(\.entry.name))
        return heists
    }

    func collectCatalogDefinitions(
        _ definitions: [HeistPlan],
        pathPrefix: [String],
        into heists: inout [ResolvedCatalogHeist]
    ) {
        for definition in definitions {
            guard let localName = definition.name, !localName.isEmpty else { continue }
            let namePath = pathPrefix + [localName]
            let qualifiedName = namePath.joined(separator: ".")
            let environment = Self.discoveryEnvironment(for: definition.parameter)
            heists.append(ResolvedCatalogHeist(
                entry: catalogEntry(
                    name: qualifiedName,
                    role: .capability,
                    parameter: definition.parameter
                ),
                plan: definition,
                definitionScope: HeistDefinitionScope(definitions: definition.definitions, pathPrefix: namePath),
                environment: environment,
                invocationStack: [qualifiedName]
            ))
            collectCatalogDefinitions(
                definition.definitions,
                pathPrefix: namePath,
                into: &heists
            )
        }
    }

    static func discoveryEnvironment(for parameter: HeistParameter) -> HeistExecutionEnvironment {
        guard let name = parameter.name else { return .empty }
        switch parameter {
        case .none:
            return .empty
        case .strings:
            return .empty.binding(string: "__heist_parameter__", to: name)
        case .elementTarget:
            return .empty.binding(target: .predicate(.identifier("__heist_parameter__")), to: name)
        }
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
            admissionStatus: .admitted
        )
    }

    func catalogSummary(for entry: HeistCatalogEntry) -> String {
        var summary = entry.role == .entry ? "Root entry heist" : "Reusable heist capability"
        if entry.requiresArgument {
            summary += " requiring \(entry.parameterKind.rawValue) argument"
        }
        return summary
    }

    func catalogTags(for entry: HeistCatalogEntry, surface: HeistSemanticSurface) -> [String] {
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
        if surface.actionCommands.contains("typeText") {
            appendUnique("text-input", to: &tags)
        }
        if surface.actionCommands.contains(where: Self.isViewportAction) {
            appendUnique("viewport", to: &tags)
        }
        if surface.actionCommands.contains(where: Self.isGestureAction) {
            appendUnique("gesture", to: &tags)
        }
        if surface.actionCommands.contains(where: Self.isSemanticAction) {
            appendUnique("semantic-action", to: &tags)
        }
        return tags
    }

    static func isSemanticAction(_ command: String) -> Bool {
        [
            "activate",
            "increment",
            "decrement",
            "performCustomAction",
            "rotor",
            "editAction",
            "setPasteboard",
            "resignFirstResponder",
        ].contains(command)
    }

    static func isGestureAction(_ command: String) -> Bool {
        ["oneFingerTap", "longPress", "swipe", "drag"].contains(command)
    }

    static func isViewportAction(_ command: String) -> Bool {
        ["scroll", "scrollToVisible", "scrollToEdge"].contains(command)
    }
}

struct ResolvedCatalogHeist {
    let entry: HeistCatalogEntry
    let plan: HeistPlan
    let definitionScope: HeistDefinitionScope
    let environment: HeistExecutionEnvironment
    let invocationStack: [String]
}

private struct HeistSemanticSurfaceBuilder {
    var actionCommands: [String] = []
    var targetPredicates: [String] = []
    var waits: [String] = []
    var expectations: [String] = []
    var nestedRunHeists: [String] = []
    var expectedEffects: [String] = []
    var semanticSurfaces: [String] = []

    static func surface(for resolved: ResolvedCatalogHeist) -> HeistSemanticSurface {
        var builder = Self()
        builder.collect(
            steps: resolved.plan.body,
            definitionScope: resolved.definitionScope,
            environment: resolved.environment,
            invocationStack: resolved.invocationStack
        )
        return HeistSemanticSurface(
            actionCommands: builder.actionCommands,
            targetPredicates: builder.targetPredicates,
            waits: builder.waits,
            expectations: builder.expectations,
            nestedRunHeists: builder.nestedRunHeists,
            expectedEffects: builder.expectedEffects,
            semanticSurfaces: builder.semanticSurfaces
        )
    }

    mutating func collect(
        steps: [HeistStep],
        definitionScope: HeistDefinitionScope,
        environment: HeistExecutionEnvironment,
        invocationStack: [String]
    ) {
        for step in steps {
            collect(
                step: step,
                definitionScope: definitionScope,
                environment: environment,
                invocationStack: invocationStack
            )
        }
    }

    mutating func collect(
        step: HeistStep,
        definitionScope: HeistDefinitionScope,
        environment: HeistExecutionEnvironment,
        invocationStack: [String]
    ) {
        switch step {
        case .action(let action):
            appendUnique(action.command.wireType.rawValue, to: &actionCommands)
            collectTargets(from: action.command)
            if let expectation = action.expectation {
                collectExpectation(expectation.predicate)
            }

        case .wait(let wait):
            collectWait(wait.predicate)

        case .conditional(let conditional):
            for predicateCase in conditional.cases {
                collect(
                    steps: predicateCase.body,
                    definitionScope: definitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }
            if let elseBody = conditional.elseBody {
                collect(
                    steps: elseBody,
                    definitionScope: definitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }

        case .waitForCases(let waitForCases):
            for predicateCase in waitForCases.cases {
                collectWait(predicateCase.predicate)
                collect(
                    steps: predicateCase.body,
                    definitionScope: definitionScope,
                    environment: environment,
                    invocationStack: invocationStack
                )
            }
            if let elseBody = waitForCases.elseBody {
                collect(
                    steps: elseBody,
                    definitionScope: definitionScope,
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
                environment: nestedEnvironment,
                invocationStack: invocationStack
            )

        case .forEachString(let forEach):
            let nestedEnvironment = environment.binding(string: forEach.values.first ?? "", to: forEach.parameter)
            collect(
                steps: forEach.body,
                definitionScope: definitionScope,
                environment: nestedEnvironment,
                invocationStack: invocationStack
            )

        case .warn, .fail:
            break

        case .heist(let plan):
            let nestedScope = HeistDefinitionScope(definitions: plan.definitions)
            collect(
                steps: plan.body,
                definitionScope: nestedScope,
                environment: environment,
                invocationStack: invocationStack
            )

        case .invoke(let invocation):
            guard let resolved = definitionScope.resolve(path: invocation.path) else { return }
            appendUnique(resolved.qualifiedName, to: &nestedRunHeists)
            guard !invocationStack.contains(resolved.qualifiedName),
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
                environment: nestedEnvironment,
                invocationStack: invocationStack + [resolved.qualifiedName]
            )
        }
    }

    mutating func collectTargets(from command: HeistActionCommand) {
        switch command {
        case .activate(let target), .increment(let target), .decrement(let target), .viewportScrollToVisible(let target):
            appendTargetPredicate(target)
        case .customAction(_, let target):
            appendTargetPredicate(target)
        case .rotor(_, let target, _):
            appendTargetPredicate(target)
        case .typeText(_, let target):
            if let target { appendTargetPredicate(target) }
        case .mechanicalTap(let target):
            appendTargetPredicate(target.selection)
        case .mechanicalLongPress(let target):
            appendTargetPredicate(target.selection)
        case .mechanicalSwipe(let target):
            appendTargetPredicates(target.selection)
        case .mechanicalDrag(let target):
            appendTargetPredicates(target.selection)
        case .viewportScroll(let target):
            appendTargetPredicate(target.selection)
        case .viewportScrollToEdge(let target):
            appendTargetPredicate(target.selection)
        case .editAction, .setPasteboard, .dismissKeyboard:
            break
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

    mutating func appendTargetPredicate(_ selection: GesturePointSelection) {
        if case .element(let target) = selection {
            appendTargetPredicate(target)
        }
    }

    mutating func appendTargetPredicate(_ selection: ScrollContainerSelection) {
        if case .element(let target) = selection {
            appendTargetPredicate(target)
        }
    }

    mutating func appendTargetPredicates(_ selection: SwipeGestureSelection) {
        switch selection {
        case .unitElement(let target, _, _), .elementDirection(let target, _):
            appendTargetPredicate(target)
        case .point(let start, _):
            appendTargetPredicate(start)
        }
    }

    mutating func appendTargetPredicates(_ selection: DragGestureSelection) {
        if case .elementToPoint(let target, _) = selection {
            appendTargetPredicate(target)
        }
    }

    mutating func appendTargetPredicate(_ predicate: ElementPredicate) {
        appendUnique(predicate.description, to: &targetPredicates)
        appendSemanticSurfaces(predicate)
    }

    mutating func appendSemanticSurfaces(_ predicate: ElementPredicate) {
        if let label = predicate.label, !label.isEmpty {
            appendUnique("label=\(label)", to: &semanticSurfaces)
        }
        if let identifier = predicate.identifier, !identifier.isEmpty {
            appendUnique("identifier=\(identifier)", to: &semanticSurfaces)
        }
        if !predicate.traits.isEmpty {
            appendUnique("traits=\(predicate.traits.map(\.rawValue).joined(separator: "|"))", to: &semanticSurfaces)
        }
        if !predicate.excludeTraits.isEmpty {
            appendUnique(
                "excludeTraits=\(predicate.excludeTraits.map(\.rawValue).joined(separator: "|"))",
                to: &semanticSurfaces
            )
        }
    }

    mutating func appendSemanticSurfaces(_ predicate: ElementPredicateTemplate) {
        if let label = predicate.label {
            appendUnique("label=\(semanticString(label))", to: &semanticSurfaces)
        }
        if let identifier = predicate.identifier {
            appendUnique("identifier=\(semanticString(identifier))", to: &semanticSurfaces)
        }
        if !predicate.traits.isEmpty {
            appendUnique("traits=\(predicate.traits.map(\.rawValue).joined(separator: "|"))", to: &semanticSurfaces)
        }
        if !predicate.excludeTraits.isEmpty {
            appendUnique(
                "excludeTraits=\(predicate.excludeTraits.map(\.rawValue).joined(separator: "|"))",
                to: &semanticSurfaces
            )
        }
    }

    func semanticString(_ expression: StringExpr) -> String {
        switch expression {
        case .literal(let literal):
            return literal
        case .ref(let reference):
            return "\(reference)_ref"
        }
    }

    mutating func appendPredicateTargets(_ predicate: AccessibilityPredicateExpr) {
        switch predicate {
        case .predicate(let predicate):
            appendPredicateTargets(predicate)
        case .state(let state):
            appendPredicateTargets(state)
        case .changed(let change):
            appendPredicateTargets(change)
        }
    }

    mutating func appendPredicateTargets(_ predicate: AccessibilityPredicate) {
        switch predicate {
        case .state(let state):
            appendPredicateTargets(state)
        case .changed(let change):
            appendPredicateTargets(change)
        }
    }

    mutating func appendPredicateTargets(_ state: AccessibilityPredicate.State) {
        switch state {
        case .present(let predicate), .absent(let predicate):
            appendTargetPredicate(predicate)
        case .presentTarget(let target), .absentTarget(let target):
            appendTargetPredicate(target)
        case .all(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        }
    }

    mutating func appendPredicateTargets(_ state: StatePredicateExpr) {
        switch state {
        case .present(let predicate), .absent(let predicate):
            appendUnique(predicate.description, to: &targetPredicates)
            appendSemanticSurfaces(predicate)
        case .presentTarget(let target), .absentTarget(let target):
            appendTargetPredicate(target)
        case .all(let states):
            for state in states {
                appendPredicateTargets(state)
            }
        }
    }

    mutating func appendPredicateTargets(_ change: AccessibilityPredicate.Change) {
        switch change {
        case .screen(let state):
            if let state { appendPredicateTargets(state) }
        case .elements:
            break
        case .appeared(let predicate), .disappeared(let predicate):
            appendTargetPredicate(predicate)
        case .updated(let update):
            if let element = update.element {
                appendTargetPredicate(element)
            }
        }
    }

    mutating func appendPredicateTargets(_ change: ChangePredicateExpr) {
        switch change {
        case .screen(let state):
            if let state { appendPredicateTargets(state) }
        case .elements:
            break
        case .appeared(let predicate), .disappeared(let predicate):
            appendUnique(predicate.description, to: &targetPredicates)
            appendSemanticSurfaces(predicate)
        case .updated(let update):
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

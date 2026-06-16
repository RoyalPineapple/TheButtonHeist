import Foundation

// Admission owns the externally submitted plan shape. Decoding this type proves
// only that source/artifact JSON can be loaded as plan IR; RuntimeSafety below
// is the separate executable-plan boundary.
@_spi(ButtonHeistInternals) public typealias UnvalidatedHeistPlan = HeistPlanAdmissionCandidate

@_spi(ButtonHeistInternals) public struct HeistPlanAdmissionCandidate: Codable, Sendable, Equatable {
    public let version: Int
    public let name: String?
    public let parameter: HeistParameter
    public let definitions: [HeistPlanAdmissionCandidate]
    public let body: [HeistStepAdmissionCandidate]

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, name, parameter, definitions, body
    }

    public init(
        version: Int = HeistPlan.currentVersion,
        name: String? = nil,
        parameter: HeistParameter = .none,
        definitions: [HeistPlanAdmissionCandidate] = [],
        body: [HeistStep]
    ) {
        self.version = version
        self.name = name
        self.parameter = parameter
        self.definitions = definitions
        self.body = body.map(HeistStepAdmissionCandidate.init)
    }

    init(_ plan: HeistPlan) {
        version = plan.version
        name = plan.name
        parameter = plan.parameter
        definitions = plan.definitions.map(HeistPlanAdmissionCandidate.init)
        body = plan.body.map(HeistStepAdmissionCandidate.init)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .version)
        guard decodedVersion == HeistPlan.currentVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: container,
                debugDescription: "Unsupported heist plan version \(decodedVersion). " +
                    "This Button Heist build supports version \(HeistPlan.currentVersion)."
            )
        }
        try decoder.rejectUnknownKeys(allowed: CodingKeys.self, typeName: "heist plan")
        version = decodedVersion
        name = try container.decodeIfPresent(String.self, forKey: .name)
        parameter = try container.decodeIfPresent(HeistParameter.self, forKey: .parameter) ?? .none
        definitions = try container.decodeIfPresent([HeistPlanAdmissionCandidate].self, forKey: .definitions) ?? []
        body = try container.decode([HeistStepAdmissionCandidate].self, forKey: .body)
        guard !body.isEmpty || !definitions.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .body,
                in: container,
                debugDescription: "HeistPlan requires a non-empty body or definitions"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(name, forKey: .name)
        if parameter != .none {
            try container.encode(parameter, forKey: .parameter)
        }
        if !definitions.isEmpty {
            try container.encode(definitions, forKey: .definitions)
        }
        try container.encode(body, forKey: .body)
    }

    public func validatedForRuntime(
        limits: HeistPlanRuntimeValidationLimits = .standard
    ) throws -> HeistPlan {
        try validatedForRuntimeSafety(limits: limits)
    }

    public func validatedForRuntimeSafety(
        limits: HeistPlanRuntimeSafetyLimits = .standard
    ) throws -> HeistPlan {
        var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
        return try validator.validate(self)
    }

    func uncheckedPlanForRuntimeValidation() -> HeistPlan {
        uncheckedPlanForRuntimeSafetyValidation()
    }

    func uncheckedPlanForRuntimeSafetyValidation() -> HeistPlan {
        HeistPlan(
            runtimeValidatedVersion: version,
            name: name,
            parameter: parameter,
            definitions: definitions.map { $0.uncheckedPlanForRuntimeSafetyValidation() },
            body: body.map(\.uncheckedStepForRuntimeSafetyValidation)
        )
    }
}

@_spi(ButtonHeistInternals) public typealias UnvalidatedHeistStep = HeistStepAdmissionCandidate

@_spi(ButtonHeistInternals) public enum HeistStepAdmissionCandidate: Codable, Sendable, Equatable {
    case action(ActionStep)
    case wait(WaitStep)
    case conditional(ConditionalStep)
    case waitForCases(WaitForCasesStep)
    case forEachElement(ForEachElementStep)
    case forEachString(ForEachStringStep)
    case warn(WarnStep)
    case fail(FailStep)
    indirect case heist(HeistPlanAdmissionCandidate)
    case invoke(HeistInvocationStep)

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case type, action, wait, conditional, waitForCases = "wait_for_cases"
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case warn, fail, heist, invoke
    }

    private enum StepType: String, Codable {
        case action
        case wait
        case conditional
        case waitForCases = "wait_for_cases"
        case forEachElement = "for_each_element"
        case forEachString = "for_each_string"
        case warn
        case fail
        case heist
        case invoke
    }

    init(_ step: HeistStep) {
        switch step {
        case .action(let step):
            self = .action(step)
        case .wait(let step):
            self = .wait(step)
        case .conditional(let step):
            self = .conditional(step)
        case .waitForCases(let step):
            self = .waitForCases(step)
        case .forEachElement(let step):
            self = .forEachElement(step)
        case .forEachString(let step):
            self = .forEachString(step)
        case .warn(let step):
            self = .warn(step)
        case .fail(let step):
            self = .fail(step)
        case .heist(let plan):
            self = .heist(UnvalidatedHeistPlan(plan))
        case .invoke(let step):
            self = .invoke(step)
        }
    }

    var uncheckedStepForRuntimeValidation: HeistStep {
        uncheckedStepForRuntimeSafetyValidation
    }

    var uncheckedStepForRuntimeSafetyValidation: HeistStep {
        switch self {
        case .action(let step):
            return .action(step)
        case .wait(let step):
            return .wait(step)
        case .conditional(let step):
            return .conditional(step)
        case .waitForCases(let step):
            return .waitForCases(step)
        case .forEachElement(let step):
            return .forEachElement(step)
        case .forEachString(let step):
            return .forEachString(step)
        case .warn(let step):
            return .warn(step)
        case .fail(let step):
            return .fail(step)
        case .heist(let plan):
            return .heist(plan.uncheckedPlanForRuntimeSafetyValidation())
        case .invoke(let step):
            return .invoke(step)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StepType.self, forKey: .type)
        switch type {
        case .action:
            try decoder.rejectUnknownKeys(allowed: ["type", "action"], typeName: "action heist step")
            self = .action(try container.decode(ActionStep.self, forKey: .action))
        case .wait:
            try decoder.rejectUnknownKeys(allowed: ["type", "wait"], typeName: "wait heist step")
            self = .wait(try container.decode(WaitStep.self, forKey: .wait))
        case .conditional:
            try decoder.rejectUnknownKeys(allowed: ["type", "conditional"], typeName: "conditional heist step")
            self = .conditional(try container.decode(ConditionalStep.self, forKey: .conditional))
        case .waitForCases:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.waitForCases.stringValue],
                typeName: "wait_for_cases heist step"
            )
            self = .waitForCases(try container.decode(WaitForCasesStep.self, forKey: .waitForCases))
        case .forEachElement:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEachElement.stringValue],
                typeName: "for_each_element heist step"
            )
            self = .forEachElement(try container.decode(ForEachElementStep.self, forKey: .forEachElement))
        case .forEachString:
            try decoder.rejectUnknownKeys(
                allowed: ["type", CodingKeys.forEachString.stringValue],
                typeName: "for_each_string heist step"
            )
            self = .forEachString(try container.decode(ForEachStringStep.self, forKey: .forEachString))
        case .warn:
            try decoder.rejectUnknownKeys(allowed: ["type", "warn"], typeName: "warn heist step")
            self = .warn(try container.decode(WarnStep.self, forKey: .warn))
        case .fail:
            try decoder.rejectUnknownKeys(allowed: ["type", "fail"], typeName: "fail heist step")
            self = .fail(try container.decode(FailStep.self, forKey: .fail))
        case .heist:
            try decoder.rejectUnknownKeys(allowed: ["type", "heist"], typeName: "heist group step")
            self = .heist(try container.decode(HeistPlanAdmissionCandidate.self, forKey: .heist))
        case .invoke:
            try decoder.rejectUnknownKeys(allowed: ["type", "invoke"], typeName: "invoke heist step")
            self = .invoke(try container.decode(HeistInvocationStep.self, forKey: .invoke))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .action(let step):
            try container.encode(StepType.action, forKey: .type)
            try container.encode(step, forKey: .action)
        case .wait(let step):
            try container.encode(StepType.wait, forKey: .type)
            try container.encode(step, forKey: .wait)
        case .conditional(let step):
            try container.encode(StepType.conditional, forKey: .type)
            try container.encode(step, forKey: .conditional)
        case .waitForCases(let step):
            try container.encode(StepType.waitForCases, forKey: .type)
            try container.encode(step, forKey: .waitForCases)
        case .forEachElement(let step):
            try container.encode(StepType.forEachElement, forKey: .type)
            try container.encode(step, forKey: .forEachElement)
        case .forEachString(let step):
            try container.encode(StepType.forEachString, forKey: .type)
            try container.encode(step, forKey: .forEachString)
        case .warn(let step):
            try container.encode(StepType.warn, forKey: .type)
            try container.encode(step, forKey: .warn)
        case .fail(let step):
            try container.encode(StepType.fail, forKey: .type)
            try container.encode(step, forKey: .fail)
        case .heist(let plan):
            try container.encode(StepType.heist, forKey: .type)
            try container.encode(plan, forKey: .heist)
        case .invoke(let step):
            try container.encode(StepType.invoke, forKey: .type)
            try container.encode(step, forKey: .invoke)
        }
    }
}

@_spi(ButtonHeistInternals) public typealias HeistPlanRuntimeValidationLimits = HeistPlanRuntimeSafetyLimits

@_spi(ButtonHeistInternals) public struct HeistPlanRuntimeSafetyLimits: Sendable, Equatable {
    public static let standard = HeistPlanRuntimeSafetyLimits()

    public let maxTotalSteps: Int
    public let maxNestedStepDepth: Int
    public let maxPredicateDepth: Int
    public let maxAllPredicateChildren: Int
    public let maxForEachStringValues: Int
    public let maxForEachElementLimit: Int
    public let maxStringBytes: Int
    public let maxTotalStringBytes: Int
    public let maxParameterBytes: Int

    public init(
        maxTotalSteps: Int = 500,
        maxNestedStepDepth: Int = 16,
        maxPredicateDepth: Int = 12,
        maxAllPredicateChildren: Int = 20,
        maxForEachStringValues: Int = 100,
        maxForEachElementLimit: Int = 100,
        maxStringBytes: Int = 4_096,
        maxTotalStringBytes: Int = 65_536,
        maxParameterBytes: Int = 64
    ) {
        self.maxTotalSteps = maxTotalSteps
        self.maxNestedStepDepth = maxNestedStepDepth
        self.maxPredicateDepth = maxPredicateDepth
        self.maxAllPredicateChildren = maxAllPredicateChildren
        self.maxForEachStringValues = maxForEachStringValues
        self.maxForEachElementLimit = maxForEachElementLimit
        self.maxStringBytes = maxStringBytes
        self.maxTotalStringBytes = maxTotalStringBytes
        self.maxParameterBytes = maxParameterBytes
    }
}

@_spi(ButtonHeistInternals) public typealias HeistPlanValidationFailure = HeistPlanRuntimeSafetyFailure

@_spi(ButtonHeistInternals) public struct HeistPlanRuntimeSafetyFailure: Sendable, Equatable, CustomStringConvertible {
    public let path: String
    public let contract: String
    public let observed: String
    public let correction: String

    public init(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        self.path = path
        self.contract = contract
        self.observed = observed
        self.correction = correction
    }

    public var description: String {
        "\(path): \(contract); observed \(observed); \(correction)"
    }
}

@_spi(ButtonHeistInternals) public typealias HeistPlanValidationError = HeistPlanRuntimeSafetyError

@_spi(ButtonHeistInternals) public struct HeistPlanRuntimeSafetyError: Error, Sendable, Equatable, CustomStringConvertible {
    public let failures: [HeistPlanRuntimeSafetyFailure]

    public init(failures: [HeistPlanRuntimeSafetyFailure]) {
        self.failures = failures
    }

    public var description: String {
        guard let first = failures.first else { return "heist plan runtime safety validation failed" }
        let suffix = failures.count > 1 ? " (+\(failures.count - 1) more)" : ""
        return "heist plan runtime safety validation failed: \(first)\(suffix)"
    }
}

// RuntimeSafety owns the bounded executable-plan boundary: finite traversal,
// non-recursive local heist references, scoped refs, safe control flow, and
// payloads that lower to runtime command contracts.
struct HeistPlanRuntimeSafetyValidator: HeistPlanTraversalVisitor {
    let limits: HeistPlanRuntimeSafetyLimits

    var failures: [HeistPlanRuntimeSafetyFailure] = []
    var stepCount = 0
    var totalStringBytes = 0
    var reportedStepLimit = false
    var reportedTotalStringLimit = false

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(limits: HeistPlanRuntimeSafetyLimits) {
        self.limits = limits
    }

    mutating func validate(_ raw: HeistPlanAdmissionCandidate) throws -> HeistPlan {
        let plan = raw.uncheckedPlanForRuntimeSafetyValidation()
        let failures = failures(in: plan)
        guard failures.isEmpty else { throw HeistPlanRuntimeSafetyError(failures: failures) }
        return plan
    }

    mutating func failures(in plan: HeistPlan) -> [HeistPlanRuntimeSafetyFailure] {
        let traversal = HeistPlanTraversal()
        traversal.walk(plan, visitor: &self)
        return failures
    }

    mutating func visitPlan(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: false)
    }

    mutating func visitDefinitions(_ definitions: [HeistPlan], context: HeistTraversalContext) {
        validateDefinitions(definitions, path: context.path)
    }

    mutating func visitDefinition(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: true)
    }

    mutating func visitStep(
        _ step: HeistStep,
        context: HeistTraversalContext
    ) {
        stepCount += 1
        if stepCount > limits.maxTotalSteps, !reportedStepLimit {
            reportedStepLimit = true
            fail(
                path: context.path,
                contract: "max total heist steps",
                observed: "\(stepCount) steps",
                correction: "Use \(limits.maxTotalSteps) steps or fewer."
            )
        }
        if context.depth > limits.maxNestedStepDepth {
            fail(
                path: context.path,
                contract: "max nested step depth",
                observed: "depth \(context.depth)",
                correction: "Flatten this heist to depth \(limits.maxNestedStepDepth) or less."
            )
        }
    }

    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {
        validateAction(
            action,
            path: context.path,
            scope: context.scope,
            environment: context.environment
        )
    }

    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {
        validateWait(wait, path: context.path, scope: context.scope, environment: context.environment)
    }

    mutating func visitWaitForCases(_ waitForCases: WaitForCasesStep, context: HeistTraversalContext) {
        validateWaitForCases(waitForCases, path: context.path)
    }

    mutating func visitPredicateCase(_ predicateCase: PredicateCase, context: HeistTraversalContext) {
        validatePredicateCase(
            predicateCase,
            path: context.path,
            scope: context.scope,
            environment: context.environment
        )
    }

    mutating func visitForEachElement(_ step: ForEachElementStep, context: HeistTraversalContext) {
        validateForEachElement(step, path: context.path, allowsCollectionLoops: context.allowsCollectionLoops)
    }

    mutating func visitForEachString(_ step: ForEachStringStep, context: HeistTraversalContext) {
        validateForEachString(
            step,
            path: context.path,
            bodyDepth: context.depth + 1,
            scope: context.scope,
            environment: context.environment,
            definitionScope: context.definitionScope,
            allowsCollectionLoops: context.allowsCollectionLoops
        )
    }

    mutating func visitWarn(_ warn: WarnStep, context: HeistTraversalContext) {
        addString(warn.message, path: "\(context.path).message", role: "warn message")
    }

    mutating func visitFail(_ fail: FailStep, context: HeistTraversalContext) {
        addString(fail.message, path: "\(context.path).message", role: "fail message")
    }

    mutating func visitHeist(_ plan: HeistPlan, context: HeistTraversalContext) {
        validatePlanHeader(plan, path: context.path, requiresName: false)
        if plan.parameter != .none {
            fail(
                path: "\(context.path).parameter",
                contract: "inline heist group must not declare a parameter",
                observed: plan.parameter.kind.rawValue,
                correction: "Use RunHeist with a named capability when a heist needs an argument."
            )
        }
    }

    mutating func visitInvoke(_ step: HeistInvocationStep, context: HeistTraversalContext) {
        validateInvocation(step, context: context)
    }

    mutating func validatePlanHeader(
        _ plan: HeistPlan,
        path: String,
        requiresName: Bool
    ) {
        if requiresName {
            guard let name = plan.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                fail(
                    path: "\(path).name",
                    contract: "heist definitions must have a non-empty name",
                    observed: "missing name",
                    correction: "Name every heist in a definitions array."
                )
                return
            }
        }
        if let name = plan.name {
            validateParameter(name, path: "\(path).name", role: "heist definition name")
        }
        validateParameterDeclaration(plan.parameter, path: "\(path).parameter")
        if plan.body.isEmpty, plan.definitions.isEmpty {
            fail(
                path: "\(path).body",
                contract: "heist plan must contain a body or nested definitions",
                observed: "empty heist",
                correction: "Add body steps, or use this plan only as a namespace with nested definitions."
            )
        }
    }

    mutating func validateDefinitions(_ definitions: [HeistPlan], path: String) {
        var seen: Set<String> = []
        for (index, definition) in definitions.enumerated() {
            guard let name = definition.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            if seen.contains(name) {
                fail(
                    path: "\(path)[\(index)].name",
                    contract: "duplicate heist definition names are not allowed in the same scope",
                    observed: "\"\(escaped(name))\"",
                    correction: "Rename one definition or put it in a different namespace."
                )
            }
            seen.insert(name)
        }
    }

    mutating func validateParameterDeclaration(_ parameter: HeistParameter, path: String) {
        guard let name = parameter.name else { return }
        validateParameter(name, path: "\(path).name", role: "\(parameter.kind.rawValue) parameter")
    }

    mutating func validateInvocation(_ step: HeistInvocationStep, context: HeistTraversalContext) {
        guard !step.path.isEmpty else {
            fail(
                path: "\(context.path).path",
                contract: "heist run path must not be empty",
                observed: "empty path",
                correction: "Run a named local capability."
            )
            return
        }
        for (index, component) in step.path.enumerated() {
            validateParameter(component, path: "\(context.path).path[\(index)]", role: "heist run path component")
        }
        validateArgument(step.argument, path: "\(context.path).argument", scope: context.scope)
        guard let resolved = context.definitionScope.resolve(path: step.path) else {
            fail(
                path: "\(context.path).path",
                contract: "heist run path must resolve to a local capability",
                observed: step.path.joined(separator: "."),
                correction: "Define this heist in the current scope or qualify it through an exported namespace."
            )
            return
        }
        let resolvedName = resolved.qualifiedName
        if context.invocationStack.contains(resolvedName) {
            fail(
                path: "\(context.path).path",
                contract: "heist runs must not be recursive",
                observed: (context.invocationStack + [resolvedName]).joined(separator: " -> "),
                correction: "Remove the recursive heist run cycle."
            )
            return
        }
        guard step.argument.kind == resolved.definition.parameter.kind else {
            fail(
                path: "\(context.path).argument",
                contract: "heist run argument type must match the target parameter",
                observed: "\(step.argument.kind.rawValue) for \(resolved.definition.parameter.kind.rawValue)",
                correction: "Pass the argument shape declared by the named capability."
            )
            return
        }
        do {
            _ = try context.environment.binding(argument: step.argument, to: resolved.definition.parameter)
        } catch {
            fail(
                path: "\(context.path).argument",
                contract: "heist run argument must bind to the target parameter",
                observed: summarize(error),
                correction: "Use a finite semantic value matching the named capability parameter."
            )
        }
    }

    mutating func validateArgument(_ argument: HeistArgument, path: String, scope: HeistReferenceScope) {
        switch argument {
        case .none:
            break
        case .string(let value):
            validateString(value, path: "\(path).value", scope: scope)
        case .elementTarget(let target):
            validateTarget(target, path: "\(path).target", scope: scope)
        }
    }

    mutating func validateAction(
        _ action: ActionStep,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommand(action.command, path: "\(path).command", scope: scope, environment: environment)
        if let waiver = action.expectationWaiver {
            addString(waiver, path: "\(path).without_expectation", role: "expectation waiver")
        }
        if let failure = action.expectationValidationFailure {
            fail(
                path: "\(path).expectation",
                contract: "action expectation composition must be supported and unambiguous",
                observed: failure,
                correction: "Use one change predicate plus optional state predicates, or split unrelated waits into explicit WaitFor steps."
            )
        }
    }

    mutating func validateCommand(
        _ command: HeistActionCommand,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommandExpressions(command, path: path, scope: scope)
        // Durability (serialize/render canonically) is an authoring concern, not
        // an execution one. It is enforced where heists are persisted or rendered
        // as canonical Swift DSL — not here, so a transient plan (a
        // single command or an inline run_heist) can execute any valid command,
        // including viewport commands. This keeps single-step and heist execution
        // on one pipeline; viewport commands still never enter the authored DSL.
        do {
            try command.assertResolvedPayloadAdmissible(in: environment)
        } catch {
            fail(
                path: path,
                contract: "resolved command payload must satisfy the heist action payload contract",
                observed: summarize(error),
                correction: "Use values and refs that lower to a valid \(command.wireType.rawValue) command payload."
            )
        }
    }

    mutating func validateWait(
        _ wait: WaitStep,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(wait.predicate, path: "\(path).predicate", depth: 1, scope: scope)
        guard wait.timeout >= 0 else {
            fail(
                path: "\(path).timeout",
                contract: "wait timeout must be non-negative",
                observed: "\(wait.timeout)",
                correction: "Use a timeout of 0 or more seconds."
            )
            return
        }
        do {
            let resolved = try wait.resolve(in: environment)
            try validateResolvedPayloadContract(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout))
        } catch {
            fail(
                path: path,
                contract: "resolved wait predicate must satisfy the heist wait payload contract",
                observed: summarize(error),
                correction: "Use scoped refs and predicate values that lower to a valid wait command."
            )
        }
    }

    mutating func validateWaitForCases(
        _ waitForCases: WaitForCasesStep,
        path: String
    ) {
        guard waitForCases.timeout >= 0 else {
            fail(
                path: "\(path).timeout",
                contract: "wait_for_cases timeout must be non-negative",
                observed: "\(waitForCases.timeout)",
                correction: "Use a timeout of 0 or more seconds."
            )
            return
        }
    }

    mutating func validatePredicateCase(
        _ predicateCase: PredicateCase,
        path: String,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment
    ) {
        validatePredicate(predicateCase.predicate, path: "\(path).predicate", depth: 1, scope: scope)
        do {
            _ = try predicateCase.predicate.resolve(in: environment)
        } catch {
            fail(
                path: "\(path).predicate",
                contract: "predicate refs must resolve in the current heist scope",
                observed: summarize(error),
                correction: "Use target_ref or string refs only inside the loop body that defines them."
            )
        }
    }

    mutating func validateForEachElement(
        _ step: ForEachElementStep,
        path: String,
        allowsCollectionLoops: Bool
    ) {
        guard allowsCollectionLoops else {
            fail(
                path: path,
                contract: "collection ForEach steps are top-level only",
                observed: "nested for_each_element",
                correction: "Move this collection loop to the top-level heist steps."
            )
            return
        }
        validateElementPredicate(step.matching, path: "\(path).matching")
        validateParameter(step.parameter, path: "\(path).parameter", role: "for_each_element parameter")
        if step.limit > limits.maxForEachElementLimit {
            fail(
                path: "\(path).limit",
                contract: "max for_each_element limit",
                observed: "\(step.limit)",
                correction: "Use a limit of \(limits.maxForEachElementLimit) or less."
            )
        }
    }

    mutating func validateForEachString(
        _ step: ForEachStringStep,
        path: String,
        bodyDepth: Int,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment,
        definitionScope: HeistDefinitionScope,
        allowsCollectionLoops: Bool
    ) {
        guard allowsCollectionLoops else {
            fail(
                path: path,
                contract: "collection ForEach steps are top-level only",
                observed: "nested for_each_string",
                correction: "Move this collection loop to the top-level heist steps."
            )
            return
        }
        validateParameter(step.parameter, path: "\(path).parameter", role: "for_each_string parameter")
        if step.values.count > limits.maxForEachStringValues {
            fail(
                path: "\(path).values",
                contract: "max for_each_string values",
                observed: "\(step.values.count) values",
                correction: "Use \(limits.maxForEachStringValues) values or fewer."
            )
        }
        for (index, value) in step.values.enumerated() {
            addString(value, path: "\(path).values[\(index)]", role: "for_each_string value")
        }

        for (index, value) in step.values.enumerated() {
            validateResolvedStringLoopPayloads(
                step.body,
                path: "\(path).body",
                depth: bodyDepth,
                scope: scope.bindingString(step.parameter),
                environment: environment.binding(string: value, to: step.parameter),
                definitionScope: definitionScope,
                valuePath: "\(path).values[\(index)]"
            )
        }
    }

    mutating func validateResolvedStringLoopPayloads(
        _ steps: [HeistStep],
        path: String,
        depth: Int,
        scope: HeistReferenceScope,
        environment: HeistExecutionEnvironment,
        definitionScope: HeistDefinitionScope,
        valuePath: String
    ) {
        var validator = StringLoopResolvedPayloadValidator(valuePath: valuePath)
        let traversal = HeistPlanTraversal()
        traversal.walk(
            steps: steps,
            path: path,
            depth: depth,
            allowsCollectionLoops: false,
            scope: scope,
            environment: environment,
            definitionScope: definitionScope,
            visitor: &validator
        )
        failures += validator.failures
    }

    func validateResolvedPayloadContract<T: Codable>(_ payload: T) throws {
        let data = try encoder.encode(payload)
        _ = try decoder.decode(T.self, from: data)
    }

    mutating func fail(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        failures.append(HeistPlanRuntimeSafetyFailure(
            path: path,
            contract: contract,
            observed: observed,
            correction: correction
        ))
    }

    func summarize(_ error: Error) -> String {
        let text = String(describing: error)
        guard text.count > 220 else { return text }
        return "\(text.prefix(217))..."
    }

    func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "\\0")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

private struct StringLoopResolvedPayloadValidator: HeistPlanTraversalVisitor {
    let valuePath: String

    var failures: [HeistPlanRuntimeSafetyFailure] = []

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    mutating func visitAction(_ action: ActionStep, context: HeistTraversalContext) {
        do {
            try action.command.assertResolvedPayloadAdmissible(in: context.environment)
        } catch {
            fail(
                path: context.path,
                contract: "string loop value must lower through the heist action payload contract",
                observed: "\(valuePath) resolved to \(summarize(error))",
                correction: "Use loop string values that keep every referenced command payload valid."
            )
        }
    }

    mutating func visitWait(_ wait: WaitStep, context: HeistTraversalContext) {
        do {
            let resolved = try wait.resolve(in: context.environment)
            try validateResolvedPayloadContract(WaitTarget(
                predicate: resolved.predicate,
                timeout: resolved.timeout
            ))
        } catch {
            fail(
                path: context.path,
                contract: "string loop value must resolve wait predicates",
                observed: "\(valuePath) resolved to \(summarize(error))",
                correction: "Use loop string values that keep every referenced wait predicate valid."
            )
        }
    }

    func validateResolvedPayloadContract<T: Codable>(_ payload: T) throws {
        let data = try encoder.encode(payload)
        _ = try decoder.decode(T.self, from: data)
    }

    mutating func fail(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        failures.append(HeistPlanRuntimeSafetyFailure(
            path: path,
            contract: contract,
            observed: observed,
            correction: correction
        ))
    }

    func summarize(_ error: Error) -> String {
        let text = String(describing: error)
        guard text.count > 220 else { return text }
        return "\(text.prefix(217))..."
    }
}

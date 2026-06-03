import Foundation

public struct HeistPlanRuntimeAdmissionLimits: Sendable, Equatable {
    public static let standard = HeistPlanRuntimeAdmissionLimits()

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

public struct HeistPlanAdmissionFailure: Sendable, Equatable, CustomStringConvertible {
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

public struct HeistPlanAdmissionError: Error, Sendable, Equatable, CustomStringConvertible {
    public let failures: [HeistPlanAdmissionFailure]

    public init(failures: [HeistPlanAdmissionFailure]) {
        self.failures = failures
    }

    public var description: String {
        guard let first = failures.first else { return "heist plan admission failed" }
        let suffix = failures.count > 1 ? " (+\(failures.count - 1) more)" : ""
        return "heist plan admission failed: \(first)\(suffix)"
    }
}

public extension HeistPlan {
    func runtimeAdmissionFailures(
        limits: HeistPlanRuntimeAdmissionLimits = .standard
    ) -> [HeistPlanAdmissionFailure] {
        var validator = HeistPlanRuntimeAdmissionValidator(limits: limits)
        return validator.validate(self)
    }

    func assertRuntimeAdmissible(
        limits: HeistPlanRuntimeAdmissionLimits = .standard
    ) throws {
        let failures = runtimeAdmissionFailures(limits: limits)
        guard failures.isEmpty else { throw HeistPlanAdmissionError(failures: failures) }
    }
}

struct HeistPlanRuntimeAdmissionValidator {
    let limits: HeistPlanRuntimeAdmissionLimits

    var failures: [HeistPlanAdmissionFailure] = []
    var stepCount = 0
    var totalStringBytes = 0
    var reportedStepLimit = false
    var reportedTotalStringLimit = false

    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(limits: HeistPlanRuntimeAdmissionLimits) {
        self.limits = limits
    }

    mutating func validate(_ plan: HeistPlan) -> [HeistPlanAdmissionFailure] {
        validateSteps(
            plan.steps,
            path: "$.steps",
            depth: 1,
            scope: .empty,
            environment: .empty,
            allowsCollectionLoops: true
        )
        return failures
    }

    mutating func validateSteps(
        _ steps: [HeistStep],
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment,
        allowsCollectionLoops: Bool
    ) {
        for (index, step) in steps.enumerated() {
            validateStep(
                step,
                path: "\(path)[\(index)]",
                depth: depth,
                scope: scope,
                environment: environment,
                allowsCollectionLoops: allowsCollectionLoops
            )
        }
    }

    mutating func validateStep(
        _ step: HeistStep,
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment,
        allowsCollectionLoops: Bool
    ) {
        stepCount += 1
        if stepCount > limits.maxTotalSteps, !reportedStepLimit {
            reportedStepLimit = true
            fail(
                path: path,
                contract: "max total heist steps",
                observed: "\(stepCount) steps",
                correction: "Use \(limits.maxTotalSteps) steps or fewer."
            )
        }
        if depth > limits.maxNestedStepDepth {
            fail(
                path: path,
                contract: "max nested step depth",
                observed: "depth \(depth)",
                correction: "Flatten this heist to depth \(limits.maxNestedStepDepth) or less."
            )
        }

        switch step {
        case .action(let action):
            validateAction(action, path: "\(path).action", scope: scope, environment: environment)
        case .wait(let wait):
            validateWait(wait, path: "\(path).wait", scope: scope, environment: environment)
        case .conditional(let conditional):
            validateConditional(
                conditional,
                path: "\(path).conditional",
                depth: depth,
                scope: scope,
                environment: environment
            )
        case .waitForCases(let waitForCases):
            validateWaitForCases(
                waitForCases,
                path: "\(path).wait_for_cases",
                depth: depth,
                scope: scope,
                environment: environment
            )
        case .forEachElement(let forEach):
            validateForEachElement(
                forEach,
                path: "\(path).for_each_element",
                depth: depth,
                scope: scope,
                environment: environment,
                allowsCollectionLoops: allowsCollectionLoops
            )
        case .forEachString(let forEach):
            validateForEachString(
                forEach,
                path: "\(path).for_each_string",
                depth: depth,
                scope: scope,
                environment: environment,
                allowsCollectionLoops: allowsCollectionLoops
            )
        case .warn(let warn):
            addString(warn.message, path: "\(path).warn.message", role: "warn message")
        case .fail(let fail):
            addString(fail.message, path: "\(path).fail.message", role: "fail message")
        }
    }

    mutating func validateAction(
        _ action: ActionStep,
        path: String,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommand(action.command, path: "\(path).command", scope: scope, environment: environment)
        if let expectation = action.expectation {
            validateWait(expectation, path: "\(path).expectation", scope: scope, environment: environment)
        }
        if let waiver = action.expectationWaiver {
            addString(waiver, path: "\(path).without_expectation", role: "expectation waiver")
        }
    }

    mutating func validateCommand(
        _ command: HeistActionCommand,
        path: String,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommandExpressions(command, path: path, scope: scope)
        if let failure = command.durableHeistActionFailure {
            fail(
                path: path,
                contract: "durable heist action support",
                observed: failure,
                correction: "Use a heist action shape that can execute, serialize, and render canonically."
            )
        }

        do {
            let message = try command.resolve(in: environment)
            try validateDirectCommandContract(message)
        } catch {
            fail(
                path: path,
                contract: "resolved command payload must satisfy the direct Fence command contract",
                observed: summarize(error),
                correction: "Use values and refs that lower to a valid \(command.wireType.rawValue) command payload."
            )
        }
    }

    mutating func validateWait(
        _ wait: WaitStep,
        path: String,
        scope: AdmissionScope,
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
            try validateDirectCommandContract(.wait(WaitTarget(predicate: resolved.predicate, timeout: resolved.timeout)))
        } catch {
            fail(
                path: path,
                contract: "resolved wait predicate must satisfy the direct Fence wait contract",
                observed: summarize(error),
                correction: "Use scoped refs and predicate values that lower to a valid wait command."
            )
        }
    }

    mutating func validateConditional(
        _ conditional: ConditionalStep,
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment
    ) {
        for (index, predicateCase) in conditional.cases.enumerated() {
            validatePredicateCase(
                predicateCase,
                path: "\(path).cases[\(index)]",
                depth: depth,
                scope: scope,
                environment: environment
            )
        }
        if let elseSteps = conditional.elseSteps {
            validateSteps(
                elseSteps,
                path: "\(path).else_steps",
                depth: depth + 1,
                scope: scope,
                environment: environment,
                allowsCollectionLoops: false
            )
        }
    }

    mutating func validateWaitForCases(
        _ waitForCases: WaitForCasesStep,
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment
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
        for (index, predicateCase) in waitForCases.cases.enumerated() {
            validatePredicateCase(
                predicateCase,
                path: "\(path).cases[\(index)]",
                depth: depth,
                scope: scope,
                environment: environment
            )
        }
        if let elseSteps = waitForCases.elseSteps {
            validateSteps(
                elseSteps,
                path: "\(path).else_steps",
                depth: depth + 1,
                scope: scope,
                environment: environment,
                allowsCollectionLoops: false
            )
        }
    }

    mutating func validatePredicateCase(
        _ predicateCase: PredicateCase,
        path: String,
        depth: Int,
        scope: AdmissionScope,
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
        validateSteps(
            predicateCase.steps,
            path: "\(path).steps",
            depth: depth + 1,
            scope: scope,
            environment: environment,
            allowsCollectionLoops: false
        )
    }

    mutating func validateForEachElement(
        _ step: ForEachElementStep,
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment,
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

        let childScope = scope.bindingTarget(step.parameter)
        let childEnvironment = environment.binding(
            target: .predicate(step.matching),
            to: step.parameter
        )
        validateSteps(
            step.steps,
            path: "\(path).steps",
            depth: depth + 1,
            scope: childScope,
            environment: childEnvironment,
            allowsCollectionLoops: false
        )
    }

    mutating func validateForEachString(
        _ step: ForEachStringStep,
        path: String,
        depth: Int,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment,
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

        let childScope = scope.bindingString(step.parameter)
        let sampleEnvironment = environment.binding(string: step.values.first ?? "", to: step.parameter)
        validateSteps(
            step.steps,
            path: "\(path).steps",
            depth: depth + 1,
            scope: childScope,
            environment: sampleEnvironment,
            allowsCollectionLoops: false
        )

        for (index, value) in step.values.enumerated() {
            validateResolvedPayloads(
                step.steps,
                path: "\(path).steps",
                environment: environment.binding(string: value, to: step.parameter),
                valuePath: "\(path).values[\(index)]"
            )
        }
    }

    mutating func validateResolvedPayloads(
        _ steps: [HeistStep],
        path: String,
        environment: HeistExecutionEnvironment,
        valuePath: String
    ) {
        for (index, step) in steps.enumerated() {
            let stepPath = "\(path)[\(index)]"
            switch step {
            case .action(let action):
                do {
                    let command = try action.command.resolve(in: environment)
                    try validateDirectCommandContract(command)
                    if let expectation = action.expectation {
                        _ = try expectation.resolve(in: environment)
                    }
                } catch {
                    fail(
                        path: stepPath,
                        contract: "string loop value must lower through the direct command contract",
                        observed: "\(valuePath) resolved to \(summarize(error))",
                        correction: "Use loop string values that keep every referenced command payload valid."
                    )
                }
            case .wait(let wait):
                do {
                    _ = try wait.resolve(in: environment)
                } catch {
                    fail(
                        path: stepPath,
                        contract: "string loop value must resolve wait predicates",
                        observed: "\(valuePath) resolved to \(summarize(error))",
                        correction: "Use loop string values that keep every referenced wait predicate valid."
                    )
                }
            case .conditional(let conditional):
                validateResolvedPayloads(
                    conditional.cases.flatMap(\.steps),
                    path: "\(stepPath).conditional.cases.steps",
                    environment: environment,
                    valuePath: valuePath
                )
                if let elseSteps = conditional.elseSteps {
                    validateResolvedPayloads(
                        elseSteps,
                        path: "\(stepPath).conditional.else_steps",
                        environment: environment,
                        valuePath: valuePath
                    )
                }
            case .waitForCases(let waitForCases):
                validateResolvedPayloads(
                    waitForCases.cases.flatMap(\.steps),
                    path: "\(stepPath).wait_for_cases.cases.steps",
                    environment: environment,
                    valuePath: valuePath
                )
                if let elseSteps = waitForCases.elseSteps {
                    validateResolvedPayloads(
                        elseSteps,
                        path: "\(stepPath).wait_for_cases.else_steps",
                        environment: environment,
                        valuePath: valuePath
                    )
                }
            case .forEachElement, .forEachString, .warn, .fail:
                break
            }
        }
    }

    func validateDirectCommandContract(_ message: ClientMessage) throws {
        let data = try encoder.encode(message)
        _ = try decoder.decode(ClientMessage.self, from: data)
    }

    mutating func fail(
        path: String,
        contract: String,
        observed: String,
        correction: String
    ) {
        failures.append(HeistPlanAdmissionFailure(
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

struct AdmissionScope {
    static let empty = AdmissionScope()

    var targetRefs: Set<String> = []
    var stringRefs: Set<String> = []

    func bindingTarget(_ reference: String) -> AdmissionScope {
        var copy = self
        copy.targetRefs.insert(reference)
        return copy
    }

    func bindingString(_ reference: String) -> AdmissionScope {
        var copy = self
        copy.stringRefs.insert(reference)
        return copy
    }
}

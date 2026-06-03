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

private struct HeistPlanRuntimeAdmissionValidator {
    let limits: HeistPlanRuntimeAdmissionLimits

    private var failures: [HeistPlanAdmissionFailure] = []
    private var stepCount = 0
    private var totalStringBytes = 0
    private var reportedStepLimit = false
    private var reportedTotalStringLimit = false

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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

    private mutating func validateSteps(
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

    private mutating func validateStep(
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

    private mutating func validateAction(
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

    private mutating func validateCommand(
        _ command: HeistActionCommand,
        path: String,
        scope: AdmissionScope,
        environment: HeistExecutionEnvironment
    ) {
        validateCommandExpressions(command, path: path, scope: scope)
        validateCanonicalRenderability(command, path: path)

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

    private mutating func validateWait(
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

    private mutating func validateConditional(
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

    private mutating func validateWaitForCases(
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

    private mutating func validatePredicateCase(
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

    private mutating func validateForEachElement(
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

    private mutating func validateForEachString(
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

    private mutating func validateResolvedPayloads(
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

    private mutating func validatePredicate(
        _ predicate: AccessibilityPredicateExpr,
        path: String,
        depth: Int,
        scope: AdmissionScope
    ) {
        switch predicate {
        case .predicate(let predicate):
            validatePredicate(predicate, path: path, depth: depth)
        case .state(let state):
            validateStatePredicate(state, path: path, depth: depth, scope: scope)
        }
    }

    private mutating func validatePredicate(
        _ predicate: AccessibilityPredicate,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch predicate {
        case .state(let state):
            validateStatePredicate(state, path: path, depth: depth)
        case .changed(let change):
            switch change {
            case .screen(let state):
                if let state {
                    validateStatePredicate(state, path: "\(path).where", depth: depth + 1)
                }
            case .appeared(let predicate), .disappeared(let predicate):
                validateElementPredicate(predicate, path: "\(path).element")
            case .updated(let update):
                if let element = update.element {
                    validateElementPredicate(element, path: "\(path).element")
                }
                addString(update.from, path: "\(path).from", role: "change predicate from value")
                addString(update.to, path: "\(path).to", role: "change predicate to value")
            case .elements:
                break
            }
        }
    }

    private mutating func validateStatePredicate(
        _ state: AccessibilityPredicate.State,
        path: String,
        depth: Int
    ) {
        checkPredicateDepth(depth, path: path)
        switch state {
        case .present(let predicate), .absent(let predicate):
            validateElementPredicate(predicate, path: "\(path).element")
        case .presentTarget(let target), .absentTarget(let target):
            validateElementTarget(target, path: "\(path).target")
        case .all(let states):
            validateAllChildCount(states.count, path: "\(path).states")
            for (index, child) in states.enumerated() {
                validateStatePredicate(child, path: "\(path).states[\(index)]", depth: depth + 1)
            }
        }
    }

    private mutating func validateStatePredicate(
        _ state: StatePredicateExpr,
        path: String,
        depth: Int,
        scope: AdmissionScope
    ) {
        checkPredicateDepth(depth, path: path)
        switch state {
        case .present(let predicate), .absent(let predicate):
            validateElementPredicate(predicate, path: "\(path).element", scope: scope)
        case .presentTarget(let target), .absentTarget(let target):
            validateTarget(target, path: "\(path).target", scope: scope)
        case .all(let states):
            validateAllChildCount(states.count, path: "\(path).states")
            for (index, child) in states.enumerated() {
                validateStatePredicate(child, path: "\(path).states[\(index)]", depth: depth + 1, scope: scope)
            }
        }
    }

    private mutating func checkPredicateDepth(_ depth: Int, path: String) {
        if depth > limits.maxPredicateDepth {
            fail(
                path: path,
                contract: "max predicate depth",
                observed: "depth \(depth)",
                correction: "Use predicates nested \(limits.maxPredicateDepth) levels or fewer."
            )
        }
    }

    private mutating func validateAllChildCount(_ count: Int, path: String) {
        if count > limits.maxAllPredicateChildren {
            fail(
                path: path,
                contract: "max .all child count",
                observed: "\(count) children",
                correction: "Use \(limits.maxAllPredicateChildren) child predicates or fewer."
            )
        }
    }

    private mutating func validateCommandExpressions(
        _ command: HeistActionCommand,
        path: String,
        scope: AdmissionScope
    ) {
        switch command {
        case .activate(let target), .increment(let target), .decrement(let target), .viewportScrollToVisible(let target):
            validateTarget(target, path: "\(path).payload.target", scope: scope)
        case .customAction(let name, let target):
            addString(name, path: "\(path).payload.actionName", role: "custom action name")
            validateTarget(target, path: "\(path).payload.target", scope: scope)
        case .rotor(let selection, let target, _):
            if case .named(let name) = selection {
                addString(name, path: "\(path).payload.rotor", role: "rotor name")
            }
            validateTarget(target, path: "\(path).payload.target", scope: scope)
        case .typeText(let text, let target):
            validateString(text, path: "\(path).payload.text", scope: scope)
            if let target {
                validateTarget(target, path: "\(path).payload.target", scope: scope)
            }
        case .mechanicalTap(let target):
            validateGesturePointSelection(target.selection, path: "\(path).payload", scope: scope)
        case .mechanicalLongPress(let target):
            validateGesturePointSelection(target.selection, path: "\(path).payload", scope: scope)
        case .mechanicalSwipe(let target):
            validateSwipe(target, path: "\(path).payload", scope: scope)
        case .mechanicalDrag(let target):
            validateDrag(target, path: "\(path).payload", scope: scope)
        case .viewportScroll(let target):
            validateScroll(target.selection, path: "\(path).payload", scope: scope)
        case .viewportScrollToEdge(let target):
            validateScroll(target.selection, path: "\(path).payload", scope: scope)
        case .setPasteboard(let target):
            addString(target.text, path: "\(path).payload.text", role: "pasteboard text")
            if target.text.isEmpty {
                fail(
                    path: "\(path).payload.text",
                    contract: "set_pasteboard text must be non-empty",
                    observed: "empty string",
                    correction: "Use non-empty text for SetPasteboard."
                )
            }
        case .editAction, .dismissKeyboard:
            break
        }
    }

    private mutating func validateGesturePointSelection(
        _ selection: GesturePointSelection,
        path: String,
        scope: AdmissionScope
    ) {
        if case .element(let target) = selection {
            validateElementTarget(target, path: "\(path).element")
        }
    }

    private mutating func validateSwipe(
        _ target: SwipeTarget,
        path: String,
        scope: AdmissionScope
    ) {
        switch target.selection {
        case .unitElement(let target, _, _), .elementDirection(let target, _):
            validateElementTarget(target, path: "\(path).element")
        case .point(let start, _):
            validateGesturePointSelection(start, path: "\(path).start", scope: scope)
        }
    }

    private mutating func validateDrag(
        _ target: DragTarget,
        path: String,
        scope: AdmissionScope
    ) {
        switch target.selection {
        case .elementToPoint(let target, _):
            validateElementTarget(target, path: "\(path).element")
        case .pointToPoint:
            break
        }
    }

    private mutating func validateScroll(
        _ selection: ScrollContainerSelection,
        path: String,
        scope: AdmissionScope
    ) {
        if case .element(let target) = selection {
            validateElementTarget(target, path: "\(path).target")
        }
    }

    private mutating func validateTarget(
        _ target: ElementTargetExpr,
        path: String,
        scope: AdmissionScope
    ) {
        switch target {
        case .target(let target):
            validateElementTarget(target, path: path)
        case .ref(let reference):
            validateReference(reference, path: path, role: "target_ref")
            if !scope.targetRefs.contains(reference) {
                fail(
                    path: path,
                    contract: "target_ref must resolve in the current heist scope",
                    observed: "\"\(reference)\"",
                    correction: "Use target_ref only inside the for_each_element body that defines it."
                )
            }
        }
    }

    private mutating func validateString(
        _ string: StringExpr,
        path: String,
        scope: AdmissionScope
    ) {
        switch string {
        case .literal(let literal):
            addString(literal, path: path, role: "string literal")
        case .ref(let reference):
            validateReference(reference, path: path, role: "text_ref")
            if !scope.stringRefs.contains(reference) {
                fail(
                    path: path,
                    contract: "text_ref must resolve in the current heist scope",
                    observed: "\"\(reference)\"",
                    correction: "Use text_ref only inside the for_each_string body that defines it."
                )
            }
        }
    }

    private mutating func validateElementTarget(_ target: ElementTarget, path: String) {
        switch target {
        case .predicate(let predicate, _):
            validateElementPredicate(predicate, path: path)
        }
    }

    private mutating func validateElementPredicate(
        _ predicate: ElementPredicate,
        path: String
    ) {
        addString(predicate.label, path: "\(path).label", role: "element label")
        addString(predicate.identifier, path: "\(path).identifier", role: "element identifier")
        addString(predicate.value, path: "\(path).value", role: "element value")
    }

    private mutating func validateElementPredicate(
        _ predicate: ElementPredicateExpr,
        path: String,
        scope: AdmissionScope
    ) {
        if let label = predicate.label {
            validateString(label, path: "\(path).label", scope: scope)
        }
        if let identifier = predicate.identifier {
            validateString(identifier, path: "\(path).identifier", scope: scope)
        }
        if let value = predicate.value {
            validateString(value, path: "\(path).value", scope: scope)
        }
    }

    private mutating func validateParameter(_ parameter: String, path: String, role: String) {
        addParameterString(parameter, path: path, role: role)
        guard HeistParameterName.isValid(parameter) else {
            fail(
                path: path,
                contract: "\(role) must be a Swift-style identifier",
                observed: "\"\(escaped(parameter))\"",
                correction: "Use letters, digits, and underscores, starting with a letter or underscore; avoid Swift keywords."
            )
            return
        }
    }

    private mutating func validateReference(_ reference: String, path: String, role: String) {
        addParameterString(reference, path: path, role: role)
        if !HeistParameterName.isValid(reference) {
            fail(
                path: path,
                contract: "\(role) must be a Swift-style identifier",
                observed: "\"\(escaped(reference))\"",
                correction: "Use a ref matching the loop parameter exactly."
            )
        }
    }

    private mutating func addParameterString(_ value: String, path: String, role: String) {
        let bytes = value.utf8.count
        if bytes > limits.maxParameterBytes {
            fail(
                path: path,
                contract: "max parameter/ref length",
                observed: "\(bytes) bytes for \(role)",
                correction: "Use \(limits.maxParameterBytes) bytes or fewer."
            )
        }
        addString(value, path: path, role: role)
    }

    private mutating func addString(_ value: String?, path: String, role: String) {
        guard let value else { return }
        let bytes = value.utf8.count
        if bytes > limits.maxStringBytes {
            fail(
                path: path,
                contract: "max string length",
                observed: "\(bytes) bytes for \(role)",
                correction: "Use \(limits.maxStringBytes) bytes or fewer for any single string."
            )
        }
        totalStringBytes += bytes
        if totalStringBytes > limits.maxTotalStringBytes, !reportedTotalStringLimit {
            reportedTotalStringLimit = true
            fail(
                path: path,
                contract: "max total string bytes",
                observed: "\(totalStringBytes) bytes",
                correction: "Use \(limits.maxTotalStringBytes) total UTF-8 string bytes or fewer."
            )
        }
    }

    private mutating func validateCanonicalRenderability(_ command: HeistActionCommand, path: String) {
        switch command {
        case .rotor(let selection, _, _):
            if case .named = selection {
                return
            }
            fail(
                path: path,
                contract: "canonical Swift DSL renderability",
                observed: "rotor selection \(selection)",
                correction: "Use a named rotor selection in durable heist JSON."
            )
        case .mechanicalLongPress(let target):
            if case .element = target.selection, target.duration != .longPressDefault {
                fail(
                    path: path,
                    contract: "canonical Swift DSL renderability",
                    observed: "long_press element duration \(target.duration)",
                    correction: "Use the default element long-press duration or a coordinate long press."
                )
            }
        case .mechanicalSwipe(let target):
            if target.duration != nil {
                fail(
                    path: path,
                    contract: "canonical Swift DSL renderability",
                    observed: "swipe duration \(String(describing: target.duration))",
                    correction: "Use the default swipe duration in durable heist JSON."
                )
            }
            switch target.selection {
            case .elementDirection, .point(.coordinate, .coordinate), .point(.coordinate, .direction):
                break
            case .unitElement, .point(.element, _):
                fail(
                    path: path,
                    contract: "canonical Swift DSL renderability",
                    observed: "unsupported swipe selection \(target.selection)",
                    correction: "Use element-direction, point-to-point, or point-direction swipe."
                )
            }
        case .mechanicalDrag(let target):
            if target.duration != nil {
                fail(
                    path: path,
                    contract: "canonical Swift DSL renderability",
                    observed: "drag duration \(String(describing: target.duration))",
                    correction: "Use the default drag duration in durable heist JSON."
                )
            }
        case .activate, .increment, .decrement, .customAction, .typeText, .mechanicalTap,
             .viewportScroll, .viewportScrollToVisible, .viewportScrollToEdge,
             .editAction, .setPasteboard, .dismissKeyboard:
            break
        }
    }

    private func validateDirectCommandContract(_ message: ClientMessage) throws {
        let data = try encoder.encode(message)
        _ = try decoder.decode(ClientMessage.self, from: data)
    }

    private mutating func fail(
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

    private func summarize(_ error: Error) -> String {
        let text = String(describing: error)
        guard text.count > 220 else { return text }
        return "\(text.prefix(217))..."
    }

    private func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\0", with: "\\0")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

private struct AdmissionScope {
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

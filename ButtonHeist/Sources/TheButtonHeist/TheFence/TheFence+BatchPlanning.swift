import Foundation

extension TheFence {

    func decodeRunBatchRequest(_ request: [String: Any]) throws -> RunBatchRequest {
        try Self.validateJSONEnvelope(
            request,
            field: "run_batch",
            maxBytes: DecodeLimits.maxRunBatchRequestBytes,
            maxDepth: DecodeLimits.maxRunBatchNestingDepth
        )
        let rawSteps = try request.requiredSchemaDictionaryArray("steps")
        guard !rawSteps.isEmpty else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count 0",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        guard rawSteps.count <= DecodeLimits.maxRunBatchSteps else {
            throw SchemaValidationError(
                field: "steps",
                observed: "array count \(rawSteps.count)",
                expected: "array count 1...\(DecodeLimits.maxRunBatchSteps)"
            )
        }
        return RunBatchRequest(
            steps: rawSteps.enumerated().map { index, step in
                decodeRunBatchStep(step, index: index)
            },
            policy: try request.schemaEnum("policy", as: BatchPolicy.self) ?? .stopOnError
        )
    }

    private func decodeRunBatchStep(_ step: [String: Any], index: Int) -> RunBatchStep {
        let originalCommandName = step["command"] as? String ?? "?"
        switch FenceOperationCatalog.normalizeBatchStep(step) {
        case .success(let operation):
            if let failure = batchBoundedResponseFailure(operation: operation, index: index) {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: failure
                )
            }
            do {
                let request = try parseRequest(operation: operation)
                return .planned(try batchStepPlan(index: index, operation: operation, request: request))
            } catch let error as SchemaValidationError {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepFailure(
                        message: error.message,
                        details: nil,
                        includeDetailsInResult: true
                    )
                )
            } catch let error as MissingElementTarget {
                let response = missingElementTargetResponse(command: error.command)
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: batchStepFailure(from: response)
                )
            } catch let error as FenceError {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepFailure(
                        message: error.coreMessage,
                        details: error.failureDetails,
                        includeDetailsInResult: true
                    )
                )
            } catch let error as BatchStepPlanBuildError {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepFailure(
                        message: error.message,
                        details: nil,
                        includeDetailsInResult: false
                    )
                )
            } catch {
                return .invalid(
                    commandName: operation.command.rawValue,
                    failure: BatchStepFailure(
                        message: error.localizedDescription,
                        details: nil,
                        includeDetailsInResult: false
                    )
                )
            }

        case .failure(let error):
            let fenceError = FenceError.invalidRequest("run_batch step \(index): \(error.message)")
            return .invalid(
                commandName: originalCommandName,
                failure: BatchStepFailure(
                    message: fenceError.coreMessage,
                    details: fenceError.failureDetails,
                    includeDetailsInResult: false
                )
            )
        }
    }

    private struct BatchStepPlanBuildError: Error {
        let message: String
    }

    private struct BatchStepPlanningContext {
        let originalIndex: Int
        let operation: NormalizedOperation
        let request: ParsedRequest
        let expectation: ActionExpectation?
        let timeout: Double?

        init(originalIndex: Int, operation: NormalizedOperation, request: ParsedRequest) {
            self.originalIndex = originalIndex
            self.operation = operation
            self.request = request
            expectation = request.expectationPayload.expectation
            timeout = request.expectationPayload.timeout
        }

        func plan(
            action: TheScore.Action,
            expectation overrideExpectation: ActionExpectation? = nil,
            timeout overrideTimeout: Double? = nil
        ) -> RunBatchPreparedStep {
            let stepTimeout = overrideTimeout ?? timeout
            return RunBatchPreparedStep(
                originalIndex: originalIndex,
                commandName: request.command.rawValue,
                action: action,
                expectation: overrideExpectation ?? expectation ?? action.defaultExpectation,
                deadline: deadline(for: action, timeout: stepTimeout)
            )
        }

        private func deadline(for action: TheScore.Action, timeout: Double?) -> TheScore.Deadline {
            timeout.map(TheScore.Deadline.init(timeout:)) ?? action.defaultDeadline
        }
    }

    func batchStepPlan(
        index: Int,
        operation: NormalizedOperation,
        request: ParsedRequest
    ) throws -> RunBatchPreparedStep {
        let context = BatchStepPlanningContext(originalIndex: index, operation: operation, request: request)
        switch request.payload {
        case .gesture(let payload):
            return try batchGestureStep(payload, context: context)
        case .scroll(let payload):
            return try batchScrollStep(payload, context: context)
        case .accessibility(let payload):
            return try batchAccessibilityStep(payload, context: context)
        case .rotor(let target):
            let semanticTarget = semanticTarget(from: operation, fallback: target.elementTarget)
            return try context.plan(action: .rotor(BatchRotorTarget(
                target: requiredExecutionTarget(semanticTarget),
                rotor: target.rotor,
                rotorIndex: target.rotorIndex,
                direction: target.direction,
                currentSourceHeistId: target.currentHeistId,
                currentTextRange: target.currentTextRange
            )))
        case .typeText(let target):
            let semanticTarget = semanticTarget(from: operation, fallback: target.elementTarget)
            return try context.plan(action: .typeText(BatchTypeTextTarget(
                text: target.text,
                target: optionalExecutionTarget(semanticTarget)
            )))
        case .editAction(let target):
            return context.plan(action: .editAction(target))
        case .setPasteboard(let target):
            return context.plan(action: .setPasteboard(target))
        case .none where request.command == .dismissKeyboard:
            return context.plan(action: .resignFirstResponder)
        case .waitFor(let target):
            return try batchWaitForStep(target, context: context)
        case .waitForChange:
            let expectation = context.expectation ?? .screenChanged
            return context.plan(
                action: .waitForChange(WaitForChangeTarget(expect: expectation, timeout: context.timeout)),
                expectation: expectation,
                timeout: context.timeout
            )
        default:
            throw BatchStepPlanBuildError(
                message: "run_batch step command \"\(request.command.rawValue)\" is not a non-read batch Action"
            )
        }
    }

    private func batchGestureStep(
        _ payload: GesturePayload,
        context: BatchStepPlanningContext
    ) throws -> RunBatchPreparedStep {
        switch payload {
        case .oneFingerTap(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchTap(BatchTouchTapTarget(
                target: optionalExecutionTarget(target),
                pointX: payload.pointX,
                pointY: payload.pointY
            )))
        case .longPress(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchLongPress(BatchLongPressTarget(
                target: optionalExecutionTarget(target),
                pointX: payload.pointX,
                pointY: payload.pointY,
                duration: payload.duration
            )))
        case .swipe(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchSwipe(BatchSwipeTarget(
                target: optionalExecutionTarget(target),
                startX: payload.startX,
                startY: payload.startY,
                endX: payload.endX,
                endY: payload.endY,
                direction: payload.direction,
                duration: payload.duration,
                start: payload.start,
                end: payload.end
            )))
        case .drag(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchDrag(BatchDragTarget(
                target: optionalExecutionTarget(target),
                startX: payload.startX,
                startY: payload.startY,
                endX: payload.endX,
                endY: payload.endY,
                duration: payload.duration
            )))
        case .pinch(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchPinch(BatchPinchTarget(
                target: optionalExecutionTarget(target),
                centerX: payload.centerX,
                centerY: payload.centerY,
                scale: payload.scale,
                spread: payload.spread,
                duration: payload.duration
            )))
        case .rotate(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchRotate(BatchRotateTarget(
                target: optionalExecutionTarget(target),
                centerX: payload.centerX,
                centerY: payload.centerY,
                angle: payload.angle,
                radius: payload.radius,
                duration: payload.duration
            )))
        case .twoFingerTap(let payload):
            let operation = context.operation
            let target = semanticTarget(from: operation, fallback: payload.elementTarget)
            return try context.plan(action: .touchTwoFingerTap(BatchTwoFingerTapTarget(
                target: optionalExecutionTarget(target),
                centerX: payload.centerX,
                centerY: payload.centerY,
                spread: payload.spread
            )))
        case .drawPath(let payload):
            return context.plan(action: .touchDrawPath(payload.target))
        case .drawBezier(let payload):
            return context.plan(action: .touchDrawBezier(payload.target))
        }
    }

    private func batchScrollStep(
        _ payload: ScrollPayload,
        context: BatchStepPlanningContext
    ) throws -> RunBatchPreparedStep {
        switch payload {
        case .scroll(let target):
            let semanticTarget = semanticTarget(from: context.operation, fallback: target.elementTarget)
            return try context.plan(action: .scroll(BatchScrollTarget(
                target: optionalExecutionTarget(semanticTarget),
                direction: target.direction
            )))
        case .scrollToVisible(let target):
            let semanticTarget = semanticTarget(from: context.operation, fallback: target.elementTarget)
            return try context.plan(action: .scrollToVisible(BatchScrollToVisibleTarget(
                target: optionalExecutionTarget(semanticTarget)
            )))
        case .elementSearch(let target):
            let semanticTarget = semanticTarget(from: context.operation, fallback: target.elementTarget)
            return try context.plan(action: .elementSearch(BatchElementSearchTarget(
                target: optionalExecutionTarget(semanticTarget),
                direction: target.direction
            )))
        case .scrollToEdge(let target):
            let semanticTarget = semanticTarget(from: context.operation, fallback: target.elementTarget)
            return try context.plan(action: .scrollToEdge(BatchScrollToEdgeTarget(
                target: optionalExecutionTarget(semanticTarget),
                edge: target.edge
            )))
        }
    }

    private func batchAccessibilityStep(
        _ payload: AccessibilityPayload,
        context: BatchStepPlanningContext
    ) throws -> RunBatchPreparedStep {
        switch payload {
        case .activate(let target, let actionName, let count):
            let semanticTarget = semanticTarget(from: context.operation, fallback: target)
            let executionTarget = try requiredExecutionTarget(semanticTarget)
            return try context.plan(action: batchAccessibilityAction(
                target: executionTarget,
                command: context.request.command,
                actionName: actionName,
                count: count
            ))
        case .increment(let target, let count):
            try rejectRepeatedBatchCount(count, command: context.request.command)
            let semanticTarget = semanticTarget(from: context.operation, fallback: target)
            return try context.plan(action: .increment(requiredExecutionTarget(semanticTarget)))
        case .decrement(let target, let count):
            try rejectRepeatedBatchCount(count, command: context.request.command)
            let semanticTarget = semanticTarget(from: context.operation, fallback: target)
            return try context.plan(action: .decrement(requiredExecutionTarget(semanticTarget)))
        case .performCustomAction(let target, let count):
            try rejectObservedBatchCount(count, command: context.request.command)
            if let elementTarget = target.elementTarget {
                let semanticTarget = semanticTarget(from: context.operation, fallback: elementTarget)
                return try context.plan(action: .performCustomAction(BatchCustomActionTarget(
                    target: requiredExecutionTarget(semanticTarget),
                    actionName: target.actionName
                )))
            }
            guard let containerTarget = target.containerTarget else {
                throw MissingElementTarget(command: context.request.command.rawValue)
            }
            return context.plan(action: .performCustomAction(BatchCustomActionTarget(
                containerTarget: containerTarget,
                ordinal: target.containerOrdinal,
                actionName: target.actionName
            )))
        }
    }

    private func batchWaitForStep(
        _ target: WaitForTarget,
        context: BatchStepPlanningContext
    ) throws -> RunBatchPreparedStep {
        let semanticTarget = semanticTarget(from: context.operation, fallback: target.elementTarget)
        let resolvedTimeout = target.timeout ?? context.timeout
        let waitAction = TheScore.Action.waitForElement(BatchWaitForTarget(
            target: try requiredExecutionTarget(semanticTarget),
            absent: target.absent,
            timeout: resolvedTimeout
        ))
        return try context.plan(
            action: waitAction,
            expectation: waitExpectation(target: semanticTarget, absent: target.absent),
            timeout: resolvedTimeout
        )
    }

    private func batchAccessibilityAction(
        target: BatchExecutionTarget,
        command: Command,
        actionName: String?,
        count: CountArgument
    ) throws -> TheScore.Action {
        guard let actionName else {
            try rejectObservedBatchCount(count, command: command)
            return .activate(target)
        }
        switch actionName {
        case Command.increment.rawValue:
            try rejectRepeatedBatchCount(count, command: command)
            return .increment(target)
        case Command.decrement.rawValue:
            try rejectRepeatedBatchCount(count, command: command)
            return .decrement(target)
        default:
            try rejectObservedBatchCount(count, command: command)
            let customName = actionName.hasPrefix("action:")
                ? String(actionName.dropFirst("action:".count))
                : actionName
            guard !customName.isEmpty else {
                throw BatchStepPlanBuildError(message: "action: prefix requires a name (e.g. \"action:myAction\")")
            }
            return .performCustomAction(BatchCustomActionTarget(target: target, actionName: customName))
        }
    }

    private func waitExpectation(
        target: BatchExecutionTarget?,
        absent: Bool?
    ) throws -> ActionExpectation {
        let matcher = try expectationMatcher(target)
        if absent == true {
            return .elementDisappeared(matcher)
        }
        return .elementAppeared(matcher)
    }

    private func expectationMatcher(_ target: BatchExecutionTarget?) throws -> ElementMatcher {
        guard let target else {
            throw BatchStepPlanBuildError(message: "typed batch expectation requires matcher predicates")
        }
        guard target.matcher.hasPredicates else {
            if let sourceHeistId = target.sourceHeistId {
                throw BatchStepPlanBuildError(
                    message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates for typed batch expectation; heistId is source metadata only"
                )
            }
            throw BatchStepPlanBuildError(
                message: "typed batch expectation requires matcher predicates"
            )
        }
        return target.matcher
    }

    private func optionalExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget? {
        guard let target else { return nil }
        return try executionTarget(target)
    }

    private func requiredExecutionTarget(_ target: BatchExecutionTarget?) throws -> BatchExecutionTarget {
        guard let target else {
            throw BatchStepPlanBuildError(message: "typed batch target requires matcher predicates or ordinal fallback")
        }
        return try executionTarget(target)
    }

    private func executionTarget(_ target: BatchExecutionTarget) throws -> BatchExecutionTarget {
        guard target.matcher.hasPredicates || target.ordinal != nil else {
            if let sourceHeistId = target.sourceHeistId {
                throw BatchStepPlanBuildError(
                    message: "run_batch target \"\(sourceHeistId)\" needs matcher predicates or ordinal fallback; heistId is source metadata only"
                )
            }
            throw BatchStepPlanBuildError(
                message: "typed batch target requires matcher predicates or ordinal fallback; heistId is source metadata only"
            )
        }
        return target
    }

    private func rejectRepeatedBatchCount(_ count: CountArgument, command: Command) throws {
        guard let value = count.value, value != 1 else { return }
        throw BatchStepPlanBuildError(
            message: "run_batch step command \"\(command.rawValue)\" with count > 1 is not supported by typed batch execution"
        )
    }

    private func rejectObservedBatchCount(_ count: CountArgument, command: Command) throws {
        guard count.observed != nil else { return }
        throw BatchStepPlanBuildError(
            message: "run_batch step command \"\(command.rawValue)\" does not support count in typed batch execution"
        )
    }

    private func semanticTarget(
        from operation: NormalizedOperation,
        fallback target: ElementTarget?
    ) -> BatchExecutionTarget? {
        let argumentTarget = semanticTarget(from: operation.arguments)
        if argumentTarget != nil { return argumentTarget }
        return semanticTarget(from: target)
    }

    private func semanticTarget(from arguments: [String: Any]) -> BatchExecutionTarget? {
        let sourceHeistId = try? arguments.schemaString("heistId")
        let ordinal = try? arguments.schemaInteger("ordinal")
        let parsedMatcher = (try? elementMatcher(arguments)) ?? ElementMatcher()
        let matcher = ElementMatcher(
            label: parsedMatcher.label,
            identifier: parsedMatcher.identifier,
            value: parsedMatcher.value,
            traits: parsedMatcher.traits,
            excludeTraits: parsedMatcher.excludeTraits
        )
        guard sourceHeistId != nil || matcher.hasPredicates || ordinal != nil else { return nil }
        return BatchExecutionTarget(sourceHeistId: sourceHeistId, matcher: matcher, ordinal: ordinal)
    }

    private func semanticTarget(from target: ElementTarget?) -> BatchExecutionTarget? {
        guard let target else { return nil }
        switch target {
        case .heistId(let heistId):
            return BatchExecutionTarget(sourceHeistId: heistId, matcher: ElementMatcher())
        case .matcher(let matcher, let ordinal):
            return BatchExecutionTarget(matcher: matcher, ordinal: ordinal)
        }
    }

    private func batchBoundedResponseFailure(
        operation: NormalizedOperation,
        index: Int
    ) -> BatchStepFailure? {
        guard operation.command == .getScreen,
              operation.arguments["inlineData"] as? Bool == true
        else { return nil }

        let error = SchemaValidationError(
            field: "steps[\(index)].inlineData",
            observed: true,
            expected: "not allowed for get_screen inside run_batch; omit inlineData or call get_screen outside run_batch"
        )
        return BatchStepFailure(
            message: error.message,
            details: nil,
            includeDetailsInResult: true
        )
    }

    private func batchStepFailure(from response: FenceResponse) -> BatchStepFailure {
        guard case .error(let message, let details) = response else {
            return BatchStepFailure(
                message: response.humanFormatted(),
                details: nil,
                includeDetailsInResult: false
            )
        }
        return BatchStepFailure(
            message: message,
            details: details,
            includeDetailsInResult: true
        )
    }
}

private extension TheFence {

    static func validateJSONEnvelope(
        _ value: Any,
        field: String,
        maxBytes: Int,
        maxDepth: Int
    ) throws {
        let byteCount = try jsonEncodedSize(
            of: value,
            field: field,
            maxBytes: maxBytes,
            maxDepth: maxDepth
        )
        guard byteCount <= maxBytes else {
            throw SchemaValidationError(
                field: field,
                observed: "\(byteCount) bytes",
                expected: "JSON request <= \(maxBytes) bytes"
            )
        }
    }

    static func jsonEncodedSize(
        of value: Any,
        field: String,
        maxBytes: Int,
        maxDepth: Int,
        depth: Int = 1
    ) throws -> Int {
        guard depth <= maxDepth else {
            throw SchemaValidationError(
                field: field,
                observed: "nesting depth \(depth)",
                expected: "nesting depth <= \(maxDepth)"
            )
        }

        func bounded(_ size: Int) throws -> Int {
            guard size <= maxBytes else {
                throw SchemaValidationError(
                    field: field,
                    observed: "\(size) bytes",
                    expected: "JSON request <= \(maxBytes) bytes"
                )
            }
            return size
        }

        if let dictionary = value as? [String: Any] {
            var size = 2
            for (index, entry) in dictionary.enumerated() {
                if index > 0 { size = try bounded(size + 1) }
                size = try bounded(size + jsonStringEncodedSize(entry.key) + 1)
                let valueSize = try jsonEncodedSize(
                    of: entry.value,
                    field: field,
                    maxBytes: maxBytes,
                    maxDepth: maxDepth,
                    depth: depth + 1
                )
                size = try bounded(size + valueSize)
            }
            return size
        }

        if let array = value as? [Any] {
            var size = 2
            for (index, item) in array.enumerated() {
                if index > 0 { size = try bounded(size + 1) }
                let itemSize = try jsonEncodedSize(
                    of: item,
                    field: field,
                    maxBytes: maxBytes,
                    maxDepth: maxDepth,
                    depth: depth + 1
                )
                size = try bounded(size + itemSize)
            }
            return size
        }

        if let string = value as? String {
            return try bounded(jsonStringEncodedSize(string))
        }

        if let bool = value as? Bool {
            return bool ? 4 : 5
        }

        if value is NSNull {
            return 4
        }

        if let number = value as? NSNumber {
            guard number.doubleValue.isFinite else {
                throw SchemaValidationError(field: field, observed: number, expected: "finite JSON number")
            }
            return try bounded(String(describing: number).utf8.count)
        }

        throw SchemaValidationError(field: field, observed: value, expected: "JSON value")
    }

    static func jsonStringEncodedSize(_ value: String) -> Int {
        var size = 2
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22, 0x5C:
                size += 2
            case 0x00...0x1F:
                size += 6
            default:
                size += scalar.utf8.count
            }
        }
        return size
    }

}

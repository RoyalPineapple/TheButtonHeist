// MARK: - Action Expectation Validation

extension ActionExpectation {
    /// Check this expectation against an ActionResult.
    /// - Parameter preActionElements: Elements from the pre-action capture, keyed by heistId.
    ///   Required for `elementDisappeared` validation (resolves removed heistIds to matchers).
    ///   Pass an empty dictionary if unavailable.
    public func validate(
        against result: ActionResult,
        preActionElements: [HeistId: HeistElement] = [:]
    ) -> ExpectationResult {
        switch self {
        case .screenChanged:
            let delta = result.accessibilityTrace?.endpointDeltaProjection
            return ExpectationResult(
                met: delta?.isScreenChangeProjection == true,
                expectation: self,
                actual: delta?.kindDescription ?? "noTrace"
            )
        case .elementsChanged:
            let delta = result.accessibilityTrace?.endpointDeltaProjection
            return ExpectationResult(
                met: delta?.satisfiesElementsChanged == true,
                expectation: self,
                actual: delta?.kindDescription ?? "noTrace"
            )
        case .elementUpdated(let heistId, let property, let oldValue, let newValue):
            return Self.validateElementUpdated(
                heistId: heistId,
                property: property,
                oldValue: oldValue,
                newValue: newValue,
                expectation: self,
                result: result
            )
        case .elementAppeared(let matcher):
            return Self.validateElementAppeared(
                matcher: matcher,
                expectation: self,
                result: result
            )
        case .elementDisappeared(let matcher):
            return Self.validateElementDisappeared(
                matcher: matcher,
                expectation: self,
                result: result,
                preActionElements: preActionElements
            )
        }
    }

    private static func validateElementUpdated(
        heistId: HeistId?,
        property: ElementProperty?,
        oldValue: String?,
        newValue: String?,
        expectation: ActionExpectation,
        result: ActionResult
    ) -> ExpectationResult {
        let updates = result.accessibilityTrace?.endpointDeltaProjection?.elementEditsProjection.updated ?? []
        guard !updates.isEmpty else {
            return ExpectationResult(met: false, expectation: expectation, actual: "no element updates")
        }
        let match = updates.contains { update in
            if let heistId, update.heistId != heistId { return false }
            let targetChanges: [PropertyChange]
            if let property {
                targetChanges = update.changes.filter { $0.property == property }
                if targetChanges.isEmpty { return false }
            } else {
                targetChanges = update.changes
            }
            if oldValue != nil || newValue != nil {
                guard targetChanges.contains(where: { change in
                    if let oldValue, change.old != oldValue { return false }
                    if let newValue, change.new != newValue { return false }
                    return true
                }) else { return false }
            }
            return true
        }
        if match {
            return ExpectationResult(met: true, expectation: expectation, actual: nil)
        }
        let observed = updates.map { update in
            let props = update.changes.map { "\($0.property.rawValue): \($0.old ?? "nil") → \($0.new ?? "nil")" }
            return "\(update.heistId): \(props.joined(separator: ", "))"
        }.joined(separator: "; ")
        return ExpectationResult(met: false, expectation: expectation, actual: observed)
    }

    private static func validateElementAppeared(
        matcher: ElementMatcher,
        expectation: ActionExpectation,
        result: ActionResult
    ) -> ExpectationResult {
        let delta = result.accessibilityTrace?.endpointDeltaProjection
        let added = delta?.elementEditsProjection.added ?? []
        if !added.isEmpty {
            if added.contains(where: { $0.matches(matcher) }) {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            let labels = added.compactMap(\.label).prefix(5).joined(separator: ", ")
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "added: [\(labels)]"
            )
        }

        if case .screenChanged(let payload)? = delta {
            if payload.newInterface.projectedElements.contains(where: { $0.matches(matcher) }) {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "screen changed but element not found in new interface"
            )
        }

        return ExpectationResult(
            met: false,
            expectation: expectation,
            actual: "no elements added"
        )
    }

    private static func validateElementDisappeared(
        matcher: ElementMatcher,
        expectation: ActionExpectation,
        result: ActionResult,
        preActionElements: [HeistId: HeistElement]
    ) -> ExpectationResult {
        let delta = result.accessibilityTrace?.endpointDeltaProjection
        let removed = delta?.elementEditsProjection.removed ?? []
        if !removed.isEmpty {
            let matched = removed.contains { heistId in
                guard let element = preActionElements[heistId] else { return false }
                return element.matches(matcher)
            }
            if matched {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            let removedIds = removed.prefix(5).joined(separator: ", ")
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: "removed: [\(removedIds)]"
            )
        }

        if case .screenChanged(let payload)? = delta {
            let matchedBefore = preActionElements.values.contains { $0.matches(matcher) }
            let stillPresent = payload.newInterface.projectedElements.contains { $0.matches(matcher) }
            if matchedBefore, !stillPresent {
                return ExpectationResult(met: true, expectation: expectation, actual: nil)
            }
            return ExpectationResult(
                met: false,
                expectation: expectation,
                actual: matchedBefore
                    ? "screen changed but element still present in new interface"
                    : "screen changed but element was not in pre-action state"
            )
        }

        return ExpectationResult(met: false, expectation: expectation, actual: "no elements removed")
    }
}

private extension AccessibilityTrace.Delta {
    var kindDescription: String {
        switch self {
        case .noChange: return AccessibilityTrace.DeltaKind.noChange.rawValue
        case .elementsChanged: return AccessibilityTrace.DeltaKind.elementsChanged.rawValue
        case .screenChanged: return AccessibilityTrace.DeltaKind.screenChanged.rawValue
        }
    }

    var isScreenChangeProjection: Bool {
        if case .screenChanged = self { return true }
        return false
    }

    var satisfiesElementsChanged: Bool {
        switch self {
        case .noChange: return false
        case .elementsChanged, .screenChanged: return true
        }
    }

    var elementEditsProjection: ElementEdits {
        if case .elementsChanged(let payload) = self { return payload.edits }
        return ElementEdits()
    }
}

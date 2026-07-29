import ThePlans
import TheScore

extension HeistDoctor {
    static func repairEvidence(from step: HeistExecutionStepResult) throws -> HeistRepairEvidence {
        guard let actionEvidence = step.actionEvidence else {
            throw HeistDoctorError.missingActionEvidence(path: step.path)
        }
        guard let command = step.actionCommand else {
            throw HeistDoctorError.missingActionEvidence(path: step.path)
        }
        guard let target = step.reportTarget else {
            throw HeistDoctorError.missingTarget(path: step.path)
        }
        guard let result = actionEvidence.result else {
            throw HeistDoctorError.missingActionResult(path: step.path)
        }
        guard let observation = result.observationEvidence,
              let before = observation.baseline?.interface
        else {
            throw HeistDoctorError.missingObservationEvidence(path: step.path)
        }
        let projection = RepairObservationProjection(observation)
        let expectation = try actionEvidence.replayExpectation()

        let outcome: HeistRepairEvidenceOutcome
        switch step.status {
        case .passed:
            outcome = .passed
        case .failed:
            outcome = .failed(
                failureKind: result.outcome.failureKind,
                message: repairMessage(
                    step: step,
                    evidence: actionEvidence,
                    expectation: expectation
                )
            )
        case .skipped:
            throw HeistDoctorError.stepStatus(path: step.path, expected: .passed, actual: .skipped)
        }

        return HeistRepairEvidence(
            stepPath: step.path,
            command: command,
            target: target,
            beforeSnapshot: before,
            observedChanges: projection.changes,
            semanticEvidence: projection.semanticText,
            method: result.method,
            expectation: expectation,
            outcome: outcome
        )
    }

    private static func repairMessage(
        step: HeistExecutionStepResult,
        evidence: HeistActionEvidence,
        expectation: ExpectationResult?
    ) -> String? {
        step.failure?.observed
            ?? evidence.result?.message
            ?? expectation?.actual
    }
}

private struct RepairObservationProjection {
    let changes: [RepairChangeFactObservation]
    let semanticText: [String]

    init(_ evidence: Observation.Evidence) {
        var previous = evidence.baseline
        var changes: [RepairChangeFactObservation] = []
        var semanticText: [String] = []

        for event in evidence.events {
            switch event {
            case .elementsChanged(let snapshot):
                let edits = previous.map {
                    ElementEdits.between($0.interface, snapshot.interface)
                } ?? ElementEdits(
                    added: snapshot.interface.projectedElements,
                    removed: [],
                    updated: []
                )
                if !edits.removed.isEmpty {
                    changes.append(.semanticElementsRemoved)
                }
                changes.append(contentsOf: edits.updated.flatMap(\.changes)
                    .filter { $0.property == .value }
                    .map {
                        .valueChange(old: $0.oldDisplayText, new: $0.newDisplayText)
                    })
                if !edits.added.isEmpty {
                    changes.append(.semanticElementsAdded)
                }
                if edits.added.isEmpty, edits.removed.isEmpty, edits.updated.isEmpty {
                    changes.append(.elementChanges)
                }
                semanticText.append(contentsOf: edits.removed.flatMap(repairIdentityStrings))
                semanticText.append(contentsOf: edits.added.flatMap(repairIdentityStrings))
                semanticText.append(contentsOf: edits.updated.flatMap {
                    repairIdentityStrings($0.before)
                        + repairIdentityStrings($0.after)
                        + $0.changes.flatMap {
                            [$0.oldDisplayText, $0.newDisplayText].compactMap { $0 }
                        }
                })
                previous = snapshot
            case .screenChanged:
                changes.append(.screenChange)
            case .notification(let notification):
                semanticText.append(contentsOf: [notification.text].compactMap { $0 })
                if let element = notification.element {
                    semanticText.append(contentsOf: repairIdentityStrings(element))
                }
            case .noChange:
                break
            }
        }

        self.changes = changes
        self.semanticText = semanticText.uniqued(on: \.self)
    }
}

private func repairIdentityStrings(_ element: HeistElement) -> [String] {
    repairIdentityStrings(element.semantics)
}

private func repairIdentityStrings(_ semantics: HeistElement.Semantics) -> [String] {
    let assertable = semantics.assertable
    return [
        stableIdentifier(assertable.identifier),
        assertable.label,
        assertable.value,
        assertable.hint,
        semantics.spokenDescription,
    ].compactMap { $0 }
}

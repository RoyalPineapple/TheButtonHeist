import Foundation

enum HeistDefinitionDuplicatePolicy: Equatable {
    /// Source preserves duplicate concrete definitions for semantic validation
    /// to diagnose; only namespace fragments are structural composition.
    case preserve
    /// Result-builder expansion can encounter the same definition value more
    /// than once and discards that identical expansion.
    case discardIdentical
}

func mergeHeistDefinitions(
    _ definitions: [HeistPlanAdmissionCandidate],
    duplicatePolicy: HeistDefinitionDuplicatePolicy
) -> [HeistPlanAdmissionCandidate] {
    definitions.reduce(into: []) { merged, definition in
        guard let definitionName = definition.name,
              let existingIndex = merged.firstIndex(where: { $0.name == definitionName })
        else {
            merged.append(definition)
            return
        }

        let existing = merged[existingIndex]
        if duplicatePolicy == .discardIdentical, existing == definition {
            return
        }
        guard existing.isNamespaceFragment, definition.isNamespaceFragment else {
            merged.append(definition)
            return
        }
        merged[existingIndex] = HeistPlanAdmissionCandidate(
            version: existing.version,
            name: existing.name,
            parameter: existing.parameter,
            definitions: mergeHeistDefinitions(
                existing.definitions + definition.definitions,
                duplicatePolicy: duplicatePolicy
            ),
            body: existing.body
        )
    }
}

func nestedHeistDefinition(
    path: HeistDefinitionPath,
    parameter: HeistParameter,
    definitions: [HeistPlanAdmissionCandidate],
    body: [HeistStepAdmissionCandidate]
) -> HeistPlanAdmissionCandidate {
    nestedHeistDefinition(
        components: path.components[...],
        parameter: parameter,
        definitions: definitions,
        body: body
    )
}

private func nestedHeistDefinition(
    components: ArraySlice<HeistPlanName>,
    parameter: HeistParameter,
    definitions: [HeistPlanAdmissionCandidate],
    body: [HeistStepAdmissionCandidate]
) -> HeistPlanAdmissionCandidate {
    guard let first = components.first else {
        preconditionFailure("validated heist definition path must not be empty")
    }
    guard components.count > 1 else {
        return HeistPlanAdmissionCandidate(
            name: first,
            parameter: parameter,
            definitions: definitions,
            body: body
        )
    }
    return HeistPlanAdmissionCandidate(
        name: first,
        definitions: [
            nestedHeistDefinition(
                components: components.dropFirst(),
                parameter: parameter,
                definitions: definitions,
                body: body
            ),
        ],
        body: []
    )
}

private extension HeistPlanAdmissionCandidate {
    var isNamespaceFragment: Bool {
        parameter == .none && body.isEmpty && !definitions.isEmpty
    }
}

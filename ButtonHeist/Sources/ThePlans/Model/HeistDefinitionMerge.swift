import Foundation

enum HeistDefinitionDuplicatePolicy: Equatable {
    /// Source preserves duplicate concrete definitions for semantic validation
    /// to diagnose; only namespace fragments are structural composition.
    case preserve
    /// Result-builder expansion can encounter the same definition value more
    /// than once and discards that identical expansion.
    case discardIdentical
}

enum HeistDefinitionMerger {
    static func merge(
        _ definitions: [HeistPlanAdmissionCandidate],
        duplicatePolicy: HeistDefinitionDuplicatePolicy
    ) -> [HeistPlanAdmissionCandidate] {
        merge(
            definitions,
            duplicatePolicy: duplicatePolicy,
            name: \.name,
            isNamespace: { $0.parameter == .none && $0.body.isEmpty && !$0.definitions.isEmpty },
            children: \.definitions,
            replacingChildren: { definition, children in
                HeistPlanAdmissionCandidate(
                    version: definition.version,
                    name: definition.name,
                    parameter: definition.parameter,
                    definitions: children,
                    body: definition.body
                )
            }
        )
    }

    static func merge(
        _ definitions: [HeistPlan],
        duplicatePolicy: HeistDefinitionDuplicatePolicy
    ) -> [HeistPlan] {
        merge(
            definitions,
            duplicatePolicy: duplicatePolicy,
            name: \.name,
            isNamespace: { $0.parameter == .none && $0.body.isEmpty },
            children: \.definitions,
            replacingChildren: { definition, children in
                HeistPlan(
                    runtimeValidatedVersion: definition.version,
                    name: definition.name,
                    parameter: definition.parameter,
                    definitions: children,
                    body: definition.body
                )
            }
        )
    }

    private static func merge<Definition: Equatable>(
        _ definitions: [Definition],
        duplicatePolicy: HeistDefinitionDuplicatePolicy,
        name: KeyPath<Definition, String?>,
        isNamespace: (Definition) -> Bool,
        children: KeyPath<Definition, [Definition]>,
        replacingChildren: (Definition, [Definition]) -> Definition
    ) -> [Definition] {
        definitions.reduce(into: []) { merged, definition in
            guard let definitionName = definition[keyPath: name],
                  let existingIndex = merged.firstIndex(where: { $0[keyPath: name] == definitionName })
            else {
                merged.append(definition)
                return
            }

            let existing = merged[existingIndex]
            if duplicatePolicy == .discardIdentical, existing == definition {
                return
            }
            guard isNamespace(existing), isNamespace(definition) else {
                merged.append(definition)
                return
            }
            merged[existingIndex] = replacingChildren(
                existing,
                merge(
                    existing[keyPath: children] + definition[keyPath: children],
                    duplicatePolicy: duplicatePolicy,
                    name: name,
                    isNamespace: isNamespace,
                    children: children,
                    replacingChildren: replacingChildren
                )
            )
        }
    }
}

public extension HeistPlan {
    func heistDefinition(at path: HeistDefinitionPath) -> HeistPlan? {
        let invocationPath = HeistInvocationPath(definitionPath: path)
        return HeistDefinitionScope(definitions: definitions).resolve(path: invocationPath)?.definition
    }
}

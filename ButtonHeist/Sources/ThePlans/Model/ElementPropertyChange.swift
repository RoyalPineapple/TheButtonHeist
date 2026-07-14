/// An authored property change that resolves references before evaluation.
public struct ElementPropertyChange: Codable, Sendable, Equatable {
    package let core: ElementPropertyChangeCore<Expr<String>>

    package init(core: ElementPropertyChangeCore<Expr<String>>) {
        self.core = core
    }

    public var property: ElementProperty { core.property }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementPropertyChange {
        ResolvedElementPropertyChange(core: try core.resolve(in: environment))
    }
}

/// The execution-phase property change. Its core contains plain `String`
/// leaves and cannot represent unresolved references.
public struct ResolvedElementPropertyChange: Codable, Sendable, Equatable {
    package let core: ElementPropertyChangeCore<String>

    package init(core: ElementPropertyChangeCore<String>) {
        self.core = core
    }

    public var property: ElementProperty { core.property }
}

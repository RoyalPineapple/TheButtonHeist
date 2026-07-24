/// An authored property change that resolves references before evaluation.
public struct ElementPropertyChange: Codable, Sendable, Equatable {
    package let value: AuthoredElementPropertyChange

    package init(value: AuthoredElementPropertyChange) {
        self.value = value
    }

    public var property: ElementProperty { value.property }

    package func resolve(in environment: HeistExecutionEnvironment) throws -> ResolvedElementPropertyChange {
        ResolvedElementPropertyChange(value: try value.resolve(in: environment))
    }
}

/// The execution-phase property change.
package struct ResolvedElementPropertyChange: Codable, Sendable, Equatable {
    package let value: ResolvedElementPropertyChangeValue

    package init(value: ResolvedElementPropertyChangeValue) {
        self.value = value
    }

    package var property: ElementProperty { value.property }
}

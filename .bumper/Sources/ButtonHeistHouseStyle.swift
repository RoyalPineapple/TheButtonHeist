import BumperBowlingCore

enum ButtonHeistComponent: String, CaseIterable {
    case plans
    case score
    case dsl
    case doctor
    case runtime
    case testing
    case tools
    case mcp
    case demo

    var id: ComponentID {
        guard let id = try? ComponentID(rawValue) else {
            preconditionFailure("Invalid component id: \(rawValue)")
        }
        return id
    }
}

extension ComponentID {
    static let plans = ButtonHeistComponent.plans.id
    static let score = ButtonHeistComponent.score.id
    static let dsl = ButtonHeistComponent.dsl.id
    static let doctor = ButtonHeistComponent.doctor.id
    static let runtime = ButtonHeistComponent.runtime.id
    static let testing = ButtonHeistComponent.testing.id
    static let tools = ButtonHeistComponent.tools.id
    static let mcp = ButtonHeistComponent.mcp.id
    static let demo = ButtonHeistComponent.demo.id
}

extension ComponentShape {
    static let buttonHeistValuePipeline = ComponentShape {
        DoesNotUse(.uiKit, .swiftUI, .persistence, .testing, severity: .error)
        DoesNotUse(
            "ArgumentParser",
            "MCP",
            "Network",
            "ObjectiveC",
            "AccessibilitySnapshotParser",
            severity: .error
        )
    }

    static let buttonHeistPureReducers = ComponentShape {
        Applies(.buttonHeistValuePipeline)
    }

    static let buttonHeistScoreContract = ComponentShape {
        DoesNotUse(.uiKit, .swiftUI, .persistence, .testing, severity: .error)
    }

    static let buttonHeistLiveRuntimeBoundary = ComponentShape {
        MayUse(.foundation, .uiKit, .swiftUI)
    }

    static let buttonHeistTestingBoundary = ComponentShape {
        MayUse(.foundation, .testing)
    }

    static let buttonHeistToolBoundary = ComponentShape {
        MayUse(.foundation)
    }

    static let buttonHeistMCPBoundary = ComponentShape {
        MayUse(.foundation)
    }

    static let buttonHeistDemoSurface = ComponentShape {
        MayUse(.foundation, .uiKit, .swiftUI)
    }
}

extension AssertionShape {
    static let buttonHeistGlobal = AssertionShape {
        DependencyBoundaries(.error)
        SingleOwner(.error)
        AcyclicDeclaredDependencies(.error)
    }
}

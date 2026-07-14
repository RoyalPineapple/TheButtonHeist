import BumperBowlingCore

enum ButtonHeistComponent: String, ComponentKey {
    case plans
    case score
    case dsl
    case doctor
    case runtime
    case testing
    case tools
    case mcp
    case demo
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

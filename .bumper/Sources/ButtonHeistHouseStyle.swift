import BumperBowlingCore

extension ComponentID {
    static let plans = checked("plans")
    static let score = checked("score")
    static let dsl = checked("dsl")
    static let doctor = checked("doctor")
    static let runtime = checked("runtime")
    static let testing = checked("testing")
    static let tools = checked("tools")
    static let mcp = checked("mcp")
    static let demo = checked("demo")

    private static func checked(_ rawValue: String) -> ComponentID {
        guard let id = try? ComponentID(rawValue) else {
            preconditionFailure("Invalid component id: \(rawValue)")
        }
        return id
    }
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

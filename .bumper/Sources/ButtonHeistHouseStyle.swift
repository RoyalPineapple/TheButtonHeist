import BumperBowlingCore

enum ButtonHeistComponent: String, ComponentKey {
    case plans
    case score
    case doctor
    case runtime
    case testing
    case tools
    case mcp
    case demo
}

extension ComponentShape {
    static let buttonHeistPlansBoundary = ComponentShape {
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

    static let buttonHeistScoreBoundary = ComponentShape {
        DoesNotUse(.uiKit, .swiftUI, .persistence, .testing, severity: .error)
    }
}

import BumperBowlingCore

let configuration = BumperConfiguration {
    Included {
        "ButtonHeist/Sources"
        "ButtonHeistCLI/Sources"
        "ButtonHeistMCP/Sources"
        "TestApp/Sources"
    }

    Excluded {
        ".build"
        "Derived"
        "DerivedData"
        "submodules"
        "tests/fixtures"
    }

    Architecture {
        Component(.plans) {
            Owns("ButtonHeist/Sources/ThePlans")
            Modules("ThePlans")
            Applies(.buttonHeistPureReducers)
        }

        Component(.score) {
            Owns("ButtonHeist/Sources/TheScore")
            Modules("TheScore")
            MayDependOn(.plans)
            Applies(.buttonHeistScoreContract)
        }

        Component(.dsl) {
            Owns("ButtonHeist/Sources/ButtonHeistDSL")
            Modules("ButtonHeistDSL")
            MayDependOn(.plans)
            Applies(.buttonHeistValuePipeline)
        }

        Component(.doctor) {
            Owns(
                "ButtonHeist/Sources/HeistDoctorCore",
                "ButtonHeist/Sources/HeistDoctorTool"
            )
            Modules("HeistDoctorCore", "HeistDoctorTool")
            MayDependOn(.plans, .score)
            Applies(.buttonHeistToolBoundary)
        }

        Component(.runtime) {
            Owns(
                "ButtonHeist/Sources/TheButtonHeist",
                "ButtonHeist/Sources/TheInsideJob",
                "ButtonHeist/Sources/ThePlant",
                "ButtonHeist/Sources/ButtonHeistSupport"
            )
            Modules("ButtonHeist", "TheInsideJob", "ThePlant", "ButtonHeistSupport")
            MayDependOn(.plans, .score)
            Applies(.buttonHeistLiveRuntimeBoundary)
        }

        Component(.testing) {
            Owns("ButtonHeist/Sources/ButtonHeistTesting")
            Modules("ButtonHeistTesting")
            MayDependOn(.plans, .dsl, .runtime)
            Applies(.buttonHeistTestingBoundary)
        }

        Component(.tools) {
            Owns(
                "ButtonHeist/Sources/HeistPlanTool",
                "ButtonHeistCLI/Sources"
            )
            Modules("HeistPlanTool", "ButtonHeistCLI")
            MayDependOn(.plans, .score, .doctor, .runtime)
            Applies(.buttonHeistToolBoundary)
        }

        Component(.mcp) {
            Owns("ButtonHeistMCP/Sources")
            Modules("ButtonHeistMCP")
            MayDependOn(.plans, .score, .runtime, .tools)
            Applies(.buttonHeistMCPBoundary)
        }

        Component(.demo) {
            Owns("TestApp/Sources")
            Modules("TestApp")
            MayDependOn(.plans, .score, .dsl, .runtime, .testing)
            Applies(.buttonHeistDemoSurface)
        }
    }

    Assertions {
        ApplyAssertions(.buttonHeistGlobal)
    }

    CustomRules()
}

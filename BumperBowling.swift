import BumperBowlingCore

let bumper = BumperProject {
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

    Architecture(ButtonHeistComponent.self) {
        Component(.plans) {
            Owns("ButtonHeist/Sources/ThePlans")
            Modules("ThePlans")
            Applies(.buttonHeistPlansBoundary)
        }

        Component(.score) {
            Owns("ButtonHeist/Sources/TheScore")
            Modules("TheScore")
            Applies(.buttonHeistScoreBoundary)
        }

        Component(.doctor) {
            Owns(
                "ButtonHeist/Sources/HeistDoctorCore",
                "ButtonHeist/Sources/HeistDoctorTool"
            )
            Modules("HeistDoctorCore", "HeistDoctorTool")
        }

        Component(.embeddedRuntime) {
            Owns(
                "ButtonHeist/Sources/TheInsideJob",
                "ButtonHeist/Sources/ThePlant"
            )
            Modules("TheInsideJob", "ThePlant")
        }

        Component(.client) {
            Owns("ButtonHeist/Sources/TheButtonHeist")
            Modules("ButtonHeist")
        }

        Component(.support) {
            Owns("ButtonHeist/Sources/ButtonHeistSupport")
            Modules("ButtonHeistSupport")
        }

        Component(.testing) {
            Owns("ButtonHeist/Sources/ButtonHeistTesting")
            Modules("ButtonHeistTesting")
        }

        Component(.tools) {
            Owns(
                "ButtonHeist/Sources/HeistPlanTool",
                "ButtonHeistCLI/Sources"
            )
            Modules("HeistPlanTool", "ButtonHeistCLI")
        }

        Component(.mcp) {
            Owns("ButtonHeistMCP/Sources")
            Modules("ButtonHeistMCP")
        }

        Component(.demo) {
            Owns("TestApp/Sources")
            Modules("TestApp")
        }
    }

    Rules {
        SingleOwner(.error)
        buttonHeistRules
    }
}

# Heist Lifecycle

Author-to-replay: how a heist written in Swift (or in the canonical DSL source form) becomes a validated plan, a portable `.heist` artifact, and finally a replayed run with a receipt. This diagram answers "where does my heist live at each stage, and where can it be rejected?"

**Illustrates:** [HEIST-FORMAT.md](../HEIST-FORMAT.md), [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [SWIFT-HEIST-AUTHORING.md](../SWIFT-HEIST-AUTHORING.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/Model/HeistPlan.swift`, `ButtonHeist/Sources/ThePlans/Compilation/HeistSwiftFileCompiler.swift`, `ButtonHeist/Sources/ThePlans/Parsing/HeistPlanSourceProgramParser.swift`, `ButtonHeist/Sources/ThePlans/Model/HeistArtifact.swift`, `ButtonHeist/Sources/ThePlans/Validation/HeistPlan+RuntimeValidation.swift`, `ButtonHeist/Sources/ThePlans/Validation/HeistPlan+RuntimeValidationAdmission.swift`, `ButtonHeist/Sources/ThePlans/Validation/HeistPlan+RuntimeValidationTraversal.swift`, `ButtonHeist/Sources/ThePlans/Validation/HeistPlan+Validation.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift`, `ButtonHeist/Sources/TheScore/Receipts/HeistExecutionResult.swift`

```mermaid
flowchart TD
    subgraph author["Authoring"]
        SWIFT["Swift DSL<br/>(ButtonHeistDSL result builders)"]
        SOURCE["canonical DSL source<br/>(compileHeistPlanSource)"]
    end

    subgraph ir["IR boundary — admission"]
        CANDIDATE["HeistPlanAdmissionCandidate<br/>decoded / parsed / built IR"]
        CHECKS["single semantic admission:<br/>rejectUnknownKeys at decode ·<br/>HeistCallGraph cycle rejection ·<br/>runtime safety limits"]
        PLAN["HeistPlan<br/>version · name · parameter ·<br/>definitions · body"]
        CANDIDATE --> CHECKS --> PLAN
    end

    HEIST[".heist package<br/>manifest.json + plan.json<br/>format com.royalpineapple.buttonheist.heist"]

    subgraph replay["Replay"]
        GATE["wire: exact buttonHeistVersion<br/>handshake gates every run"]
        BRAINS["TheBrains.executeHeistPlan<br/>in the app process"]
        RECEIPT["HeistExecutionResult<br/>outcome + per-step results + durationMs"]
        GATE --> BRAINS
        BRAINS --> RECEIPT
    end

    SWIFT --> CANDIDATE
    SOURCE --> CANDIDATE
    PLAN --> HEIST
    HEIST -- "run_heist via XCTest / CLI / MCP" --> GATE
    PLAN -- "direct run (runHeist, perform)" --> GATE
```

Notes:

- Both authoring frontends lower to `HeistPlanAdmissionCandidate`; one semantic admission constructs the validated `HeistPlan`. The runtime never compiles Swift. Live composition (heists assembled over an interactive session) enters the same IR boundary as hand-authoring.
- Admission is strict at the boundary: decoding rejects unknown keys with an explicit allowed list per step type, `HeistCallGraph` rejects any recursive definition cycle ("heist runs must not be recursive"), and `HeistPlanRuntimeSafetyLimits` caps plan size (see [totality.md](totality.md)).
- `.compositionQuality` and `.strictTest` lint consume an admitted `HeistPlan`; they are quality checks, not a second admission path.
- The `.heist` package is two JSON files: `manifest.json` (`format`, `formatVersion`, `planVersion`, `entry`, `producer`, `createdAt`) and `plan.json` (the IR, `HeistPlan.currentVersion = 1`), read and written by `HeistArtifactCodec`.
- Replay always crosses the wire contract: the exact `buttonHeistVersion` handshake gates the session before any plan runs, so a heist can never execute against a mismatched runtime.

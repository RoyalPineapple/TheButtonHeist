# Heist Lifecycle

Author-to-replay: how a heist written in Swift (or in the canonical DSL source form) becomes a validated plan, a portable `.heist` artifact, and finally a replayed run with a result. This diagram answers "where does my heist live at each stage, and where can it be rejected?"

**Illustrates:** [HEIST-FORMAT.md](../HEIST-FORMAT.md), [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [SWIFT-HEIST-AUTHORING.md](../SWIFT-HEIST-AUTHORING.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/Model/HeistContent.swift`, `ButtonHeist/Sources/ThePlans/Model/HeistPlan.swift`, `ButtonHeist/Sources/ThePlans/Compilation/HeistSwiftFileCompilation.swift`, `ButtonHeist/Sources/ThePlans/Parsing/HeistPlanSourceProgramParser.swift`, `ButtonHeist/Sources/ThePlans/Model/HeistArtifact.swift`, `ButtonHeist/Sources/ThePlans/Validation/HeistPlan+RuntimeValidationTraversal.swift`, `ButtonHeist/Sources/ThePlans/Validation/HeistPlan+Validation.swift`, `ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains+HeistExecution.swift`, `ButtonHeist/Sources/TheScore/Results/HeistResult.swift`, `ButtonHeist/Sources/TheScore/Reports/HeistResult+Report.swift`, `ButtonHeist/Sources/TheScore/Results/HeistResultRecording.swift`

```mermaid
flowchart TD
    subgraph author["Authoring"]
        SWIFT["Swift DSL<br/>(ThePlans result builders)"]
        SOURCE["canonical DSL source<br/>(compileHeistPlanSource)"]
        CONTENT["opaque HeistContent<br/>authoring fragment"]
        PARSE["lex and parse source"]
        SWIFT --> CONTENT
        SOURCE --> PARSE
    end

    subgraph ir["HeistPlan boundary — admission"]
        PLAN["HeistPlan<br/>version · name · parameter ·<br/>definitions · body"]
        CHECKS["one root admission:<br/>strict structural decode ·<br/>HeistCallGraph cycle rejection ·<br/>runtime safety limits"]
        PLAN --> CHECKS
    end

    HEIST[".heist package<br/>manifest.json + plan.json<br/>format com.royalpineapple.buttonheist.heist"]

    subgraph replay["Replay"]
        GATE["wire: exact buttonHeistVersion<br/>handshake gates every run"]
        BRAINS["TheBrains.executeHeistPlan<br/>in the app process"]
        RESULT["HeistResult<br/>semantic step tree + durationMs<br/>outcome derived from nodes"]
        REPORT["HeistReport.project(result:)<br/>one semantic interpretation"]
        RENDER["JSON · compact · human · JUnit<br/>render HeistReport"]
        RECORD{"recording mode accepts<br/>HeistResult.Outcome?"}
        RESULTFILE["recorded HeistResult<br/>JSON.gz"]
        GATE --> BRAINS
        BRAINS --> RESULT
        RESULT --> REPORT --> RENDER
        RESULT --> RECORD
        RECORD -->|yes| RESULTFILE
    end

    CONTENT --> PLAN
    PARSE --> PLAN
    CHECKS --> HEIST
    HEIST -- "run_heist via XCTest / CLI / MCP" --> GATE
    PLAN -- "direct run (runHeist, perform)" --> GATE
```

Notes:

- Swift authoring produces opaque `HeistContent`, while canonical source is lexed and parsed. Both construct one recursive `HeistPlan`, which performs structural admission at the root and delegates cross-tree checks to `HeistPlanRuntimeSafetyValidator`. The runtime never compiles Swift. Live composition (heists assembled over an interactive session) enters the same admission boundary as hand-authoring.
- Admission is strict at the boundary: decoding rejects unknown keys with an explicit allowed list per step type, `HeistCallGraph` rejects any recursive definition cycle ("heist runs must not be recursive"), and `HeistPlanRuntimeSafetyLimits` caps plan size (see [totality.md](totality.md)).
- `.compositionQuality` and `.strictTest` lint consume an admitted `HeistPlan`; they are quality checks, not a second admission path.
- The `.heist` package is two JSON files: `manifest.json` (`format`, `formatVersion`, `planVersion`, `entry`, `producer`, `createdAt`) and `plan.json` (the IR, `HeistPlan.currentVersion = 2`), read and written by `HeistArtifactCodec`.
- Replay always crosses the wire contract: the exact `buttonHeistVersion` handshake gates the session before any plan runs, so a heist can never execute against a mismatched runtime.
- `HeistResult` remains execution truth. `HeistReport.project(result:)`
  interprets it once, and every presentation boundary renders that report.
- Result recording reads `HeistResult.Outcome` directly. The recording mode and
  artifact filename do not introduce a second passed/failed status.

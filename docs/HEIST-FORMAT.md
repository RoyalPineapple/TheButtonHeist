# Heist Format

Button Heist has one authored language and one generated artifact format.

Humans and agents write ButtonHeist DSL. The runtime executes a validated
`HeistPlan`. A `.heist` path is a generated package directory that carries that
plan; it is not a hand-authored JSON file.

## File Roles

| Role | Meaning |
|------|---------|
| `.swift` | Full Swift source for reusable authored heists, tests, helpers, and local constants. |
| `plan` source string | ButtonHeist DSL source for MCP/CLI inline authoring. It is Swift-like, but accepts only the DSL constructs Button Heist can parse and render canonically. |
| `.heist` | Generated package artifact containing `manifest.json` and `plan.json`. Do not hand-author it. |
| `.json` | Raw `HeistPlan` JSON IR for internal diagnostics and generated tooling only. It is not public heist authoring input or a public artifact API. |

`run_heist` accepts ButtonHeist DSL source through `plan`, or a generated
`.heist` package through `path`. Public run input does not accept raw structured
JSON IR fields.

## Package Shape

A `.heist` path is a package directory:

```text
SearchFlow.heist/
  manifest.json
  plan.json
```

Plain JSON with a `.heist` extension is invalid. Generate a fresh `.heist`
package from Swift/DSL source when crossing public artifact boundaries.

## Manifest

`manifest.json` is the artifact envelope:

```json
{
  "createdAt": "2026-06-05T00:00:00Z",
  "entry": "purchaseFlow",
  "format": "com.royalpineapple.buttonheist.heist",
  "formatVersion": 1,
  "planVersion": 1,
  "producer": {
    "name": "buttonheist"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `entry` | `String` | Required non-empty root plan identity. Must equal `plan.json.name`. |
| `format` | `String` | Must be `com.royalpineapple.buttonheist.heist`. |
| `formatVersion` | `Int` | Package/container schema version. Current value is `1`. |
| `planVersion` | `Int` | Must match `plan.json.version`. Current value is `1`. |
| `producer` | `HeistArtifactProducer` | Tool that generated the artifact. |
| `createdAt` | `Date` | Artifact creation timestamp. |

`entry` is not a path, registry key, alias, import, or selector for arbitrary
definitions. It names the root `HeistPlan.name` stored in `plan.json`.
Parameterized definitions are reusable capabilities, not artifact entries; run
them from a root plan with `RunHeist("Name", argument)`.

The manifest does not contain app bundle IDs, step counts, screenshots,
accessibility evidence, repair provenance, trace IDs, target labels, command
lists, or source metadata. Those belong in `plan.json`, external evidence, or
future sidecars.

## Plan JSON

`plan.json` is the canonical generated `HeistPlan` value. It is storage, wire,
and internal IR. It is not the surface humans or agents should write by hand.

The wire contract is executable, not prose-only. Keep this document aligned
with:

- `ButtonHeist/Tests/ThePlansTests/HeistPlanWireContractTests.swift`
- `ButtonHeist/Tests/ThePlansTests/ThePlansBoundaryTests.swift`
- `ButtonHeist/Tests/TheScoreTests/HeistPlaybackTests.swift`

The root shape is:

```json
{
  "version": 1,
  "name": "purchaseFlow",
  "parameter": { "type": "none" },
  "definitions": [],
  "body": [
    {
      "type": "warn",
      "warn": { "message": "checkpoint" }
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | `Int` | Must match the supported `HeistPlan` version. |
| `name` | `String?` | Heist or definition name. Required for `.heist` root entries and stored definitions; optional for inline one-step plans. |
| `parameter` | `HeistParameter` | Optional reusable-heist parameter declaration. Omitted means no parameter. |
| `definitions` | `[HeistPlan]` | Local named reusable heist definitions. |
| `body` | `[HeistStep]` | Ordered list of typed heist steps. The body must be non-empty unless the plan only provides definitions. |

Unknown keys are rejected. There is no app identifier, source metadata, runtime
ID, capture-local element ID, geometry, or implicit viewport state in the root
plan contract.

## Authored Shape

Use DSL when explaining or authoring heists.

```swift
HeistPlan("purchaseFlow") {
    TypeText("milk", into: .label("Search"))
        .expect(.exists(.value("milk")), timeout: .seconds(2))

    Activate(.label("Milk"))
        .expect(.change(.screen()))

    WaitFor(.missing(.label("Loading")), timeout: .seconds(5))
        .else {
            Fail("Loading did not finish")
        }
}
```

The same primitives scale up without creating a second runtime:

```swift
HeistDef<String>("addToCart", parameter: "item") { item in
    TypeText(item, into: .label("Search"))
        .expect(.exists(.value(item)), timeout: .seconds(2))

    Activate(.label(item))
        .expect(.exists(.label("Cart")), timeout: .seconds(2))
}

HeistPlan("cartFlow") {
    ForEach(["Milk", "Eggs"]) { item in
        RunHeist("addToCart", item)
    }

    If {
        Case(.exists(.label("Checkout"))) {
            Activate(.label("Checkout"))
                .expect(.change(.screen()))
        }

        Else {
            Fail("Checkout unavailable")
        }
    }
}
```

Semantic ForEach binds a target expression, not a cached element handle:

```swift
ForEach(.matching(.label("Delete")), limit: 20) { target in
    Activate(target)
        .expect(.missing(target), timeout: .seconds(2))
}
```

At runtime each iteration re-resolves the target through the normal semantic
pipeline. The body receives no UIKit object, live geometry, runtime ID, capture
ID, or viewport handle.

## Rejected Historical Forms

These forms existed during the prototype phase and should not appear in public
docs, demos, or new fixtures:

- a tracked `.heist` file containing raw JSON instead of a package directory
- `target.matcher` or `matcher` target wrappers
- raw authored JSON examples that teach generated step names instead of DSL
- public source spellings that use internal payload keys instead of DSL targets
- viewport setup before semantic action as a durable heist step
- geometry, runtime IDs, capture-local IDs, or container names as semantic identity

The generated `plan.json` may contain internal wire names. Do not copy those
names into agent-facing examples. If a heist is meant for humans or agents to
edit, render it as canonical DSL.

## Runtime Contract

Normal heists express semantic intent and semantic outcomes. Button Heist owns
reveal, element inflation, settlement, live geometry, and diagnostics while the
plan runs.

Runtime validation rejects non-executable plans before dispatch: unresolved
refs, invalid payloads, oversized loops, excessive depth, noncanonical
commands, nested collection loops, and unknown fields.

Lint is separate quality guidance for authored or composed plans:

| Mode | Purpose |
|------|---------|
| `compositionQuality` | Warns when composed plans look like fragile transcripts. |
| `strictTest` | Fails missing expectations, mechanical commands, viewport/debug action steps, and empty branches. |

Lint returns structured findings with severity, step path, message, and a fix
suggestion. It does not replace runtime validation.

## Non-Goals

The durable heist AST is small on purpose. It does not support:

- arbitrary dynamic code execution over the wire
- unbounded loops, sleeps, retries, catch/recover, or arbitrary polling loops
- native Swift control flow as runtime control flow
- hidden pre-action viewport movement for semantic actions
- viewport/debug commands as durable semantic action steps
- generic variables or expression evaluation beyond typed string and target refs
- geometry, runtime IDs, capture-local IDs, or container names as durable selectors
- unknown JSON keys
- mechanical commands in strict semantic tests unless explicitly waived

## Live Composition

Live composition turns completed interactions and settled semantic evidence into
semantic action intent plus validated semantic expectation.

Rules:

- observation commands are scratchpad and add no steps
- wait is an assertion primitive and becomes a wait step
- failed actions add no steps
- unmet expectations add no steps
- direct viewport/debug commands add no steps
- scroll setup before semantic action adds no setup step
- coordinate gestures survive only when no semantic element intent exists
- composed heists should pass composition-quality lint

Composed and authored heists must not depend on scroll position, geometry,
runtime IDs, capture-local IDs, or container names as semantic identity. Direct
viewport/debug commands may use a current `containerName` while inspecting the
live interface, but those commands are not durable heist primitives.

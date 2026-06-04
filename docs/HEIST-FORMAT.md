# Heist Plan Format

**Extension**: `.heist`
**Encoding**: JSON (UTF-8)
**Current version**: `2`

A heist file stores a `HeistPlan`: the canonical runtime and wire contract for
semantic Button Heist tests. Swift DSL source, recorded heists, agent-authored
JSON, and playback all converge on this value.

The plan is not a transcript of viewport mechanics. Normal heists express
semantic intent and semantic outcomes; Button Heist owns reveal, actionability,
settlement, live geometry, and diagnostics at replay time.

## Structure

```json
{
  "version": 2,
  "name": "purchaseFlow",
  "parameter": { "type": "none" },
  "definitions": [],
  "body": []
}
```

| Field | Type | Description |
|-------|------|-------------|
| `version` | `Int` | Must match the supported `HeistPlan` version. |
| `name` | `String?` | Optional heist or definition name. Required for plans stored in `definitions`. |
| `parameter` | `HeistParameter` | Optional reusable-heist parameter declaration. Omitted means no parameter. |
| `definitions` | `[HeistPlan]` | Local named reusable heist definitions. |
| `body` | `[HeistStep]` | Ordered list of typed heist steps. The body must be non-empty unless the plan only provides definitions. |

Unknown keys are rejected. There is no app identifier, source metadata,
runtime ID, capture-local ID, scroll container handle, or stable viewport handle
in the plan contract.

## Definitions and Invocations

Definitions are named `HeistPlan` values stored inside another plan. They are
local to the containing plan and exported through that namespace only. There is
no import mechanism, global lookup table, remote lookup, or arbitrary Swift
source execution over the wire.

```json
{
  "version": 2,
  "name": "purchaseFlow",
  "definitions": [
    {
      "version": 2,
      "name": "LibraryScreen",
      "definitions": [
        {
          "version": 2,
          "name": "addToCart",
          "parameter": { "type": "strings", "name": "item" },
          "body": [
            {
              "type": "action",
              "action": {
                "command": {
                  "type": "activate",
                  "payload": { "label_ref": "item" }
                },
                "expectation": {
                  "predicate": { "type": "present", "element": { "label": "Cart" } },
                  "timeout": 2
                }
              }
            }
          ]
        }
      ],
      "body": []
    }
  ],
  "body": [
    {
      "type": "invoke",
      "invoke": {
        "path": ["LibraryScreen", "addToCart"],
        "argument": { "type": "strings", "value": "Milk" }
      }
    }
  ]
}
```

Lookup is explicit:

- `["LibraryScreen", "addToCart"]` can call a definition nested under `LibraryScreen`.
- `["addToCart"]` is valid only when the current definition scope defines `addToCart` directly.
- Duplicate names in the same `definitions` array are rejected.
- Recursion and invocation cycles are rejected by runtime admission.

Parameters are finite semantic values only:

| Type | Meaning |
|------|---------|
| `none` | No argument accepted. |
| `strings` | One or more strings. A single string encodes as one-value array semantics at execution. |
| `element_targets` | One or more semantic `ElementTarget` values. A single target encodes as one-value array semantics at execution. |

Arguments must match the target parameter type. String arguments may use
`value`, `value_ref`, or `values`; element-target arguments may use `target`,
`target_ref`, or `targets`. Refs are scoped names, not objects. They carry no
geometry, runtime ID, capture ID, or cached element.

## Step Types

Each step is a type-discriminated object with exactly one payload:

```json
{
  "type": "action",
  "action": {
    "command": {
      "type": "activate",
      "payload": { "label": "Delete" }
    },
    "expectation": {
      "predicate": {
        "type": "absent",
        "target": { "label": "Delete" }
      },
      "timeout": 2
    }
  }
}
```

Supported step types:

| Type | Payload key | Purpose |
|------|-------------|---------|
| `action` | `action` | Execute one command through the normal command pipeline. |
| `wait` | `wait` | Wait for one predicate until timeout. |
| `conditional` | `conditional` | Immediate settled-state branching. |
| `wait_for_cases` | `wait_for_cases` | Wait until one case predicate matches, or Else handles timeout. |
| `for_each_element` | `for_each_element` | Bounded loop over a semantic predicate match set. |
| `for_each_string` | `for_each_string` | Bounded loop over a finite string array. |
| `heist` | `heist` | Inline structural heist group executed through the same pipeline. |
| `invoke` | `invoke` | Call a local named definition with a typed argument. |
| `warn` | `warn` | Emit a non-failing report message. |
| `fail` | `fail` | Fail the heist with a message. |

## Actions And Expectations

An action step wraps a `ClientMessage` plus either an expectation or an explicit
expectation waiver:

```json
{
  "type": "action",
  "action": {
    "command": {
      "type": "type_text",
      "payload": {
        "text": "milk",
        "elementTarget": { "label": "Search" }
      }
    },
    "expectation": {
      "predicate": {
        "type": "present",
        "element": { "label": "Search", "value": "milk" }
      },
      "timeout": 5
    }
  }
}
```

Use `without_expectation` only when a semantic action has no durable semantic
outcome:

```json
{
  "type": "action",
  "action": {
    "command": {
      "type": "rotor",
      "payload": {
        "label": "Article",
        "rotor": "Headings",
        "direction": "next"
      }
    },
    "without_expectation": "Navigation cursor only"
  }
}
```

`expectation` and `without_expectation` are mutually exclusive.

## Element Targets

Semantic commands use `ElementTarget`. An element target is a predicate plus an
optional ordinal disambiguator:

```json
{ "label": "Delete", "traits": ["button"], "ordinal": 0 }
```

Target fields:

| Field | Type | Description |
|-------|------|-------------|
| `label` | `String` | Accessibility label exact match after normalization. |
| `identifier` | `String` | Accessibility identifier exact match after normalization. |
| `value` | `String` | Accessibility value exact match after normalization. |
| `traits` | `[String]` | Required semantic traits. |
| `excludeTraits` | `[String]` | Traits that must not be present. |
| `ordinal` | `Int` | 0-based index among predicate matches. Requires at least one predicate field. |

Ordinal is not durable identity. It only selects among the current semantic
match set at runtime. Normal semantic actions re-resolve targets through
Button Heist actionability; users do not move the viewport first or provide
viewport handles.

## Predicates

`AccessibilityPredicate` is the shared predicate vocabulary for waits,
expectations, conditionals, and semantic ForEach.

State predicates evaluate against one settled semantic observation:

```json
{ "type": "present", "element": { "label": "Home" } }
{ "type": "absent", "target": { "label": "Loading" } }
{ "type": "all", "states": [
  { "type": "present", "element": { "label": "Results" } },
  { "type": "absent", "element": { "label": "Loading" } }
] }
```

Change predicates evaluate against settled transition evidence:

```json
{ "type": "screen_changed" }
{ "type": "screen_changed", "where": { "type": "present", "element": { "label": "Home" } } }
{ "type": "elements_changed" }
{ "type": "element_appeared", "element": { "label": "Toast" } }
{ "type": "element_disappeared", "element": { "label": "Delete" } }
{ "type": "element_updated", "element": { "label": "Search" }, "property": "value", "to": "milk" }
```

State predicates do not contain change predicates. Change predicates are not
search selectors; they require event or action-result delta evidence.

## Waits

Single predicate wait:

```json
{
  "type": "wait",
  "wait": {
    "predicate": { "type": "present", "element": { "label": "Home" } },
    "timeout": 5
  }
}
```

Branching wait:

```json
{
  "type": "wait_for_cases",
  "wait_for_cases": {
    "timeout": 8,
    "cases": [
      {
        "predicate": { "type": "present", "element": { "label": "Home" } },
        "body": [{ "type": "warn", "warn": { "message": "Logged in" } }]
      }
    ],
    "else_body": [{ "type": "fail", "fail": { "message": "No known result" } }]
  }
}
```

Timeout without Else fails. Else handles timeout.

## Conditionals

Conditionals evaluate immediately against the current settled semantic state.
The first matching case wins; no match without Else is a no-op.

```json
{
  "type": "conditional",
  "conditional": {
    "cases": [
      {
        "predicate": { "type": "present", "element": { "label": "Login" } },
        "body": [{ "type": "warn", "warn": { "message": "Login visible" } }]
      }
    ],
    "else_body": [{ "type": "fail", "fail": { "message": "Unknown state" } }]
  }
}
```

## Semantic ForEach

Semantic ForEach evaluates a predicate match set, enforces a bounded limit, and
executes its body through the normal heist pipeline. It is a durable AST node,
not native Swift loop expansion.

```swift
ForEach(.matching(.label("Delete")), limit: 20) { target in
  Activate(target)
    .expect(.absent(target), timeout: .seconds(2))
}
```

Wire shape:

```json
{
  "type": "for_each_element",
  "for_each_element": {
    "matching": { "label": "Delete" },
    "limit": 20,
    "parameter": "target",
    "body": [
      {
        "type": "action",
        "action": {
          "command": {
            "type": "activate",
            "payload": { "target_ref": "target" }
          },
          "expectation": {
            "predicate": {
              "type": "absent",
              "target_ref": "target"
            },
            "timeout": 2
          }
        }
      }
    ]
  }
}
```

At runtime each iteration computes
`ElementTarget.predicate(matching, ordinal: index)`, binds it to the target
reference, and executes the body steps. The body does not receive cached
geometry, UIKit objects, or a capture-local handle. Nested collection ForEach
is rejected by runtime admission.

String-array ForEach serializes as `for_each_string`:

```json
{
  "type": "for_each_string",
  "for_each_string": {
    "values": ["Milk", "Eggs"],
    "parameter": "item",
    "body": [
      {
        "type": "action",
        "action": {
          "command": {
            "type": "type_text",
            "payload": {
              "text_ref": "item",
              "target": { "label": "Add item" }
            }
          },
          "expectation": {
            "predicate": {
              "type": "present",
              "element": { "label_ref": "item" }
            },
            "timeout": 2
          }
        }
      }
    ]
  }
}
```

## Inline Heists and Invocations

Inline heists group steps structurally while preserving the same execution
pipeline:

```json
{
  "type": "heist",
  "heist": {
    "version": 2,
    "name": "checkoutGroup",
    "body": [
      {
        "type": "action",
        "action": {
          "command": { "type": "activate", "payload": { "label": "Checkout" } },
          "expectation": { "predicate": { "type": "screen_changed" }, "timeout": 2 }
        }
      }
    ]
  }
}
```

Invocations call local definitions by explicit path:

```json
{
  "type": "invoke",
  "invoke": {
    "path": ["LibraryScreen", "addToCart"],
    "argument": { "type": "strings", "value": "Milk" }
  }
}
```

Invocation execution binds the argument to the definition parameter in the
heist execution environment, then executes the definition body through the
normal heist pipeline. Reports preserve the invocation boundary and child step
results. A failed invocation stops its caller unless the caller's control flow
handles the failure explicitly.

## Mechanical And Viewport Escape Hatches

Mechanical gestures and viewport movement are explicit escape hatches. They are
valid plan actions, but strict semantic-test validation flags them.

Coordinate gesture:

```json
{
  "type": "action",
  "action": {
    "command": {
      "type": "one_finger_tap",
      "payload": { "point": { "x": 120, "y": 400 } }
    },
    "without_expectation": "Canvas coordinate interaction"
  }
}
```

Viewport movement:

```json
{
  "type": "action",
  "action": {
    "command": {
      "type": "scroll",
      "payload": { "direction": "down" }
    },
    "without_expectation": "Explicit viewport inspection"
  }
}
```

Semantic actions do not require `scroll_to_visible` before they run. Recording
drops pre-action viewport movement when a semantic action intent can be
derived.

## Runtime Admission And Lint

Runtime admission is the hard execution preflight. It rejects non-executable
plans before any action dispatch: unresolved refs, invalid payloads, oversized
loops, excessive depth, noncanonical commands, and nested collection loops.

Lint is quality guidance for authored or recorded tests:

| Mode | Purpose |
|------|---------|
| `recordingQuality` | Warns when recordings look like fragile transcripts. |
| `strictTest` | Fails missing expectations, mechanical commands, pre-action viewport movement, and empty branches. |

Lint returns structured findings with severity, step path, message, and a fix
suggestion. It does not replace runtime admission.

## Intentional Non-Goals

The durable heist AST is small on purpose. It does not support:

- unbounded loops, sleeps, retries, catch/recover, or arbitrary polling loops
- preserving native Swift `for` loops as runtime loops
- hidden pre-action viewport movement for semantic actions
- arbitrary dynamic code or source execution over the wire
- generic variables or expression evaluation beyond typed string and target refs
- geometry, runtime IDs, capture-local IDs, or scroll container handles as
  durable selectors
- unknown JSON keys
- mechanical commands in strict semantic tests unless explicitly waived

## Recording Contract

Recording composes completed interactions and settled semantic evidence into
semantic action intent plus validated semantic expectation.

See [Recording Contract](RECORDING-CONTRACT.md) for the focused recording
rules.

Rules:

- Read commands are scratchpad and record no steps.
- Failed actions record no steps.
- Unmet expectations record no steps.
- Scroll setup before semantic action records no setup step.
- Coordinate gestures survive only when no semantic element intent exists.
- Recorded heists should pass recording-quality lint.

Recorded heists must not depend on scroll position, geometry, runtime IDs,
capture-local IDs, or public container handles unless the command is explicitly
mechanical or viewport-shaped.

# Heist language spec

This document defines the public Button Heist authoring boundary.

## Durable boundary

`HeistPlan` is the durable DSL artifact boundary. A behavior that must survive
storage, `.heist` packaging, catalog discovery, MCP composition, canonical
rendering, or replay MUST be represented as a validated `HeistPlan`.

Durable heists MAY be authored through canonical ButtonHeist source, trusted
local Swift DSL that compiles to a `HeistPlan`, or generated `.heist` artifacts.
The durable artifact format is described in [Heist format](HEIST-FORMAT.md).

Runtime wire IR is internal and generated. Raw `version`/`name`/`parameter`/
`definitions`/`body` JSON MUST NOT be used as the human or agent authoring
language.

## Execution entry points

`run_heist` MUST accept durable plans only. Public callers SHOULD pass one of:

- canonical ButtonHeist source whose top level is a `HeistPlan`
- a generated `.heist` artifact path

CLI tools MAY accept trusted local Swift source as an authoring frontend, but
they MUST compile it to a validated `HeistPlan` before using the ordinary
runtime path.

`perform(step:)` MUST accept exactly one durable DSL step. It MAY run one action
statement or one `WaitFor(...)` statement for immediate client interaction. It
MUST reject `HeistPlan`, `HeistDef`, `RunHeist`, `If`, `ForEach`, multi-step
source, raw wire IR, and direct viewport/debug/session command text.

## Direct client commands

Viewport, debug, observation, and session commands are direct client commands.
They are useful for inspecting the live app, selecting the current session,
capturing pixels, or moving diagnostic viewport state. They are not Button Heist
DSL.

Direct client commands MUST NOT appear in `HeistPlan` source, `.heist`
artifacts, reusable heist definitions, or canonical DSL examples. Live
composition MAY use them as scratchpad observations, but they MUST add no
durable steps.

Direct client commands MAY use live container or viewport context while
inspecting the current interface. Those live names and positions are client
context only; they MUST NOT be promoted into durable selectors.

## Selector durability

Durable selectors describe semantic element identity, not a captured screen
instance. A selector is durable when it is built from Button Heist element
predicates that can be re-resolved after storage, packaging, canonical
rendering, and replay.

The durable selector forms are:

- exact labels and structured label predicates, such as `.label("Pay")`,
  `.label(.prefix("Delete"))`, or `.element(.label(.contains("Search")))`
- accessibility identifiers, such as `.identifier("pay_button")`
- values, when the value is intentionally part of the element's stable semantic
  identity or state assertion
- trait-constrained element selectors, such as
  `.element(.label("Pay"), .traits([.button]))`
- ordinal disambiguation only when attached to a semantic base selector, such as
  `.target(.element(.label("Delete"), .traits([.button])), ordinal: 1)`

Copyable durable selector examples:

```swift
Activate(.label("Pay"))

Activate(.identifier("pay_button"))

Activate(.element(.label("Pay"), .traits([.button])))

Activate(.target(.element(.label("Delete"), .traits([.button])), ordinal: 1))

WaitFor(.element(.label("Total"), .value("$12.00")), timeout: .seconds(2))
```

The following forms are not durable selector or context identity:

- index-only selectors, including ordinals with no semantic base selector
- viewport position, screen location, scroll offset, or visible-row position
- current focus
- runtime IDs
- capture-local IDs
- generated container names
- raw coordinate identity

Ordinal is a disambiguator over the current match set for a semantic selector.
It is not durable identity by itself. Coordinate gestures may be explicit
mechanical actions, but coordinates do not identify semantic elements and MUST
NOT be taught as durable selector examples.

Once code-level selector validation exists, durable plan admission MUST reject
plans that depend on non-durable selector identity. Until then, these forms are
excluded by this specification, and lint, canonicalization, documentation, and
generated examples MUST NOT present them as durable selector patterns.

## Durable DSL examples

Use `HeistPlan` for reusable or multi-step behavior:

```swift
HeistPlan("checkout") {
    Activate(.label("Pay"))
        .expect(.change(.screen()))

    WaitFor(.label("Receipt"), timeout: .seconds(10))
}
```

Use `perform(step:)` for one durable step:

```swift
Activate(.label("Pay"))
    .expect(.change(.screen()))
```

Use definitions and composition inside a durable plan:

```swift
HeistPlan("cart") {
    HeistDef<String>("Cart.addItem", parameter: "item") { item in
        TypeText(item, into: .label("Search Items"))
            .expect(.exists(.element(.label("Search Items"), .value(item))))

        Activate(.label(item))
            .expect(.appeared(.label("Cart")))
    }

    RunHeist("Cart.addItem", "Milk")
}
```

## Authoring rules

Durable heist source MUST use Button Heist DSL constructs: actions, targets,
expectations, expectation waivers, `WaitFor`, `If`, `Case`, `Else`, `ForEach`,
`RunHeist`, `HeistDef`, `Warn`, and `Fail`.

Durable heist source MUST NOT depend on viewport position, current pixels,
runtime IDs, capture-local IDs, generated container names, or session state as
semantic identity.

Agents SHOULD author or exchange canonical DSL source unless they are passing a
generated `.heist` artifact. Authors SHOULD keep direct client commands outside
durable examples so examples can be copied into `run_heist` without changing the
language boundary.

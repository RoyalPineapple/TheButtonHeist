# Heist language spec

This document defines the public Button Heist authoring boundary.

## Durable boundary

`HeistPlan` is the durable DSL artifact boundary. A behavior that must survive
storage, `.heist` packaging, catalog discovery, MCP composition, canonical
rendering, or replay MUST be represented as a validated `HeistPlan`.

Durable heists MAY be authored through canonical ButtonHeist source, trusted
local Swift DSL that compiles to a `HeistPlan`, or generated `.heist` artifacts.
The durable artifact format is described in [Heist format](HEIST-FORMAT.md).
The authoring surface — step types, passables, target forms, and the concrete
predicate grammar — is drawn in the
[DSL grammar diagram](diagrams/dsl-grammar.md); the termination guarantees are
drawn in the [totality diagram](diagrams/totality.md).

Runtime wire IR is internal and generated. Raw `version`/`name`/`parameter`/
`definitions`/`body` JSON MUST NOT be used as the human or agent authoring
language.

## Path grammar

Heist plan names and reference names are distinct typed currencies over one
exact identifier grammar. `HeistPlanName` names a root plan or one local
definition; `HeistReferenceName` names a parameter or expression reference.
`HeistDefinitionPath` names where a reusable definition is declared;
`HeistInvocationPath` names the capability a `RunHeist` step invokes. The two
path types remain distinct even though both delegate to one canonical path
grammar. A heist path is a non-empty dot-separated list of plan-name
components:

```text
heist-path = identifier ("." identifier)*
identifier = letter-or-underscore (letter-or-digit-or-underscore)*
```

Identifiers are admitted without trimming or repair. They and path components
MUST NOT be empty, contain whitespace, contain punctuation other
than the dot separator, start with a digit, or use Swift reserved words.
`Cart.checkout` is valid. `Cart..checkout`, `.checkout`, `Cart.`,
`Cart Screen.checkout`, `1Cart.checkout`, and `Cart.class` are invalid.

Swift string literals are contextual authoring sugar because all three types
conform to `ExpressibleByStringLiteral`; the resulting value is still typed.
Dynamic source, JSON, and CLI text MUST enter through the role type's throwing
validating initializer at that boundary. Public plan APIs do not accept raw-string paths,
component arrays, aliases, or alternate spellings. All three types use
single-value string encoding, so generated JSON stores a name or dotted path as
one string rather than exposing component bookkeeping.

## Execution entry points

`run_heist` MUST accept durable plans only. Public callers SHOULD pass one of:

- canonical ButtonHeist source whose top level is a `HeistPlan`
- a generated `.heist` artifact path

CLI tools MAY accept trusted local Swift source as an authoring frontend, but
they MUST compile it to a validated `HeistPlan` before using the ordinary
runtime path.

`perform(step:)` MUST accept exactly one durable DSL step. It MAY run one action
statement or one `WaitFor(...)` statement for immediate client interaction. It
MUST reject `HeistPlan`, `HeistDef`, `RunHeist`, `If`, `ForEach`, `RepeatUntil`,
multi-step source, raw wire IR, direct viewport/debug/session command text, and
`WaitFor(...).else { ... }`. Branching or composition belongs behind
`run_heist`.

## Compilation and validation

Canonical ButtonHeist source and trusted local Swift DSL are authoring
frontends, not executable products. Both frontends MUST lower through the same
semantic validation boundary before producing a durable `HeistPlan`.

The checked-plan pipeline is:

1. Parse or build syntax into an admission candidate.
2. Validate syntax-local contracts such as typed paths, supported step shapes,
   parameter names, and expectation composition.
3. Run semantic validation for duplicate sibling definitions, unresolved
   `RunHeist` targets, argument arity/type mismatches, unsupported recursion,
   non-durable actions, bounded loops, bounded nesting, and payload contracts.
4. Admit only a validated `HeistPlan` to storage, catalog discovery, rendering,
   replay, or execution.

`validate_heist` exposes this admission boundary without opening a device
connection or creating a session. It accepts exactly one canonical source:
inline ButtonHeist `plan` text or a generated `.heist` `path`. It separately
reports plan admission, root invocation argument validity, and optional lint.
An invalid candidate is a successful validation response with
`admissible: false`; malformed command arguments remain request errors.

Validation cannot prove that a live accessibility target exists or that an
expectation will be satisfied. `run_heist` MUST repeat admission at execution
time rather than trusting an earlier validation report.

The full author-to-replay pipeline, including where admission can reject, is
drawn in the [heist lifecycle diagram](diagrams/heist-lifecycle.md).

Invalid syntax MUST NOT become a different valid program. In particular,
invalid dotted paths MUST NOT be repaired by dropping empty components or
otherwise canonicalizing user input.

## Diagnostics

Diagnostics are part of the public language contract. Each diagnostic MUST
include a stable code, title, phase, message, and actionable hint when a useful
repair exists. Source compilation diagnostics SHOULD include a source span with
source name, line, column, byte offset, and token length.

Representative stable codes:

- `heist.dsl.invalid_definition`: invalid `HeistDef` path or definition shape
- `heist.dsl.invalid_invocation_path`: invalid `RunHeist` path
- `heist.dsl.invalid_invocation_expectation`: invalid `RunHeist(...).expect`
  composition
- `heist.source.invalid_syntax`: unsupported or malformed source syntax
- `heist.plan.runtime_safety`: semantic validation failure
- `heist.plan.non_durable_action`: direct client command admitted into durable
  DSL

For the same invalid authoring shape, canonical source and Swift DSL builder
diagnostics SHOULD share the same code, title, message, path, and hint. Their
phases and source spans may differ because they originate from different
frontends.

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

## Target durability

`AccessibilityTarget` is the one target language for actions, wait and action
expectations, control-flow predicates, CLI/MCP arguments, and `get_interface`
subtree queries. Durable targets describe semantic
accessibility-node identity, not a captured screen instance. A target is durable
when it can be re-resolved after storage, packaging, canonical rendering, and
replay. How a target resolves at runtime — exact-or-miss matching, ordinals,
container scope, and diagnostics — is drawn in the
[element inflation diagram](diagrams/element-inflation.md).

The durable target forms are:

- exact labels and structured label predicates, such as `.label("Pay")`,
  `.label(.prefix("Delete"))`, or `.element(.label(.contains("Search")))`
- accessibility identifiers, such as `.identifier("pay_button")`
- values, when the value is intentionally part of the element's stable semantic
  identity or state assertion
- trait-constrained element selectors, such as
  `.element(.label("Pay"), .traits([.button]))`
- container selectors such as `.container(.identifier("Checkout"))`; an
  identifier can match any delivered parser container type, not only a semantic
  group
- descendant scope such as
  `.within(container: .identifier("Checkout"), .label("Pay"))`
- ordinal disambiguation only when attached to a semantic base selector, such as
  `.target(.element(.label("Delete"), .traits([.button])), ordinal: 1)`

Copyable durable selector examples:

```swift
Activate(.label("Pay"))

Activate(.identifier("pay_button"))

Activate(.element(.label("Pay"), .traits([.button])))

Activate(.target(.element(.label("Delete"), .traits([.button])), ordinal: 1))

WaitFor(.exists(.element(.label("Total"), .value("$12.00"))), timeout: 2)
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

## String matching and normalization

Element string predicates (`label`, `identifier`, `value`) match **exact or
miss**. Exact means case-insensitive equality after typography folding, and
the same comparison runs on the client and in the app server:

- Typographic characters with an ASCII equivalent fold before comparison:
  curly single and double quotes fold to `'` and `"`, the hyphen/dash family
  (including en dash, em dash, and minus sign) folds to `-`, the ellipsis
  character folds to `...`, and non-breaking or typographic spaces fold to a
  plain space.
- Everything else passes through unchanged: emoji, accented characters, and
  non-Latin scripts are compared as written.
- Case comparison is locale-aware case-insensitive equality.

There is no substring fallback. When an exact predicate misses, the resolver
returns structured diagnostics with near-miss suggestions; it never silently
widens the match. Broad matching is explicit and opt-in: `.contains`,
`.prefix`, and `.suffix` apply the same normalization and require non-empty
patterns. `StringMatch` is expressible by string literal, so a string passed to
a matcher-bearing API means `.exact(string)`. Expression storage and resolved
matcher types are implementation details, not authored API.

## Accessibility predicate grammar

`AccessibilityPredicate` is the concrete root condition. `ChangeDeclaration`
provides two concrete assertion contexts whose constructors expose only valid
combinations:

- Root: `.exists(target)`, `.missing(target)`, `.changed(declaration)`,
  `.noChange`, and `.announcement(...)`.
- Screen declaration: `.changed(.screen([.exists(target),
  .missing(target)]))`.
- Elements declaration: `.changed(.elements([.exists(target),
  .missing(target), .appeared(target), .disappeared(target),
  .updated(target, change)]))`.

`exists` and `missing` always read the current delivered interface tree. They
use the same `AccessibilityTarget` resolution as actions and subtree queries,
including element, container-only, and descendant-scoped targets. `appeared`,
`disappeared`, and `updated` read the ordered temporal fact stream. There is no
root-level generic changed predicate and no alternate spelling.

A screen boundary is also an element lifecycle change: every old-tree node
disappears, the screen marker occurs, and every new-tree node appears. Therefore
`changed(.elements(...))` can match appearances or disappearances across a
screen boundary. `updated` can only match two captures in the same screen
generation.

`.noChange` requires a complete observation window with no facts. Notification
ingress is retained and cursor-backed; checkpoints do not consume events.
Screen, layout, value, and announcement notifications are edge evidence and
prevent `noChange`. A transition assertion never passes solely because its
implied final state is true.

## Timeouts

Every timeout in the language is a `Double` in **seconds**. DSL source spells
fixed timeouts as bare numeric literals; generated plan JSON carries the same
value as a bare number of seconds. Runtime Swift code constructing a dynamic
timeout uses `try WaitTimeout.seconds(_:)` or
`try WaitTimeout.milliseconds(_:)`. Timeouts MUST be finite and positive.

| Site | Default | Notes |
|------|---------|-------|
| `WaitFor(_, timeout:)` | 30 seconds | Standalone waits and `WaitFor(...).else` gates. |
| Action `.expect(_, timeout:)` | 1 second | How long an action expectation polls accumulated settled evidence before reporting the expectation unmet. |
| `RepeatUntil(_, timeout:)` | none — required | The mandatory bound for a predicate only the run can decide. Runtime validation caps it at 30 seconds. |

Settlement has its own clock, separate from these: the settle loop and its
5-second default hard timeout are defined in
[Scope and limits](SCOPE-AND-LIMITS.md).

## Validation bounds

Runtime admission enforces structural bounds so a durable plan stays a bounded
recording. Current limits: 500 total steps, nesting depth 16, 100 values per
string `ForEach`, a maximum `limit` of 100 per element `ForEach`, and 250
definitions per plan. Plans that exceed a bound are rejected at admission with
a diagnostic, not truncated. Collection `ForEach` loops MUST NOT contain another
collection `ForEach` loop, directly or through expanded `RunHeist` bodies.

## Durable DSL examples

Use `HeistPlan` for reusable or multi-step behavior:

```swift
HeistPlan("checkout") {
    Activate(.label("Pay"))
        .expect(.changed(.screen([.exists(.label("Receipt"))])))

    WaitFor(.exists(.label("Receipt")), timeout: 10)
}
```

Use `perform(step:)` for one durable step:

```swift
Activate(.label("Pay"))
    .expect(.changed(.screen([.exists(.label("Receipt"))])))
```

`WaitFor(...)` evaluates the same predicate language as action expectations.
Current-tree predicates pass when the current delivered tree satisfies them.
Change declarations require observed facts; standalone waits do not infer an
appearance, disappearance, or update from final state.

Container presence is a current-tree predicate, not a transition predicate. Use
`.exists(.container(.identifier("Checkout")))` when a heist needs to assert that the
current settled hierarchy contains a matching container without
requiring a preceding screen-change fact. Container predicates can match
semantic-group label and value, identifier on any container, role shorthands
such as `.list` or `.dataTable(rowCount: .init(...), columnCount: .init(...))`,
scrollability through `.scrollable(true)`, custom
actions, modal boundary, or `.matching(...)` combinations. Use
`.within(container: .label("Checkout"), .label("Pay"))` when an element target
must resolve inside that container. Use `.changed(.screen())` when the action
itself must prove navigation occurred.

Use `RepeatUntil` for bounded repetition toward a settled outcome. The body
repeats until the predicate holds against settled state or the mandatory
timeout elapses; the optional lowercase `.else { ... }` body runs when the
timeout wins:

```swift
RepeatUntil(.exists(.label("Inbox empty")), timeout: 10) {
    Activate(.label("Delete"))
}
.else {
    Fail("Inbox never emptied")
}
```

`RepeatUntil` has no default timeout: the timeout is the totality guarantee for
a predicate only the run can decide, so authors MUST write one. A timeout of
`0` checks the predicate once and runs no bodies before the else path. Without
an `.else` body, an elapsed timeout fails the step with the receipt.

Use definitions and composition inside a durable plan:

```swift
HeistPlan("cart") {
    HeistDef<String>("Cart.addItem", parameter: "item") { item in
        TypeText(item, into: .label("Search Items"))
            .expect(.exists(.element(.label("Search Items"), .value(item))))

        Activate(.label(item))
            .expect(.changed(.elements([.appeared(.label("Cart"))])))
    }

    RunHeist("Cart.addItem", "Milk")
}
```

## Authoring rules

Durable heist source MUST use Button Heist DSL constructs: actions, targets,
expectations, expectation waivers, `WaitFor`, `RepeatUntil`, `If`, `Case`,
`Else`, `ForEach`, `RunHeist`, `HeistDef`, `Warn`, and `Fail`.

Durable heist source MUST NOT depend on viewport position, current pixels,
runtime IDs, capture-local IDs, generated container names, or session state as
semantic identity.

Agents SHOULD author or exchange canonical DSL source unless they are passing a
generated `.heist` artifact. Authors SHOULD keep direct client commands outside
durable examples so examples can be copied into `run_heist` without changing the
language boundary.

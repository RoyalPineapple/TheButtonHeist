# Bumper Bowling Rules

Button Heist uses Bumper Bowling only for repository-wide source invariants
that Swift, SwiftLint, and behavioral tests cannot express directly. SwiftPM
and Tuist own target dependencies, Swift access control owns private
construction, and tests own runtime and wire contracts.

Every retained rule below protects a current typed or capability boundary.
Rules that preserve an implementation helper, a deleted pipeline, or a state
that access control already makes unconstructible are intentionally absent.

## Architecture Scope

| Rule ID | Invariant | Repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `duplicate_ownership` | Every included path and module has one Button Heist component owner, so scoped rules have an unambiguous lane. | Remove the overlapping `Owns` or `Modules` declaration. | Verification: Bumper validates its component configuration before applying scoped rules. Delete when Bumper no longer uses component ownership for scoping. |
| `forbidden_import` | ThePlans and TheScore remain value layers. ThePlans excludes UI, persistence, testing, CLI, MCP, networking, Objective-C, and live accessibility parser authority; TheScore excludes UI, persistence, and testing authority. | Normalize boundary evidence into Button Heist values before it enters a value layer. | Verification: Bumper evaluates imports against the component shapes on every repository run. Delete an exclusion when the build graph makes that import impossible. |

The component declarations in `BumperBowling.swift` are a scoping map, not a
second dependency graph. Package manifests, Tuist projects, and compilation
remain authoritative for target dependencies and cycles.

## Typed Capability Boundaries

These rules operate on modules and components rather than exact implementation
files. Moving code inside its owning component does not change policy.

| Rule ID | Invariant | Repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.ui_framework_ownership` | UIKit and SwiftUI remain in runtime and demo components. | Perform UI work at the runtime or demo boundary and pass values inward. | Verification: focused valid and invalid import fixtures plus repository evaluation. Delete when target dependencies make these imports impossible elsewhere. |
| `buttonheist.network_framework_ownership` | Network.framework remains in runtime transport or TheScore's typed TLS boundary. | Move network authority to transport or TLS code and pass typed outcomes inward. | Verification: focused component mutation fixtures plus repository evaluation. Delete when the build graph encodes the same capability boundary. |
| `buttonheist.security_framework_ownership` | Security.framework remains in TheScore's TLS material boundary. | Keep key material conversion in TheScore and expose typed values. | Verification: focused component mutation fixtures plus repository evaluation. Delete when Security is isolated in a dedicated target. |
| `buttonheist.objective_c_framework_ownership` | Objective-C runtime authority remains in the runtime component. | Keep private-SPI and method-override work behind the runtime boundary. | Verification: focused component mutation fixtures plus repository evaluation. Delete when the bridge is isolated in an inaccessible target. |
| `buttonheist.accessibility_parser_ownership` | Live accessibility parser, Core, and preview authority remains in the runtime component. | Parse live evidence in the runtime and pass semantic Button Heist values outward. | Verification: focused component mutation fixtures plus repository evaluation. Delete when parser products are inaccessible outside the runtime target. |

## User Accessibility

| Rule ID | Invariant | Repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.demo_accessibility_identifier` | Demo controls are discoverable through the semantics available to accessibility users, rather than test-only identifiers. Named SPI research fixtures remain exempt. | Improve the control's label, value, traits, hint, or actions. | Verification: standard `memberReferenceOwnership` with demo, research-fixture, and non-demo fixtures. Delete when demo and research targets split and the demo target cannot call the identifier API. |

## Typed Source Boundaries

These checks use lexical and explicit-type syntax only. They do not pretend to
resolve Swift types or infer runtime ownership.

| Rule ID | Invariant | Repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.any_boundary` | Production `Any` appears only in the three current Foundation and Objective-C boundary declarations and is normalized immediately. | Add a typed boundary value and convert the external object there. | Verification: invalid arbitrary API and valid named-boundary fixtures plus repository evaluation. Delete when Foundation exposes typed equivalents or the bridges move into isolated targets. |
| `buttonheist.callback_isolation` | Stored `onFoo` callback types declare `@Sendable` or a global actor, including file-local callback aliases. | State the callback's actor or Sendability contract in its type. | Verification: direct and aliased valid and invalid fixtures plus strict-concurrency compilation. Delete when Swift requires equivalent isolation for every stored callback shape. |
| `buttonheist.checked_concurrency` | Production code does not use `@preconcurrency` or `nonisolated(unsafe)` escape hatches. | Model actor isolation or Sendability explicitly. | Verification: focused attribute and modifier mutations plus repository evaluation. Delete when the compiler settings reject both forms directly. |

## Canonical Runtime Owners

This shaper guards a semantic effect boundary that Swift access control cannot
express across files in the runtime target.

| Rule ID | Invariant | Repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.semantic_observation_commit_ownership` | `Observation.Stream` is the only runtime caller that commits admissions through actor-owned `Observation.StoreOwner`, so graph, Log, lineage, and delivery order cannot be advanced by competing paths. | Commit admitted observations through the observation stream. | Verification: standard `boundaryOnly` with an invalid competing committer fixture and repository evaluation of the observation owner. Delete when Store commit becomes inaccessible outside the stream owner. |

## Plan Language Boundaries

These shapers preserve the public/package boundary after the compiler and
access-control model have rejected most invalid constructions. They use
Bumper's source queries and repository facts; no project syntax visitor
reparses or reinterprets Swift.

| Rule ID | Invariant | Repair | Verification and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.heist_content_opacity` | `HeistContent` is an opaque authoring fragment with no public stored builder bookkeeping. | Keep steps, nested definitions, and diagnostics internal to the result builder and construct a `HeistPlan` through its public initializer. | Verification: internal and public stored-property fixtures plus repository evaluation. Delete when `HeistContent` moves into an implementation-only module behind a public result-builder function. |
| `buttonheist.plan_else_ownership` | Only `WaitFor` and `IfContent` expose a DSL `else` branch. `RepeatUntil` timeout is failure, not an executable alternate body. | Model loop timeout behavior through wait predicates or surrounding conditionals instead of adding loop-local else bodies. | Verification: valid wait/conditional fixtures, invalid `RepeatUntil` fixture, and repository evaluation. Delete when Swift access control or separate modules make unsupported DSL `else` declarations unrepresentable. |
| `buttonheist.exported_tuple_return` | Functions, properties, subscripts, and protocol requirements with effective public, open, or package visibility use named contract types instead of multi-value tuples. Effective access includes visibility inherited from exported protocols, extensions, and enclosing declarations; explicitly private or internal members and local tuple scratch values remain permitted. | Introduce a named Swift type whose fields state the contract meaning, or narrow the declaration when it is not an exported contract. | Verification: one canonical rule reports explicit and inherited exported violations across every audited declaration form, with private, internal, local, and parenthesized controls plus repository evaluation. Delete when Swift provides a native lint for exported tuple contracts or the build graph isolates all package API behind generated interfaces. |

## Rule Lifecycle

A new blocking rule must demonstrate valid Swift that violates a durable
repository invariant, explain why the compiler, build graph, and tests cannot
own it, and include one valid and one invalid in-memory fixture. When a native
boundary makes the bad state unconstructible, delete the Bumper rule and its
fixture in the same change.

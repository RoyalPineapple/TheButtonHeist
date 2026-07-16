# Bumper Bowling Rules

Button Heist uses Bumper Bowling only for repository-wide source invariants
that Swift, SwiftLint, and behavioral tests cannot express directly. SwiftPM
and Tuist own target dependencies, Swift access control owns private
construction, and tests own runtime and wire contracts.

Every retained rule below protects a current typed boundary or canonical
owner. Rules that preserve an implementation helper, a deleted pipeline, or a
state that access control already makes unconstructible are intentionally
absent.

## Architecture Scope

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `duplicate_ownership` | Every included path and module has one Button Heist component owner, so scoped rules have an unambiguous lane. | Remove the overlapping `Owns` or `Modules` declaration. | Bumper validates its component configuration. Delete when Bumper no longer uses component ownership for scoping. |
| `forbidden_import` | ThePlans and TheScore remain value layers. ThePlans excludes UI, persistence, testing, CLI, MCP, networking, Objective-C, and live accessibility parser authority; TheScore excludes UI, persistence, and testing authority. | Normalize boundary evidence into Button Heist values before it enters a value layer. | Bumper evaluates component import facts. Delete an exclusion when the build graph makes the import impossible. |

The component declarations in `BumperBowling.swift` are a scoping map, not a
second dependency graph. Package manifests, Tuist projects, and compilation
remain authoritative for target dependencies and cycles.

## Typed Capability Boundaries

These rules operate on modules and components rather than exact implementation
files. Moving code inside its owning component does not change policy.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.ui_framework_ownership` | UIKit and SwiftUI remain in runtime and demo components. | Perform UI work at the runtime or demo boundary and pass values inward. | Focused valid and invalid import fixtures. Delete when target dependencies make the imports impossible elsewhere. |
| `buttonheist.network_framework_ownership` | Network.framework remains in runtime transport or TheScore's typed TLS boundary. | Move network authority to transport or TLS code and pass typed outcomes inward. | Focused component mutation fixtures. Delete when the build graph encodes the same capability boundary. |
| `buttonheist.security_framework_ownership` | Security.framework remains in TheScore's TLS material boundary. | Keep key material conversion in TheScore and expose typed values. | Focused component mutation fixtures. Delete when Security is isolated in a dedicated target. |
| `buttonheist.objective_c_framework_ownership` | Objective-C runtime authority remains in the runtime component. | Keep private-SPI and method-override work behind the runtime boundary. | Focused component mutation fixtures. Delete when the bridge is isolated in an inaccessible target. |
| `buttonheist.accessibility_parser_ownership` | Live accessibility parser, Core, and preview authority remains in the runtime component. | Parse live evidence in the runtime and pass semantic Button Heist values outward. | Focused component mutation fixtures. Delete when parser products are inaccessible outside the runtime target. |

## User Accessibility

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.demo_accessibility_identifier` | Demo controls are discoverable through the semantics available to accessibility users, rather than test-only identifiers. Named SPI research fixtures remain exempt. | Improve the control's label, value, traits, hint, or actions. | Standard `memberReferenceOwnership` with demo, research-fixture, and non-demo fixtures. Delete when demo and research targets split and the demo target cannot call the identifier API. |

## Typed Source Boundaries

These checks use lexical and explicit-type syntax only. They do not pretend to
resolve Swift types or infer runtime ownership.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.any_boundary` | Production `Any` appears only in the three current Foundation and Objective-C admission declarations and is normalized immediately. | Add a typed boundary value and convert the external object there. | Invalid arbitrary API plus valid named-boundary fixtures. Delete when Foundation exposes typed equivalents or the bridges move into isolated targets. |
| `buttonheist.callback_isolation` | Stored `onFoo` callback types declare `@Sendable` or a global actor, including file-local callback aliases. | State the callback's actor or Sendability contract in its type. | Direct and aliased valid and invalid fixtures plus strict-concurrency compilation. Delete when Swift requires equivalent isolation for every stored callback shape. |
| `buttonheist.checked_concurrency` | Production code does not use `@preconcurrency` or `nonisolated(unsafe)` escape hatches. | Model actor isolation or Sendability explicitly. | Focused attribute and modifier mutations plus repository lint. Delete when the compiler settings reject both forms directly. |

## Canonical Runtime Owners

These positive shapers name current owners. They do not ban old helper names or
preserve compatibility paths.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.predicate_wait_lifecycle_ownership` | `PredicateWait.swift` is the only production file that constructs `PredicateWaitLifecycleMachine`; all predicate waits use that lifecycle driver. | Add wait behavior as a lifecycle state, event, or effect and execute it through `PredicateWait`. | Standard `canonicalConstruction` with authorized and unauthorized construction fixtures. Delete when the machine initializer is inaccessible outside `PredicateWait`. |
| `buttonheist.interface_tree_element_matching_ownership` | Direct `InterfaceTree` element matching stays in `TheStash+Matching.swift` and is consumed by `TheStash+TargetResolution.swift`. | Resolve element targets through TheStash's canonical matching and target-resolution path. | Standard `boundaryOnly` with authorized and unauthorized call fixtures. Delete when the matching entry point is inaccessible outside those owners. |
| `buttonheist.interface_tree_container_matching_ownership` | Direct `InterfaceTree` container matching stays in `TheStash+Matching.swift` and is consumed by `TheStash+TargetResolution.swift`. | Resolve container targets through TheStash's canonical matching and target-resolution path. | Standard `boundaryOnly` with authorized and unauthorized call fixtures. Delete when the matching entry point is inaccessible outside those owners. |

## Rule Lifecycle

A new blocking rule must demonstrate valid Swift that violates a durable
repository invariant, explain why the compiler, build graph, and tests cannot
own it, and include one valid and one invalid in-memory fixture. When a native
boundary makes the bad state unconstructible, delete the Bumper rule and its
fixture in the same change.

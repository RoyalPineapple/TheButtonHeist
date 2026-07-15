# Bumper Bowling Rules

Button Heist uses Bumper Bowling only for repository-wide source invariants
that Swift, SwiftLint, and the test suite cannot express directly. SwiftPM and
Tuist own target dependencies, Swift access control owns construction, and
behavioral tests own runtime and wire contracts. Bumper does not prescribe
filenames, helper names, or implementation shape.

Every retained rule records its invariant, repair, proof, and deletion
condition below. Button Heist owns these policies; Bumper Bowling supplies the
generic facts, scopes, shapers, diagnostics, and test harness used to express
them.

## Architecture Scope

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `duplicate_ownership` | Every included path and module has one Button Heist component owner, so scoped rules have an unambiguous lane. | Remove the overlapping `Owns` or `Modules` declaration. | Bumper validates its component configuration. Delete when Bumper no longer uses path/module ownership for scoping. |
| `forbidden_import` | ThePlans and TheScore remain value layers: ThePlans excludes UI, persistence, testing, CLI, MCP, networking, Objective-C, and accessibility-parser authority; TheScore excludes UI, persistence, and testing authority. | Normalize boundary evidence into Button Heist values before it enters the value layer. | Bumper evaluates component import facts. Delete an exclusion when the corresponding build target cannot import that dependency. |

The component declarations in `BumperBowling.swift` are a scoping map, not a
second dependency graph. `Package.swift`, the Tuist projects, and compilation
are authoritative for allowed target dependencies and cycles.

## Framework Authority

These rules operate on modules and components rather than exact files. Moving
an implementation within its owning component does not change policy.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.ui_framework_ownership` | UIKit and SwiftUI remain in runtime and demo components. | Perform UI work at the runtime/demo boundary and pass values inward. | Focused valid/invalid import fixtures. Delete when target dependencies make the imports impossible elsewhere. |
| `buttonheist.network_framework_ownership` | Network.framework remains in runtime transport or TheScore's typed TLS boundary. | Move network authority to transport/TLS code and pass typed outcomes inward. | Focused component mutation fixture. Delete when the build graph encodes the same capability boundary. |
| `buttonheist.security_framework_ownership` | Security.framework remains in TheScore's TLS material boundary. | Keep key material conversion in TheScore and expose typed values. | Focused component mutation fixture. Delete when Security is isolated in a dedicated target. |
| `buttonheist.objective_c_framework_ownership` | Objective-C runtime authority remains in the runtime component. | Keep private-SPI and method-override work behind the runtime boundary. | Focused component mutation fixture. Delete when the bridge is isolated in a target inaccessible elsewhere. |
| `buttonheist.accessibility_parser_ownership` | Live accessibility parser/Core/preview authority remains in the runtime component; shared snapshot model values remain allowed at value boundaries. | Parse live evidence in the runtime and pass semantic Button Heist values outward. | Focused component mutation fixture. Delete when parser products are inaccessible outside the runtime target. |

## User Accessibility

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.demo_accessibility_identifier` | Demo controls are discoverable through labels, values, traits, hints, and actions rather than test-only identifiers. Named SPI research fixtures remain exempt. | Improve the control's real accessibility semantics. | Focused member-reference fixture plus repository lint. Delete when demo and research targets split and the demo target cannot call the identifier API. |

## Typed Source Boundaries

These checks use lexical and explicit-type syntax only. They do not pretend to
resolve Swift types or infer runtime ownership.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.any_boundary` | Production `Any` appears only in the three named Foundation/Objective-C admission declarations and is normalized immediately. | Add a typed boundary value and convert the external object there. | Invalid arbitrary API plus valid named-boundary fixtures. Delete when Foundation exposes typed equivalents or those bridges move into isolated targets. |
| `buttonheist.callback_isolation` | Stored `onFoo` callback types declare `@Sendable` or a global actor, including file-local callback aliases. | State the callback's actor or Sendability contract in its type. | Direct and aliased valid/invalid fixtures plus strict-concurrency compilation. Delete when Swift requires equivalent isolation for every stored callback shape. |

## Checked Concurrency

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.checked_concurrency` | Production code does not use `@preconcurrency` or broad `nonisolated(unsafe)` escape hatches. The private IOHID loader remains the sole narrow exception. | Model actor isolation or Sendability explicitly; isolate unavoidable private SPI behind its owner. | Focused attribute/modifier mutations plus repository lint. Delete when upstream SPI is concurrency-safe and the final exception disappears. |

## Retired Policy

Exact declaration filenames, constructor allowlists, compatibility-name bans,
explicit-access file lists, expression suffixes, folder import allowlists, and
recursive implementation policing are intentionally absent. Interface graph
construction and settled-observation admission now use inaccessible
constructors and proof types; remaining cross-file constructors are not
policed through filename lists. Durable observation values rely on `Sendable`
and strict concurrency rather than a blacklist of UIKit-looking type names.
Traversal, receipts, serialization, retries, and observation lifecycle remain
covered by behavioral, wire-contract, and reducer tests.

## Rule Lifecycle

A new blocking rule must demonstrate valid Swift that violates a durable
repository invariant, explain why the compiler/build graph/tests cannot own
it, and include one valid and one invalid in-memory fixture. When a native
boundary makes the bad state unconstructible, delete the Bumper rule and its
fixture in the same change.

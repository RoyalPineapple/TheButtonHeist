# Bumper Bowling Rules

Button Heist uses Bumper Bowling only for repository-wide source invariants
that Swift, SwiftLint, and the test suite cannot express directly. SwiftPM and
Tuist own target dependencies, Swift access control owns construction, and
behavioral tests own runtime and wire contracts. Bumper does not prescribe
filenames, helper names, or implementation shape except where a named currency
or cross-file owner is itself the durable invariant.

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

## Observation And Graph Pipeline

The stream owns observation history and publication. A narrow custom rule
protects the cross-file proof-to-graph relationship that the standard shapers
cannot express.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.semantic_observation_log_ownership` | `SemanticObservationStream` constructs the only `SemanticObservationLog`. | Read or inject the stream-owned log instead of creating another history. | Bumper's standard `canonicalConstruction` fact plus repository lint. Delete when the log is nested in or privately initialized by the stream. |
| `buttonheist.semantic_observation_publication_ownership` | Only `SemanticObservationStream` calls `observationLog.publish`. | Submit a settled proof to the stream rather than publishing from a consumer. | Bumper's standard `boundaryOnly` fact plus repository lint. Delete when publication is private to the stream. |
| `buttonheist.settled_observation_commit_ownership` | One proof-bearing `SemanticObservationStream.publishCommittedObservation` call enters `TheStash.reduceInterfaceGraph`; only that reducer and explicit lifecycle reset mutate `interfaceTree`. | Settle or explore into `InterfaceObservationProof`, then commit through the stream. | The custom typed-query rule checks call count, enclosing proof-bearing function, and graph assignments. Delete when graph storage and reducer invocation are inaccessible outside one owner. |

## Expression Ownership

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.expr_ownership` | The package enum `Expr<Value>` in `StringExpressions.swift` is the repository's one authored-expression currency. This does not reserve the `Expr` suffix or ban semantically distinct types. | Extend `Expr<Value>` or choose a domain name that represents a genuinely different concept. | Bumper 0.5.2's standard `singleDeclaration` fact plus repository lint. Delete when module boundaries make another `Expr` declaration impossible or the currency is removed. |

## Canonical Traversal

Both rules use Bumper 0.5.2's standard `canonicalTraversal` shaper. They protect
recursive ownership without preserving helper names or a custom recursion
visitor.

| Rule ID | Invariant | Repair | Proof and deletion condition |
| --- | --- | --- | --- |
| `buttonheist.canonical_plan_traversal` | `HeistPlanTraversal.swift` owns analysis walks and TheBrains owns recursive execution of `HeistStep`. | Express analysis through the traversal algebra; keep execution recursion in TheBrains. | Bumper's recursive-call facts plus repository lint. Delete when recursive children are inaccessible outside those owners. |
| `buttonheist.canonical_accessibility_hierarchy_traversal` | `AccessibilityHierarchy+Traversal.swift` owns recursive `.container` descent. | Use the canonical fold, preorder, compaction, or graph projection. | Bumper's recursive-call facts plus repository lint. Delete when the parser exposes only its traversal algebra. |

## Retired Policy

Constructor allowlists, compatibility-name bans, explicit-access file lists,
expression-suffix reservations, folder import allowlists, component dependency
shadow graphs, viewport helper policing, and custom recursive visitors are
intentionally absent. Interface graph construction uses proof types; Bumper
retains only the narrow cross-file commit relationship until Swift access
control can own it. Durable observation values rely on `Sendable` and strict
concurrency rather than a blacklist of UIKit-looking type names. Receipts,
serialization, retries, settlement behavior, and wire contracts remain covered
by behavioral and reducer tests.

## Rule Lifecycle

A new blocking rule must demonstrate valid Swift that violates a durable
repository invariant, explain why the compiler/build graph/tests cannot own
it, and include one valid and one invalid in-memory fixture. When a native
boundary makes the bad state unconstructible, delete the Bumper rule and its
fixture in the same change.

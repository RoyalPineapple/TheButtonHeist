# Swift Shape Audits

These are the codebase audits that have produced useful simplification in
Button Heist. They are intentionally biased toward Swift-shaped correctness:
make invalid states unrepresentable, keep boundaries typed, and reject old
shapes instead of adapting them.

Run these audits when planning an invariant pass, reviewing an agent patch, or
deciding whether a public API belongs in the client contract.

## Gate First

- Run `scripts/reject-invalid-swift-shapes.sh` before pushing any invariant PR.
- Run `DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer scripts/check-swift-api-baseline.sh` for public API changes.
- Run `scripts/generate-project.sh` after Tuist/Xcode test commands before reading generated project diffs.
- Treat any new guardrail failure as a design question first, not an allowlist request.

## 1. Access Level Shape

Smell: internal plumbing exposed as `public` because multiple package targets need it.

Preferred shape: use Swift `package` access for cross-target implementation details. Reserve
`public` for caller-facing client API and wire/source contracts.

Where to look:

```bash
rg '^public (struct|enum|class|protocol|extension|func|var|let)| public (let|var|init|func)' ButtonHeist/Sources
```

Acceptance criteria:

- Every new `public` symbol is intentionally part of the external Button Heist API.
- Public API baseline drift is reviewed symbol-by-symbol.
- Types like traversal records, parser helpers, runtime indexes, test fixtures, and local diagnostics are `package` or narrower.
- No public symbol exists solely to make another package target compile.

## 2. Tuple API Shape

Smell: tuples returned from functions or exposed in properties, especially named tuples that carry domain meaning.

Preferred shape: named structs or enums. Tuples are acceptable only as short-lived local destructuring.

Where to look:

```bash
rg '-> *\\(|var [^=]+: *\\(|let [^=]+: *\\(' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- No tuple appears in public, package, internal, or test helper API surfaces.
- Returned values with meaning are named types with domain field names.
- Tests assert the named type, not tuple element positions.

## 3. Raw String Shape

Smell: string literals representing command names, action types, status codes, config keys, failure codes, source phases, or option values.

Preferred shape: `String`-backed enums or small value types. Convert to strings only at JSON, CLI, MCP, Info.plist, or environment boundaries.

Where to look:

```bash
rg '"[a-zA-Z0-9_.-]+"' ButtonHeist/Sources ButtonHeist/Tests
rg '\\.rawValue *==|== *[A-Za-z0-9_]+\\.rawValue' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- Known vocabularies have one authoritative enum or value type.
- `.rawValue` use is at serialization, parsing, logging, or display boundaries only.
- Tests compare typed values before checking encoded strings.

## 4. Any And Dynamic Data Shape

Smell: `[String: Any]`, `AnyHashable`, `Any.Type`, `any Encodable`, `as Any`, `JSONSerialization`, or Foundation property-list erasure in normal code.

Preferred shape: typed Codable models, typed fixture enums, `NSObject`/Foundation bridges only at the narrow Foundation API boundary, and MCP `Value` maps only at the MCP argument boundary.

Where to look:

```bash
scripts/reject-invalid-swift-shapes.sh
rg '\\[String: *Any\\]|AnyHashable|Any\\.Type|any +Encodable|as Any|JSONSerialization' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- No new broad `Any` sites outside an explicit bridge helper.
- Test fixtures use typed builders instead of raw dictionaries.
- Dynamic external inputs are decoded once into typed models, then stay typed.

## 5. Public Boundary Shape

Smell: adapter, compatibility, public-prefix, or projection names that leak history instead of domain meaning.

Preferred shape: current domain names and one canonical boundary model. Break old callers when the old surface is wrong.

Where to look:

```bash
rg 'Adapter|Compatibility|Compat|Legacy|Public[A-Z]|actionKind|inlineButtonHeistSource|HeistPlanSourceRequest' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- No compatibility adapters are introduced for retired internal shapes.
- Old spellings are rejected by parser/decoder tests.
- Boundary names describe the domain, not their visibility or migration history.

## 6. Pipeline Result Shape

Smell: one pipeline returns `(met, actual)`, another returns `ExpectationResult`, another assembles failure JSON directly.

Preferred shape: one domain result type per pipeline, with conversion helpers only at the boundary.

Where to look:

```bash
rg 'ExpectationResult|PredicateEvaluationResult|ActionResult|HeistExecutionResult|Failure' ButtonHeist/Sources
rg 'return \\(|met:|actual:' ButtonHeist/Sources/TheScore ButtonHeist/Sources/TheInsideJob
```

Acceptance criteria:

- Predicate state evaluation returns `PredicateEvaluationResult`.
- User-facing expectations are produced by one conversion path.
- Action, heist, logging, and error pipelines each have one canonical result model.
- JSON response assembly consumes typed projections, not ad hoc dictionaries.

## 7. Explicit State Machine Shape

Smell: phase flags, sibling optionals, nullable resources, or parallel collections that encode one lifecycle.

Preferred shape: enums with associated values and state structs that carry exactly the data valid in that phase.

Where to look:

```bash
rg 'is[A-Z]|did[A-Z]|phase|state|Task<|\\?' ButtonHeist/Sources/TheInsideJob ButtonHeist/Sources/TheButtonHeist
```

Acceptance criteria:

- Multi-step lifecycle has one state enum.
- Phase-specific data lives inside the enum case's associated value.
- No guard exists only to reject an impossible phase/data combination.
- Tests assert transitions through domain decisions, not incidental booleans.

## 8. Collection Identity Shape

Smell: `contains(where: { $0 === object })`, array uniqueness checks, container-keyed dictionaries, or object identity used where a typed key exists.

Preferred shape: `Set`/`Dictionary` keyed by typed identity: `TreePath`, `HeistId`, enum keys, or small Hashable records.

Where to look:

```bash
rg 'contains\\(where:.*===|ObjectIdentifier|\\[[^\\]]+: *\\[[^\\]]+\\]|Dictionary\\(' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- Deduplication uses `Set` when order is irrelevant.
- Ordered uniqueness uses a typed seen set plus an ordered result.
- UI object identity is kept behind live lookup boundaries and converted to typed path/id keys quickly.

## 9. Property Checker Shape

Smell: switches that manually pair property enum cases with erased value enum cases at every call site.

Preferred shape: typed property checker/proof objects. Associated data should carry the only valid value type for that property.

Where to look:

```bash
rg 'ElementProperty|ElementPropertyValue|property.*matches|switch \\(property, value\\)' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- Invalid property/value combinations fail at decode or construction boundaries.
- Custom content and rotor predicates use the same typed string matcher machinery as label/value/hint.
- Tests cover every property family through shared checker fixtures, not bespoke switch cases.

## 10. Logging And Error Pipeline Shape

Smell: raw `Logger(...)`, `print`, `FileHandle.standardOutput.write`, new `FooError`, stringly failure codes, or response JSON built from string keys.

Preferred shape: one logger factory, one local output sink per tool, one error type per logical domain, and typed failure taxonomies/projections.

Where to look:

```bash
scripts/reject-invalid-swift-shapes.sh
rg 'Logger\\(|print\\(|standardOutput|enum .*Error: Error|errorKind|failureCode' ButtonHeist/Sources ButtonHeist/Tests
```

Acceptance criteria:

- New logging goes through the tracked logging pipeline or an explicitly audited legacy site.
- Tool stdout writes are routed through local output sinks.
- New error types document their logical boundary and why existing domain errors cannot carry the case.
- Failure responses are assembled from typed failure/projection models.

## 11. Functional Pipeline Shape

Smell: loops that only append transformed values, mutable flags that summarize earlier work, duplicate success/failure assembly, or functions taking loose context parameters.

Preferred shape: `map`, `compactMap`, `reduce(into:)`, `lazy`, domain snapshots, and pure functions that can be tested without side effects.

Where to look:

```bash
rg 'var [a-zA-Z0-9_]+ = \\[|append\\(|did[A-Z]|var .* = false|func .*\\([^)]*,[^)]*,[^)]*,[^)]*,' ButtonHeist/Sources
```

Acceptance criteria:

- Pure transforms are expressed as value pipelines.
- Side-effectful loops are isolated and named for the side effect.
- Context groups become structs when passed together more than once.
- Success/failure branches share one result assembly path.

## 12. Test Guardrail Shape

Smell: a convention enforced only by code review or a one-off audit note.

Preferred shape: source-shape tests, CI shell guards, public API baselines, and negative decoding/parser tests.

Where to look:

```bash
rg 'reject|guardrail|retired|shape|baseline|source-shape|no new' ButtonHeist/Tests scripts api-baselines
```

Acceptance criteria:

- Every retired shape has a failing test or script check.
- Every intentional public API change updates `api-baselines/swift`.
- Every parser/decoder retirement has a negative test proving the old spelling is rejected.
- Guardrails fail on new use sites, not just on generated reports.

## Review Rule

When an audit finds a smell, prefer this order:

1. Move the concept into the type system.
2. Narrow the access level.
3. Delete compatibility and adapters.
4. Add a guardrail so the old shape cannot return.
5. Update baselines only after confirming the public API change is intentional.

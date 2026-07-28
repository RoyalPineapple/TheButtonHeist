# The wire format still collapses two predicates into one

The Swift API has four sibling predicates matching the four ticks. The wire
format has three, and reaches the fourth through a discriminator: `screenChanged`
and `elementsChanged` both encode as `{"type":"changed"}` and are told apart by a
`"scope"` key reading `"screen"` or `"elements"`.

That is the pre-sibling shape kept alive at the boundary. One wire type plus a
tag standing in for two types is an adapter, and it is the only place in the
system where the four predicates are not four things.

**No backwards compatibility, no adapters.** The wire types become
`screenChanged` and `elementsChanged`, and `changed`/`scope` go.

## Why it is not part of the tick migration

Landing this is a protocol break, not an internal collapse. `wireTypeValues` is
public and feeds the MCP tool schema, so the externally visible command
vocabulary changes. That belongs in its own PR with its own review, rather than
riding along inside a migration phase.

It surfaced from two failing tests on `alex/nightly-watchdog-correctness` and was
deliberately left undone there — the branch's job was green tests, and a
half-applied protocol change is worse than an intact adapter.

## The source change

All of it is in `ButtonHeist/Sources/ThePlans/Model/AccessibilityPredicate.swift`.
This part is small and was verified to compile:

1. `RootPredicateWireType`: replace `case changed` with `case screenChanged` and
   `case elementsChanged`.
2. `decodeRoot`: delete the `case .changed` block — the nested `scope` decode,
   its unknown-scope `DecodingError`, and the inner `switch scope`. Replace with
   two flat cases. Each keeps its own `rejectUnknownKeys` allow-list, now without
   `"scope"`: `["type", "match"]` for screen, `["type", "assertions"]` for
   elements.
3. `encodeRoot`: each case encodes its own type and stops encoding `scope`.
4. Delete `AccessibilityChangedWireScope`.
5. Drop `scope` from `AccessibilityPredicateCodingKeys`. It is load-bearing:
   `rejectUnknownKeys` works off explicit allow-lists, so leaving a stale key in
   the enum lets `scope` be silently accepted on some other predicate.

## What that breaks — 42 documents

Every wire document carrying the old shape has to move. `grep -rn '"changed"'`
finds them; re-run it rather than trusting this table, which was accurate at
`2c81389a5`.

| File | Sites |
|---|---|
| `Tests/ButtonHeistTests/TheFenceHandlerWaitExpectationTests.swift` | 12 |
| `Tests/ThePlansTests/CanonicalAccessibilityPredicateTests.swift` | 9 |
| `Tests/TheScoreTests/AccessibilityPredicateFinalStateTests.swift` | 5 |
| `docs/WIRE-PROTOCOL.md` | 4 |
| `Tests/ButtonHeistTests/TheFenceHandlerCommandAdmissionTests.swift` | 2 |
| `docs/HEIST-FORMAT.md` | 2 |
| `Tests/ButtonHeistTests/ElementActionRequestContractTests.swift` | 1 |
| `Tests/ButtonHeistTests/TheFenceHandlerFailureMappingTests.swift` | 1 |
| `Tests/ButtonHeistTests/TheFenceHandlerInterfaceSessionTests.swift` | 1 |
| `Tests/ThePlansTests/HeistPlanAdmissionWireTests.swift` | 1 |
| `Tests/ThePlansTests/HeistPlanExpressionContractTests.swift` | 1 |
| `Tests/TheScoreTests/WireTypeRoundTripIdentityAndSimplePayloadTests.swift` | 1 |
| `Tests/TheScoreTests/WireTypeRoundTripPlanTraceAndMessageTests.swift` | 1 |
| `docs/API.md` | 1 |

### Three things that are not find-and-replace

**Encoded JSON is key-sorted.** `AccessibilityPredicate.screenChanged` currently
asserts as `{"scope":"screen","type":"changed"}`. It becomes
`{"type":"screenChanged"}` — and where a `match` is present, the key order shifts
because `scope` is gone from the middle. Expected strings have to be re-derived,
not edited in place. `CanonicalAccessibilityPredicateTests.swift:12,15` are the
clearest examples.

**Some documents are deliberately invalid**, and their intent has to be restated
rather than substituted. In `CanonicalAccessibilityPredicateTests.swift`:

- `:25` a screen predicate carrying `assertions` — still rejectable, as
  `{"type":"screenChanged","assertions":[…]}`. This is the claim the six
  `MacFrameworkTests` failures were about, so keep it: it is the one case here
  with a demonstrated history of regressing.
- `:32` an elements predicate carrying `match` — same, as
  `{"type":"elementsChanged","assertions":[],"match":…}`.
- `:158` `{"type":"changed","scope":"screen","unexpected":true}` — the unknown-key
  rejection, which survives the move.
- `:159` `{"type":"changed","scope":"invalid","assertions":[]}` — **this one has
  no successor.** It tests the unknown-*scope* error, and there is no scope to be
  unknown. The equivalent claim is an unknown *type*, which
  `decodeRoot`'s `invalidType` already covers, so check whether that case is
  already asserted elsewhere before writing a replacement. Deleting a test
  because its subject is gone is correct; deleting it silently is not.
- `:163-164` a nested predicate where an element assertion belongs. Still
  invalid, still worth asserting.

**`wireTypeValues` is a public contract.** It is
`PresencePredicateWireType.allCases + RootPredicateWireType.allCases`, so adding a
case changes both its contents *and* its length. Two tests read it
(`WireTypeRoundTripIdentityAndSimplePayloadTests.swift:72`,
`StringMatchCommandSchemaContractTests.swift:239`) and it reaches the MCP schema
through `FenceParameterBlocks.swift:102` as `enumValues`. Check whether either
test asserts order or count.

## Docs

`docs/WIRE-PROTOCOL.md` is the normative one. `API.md` and `HEIST-FORMAT.md`
carry examples. The authored DSL examples across the docs already say
`.elementsChanged([…])` — an earlier rename reached them — so what is left is
the JSON.

## Verify

- `scripts/test-runner.py run MacFrameworkTests` covers `ThePlansTests` and
  `TheScoreTests`; `ButtonHeistTests` holds the fence handler tests.
- `scripts/check-swift-api-breaking-changes.sh` will report this. The branch this
  came from already carries an intentional-break exemption note against v0.6.32;
  a wire break wants its own, stating that the wire types are now the four
  predicates.
- `grep -rn '"changed"' ButtonHeist docs` should come back empty.

## What surfaced it, and what that turned out to be

Six `MacFrameworkTests` failures led here, and they were **a different bug** —
already fixed on `alex/nightly-watchdog-correctness`, not waiting for this work.

They were documents sending `{"type":"changed","scope":"screen","assertions":…}`.
A screen predicate takes a `match` and no assertion list, so `rejectUnknownKeys`
refused them — correctly. Six documents, two of them the docs' own examples, still
said a screen predicate carried assertions. The tell was
`testParseExpectationRejectsGenericChangedPredicate` passing while
`testParseExpectationScreenChangedObject` failed.

So there is no failing test pointing at the collapse today. This is a design
correction, not a fix, and the suite is green without it. Expect to move 40
documents that currently pass.

Worth knowing while working here: `xcodebuild` swallows assertion text for this
target, and so does the CI log — both print only pass/fail. Read the `.xcresult`
bundle under `~/Library/Developer/Xcode/DerivedData/ButtonHeist-*/Logs/Test/` with
`xcrun xcresulttool get test-results tests`, or infer from which neighbouring
tests pass.

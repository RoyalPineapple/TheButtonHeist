# Heist language design rationale

The heist language is deliberately small, and its restrictions are design, not
immaturity. This page states the reasoning and names the prior art each choice
descends from. The normative rules live in the
[Heist language spec](HEIST-LANGUAGE-SPEC.md); this page explains why the rules
are what they are.

## Lineage

**`HeistDef` is the PageObject/Robot pattern.** Martin Fowler's PageObject and
the Robot pattern popularized by Jake Wharton's testing-robots talk both wrap
low-level selectors inside a method named for what the product does. A
`HeistDef` has the same anatomy — an accessibility predicate inside, a product
name outside — expressed as a result-builder grammar instead of a class.
`Cart.addItem` is not a button or a label; it is a product capability, defined
once and invoked by name.

**String-only parameter crossing is Gherkin's design.** Gherkin steps take
strings, and that constraint is what keeps a Gherkin suite readable as a
description rather than a program. Gherkin's documented failure mode is the
pressure toward programmability — helpers that grow logic until the feature
files are code in disguise. The heist language's answer to that pressure is an
explicit escape hatch rather than a wider grammar: the Swift host around a
heist is fully Turing-complete. Compute the list, read the model, branch on
anything — and only the finished string crosses into the heist. A capability
that genuinely needs multiple parameters, return values, or complex logic
should be a thin Swift wrapper that drives heists, not a stretched heist.

**A list is not a parameter.** A `HeistDef` takes one `String`, one
`ElementTarget`, or nothing. To act over several strings, keep the definition
single-string and loop at the call site with `ForEach`. The generated wire
format does carry string arrays — the `for_each_string` step stores its
`values` list — but that array is loop source data, fixed at plan admission
and owned by the loop. It is not structured input crossing into a definition
body; the body sees one resolved string per iteration. The doctrine is about
what a definition can receive, not about whether the artifact may contain a
list.

**Totality via bounded loops and no recursion is Starlark's and Dhall's
design.** Both languages guarantee termination by construction: loops iterate
fixed collections, and recursion is unrepresentable. The heist language makes
the same trade for the same reason — a heist is a bounded recording of an
accessibility interaction, and crossing the line would make it a program that
may never stop.

**Settle-then-assert is EarlGrey's synchronization thesis, better specified.**
EarlGrey's insight was that a test should act only when the app is idle,
and that the framework — not the author — should own knowing when that is.
The Button Heist keeps the thesis and specifies the mechanism publicly:
"settled" has an exact fingerprint-based definition
([Scope and limits](SCOPE-AND-LIMITS.md)), and every step also asserts its
outcome against the settled tree after acting.

## The invariant, precisely

Two rules keep every heist total:

1. **Runtime state can be tested, never named.** A heist can branch on, wait
   for, repeat until, and assert against runtime state — but it cannot capture
   a runtime value into a name and compute on it. There are no variables bound
   to observed values, no functions that return values, no value composition.
   This is the rule that keeps unbounded computation unrepresentable.
2. **The definition call graph is acyclic.** `RunHeist` resolution is checked
   for cycles at admission; a definition whose invocation chain reaches itself
   is rejected before it runs. This is a second rule, not a corollary of the
   first — it closes the one door a bounded grammar would otherwise leave
   open, recursion smuggling unbounded iteration back in.

"Total" deserves its qualifier. A heist is terminating **by construction**
where structure guarantees it: `ForEach` iterates a list or match set fixed
before the loop starts, and definition expansion bottoms out because the call
graph is acyclic. It is terminating **by mandatory timeout** where only the
run can tell: a `WaitFor` or `RepeatUntil` whose predicate never comes true is
cut off by a bounded timeout (`WaitFor` defaults to 30 seconds; `RepeatUntil`
requires an explicit timeout). You do not always know the outcome before the
run, but you always know there is one.

## Positive assertions

The predicate grammar deliberately omits general negation and disjunction. An
expectation is a contract, and an open-ended negation — "the value is anything
except 5" — is a green light over an undefined state: it passes for wrong
reasons as easily as right ones. Where a negative matters, the grammar gives
it a positive form: `.missing(...)` asserts absence from the settled tree, and
trait exclusion (`.excludeTraits([.selected])`) asserts "a button that is not
selected." Where a meaningful state is not yet expressible as a trait, the
right move is to expose it as one — fix the interface, not the grammar.

## The test for additions

A proposed addition belongs in the language only if it keeps all four
properties:

1. **Inputs stay strings and element matchers.** A list of strings is not a
   new input kind; it is a single-string `HeistDef` wrapped in a `ForEach` at
   the call site.
2. **Nothing unbounded.** No open-ended iteration, no recursion, and no
   wait-shaped step without a timeout.
3. **Bodies stay declarative.** The existing step vocabulary, never arbitrary
   code.
4. **It names something an accessibility operator actually does.** Increment
   a stepper until the value is right: yes. Assert "the value is anything
   except 5": no. A hardware interaction or a hand-off to another process: no
   — those are out-of-process effects, not gaps in the language
   ([Scope and limits](SCOPE-AND-LIMITS.md)).

## Economy for agents

The grammar is kept small so that an agent can hold all of it in context,
generate it correctly, and repair a heist when a label drifts — two passable
types, a short step vocabulary, one expectation combinator. That is the design
intent, stated as intent: authoring economy is not something this project has
benchmarked. What the shape buys today is that one language carries the whole
lifecycle — explored live over MCP, saved to Swift, compiled to a `.heist`
artifact, replayed, and embedded in XCTest — with no translation step between
the agent's vocabulary and the test suite's.

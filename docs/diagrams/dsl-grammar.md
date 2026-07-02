# DSL Grammar

The authoring surface as one picture: step types, action commands, the passable types, target forms, and — the central division — the split between state predicates (evaluated against a frozen parse) and change predicates (requiring delta evidence, never usable as search selectors). This diagram answers "what can a heist say, and what kind of evidence does each construct consume?"

**Illustrates:** [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [HEIST-FORMAT.md](../HEIST-FORMAT.md), [SWIFT-HEIST-AUTHORING.md](../SWIFT-HEIST-AUTHORING.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/HeistStep.swift`, `ButtonHeist/Sources/ThePlans/HeistActionCommand.swift`, `ButtonHeist/Sources/ThePlans/HeistArgument.swift`, `ButtonHeist/Sources/ThePlans/AccessibilityPredicate.swift`, `ButtonHeist/Sources/ThePlans/StatePredicateExpressions.swift`, `ButtonHeist/Sources/ThePlans/ElementTarget.swift`

```mermaid
flowchart TD
    subgraph steps["HeistStep — 10 cases"]
        ACTION["action(ActionStep)"]
        WAIT["wait(WaitStep)"]
        COND["conditional(ConditionalStep)"]
        FEE["forEachElement(ForEachElementStep)"]
        FES["forEachString(ForEachStringStep)"]
        RU["repeatUntil(RepeatUntilStep)"]
        WARNS["warn(WarnStep)"]
        FAILS["fail(FailStep)"]
        NESTED["heist(HeistPlan)"]
        INVOKE["invoke(HeistInvocationStep)<br/>RunHeist by name + argument"]
        ACTION ~~~ COND
        COND ~~~ FES
        FES ~~~ WARNS
        WARNS ~~~ NESTED
        WAIT ~~~ FEE
        FEE ~~~ RU
        RU ~~~ FAILS
        FAILS ~~~ INVOKE
    end

    subgraph commands["HeistActionCommand"]
        SEMANTIC["semantic (durable):<br/>activate · increment · decrement ·<br/>customAction · rotor · typeText"]
        MECH["mechanical (coordinates):<br/>mechanicalTap · mechanicalLongPress ·<br/>mechanicalSwipe · mechanicalDrag"]
        VIEWPORT["viewport (non-durable):<br/>viewportScroll · viewportScrollToVisible ·<br/>viewportScrollToEdge"]
        SEMANTIC ~~~ MECH
        MECH ~~~ VIEWPORT
    end

    subgraph passables["Passable types"]
        PSTR["String — StringExpr:<br/>.literal or .ref"]
        PTGT["ElementTarget — ElementTargetExpr:<br/>.target or .ref"]
        PVOID["Void — no argument"]
        PSTR ~~~ PTGT
        PTGT ~~~ PVOID
    end

    NESTED ~~~ SEMANTIC
    INVOKE ~~~ PSTR
    ACTION --> commands
    INVOKE --> passables
```

The predicate split:

```mermaid
flowchart LR
    subgraph statep["State predicates — frozen parse"]
        STATE["AccessibilityPredicate.state(State)<br/>exists · missing · existsTarget ·<br/>missingTarget · all"]
        NOTE1["evaluated against one settled capture —<br/>answers 'is the screen like this now?'"]
        STATE --- NOTE1
    end
    subgraph changep["Change predicates — delta evidence"]
        CHANGE["AccessibilityPredicate.changePredicate(Change)<br/>any · screenScope · elementsScope · allScopes<br/>and noChangePredicate"]
        NOTE2["require before/after settled captures —<br/>answer 'did the action change this?'<br/>never usable as search selectors"]
        CHANGE --- NOTE2
    end
    ACTIONK["action + expectation"] --> changep
    WAITK["WaitFor · If · RepeatUntil conditions"] --> statep
```

Notes:

- Targets have exactly one durable form: `ElementTarget.predicate(ElementPredicate, ordinal:)` — a semantic selector with an optional 0-based disambiguating ordinal. There is no coordinate target and no capture-local id target in the durable language (see [element-inflation.md](element-inflation.md)).
- The state/change split is the headline design rule: a state predicate can gate control flow because it reads one frozen parse; a change predicate classifies an action's delta and therefore only exists attached to an action's expectation. Element deltas are expressed with `ElementUpdatePredicate.updated(_, before:, after:)`.
- Wire discriminators for the loop steps are snake_case in `plan.json`: `for_each_element`, `for_each_string`, `repeat_until`.

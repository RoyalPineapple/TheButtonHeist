# DSL Grammar

The authoring surface as one picture: step types, action commands, passable
types, one target language, and one context-typed predicate tree.

**Illustrates:** [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [HEIST-FORMAT.md](../HEIST-FORMAT.md), [SWIFT-HEIST-AUTHORING.md](../SWIFT-HEIST-AUTHORING.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/Model/HeistStep.swift`, `ButtonHeist/Sources/ThePlans/Model/HeistActionCommand.swift`, `ButtonHeist/Sources/ThePlans/Model/AccessibilityPredicate.swift`, `ButtonHeist/Sources/ThePlans/Model/AccessibilityTarget.swift`

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
        INVOKE["invoke(HeistInvocationStep)"]
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
        PTGT["AccessibilityTarget:<br/>predicate · container · within · ref"]
        PVOID["Void — no argument"]
        PSTR ~~~ PTGT
        PTGT ~~~ PVOID
    end

    NESTED ~~~ SEMANTIC
    INVOKE ~~~ PSTR
    ACTION --> commands
    INVOKE --> passables
```

The predicate contexts:

```mermaid
flowchart LR
    ROOT["AccessibilityPredicate RootContext<br/>exists · missing · changed · noChange · announcement"]
    CHANGED["changed(ChangeDeclaration)"]
    SCREEN["ScreenAssertionContext<br/>exists · missing"]
    ELEMENTS["ElementsAssertionContext<br/>exists · missing · appeared · disappeared · updated"]
    TREE["current delivered Interface tree"]
    FACTS["ordered ChangeFact stream"]
    ROOT --> CHANGED
    CHANGED -->|screen| SCREEN
    CHANGED -->|elements| ELEMENTS
    ROOT -->|exists / missing| TREE
    SCREEN --> TREE
    ELEMENTS --> TREE
    ELEMENTS --> FACTS
```

Notes:

- `invoke(HeistInvocationStep)` is `RunHeist` by name plus an argument — the passable types are what that argument can be.
- `AccessibilityTarget` is shared by actions and predicates. It can target an element predicate, a container predicate, a scoped descendant, or a reference.
- Generic predicate contexts make invalid combinations unconstructible. Current-tree existence checks are shared; lifecycle and update assertions are available only inside element change declarations.
- Wire discriminators for the loop steps are snake_case in `plan.json`: `for_each_element`, `for_each_string`, `repeat_until`.

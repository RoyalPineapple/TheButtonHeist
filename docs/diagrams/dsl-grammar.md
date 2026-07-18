# DSL Grammar

The authoring surface as one picture: step types, action commands, passable
types, one target language, and one concrete predicate tree.

**Illustrates:** [HEIST-LANGUAGE-SPEC.md](../HEIST-LANGUAGE-SPEC.md), [HEIST-FORMAT.md](../HEIST-FORMAT.md), [SWIFT-HEIST-AUTHORING.md](../SWIFT-HEIST-AUTHORING.md)
**Source of truth:** `ButtonHeist/Sources/ThePlans/Model/HeistStep.swift`, `ButtonHeist/Sources/ThePlans/Model/HeistActions.swift`, `ButtonHeist/Sources/ThePlans/Model/HeistActionCommand.swift`, `ButtonHeist/Sources/ThePlans/Model/AccessibilityPredicate.swift`, `ButtonHeist/Sources/ThePlans/Model/AccessibilityTarget.swift`

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

    subgraph commands["Public action constructors"]
        SEMANTIC["semantic:<br/>Activate · Increment · Decrement · TypeText ·<br/>ClearText · CustomAction · Rotor"]
        SYSTEM["screen and system:<br/>ScreenActions · Edit · SetPasteboard ·<br/>TakeScreenshot · DismissKeyboard"]
        MECH["mechanical:<br/>Mechanical.Tap · Mechanical.LongPress ·<br/>Mechanical.Swipe · Mechanical.Drag"]
        SEMANTIC ~~~ SYSTEM
        SYSTEM ~~~ MECH
    end

    subgraph passables["Passable types"]
        PSTR["String<br/>literal or typed reference"]
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

The predicate and target contexts:

```mermaid
flowchart LR
    ROOT["AccessibilityPredicate<br/>exists · missing · changed · noChange · announcement"]
    CHANGED["changed(ChangeDeclaration)"]
    SCREEN["ChangeDeclaration.ScreenAssertion<br/>exists · missing"]
    ELEMENTS["ChangeDeclaration.ElementAssertion<br/>exists · missing · appeared · disappeared · updated"]
    TARGET["AccessibilityTarget"]
    ELEMENT["element predicate"]
    CONTAINER["container predicate"]
    WITHIN["within container"]
    TREE["current InterfaceTree"]
    FACTS["observation-window transitions"]
    RESOLVE["one target resolver"]
    ROOT --> CHANGED
    CHANGED -->|screen| SCREEN
    CHANGED -->|elements| ELEMENTS
    ROOT -->|exists / missing| TARGET
    SCREEN -->|exists / missing| TARGET
    ELEMENTS -->|all assertions| TARGET
    TARGET --> ELEMENT
    TARGET --> CONTAINER
    TARGET --> WITHIN
    ELEMENT --> RESOLVE
    CONTAINER --> RESOLVE
    WITHIN --> RESOLVE
    ROOT -->|exists / missing| TREE
    SCREEN -->|exists / missing| TREE
    ELEMENTS -->|exists / missing| TREE
    TREE --> RESOLVE
    ELEMENTS -->|appeared / disappeared / updated| FACTS
    FACTS --> RESOLVE
```

Notes:

- `invoke(HeistInvocationStep)` is `RunHeist` by name plus an argument — the passable types are what that argument can be.
- `AccessibilityTarget` is shared by actions, waits, action expectations, control-flow predicates, CLI/MCP, and `get_interface` subtree selection. It can target an element predicate, a container predicate, a scoped descendant, or a reference.
- Concrete nested assertion types make invalid combinations unconstructible. Current-tree existence checks are shared; lifecycle and update assertions are available only inside element change declarations.
- Expression, core, and resolved representations stay behind the public DSL surface.
- Wire discriminators for the loop steps are snake_case in `plan.json`: `for_each_element`, `for_each_string`, `repeat_until`.

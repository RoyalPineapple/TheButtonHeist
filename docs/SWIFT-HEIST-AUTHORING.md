# Swift Heist Authoring Boundary

Swift Heist is the editable source form for authoring heists. Treat the Swift
DSL like product code: it can use helper functions, local variables, comments,
formatting, and static expansion helpers such as `ForEach` to make a heist easy
to read and maintain.

`HeistPlan` is the execution model. A Swift DSL file builds a `HeistPlan`; a
`.heist` JSON file stores and transports a `HeistPlan`. JSON is the wire and
storage artifact, not the source authoring surface.

Decoding `.heist` JSON reconstructs an executable `HeistPlan` with the steps,
targets, arguments, and expectations required for playback. It does not
reconstruct the Swift source that produced it. In particular, JSON cannot
recover:

- helper functions or builder structure
- static `ForEach` source before expansion
- comments
- local variables, constants, or their names
- source grouping, whitespace, formatting, or review intent

At runtime, Button Heist executes only `HeistPlan`. The Swift DSL is an
authoring convenience that produces a plan; JSON is a durable representation of
that plan. Keep Swift DSL files when the heist needs to remain editable as
source, and keep `.heist` JSON when the heist needs to move across the wire or
be stored for deterministic playback.

`ForEach` has two authoring forms. `ForEach(collection)` is static Swift
expansion and emits only the linear child steps. `ForEach(.matching(predicate),
limit:)` emits one runtime `for_each` step; the closure receives
`ElementTarget.predicate(predicate, ordinal: 0)`, so each iteration repeats the
same semantic promise and command execution re-resolves it normally.
Runtime `ForEach` repeats semantic intent; commands re-resolve targets. The
loop owns match counting and limit enforcement only.

# Button Heist Examples

These examples show the same product contract through three surfaces:

- [Semantic command](semantic-command.md): one direct command with expectation.
- [Heist program](heist-program.swift): Swift DSL as a semantic program.
- [Recording becomes a test](recording-becomes-test.md): live execution becoming
  a generated `.heist` package artifact and optional Swift DSL source.

Each example follows the same machine:

```text
accessibility contract
-> semantic intent
-> shared action-or-wait runtime
-> settled semantic evidence
-> next step, report, or recording
```

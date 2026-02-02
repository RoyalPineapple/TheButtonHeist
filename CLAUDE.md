# CLAUDE.md

## Commit Hygiene

- **Always ensure code builds before committing.** Never commit code that doesn't compile or pass basic build checks.
- Run `xcodebuild` to verify the project builds successfully before staging changes.
- Keep commits atomic and focused on a single logical change.

## CLI-First Development

- **The CLI is the canonical test client.** All features must be usable from the command line.
- This enables a full feedback loop for agentic workflows where automated tools can exercise the entire feature set.
- When adding new functionality, ensure corresponding CLI commands or flags are available.

## Feedback Loop Workflow

- **Development and diagnostics should be driven by feedback loops.** Make changes, then validate their output entirely via CLI and tools that an agent can use and verify.
- Avoid workflows that require manual GUI interaction for validation—if an agent can't verify it, automate it until it can.
- Build observability into features so their behavior can be inspected programmatically.

## End-to-End Testing with iOS Simulator

- **Round-trip testing between the iOS app and CLI is essential.** The CLI drives the simulator, the app responds, and the CLI verifies the results.
- Use `xcrun simctl` and the project CLI to launch, interact with, and inspect the iOS app running in the simulator.
- Tests should be fully automatable: boot simulator → install app → run test scenarios via CLI → capture and verify output.
- This creates a complete feedback loop where an agent can make code changes, rebuild, deploy to simulator, and validate behavior without human intervention.

# ButtonHeist MCP Server

Thin MCP interface over `TheMastermind`.

## Architecture

- `TheMastermind` in `ButtonHeist` is the single orchestration layer.
- CLI `buttonheist session` and MCP `run` both delegate to `TheMastermind`.
- Parallelization/multi-session work is intentionally deferred.

## Build

```bash
cd ButtonHeistMCP
swift build -c release
```

## Tool Surface

- `run`: execute one session command through `TheMastermind`.

Supported commands are sourced from:

- `ButtonHeist/Sources/ButtonHeist/MastermindCommandCatalog.swift`

## Notes

- Use `BUTTONHEIST_DEVICE` to target a specific simulator/device.
- Token and reconnect behavior are handled by `TheMastermind`.
- For fast navigation loops, prefer action deltas over full snapshots:
  - Avoid calling `get_interface` after every action; request it only when needed.

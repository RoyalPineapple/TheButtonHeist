# ButtonHeist MCP Server

The buyer interface. This is the piece that lets an agent talk to ButtonHeist like it was born there.

## Build

```bash
cd ButtonHeistMCP
swift build -c release
# Binary at .build/release/buttonheist-mcp
```

## Tool Surface

ButtonHeistMCP projects its tool surface from `TheFence.Command` via
`ToolDefinitions`. The MCP server exposes adapter-shaped tools, but command
identity, parameter names, grouped selector routing, and schemas are owned by
the Fence command contract.

`gesture`, `scroll`, and `edit_action` are grouped tools — their typed selector parameter routes to a TheFence command. All other tools map 1:1 to a TheFence command name. TheFence command names are the product command contract; wire message discriminators are a lower transport layer and are documented separately in the wire protocol. `run_batch.steps` use batch-executable canonical TheFence command requests and do not accept nested grouped MCP wrapper shapes, nested `run_batch`, or session-only commands (`help`, `status`, `quit`, `exit`).

## Runtime Behavior

- Uses `StdioTransport`, so MCP traffic is JSON-RPC over stdin/stdout
- Reuses a single `TheFence` instance and auto-reconnects when the next tool call arrives
- Resets an idle timeout after every tool call and disconnects when inactive
- Returns screenshot metadata plus an artifact path by default; pass `inlineData=true` on `get_screen` to opt into capped MCP image content
- Rejects `inlineData=true` for `get_screen` inside `run_batch` so batched responses stay bounded
- Returns recording artifact paths plus metadata by default; `inlineData` and `includeInteractionLog` are explicit, size-capped expansion flags

## Environment

- `BUTTONHEIST_DEVICE` selects a specific discovered device
- `BUTTONHEIST_TOKEN` provides the auth token for driver connections
- `BUTTONHEIST_DRIVER_ID` is forwarded through `TheFence` for session locking
- `BUTTONHEIST_SESSION_TIMEOUT` controls the idle disconnect timeout (default: 60 seconds)

## See Also

- [MCP Tool Reference](../docs/reference/mcp-tools.md) for the generated tool surface
- [Command Reference](../docs/reference/commands.md) for canonical Fence commands
- [API Reference](../docs/API.md) for public API context
- [Project Overview](../README.md) for setup and architecture
- [CLI Reference](../ButtonHeistCLI/) for direct terminal usage

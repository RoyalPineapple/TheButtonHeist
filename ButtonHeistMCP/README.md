# ButtonHeist MCP Server

The MCP server exposes The Button Heist's accessibility contract runtime to agents. It projects the same command contract used by the CLI and heist execution, so direct commands and composed heists run through one action/wait runtime.

## Build

```bash
cd ButtonHeistMCP
swift build -c release
# Binary at .build/release/buttonheist-mcp
```

## Tool Surface

ButtonHeistMCP projects its tool surface from `TheFence.Command` via
`ToolDefinitions`. The MCP server exposes one tool per exposed command; command
identity, parameter names, and schemas are owned by the Fence command contract.

Each MCP tool maps 1:1 to a TheFence command name. TheFence command names are
the product command contract; wire message discriminators are a lower transport
layer and are documented separately in the wire protocol. `run_heist` executes
a typed heist plan through the same semantic action/wait runtime used by direct
commands.

The generated [MCP Tool Reference](../docs/reference/mcp-tools.md) is the
current tool and schema reference. This README stays at the adapter behavior
layer.

## Runtime Behavior

- Uses `StdioTransport`, so MCP traffic is JSON-RPC over stdin/stdout
- Reuses a single `TheFence` instance and auto-reconnects when the next tool call arrives
- Resets an idle timeout after every tool call and disconnects when inactive
- Returns screenshot metadata plus an artifact path by default; pass `inlineData=true` on `get_screen` to opt into capped MCP image content
- `get_screen` is an explicit inspection command; capture screenshots before or after `run_heist`

## Environment

- `BUTTONHEIST_DEVICE` selects a specific discovered device
- `BUTTONHEIST_TOKEN` provides the auth token for driver connections
- `BUTTONHEIST_DRIVER_ID` is forwarded through `TheFence` for session locking
- `BUTTONHEIST_SESSION_TIMEOUT` controls the idle disconnect timeout (default: 60 seconds)

## See Also

- [MCP Agent Guide](../docs/MCP-AGENT-GUIDE.md) for agent observation, action, wait, and heist-composition patterns
- [MCP Tool Reference](../docs/reference/mcp-tools.md) for the generated tool surface
- [Command Reference](../docs/reference/commands.md) for canonical Fence commands
- [API Reference](../docs/API.md) for public API context
- [Project Overview](../README.md) for setup and architecture
- [CLI Reference](../ButtonHeistCLI/) for direct terminal usage

# ButtonHeist MCP Server

Model Context Protocol server that gives AI agents eyes and hands for iOS apps. It exposes a single `run` tool through which Claude (or any MCP client) can see the screen, read the UI hierarchy, and perform any gesture — tap, swipe, draw, type — all through native tool calls.

## How It Works

```
AI Agent (Claude Code, Claude Desktop, any MCP client)
    │ MCP (JSON-RPC 2.0 over stdio)
buttonheist-mcp
    │ spawns persistent subprocess
buttonheist session --format json
    │ TCP connection (stays open for the whole session)
InsideMan (embedded in your iOS app)
```

The MCP server is a **thin proxy**. All device logic lives in the CLI's `session` command — the server just routes tool calls through a subprocess pipe. This means the CLI and MCP server always have identical capabilities.

**Key design decisions:**
- **Single `run` tool** — collapses 20+ commands into one tool, reducing token overhead in LLM context
- **Persistent connection** — no per-call Bonjour discovery or TCP handshake, so tool calls complete in milliseconds
- **SessionPipe actor** — serializes concurrent MCP tool calls through the subprocess pipe, preventing interleaved I/O
- **Screenshots via temp files** — PNG data routes through disk, returned as inline MCP images (not base64 text through the pipe)

## Building

```bash
cd ButtonHeistMCP
swift build -c release
# Binary at .build/release/buttonheist-mcp
```

**Dependency**: [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk) (v0.10.0+)

## Configuration

### .mcp.json

Add this to your project root. MCP clients (Claude Code, Claude Desktop) read it automatically:

```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": []
    }
  }
}
```

### Device Targeting

When running multiple simulators or devices, target a specific one:

**Option 1** — `--device` flag:
```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": ["--device", "DEADBEEF-1234-5678-9ABC-DEF012345678"]
    }
  }
}
```

**Option 2** — Environment variable:
```json
{
  "mcpServers": {
    "buttonheist": {
      "command": "./ButtonHeistMCP/.build/release/buttonheist-mcp",
      "args": [],
      "env": { "BUTTONHEIST_DEVICE": "iPad Pro" }
    }
  }
}
```

The filter matches against device name, app name, short ID prefix, simulator UDID, or vendor identifier.

### CLI Binary Discovery

The server locates the `buttonheist` CLI binary in this order:

1. `BUTTONHEIST_CLI` environment variable
2. Same directory as the MCP binary
3. `../ButtonHeistCLI/.build/release/buttonheist` (relative)
4. `../ButtonHeistCLI/.build/debug/buttonheist` (relative)
5. `PATH` lookup

## The `run` Tool

Every interaction goes through one tool. Pass a `command` and any additional parameters:

```json
{"command": "get_screen"}
{"command": "get_interface"}
{"command": "tap", "identifier": "loginButton"}
{"command": "tap", "x": 196.5, "y": 659}
{"command": "swipe", "identifier": "list", "direction": "up"}
{"command": "type_text", "text": "hello", "identifier": "emailField"}
{"command": "draw_path", "points": [{"x": 100, "y": 400}, {"x": 200, "y": 300}], "duration": 1.0}
```

### Available Commands

| Command | Description |
|---------|-------------|
| `get_interface` | Read the UI element hierarchy |
| `get_screen` | Capture a PNG screenshot |
| `tap` | Tap an element or coordinate |
| `long_press` | Long press with configurable duration |
| `swipe` | Swipe by direction or between points |
| `drag` | Drag between two points |
| `pinch` | Pinch/zoom gesture |
| `rotate` | Two-finger rotation |
| `two_finger_tap` | Two-finger tap |
| `draw_path` | Draw along a path of waypoints |
| `draw_bezier` | Draw along cubic bezier curves |
| `activate` | Accessibility activate (VoiceOver double-tap) |
| `increment` / `decrement` | Adjust sliders, steppers, pickers |
| `perform_custom_action` | Invoke a named custom accessibility action |
| `type_text` | Type text / delete characters |
| `edit_action` | Copy, paste, cut, select, selectAll |
| `dismiss_keyboard` | Dismiss the software keyboard |
| `wait_for_idle` | Wait until animations settle |
| `list_devices` | List all discovered devices |
| `status` | Connection status |
| `help` | List all commands |

## See Also

- [CLI Reference](../ButtonHeistCLI/) — Full command-line documentation (`session` is the backbone of this server)
- [API Reference](../docs/API.md) — Complete API docs with parameter details for every command
- [Project Overview](../README.md) — Architecture and quick start

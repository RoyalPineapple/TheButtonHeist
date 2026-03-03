# ButtonHeistMCP - The MCP Server

> **Module:** `ButtonHeistMCP/Sources/`
> **Platform:** macOS 14.0+
> **Role:** Exposes TheMastermind as an MCP (Model Context Protocol) tool for AI agents

## Responsibilities

The MCP server provides a bridge between AI agents and ButtonHeist:

1. **Single `run` tool** accepting `{command, ...params}` JSON
2. **TheMastermind delegation** for all command execution
3. **Smart response rendering** - screenshots as inline MCP images, recordings summarized
4. **Environment-based config** - device filter, token, force mode
5. **StdioTransport** - JSON-RPC over stdin/stdout

## Architecture Diagram

```mermaid
graph TD
    subgraph MCP["ButtonHeistMCP"]
        Main["main.swift - @main ButtonHeistMCPServer"]
        Server["MCP Server - (swift-sdk)"]
        Transport["StdioTransport - stdin/stdout JSON-RPC"]
        ToolDef["ToolDefinitions.swift - run tool schema"]
        Handler["handleToolCall - decode → execute → render"]
    end

    subgraph Config["Environment Config"]
        Device["BUTTONHEIST_DEVICE"]
        Token["BUTTONHEIST_TOKEN"]
        Force["BUTTONHEIST_FORCE"]
        DriverID["BUTTONHEIST_DRIVER_ID"]
    end

    subgraph Rendering["Response Rendering"]
        TextContent["Text content - (JSON dict)"]
        ImageContent["Image content - (inline PNG base64)"]
        VideoSummary["Video summary - (size info only)"]
    end

    AIAgent["AI Agent - (Claude, etc.)"] <-->|JSON-RPC| Transport
    Transport --> Server
    Server --> Handler
    Handler --> TheMastermind["TheMastermind"]
    Config --> TheMastermind

    Handler --> TextContent
    Handler --> ImageContent
    Handler --> VideoSummary
```

## Tool Call Flow

```mermaid
sequenceDiagram
    participant AI as AI Agent
    participant MCP as MCP Server
    participant TM as TheMastermind

    AI->>MCP: CallTool("run", {command: "tap", identifier: "btn"})
    MCP->>MCP: Validate tool name == "run"
    MCP->>MCP: decodeArguments([String: Value] → [String: Any])
    MCP->>TM: execute(request: {command: "tap", identifier: "btn"})
    TM-->>MCP: MastermindResponse.action(result)
    MCP->>MCP: renderResponse(response)
    MCP-->>AI: [TextContent(json)]
```

## Screenshot Response Flow

```mermaid
sequenceDiagram
    participant AI as AI Agent
    participant MCP as MCP Server
    participant TM as TheMastermind

    AI->>MCP: CallTool("run", {command: "get_screen"})
    MCP->>TM: execute(request: {command: "get_screen"})
    TM-->>MCP: MastermindResponse.screenshotData(pngData, w, h)
    MCP->>MCP: renderResponse:
    Note over MCP: 1. Extract pngData from jsonDict
    Note over MCP: 2. Create .image content
    Note over MCP: 3. Remove pngData from text dict
    Note over MCP: 4. Create .text(remainingJson) content
    MCP-->>AI: [ImageContent(png), TextContent(metadata)]
```

## Tool Schema

```mermaid
graph TD
    RunTool["run tool"]
    RunTool --> Schema["Input Schema: - additionalProperties: true"]
    RunTool --> Desc["Description includes: - MastermindCommandCatalog.all - (auto-synced)"]

    Schema --> Cmd["command: string (required)"]
    Schema --> Params["...any additional params - (identifier, label, order, x, y, etc.)"]
```

## Items Flagged for Review

### MEDIUM PRIORITY

**MCP version hardcoded to "1.0.0"** (`ButtonHeistMCP/Sources/main.swift:20`)
```swift
Server(name: "buttonheist", version: "1.0.0")
```
- CLI version is "2.1.0" (`ButtonHeistCLI/Sources/Support/main.swift:12`)
- These versions are independent and not derived from a shared source
- Could cause confusion about which version of the protocol is supported

**Video data omitted from MCP responses** (`main.swift`)
- `renderResponse` replaces `videoData` with a size summary
- The actual video bytes are NOT returned to the AI agent
- This is intentional (too large for LLM context) but means MCP clients can't access raw video
- Only `screenshotData` gets the inline image treatment

**`additionalProperties: true` schema** (`ToolDefinitions.swift`)
- The tool accepts any JSON keys alongside `command`
- No per-command parameter validation at the MCP schema level
- All validation happens inside TheMastermind's dispatch
- An AI agent sending wrong parameters gets a runtime error, not a schema error

### LOW PRIORITY

**Single-tool design**
- All 27 commands go through one `run` tool
- Alternative: could expose each command as a separate MCP tool with typed schemas
- Current design is simpler to maintain (auto-syncs with catalog) but less discoverable

**No streaming support**
- MCP responses are one-shot
- No way to subscribe to interface updates or stream recording progress
- Each `get_interface` call is a fresh request

**Environment variable configuration only**
- No command-line flags (it's an MCP server, so stdin/stdout are for JSON-RPC)
- All config must come from environment variables
- This is the correct pattern for MCP servers

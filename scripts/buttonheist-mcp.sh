#!/bin/bash
# Wrapper for buttonheist-mcp.
# The caller must set BUTTONHEIST_DEVICE and BUTTONHEIST_TOKEN as env vars
# pointing to the specific app instance this MCP server should control.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

exec "$REPO_ROOT/ButtonHeistMCP/.build/release/buttonheist-mcp" "$@"

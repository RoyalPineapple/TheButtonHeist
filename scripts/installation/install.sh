#!/bin/bash
# buttonheist-integrate — Agentic integration for Button Heist
#
# Launches a coding agent to wire TheInsideJob into your iOS app. Supports
# multiple AI coding CLIs — pick your model, the prompt is universal.
#
# Install:
#   brew install RoyalPineapple/tap/buttonheist
#
# Usage:
#   buttonheist-integrate                  # defaults to claude
#   buttonheist-integrate claude           # Claude Code (Anthropic)     — paid
#   buttonheist-integrate gemini           # Gemini CLI (Google)         — free
#   buttonheist-integrate codex            # Codex CLI (OpenAI)          — paid
#   buttonheist-integrate copilot          # GitHub Copilot CLI          — paid
#   buttonheist-integrate aider            # Aider (open source)         — free
#   buttonheist-integrate --print-prompt   # print the prompt to paste anywhere

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

step()  { printf "\n${BLUE}${BOLD}▸${RESET} ${BOLD}%s${RESET}\n" "$1"; }
ok()    { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
warn()  { printf "  ${YELLOW}⚠${RESET} %s\n" "$1"; }
fail()  { printf "  ${RED}✗${RESET} %s\n" "$1"; exit 1; }
dim()   { printf "  ${DIM}%s${RESET}\n" "$1"; }

usage() {
    cat <<EOF
Usage: buttonheist-integrate [model] [project-dir]
       buttonheist-integrate --print-prompt

Paid models:
  claude    Claude Code (Anthropic)       — default
  codex     Codex CLI (OpenAI)
  copilot   GitHub Copilot CLI

Free models:
  gemini    Gemini CLI (Google)
  aider     Aider (open source, works with any model)

Other:
  --print-prompt    Print the integration prompt and exit.
                    Paste it into any coding agent — Cursor, Windsurf,
                    Cline, or whatever you prefer.

If no model is given, defaults to claude.
If no project directory is given, uses the current directory.
EOF
    exit 0
}

# ── The prompt ──────────────────────────────────────────────────────────────
# The prompt text lives as a SPM resource inside the buttonheist CLI — same
# idea as Bundle.main in an iOS app. SPM puts it in a .bundle directory
# next to the binary. We just find the binary and read the file.

# --- BEGIN BAKE TARGET ---
BUNDLE_NAME="ButtonHeistCLI_ButtonHeistCLIExe.bundle"
PROMPT_FILENAME="integration-prompt.md"

load_prompt() {
    local bh bh_dir prompt_file
    bh="$(which buttonheist 2>/dev/null || true)"
    if [ -z "$bh" ]; then
        fail "buttonheist not found on PATH. Install it first: brew install RoyalPineapple/tap/buttonheist"
    fi
    # Follow symlinks to the real binary (Homebrew uses symlinks)
    bh="$(readlink -f "$bh" 2>/dev/null || realpath "$bh" 2>/dev/null || echo "$bh")"
    bh_dir="$(dirname "$bh")"
    prompt_file="$bh_dir/$BUNDLE_NAME/$PROMPT_FILENAME"
    if [ ! -f "$prompt_file" ]; then
        fail "Integration prompt not found at $prompt_file"
    fi
    INTEGRATION_PROMPT="$(cat "$prompt_file")"
}
# --- END BAKE TARGET ---

# ── Supported models ────────────────────────────────────────────────────────

model_binary() {
    case "$1" in
        claude)  echo "claude" ;;
        gemini)  echo "gemini" ;;
        codex)   echo "codex" ;;
        copilot) echo "copilot" ;;
        aider)   echo "aider" ;;
        *)       echo "" ;;
    esac
}

model_npm_package() {
    case "$1" in
        claude)  echo "@anthropic-ai/claude-code" ;;
        gemini)  echo "@google/gemini-cli" ;;
        codex)   echo "@openai/codex" ;;
        copilot) echo "@github/copilot" ;;
        *)       echo "" ;;
    esac
}

model_install_hint() {
    case "$1" in
        claude|gemini|codex|copilot) echo "npm install -g $(model_npm_package "$1")" ;;
        aider)   echo "pip install aider-chat" ;;
        *)       echo "" ;;
    esac
}

model_display_name() {
    case "$1" in
        claude)  echo "Claude Code (Anthropic)" ;;
        gemini)  echo "Gemini CLI (Google)" ;;
        codex)   echo "Codex CLI (OpenAI)" ;;
        copilot) echo "GitHub Copilot CLI" ;;
        aider)   echo "Aider" ;;
        *)       echo "$1" ;;
    esac
}

model_tier() {
    case "$1" in
        claude|codex|copilot) echo "paid" ;;
        gemini|aider)         echo "free" ;;
        *)                    echo "unknown" ;;
    esac
}

# Run the agent with the prompt. $1 = model, $2 = project dir
model_exec() {
    local model="$1" project_dir="$2"
    cd "$project_dir"
    case "$model" in
        claude)
            claude -p "$INTEGRATION_PROMPT"
            ;;
        gemini)
            gemini -y -p "$INTEGRATION_PROMPT"
            ;;
        codex)
            codex --approval-mode suggest "$INTEGRATION_PROMPT"
            ;;
        copilot)
            copilot -p "$INTEGRATION_PROMPT"
            ;;
        aider)
            aider --message "$INTEGRATION_PROMPT"
            ;;
        *)
            fail "Unknown model: $model"
            ;;
    esac
}

# ── Parse arguments ─────────────────────────────────────────────────────────

MODEL=""
PROJECT_DIR=""
PRINT_PROMPT=false

for arg in "$@"; do
    case "$arg" in
        -h|--help)         usage ;;
        --print-prompt)    PRINT_PROMPT=true ;;
        claude|gemini|codex|copilot|aider)
            MODEL="$arg" ;;
        *)
            PROJECT_DIR="$arg" ;;
    esac
done

# ── Load prompt (deferred until after --help parsing) ───────────────────────

load_prompt

# ── --print-prompt: dump and exit ───────────────────────────────────────────

if $PRINT_PROMPT; then
    printf "${BOLD}Button Heist — Integration Prompt${RESET}\n"
    printf "${DIM}Paste this into any AI coding agent.${RESET}\n\n"
    printf "%s\n" "$INTEGRATION_PROMPT"
    exit 0
fi

# ── Normal flow ─────────────────────────────────────────────────────────────

MODEL="${MODEL:-claude}"
PROJECT_DIR="${PROJECT_DIR:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)" || fail "Directory not found: ${PROJECT_DIR}"

DISPLAY_NAME="$(model_display_name "$MODEL")"
BINARY="$(model_binary "$MODEL")"
TIER="$(model_tier "$MODEL")"

printf "\n${BOLD}Button Heist — Agentic Integration${RESET}\n"
printf "${DIM}${DISPLAY_NAME} will inspect your project and wire in TheInsideJob.${RESET}\n\n"
dim "Model:  $MODEL ($TIER)"
dim "Target: $PROJECT_DIR"

# ── Preflight: coding agent ────────────────────────────────────────────────

step "Checking for $DISPLAY_NAME"

if [ -z "$BINARY" ]; then
    fail "Unknown model: $MODEL. Run 'buttonheist-integrate --help' for supported models."
fi

if ! command -v "$BINARY" &>/dev/null; then
    INSTALL_HINT="$(model_install_hint "$MODEL")"
    echo ""
    printf "  %s is required but not installed.\n" "$DISPLAY_NAME"
    printf "  Install it with:\n\n"
    printf "    ${BOLD}%s${RESET}\n\n" "$INSTALL_HINT"

    case "$MODEL" in
        claude|gemini|codex|copilot)
            read -rp "  Install now with npm? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                NPM_PACKAGE="$(model_npm_package "$MODEL")"
                if command -v npm &>/dev/null; then
                    npm install -g "$NPM_PACKAGE"
                    ok "Installed $DISPLAY_NAME"
                elif command -v brew &>/dev/null; then
                    printf "\n  npm not found. Node.js is required.\n"
                    read -rp "  Install Node.js via Homebrew? [y/N] " node_answer
                    if [[ "$node_answer" =~ ^[Yy]$ ]]; then
                        brew install node
                        npm install -g "$NPM_PACKAGE"
                        ok "Installed node + $DISPLAY_NAME"
                    else
                        fail "Node.js is required. Install it first: https://nodejs.org"
                    fi
                else
                    fail "Neither npm nor Homebrew found. Install Node.js first: https://nodejs.org"
                fi
            else
                fail "$DISPLAY_NAME is required. Install it and re-run."
            fi
            ;;
        aider)
            read -rp "  Install now? [y/N] " answer
            if [[ "$answer" =~ ^[Yy]$ ]]; then
                if command -v pip3 &>/dev/null; then
                    pip3 install aider-chat
                    ok "Installed aider"
                elif command -v pip &>/dev/null; then
                    pip install aider-chat
                    ok "Installed aider"
                elif command -v brew &>/dev/null; then
                    brew install aider
                    ok "Installed aider"
                else
                    fail "Neither pip nor Homebrew found. Install Python first."
                fi
            else
                fail "$DISPLAY_NAME is required. Install it and re-run."
            fi
            ;;
        *)
            fail "$DISPLAY_NAME is required. Install it and re-run."
            ;;
    esac
fi

ok "Found: $BINARY"

# ── Preflight: buttonheist CLI ──────────────────────────────────────────────

step "Checking for Button Heist CLI"

if command -v buttonheist &>/dev/null; then
    ok "buttonheist $(buttonheist --version 2>/dev/null || echo '(installed)')"
else
    warn "buttonheist CLI not found — install with: brew install RoyalPineapple/tap/buttonheist"
    dim "The integration will still work, but you need the CLI to use Button Heist afterward."
fi

# ── Resolve MCP binary for .mcp.json ────────────────────────────────────────

MCP_BIN=""
if command -v buttonheist-mcp &>/dev/null; then
    MCP_BIN="buttonheist-mcp"
elif [ -x "$(brew --prefix 2>/dev/null)/bin/buttonheist-mcp" ]; then
    MCP_BIN="buttonheist-mcp"
fi

# ── Write .mcp.json if missing ──────────────────────────────────────────────

step "Configuring MCP"

MCP_CONFIG="$PROJECT_DIR/.mcp.json"

if [ -f "$MCP_CONFIG" ]; then
    if grep -q "buttonheist" "$MCP_CONFIG"; then
        ok ".mcp.json already has buttonheist"
    else
        warn ".mcp.json exists but no buttonheist entry — the agent will add it"
    fi
elif [ -n "$MCP_BIN" ]; then
    cat > "$MCP_CONFIG" <<EOF
{
  "mcpServers": {
    "buttonheist": {
      "command": "$MCP_BIN",
      "args": []
    }
  }
}
EOF
    ok "Created .mcp.json → $MCP_BIN"
else
    warn "Skipping .mcp.json — buttonheist-mcp not found"
fi

# ── Fair warning ───────────────────────────────────────────────────────────

echo ""
printf "${YELLOW}${BOLD}  ┌──────────────────────────────────────────────────────────────┐${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}                                                              ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}  You are about to let an AI agent ${BOLD}modify your Xcode project${RESET}.   ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}                                                              ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}  It will edit build files, add dependencies, and touch your   ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}  source code. That is the whole point of this tool. If you    ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}  don't trust an agent with your project, this isn't for you.  ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}                                                              ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}  But if you're not on a clean git branch,                     ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}  ${RED}${BOLD}now would be a great time to commit${RESET}.                        ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  │${RESET}                                                              ${YELLOW}${BOLD}│${RESET}\n"
printf "${YELLOW}${BOLD}  └──────────────────────────────────────────────────────────────┘${RESET}\n"
echo ""

# Check for dirty working tree and warn harder
if command -v git &>/dev/null && git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    if ! git -C "$PROJECT_DIR" diff --quiet 2>/dev/null || ! git -C "$PROJECT_DIR" diff --cached --quiet 2>/dev/null; then
        warn "You have uncommitted changes. Brave."
    else
        warn "Clean working tree. You've done this before."
    fi
else
    warn "Not a git repo. Living dangerously."
fi

read -rp "  Let the agent loose? [y/N] " answer
if ! [[ "$answer" =~ ^[Yy]$ ]]; then
    dim "No judgment. Commit first, come back when you're ready."
    exit 0
fi

# ── Hand off to the agent ──────────────────────────────────────────────────

step "Launching $DISPLAY_NAME"
echo ""

model_exec "$MODEL" "$PROJECT_DIR"

# ── Done ────────────────────────────────────────────────────────────────────

echo ""
printf "${GREEN}${BOLD}Integration complete.${RESET}\n\n"
printf "  ${DIM}# Discover devices${RESET}\n"
printf "  buttonheist list\n\n"
printf "  ${DIM}# Interactive session${RESET}\n"
printf "  buttonheist session\n\n"

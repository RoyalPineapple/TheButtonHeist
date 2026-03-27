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
# Shared across every model. This is the brains of the operation.

INTEGRATION_PROMPT='You are integrating Button Heist into this iOS project. Your job is to add the
TheInsideJob framework so it auto-starts in DEBUG builds. TheInsideJob runs an
in-app server that lets AI agents (and humans) control the app via CLI or MCP.

No initialization code is needed — the framework auto-starts via an ObjC +load
hook when the binary is linked. You just need to: add the dependency, add the
import, and add Info.plist entries.

## Step 1: Identify the build system

Look at the project root and determine which build system and dependency manager
is in use. Check for these files in order:

| File                | Build system       |
|---------------------|--------------------|
| Package.swift       | Swift Package Manager |
| Podfile             | CocoaPods          |
| Cartfile            | Carthage           |
| Project.swift       | Tuist              |
| project.yml         | XcodeGen           |
| BUILD / BUILD.bazel | Bazel              |
| *.xcodeproj only    | Bare Xcode project |
| *.xcworkspace       | Xcode workspace (check what is inside) |

A project may use multiple (e.g. CocoaPods + Xcode workspace, or Tuist + SPM).
Identify the primary dependency management path.

## Step 2: Identify the app target

Find the main iOS application target — the one that produces a .app bundle.
Skip test targets, app extensions (widgets, intents, share extensions), watch
apps, and framework/library targets.

If there are multiple app targets (e.g. a debug app and a production app),
prefer the debug/development target. If unclear, ask the user which target.

## Step 3: Add the dependency

### Swift Package Manager (Package.swift)

Add to the package dependencies array:

```swift
.package(url: "https://github.com/RoyalPineapple/ButtonHeist.git", branch: "main")
```

Add to the app target dependencies:

```swift
.product(name: "TheInsideJob", package: "ButtonHeist")
```

TheInsideJob is iOS-only. If the package has cross-platform targets, use a
platform condition:

```swift
.product(name: "TheInsideJob", package: "ButtonHeist", condition: .when(platforms: [.iOS]))
```

### Xcode project with SPM (no Package.swift, just .xcodeproj)

The dependency needs to be added through the Xcode project file. Use:

```bash
xcodebuild -project <Project>.xcodeproj \
  -addPackageDependency https://github.com/RoyalPineapple/ButtonHeist.git \
  -packageVersion branch:main
```

If that command is not available or fails, instruct the user:
"Open your project in Xcode > File > Add Package Dependencies >
paste https://github.com/RoyalPineapple/ButtonHeist.git > add TheInsideJob
to your app target."

### CocoaPods (Podfile)

Add to the app target pod block:

```ruby
target '\''YourApp'\'' do
  # Button Heist — auto-starts in DEBUG builds
  pod '\''ButtonHeist/TheInsideJob'\'', :git => '\''https://github.com/RoyalPineapple/ButtonHeist.git'\'', :branch => '\''main'\''
end
```

Then run `pod install`.

If there is no .podspec in the Button Heist repo (there is not one yet), fall
back to adding it as an SPM dependency alongside CocoaPods. Many projects use
both. Add the SPM package to the .xcworkspace via Xcode package dependency UI.

### Carthage (Cartfile)

Add to Cartfile:

```
github "RoyalPineapple/ButtonHeist" "main"
```

Then: `carthage update --use-xcframeworks --platform iOS`

Link TheInsideJob.xcframework to the app target. If Carthage cannot build it,
fall back to SPM — tell the user Carthage is not supported yet and add as an
SPM dependency instead.

### Tuist (Project.swift)

1. Add to `Tuist/Package.swift`:

```swift
.package(url: "https://github.com/RoyalPineapple/ButtonHeist.git", branch: "main")
```

2. Run `tuist install` to fetch it.

3. In the app target definition, add the dependency:

```swift
.external(name: "TheInsideJob")
```

4. Run `tuist generate` to regenerate the Xcode project.

### XcodeGen (project.yml)

Add to the `packages` section:

```yaml
packages:
  ButtonHeist:
    url: https://github.com/RoyalPineapple/ButtonHeist.git
    branch: main
```

Add to the app target dependencies:

```yaml
targets:
  YourApp:
    dependencies:
      - package: ButtonHeist
        product: TheInsideJob
```

Then run `xcodegen generate`.

### Bazel (BUILD files)

Add as a repository rule in WORKSPACE/MODULE.bazel:

```starlark
git_override(
    module_name = "ButtonHeist",
    remote = "https://github.com/RoyalPineapple/ButtonHeist.git",
    branch = "main",
)
```

Or with `rules_swift_package_manager`:

```starlark
swift_package(
    name = "ButtonHeist",
    url = "https://github.com/RoyalPineapple/ButtonHeist.git",
    branch = "main",
)
```

Add `@ButtonHeist//:TheInsideJob` to the app target deps.

If the Bazel setup is complex or non-standard, describe what needs to happen
and let the user wire it in. Do not guess at custom macros.

### Bare Xcode project (no dependency manager)

Add ButtonHeist as an SPM dependency directly in the .xcodeproj. This is the
simplest path — Xcode has built-in SPM support since Xcode 11.

If the project deliberately avoids SPM (rare), instruct the user to build
TheInsideJob.xcframework from source and embed it manually.

## Step 4: Add the import

Find the app entry point. Look for these patterns:

**SwiftUI app:**
```swift
@main
struct SomeApp: App {
```

**UIKit AppDelegate:**
```swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
```
or
```swift
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
```

**UIKit SceneDelegate (iOS 13+):**
The entry point is still AppDelegate. The import goes in AppDelegate.swift.

**ObjC main.m / main.swift:**
Add the import in AppDelegate.swift. If AppDelegate is also ObjC, add it in
the bridging header or a Swift file compiled into the target.

**No obvious entry point:**
Search for `UIApplication.shared`, `UIWindow`, `@main`, `@UIApplicationMain`,
or `INFOPLIST_KEY_UIMainStoryboardFile` build setting.

Add the import wrapped in a DEBUG guard:

```swift
#if DEBUG
import TheInsideJob
#endif
```

Place it with the other imports at the top of the file.

## Step 5: Info.plist entries

TheInsideJob uses Bonjour for device discovery. iOS requires two Info.plist
keys for local network access:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Button Heist uses the local network for UI automation.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

How to add them depends on the project:

**Traditional Info.plist file:**
Find the app Info.plist (check the target build settings for `INFOPLIST_FILE`)
and add the keys directly.

**Xcode-generated Info.plist (Xcode 15+):**
If there is no Info.plist file and the target uses `GENERATE_INFOPLIST_FILE = YES`,
add the keys via build settings:

```
INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Button Heist uses the local network for UI automation."
INFOPLIST_KEY_NSBonjourServices = _buttonheist._tcp
```

Or create an Info.plist file and set `INFOPLIST_FILE` to point at it.

**Tuist:**
Add to the target infoPlist parameter:

```swift
.extendingDefault(with: [
    "NSLocalNetworkUsageDescription": "Button Heist uses the local network for UI automation.",
    "NSBonjourServices": ["_buttonheist._tcp"],
])
```

**XcodeGen (project.yml):**
```yaml
info:
  properties:
    NSLocalNetworkUsageDescription: "Button Heist uses the local network for UI automation."
    NSBonjourServices:
      - _buttonheist._tcp
```

**Bazel:**
Add to the `ios_application` rule infoplists attribute.

**Important:** If the app already has `NSBonjourServices`, append
`_buttonheist._tcp` to the existing array — do not replace it.

## Step 6: Verify the build

Run a build to confirm everything compiles:

```bash
# For Xcode projects/workspaces
xcodebuild -workspace <Workspace>.xcworkspace -scheme <AppScheme> \
  -destination '\''generic/platform=iOS Simulator'\'' build

# For SPM
swift build

# For Tuist
tuist generate && tuist build <scheme>

# For Bazel
bazel build //path/to:<app_target>
```

If the build fails, read the error and fix it. Common issues:
- Platform mismatch (TheInsideJob is iOS-only, do not link it to macOS targets)
- Minimum deployment target too low (requires iOS 17.0+)
- Swift tools version mismatch (requires swift-tools-version: 6.0+)

## Step 7: Print summary

After successful integration, print:
- What files you changed
- How to build and run the app
- How to connect: `buttonheist list` then `buttonheist session`
- Note that .mcp.json is configured (if it exists) for AI agent access

Be concise. Make the minimal changes needed. Do not refactor, rename, or
"improve" anything else in the project.'

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

model_install_hint() {
    case "$1" in
        claude)  echo "npm install -g @anthropic-ai/claude-code" ;;
        gemini)  echo "npm install -g @google/gemini-cli" ;;
        codex)   echo "npm install -g @openai/codex" ;;
        copilot) echo "npm install -g @github/copilot" ;;
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
            codex exec --full-auto "$INTEGRATION_PROMPT"
            ;;
        copilot)
            copilot -p "$INTEGRATION_PROMPT"
            ;;
        aider)
            aider --message "$INTEGRATION_PROMPT" --yes
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
                if command -v npm &>/dev/null; then
                    eval "$INSTALL_HINT"
                    ok "Installed $DISPLAY_NAME"
                elif command -v brew &>/dev/null; then
                    printf "\n  npm not found. Installing Node.js via Homebrew first...\n"
                    brew install node
                    eval "$INSTALL_HINT"
                    ok "Installed node + $DISPLAY_NAME"
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
    MCP_BIN="$(command -v buttonheist-mcp)"
elif [ -x "$(brew --prefix 2>/dev/null)/bin/buttonheist-mcp" ]; then
    MCP_BIN="$(brew --prefix)/bin/buttonheist-mcp"
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

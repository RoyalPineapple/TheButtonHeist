#!/usr/bin/env bash
# Deterministic end-to-end smoke test for BH Demo through the Button Heist CLI.
#
# The script creates a fresh simulator, builds the demo app and CLI, launches
# TheInsideJob with deterministic connection metadata, drives a short UI flow,
# and deletes the simulator unless --keep-simulator is passed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

KEEP_SIMULATOR=false
SKIP_GENERATE=false
SIM_NAME=""
SIM_UDID=""
DEVICE_TYPE="iPhone 16 Pro"
RUNTIME=""
PORT=""
TOKEN=""
APP=""
CLI_CONFIGURATION="debug"
HEIST_PATH=""
SKIP_HEIST_PLAYBACK=false

usage() {
    cat <<'EOF'
Usage: scripts/e2e-demo-smoke.sh [options]

Options:
  --keep-simulator       Leave the simulator booted after the smoke test.
  --skip-generate        Skip scripts/generate-project.sh before building.
  --sim-name NAME        Simulator name. Defaults to buttonheist-e2e-{worktree}.
  --sim-udid UDID        Reuse an existing simulator instead of creating one.
  --device-type NAME     Simulator device type. Defaults to "iPhone 16 Pro".
  --runtime RUNTIME      Runtime identifier, name, or version. Defaults to latest available iOS runtime.
  --port PORT            InsideJob port. Defaults to a deterministic port derived from this worktree.
  --token TOKEN          InsideJob token and driver id. Defaults to the simulator name.
  --app PATH             Reuse a prebuilt BHDemo.app instead of building it.
  --cli-configuration C  SwiftPM CLI configuration: debug or release. Defaults to debug.
  --heist PATH           Heist fixture to replay. Defaults to tests/fixtures/bh-demo-smoke.heist.
  --skip-heist-playback  Skip replaying the recorded heist fixture.
  -h, --help             Show this help.

This harness is intentionally CLI-only: it does not require an MCP server or a
loaded MCP host session.
EOF
}

log() {
    printf '==> %s\n' "$*"
}

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || fail "missing required tool: $1"
}

sanitize_identifier() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -cs '[:alnum:]' '-' \
        | sed 's/^-//; s/-$//; s/--*/-/g'
}

derive_port() {
    local seed="$1"
    local checksum
    checksum=$(printf '%s' "$seed" | cksum | awk '{print $1}')
    printf '%s\n' "$((20000 + (checksum % 10000)))"
}

validate_port() {
    local value="$1"
    if [[ -z "$value" || "$value" == *[!0-9]* ]]; then
        fail "port must be numeric"
    fi
    if (( value < 1024 || value > 65535 )); then
        fail "port must be between 1024 and 65535"
    fi
}

port_is_open() {
    nc -z 127.0.0.1 "$1" >/dev/null 2>&1
}

resolve_runtime() {
    local requested="$1"
    local runtime_id
    runtime_id="$(
        xcrun simctl list runtimes -j | jq -er --arg requested "$requested" '
            [.runtimes[] | select(.platform == "iOS" and .isAvailable == true)] as $runtimes
            | if ($runtimes | length) == 0 then
                empty
              elif $requested == "" then
                $runtimes
                | sort_by(.version | split(".") | map(tonumber))
                | last
                | .identifier
              else
                $runtimes[]
                | select(.identifier == $requested or .name == $requested or .version == $requested)
                | .identifier
              end
        '
    )" || true
    [[ -n "$runtime_id" ]] || fail "iOS runtime not found: ${requested:-latest available}"
    printf '%s\n' "$runtime_id"
}

simulators_named() {
    local name="$1"
    xcrun simctl list devices -j | jq -r --arg name "$name" '
        .devices[]
        | .[]
        | select(.name == $name)
        | .udid
    '
}

delete_simulators_named() {
    local name="$1"
    local udid
    simulators_named "$name" | while IFS= read -r udid; do
        [[ -z "$udid" ]] && continue
        log "Deleting stale simulator $name ($udid)"
        xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
        xcrun simctl delete "$udid" >/dev/null 2>&1 || true
    done
}

wait_for_port() {
    local port="$1"
    local attempts=30
    local remaining="$attempts"
    while (( remaining > 0 )); do
        if port_is_open "$port"; then
            return 0
        fi
        remaining=$((remaining - 1))
        sleep 1
    done
    fail "InsideJob did not open port $port within ${attempts}s"
}

json_expect_ok() {
    local context="$1"
    local status
    status="$(jq -r '.status // "missing"')" || fail "$context output is not valid JSON"
    [[ "$status" == "ok" ]] || fail "$context failed: expected status=ok, got $status"
}

json_expect_connected() {
    local connected
    connected="$(jq -r '.connected // false')" || fail "session state output is not valid JSON"
    [[ "$connected" == "true" ]] || fail "session state failed: expected connected=true"
}

json_screen_title() {
    jq -r '.interface.navigation.screenTitle // ""'
}

expect_screen_title() {
    local expected="$1"
    local actual
    actual=$(json_screen_title)
    if [[ "$actual" != "$expected" ]]; then
        fail "expected screen title '$expected', got '$actual'"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-simulator)
            KEEP_SIMULATOR=true
            shift
            ;;
        --skip-generate)
            SKIP_GENERATE=true
            shift
            ;;
        --sim-name)
            SIM_NAME="${2:-}"
            [[ -n "$SIM_NAME" ]] || fail "--sim-name requires a value"
            shift 2
            ;;
        --sim-udid)
            SIM_UDID="${2:-}"
            [[ -n "$SIM_UDID" ]] || fail "--sim-udid requires a value"
            shift 2
            ;;
        --device-type)
            DEVICE_TYPE="${2:-}"
            [[ -n "$DEVICE_TYPE" ]] || fail "--device-type requires a value"
            shift 2
            ;;
        --runtime)
            RUNTIME="${2:-}"
            [[ -n "$RUNTIME" ]] || fail "--runtime requires a value"
            shift 2
            ;;
        --port)
            PORT="${2:-}"
            [[ -n "$PORT" ]] || fail "--port requires a value"
            shift 2
            ;;
        --token)
            TOKEN="${2:-}"
            [[ -n "$TOKEN" ]] || fail "--token requires a value"
            shift 2
            ;;
        --app)
            APP="${2:-}"
            [[ -n "$APP" ]] || fail "--app requires a value"
            shift 2
            ;;
        --cli-configuration)
            CLI_CONFIGURATION="${2:-}"
            [[ -n "$CLI_CONFIGURATION" ]] || fail "--cli-configuration requires a value"
            shift 2
            ;;
        --heist)
            HEIST_PATH="${2:-}"
            [[ -n "$HEIST_PATH" ]] || fail "--heist requires a value"
            shift 2
            ;;
        --skip-heist-playback)
            SKIP_HEIST_PLAYBACK=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

require_tool xcrun
require_tool xcodebuild
require_tool swift
require_tool nc
require_tool cksum
require_tool awk
require_tool sed
require_tool jq

WORKTREE_ID="$(sanitize_identifier "$(basename "$REPO_ROOT")")"
[[ -n "$WORKTREE_ID" ]] || WORKTREE_ID="workspace"

if [[ -z "$SIM_NAME" ]]; then
    SIM_NAME="buttonheist-e2e-$WORKTREE_ID"
fi
if [[ -z "$TOKEN" ]]; then
    TOKEN="$SIM_NAME"
fi
if [[ -z "$PORT" ]]; then
    PORT="$(derive_port "$REPO_ROOT")"
fi
if [[ -z "$HEIST_PATH" ]]; then
    HEIST_PATH="$REPO_ROOT/tests/fixtures/bh-demo-smoke.heist"
fi
validate_port "$PORT"
case "$CLI_CONFIGURATION" in
    debug|release) ;;
    *) fail "--cli-configuration must be debug or release" ;;
esac

DEVICE_ENDPOINT="127.0.0.1:$PORT"
DERIVED_DATA="${TMPDIR:-/tmp}/buttonheist-e2e-${WORKTREE_ID}-derived-data"
BUILD_LOG="${TMPDIR:-/tmp}/buttonheist-e2e-${WORKTREE_ID}-xcodebuild.log"
BUTTONHEIST_BIN="$REPO_ROOT/ButtonHeistCLI/.build/$CLI_CONFIGURATION/buttonheist"
OWNS_SIMULATOR=false
APP_LAUNCHED=false

cleanup() {
    local status=$?
    if [[ -n "$SIM_UDID" && "$APP_LAUNCHED" == true ]]; then
        xcrun simctl terminate "$SIM_UDID" com.buttonheist.testapp >/dev/null 2>&1 || true
    fi
    if [[ -n "$SIM_UDID" && "$OWNS_SIMULATOR" == true && "$KEEP_SIMULATOR" == false ]]; then
        log "Deleting simulator $SIM_NAME ($SIM_UDID)"
        xcrun simctl shutdown "$SIM_UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$SIM_UDID" >/dev/null 2>&1 || true
    elif [[ -n "$SIM_UDID" && "$OWNS_SIMULATOR" == true ]]; then
        log "Keeping simulator $SIM_NAME ($SIM_UDID)"
    fi
    rm -rf "$DERIVED_DATA"
    rm -f "$BUILD_LOG"
    exit "$status"
}
trap cleanup EXIT

run_cli_json() {
    BUTTONHEIST_DEVICE="$DEVICE_ENDPOINT" \
    BUTTONHEIST_TOKEN="$TOKEN" \
    BUTTONHEIST_DRIVER_ID="$TOKEN" \
    "$BUTTONHEIST_BIN" "$@" --format json --quiet
}

if port_is_open "$PORT"; then
    fail "port $PORT is already in use; pass --port to choose a deterministic alternate"
fi

log "Configuration"
printf '    worktree: %s\n' "$REPO_ROOT"
printf '    simulator: %s\n' "$SIM_NAME"
printf '    endpoint: %s\n' "$DEVICE_ENDPOINT"
printf '    token/id: %s\n' "$TOKEN"
printf '    cli config: %s\n' "$CLI_CONFIGURATION"
if [[ "$SKIP_HEIST_PLAYBACK" == false ]]; then
    printf '    heist: %s\n' "$HEIST_PATH"
    [[ -f "$HEIST_PATH" ]] || fail "heist fixture not found at $HEIST_PATH"
fi

log "Preparing dependencies"
git submodule update --init --recursive submodules/AccessibilitySnapshotBH
if [[ "$SKIP_GENERATE" == false ]]; then
    ./scripts/generate-project.sh
fi

log "Building ButtonHeistCLI"
(cd ButtonHeistCLI && swift build -c "$CLI_CONFIGURATION" --quiet)

log "Preparing simulator"
if [[ -n "$SIM_UDID" ]]; then
    log "Using existing simulator $SIM_UDID"
    xcrun simctl boot "$SIM_UDID" >/dev/null 2>&1 || true
else
    delete_simulators_named "$SIM_NAME"
    RUNTIME_ID="$(resolve_runtime "$RUNTIME")"
    SIM_UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME_ID")"
    OWNS_SIMULATOR=true
    xcrun simctl boot "$SIM_UDID"
fi
xcrun simctl bootstatus "$SIM_UDID" -b

if [[ -z "$APP" ]]; then
    log "Building BH Demo"
    rm -rf "$DERIVED_DATA"
    if ! xcodebuild \
        -workspace ButtonHeist.xcworkspace \
        -scheme "BH Demo" \
        -destination "platform=iOS Simulator,id=$SIM_UDID" \
        -derivedDataPath "$DERIVED_DATA" \
        build > "$BUILD_LOG" 2>&1; then
        cat "$BUILD_LOG" >&2
        fail "BH Demo build failed"
    fi
    APP="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/BHDemo.app"
else
    log "Using prebuilt BH Demo"
fi
[[ -d "$APP" ]] || fail "built app not found at $APP"

log "Installing and launching BH Demo"
xcrun simctl install "$SIM_UDID" "$APP"
SIMCTL_CHILD_INSIDEJOB_PORT="$PORT" \
SIMCTL_CHILD_INSIDEJOB_TOKEN="$TOKEN" \
SIMCTL_CHILD_INSIDEJOB_ID="$TOKEN" \
xcrun simctl launch "$SIM_UDID" com.buttonheist.testapp >/dev/null
APP_LAUNCHED=true
wait_for_port "$PORT"

log "Verifying CLI connection"
SESSION_JSON="$(run_cli_json get_session_state)"
printf '%s' "$SESSION_JSON" | json_expect_ok "get_session_state"
printf '%s' "$SESSION_JSON" | json_expect_connected

log "Verifying root interface"
ROOT_JSON="$(run_cli_json get_interface --timeout 15)"
printf '%s' "$ROOT_JSON" | json_expect_ok "root get_interface"
printf '%s' "$ROOT_JSON" | expect_screen_title "ButtonHeist Demo"

log "Navigating to Controls Demo"
CONTROLS_ACTION_JSON="$(run_cli_json activate --label "Controls Demo" --traits button --timeout 15)"
printf '%s' "$CONTROLS_ACTION_JSON" | json_expect_ok "activate Controls Demo"
CONTROLS_JSON="$(run_cli_json get_interface --timeout 15)"
printf '%s' "$CONTROLS_JSON" | json_expect_ok "Controls Demo get_interface"
printf '%s' "$CONTROLS_JSON" | expect_screen_title "Controls Demo"

log "Navigating to Display"
DISPLAY_ACTION_JSON="$(run_cli_json activate --label "Display" --traits button --timeout 15)"
printf '%s' "$DISPLAY_ACTION_JSON" | json_expect_ok "activate Display"
DISPLAY_JSON="$(run_cli_json get_interface --timeout 15)"
printf '%s' "$DISPLAY_JSON" | json_expect_ok "Display get_interface"
printf '%s' "$DISPLAY_JSON" | expect_screen_title "Display"

log "Navigating back to Controls Demo"
BACK_JSON="$(run_cli_json activate --label "Controls Demo" --traits button backButton --timeout 15)"
printf '%s' "$BACK_JSON" | json_expect_ok "activate back to Controls Demo"
FINAL_JSON="$(run_cli_json get_interface --timeout 15)"
printf '%s' "$FINAL_JSON" | json_expect_ok "final get_interface"
printf '%s' "$FINAL_JSON" | expect_screen_title "Controls Demo"

if [[ "$SKIP_HEIST_PLAYBACK" == false ]]; then
    log "Returning to root for heist playback"
    ROOT_BACK_JSON="$(run_cli_json activate --label "ButtonHeist Demo" --traits button backButton --timeout 15)"
    printf '%s' "$ROOT_BACK_JSON" | json_expect_ok "activate back to ButtonHeist Demo"
    PLAYBACK_ROOT_JSON="$(run_cli_json get_interface --timeout 15)"
    printf '%s' "$PLAYBACK_ROOT_JSON" | json_expect_ok "playback root get_interface"
    printf '%s' "$PLAYBACK_ROOT_JSON" | expect_screen_title "ButtonHeist Demo"

    log "Replaying recorded heist"
    PLAYBACK_JSON="$(run_cli_json play_heist --input "$HEIST_PATH")"
    printf '%s' "$PLAYBACK_JSON" | json_expect_ok "play_heist"
    PLAYBACK_FINAL_JSON="$(run_cli_json get_interface --timeout 15)"
    printf '%s' "$PLAYBACK_FINAL_JSON" | json_expect_ok "playback final get_interface"
    printf '%s' "$PLAYBACK_FINAL_JSON" | expect_screen_title "Controls Demo"
fi

log "Demo smoke test passed"

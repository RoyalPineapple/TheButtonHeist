#!/bin/zsh
# Benchmark harness for Button Heist vs ios-simulator-mcp.
#
# Usage:
#   ./benchmarks/run.sh --sim-udid <UDID> --port <PORT> [options]
#
# Options:
#   --sim-udid UDID   Target simulator (required)
#   --port PORT       App port on 127.0.0.1 (required). Passed to app via
#                     SIMCTL_CHILD_INSIDEJOB_PORT at launch.
#   -t TASK           Task(s), comma-separated (default: all in benchmarks/tasks/)
#   -c CONFIG         Config(s), comma-separated: idb, bh, bh-batch, bh-expect
#   -n COUNT          Trials per cell (default: 5)
#   -m MODEL          Claude model (default: claude-sonnet-4-6)
#   --max-turns N     Max turns per trial (default: 80)
#   --wall-timeout S  Max wall-clock seconds per trial (default: 600)
#   --dry-run         Print schedule without running
#   --resume DIR      Resume a previous run, skipping completed trials
#   -h                Show this help
#
# Multi-sim parallel usage:
#   BH_SIM=8A501DF7-97A9-4825-B0AC-552743784E1D   # iPhone 16 Pro
#   IDB_SIM=EF8A77E7-9EF0-4F70-A374-0FA334D91E59  # Oslo Bench
#
#   ./benchmarks/run.sh --sim-udid $BH_SIM  --port 1455 -c bh,bh-batch,bh-expect -n 5 &
#   ./benchmarks/run.sh --sim-udid $IDB_SIM --port 1456 -c idb -n 5 &
#   wait
#
# Prerequisites:
#   - AccessibilityTestApp installed on target simulator
#   - ButtonHeistMCP built: cd ButtonHeistMCP && swift build -c release
#   - For idb config: npx available
#   - claude CLI installed and authenticated

set -uo pipefail
# Note: -e intentionally omitted. The harness must survive individual trial
# failures — claude -p can exit non-zero, timeout can kill trials, etc.
# Each trial's exit code is captured explicitly.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# --- Defaults ---
ALL_TASKS=""
ALL_CONFIGS="bh,bh-batch,bh-expect,idb"
TRIAL_COUNT=5
MODEL="claude-sonnet-4-6"
MAX_TURNS=200
WALL_TIMEOUT=600
DRY_RUN=false
RESUME_DIR=""
SIM_UDID=""
APP_PORT=""
SAVE_BASELINE=""

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t) ALL_TASKS="$2"; shift 2 ;;
        -c) ALL_CONFIGS="$2"; shift 2 ;;
        -n) TRIAL_COUNT="$2"; shift 2 ;;
        -m) MODEL="$2"; shift 2 ;;
        --sim-udid) SIM_UDID="$2"; shift 2 ;;
        --port) APP_PORT="$2"; shift 2 ;;
        --max-turns) MAX_TURNS="$2"; shift 2 ;;
        --wall-timeout) WALL_TIMEOUT="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --resume) RESUME_DIR="$2"; shift 2 ;;
        --save-baseline) SAVE_BASELINE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Required flags ---
if [ -z "$SIM_UDID" ]; then
    echo "Error: --sim-udid required. List booted sims: xcrun simctl list devices booted" >&2
    exit 1
fi
if [ -z "$APP_PORT" ]; then
    echo "Error: --port required (e.g., --port 1455)" >&2
    exit 1
fi

# Verify simulator is booted
if ! xcrun simctl list devices booted -j 2>/dev/null \
    | jq -e --arg udid "$SIM_UDID" '.devices | to_entries[] | .value[] | select(.udid == $udid)' >/dev/null 2>&1; then
    echo "Error: Simulator $SIM_UDID is not booted" >&2
    exit 1
fi

# --- Constants ---
BUNDLE_ID="com.buttonheist.testapp"
APP_TOKEN="INJECTED-TOKEN-12345"

# --- Discover tasks ---
if [ -z "$ALL_TASKS" ]; then
    ALL_TASKS=$(ls "$SCRIPT_DIR/tasks/"*.txt 2>/dev/null | xargs -I{} basename {} .txt | paste -sd, -)
fi
if [ -z "$ALL_TASKS" ]; then
    echo "Error: No task files found in $SCRIPT_DIR/tasks/" >&2
    exit 1
fi

TASKS=("${(@s/,/)ALL_TASKS}")
CONFIGS=("${(@s/,/)ALL_CONFIGS}")

# --- Setup output directory ---
if [ -n "$RESUME_DIR" ]; then
    RUN_DIR="$RESUME_DIR"
    RUN_ID=$(basename "$RUN_DIR")
    echo "Resuming run: $RUN_ID"
else
    RUN_ID="$(date +%Y%m%d-%H%M%S)-${MODEL##*-}-p${APP_PORT}"
    RUN_DIR="$SCRIPT_DIR/results/$RUN_ID"
    mkdir -p "$RUN_DIR"
fi

# --- Logging ---
log() { echo "[$(date +%H:%M:%S)] $*"; }

# --- Verify app is installed ---
if ! xcrun simctl listapps "$SIM_UDID" 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "Error: $BUNDLE_ID not installed on $SIM_UDID" >&2
    exit 1
fi

# --- Preflight ---
preflight() {
    local ok=true

    local needs_bh=false
    for c in "${CONFIGS[@]}"; do [[ "$c" != "idb" && "$c" != "mobile-mcp" ]] && needs_bh=true; done
    if $needs_bh && [ ! -x "$REPO_ROOT/ButtonHeistMCP/.build/release/buttonheist-mcp" ]; then
        log "ERROR: ButtonHeistMCP not built. Run: cd ButtonHeistMCP && swift build -c release"
        ok=false
    fi

    if ! command -v claude >/dev/null 2>&1; then
        log "ERROR: claude CLI not found in PATH"
        ok=false
    fi

    if [[ " ${CONFIGS[*]} " == *" idb "* || " ${CONFIGS[*]} " == *" mobile-mcp "* ]] && ! command -v npx >/dev/null 2>&1; then
        log "ERROR: npx not found (needed for idb/mobile-mcp configs)"
        ok=false
    fi

    if [ "$ok" = false ]; then
        log "Preflight failed."
        exit 1
    fi
    log "Preflight passed"
}
preflight

# --- Wait for app TCP listener ---
wait_for_app() {
    local retries=0
    while [ $retries -lt 30 ]; do
        if nc -z 127.0.0.1 "$APP_PORT" 2>/dev/null; then
            sleep 0.5
            return 0
        fi
        sleep 0.5
        retries=$((retries + 1))
    done
    log "  WARNING: Port $APP_PORT not responding after 15s"
    return 1
}

# --- App reset ---
reset_app() {
    log "  Resetting app..."

    xcrun simctl terminate "$SIM_UDID" "$BUNDLE_ID" 2>/dev/null || true

    # Wait for old port to close
    local i=0
    while nc -z 127.0.0.1 "$APP_PORT" 2>/dev/null && [ $i -lt 10 ]; do
        sleep 0.5
        i=$((i + 1))
    done

    # Launch with port override
    SIMCTL_CHILD_INSIDEJOB_PORT="$APP_PORT" \
    SIMCTL_CHILD_INSIDEJOB_TOKEN="$APP_TOKEN" \
        xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" >/dev/null 2>&1

    if ! wait_for_app; then
        log "  ERROR: App failed to start on port $APP_PORT"
        return 1
    fi

    log "  App ready on 127.0.0.1:$APP_PORT"
}

# --- Coaching preambles ---
coaching_for_config() {
    case "$1" in
        bh) echo "" ;;
        bh-batch)
            cat <<'COACH'
IMPORTANT: You have a run_batch tool that lets you send multiple actions in a single call. Use it aggressively — combine sequential actions (like typing digits on a calculator, or tap-type-tap for adding items) into a single batch instead of individual calls. This dramatically reduces round trips.

COACH
            ;;
        bh-expect)
            cat <<'COACH'
IMPORTANT: You have a run_batch tool that lets you send multiple actions in a single call. Use it aggressively — combine sequential actions into a single batch. Each step in a batch can include an "expect" field to verify the outcome: "screen_changed" (did we navigate?), "layout_changed" (were elements added/removed?), or {"value": "expected_text"} (does a field contain the expected value?). Use expectations to verify outcomes inline instead of re-reading the interface after each action.

COACH
            ;;
        idb)
            cat <<COACH
IMPORTANT: Multiple simulators are booted. You MUST pass udid: "$SIM_UDID" in EVERY tool call. If you omit the udid parameter, the tool will target the wrong simulator.

When interacting with UI elements, you will receive frame data in the format {"x": X, "y": Y, "width": W, "height": H}. To tap an element, compute its center point: center_x = x + width/2, center_y = y + height/2. Use these center coordinates for tap actions.

COACH
            ;;
        mobile-mcp)
            cat <<COACH
IMPORTANT: Multiple simulators are booted. You MUST pass udid: "$SIM_UDID" in EVERY tool call. If you omit the udid parameter, the tool will target the wrong simulator.

Use mobile_list_elements_on_screen to inspect UI element hierarchy. Elements include coordinates — use those directly for tap/swipe actions. Use mobile_take_screenshot to visually verify state when the element list is ambiguous.

COACH
            ;;
    esac
}

# --- MCP configs ---
generate_mcp_configs() {
    # BH config — point at binary with discovered port
    jq -n --arg device "127.0.0.1:$APP_PORT" --arg token "$APP_TOKEN" \
        --arg bin "$REPO_ROOT/ButtonHeistMCP/.build/release/buttonheist-mcp" \
        '{mcpServers:{buttonheist:{command:$bin,env:{BUTTONHEIST_TOKEN:$token,BUTTONHEIST_DEVICE:$device}}}}' \
        > "$RUN_DIR/_mcp_bh.json"

    # idb config — inject UDID
    jq --arg udid "$SIM_UDID" \
       '.mcpServers["ios-simulator"].env = {"IDB_UDID": $udid}' \
       "$SCRIPT_DIR/configs/idb.json" > "$RUN_DIR/_mcp_idb.json"

    # mobile-mcp config — inject UDID
    jq --arg udid "$SIM_UDID" \
       '.mcpServers["mobile-mcp"].env = {"UDID": $udid}' \
       "$SCRIPT_DIR/configs/mobile-mcp.json" > "$RUN_DIR/_mcp_mobile-mcp.json"
}

mcp_config_for() {
    case "$1" in
        idb)        echo "$RUN_DIR/_mcp_idb.json" ;;
        mobile-mcp) echo "$RUN_DIR/_mcp_mobile-mcp.json" ;;
        *)          echo "$RUN_DIR/_mcp_bh.json" ;;
    esac
}

# --- Allowed tools ---
BH_BASE_TOOLS="mcp__buttonheist__get_interface,mcp__buttonheist__get_screen,mcp__buttonheist__activate,mcp__buttonheist__type_text,mcp__buttonheist__swipe,mcp__buttonheist__gesture,mcp__buttonheist__accessibility_action,mcp__buttonheist__scroll,mcp__buttonheist__scroll_to_visible,mcp__buttonheist__scroll_to_edge,mcp__buttonheist__wait_for_idle,mcp__buttonheist__get_session_state,mcp__buttonheist__list_devices,mcp__buttonheist__tap,mcp__buttonheist__increment,mcp__buttonheist__decrement,mcp__buttonheist__perform_custom_action"
BH_BATCH_TOOLS="${BH_BASE_TOOLS},mcp__buttonheist__run_batch"
IDB_TOOLS="mcp__ios-simulator__ui_describe_all,mcp__ios-simulator__ui_tap,mcp__ios-simulator__ui_type,mcp__ios-simulator__ui_swipe,mcp__ios-simulator__screenshot,mcp__ios-simulator__get_booted_sim_id,mcp__ios-simulator__launch_app,mcp__ios-simulator__ui_describe_point,mcp__ios-simulator__ui_view"
MOBILE_MCP_TOOLS="mcp__mobile-mcp__mobile_list_available_devices,mcp__mobile-mcp__mobile_list_apps,mcp__mobile-mcp__mobile_launch_app,mcp__mobile-mcp__mobile_terminate_app,mcp__mobile-mcp__mobile_get_screen_size,mcp__mobile-mcp__mobile_click_on_screen_at_coordinates,mcp__mobile-mcp__mobile_double_tap_on_screen,mcp__mobile-mcp__mobile_long_press_on_screen_at_coordinates,mcp__mobile-mcp__mobile_list_elements_on_screen,mcp__mobile-mcp__mobile_press_button,mcp__mobile-mcp__mobile_open_url,mcp__mobile-mcp__mobile_swipe_on_screen,mcp__mobile-mcp__mobile_type_keys,mcp__mobile-mcp__mobile_take_screenshot,mcp__mobile-mcp__mobile_set_orientation,mcp__mobile-mcp__mobile_get_orientation"

allowed_tools_for() {
    case "$1" in
        idb)                echo "$IDB_TOOLS" ;;
        mobile-mcp)         echo "$MOBILE_MCP_TOOLS" ;;
        bh)                 echo "$BH_BASE_TOOLS" ;;
        bh-batch|bh-expect) echo "$BH_BATCH_TOOLS" ;;
        *)                  echo "$BH_BASE_TOOLS" ;;
    esac
}

# --- Schedule ---
build_schedule() {
    for trial_num in $(seq 1 "$TRIAL_COUNT"); do
        local shuffled_configs=("${(@f)$(printf '%s\n' "${CONFIGS[@]}" | awk 'BEGIN{srand()}{print rand(), $0}' | sort -n | cut -d' ' -f2-)}")
        for config in "${shuffled_configs[@]}"; do
            local shuffled_tasks=("${(@f)$(printf '%s\n' "${TASKS[@]}" | awk 'BEGIN{srand()}{print rand(), $0}' | sort -n | cut -d' ' -f2-)}")
            for task in "${shuffled_tasks[@]}"; do
                echo "${task}|${config}|${trial_num}"
            done
        done
    done
}

trial_exists() {
    [ -f "$RUN_DIR/${1}_${2}_${3}.json" ]
}

# --- Run a single trial ---
run_trial() {
    local task="$1" config="$2" trial_num="$3"
    local result_file="$RUN_DIR/${task}_${config}_${trial_num}.json"
    local prompt_file="$SCRIPT_DIR/tasks/${task}.txt"

    if [ ! -f "$prompt_file" ]; then
        log "  ERROR: Task file not found: $prompt_file"
        return 1
    fi

    local coaching
    coaching=$(coaching_for_config "$config")
    local raw_prompt="$(cat "$prompt_file")"

    # Template substitution: generate random values per trial
    # Calculator: random 3-digit × 3-digit ÷ 2-digit
    local rand_a=$((RANDOM % 900 + 100))
    local rand_b=$((RANDOM % 900 + 100))
    local rand_c=$((RANDOM % 90 + 10))
    local calc_expected=$(python3 -c "print($rand_a * $rand_b / $rand_c)" 2>/dev/null || echo "")

    # Todo items: random verb+noun combos
    local verbs=(Buy Fix Call Send Find Wash Read Pack Move Cook Clean Build Check Write Paint)
    local nouns=(milk bike shoes lamp fence shirt cable books chair table socks shelf radio phone tools)
    local todo_a="${verbs[$((RANDOM % ${#verbs[@]} + 1))]} ${nouns[$((RANDOM % ${#nouns[@]} + 1))]}"
    local todo_b="${verbs[$((RANDOM % ${#verbs[@]} + 1))]} ${nouns[$((RANDOM % ${#nouns[@]} + 1))]}"
    local todo_c="${verbs[$((RANDOM % ${#verbs[@]} + 1))]} ${nouns[$((RANDOM % ${#nouns[@]} + 1))]}"

    raw_prompt="${raw_prompt//\{\{RAND3_A\}\}/$rand_a}"
    raw_prompt="${raw_prompt//\{\{RAND3_B\}\}/$rand_b}"
    raw_prompt="${raw_prompt//\{\{RAND2_C\}\}/$rand_c}"
    raw_prompt="${raw_prompt//\{\{TODO_A\}\}/$todo_a}"
    raw_prompt="${raw_prompt//\{\{TODO_B\}\}/$todo_b}"
    raw_prompt="${raw_prompt//\{\{TODO_C\}\}/$todo_c}"

    local full_prompt="${coaching}${raw_prompt}"

    # Save generated values for scoring (quote strings for safe sourcing)
    local vars_file="$RUN_DIR/${task}_${config}_${trial_num}.vars"
    cat > "$vars_file" <<VARS
rand_a=$rand_a
rand_b=$rand_b
rand_c=$rand_c
calc_expected='$calc_expected'
todo_a='$todo_a'
todo_b='$todo_b'
todo_c='$todo_c'
VARS
    local mcp_config
    mcp_config=$(mcp_config_for "$config")

    if [ "$DRY_RUN" = true ]; then
        log "  [DRY RUN] task=$task config=$config trial=$trial_num mcp=$mcp_config"
        return 0
    fi

    reset_app
    generate_mcp_configs

    local start_ts=$(date +%s)
    local allowed_tools=$(allowed_tools_for "$config")
    local exit_code=0

    local stream_file="$RUN_DIR/${task}_${config}_${trial_num}.jsonl"

    timeout "${WALL_TIMEOUT}" claude -p "$full_prompt" \
        --verbose \
        --output-format stream-json \
        --model "$MODEL" \
        --max-turns "$MAX_TURNS" \
        --no-session-persistence \
        --permission-mode bypassPermissions \
        --strict-mcp-config \
        --mcp-config "$mcp_config" \
        --allowedTools "$allowed_tools" \
        < /dev/null \
        > "$stream_file" 2>"$RUN_DIR/${task}_${config}_${trial_num}.stderr" \
        || exit_code=$?

    # Extract final result message from stream into summary JSON
    grep '^{"type":"result"' "$stream_file" | tail -1 > "$result_file" 2>/dev/null || true

    local end_ts=$(date +%s)
    local elapsed=$((end_ts - start_ts))

    # Enrich with metadata
    if [ -f "$result_file" ] && jq empty "$result_file" 2>/dev/null; then
        local tmp=$(mktemp)
        jq --arg task "$task" --arg config "$config" --argjson trial "$trial_num" \
           --arg model "$MODEL" --argjson wall_s "$elapsed" --argjson exit_code "$exit_code" \
           --arg sim "$SIM_UDID" --argjson port "$APP_PORT" \
           '. + {benchmark_meta:{task:$task,config:$config,trial:$trial,model:$model,wall_clock_s:$wall_s,exit_code:$exit_code,sim_udid:$sim,app_port:$port}}' \
           "$result_file" > "$tmp"
        mv "$tmp" "$result_file"
    else
        local error_reason="harness_error"
        [ "$exit_code" -eq 124 ] && error_reason="wall_timeout"
        jq -n --arg task "$task" --arg config "$config" --argjson trial "$trial_num" \
              --arg model "$MODEL" --argjson wall_s "$elapsed" --argjson exit_code "$exit_code" \
              --arg reason "$error_reason" --arg sim "$SIM_UDID" \
              '{is_error:true,subtype:$reason,num_turns:0,result:"",benchmark_meta:{task:$task,config:$config,trial:$trial,model:$model,wall_clock_s:$wall_s,exit_code:$exit_code,sim_udid:$sim}}' \
              > "$result_file"
    fi

    # Score
    local score_json
    score_json=$("$SCRIPT_DIR/verify/score.sh" "$task" "$result_file" 2>/dev/null || echo '{"score":-1,"reason":"scorer failed"}')
    local tmp=$(mktemp)
    jq --argjson score "$score_json" '. + {correctness:$score}' "$result_file" > "$tmp"
    mv "$tmp" "$result_file"

    local turns=$(jq -r '.num_turns // 0' "$result_file")
    local cost_usd=$(jq -r '.total_cost_usd // 0' "$result_file")
    local score=$(echo "$score_json" | jq -r '.score // "?"')
    log "  Done: ${turns} turns, ${elapsed}s, \$${cost_usd}, score=${score}"
}

# --- Summary ---
generate_summary() {
    log "Generating summary..."
    jq -s '
        [.[] | select(.benchmark_meta != null)]
        | group_by(.benchmark_meta.task + "|" + .benchmark_meta.config)
        | map({
            task: .[0].benchmark_meta.task,
            config: .[0].benchmark_meta.config,
            n: length,
            completed: [.[] | select(.is_error != true)] | length,
            correct: [.[] | select(.correctness.score == 1)] | length,
            partial: [.[] | select(.correctness.score == 0.5)] | length,
            turns: {
                values: [.[] | select(.is_error != true) | .num_turns],
                mean: ([.[] | select(.is_error != true) | .num_turns] | if length > 0 then add/length else null end),
                min: ([.[] | select(.is_error != true) | .num_turns] | if length > 0 then min else null end),
                max: ([.[] | select(.is_error != true) | .num_turns] | if length > 0 then max else null end)
            },
            wall_s: {
                values: [.[] | select(.is_error != true) | .benchmark_meta.wall_clock_s],
                mean: ([.[] | select(.is_error != true) | .benchmark_meta.wall_clock_s] | if length > 0 then add/length else null end)
            },
            context_tokens: {
                values: [.[] | select(.is_error != true) | ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))],
                mean: ([.[] | select(.is_error != true) | ((.usage.input_tokens // 0) + (.usage.cache_creation_input_tokens // 0) + (.usage.cache_read_input_tokens // 0))] | if length > 0 then add/length else null end)
            },
            output_tokens: {
                values: [.[] | select(.is_error != true) | .usage.output_tokens],
                mean: ([.[] | select(.is_error != true) | .usage.output_tokens] | if length > 0 then add/length else null end)
            },
            cost_usd: {
                values: [.[] | select(.is_error != true) | .total_cost_usd],
                total: ([.[] | select(.is_error != true) | .total_cost_usd] | if length > 0 then add else 0 end)
            }
        })
        | sort_by(.task + .config)
    ' "$RUN_DIR"/*.json > "$RUN_DIR/summary.json" 2>/dev/null || true
    log "Summary: $RUN_DIR/summary.json"
}

# --- Environment metadata ---
SIM_DEVICE_NAME=$(xcrun simctl list devices booted -j 2>/dev/null \
    | jq -r ".devices | to_entries[] | .value[] | select(.udid == \"$SIM_UDID\") | .name" | head -1)
SIM_RUNTIME=$(xcrun simctl list devices booted -j 2>/dev/null \
    | jq -r ".devices | to_entries[] | select(.value[] | .udid == \"$SIM_UDID\") | .key" \
    | head -1 | sed 's/com.apple.CoreSimulator.SimRuntime.//' | tr '-' '.')

generate_mcp_configs

GIT_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git -C "$REPO_ROOT" diff --quiet 2>/dev/null && echo "false" || echo "true")

jq -n --arg run_id "$RUN_ID" --arg model "$MODEL" --arg sim_udid "$SIM_UDID" \
    --arg sim_device "$SIM_DEVICE_NAME" --arg sim_runtime "$SIM_RUNTIME" \
    --arg bundle_id "$BUNDLE_ID" --argjson port "$APP_PORT" --arg token "$APP_TOKEN" \
    --argjson max_turns "$MAX_TURNS" --argjson trial_count "$TRIAL_COUNT" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg git_sha "$GIT_SHA" --argjson git_dirty "$GIT_DIRTY" \
    '{run_id:$run_id,model:$model,git:{sha:$git_sha,dirty:$git_dirty},simulator:{udid:$sim_udid,device:$sim_device,runtime:$sim_runtime},app:{bundle_id:$bundle_id,port:$port,token:$token},settings:{max_turns:$max_turns,trials_per_cell:$trial_count},started:$started}' \
    > "$RUN_DIR/manifest.json"

# --- Run plan ---
TOTAL_CELLS=$(( ${#TASKS[@]} * ${#CONFIGS[@]} ))
TOTAL_TRIALS=$(( TOTAL_CELLS * TRIAL_COUNT ))

log "=== Benchmark Run ==="
log "Run ID:     $RUN_ID"
log "Model:      $MODEL"
log "Simulator:  $SIM_DEVICE_NAME ($SIM_RUNTIME) [$SIM_UDID]"
log "App:        $BUNDLE_ID on 127.0.0.1:$APP_PORT"
log "Tasks:      ${TASKS[*]}"
log "Configs:    ${CONFIGS[*]}"
log "Trials:     $TRIAL_COUNT per cell × $TOTAL_CELLS cells = $TOTAL_TRIALS total"
log "Max turns:  $MAX_TURNS    Wall timeout: ${WALL_TIMEOUT}s"
log "Output:     $RUN_DIR"
log ""

if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN]"
    log ""
fi

# --- Execute ---
COMPLETED=0
SKIPPED=0
FAILED=0

while IFS='|' read -r task config trial_num; do
    if [ -n "$RESUME_DIR" ] && trial_exists "$task" "$config" "$trial_num"; then
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    COMPLETED=$((COMPLETED + 1))
    log "[$COMPLETED/$TOTAL_TRIALS] $task | $config | trial $trial_num"

    if ! run_trial "$task" "$config" "$trial_num"; then
        FAILED=$((FAILED + 1))
        log "  FAILED (continuing...)"
    fi
done < <(build_schedule)

if [ "$DRY_RUN" = false ]; then
    generate_summary
fi

log ""
log "=== Run Complete ==="
log "Completed: $COMPLETED  Skipped: $SKIPPED  Failed: $FAILED"
log "Results:   $RUN_DIR"

# --- Save baseline ---
if [ -n "$SAVE_BASELINE" ] && [ "$DRY_RUN" = false ]; then
    local baseline_dir="$SCRIPT_DIR/baselines"
    mkdir -p "$baseline_dir"
    local baseline_file="$baseline_dir/${SAVE_BASELINE}.json"

    # Build baseline: manifest + summary in one file
    jq -n --slurpfile manifest "$RUN_DIR/manifest.json" \
          --slurpfile summary "$RUN_DIR/summary.json" \
          --arg name "$SAVE_BASELINE" \
          '{name:$name, manifest:$manifest[0], cells:$summary[0]}' \
          > "$baseline_file"

    log "Baseline saved: $baseline_file"
    log "  Compare future runs with: ./benchmarks/report.sh <results-dir> --baseline $SAVE_BASELINE"
fi

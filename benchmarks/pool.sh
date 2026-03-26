#!/bin/zsh
# Parallel benchmark orchestrator with simulator pool management.
#
# Creates a pool of simulators, assigns one to each worker, dispatches
# trials via a shared work queue, and tears down cleanly on exit.
#
# Usage:
#   ./benchmarks/pool.sh --workers 4 [options]
#
# Options:
#   --workers N         Number of parallel workers/simulators (required)
#   --base-port PORT    Starting port number (default: 2000, each worker gets +1)
#   --device-type TYPE  Simulator device type (default: iPhone-16-Pro)
#   --runtime RT        Simulator runtime (default: iOS-26-1)
#   --keep-sims         Don't delete simulators on teardown (just shutdown)
#   --app PATH          Path to .app bundle (auto-detected from DerivedData if omitted)
#   --skip-install      Skip app installation (use if already installed)
#   -t TASKS            Tasks, comma-separated (default: all)
#   -c CONFIGS          Configs, comma-separated (default: bh,bh-batch,bh-expect)
#   -n COUNT            Trials per cell (default: 5)
#   -m MODEL            Claude model (default: claude-sonnet-4-6)
#   --max-turns N       Max turns per trial (default: 200)
#   --wall-timeout S    Max seconds per trial (default: 600)
#   --dry-run           Print plan without running
#   --resume DIR        Resume a previous pool run
#   --save-baseline N   Save results as named baseline
#   -h                  Show this help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# --- Defaults ---
WORKER_COUNT=""
BASE_PORT=2000
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-1"
KEEP_SIMS=false
APP_PATH=""
SKIP_INSTALL=false
ALL_TASKS=""
ALL_CONFIGS="bh,bh-batch,bh-expect"
TRIAL_COUNT=5
MODEL="claude-sonnet-4-6"
MAX_TURNS=200
WALL_TIMEOUT=600
DRY_RUN=false
RESUME_DIR=""
SAVE_BASELINE=""

# --- Constants ---
BUNDLE_ID="com.buttonheist.testapp"
APP_TOKEN="INJECTED-TOKEN-12345"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workers) WORKER_COUNT="$2"; shift 2 ;;
        --base-port) BASE_PORT="$2"; shift 2 ;;
        --device-type) DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.$2"; shift 2 ;;
        --runtime) RUNTIME="com.apple.CoreSimulator.SimRuntime.$2"; shift 2 ;;
        --keep-sims) KEEP_SIMS=true; shift ;;
        --app) APP_PATH="$2"; shift 2 ;;
        --skip-install) SKIP_INSTALL=true; shift ;;
        -t) ALL_TASKS="$2"; shift 2 ;;
        -c) ALL_CONFIGS="$2"; shift 2 ;;
        -n) TRIAL_COUNT="$2"; shift 2 ;;
        -m) MODEL="$2"; shift 2 ;;
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

if [ -z "$WORKER_COUNT" ]; then
    echo "Error: --workers N is required" >&2
    exit 1
fi

# --- Source shared code ---
source "$SCRIPT_DIR/lib.sh"
source "$SCRIPT_DIR/simpool.sh"

log() { echo "[pool $(date +%H:%M:%S)] $*"; }

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

# --- Preflight ---
preflight_check "${CONFIGS[@]}" || exit 1
log "Preflight passed"

# --- Setup output directory ---
if [ -n "$RESUME_DIR" ]; then
    RUN_DIR="$RESUME_DIR"
    RUN_ID=$(basename "$RUN_DIR")
    log "Resuming run: $RUN_ID"
else
    RUN_ID="pool-$(date +%Y%m%d-%H%M%S)-${MODEL##*-}-w${WORKER_COUNT}"
    RUN_DIR="$SCRIPT_DIR/results/$RUN_ID"
    mkdir -p "$RUN_DIR"
fi

# --- Initialize simulator pool ---
POOL_DIR="$RUN_DIR/_pool"
simpool_init "$POOL_DIR"

# --- Cleanup trap ---
WORKER_PIDS=()

cleanup() {
    log "Cleaning up..."

    # Stop WDA if running
    simpool_stop_wda 2>/dev/null || true

    # Signal all workers to stop
    for pid in "${WORKER_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done

    # Wait for workers to finish current trial (up to 30s)
    local waited=0
    for pid in "${WORKER_PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            if [ $waited -lt 30 ]; then
                wait "$pid" 2>/dev/null || true
                waited=$((waited + 1))
            else
                kill -KILL "$pid" 2>/dev/null || true
            fi
        fi
    done

    # Teardown sims
    if $KEEP_SIMS; then
        simpool_teardown
    else
        simpool_teardown --delete
    fi

    # Generate summary if we have results
    if [ "$DRY_RUN" = false ] && ls "$RUN_DIR"/*.json >/dev/null 2>&1; then
        generate_summary "$RUN_DIR"
        log "Summary: $RUN_DIR/summary.json"
    fi

    log "Cleanup complete"
}
trap cleanup EXIT

# --- Build work queue ---
QUEUE_FILE="$RUN_DIR/_queue.txt"
QUEUE_LOCK="$RUN_DIR/_queue.lock.d"

build_queue() {
    local queue_entries=()
    for trial_num in $(seq 1 "$TRIAL_COUNT"); do
        local shuffled_configs=("${(@f)$(printf '%s\n' "${CONFIGS[@]}" | awk 'BEGIN{srand()}{print rand(), $0}' | sort -n | cut -d' ' -f2-)}")
        for config in "${shuffled_configs[@]}"; do
            local shuffled_tasks=("${(@f)$(printf '%s\n' "${TASKS[@]}" | awk 'BEGIN{srand()}{print rand(), $0}' | sort -n | cut -d' ' -f2-)}")
            for task in "${shuffled_tasks[@]}"; do
                if [ -n "$RESUME_DIR" ] && [ -f "$RUN_DIR/${task}_${config}_${trial_num}.json" ]; then
                    queue_entries+=("done:resume|${task}|${config}|${trial_num}")
                else
                    queue_entries+=("pending|${task}|${config}|${trial_num}")
                fi
            done
        done
    done
    printf '%s\n' "${queue_entries[@]}" > "$QUEUE_FILE"
}

count_pending() {
    grep -c '^pending|' "$QUEUE_FILE" 2>/dev/null || echo 0
}

count_done() {
    grep -c '^done:' "$QUEUE_FILE" 2>/dev/null || echo 0
}

# --- Main ---

TOTAL_CELLS=$(( ${#TASKS[@]} * ${#CONFIGS[@]} ))
TOTAL_TRIALS=$(( TOTAL_CELLS * TRIAL_COUNT ))

log "=== Parallel Benchmark Run ==="
log "Run ID:     $RUN_ID"
log "Model:      $MODEL"
log "Workers:    $WORKER_COUNT"
log "Base port:  $BASE_PORT"
log "Tasks:      ${TASKS[*]}"
log "Configs:    ${CONFIGS[*]}"
log "Trials:     $TRIAL_COUNT per cell x $TOTAL_CELLS cells = $TOTAL_TRIALS total"
log "Max turns:  $MAX_TURNS    Wall timeout: ${WALL_TIMEOUT}s"
log "Output:     $RUN_DIR"
log ""

# Build the queue
build_queue
PENDING=$(count_pending)
RESUMED=$((TOTAL_TRIALS - PENDING))
if [ $RESUMED -gt 0 ]; then
    log "Resumed: $RESUMED already complete, $PENDING remaining"
fi

if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Queue:"
    head -20 "$QUEUE_FILE"
    [ $TOTAL_TRIALS -gt 20 ] && log "  ... and $((TOTAL_TRIALS - 20)) more"
    log ""
    log "Would create $WORKER_COUNT simulators on ports $BASE_PORT-$((BASE_PORT + WORKER_COUNT - 1))"
    exit 0
fi

# --- Provision simulators ---
log "--- Simulator Pool ---"

simpool_create "$WORKER_COUNT" "$BASE_PORT" "$DEVICE_TYPE" "$RUNTIME" || {
    log "ERROR: Failed to create simulator pool"
    exit 1
}

simpool_boot || {
    log "ERROR: Failed to boot simulator pool"
    exit 1
}

if ! $SKIP_INSTALL; then
    if [ -z "$APP_PATH" ]; then
        APP_PATH=$(simpool_find_app)
        if [ -z "$APP_PATH" ]; then
            log "ERROR: No AccessibilityTestApp.app found in DerivedData."
            log "Build it first: xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp -destination 'generic/platform=iOS Simulator' build"
            exit 1
        fi
        log "Using app: $APP_PATH"
    fi
    simpool_install_app "$APP_PATH" || {
        log "ERROR: Failed to install app"
        exit 1
    }
fi

# --- Start WDA if mobile-mcp is in the config set ---
if [[ " ${CONFIGS[*]} " == *" mobile-mcp "* ]]; then
    WDA_PROJECT="$REPO_ROOT/WebDriverAgent"
    WDA_BASE_PORT=8100
    if [ ! -d "$WDA_PROJECT/WebDriverAgent.xcodeproj" ]; then
        log "ERROR: WebDriverAgent not found at $WDA_PROJECT"
        log "Clone it: git clone --depth 1 https://github.com/appium/WebDriverAgent.git"
        exit 1
    fi
    simpool_build_wda "$WDA_PROJECT" || exit 1
    simpool_start_wda "$WDA_PROJECT" "$WDA_BASE_PORT" || exit 1
fi

log ""
log "Pool status:"
simpool_status
log ""

# --- Write manifest ---
GIT_SHA=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown")
GIT_DIRTY=$(git -C "$REPO_ROOT" diff --quiet 2>/dev/null && echo "false" || echo "true")

jq -n --arg run_id "$RUN_ID" --arg model "$MODEL" \
    --argjson workers "$WORKER_COUNT" --argjson base_port "$BASE_PORT" \
    --arg bundle_id "$BUNDLE_ID" --arg token "$APP_TOKEN" \
    --argjson max_turns "$MAX_TURNS" --argjson trial_count "$TRIAL_COUNT" \
    --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg git_sha "$GIT_SHA" --argjson git_dirty "$GIT_DIRTY" \
    --arg device_type "$DEVICE_TYPE" --arg runtime "$RUNTIME" \
    '{run_id:$run_id,model:$model,git:{sha:$git_sha,dirty:$git_dirty},
      pool:{workers:$workers,base_port:$base_port,device_type:$device_type,runtime:$runtime},
      app:{bundle_id:$bundle_id,token:$token},
      settings:{max_turns:$max_turns,trials_per_cell:$trial_count},
      started:$started}' \
    > "$RUN_DIR/manifest.json"

# --- Launch workers ---
log "--- Launching $WORKER_COUNT workers ---"

for i in $(seq 0 $((WORKER_COUNT - 1))); do
    worker_id="w${i}"

    # Claim a sim from the pool
    claim=$(simpool_claim "$worker_id")
    sim_udid="${claim%% *}"
    app_port="${claim##* }"

    log "Worker $worker_id -> sim $sim_udid port $app_port"

    # Launch worker as background process
    WORKER_ID="$worker_id" \
    SIM_UDID="$sim_udid" \
    APP_PORT="$app_port" \
    RUN_DIR="$RUN_DIR" \
    QUEUE_FILE="$QUEUE_FILE" \
    QUEUE_LOCK="$QUEUE_LOCK" \
    MODEL="$MODEL" \
    MAX_TURNS="$MAX_TURNS" \
    WALL_TIMEOUT="$WALL_TIMEOUT" \
    SCRIPT_DIR="$SCRIPT_DIR" \
    REPO_ROOT="$REPO_ROOT" \
    BUNDLE_ID="$BUNDLE_ID" \
    APP_TOKEN="$APP_TOKEN" \
        zsh "$SCRIPT_DIR/worker.sh" \
        >> "$RUN_DIR/worker_${worker_id}.log" 2>&1 &

    WORKER_PIDS+=($!)
done

log ""
log "All workers launched. Monitoring progress..."
log "  Logs: $RUN_DIR/worker_w*.log"
log "  Queue: $QUEUE_FILE"
log ""

# --- Monitor progress ---
while true; do
    alive=0
    for pid in "${WORKER_PIDS[@]}"; do
        kill -0 "$pid" 2>/dev/null && alive=$((alive + 1))
    done

    done_count=$(count_done)
    pending_count=$(count_pending)
    claimed=$(grep -c '^claimed:' "$QUEUE_FILE" 2>/dev/null || echo 0)

    log "Progress: ${done_count}/${TOTAL_TRIALS} done, ${claimed} in-flight, ${pending_count} pending, ${alive} workers alive"

    if [ "$alive" -eq 0 ]; then
        break
    fi
    if [ "$pending_count" -eq 0 ] && [ "$claimed" -eq 0 ]; then
        for pid in "${WORKER_PIDS[@]}"; do
            wait "$pid" 2>/dev/null || true
        done
        break
    fi

    sleep 10
done

# --- Final summary ---
generate_summary "$RUN_DIR"

log ""
log "=== Run Complete ==="
log "Results: $RUN_DIR"
log "Summary: $RUN_DIR/summary.json"

done_count=$(count_done)
log "Completed: $done_count / $TOTAL_TRIALS"

# Generate report
"$SCRIPT_DIR/report.sh" "$RUN_DIR" > "$RUN_DIR/report.md" 2>/dev/null && \
    log "Report:  $RUN_DIR/report.md"

# --- Save baseline ---
if [ -n "$SAVE_BASELINE" ]; then
    baseline_dir="$SCRIPT_DIR/baselines"
    mkdir -p "$baseline_dir"
    baseline_file="$baseline_dir/${SAVE_BASELINE}.json"

    jq -n --slurpfile manifest "$RUN_DIR/manifest.json" \
          --slurpfile summary "$RUN_DIR/summary.json" \
          --arg name "$SAVE_BASELINE" \
          '{name:$name, manifest:$manifest[0], cells:$summary[0]}' \
          > "$baseline_file"

    log "Baseline saved: $baseline_file"
fi

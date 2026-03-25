#!/bin/zsh
# Benchmark worker — claims trials from a shared queue and runs them
# against an assigned simulator.
#
# Launched by pool.sh. Not intended to be run directly.
#
# Expected environment:
#   WORKER_ID       — unique worker identifier (e.g., "w0")
#   SIM_UDID        — assigned simulator UDID
#   APP_PORT        — assigned port
#   RUN_DIR         — shared results directory
#   QUEUE_FILE      — path to the shared trial queue
#   QUEUE_LOCK      — path to the queue lock dir (mkdir-based)
#   MODEL           — claude model
#   MAX_TURNS       — max turns per trial
#   WALL_TIMEOUT    — max seconds per trial
#   SCRIPT_DIR      — path to benchmarks/
#   REPO_ROOT       — repo root
#   BUNDLE_ID       — app bundle id
#   APP_TOKEN       — app auth token

set -uo pipefail

source "$SCRIPT_DIR/lib.sh"

log() { echo "[${WORKER_ID} $(date +%H:%M:%S)] $*"; }

# --- Atomic lock via mkdir ---
_lock_acquire() {
    while ! mkdir "$1" 2>/dev/null; do
        sleep 0.05
    done
}
_lock_release() {
    rmdir "$1" 2>/dev/null || true
}

# --- Graceful shutdown ---
SHUTTING_DOWN=false
trap 'SHUTTING_DOWN=true; log "Received shutdown signal, finishing current trial..."' TERM INT

# --- Claim next trial from queue ---
# Queue format: STATUS|task|config|trial_num
#   STATUS: "pending" or "claimed:<worker_id>" or "done:<worker_id>"
claim_next_trial() {
    _lock_acquire "$QUEUE_LOCK"

    local line_num=0
    local found=""
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if [[ "$line" == pending\|* ]]; then
            local trial_spec="${line#pending|}"
            sed -i '' "${line_num}s/^pending|/claimed:${WORKER_ID}|/" "$QUEUE_FILE"
            found="$trial_spec"
            break
        fi
    done < "$QUEUE_FILE"

    _lock_release "$QUEUE_LOCK"

    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi
    return 1
}

# --- Mark trial as done in queue ---
mark_done() {
    local task="$1" config="$2" trial_num="$3"

    _lock_acquire "$QUEUE_LOCK"
    sed -i '' "s/^claimed:${WORKER_ID}|${task}|${config}|${trial_num}$/done:${WORKER_ID}|${task}|${config}|${trial_num}/" "$QUEUE_FILE"
    _lock_release "$QUEUE_LOCK"
}

# --- Main loop ---
log "Started (sim=$SIM_UDID port=$APP_PORT)"

# Generate MCP configs once for this worker's sim/port
generate_mcp_configs "$RUN_DIR" "$APP_PORT" "$SIM_UDID"

WORKER_TRIAL_COUNT=0
while ! $SHUTTING_DOWN; do
    # Claim next trial
    trial_spec=$(claim_next_trial) || break

    IFS='|' read -r task config trial_num <<< "$trial_spec"
    WORKER_TRIAL_COUNT=$((WORKER_TRIAL_COUNT + 1))

    log "[$WORKER_TRIAL_COUNT] $task | $config | trial $trial_num"

    # Run the trial
    result_line=$(run_trial "$task" "$config" "$trial_num" \
        "$SIM_UDID" "$APP_PORT" "$RUN_DIR" \
        "$MODEL" "$MAX_TURNS" "$WALL_TIMEOUT" 2>&1) || true

    log "  $result_line"

    mark_done "$task" "$config" "$trial_num"
done

log "Finished ($WORKER_TRIAL_COUNT trials completed)"

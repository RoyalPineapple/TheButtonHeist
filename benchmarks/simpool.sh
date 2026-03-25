#!/bin/zsh
# Simulator pool lifecycle management.
# Sourced by pool.sh. Manages creation, booting, app installation,
# assignment, and teardown of a pool of iOS simulators.
#
# Expected variables (set by caller before sourcing):
#   BUNDLE_ID    — app bundle id
#   APP_TOKEN    — auth token for the app
#   REPO_ROOT    — path to repo root
#
# All pool sims are named "bench-pool-<N>" and tracked via a state dir.
# This script NEVER touches sims it didn't create.

SIMPOOL_PREFIX="bench-pool"

# --- Internal helpers ---

_simpool_log() { echo "[simpool $(date +%H:%M:%S)] $*"; }

# Atomic lock via mkdir (works on all POSIX shells, no flock needed)
_lock_acquire() {
    local lock_dir="$1"
    while ! mkdir "$lock_dir" 2>/dev/null; do
        sleep 0.05
    done
}
_lock_release() {
    rmdir "$1" 2>/dev/null || true
}

# --- Pool state directory ---
# Each pool run gets a state dir: $POOL_STATE_DIR/
#   sims.json   — array of {index, udid, port, name, state}
#   claims/     — one file per claimed sim: <udid> contains worker PID

simpool_init() {
    local state_dir="$1"
    mkdir -p "$state_dir/claims"
    echo '[]' > "$state_dir/sims.json"
    POOL_STATE_DIR="$state_dir"
}

# --- Create N simulators ---
# Args: count base_port device_type runtime
simpool_create() {
    local count="$1"
    local base_port="$2"
    local device_type="${3:-com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro}"
    local runtime="${4:-com.apple.CoreSimulator.SimRuntime.iOS-26-1}"

    _simpool_log "Creating $count simulators (${device_type##*.}, ${runtime##*.})"

    local sims=()
    for i in $(seq 0 $((count - 1))); do
        local name="${SIMPOOL_PREFIX}-${i}"
        local port=$((base_port + i))

        # Check if a sim with this name already exists (from a crashed previous run)
        local existing_udid
        existing_udid=$(xcrun simctl list devices -j 2>/dev/null \
            | jq -r --arg name "$name" \
              '[.devices[][] | select(.name == $name and .isAvailable == true)] | .[0].udid // empty' 2>/dev/null)

        if [ -n "$existing_udid" ]; then
            _simpool_log "  Reusing existing sim: $name ($existing_udid) -> port $port"
            sims+=("{\"index\":$i,\"udid\":\"$existing_udid\",\"port\":$port,\"name\":\"$name\",\"state\":\"created\"}")
        else
            local udid
            udid=$(xcrun simctl create "$name" "$device_type" "$runtime" 2>&1)
            if [ $? -ne 0 ]; then
                _simpool_log "  ERROR creating $name: $udid"
                return 1
            fi
            _simpool_log "  Created: $name ($udid) -> port $port"
            sims+=("{\"index\":$i,\"udid\":\"$udid\",\"port\":$port,\"name\":\"$name\",\"state\":\"created\"}")
        fi
    done

    # Write state
    printf '%s\n' "${sims[@]}" | jq -s '.' > "$POOL_STATE_DIR/sims.json"
}

# --- Boot all pool sims ---
simpool_boot() {
    _simpool_log "Booting pool simulators..."

    local pids=()
    local udids=()
    udids=($(jq -r '.[].udid' "$POOL_STATE_DIR/sims.json"))

    for udid in "${udids[@]}"; do
        local state
        state=$(xcrun simctl list devices -j 2>/dev/null \
            | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .state' 2>/dev/null)

        if [ "$state" = "Booted" ]; then
            _simpool_log "  $udid already booted"
        else
            xcrun simctl boot "$udid" 2>/dev/null &
            pids+=($!)
        fi
    done

    # Wait for all boot commands
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Verify all booted
    local retries=0
    while [ $retries -lt 30 ]; do
        local all_booted=true
        for udid in "${udids[@]}"; do
            local state
            state=$(xcrun simctl list devices -j 2>/dev/null \
                | jq -r --arg u "$udid" '.devices[][] | select(.udid == $u) | .state' 2>/dev/null)
            if [ "$state" != "Booted" ]; then
                all_booted=false
                break
            fi
        done
        $all_booted && break
        sleep 1
        retries=$((retries + 1))
    done

    # Update state
    local tmp=$(mktemp)
    jq 'map(.state = "booted")' "$POOL_STATE_DIR/sims.json" > "$tmp"
    mv "$tmp" "$POOL_STATE_DIR/sims.json"

    _simpool_log "All simulators booted"
}

# --- Install app on all pool sims ---
# Args: app_path (the .app bundle to install)
simpool_install_app() {
    local app_path="$1"

    if [ ! -d "$app_path" ]; then
        _simpool_log "ERROR: App not found at $app_path"
        return 1
    fi

    _simpool_log "Installing app on all pool sims..."

    local udids=()
    udids=($(jq -r '.[].udid' "$POOL_STATE_DIR/sims.json"))

    for udid in "${udids[@]}"; do
        xcrun simctl install "$udid" "$app_path" 2>&1 || {
            _simpool_log "  WARNING: Install failed on $udid"
        }
    done

    # Update state
    local tmp=$(mktemp)
    jq 'map(.state = "ready")' "$POOL_STATE_DIR/sims.json" > "$tmp"
    mv "$tmp" "$POOL_STATE_DIR/sims.json"

    _simpool_log "App installed on all sims"
}

# --- Claim a sim for a worker ---
# Args: worker_id
# Prints: "udid port" of the claimed sim
simpool_claim() {
    local worker_id="$1"
    local lock_dir="$POOL_STATE_DIR/claims.lock.d"

    _lock_acquire "$lock_dir"

    local count
    count=$(jq 'length' "$POOL_STATE_DIR/sims.json")
    local found=false

    for i in $(seq 0 $((count - 1))); do
        local udid
        udid=$(jq -r ".[$i].udid" "$POOL_STATE_DIR/sims.json")
        local claim_file="$POOL_STATE_DIR/claims/$udid"

        if [ ! -f "$claim_file" ]; then
            echo "$worker_id" > "$claim_file"
            local port
            port=$(jq -r ".[$i].port" "$POOL_STATE_DIR/sims.json")
            _lock_release "$lock_dir"
            echo "$udid $port"
            return 0
        fi
    done

    _lock_release "$lock_dir"
    echo "ERROR: No available sims in pool" >&2
    return 1
}

# --- Release a sim back to the pool ---
# Args: udid
simpool_release() {
    local udid="$1"
    local lock_dir="$POOL_STATE_DIR/claims.lock.d"

    _lock_acquire "$lock_dir"
    rm -f "$POOL_STATE_DIR/claims/$udid"
    _lock_release "$lock_dir"
}

# --- Get sim info ---
# Args: udid
simpool_info() {
    local udid="$1"
    jq --arg u "$udid" '.[] | select(.udid == $u)' "$POOL_STATE_DIR/sims.json"
}

# --- List all pool sims with status ---
simpool_status() {
    jq -r '.[] | "\(.name)\t\(.udid)\t\(.port)\t\(.state)"' "$POOL_STATE_DIR/sims.json" | while IFS=$'\t' read -r name udid port state; do
        local claimed_by=""
        if [ -f "$POOL_STATE_DIR/claims/$udid" ]; then
            claimed_by=" [worker $(cat "$POOL_STATE_DIR/claims/$udid")]"
        fi
        local booted=""
        if xcrun simctl list devices booted -j 2>/dev/null | jq -e --arg u "$udid" '.devices[][] | select(.udid == $u)' >/dev/null 2>&1; then
            booted="booted"
        else
            booted="shutdown"
        fi
        echo "  $name ($udid) port=$port $booted$claimed_by"
    done
}

# --- Teardown: shutdown and optionally delete pool sims ---
# Args: [--delete]
simpool_teardown() {
    local delete=false
    [[ "${1:-}" == "--delete" ]] && delete=true

    _simpool_log "Tearing down pool..."

    jq -r '.[] | "\(.udid)\t\(.name)"' "$POOL_STATE_DIR/sims.json" 2>/dev/null | while IFS=$'\t' read -r udid name; do
        xcrun simctl terminate "$udid" "$BUNDLE_ID" 2>/dev/null || true
        xcrun simctl shutdown "$udid" 2>/dev/null || true
        _simpool_log "  Shutdown: $name ($udid)"

        if $delete; then
            xcrun simctl delete "$udid" 2>/dev/null || true
            _simpool_log "  Deleted: $name ($udid)"
        fi
    done

    setopt local_options null_glob
    rm -f "$POOL_STATE_DIR"/claims/*

    _simpool_log "Pool teardown complete"
}

# --- Find the freshest AccessibilityTestApp build ---
simpool_find_app() {
    ls -td ~/Library/Developer/Xcode/DerivedData/ButtonHeist*/Build/Products/Debug-iphonesimulator/AccessibilityTestApp.app 2>/dev/null | head -1
}

#!/bin/zsh
# Shared functions for the benchmark harness.
# Sourced by run.sh (optional), worker.sh, and pool.sh.
#
# Expected variables (set by caller before sourcing):
#   SCRIPT_DIR   — path to benchmarks/
#   REPO_ROOT    — path to repo root
#   BUNDLE_ID    — app bundle id
#   APP_TOKEN    — auth token for the app

# --- Coaching preambles ---
coaching_for_config() {
    local sim_udid="${2:-}"
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
IMPORTANT: Multiple simulators are booted. You MUST pass udid: "$sim_udid" in EVERY tool call. If you omit the udid parameter, the tool will target the wrong simulator.

When interacting with UI elements, you will receive frame data in the format {"x": X, "y": Y, "width": W, "height": H}. To tap an element, compute its center point: center_x = x + width/2, center_y = y + height/2. Use these center coordinates for tap actions.

COACH
            ;;
    esac
}

# --- MCP config generation ---
generate_mcp_configs() {
    local run_dir="$1" app_port="$2" sim_udid="$3"

    jq -n --arg device "127.0.0.1:$app_port" --arg token "$APP_TOKEN" \
        --arg bin "$REPO_ROOT/ButtonHeistMCP/.build/release/buttonheist-mcp" \
        '{mcpServers:{buttonheist:{command:$bin,env:{BUTTONHEIST_TOKEN:$token,BUTTONHEIST_DEVICE:$device}}}}' \
        > "$run_dir/_mcp_bh_${app_port}.json"

    jq --arg udid "$sim_udid" \
       '.mcpServers["ios-simulator"].env = {"IDB_UDID": $udid}' \
       "$SCRIPT_DIR/configs/idb.json" > "$run_dir/_mcp_idb_${sim_udid}.json"
}

mcp_config_for() {
    local config="$1" run_dir="$2" app_port="$3" sim_udid="$4"
    case "$config" in
        idb) echo "$run_dir/_mcp_idb_${sim_udid}.json" ;;
        *)   echo "$run_dir/_mcp_bh_${app_port}.json" ;;
    esac
}

# --- Allowed tools ---
BH_BASE_TOOLS="mcp__buttonheist__get_interface,mcp__buttonheist__get_screen,mcp__buttonheist__activate,mcp__buttonheist__type_text,mcp__buttonheist__swipe,mcp__buttonheist__gesture,mcp__buttonheist__accessibility_action,mcp__buttonheist__scroll,mcp__buttonheist__scroll_to_visible,mcp__buttonheist__scroll_to_edge,mcp__buttonheist__wait_for_idle,mcp__buttonheist__get_session_state,mcp__buttonheist__list_devices,mcp__buttonheist__tap,mcp__buttonheist__increment,mcp__buttonheist__decrement,mcp__buttonheist__perform_custom_action"
BH_BATCH_TOOLS="${BH_BASE_TOOLS},mcp__buttonheist__run_batch"
IDB_TOOLS="mcp__ios-simulator__ui_describe_all,mcp__ios-simulator__ui_tap,mcp__ios-simulator__ui_type,mcp__ios-simulator__ui_swipe,mcp__ios-simulator__screenshot,mcp__ios-simulator__get_booted_sim_id,mcp__ios-simulator__launch_app,mcp__ios-simulator__ui_describe_point,mcp__ios-simulator__ui_view"

allowed_tools_for() {
    case "$1" in
        idb)                echo "$IDB_TOOLS" ;;
        bh)                 echo "$BH_BASE_TOOLS" ;;
        bh-batch|bh-expect) echo "$BH_BATCH_TOOLS" ;;
        *)                  echo "$BH_BASE_TOOLS" ;;
    esac
}

# --- Wait for app TCP listener ---
wait_for_app() {
    local port="$1"
    local retries=0
    while [ $retries -lt 30 ]; do
        if nc -z 127.0.0.1 "$port" 2>/dev/null; then
            sleep 0.5
            return 0
        fi
        sleep 0.5
        retries=$((retries + 1))
    done
    return 1
}

# --- App reset ---
reset_app() {
    local sim_udid="$1" app_port="$2"

    xcrun simctl terminate "$sim_udid" "$BUNDLE_ID" 2>/dev/null || true

    local i=0
    while nc -z 127.0.0.1 "$app_port" 2>/dev/null && [ $i -lt 10 ]; do
        sleep 0.5
        i=$((i + 1))
    done

    SIMCTL_CHILD_INSIDEJOB_PORT="$app_port" \
        xcrun simctl launch "$sim_udid" "$BUNDLE_ID" >/dev/null 2>&1

    if ! wait_for_app "$app_port"; then
        return 1
    fi
}

# --- Template substitution ---
substitute_template() {
    local raw_prompt="$1"

    local rand_a=$((RANDOM % 900 + 100))
    local rand_b=$((RANDOM % 900 + 100))
    local rand_c=$((RANDOM % 90 + 10))
    local calc_expected=$(python3 -c "print($rand_a * $rand_b / $rand_c)" 2>/dev/null || echo "")

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

    # Export vars for scoring
    TRIAL_VARS_rand_a=$rand_a
    TRIAL_VARS_rand_b=$rand_b
    TRIAL_VARS_rand_c=$rand_c
    TRIAL_VARS_calc_expected=$calc_expected
    TRIAL_VARS_todo_a=$todo_a
    TRIAL_VARS_todo_b=$todo_b
    TRIAL_VARS_todo_c=$todo_c

    echo "$raw_prompt"
}

write_vars_file() {
    local vars_file="$1"
    cat > "$vars_file" <<VARS
rand_a=$TRIAL_VARS_rand_a
rand_b=$TRIAL_VARS_rand_b
rand_c=$TRIAL_VARS_rand_c
calc_expected='$TRIAL_VARS_calc_expected'
todo_a='$TRIAL_VARS_todo_a'
todo_b='$TRIAL_VARS_todo_b'
todo_c='$TRIAL_VARS_todo_c'
VARS
}

# --- Run a single trial ---
# Args: task config trial_num sim_udid app_port run_dir model max_turns wall_timeout
run_trial() {
    local task="$1" config="$2" trial_num="$3"
    local sim_udid="$4" app_port="$5" run_dir="$6"
    local model="$7" max_turns="$8" wall_timeout="$9"

    local result_file="$run_dir/${task}_${config}_${trial_num}.json"
    local prompt_file="$SCRIPT_DIR/tasks/${task}.txt"

    if [ ! -f "$prompt_file" ]; then
        echo "ERROR: Task file not found: $prompt_file" >&2
        return 1
    fi

    local coaching
    coaching=$(coaching_for_config "$config" "$sim_udid")
    local raw_prompt="$(cat "$prompt_file")"
    local full_prompt
    full_prompt=$(substitute_template "$raw_prompt")
    full_prompt="${coaching}${full_prompt}"

    write_vars_file "$run_dir/${task}_${config}_${trial_num}.vars"

    local mcp_config
    mcp_config=$(mcp_config_for "$config" "$run_dir" "$app_port" "$sim_udid")

    reset_app "$sim_udid" "$app_port"
    generate_mcp_configs "$run_dir" "$app_port" "$sim_udid"

    local start_ts=$(date +%s)
    local allowed_tools=$(allowed_tools_for "$config")
    local exit_code=0

    timeout "${wall_timeout}" claude -p "$full_prompt" \
        --output-format json \
        --model "$model" \
        --max-turns "$max_turns" \
        --no-session-persistence \
        --permission-mode bypassPermissions \
        --strict-mcp-config \
        --mcp-config "$mcp_config" \
        --allowedTools "$allowed_tools" \
        < /dev/null \
        > "$result_file" 2>"$run_dir/${task}_${config}_${trial_num}.stderr" \
        || exit_code=$?

    local end_ts=$(date +%s)
    local elapsed=$((end_ts - start_ts))

    # Enrich with metadata
    if [ -f "$result_file" ] && jq empty "$result_file" 2>/dev/null; then
        local tmp=$(mktemp)
        jq --arg task "$task" --arg config "$config" --argjson trial "$trial_num" \
           --arg model "$model" --argjson wall_s "$elapsed" --argjson exit_code "$exit_code" \
           --arg sim "$sim_udid" --argjson port "$app_port" \
           '. + {benchmark_meta:{task:$task,config:$config,trial:$trial,model:$model,wall_clock_s:$wall_s,exit_code:$exit_code,sim_udid:$sim,app_port:$port}}' \
           "$result_file" > "$tmp"
        mv "$tmp" "$result_file"
    else
        local error_reason="harness_error"
        [ "$exit_code" -eq 124 ] && error_reason="wall_timeout"
        jq -n --arg task "$task" --arg config "$config" --argjson trial "$trial_num" \
              --arg model "$model" --argjson wall_s "$elapsed" --argjson exit_code "$exit_code" \
              --arg reason "$error_reason" --arg sim "$sim_udid" \
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
    echo "${turns}t ${elapsed}s \$${cost_usd} score=${score}"
}

# --- Summary generation ---
generate_summary() {
    local run_dir="$1"
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
    ' "$run_dir"/*.json > "$run_dir/summary.json" 2>/dev/null || true
}

# --- Preflight checks ---
preflight_check() {
    local configs=("$@")
    local ok=true

    local needs_bh=false
    for c in "${configs[@]}"; do [[ "$c" != "idb" ]] && needs_bh=true; done
    if $needs_bh && [ ! -x "$REPO_ROOT/ButtonHeistMCP/.build/release/buttonheist-mcp" ]; then
        echo "ERROR: ButtonHeistMCP not built. Run: cd ButtonHeistMCP && swift build -c release" >&2
        ok=false
    fi

    if ! command -v claude >/dev/null 2>&1; then
        echo "ERROR: claude CLI not found in PATH" >&2
        ok=false
    fi

    if [[ " ${configs[*]} " == *" idb "* ]] && ! command -v npx >/dev/null 2>&1; then
        echo "ERROR: npx not found (needed for idb config)" >&2
        ok=false
    fi

    [ "$ok" = true ]
}

#!/bin/zsh
# Quick status of all active benchmark runs.
# Usage: ./benchmarks/status.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

for run_dir in "$SCRIPT_DIR"/results/2026*/; do
    [ -d "$run_dir" ] || continue
    run_id=$(basename "$run_dir")

    # Count trials
    total=$(ls "$run_dir"/*.json 2>/dev/null | grep -v "_mcp_\|manifest\|summary" | wc -l | tr -d ' ')
    completed=$(for f in "$run_dir"/*.json; do
        [[ "$f" == *_mcp_* || "$f" == *manifest* || "$f" == *summary* ]] && continue
        [ -s "$f" ] && echo 1
    done | wc -l | tr -d ' ')
    in_progress=$(for f in "$run_dir"/*.json; do
        [[ "$f" == *_mcp_* || "$f" == *manifest* || "$f" == *summary* ]] && continue
        [ ! -s "$f" ] && echo 1
    done | wc -l | tr -d ' ')

    # Check if harness is alive — look for claude -p writing into this run dir
    harness_alive="dead"
    local active_agents=$(pgrep -af "claude.*-p.*$run_id" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$active_agents" -gt 0 ]; then
        harness_alive="running ($active_agents agents)"
    fi

    # Check for summary (means run finished)
    [ -s "$run_dir/summary.json" ] && harness_alive="FINISHED"

    echo "=== $run_id ==="
    echo "  Status:    $harness_alive"
    echo "  Completed: $completed  In-progress: $in_progress"

    # Show completed trials
    for f in "$run_dir"/*.json; do
        [[ "$f" == *_mcp_* || "$f" == *manifest* || "$f" == *summary* ]] && continue
        [ -s "$f" ] || continue
        jq -r '"    " + .benchmark_meta.task + " | " + .benchmark_meta.config + " | " + (.num_turns // 0 | tostring) + "t " + (.benchmark_meta.wall_clock_s // 0 | tostring) + "s score=" + (.correctness.score // "?" | tostring)' "$f" 2>/dev/null
    done

    # Show last log line
    if [ -f "$run_dir/run.log" ]; then
        echo "  Last log: $(tail -1 "$run_dir/run.log" 2>/dev/null)"
    fi
    echo ""
done

#!/bin/zsh
# Generate a markdown report from benchmark results.
# Usage: report.sh <results-dir> [--baseline <name>]
# Reads summary.json and produces a formatted markdown table on stdout.
# With --baseline, also shows deltas against a stored baseline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULTS_DIR="${1:?Usage: report.sh <results-dir> [--baseline <name>]}"
SUMMARY="$RESULTS_DIR/summary.json"
MANIFEST="$RESULTS_DIR/manifest.json"
BASELINE_NAME=""

shift
while [[ $# -gt 0 ]]; do
    case "$1" in
        --baseline) BASELINE_NAME="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [ ! -f "$SUMMARY" ]; then
    echo "Error: $SUMMARY not found" >&2
    exit 1
fi

BASELINE_FILE=""
if [ -n "$BASELINE_NAME" ]; then
    BASELINE_FILE="$SCRIPT_DIR/baselines/${BASELINE_NAME}.json"
    if [ ! -f "$BASELINE_FILE" ]; then
        echo "Error: Baseline '$BASELINE_NAME' not found at $BASELINE_FILE" >&2
        exit 1
    fi
fi

cat <<'HEADER'
# Benchmark Report

HEADER

# Run metadata from manifest
if [ -f "$MANIFEST" ]; then
    MODEL=$(jq -r '.model // "unknown"' "$MANIFEST")
    GIT_SHA=$(jq -r '.git.sha // "unknown"' "$MANIFEST" | head -c 10)
    GIT_DIRTY=$(jq -r '.git.dirty // false' "$MANIFEST")
    STARTED=$(jq -r '.started // "unknown"' "$MANIFEST")
    SIM_DEVICE=$(jq -r '.simulator.device // "unknown"' "$MANIFEST")
    SIM_RUNTIME=$(jq -r '.simulator.runtime // "unknown"' "$MANIFEST")
    DIRTY_TAG=""
    [ "$GIT_DIRTY" = "true" ] && DIRTY_TAG=" (dirty)"

    echo "| | |"
    echo "|---|---|"
    echo "| **Model** | $MODEL |"
    echo "| **Git** | \`${GIT_SHA}\`${DIRTY_TAG} |"
    echo "| **Simulator** | $SIM_DEVICE ($SIM_RUNTIME) |"
    echo "| **Started** | $STARTED |"
    echo ""
fi

# Overall summary table
echo "## Results"
echo ""
echo "| Task | Config | n | OK | Correct | Turns | Wall | Context | Output | Cost |"
echo "|---|---|--:|--:|--:|--:|--:|--:|--:|--:|"

jq -r '.[] |
    "| \(.task) | \(.config) | \(.n) | \(.completed) | \(.correct) | " +
    (if .turns.mean then (.turns.mean | . * 10 | round / 10 | tostring) else "—" end) + " | " +
    (if .wall_s.mean then (.wall_s.mean | round | tostring) + "s" else "—" end) + " | " +
    (if .context_tokens.mean then (.context_tokens.mean | round | tostring | gsub("(?<a>[0-9])(?=([0-9]{3})+$)"; .a + ",")) else "—" end) + " | " +
    (if .output_tokens.mean then (.output_tokens.mean | round | tostring | gsub("(?<a>[0-9])(?=([0-9]{3})+$)"; .a + ",")) else "—" end) + " | " +
    (if .cost_usd.total then "$" + (.cost_usd.total | . * 10000 | round / 10000 | tostring) else "—" end) + " |"
' "$SUMMARY"

echo ""

# --- Savings vs idb ---
echo "## Savings vs idb"
echo ""

jq -r '
    reduce .[] as $row ({}; . + {"\($row.task)|\($row.config)": $row}) as $idx |
    [.[] | .task] | unique | .[] as $task |
    ($idx["\($task)|idb"] // null) as $idb |
    if $idb == null or $idb.context_tokens.mean == null then
        "| \($task) | — | — | — | (no idb baseline) |"
    else
        ["bh", "bh-batch", "bh-expect"] | .[] as $cfg |
        ($idx["\($task)|\($cfg)"] // null) as $row |
        if $row == null or $row.context_tokens.mean == null then
            empty
        else
            "| \($task) | \($cfg) | " +
            (if $row.turns.mean and $idb.turns.mean then
                ((1 - $row.turns.mean / $idb.turns.mean) * 100 | round | tostring) + "%"
            else "—" end) + " | " +
            (if $row.context_tokens.mean and $idb.context_tokens.mean then
                ((1 - $row.context_tokens.mean / $idb.context_tokens.mean) * 100 | round | tostring) + "%"
            else "—" end) + " | " +
            "\($row.correct)/\($row.n) vs \($idb.correct)/\($idb.n) |"
        end
    end
' "$SUMMARY" | {
    echo "| Task | Config | Turn Savings | Token Savings | Correctness |"
    echo "|---|---|--:|--:|---|"
    cat
}

echo ""

# --- Baseline comparison ---
if [ -n "$BASELINE_FILE" ]; then
    echo "## Delta vs Baseline (\`$BASELINE_NAME\`)"
    echo ""

    BASELINE_SHA=$(jq -r '.manifest.git.sha // "?"' "$BASELINE_FILE" | head -c 10)
    BASELINE_MODEL=$(jq -r '.manifest.model // "?"' "$BASELINE_FILE")
    echo "_Baseline: \`$BASELINE_SHA\` ($BASELINE_MODEL)_"
    echo ""

    # Compare each cell: current vs baseline
    jq -r --slurpfile base "$BASELINE_FILE" '
        # Index baseline by task|config
        reduce ($base[0].cells // [])[] as $row ({}; . + {"\($row.task)|\($row.config)": $row}) as $base_idx |

        # Index current by task|config
        reduce .[] as $row ({}; . + {"\($row.task)|\($row.config)": $row}) as $curr_idx |

        # All unique task|config keys from both
        ([$curr_idx | keys[], ($base_idx | keys[])] | unique | .[]) as $key |
        ($curr_idx[$key] // null) as $curr |
        ($base_idx[$key] // null) as $prev |

        if $curr == null or $prev == null then empty
        elif $curr.turns.mean == null or $prev.turns.mean == null then empty
        else
            ($curr.turns.mean - $prev.turns.mean) as $turn_delta |
            (if $prev.context_tokens.mean and $curr.context_tokens.mean and $prev.context_tokens.mean > 0 then
                (($curr.context_tokens.mean - $prev.context_tokens.mean) / $prev.context_tokens.mean * 100) | round
            else null end) as $token_pct |

            "| \($curr.task) | \($curr.config) | " +
            ($prev.turns.mean | . * 10 | round / 10 | tostring) + " → " +
            ($curr.turns.mean | . * 10 | round / 10 | tostring) +
            " (" + (if $turn_delta > 0 then "+" else "" end) + ($turn_delta | . * 10 | round / 10 | tostring) + ") | " +
            (if $token_pct then
                (if $token_pct > 0 then "+" else "" end) + ($token_pct | tostring) + "%"
            else "—" end) + " | " +
            "\($curr.correct)/\($curr.n) vs \($prev.correct)/\($prev.n) |"
        end
    ' "$SUMMARY" | {
        echo "| Task | Config | Turns (prev → curr) | Token Delta | Correctness |"
        echo "|---|---|---|--:|---|"
        cat
    }

    echo ""
fi

# --- Correctness failures ---
echo "## Correctness Details"
echo ""

HAS_FAILURES=false
for result_file in "$RESULTS_DIR"/*.json; do
    [ "$(basename "$result_file")" = "summary.json" ] && continue
    [ "$(basename "$result_file")" = "manifest.json" ] && continue
    score=$(jq -r '.correctness.score // "?"' "$result_file")

    if [ "$score" = "0" ] || [ "$score" = "0.5" ]; then
        HAS_FAILURES=true
        task=$(jq -r '.benchmark_meta.task // "?"' "$result_file")
        config=$(jq -r '.benchmark_meta.config // "?"' "$result_file")
        trial=$(jq -r '.benchmark_meta.trial // "?"' "$result_file")
        turns=$(jq -r '.num_turns // "?"' "$result_file")
        echo "- **$task | $config | #$trial**: score=$score, turns=$turns"
        jq -r '.correctness.details // {} | to_entries[] | select(.value.match == false) |
            "  - \(.key): expected \(.value.expected), got \(.value.actual)"' "$result_file" 2>/dev/null
    fi
done

if [ "$HAS_FAILURES" = false ]; then
    echo "_All trials scored 1.0 (or manual)._"
fi

echo ""
echo "---"
echo "*Generated $(date -u +%Y-%m-%dT%H:%M:%SZ)*"

#!/usr/bin/env bash
# Require a successful main-branch CI push run for one exact commit.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/release-contract.sh
source "$SCRIPT_DIR/release-contract.sh"

REPOSITORY="$BUTTONHEIST_GITHUB_REPO"
TIMEOUT_SECONDS=0
POLL_SECONDS=15

usage() {
    cat <<'EOF'
Usage: scripts/require-successful-ci-for-commit.sh [options] COMMIT [LABEL]

Options:
  --repo OWNER/REPO  GitHub repository. Defaults to the release contract repo.
  --timeout SECONDS  Wait this long for CI. Defaults to an immediate check.
  --poll SECONDS     Poll interval while waiting. Defaults to 15 seconds.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) REPOSITORY="${2:-}"; shift 2 ;;
        --timeout) TIMEOUT_SECONDS="${2:-}"; shift 2 ;;
        --poll) POLL_SECONDS="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        -*) echo "Error: unknown option '$1'" >&2; usage >&2; exit 2 ;;
        *) break ;;
    esac
done

COMMIT_SHA="${1:-}"
LABEL="${2:-release commit}"
if [[ -z "$COMMIT_SHA" || -z "$REPOSITORY" ]]; then
    usage >&2
    exit 2
fi
if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$POLL_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: timeout must be nonnegative and poll must be positive" >&2
    exit 2
fi

ci_run_count() {
    local jq_filter="$1"
    gh run list \
        --repo "$REPOSITORY" \
        --workflow CI \
        --branch main \
        --commit "$COMMIT_SHA" \
        --limit 20 \
        --json conclusion,event,status \
        --jq "$jq_filter" 2>/dev/null || echo 0
}

print_ci_runs() {
    gh run list \
        --repo "$REPOSITORY" \
        --workflow CI \
        --branch main \
        --commit "$COMMIT_SHA" \
        --limit 20 || true
}

report_failure() {
    local message="$1"
    print_ci_runs
    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        echo "::error::$message"
    else
        echo "Error: $message" >&2
    fi
}

deadline=$((SECONDS + TIMEOUT_SECONDS))
echo "Waiting for main CI on $LABEL (${COMMIT_SHA:0:8})..."
while true; do
    success_count=$(ci_run_count '[.[] | select(.event == "push" and .status == "completed" and .conclusion == "success")] | length')
    if [[ "$success_count" -gt 0 ]]; then
        echo "CI verified green on exact commit ${COMMIT_SHA:0:8}"
        exit 0
    fi

    running_count=$(ci_run_count '[.[] | select(.event == "push" and .status != "completed")] | length')
    failed_count=$(ci_run_count '[.[] | select(.event == "push" and .status == "completed" and .conclusion != "success")] | length')
    total_count=$(ci_run_count '[.[] | select(.event == "push")] | length')
    if [[ "$failed_count" -gt 0 && "$running_count" -eq 0 && "$total_count" -gt 0 ]]; then
        report_failure "Main-branch CI failed on exact $LABEL $COMMIT_SHA."
        exit 1
    fi

    if [[ "$TIMEOUT_SECONDS" -eq 0 || "$SECONDS" -ge "$deadline" ]]; then
        report_failure "No successful main-branch CI push run found for exact $LABEL $COMMIT_SHA."
        exit 1
    fi
    sleep "$POLL_SECONDS"
done

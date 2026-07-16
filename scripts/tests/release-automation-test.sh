#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
FAKE_BIN="$FIXTURE_ROOT/bin"
GH_LOG="$FIXTURE_ROOT/gh.log"

cd "$REPO_ROOT"

trap 'rm -rf "$FIXTURE_ROOT"' EXIT
mkdir -p "$FAKE_BIN"

# shellcheck source=scripts/release-contract.sh
source "$REPO_ROOT/scripts/release-contract.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

canonical_version=$(buttonheist_code_version)
release_version=$(tr -d '[:space:]' < "$REPO_ROOT/$BUTTONHEIST_RELEASE_VERSION_FILE")
[[ "$canonical_version" == "$release_version" ]] \
    || fail "canonical code version ($canonical_version) disagrees with release mirror ($release_version)"

cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_LOG"

if [[ "${1:-} ${2:-}" == "run list" && "$*" == *"--json"* ]]; then
    jq -cn \
        --arg sha "$FAKE_GH_SHA" \
        --arg conclusion "${FAKE_GH_RESULT:-success}" \
        '[{
            databaseId: 17,
            event: "push",
            headSha: $sha,
            status: "completed",
            conclusion: $conclusion
        }]'
    exit 0
fi
if [[ "${1:-} ${2:-}" == "run view" ]]; then
    jq -cn --arg conclusion "${FAKE_GH_RESULT:-success}" '{jobs: [{
        name: "exact-sha-suite",
        status: "completed",
        conclusion: $conclusion
    }]}'
    exit 0
fi
if [[ "${1:-} ${2:-}" == "run download" ]]; then
    destination=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--dir" ]]; then
            destination="${2:-}"
            break
        fi
        shift
    done
    [[ -n "$destination" ]]
    mkdir -p "$destination"
    jq -cn --arg sha "$FAKE_GH_SHA" '{
        schemaVersion: 1,
        commit: $sha,
        workflow: {
            ref: "RoyalPineapple/TheButtonHeist/.github/workflows/ci.yml@refs/heads/main",
            sha: $sha,
            runId: "17",
            runAttempt: "1"
        },
        suites: [
            {name: "release-contract", conclusion: "success"},
            {name: "macos-tests", conclusion: "success"},
            {name: "ios-tests", conclusion: "success"},
            {name: "ios-demo-gates", conclusion: "success"},
            {name: "main-integration", conclusion: "success"},
            {name: "critical-mutations", conclusion: "success"}
        ]
    }' > "$destination/exact-sha-suite.json"
    exit 0
fi
if [[ "${1:-} ${2:-}" == "run list" ]]; then
    echo "fixture CI run"
    exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 2
EOF
chmod +x "$FAKE_BIN/gh"

PATH="$FAKE_BIN:$PATH" \
FAKE_GH_LOG="$GH_LOG" \
FAKE_GH_SHA=0123456789abcdef \
FAKE_GH_RESULT=success \
    "$REPO_ROOT/scripts/require-successful-ci-for-commit.sh" \
    --repo RoyalPineapple/TheButtonHeist \
    0123456789abcdef \
    fixture

grep -Fq -- '--branch main --commit 0123456789abcdef' "$GH_LOG" \
    || fail "exact-commit CI guard did not constrain branch and commit"

set +e
output=$(
    PATH="$FAKE_BIN:$PATH" \
    FAKE_GH_LOG="$GH_LOG" \
    FAKE_GH_SHA=fedcba9876543210 \
    FAKE_GH_RESULT=failure \
        "$REPO_ROOT/scripts/require-successful-ci-for-commit.sh" \
        --repo RoyalPineapple/TheButtonHeist \
        fedcba9876543210 \
        fixture 2>&1
)
status=$?
set -e
[[ "$status" -eq 1 ]] || fail "exact-commit CI guard accepted a failed push run: $output"
[[ "$output" == *"No successful exact-SHA release suite"* ]] \
    || fail "failed CI result lacked a useful diagnostic: $output"

echo "PASS: release automation shares canonical version and exact-commit CI ownership"

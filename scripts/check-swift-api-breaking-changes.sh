#!/usr/bin/env bash
# Check public Swift API compatibility against the latest release tag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BASELINE_TAG="${BUTTONHEIST_SWIFT_API_BASELINE_TAG:-}"

if [[ -z "$BASELINE_TAG" ]]; then
    git fetch --quiet --force --tags origin +refs/heads/main:refs/remotes/origin/main
    BASELINE_TAG="$(git tag --merged origin/main --sort=-v:refname 'v*' | head -1 || true)"
fi

if [[ -z "$BASELINE_TAG" ]]; then
    echo "No release tag found on origin/main; skipping Swift API breakage check."
    exit 0
fi

echo "Checking Swift API breakage against $BASELINE_TAG"
INTENTIONAL_BREAKAGES=(
    # Add only diagnostics absent from the baseline gate.
)

extract_intentional_breakages() {
    awk '
        /^INTENTIONAL_BREAKAGES=\($/ { in_array = 1; found = 1; next }
        in_array && /^\)$/ { complete = 1; exit }
        in_array && /^[[:space:]]*(#.*)?$/ { next }
        in_array && /^[[:space:]]*"[^"]*"[[:space:]]*$/ {
            line = $0
            sub(/^[[:space:]]*"/, "", line)
            sub(/"[[:space:]]*$/, "", line)
            print line
            next
        }
        in_array { exit 2 }
        END { if (!found || !complete) exit 2 }
    '
}

if [[ "${#INTENTIONAL_BREAKAGES[@]}" -gt 0 ]]; then
    GATE_PATH="scripts/$(basename "${BASH_SOURCE[0]}")"
    if ! git rev-parse --verify "${BASELINE_TAG}^{commit}" >/dev/null 2>&1; then
        echo "Error: Swift API baseline '$BASELINE_TAG' is not a commit."
        exit 2
    fi

    baseline_breakages=()
    if git cat-file -e "$BASELINE_TAG:$GATE_PATH" 2>/dev/null; then
        if ! baseline_source="$(git show "$BASELINE_TAG:$GATE_PATH")" \
            || ! baseline_breakage_lines="$(
                printf '%s\n' "$baseline_source" | extract_intentional_breakages
            )"; then
            echo "Error: could not parse Swift API breakage exemptions from $BASELINE_TAG."
            exit 2
        fi
        while IFS= read -r breakage; do
            [[ -n "$breakage" ]] || continue
            baseline_breakages+=("$breakage")
        done <<< "$baseline_breakage_lines"
    fi

    stale_breakages=()
    for intentional in "${INTENTIONAL_BREAKAGES[@]}"; do
        for baseline_breakage in "${baseline_breakages[@]}"; do
            if [[ "$intentional" == "$baseline_breakage" ]]; then
                stale_breakages+=("$intentional")
                break
            fi
        done
    done

    if [[ "${#stale_breakages[@]}" -gt 0 ]]; then
        echo "Error: stale Swift API breakage exemption inherited from $BASELINE_TAG:"
        printf '  - %s\n' "${stale_breakages[@]}"
        exit 2
    fi
fi

PUBLIC_PRODUCTS=()
while IFS= read -r product; do
    PUBLIC_PRODUCTS+=("$product")
done < <(grep -E '^[[:space:]]*[.]library[(]name:[[:space:]]*"[^"]+"' Package.swift \
    | sed -E 's/.*name:[[:space:]]*"([^"]+)".*/\1/')

if [[ "${#PUBLIC_PRODUCTS[@]}" -eq 0 ]]; then
    echo "Error: no Swift library products found in Package.swift."
    exit 2
fi

MODE="${BUTTONHEIST_SWIFT_API_BREAKAGE_MODE:-strict}"
case "$MODE" in
    strict|report) ;;
    *)
        echo "Error: BUTTONHEIST_SWIFT_API_BREAKAGE_MODE must be 'strict' or 'report', got '$MODE'"
        exit 2
        ;;
esac

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

set +e
swift package diagnose-api-breaking-changes "$BASELINE_TAG" \
    --products "${PUBLIC_PRODUCTS[@]}" 2>&1 | tee "$OUTPUT_FILE"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -eq 0 ]]; then
    exit 0
fi

if [[ "$MODE" == "report" ]]; then
    echo "Swift API breakage reported in non-blocking mode."
    echo "Run with BUTTONHEIST_SWIFT_API_BREAKAGE_MODE=strict to fail on this diagnostic."
    exit 0
fi

detected_breakages=()
while IFS= read -r line; do
    [[ "$line" == *"API breakage: "* ]] || continue
    breakage="${line#*"API breakage: "}"
    [[ -n "$breakage" ]] || continue
    detected_breakages+=("$breakage")
done < "$OUTPUT_FILE"
if [[ "${#detected_breakages[@]}" -eq 0 ]]; then
    exit "$status"
fi

unexpected_breakages=()
for breakage in "${detected_breakages[@]}"; do
    allowed=0
    for intentional in "${INTENTIONAL_BREAKAGES[@]}"; do
        if [[ "$breakage" == "$intentional" ]]; then
            allowed=1
            break
        fi
    done
    if [[ "$allowed" -eq 0 ]]; then
        unexpected_breakages+=("$breakage")
    fi
done

if [[ "${#unexpected_breakages[@]}" -eq 0 ]]; then
    echo "Only intentional Swift API breakage detected:"
    printf '  - %s\n' "${detected_breakages[@]}"
    exit 0
fi

echo "Unexpected Swift API breakage detected:"
printf '  - %s\n' "${unexpected_breakages[@]}"
exit "$status"

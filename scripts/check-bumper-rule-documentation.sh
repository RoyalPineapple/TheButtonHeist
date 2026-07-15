#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RULE_SOURCE="$REPO_ROOT/.bumper/Sources/ButtonHeistCustomRules.swift"
RULE_DOC="$REPO_ROOT/docs/BUMPER-RULES.md"

fail() {
    echo "Bumper rule documentation error: $*" >&2
    exit 1
}

require_documented() {
    local value="$1"
    grep -Fq "\`$value\`" "$RULE_DOC" || fail "missing documentation for $value"
}

[[ -f "$RULE_DOC" ]] || fail "missing docs/BUMPER-RULES.md"

while IFS= read -r rule_id; do
    require_documented "$rule_id"
done < <(
    grep -Eo '"buttonheist\.[A-Za-z0-9_.]+"' "$RULE_SOURCE" \
        | tr -d '"' \
        | sort -u
)

for rule_id in \
    component_boundary \
    declared_dependency_cycle \
    duplicate_ownership \
    forbidden_import; do
    require_documented "$rule_id"
done

while IFS= read -r symbol; do
    require_documented "$symbol"
done < <(
    sed -n '/private enum ArchitectureCurrency:/,/^}/p' "$RULE_SOURCE" \
        | sed -n 's/.*= "\([^"]*\)"/\1/p'
)

custom_rule_count="$(grep -Ec 'Rules\.(repository|files)\(' "$RULE_SOURCE" || true)"
custom_summary_count="$(grep -Ec '^[[:space:]]+summary: "' "$RULE_SOURCE" || true)"
[[ "$custom_rule_count" -eq "$custom_summary_count" ]] \
    || fail "every custom repository/file rule must declare an explicit summary"

echo "Bumper rule documentation is complete."

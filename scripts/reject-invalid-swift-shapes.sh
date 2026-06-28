#!/usr/bin/env bash
# Reject retired dynamic/compatibility shapes in Swift code.

set -euo pipefail

CODE_PATHS=(
  ButtonHeist/Sources
  ButtonHeist/Tests
  ButtonHeistCLI/Sources
  ButtonHeistCLI/Tests
  ButtonHeistMCP/Sources
  ButtonHeistMCP/Tests
  Project.swift
  Package.swift
)

EXISTING_PATHS=()
for path in "${CODE_PATHS[@]}"; do
  if [[ -e "$path" ]]; then
    EXISTING_PATHS+=("$path")
  fi
done

CHECKS=(
  'retired plan-source request type::\bHeistPlanSourceRequest\b'
  'retired inline plan-source field::\binlineButtonHeistSource\b'
  'retired inline admission compatibility flag::\bacceptsInlineButtonHeistSource\b'
  'untyped JSON dictionary::\[String:[[:space:]]*Any\]'
  'type-erased hash key::\bAnyHashable\b'
  'metatype-as-data expectation::\bAny\.Type\b'
  'Foundation dynamic JSON traversal::\bJSONSerialization\.(jsonObject|data)\b'
  'visible Any bridge::\bas Any\b'
)

status=0
for check in "${CHECKS[@]}"; do
  label="${check%%::*}"
  pattern="${check#*::}"
  matches="$(git grep -n -E "$pattern" -- "${EXISTING_PATHS[@]}" || true)"
  if [[ -n "$matches" ]]; then
    echo "::error::Invalid Swift pipeline shape rejected: $label"
    printf '%s\n' "$matches"
    status=1
  fi
done

if [[ "$status" -ne 0 ]]; then
  cat <<'EOF'

Only typed Swift models, typed Codable fixtures, concrete enums/structs, and
narrow typed bridge helpers are accepted here.
EOF
fi

exit "$status"

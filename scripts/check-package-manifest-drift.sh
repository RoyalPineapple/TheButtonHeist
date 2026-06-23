#!/usr/bin/env bash
# Validate the intentional overlap between root Package.swift and ButtonHeist/Package.swift.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/check-package-manifest-drift.py" "$@"

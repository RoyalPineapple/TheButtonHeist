// Package contract: `import ButtonHeist` is the aggregate macOS facade for
// public authoring (`ThePlans`) and client/runtime diagnostics (`TheScore`).
// scripts/check-buttonheist-import-contract.sh owns the allowlist for this
// intentional re-export surface.
@_exported import ThePlans
@_exported import TheScore

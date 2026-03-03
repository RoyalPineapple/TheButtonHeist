# Versioning

Button Heist uses [Semantic Versioning](https://semver.org/) (SemVer): `MAJOR.MINOR.PATCH`.

## Current version

**0.0.1** — Initial SemVer baseline.

## Version format

| Component | When to increment |
|-----------|-------------------|
| **MAJOR** | Breaking changes (incompatible API, protocol, or behavior) |
| **MINOR** | New features (backward compatible) |
| **PATCH** | Bug fixes and small improvements (backward compatible) |

During 0.x.y, the API is considered unstable; MINOR bumps may include breaking changes.

## Single source of truth

The canonical version lives in:

```
ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift
```

```swift
public let buttonHeistVersion = "0.0.1"
```

This constant is used by:
- **ButtonHeistCLI** — `buttonheist --version`
- **ButtonHeistMCP** — MCP server version reporting

## Files updated by release script

`./scripts/release.sh <version>` updates:

1. **`buttonHeistVersion`** in `TheFence+CommandCatalog.swift` (source of truth)
2. **`VERSION`** at repo root (for tooling, CI, tags)
3. **`docs/API.md`** — CLI Reference section
4. **`TestApp/Sources/DisclosureGroupingDemo.swift`** — demo UI version label
5. **`docs/VERSIONING.md`** — current version line

## Release workflow

Use the release script for consistency:

```bash
./scripts/release.sh 0.0.2
```

The script updates all version references. Then:

1. Run full build and tests (see CLAUDE.md Pre-Commit Checklist)
2. Commit: `git add -A && git commit -m 'Release 0.0.2'`
3. Tag: `git tag v0.0.2`

Use `--dry-run` to preview changes without modifying files.

## Protocol version vs product version

- **Product version** (`buttonHeistVersion`): What users see; follows SemVer.
- **Protocol version** (`protocolVersion` in `Messages.swift`): Wire protocol compatibility; separate from product version. Bump when message formats or handshake change.

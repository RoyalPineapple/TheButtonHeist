# Versioning

Button Heist uses two versioning schemes:

- **Product version**: [CalVer](https://calver.org/) `YYYY.MM.DD` — the version users see.
- **Protocol version**: [SemVer](https://semver.org/) — wire protocol compatibility only.

## Product version (CalVer)

Format: `YYYY.MM.DD` with an optional `.PATCH` suffix for same-day releases (e.g. `2026.03.27.1`).

### Current version

**0.0.1** — Pre-CalVer baseline. The first CalVer release will be the date it ships.

### Why CalVer

- Releases are date-stamped, so "which version am I on?" is instantly obvious.
- No bikeshedding over major/minor/patch — the date is the version.
- Same-day hotfixes use the `.PATCH` suffix: `2026.03.27`, `2026.03.27.1`, etc.

### Single source of truth

The canonical version lives in:

```
ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift
```

```swift
public let buttonHeistVersion = "2026.03.27"
```

This constant is used by:
- **ButtonHeistCLI** — `buttonheist --version`
- **ButtonHeistMCP** — MCP server version reporting
- **TheInsideJob** — iOS server status identity

### Files updated by release script

`./scripts/release.sh [<version>]` updates:

1. **`buttonHeistVersion`** in `TheScore/Messages.swift` (source of truth)
2. **`VERSION`** at repo root (for tooling, CI, tags)
3. **`docs/API.md`** — CLI Reference section
4. **`TestApp/Sources/DisclosureGroupingDemo.swift`** — demo UI version label
5. **`docs/VERSIONING.md`** — current version line
6. **`Formula/buttonheist.rb`** — Homebrew formula version

If no version argument is given, the script defaults to today's date.

### Release workflow

```bash
./scripts/release.sh              # Uses today's date
./scripts/release.sh 2026.03.27   # Explicit date
./scripts/release.sh --dry-run    # Preview only
```

The script updates all version references. Then:

1. Run full build and tests (see CLAUDE.md Pre-Commit Checklist)
2. Commit: `git add -A && git commit -m 'Release 2026.03.27'`
3. Tag: `git tag v2026.03.27`

Use `--dry-run` to preview changes without modifying files.

## Protocol version (SemVer)

The wire protocol version (`protocolVersion` in `Messages.swift`) follows SemVer and is **independent** of the product version. Bump it only when the wire format, handshake, or message schema changes.

| Component | When to increment |
|-----------|-------------------|
| **MAJOR** | Breaking wire changes (removed fields, changed semantics) |
| **MINOR** | New message types or optional fields (backward compatible) |
| **PATCH** | Bug fixes to encoding/decoding (backward compatible) |

The release script does **not** touch `protocolVersion` — it is bumped manually and deliberately when the protocol changes.

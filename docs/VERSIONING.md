# Versioning

Button Heist uses two versioning schemes:

- **Product version**: [CalVer](https://calver.org/) `YYYY.MM.DD` — the version users see.
- **Protocol version**: [SemVer](https://semver.org/) — wire protocol compatibility only.

## Product version (CalVer)

Format: `YYYY.MM.DD` with an optional `.PATCH` suffix for same-day releases (e.g. `2026.03.27.1`).

### Current version

**2026.04.02** — Pre-CalVer baseline. The first CalVer release will be the date it ships.

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

The release script performs the full pipeline from a clean `main` branch:

```bash
./scripts/release.sh              # Uses today's date
./scripts/release.sh 2026.04.03   # Explicit date
./scripts/release.sh --dry-run    # Preview only
```

The script:

1. **Validates** — must be on `main`, in sync with `origin/main`, clean worktree
2. **Bumps version** across 6 files
3. **Builds** all targets (TheScore, ButtonHeist, TheInsideJob, CLI, MCP)
4. **Tests** all suites (TheScoreTests, ButtonHeistTests, TheInsideJobTests)
5. **Commits, tags, pushes** to `origin/main`
6. **Creates GitHub release** with CLI and MCP binaries
7. **Updates Homebrew tap** (`RoyalPineapple/homebrew-tap`) with real SHA-256 hashes

Use `--dry-run` to preview without modifying anything.

## Protocol version (SemVer)

The wire protocol version (`protocolVersion` in `Messages.swift`) follows SemVer and is **independent** of the product version. Bump it only when the wire format, handshake, or message schema changes.

| Component | When to increment |
|-----------|-------------------|
| **MAJOR** | Breaking wire changes (removed fields, changed semantics) |
| **MINOR** | New message types or optional fields (backward compatible) |
| **PATCH** | Bug fixes to encoding/decoding (backward compatible) |

The release script does **not** touch `protocolVersion` — it is bumped manually and deliberately when the protocol changes.

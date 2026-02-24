# Simulator State Snapshots

Use iOS Simulator snapshots for TimeMachine-style testing — save app state before risky actions, restore to known states for faster navigation, and recover from crashes without replaying the full action sequence.

## Prerequisites

- Requires Bash tool access (for `xcrun simctl` commands)
- Simulator must be booted
- Know your simulator UDID (from `xcrun simctl list devices`)

## Commands

### Save a snapshot
```bash
xcrun simctl snapshot save <UDID> <snapshot-name>
```

### Restore a snapshot
```bash
xcrun simctl snapshot restore <UDID> <snapshot-name>
```

### List snapshots
```bash
xcrun simctl snapshot list <UDID>
```

### Delete a snapshot
```bash
xcrun simctl snapshot delete <UDID> <snapshot-name>
```

## Naming Convention

Use descriptive names that tie back to session notes:

```
fuzz-<session-date>-<screen-name>
```

Examples:
- `fuzz-20260217-main-menu` — snapshot at the main menu
- `fuzz-20260217-settings-all-toggles-on` — snapshot with all settings toggles enabled
- `fuzz-20260217-deep-profile-edit` — snapshot deep in the profile edit flow

## When to Snapshot

### Before exploring a new screen
Save before navigating into an unexplored area. If the app crashes during exploration, you can restore to just before the crash instead of replaying from app launch.

### Before destructive actions
If you're about to try something that might corrupt state (typing extreme values, rapid-fire interactions), save first.

### At interesting states
If you've set up a specific configuration (all toggles on, form partially filled, specific navigation depth), save it. You can restore later to test from that exact state without replaying all the setup actions.

### Before stress testing
Save right before a stress test sequence. If it crashes, you have the exact pre-crash state for reproduction.

## Integration with Session Notes

Track snapshots in your session notes file under a `## Snapshots` section:

```markdown
## Snapshots
| Name | Screen | Description | Created At |
|------|--------|-------------|------------|
| fuzz-20260217-main-menu | Main Menu | Initial state, no interactions | Action #0 |
| fuzz-20260217-settings-modified | Settings | Dark mode on, notifications off | Action #25 |
```

When restoring a snapshot, note it in the `## Action Log`:
```
[#51] RESTORED snapshot fuzz-20260217-settings-modified → back on Settings screen
```

## Workflow: Crash Reproduction

When a crash occurs:

1. Note the exact action that caused the crash (from session notes `## Action Log`)
2. Note the last saved snapshot before the crash
3. After relaunching the app, restore the snapshot:
   ```bash
   xcrun simctl snapshot restore <UDID> fuzz-20260217-pre-crash-state
   ```
4. The app is now back at the pre-crash state
5. Replay just the last few actions to reproduce the crash
6. This gives you a minimal reproduction path

## Workflow: Deep Navigation Shortcut

For apps with deep navigation (5+ levels):

1. Save a snapshot at each navigation depth as you explore
2. When you need to test something on a deep screen again, restore the nearest snapshot instead of navigating through all the intermediate screens
3. This saves significant time and action budget

## Limitations

- Snapshots include the full simulator state (all apps, system settings, etc.)
- Restoring a snapshot kills and relaunches the app — you'll need to wait for the app to re-advertise via Bonjour
- Snapshot save/restore takes a few seconds
- Storage: each snapshot can be large (hundreds of MB). Clean up snapshots at session end.

## Cleanup

At the end of a fuzzing session, delete all session snapshots:

```bash
# List and delete all session snapshots
xcrun simctl snapshot list <UDID>
xcrun simctl snapshot delete <UDID> fuzz-20260217-main-menu
xcrun simctl snapshot delete <UDID> fuzz-20260217-settings-modified
# ... etc
```

Or note in the session report which snapshots were preserved for future reproduction.

# Trace: fuzzsession-2026-03-03-1315-fuzz-systematic-traversal
**Session notes**: fuzzsession-2026-03-03-1315-fuzz-systematic-traversal.md

## Entries

### #1 observe
- **timestamp**: 2026-03-03T13:15:00Z
- **type**: observe
- **screen**: Main Menu
- **element_count**: 10
- **interactive_count**: 8
- **purpose**: initial_observation

### #2 interact
- **timestamp**: 2026-03-03T13:15:10Z
- **type**: interact
- **command**: `buttonheist activate --index 0 --format json`
- **screen_before**: Main Menu
- **result**: {status: ok, method: activate, delta: elementsChanged}
- **screen_after**: Controls Demo
- **purpose**: navigation

### #3 interact
- **timestamp**: 2026-03-03T13:15:25Z
- **type**: interact
- **command**: `buttonheist activate --index 1 --device a88cecc5 --format json`
- **screen_before**: Controls Demo
- **result**: {status: ok, method: activate, delta: screenChanged, newElements: 19}
- **screen_after**: Toggles & Pickers
- **purpose**: navigation

### #4 interact
- **timestamp**: 2026-03-03T13:15:35Z
- **type**: interact
- **command**: `buttonheist activate --identifier buttonheist.pickers.subscribeToggle --format json`
- **screen_before**: Toggles & Pickers
- **result**: {status: ok, method: activate, delta: valuesChanged, changes: [subscribeToggle 0→1, lastActionLabel "None"→"Toggle: ON"]}
- **screen_after**: Toggles & Pickers
- **purpose**: fuzzing

### #5 interact
- **timestamp**: 2026-03-03T13:15:50Z
- **type**: interact
- **command**: `buttonheist activate --identifier BackButton --format json`
- **screen_before**: Toggles & Pickers
- **result**: {status: ok, method: syntheticTap, delta: screenChanged, newElements: 17}
- **screen_after**: Main Menu
- **purpose**: navigation

### #6 interact
- **timestamp**: 2026-03-03T13:16:00Z
- **type**: interact
- **command**: `buttonheist activate --index 5 --device a88cecc5 --format json`
- **screen_before**: Main Menu
- **result**: {status: ok, method: activate, delta: screenChanged, newElements: 32}
- **screen_after**: Settings
- **purpose**: navigation

### #7 interact
- **timestamp**: 2026-03-03T13:16:10Z
- **type**: interact
- **command**: `buttonheist activate --index 11 --device a88cecc5 --format json`
- **screen_before**: Settings
- **result**: {status: ok, method: activate, delta: valuesChanged, changes: [showCompleted 1→0]}
- **screen_after**: Settings
- **purpose**: fuzzing

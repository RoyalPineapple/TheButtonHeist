You are integrating Button Heist into this iOS project. Your job is to add the
TheInsideJob framework so it auto-starts in DEBUG builds. TheInsideJob runs an
in-app server that lets AI agents (and humans) control the app via CLI or MCP.

No initialization code is needed — the framework auto-starts via an ObjC +load
hook when the binary is linked. You just need to: add the dependency, add the
import, and add Info.plist entries.

**Important:** TheInsideJob requires iOS 17.0+ and swift-tools-version 6.0+.

## Step 1: Identify the build system

Look at the project root and determine which build system and dependency manager
is in use. Check for these files in order:

| File                | Build system       |
|---------------------|--------------------|
| Package.swift       | Swift Package Manager |
| Podfile             | CocoaPods          |
| Cartfile            | Carthage           |
| Project.swift       | Tuist              |
| project.yml         | XcodeGen           |
| BUILD / BUILD.bazel | Bazel              |
| *.xcodeproj only    | Bare Xcode project |
| *.xcworkspace       | Xcode workspace (check what is inside) |

A project may use multiple (e.g. CocoaPods + Xcode workspace, or Tuist + SPM).
Identify the primary dependency management path.

## Step 2: Identify the app target

Find the main iOS application target — the one that produces a .app bundle.
Skip test targets, app extensions (widgets, intents, share extensions), watch
apps, and framework/library targets.

If there are multiple app targets (e.g. a debug app and a production app),
prefer the debug/development target. If unclear, ask the user which target.

## Step 3: Add the dependency

### Swift Package Manager (Package.swift)

Add to the package dependencies array:

```swift
.package(url: "https://github.com/RoyalPineapple/ButtonHeist.git", branch: "main")
```

Add to the app target dependencies:

```swift
.product(name: "TheInsideJob", package: "ButtonHeist")
```

TheInsideJob is iOS-only. If the package has cross-platform targets, use a
platform condition:

```swift
.product(name: "TheInsideJob", package: "ButtonHeist", condition: .when(platforms: [.iOS]))
```

### Xcode project with SPM (no Package.swift, just .xcodeproj)

Xcode has built-in SPM support but there is no CLI command to add a package
dependency. Instruct the user:

"Open your project in Xcode > File > Add Package Dependencies >
paste https://github.com/RoyalPineapple/ButtonHeist.git > add TheInsideJob
to your app target."

### CocoaPods (Podfile)

Button Heist does not publish a podspec. Add it as an SPM dependency alongside
CocoaPods — many projects use both. Add the SPM package to the .xcworkspace via
the Xcode package dependency UI:

1. Open the .xcworkspace in Xcode
2. File > Add Package Dependencies
3. Paste https://github.com/RoyalPineapple/ButtonHeist.git
4. Add TheInsideJob to the app target

Then continue to Step 4 (the import).

### Carthage (Cartfile)

Carthage is not supported. Tell the user to add ButtonHeist as an SPM
dependency instead — Xcode has built-in SPM support since Xcode 11, and the
two can coexist in the same project.

### Tuist (Project.swift)

1. Add to `Tuist/Package.swift`:

```swift
.package(url: "https://github.com/RoyalPineapple/ButtonHeist.git", branch: "main")
```

2. Run `tuist install` to fetch it.

3. In the app target definition, add the dependency:

```swift
.external(name: "TheInsideJob")
```

4. Run `tuist generate` to regenerate the Xcode project.

### XcodeGen (project.yml)

Add to the `packages` section:

```yaml
packages:
  ButtonHeist:
    url: https://github.com/RoyalPineapple/ButtonHeist.git
    branch: main
```

Add to the app target dependencies:

```yaml
targets:
  YourApp:
    dependencies:
      - package: ButtonHeist
        product: TheInsideJob
```

Then run `xcodegen generate`.

### Bazel (BUILD files)

Add as a repository rule in WORKSPACE/MODULE.bazel:

```starlark
git_override(
    module_name = "ButtonHeist",
    remote = "https://github.com/RoyalPineapple/ButtonHeist.git",
    branch = "main",
)
```

Or with `rules_swift_package_manager`:

```starlark
swift_package(
    name = "ButtonHeist",
    url = "https://github.com/RoyalPineapple/ButtonHeist.git",
    branch = "main",
)
```

Add `@ButtonHeist//:TheInsideJob` to the app target deps.

If the Bazel setup is complex or non-standard, describe what needs to happen
and let the user wire it in. Do not guess at custom macros.

### Bare Xcode project (no dependency manager)

Add ButtonHeist as an SPM dependency directly in the .xcodeproj. This is the
simplest path — Xcode has built-in SPM support since Xcode 11.

If the project deliberately avoids SPM (rare), instruct the user to build
TheInsideJob.xcframework from source and embed it manually.

## Step 4: Add the import

Find the app entry point. Look for these patterns:

**SwiftUI app:**
```swift
@main
struct SomeApp: App {
```

**UIKit AppDelegate:**
```swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
```
or
```swift
@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
```

**UIKit SceneDelegate (iOS 13+):**
The entry point is still AppDelegate. The import goes in AppDelegate.swift.

**ObjC main.m / main.swift:**
Add the import in AppDelegate.swift. If AppDelegate is also ObjC, add it in
the bridging header or a Swift file compiled into the target.

**No obvious entry point:**
Search for `UIApplication.shared`, `UIWindow`, `@main`, `@UIApplicationMain`,
or `INFOPLIST_KEY_UIMainStoryboardFile` build setting.

Add the import wrapped in a DEBUG guard:

```swift
#if DEBUG
import TheInsideJob
#endif
```

Place it with the other imports at the top of the file.

## Step 5: Info.plist entries

TheInsideJob uses Bonjour for device discovery. iOS requires two Info.plist
keys for local network access:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Button Heist uses the local network for UI automation.</string>
<key>NSBonjourServices</key>
<array>
    <string>_buttonheist._tcp</string>
</array>
```

How to add them depends on the project:

**Traditional Info.plist file:**
Find the app Info.plist (check the target build settings for `INFOPLIST_FILE`)
and add the keys directly.

**Xcode-generated Info.plist (Xcode 15+):**
If there is no Info.plist file and the target uses `GENERATE_INFOPLIST_FILE = YES`,
add the keys via build settings:

```
INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Button Heist uses the local network for UI automation."
INFOPLIST_KEY_NSBonjourServices = _buttonheist._tcp
```

Or create an Info.plist file and set `INFOPLIST_FILE` to point at it.

**Tuist:**
Add to the target infoPlist parameter:

```swift
.extendingDefault(with: [
    "NSLocalNetworkUsageDescription": "Button Heist uses the local network for UI automation.",
    "NSBonjourServices": ["_buttonheist._tcp"],
])
```

**XcodeGen (project.yml):**
```yaml
info:
  properties:
    NSLocalNetworkUsageDescription: "Button Heist uses the local network for UI automation."
    NSBonjourServices:
      - _buttonheist._tcp
```

**Bazel:**
Add to the `ios_application` rule infoplists attribute.

**Important:** If the app already has `NSBonjourServices`, append
`_buttonheist._tcp` to the existing array — do not replace it.

## Step 6: Verify the build

Run a build to confirm everything compiles:

```bash
# For Xcode projects/workspaces
xcodebuild -workspace <Workspace>.xcworkspace -scheme <AppScheme> \
  -destination 'generic/platform=iOS Simulator' build

# For Tuist
tuist generate && tuist build <scheme>

# For Bazel
bazel build //path/to:<app_target>
```

Do not use `swift build` for iOS projects — it does not have access to iOS SDKs.

If the build fails, read the error and fix it. Common issues:
- Platform mismatch (TheInsideJob is iOS-only, do not link it to macOS targets)
- Minimum deployment target too low (requires iOS 17.0+)
- Swift tools version mismatch (requires swift-tools-version: 6.0+)

## Step 7: Print summary

After successful integration, print:
- What files you changed
- How to build and run the app
- How to connect: `buttonheist list` then `buttonheist session`
- Note that .mcp.json is configured (if it exists) for AI agent access

Be concise. Make the minimal changes needed. Do not refactor, rename, or
"improve" anything else in the project.

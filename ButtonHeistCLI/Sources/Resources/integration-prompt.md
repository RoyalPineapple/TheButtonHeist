You are integrating Button Heist into this iOS project. Your job is to add the
TheInsideJob framework so it auto-starts in DEBUG builds. TheInsideJob runs an
in-app server that lets AI agents (and humans) control the app via CLI or MCP.

No initialization code is needed — the framework auto-starts via an ObjC +load
hook when the binary is linked. You just need to: copy the frameworks, wire them
into the build, add the import, and add Info.plist entries.

**Important:** TheInsideJob requires iOS 17.0+.

## Prebuilt frameworks

The prebuilt frameworks are at:

```
{{FRAMEWORKS_PATH}}
```

The frameworks you need to copy and embed:

**Required (TheInsideJob and its direct dependencies):**
- `TheInsideJob.framework`
- `TheScore.framework`
- `AccessibilitySnapshotParser.framework`
- `AccessibilitySnapshotParser_ObjC.framework`

**Crypto stack (transitive dependencies):**
- `X509.framework`
- `Crypto.framework`
- `SwiftASN1.framework`
- `CCryptoBoringSSL.framework`
- `CCryptoBoringSSLShims.framework`
- `CryptoBoringWrapper.framework`
- `_CertificateInternals.framework`
- `_CryptoExtras.framework`

## Step 1: Identify the app target

Find the main iOS application target — the one that produces a .app bundle.
Skip test targets, app extensions (widgets, intents, share extensions), watch
apps, and framework/library targets.

If there are multiple app targets (e.g. a debug app and a production app),
prefer the debug/development target. If unclear, ask the user which target.

## Step 2: Copy frameworks into the project

Create a `ButtonHeistFrameworks/` directory inside the project and copy all
the frameworks into it:

```bash
mkdir -p ButtonHeistFrameworks
cp -R {{FRAMEWORKS_PATH}}/TheInsideJob.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/TheScore.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/AccessibilitySnapshotParser.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/AccessibilitySnapshotParser_ObjC.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/X509.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/Crypto.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/SwiftASN1.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/CCryptoBoringSSL.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/CCryptoBoringSSLShims.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/CryptoBoringWrapper.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/_CertificateInternals.framework ButtonHeistFrameworks/
cp -R {{FRAMEWORKS_PATH}}/_CryptoExtras.framework ButtonHeistFrameworks/
```

## Step 3: Wire frameworks into the Xcode project

Edit the `project.pbxproj` file to add the frameworks. This is a plain-text
plist file. You need to add several entries. Study the existing framework
references in the file to match the exact style.

**Generate unique 24-character hex IDs** for each new object. Look at existing
IDs in the file and ensure yours don't collide.

For each framework, you need:

### 3a. PBXFileReference (one per framework)

Add in the `/* Begin PBXFileReference section */`:

```
		<FILE_REF_ID> /* TheInsideJob.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = TheInsideJob.framework; path = ButtonHeistFrameworks/TheInsideJob.framework; sourceTree = "<group>"; };
```

### 3b. PBXGroup

Add the file references to an existing group (like "Frameworks") or create a
new "ButtonHeistFrameworks" group and add it to the main group's children.

### 3c. PBXBuildFile (two per framework — link + embed)

Each framework needs two build file entries:

```
		<LINK_BUILD_FILE_ID> /* TheInsideJob.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = <FILE_REF_ID> /* TheInsideJob.framework */; };
		<EMBED_BUILD_FILE_ID> /* TheInsideJob.framework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = <FILE_REF_ID> /* TheInsideJob.framework */; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
```

### 3d. Add to the app target's Frameworks build phase

Find the `PBXFrameworksBuildPhase` for the app target and add:

```
		<LINK_BUILD_FILE_ID> /* TheInsideJob.framework in Frameworks */,
```

### 3e. Add or create an Embed Frameworks build phase

Find or create a `PBXCopyFilesBuildPhase` with `dstSubfolderSpec = 10` (Frameworks)
for the app target. Add all the embed build file IDs:

```
		<EMBED_BUILD_FILE_ID> /* TheInsideJob.framework in Embed Frameworks */,
```

If creating the phase:

```
		<COPY_PHASE_ID> /* Embed Frameworks */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 10;
			files = (
				<EMBED_BUILD_FILE_IDS...>
			);
			name = "Embed Frameworks";
			runOnlyForDeploymentPostprocessing = 0;
		};
```

And add `<COPY_PHASE_ID>` to the target's `buildPhases` array.

### 3f. Add framework search path

Add to the app target's build settings (in the `XCBuildConfiguration` objects
for both Debug and Release):

```
FRAMEWORK_SEARCH_PATHS = "$(SRCROOT)/ButtonHeistFrameworks";
```

If there's already a `FRAMEWORK_SEARCH_PATHS`, append to it. The value is an
array:

```
FRAMEWORK_SEARCH_PATHS = (
    "$(inherited)",
    "$(SRCROOT)/ButtonHeistFrameworks",
);
```

**Repeat steps 3a–3e for ALL 12 frameworks listed above.** Every framework must
have file references, build files, link phase entries, and embed phase entries.

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

Find the app Info.plist (check the target build settings for `INFOPLIST_FILE`)
and add the keys directly.

If there is no Info.plist file and the target uses `GENERATE_INFOPLIST_FILE = YES`,
add the keys via build settings in the pbxproj:

```
INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Button Heist uses the local network for UI automation.";
INFOPLIST_KEY_NSBonjourServices = _buttonheist._tcp;
```

**Important:** If the app already has `NSBonjourServices`, append
`_buttonheist._tcp` to the existing array — do not replace it.

## Step 6: Verify the build

Run a build to confirm everything compiles. Use **absolute paths** in the command:

```bash
xcodebuild -project <absolute/path/to/project.xcodeproj> -scheme <AppScheme> \
  -destination 'generic/platform=iOS Simulator' build
```

Or if there's an `.xcworkspace`:

```bash
xcodebuild -workspace <absolute/path/to/workspace.xcworkspace> -scheme <AppScheme> \
  -destination 'generic/platform=iOS Simulator' build
```

Do not use `swift build` for iOS projects — it does not have access to iOS SDKs.

If the build fails, read the error and fix it. Common issues:
- Missing framework search path
- Framework not embedded (link vs embed)
- Minimum deployment target too low (requires iOS 17.0+)

## Step 7: Print summary

After successful integration, print:
- What files you changed
- How to build and run the app — use **absolute paths** in all commands
- How to connect: `buttonheist list` then `buttonheist session`
- Note that .mcp.json is configured (if it exists) for AI agent access

Be concise. Make the minimal changes needed. Do not refactor, rename, or
"improve" anything else in the project.

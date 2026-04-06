// swiftlint:disable line_length
enum IntegrationPrompt {
    static let text = ##"""
    You are integrating Button Heist into this iOS project. Your job is to add the
    TheInsideJob framework so it auto-starts in DEBUG builds. TheInsideJob runs an
    in-app server that lets AI agents (and humans) control the app via CLI or MCP.

    No initialization code is needed — the framework auto-starts via an ObjC +load
    hook when the binary is linked. You just need to: wire the dependency, add the
    import, and add Info.plist entries.

    **Important:** TheInsideJob requires iOS 17.0+.

    ## Step 1: Identify the build system

    Examine the project root to determine which build system is in use. Check for
    these files, in order:

    | File(s) present | Build system |
    |---|---|
    | `MODULE.bazel` or `WORKSPACE.bazel` + `BUILD.bazel` files + `Package.swift` | **Bazel + SPM** |
    | `MODULE.bazel` or `WORKSPACE.bazel` + `BUILD.bazel` files (no `Package.swift`) | **Bazel (manual)** |
    | `Project.swift` or `Tuist/` directory | **Tuist** |
    | `project.yml` | **XcodeGen** |
    | `Podfile` | **CocoaPods** |
    | `Package.swift` at root (no Bazel files) + `.xcodeproj` | **SPM + Xcode** |
    | Only `.xcodeproj` or `.xcworkspace` | **Xcode project (manual)** |

    Projects may use combinations (e.g. CocoaPods + Xcode, Tuist + SPM). If
    multiple signals are present, follow the primary build system's path and adapt.

    ## Step 2: Identify the app target

    Find the main iOS application target — the one that produces a .app bundle.
    Skip test targets, app extensions (widgets, intents, share extensions), watch
    apps, and framework/library targets.

    If there are multiple app targets (e.g. a debug app and a production app),
    prefer the debug/development target. If unclear, ask the user which target.

    ## Step 3: Add the dependency

    Follow the section matching your detected build system.

    ---

    ### Path A: Swift Package Manager (Xcode-managed)

    For projects using SPM through Xcode's built-in package management.

    **Detection:** `Package.swift` at root or SPM packages visible in
    `.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`.

    1. Add to `Package.swift` dependencies:

    ```swift
    .package(url: "https://github.com/RoyalPineapple/TheButtonHeist", from: "{{VERSION}}"),
    ```

    2. Add the product to the app target's dependencies:

    ```swift
    .product(name: "TheInsideJob", package: "TheButtonHeist"),
    ```

    3. If the project uses Xcode's GUI-managed packages (no root `Package.swift`),
       instruct the user to add it via File > Add Package Dependencies in Xcode.

    **Conflict warning:** If the project already depends on
    `CashApp/AccessibilitySnapshot`, there will be a package name collision with
    TheButtonHeist's fork dependency. The fork must use a distinct package name,
    or the project must switch to the fork.

    ---

    ### Path B: CocoaPods

    **Detection:** `Podfile` at the project root.

    1. Add to the app target in `Podfile`:

    ```ruby
    target 'YourApp' do
      pod 'TheButtonHeist', :git => 'https://github.com/RoyalPineapple/TheButtonHeist.git', :tag => '{{VERSION}}'
    end
    ```

    If TheButtonHeist publishes a podspec to trunk, use the simpler form:

    ```ruby
    pod 'TheButtonHeist', '~> {{VERSION}}'
    ```

    2. For debug-only linking, wrap in a configuration condition:

    ```ruby
    pod 'TheButtonHeist', :git => 'https://github.com/RoyalPineapple/TheButtonHeist.git', :tag => '{{VERSION}}', :configurations => ['Debug']
    ```

    3. Run:

    ```bash
    pod install
    ```

    4. Open the `.xcworkspace` (not `.xcodeproj`) going forward.

    ---

    ### Path C: Tuist

    **Detection:** `Project.swift` or `Tuist/` directory at the project root.

    1. Add the external dependency in `Tuist/Package.swift` (or wherever Tuist
       manages external dependencies):

    ```swift
    .package(url: "https://github.com/RoyalPineapple/TheButtonHeist", from: "{{VERSION}}"),
    ```

    2. In `Project.swift`, add TheInsideJob as a dependency of the app target:

    ```swift
    .target(
        name: "YourApp",
        dependencies: [
            .external(name: "TheInsideJob"),
            // ... existing deps
        ],
    )
    ```

    3. Fetch and resolve:

    ```bash
    tuist install
    ```

    4. Regenerate the project:

    ```bash
    tuist generate
    ```

    ---

    ### Path D: XcodeGen

    **Detection:** `project.yml` at the project root.

    1. Add TheButtonHeist as a Swift Package in `project.yml`:

    ```yaml
    packages:
      TheButtonHeist:
        url: https://github.com/RoyalPineapple/TheButtonHeist
        from: "{{VERSION}}"
    ```

    2. Add the dependency to the app target:

    ```yaml
    targets:
      YourApp:
        dependencies:
          - package: TheButtonHeist
            product: TheInsideJob
    ```

    3. Regenerate the project:

    ```bash
    xcodegen generate
    ```

    ---

    ### Path E: Bazel + SPM (`rules_swift_package_manager`)

    **Detection:** `MODULE.bazel` + `Package.swift` at root, `BUILD.bazel` files
    throughout, possibly a `Packages/` directory with auto-generated wrappers.

    1. Add to `Package.swift` dependencies:

    ```swift
    .package(url: "https://github.com/RoyalPineapple/TheButtonHeist", from: "{{VERSION}}"),
    ```

    2. Resolve dependencies using the project's resolve command. Common patterns:

    ```bash
    # If the project has a custom resolve script:
    sq package resolve
    # Or directly:
    bazel run @swift_package//:resolve
    # Or:
    swift package resolve
    ```

    3. Add to `MODULE.bazel` in the `use_repo(swift_deps, ...)` block, in
       alphabetical order:

    ```starlark
    "swiftpkg_thebuttonheist",
    ```

    4. Generate Bazel wrappers if the project uses them. Look for a generation
       script (e.g. `Scripts/SwiftPM/generate_swiftpm_dependency_wrappers.rb` or
       similar). This creates `Packages/thebuttonheist/BUILD.bazel`.

    5. Wire as a **debug-only** dependency. Bazel projects typically use a
       `select()` mechanism for debug-only deps. Search for where other debug
       frameworks are linked (Reveal, FLEX, FloatingPerformanceMonitor). Look for
       patterns like:

    ```starlark
    deps = some_select(
        debug = [
            "//Packages/ios-reveal-sdk:Reveal-SDK",
        ],
        default = [...],
    )
    ```

    Add TheInsideJob to the debug list:

    ```starlark
    "//Packages/thebuttonheist:TheInsideJob",
    ```

    If there is no debug/release selection mechanism, add it to the regular `deps`.

    **Conflict warning:** Same AccessibilitySnapshot collision risk as Path A.

    **What NOT to do in Bazel projects:**
    - Do NOT edit `.pbxproj` files — Bazel projects generate Xcode projects
    - Do NOT copy/vendor frameworks manually — use the SPM integration
    - Do NOT modify `BUILD.bazel` dependency lists by hand for SPM packages — use
      the project's wrapper generation tooling

    ---

    ### Path F: Bazel (manual, no SPM)

    **Detection:** `MODULE.bazel` or `WORKSPACE.bazel` + `BUILD.bazel` files, but
    no `Package.swift` for dependency management.

    This requires vendoring the prebuilt frameworks.

    1. Copy the prebuilt frameworks into the project:

    ```bash
    mkdir -p Vendor/ButtonHeist
    cp -R {{FRAMEWORKS_PATH}}/*.framework Vendor/ButtonHeist/
    ```

    2. Create a `Vendor/ButtonHeist/BUILD.bazel`:

    ```starlark
    load(
        "@build_bazel_rules_apple//apple:apple.bzl",
        "apple_dynamic_framework_import",
    )

    FRAMEWORKS = [
        "TheInsideJob",
        "TheScore",
        "AccessibilitySnapshotParser",
        "AccessibilitySnapshotParser_ObjC",
        "X509",
        "Crypto",
        "SwiftASN1",
        "CCryptoBoringSSL",
        "CCryptoBoringSSLShims",
        "CryptoBoringWrapper",
        "_CertificateInternals",
        "_CryptoExtras",
    ]

    [apple_dynamic_framework_import(
        name = fw + "-import",
        framework_imports = glob([fw + ".framework/**"]),
        visibility = ["//visibility:private"],
    ) for fw in FRAMEWORKS]

    objc_library(
        name = "TheInsideJob",
        deps = [fw + "-import" for fw in FRAMEWORKS],
        visibility = ["//visibility:public"],
    )
    ```

    3. Add `//Vendor/ButtonHeist:TheInsideJob` to the app target's `deps`.

    4. If `bitcode_strip` fails during the build, pre-strip the frameworks:

    ```bash
    for fw in Vendor/ButtonHeist/*.framework; do
      name=$(basename "$fw" .framework)
      xcrun bitcode_strip "$fw/$name" -r -o "$fw/$name.tmp" 2>/dev/null && mv "$fw/$name.tmp" "$fw/$name"
    done
    ```

    ---

    ### Path G: Buck / Buck2

    **Detection:** `BUCK` or `TARGETS` files, `.buckconfig` at root.

    1. Add the prebuilt frameworks (same as Path F step 1).

    2. Create a `BUCK` file in the vendor directory:

    ```python
    prebuilt_apple_framework(
        name = "TheInsideJob",
        framework = "TheInsideJob.framework",
        preferred_linkage = "shared",
        visibility = ["PUBLIC"],
    )
    ```

    Repeat for each framework, or create a wrapper rule that depends on all of them.

    3. Add the dependency to the app target's `deps`.

    ---

    ### Path H: Xcode project (manual)

    For projects with only `.xcodeproj` / `.xcworkspace` and no package manager.

    #### Prebuilt frameworks

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

    #### Copy frameworks into the project

    ```bash
    mkdir -p ButtonHeistFrameworks
    cp -R {{FRAMEWORKS_PATH}}/*.framework ButtonHeistFrameworks/
    ```

    #### Wire frameworks into the Xcode project

    Edit the `project.pbxproj` file. Study existing framework references to match
    the exact style. **Generate unique 24-character hex IDs** for each new object.

    For each of the 12 frameworks, add:

    1. **PBXFileReference** in `/* Begin PBXFileReference section */`:

    ```
    <ID> /* Foo.framework */ = {isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = Foo.framework; path = ButtonHeistFrameworks/Foo.framework; sourceTree = "<group>"; };
    ```

    2. **PBXGroup** — add file references to an existing "Frameworks" group or
       create a new "ButtonHeistFrameworks" group.

    3. **PBXBuildFile** — two per framework (link + embed):

    ```
    <LINK_ID> /* Foo.framework in Frameworks */ = {isa = PBXBuildFile; fileRef = <ID>; };
    <EMBED_ID> /* Foo.framework in Embed Frameworks */ = {isa = PBXBuildFile; fileRef = <ID>; settings = {ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }; };
    ```

    4. **PBXFrameworksBuildPhase** — add the link build file ID.

    5. **PBXCopyFilesBuildPhase** (`dstSubfolderSpec = 10`) — add the embed build
       file ID. Create this phase if it doesn't exist.

    6. **Framework search path** — add to `FRAMEWORK_SEARCH_PATHS` in both Debug
       and Release build configurations:

    ```
    FRAMEWORK_SEARCH_PATHS = (
        "$(inherited)",
        "$(SRCROOT)/ButtonHeistFrameworks",
    );
    ```

    ---

    ## Step 4: Add the import

    Find the app entry point (`@main struct ... App` or `@main class AppDelegate`).
    Add the import wrapped in a DEBUG guard:

    ```swift
    #if DEBUG
    import TheInsideJob
    #endif
    ```

    Place it with the other imports at the top of the file.

    ## Step 5: Info.plist entries

    TheInsideJob uses Bonjour for device discovery. Add these keys to the app's
    Info.plist:

    ```xml
    <key>NSLocalNetworkUsageDescription</key>
    <string>Button Heist uses the local network for UI automation.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_buttonheist._tcp</string>
    </array>
    ```

    **Important:** If the app already has `NSBonjourServices`, **append**
    `_buttonheist._tcp` to the existing array — do not replace it. If the app
    already has `NSLocalNetworkUsageDescription`, leave the existing string as-is.

    If there is no Info.plist and the target uses `GENERATE_INFOPLIST_FILE = YES`,
    add the keys via build settings:

    ```
    INFOPLIST_KEY_NSLocalNetworkUsageDescription = "Button Heist uses the local network for UI automation.";
    INFOPLIST_KEY_NSBonjourServices = _buttonheist._tcp;
    ```

    ## Step 6: Verify the build

    Build the project using whatever build system was detected:

    ```bash
    # SPM / Xcode
    xcodebuild -project <path.xcodeproj> -scheme <Scheme> -destination 'generic/platform=iOS Simulator' build

    # CocoaPods
    xcodebuild -workspace <path.xcworkspace> -scheme <Scheme> -destination 'generic/platform=iOS Simulator' build

    # Tuist
    tuist build

    # Bazel
    bazel build //<target> --swiftcopt=-Xfrontend --swiftcopt=-suppress-warnings

    # Buck2
    buck2 build //<target>
    ```

    Do not use `swift build` for iOS projects — it does not have access to iOS SDKs.

    If the build fails, read the error and fix it. Common issues:
    - Missing framework search path (Xcode manual path)
    - Framework not embedded — link vs embed (Xcode manual path)
    - Minimum deployment target too low (requires iOS 17.0+)
    - AccessibilitySnapshot package name collision (SPM-based paths)
    - `bitcode_strip` failures on vendored frameworks (Bazel manual path)

    ## Step 7: Print summary

    After successful integration, print:
    - Which build system was detected
    - What files were changed
    - How to build and run the app
    - How to connect: `buttonheist list` then `buttonheist session`
    - Note that .mcp.json should be configured for AI agent access

    Be concise. Make the minimal changes needed. Do not refactor, rename, or
    "improve" anything else in the project.
    """##
}
// swiftlint:enable line_length

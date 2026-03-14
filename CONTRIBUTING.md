# Contributing to ButtonHeist

## Development Setup

### Prerequisites

- Xcode with Swift 6 package support
- [Tuist](https://tuist.io)
- iOS 17+ device or simulator
- macOS 14+

### Getting Started

1. Clone the repository.
2. Initialize submodules: `git submodule update --init --recursive`
3. Generate the workspace: `tuist generate`
4. Open `ButtonHeist.xcworkspace`

## Project Structure

| Directory | Description |
|-----------|-------------|
| `ButtonHeist/Sources/TheScore/` | Shared protocol types and constants |
| `ButtonHeist/Sources/TheInsideJob/` | Embedded iOS server runtime |
| `ButtonHeist/Sources/ThePlant/` | ObjC auto-start loader for `TheInsideJob` |
| `ButtonHeist/Sources/TheButtonHeist/` | macOS client framework (`TheMastermind`, `TheFence`, `TheHandoff`) |
| `ButtonHeistCLI/` | Swift package for the CLI executable |
| `ButtonHeistMCP/` | Swift package for the MCP server executable |
| `TestApp/` | Sample SwiftUI and UIKit test applications |
| `AccessibilitySnapshot/` | Hierarchy parsing submodule |
| `docs/` | Architecture, protocol, and API docs |

## Code Style

### Swift

- Use Swift's standard naming conventions
- Prefer actor isolation or `@MainActor` where UI work requires it
- Use explicit access control (`public`, `internal`, `private`)
- Keep files focused on a single responsibility

### Formatting

- 4-space indentation
- Opening braces on the same line
- No trailing whitespace

## Making Changes

### Branch Naming

Use clear, descriptive branch names tied to the change you are making.

### Commit Messages

- Use present tense (`Add feature`, not `Added feature`)
- Keep the first line under 72 characters
- Reference issues when applicable

### Pull Requests

1. Create a branch from `main`
2. Make your changes
3. Test the affected surfaces
4. Submit a pull request with a clear description and any relevant issue references

## Testing

### Build Checks

```bash
git submodule update --init --recursive
tuist generate

xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScore build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJob \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

cd ButtonHeistCLI && swift build -c release
cd ../ButtonHeistMCP && swift build -c release
```

### Manual Checks

1. Run `AccessibilityTestApp` or `UIKitTestApp`
2. Verify `buttonheist list` discovers the app
3. Verify `get_interface`, `activate`, and `type` still work end-to-end

## Module Guidelines

### TheScore

- Keep types `Codable` and cross-platform compatible
- Avoid UIKit/AppKit imports
- Treat protocol changes as compatibility-sensitive

### TheInsideJob

- iOS-only; UIKit is allowed
- Keep UI work on the main actor
- Be careful with private API usage and transport/auth changes

### ButtonHeist

- Preserve the separation between `TheMastermind`, `TheFence`, and `TheHandoff`
- Keep discovery/connection behavior consistent between CLI and MCP consumers
- Prefer updating shared command handling in `TheFence` rather than duplicating logic in clients

## Questions

Open an issue for questions or discussion.

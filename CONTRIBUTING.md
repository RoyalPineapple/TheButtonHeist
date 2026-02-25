# Contributing to ButtonHeist

Thank you for your interest in contributing to ButtonHeist!

## Development Setup

### Prerequisites

- Xcode 15+
- [Tuist](https://tuist.io) for project generation
- iOS 17+ device or simulator
- macOS 14+

### Getting Started

1. Clone the repository
2. Install Tuist: `curl -Ls https://install.tuist.io | bash`
3. Generate the Xcode project: `tuist generate`
4. Open `ButtonHeist.xcworkspace`

## Project Structure

| Directory | Description |
|-----------|-------------|
| `ButtonHeist/Sources/TheGoods/` | Shared types and protocol messages |
| `ButtonHeist/Sources/InsideJob/` | iOS server framework (server, touch injection, tap visualization) |
| `ButtonHeist/Sources/InsideJobLoader/` | ObjC auto-start via +load |
| `ButtonHeist/Sources/Wheelman/` | Cross-platform networking (TCP server/client, Bonjour discovery) |
| `ButtonHeistCLI/` | Command-line tool (list, watch, action, touch, type, screenshot, session) |
| `ButtonHeistMCP/` | MCP server for AI agent integration |
| `TestApp/` | Sample SwiftUI and UIKit iOS applications |
| `AccessibilitySnapshot/` | Hierarchy parsing submodule |

## Code Style

### Swift

- Use Swift's standard naming conventions
- Prefer `@MainActor` for UI-related code
- Use explicit access control (`public`, `internal`, `private`)
- Keep files focused on a single responsibility

### Formatting

- 4-space indentation
- Opening braces on same line
- No trailing whitespace

## Making Changes

### Branch Naming

Use descriptive branch names:
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation changes

### Commit Messages

Write clear, concise commit messages:
- Use present tense ("Add feature" not "Added feature")
- Keep the first line under 72 characters
- Reference issues when applicable

### Pull Requests

1. Create a branch from `main`
2. Make your changes
3. Test on both iOS device/simulator and macOS
4. Submit a pull request with:
   - Clear description of changes
   - Any relevant issue references
   - Screenshots for UI changes

## Testing

### Building All Targets

```bash
# Generate project
tuist generate

# Build frameworks
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheGoods build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme InsideJob \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcodebuild -workspace ButtonHeist.xcworkspace -scheme Wheelman build

# Build apps
xcodebuild -workspace ButtonHeist.xcworkspace -scheme AccessibilityTestApp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# CLI
cd ButtonHeistCLI && swift build
```

### Manual Testing

1. Run TestApp on iOS simulator
2. Verify device discovery works via CLI
3. Verify hierarchy updates in real-time

## Module Guidelines

### TheGoods

- Keep types `Codable` and cross-platform compatible
- Avoid UIKit/AppKit imports
- Document all public types

### InsideJob

- iOS-only, UIKit is allowed
- Run all operations on `@MainActor`
- Uses SimpleSocketServer (from Wheelman) for TCP server

### Wheelman

- Cross-platform (iOS + macOS)
- TCP server (SimpleSocketServer), client (DeviceConnection), and Bonjour discovery (DeviceDiscovery)
- Uses Network framework (NWListener, NWConnection, NWBrowser)

## Questions?

Open an issue for questions or discussion.

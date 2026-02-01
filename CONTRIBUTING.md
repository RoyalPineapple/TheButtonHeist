# Contributing to Accra

Thank you for your interest in contributing to Accra!

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
4. Open `Accra.xcworkspace`

## Project Structure

| Directory | Description |
|-----------|-------------|
| `AccraCore/Sources/AccraCore/` | Shared types and protocol messages |
| `AccraCore/Sources/AccraHost/` | iOS server framework |
| `AccraCore/Sources/AccraClient/` | macOS client library |
| `AccraInspector/Sources/` | macOS GUI application |
| `AccraCLI/` | Command-line tool (SPM package) |
| `TestApp/` | Sample iOS applications |

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
xcodebuild -workspace Accra.xcworkspace -scheme AccraCore build
xcodebuild -workspace Accra.xcworkspace -scheme AccraHost \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
xcodebuild -workspace Accra.xcworkspace -scheme AccraClient build

# Build apps
xcodebuild -workspace Accra.xcworkspace -scheme AccraInspector build
xcodebuild -workspace Accra.xcworkspace -scheme TestApp \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build

# CLI
cd AccraCLI && swift build
```

### Manual Testing

1. Run TestApp on iOS simulator
2. Run AccraInspector on macOS
3. Verify device discovery works
4. Verify hierarchy updates in real-time

## Module Guidelines

### AccraCore

- Keep types `Codable` and cross-platform compatible
- Avoid UIKit/AppKit imports
- Document all public types

### AccraHost

- iOS-only, UIKit is allowed
- Run all operations on `@MainActor`
- Use Network framework for WebSocket

### AccraClient

- macOS-only
- Provide both `@Published` properties and callbacks
- Handle connection lifecycle gracefully

### AccraInspector

- Follow the design system in `docs/DESIGN-SYSTEM.md`
- Use semantic colors and typography tokens
- Keep views small and composable

## Questions?

Open an issue for questions or discussion.

# Changelog

All notable changes to Accra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Initial public release
- AccraCore: Cross-platform shared types and wire protocol
- AccraHost: iOS server framework with Bonjour discovery
- AccraClient: macOS client library with SwiftUI support
- AccraInspector: macOS GUI application for visual inspection
- AccraCLI: Unix-standard command-line tool
- TestApp: Sample SwiftUI and UIKit applications
- Documentation suite

### Technical Details
- Wire protocol version: 1.0
- Bonjour service type: `_a11ybridge._tcp`
- Minimum iOS: 17.0
- Minimum macOS: 14.0

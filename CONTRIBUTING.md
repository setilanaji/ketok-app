# Contributing to Ketok

Thanks for your interest in contributing!

## Getting Started

1. Fork the repo and clone it locally
2. Open `Ketok.xcodeproj` in Xcode 15+
3. Press `Cmd+R` to build and run

No additional dependencies are required to build the app itself. Android SDK, ADB, and FVM are only needed by the projects you configure inside the app.

## Reporting Issues

- Search existing issues before opening a new one
- Include macOS version, Xcode version, and steps to reproduce
- Attach the relevant build log if the issue is build-related

## Pull Requests

- Keep PRs focused — one fix or feature per PR
- Match the existing code style (Swift/SwiftUI conventions)
- Test your changes by running the app (`make run`)
- If you're adding a new service or model, follow the patterns in `Ketok/Services/` and `Ketok/Models/`

## Project Structure

```
Ketok/
├── KetokApp.swift          # App entry point, service wiring
├── Models/                 # Data models (AndroidProject, BuildStatus, etc.)
├── Services/               # Business logic (build, ADB, notifications, etc.)
├── Views/                  # SwiftUI views (MenuBarView, SettingsView)
└── Assets.xcassets         # App icons and brand colors
```

## Build Commands

```bash
make build      # Debug build
make run        # Build and launch
make clean      # Remove build artifacts
```

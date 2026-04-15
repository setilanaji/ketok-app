# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ketok is a macOS menu bar app (Swift/SwiftUI) for building Android APK/AAB files. It supports both native Gradle and Flutter (with FVM) projects — no Android Studio needed. The app lives in the menu bar as a paperplane icon.

- **Platform**: macOS 14.0+ (Sonoma)
- **Language**: Swift 5.9
- **UI Framework**: SwiftUI
- **Build System**: Xcode project (`Ketok.xcodeproj`), no SPM dependencies
- **Bundle prefix**: `com.ketok`

## Build Commands

```bash
make build          # Debug build (xcodebuild)
make release        # Release build
make run            # Build and launch the app
make dmg            # Build + create DMG installer (via Scripts/build_dmg.sh)
make dmg-notarize   # Build + DMG + Apple notarization
make clean          # Remove build artifacts
```

You can also open `Ketok.xcodeproj` in Xcode and press Cmd+R.

## Architecture

### App Entry Point

`KetokApp.swift` — `@main` struct using `MenuBarExtra` scene. All services are created as `@StateObject` here and injected into views via `.environmentObject()`. Services are wired together in `onAppear` (e.g., build service gets references to signing store, ADB service, stats store).

### Key Layers

**Models** (`Ketok/Models/`):
- `AndroidProject` — core model representing a configured project (native or Flutter). Contains path resolution logic for APK/AAB output paths, Gradle task names, Flutter build commands, and output file renaming.
- `BuildStatus` — tracks state of an in-progress or completed build
- `BuildProfile`, `BuildTemplate`, `FavoriteBuild`, `SigningConfig` — user configuration models

**Services** (`Ketok/Services/`):
- `GradleBuildService` — central build orchestrator. Runs Gradle/Flutter builds via `Process` (shell execution). Supports build queue, parallel builds, signing injection, and post-build actions.
- `ProjectStore` — persists project list
- `ProjectEnvironmentDetector` — auto-detects SDK paths, JAVA_HOME, FVM, project type, variants, build types from the filesystem
- `FlutterPreBuildService` — detects and runs pre-build steps (build_runner, flutter_gen, envied code generation, version drift fixes)
- `ADBService` — device management and APK installation
- `OTADistributionService` — local WiFi sharing via QR code
- `NotificationService` — macOS notifications with actionable buttons
- `BuildHealthService` — health scores and failure pattern recognition
- `GradleCompatibilityService` — AGP/Gradle/JDK/Kotlin compatibility validation

**Views** (`Ketok/Views/`):
- `MenuBarView` — main UI shown in the menu bar popover
- `SettingsView` — settings window (projects, devices, signing, etc.)

**Brand** (`Brand.swift`):
- Design tokens (colors, gradients) and reusable SwiftUI view modifiers (`brandedHeader()`, `brandedCard()`, `brandedCapsule()`, `brandedProgress()`). Colors are defined in asset catalogs with dark mode variants.

### Build Execution Flow

1. User selects project/variant/buildType in `MenuBarView`
2. `GradleBuildService.enqueueBuild()` adds to queue
3. Queue processor calls `startBuild()` which:
   - Re-detects version info via `ProjectEnvironmentDetector`
   - For Flutter: runs `pub get`, then `FlutterPreBuildService` for code generation
   - For Flutter with FVM: auto-resolves commands through `fvm flutter`/`fvm dart`
   - Runs the actual Gradle/Flutter build via `/bin/bash` Process
   - Handles signing config injection for release builds
   - On success: renames output, copies to output folder, runs post-build actions
4. `NotificationService` sends macOS notifications with action buttons

### UserDefaults Keys

Settings use `com.buildpilot.*` prefix (legacy name before rebrand to Ketok).

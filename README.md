# Ketok

A macOS menu bar app for building Android APK/AAB files. Supports Flutter (with FVM) and native Gradle projects — no Android Studio needed.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue) ![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange) ![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple) ![v0.1.0](https://img.shields.io/badge/version-0.1.0-green)

## Features

- **One-click builds** — Select variant, build type, and go. APK & AAB output.
- **Flutter + FVM support** — Auto-detects FVM-pinned SDK and runs `fvm flutter`/`fvm dart` commands transparently.
- **Smart pre-build** — Runs `build_runner`, `gen-l10n`, `flutter_gen`, and envied code generation automatically when needed.
- **Multi-project** — Manages multiple Android projects. Auto-detects variants, build types, and modules from Gradle config.
- **Build intelligence** — Health scores, failure pattern recognition (OOM, dependency conflicts, Kotlin errors, etc.), and Gradle compatibility validation (AGP/Gradle/JDK/Kotlin matrix).
- **Pre-build diagnostics** — Scans for issues (missing pubspec.lock, stale dependencies, missing .env vars, SDK problems) and auto-fixes them.
- **Device install & OTA** — Install APKs on all connected devices in parallel, or share builds over local WiFi via QR code.
- **Version management** — Semantic version bumping with conventional commit analysis and git tagging.
- **Notifications** — macOS native notifications with actionable buttons, plus Slack & Discord webhook integration.
- **Build profiles & templates** — Save reusable build configurations. Pre-configured pipelines (Quick Debug, Release Bundle, QA Distribution).
- **Dependency scanner** — Detect outdated, vulnerable, and conflicting packages.
- **Global hotkey** — `Cmd+Shift+B` to trigger a quick build from anywhere.

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (to build from source)
- Android SDK with `gradlew` in your project roots
- ADB (optional — for device installation)
- FVM (optional — auto-detected if present)

## Getting Started

### Build from Source

```bash
git clone https://github.com/setilanaji/ketok.git
cd Ketok
open Ketok.xcodeproj
```

Press `Cmd+R` in Xcode to build and run. The app appears as a paperplane icon in your menu bar.

### Create DMG Installer

```bash
./Scripts/build_dmg.sh
```

This archives the app, packages it into a DMG with drag-to-Applications layout, and outputs `build/Ketok.dmg`. See `make help` for more commands.

### Add Your Projects

1. Click the paperplane icon in the menu bar
2. Click **Settings** in the footer
3. In the **Projects** tab, click **+** to add a project
4. Browse to your Android project root (where `gradlew` lives)
5. The app auto-detects variants, build types, and module paths

## Architecture

```
Ketok/
├── KetokApp.swift          # App entry point, @StateObject wiring, service initialization
├── Models/                 # Data models — AndroidProject, BuildStatus, SigningConfig, etc.
├── Services/               # Business logic
│   ├── GradleBuildService  # Core build orchestrator (queue, process execution, signing)
│   ├── ProjectStore        # Project list persistence
│   ├── ProjectEnvironmentDetector  # Auto-detects SDK paths, variants, build types, FVM
│   ├── FlutterPreBuildService      # Code generation (build_runner, flutter_gen, envied)
│   ├── ADBService          # Device management and APK installation
│   ├── OTADistributionService      # Local WiFi sharing via HTTP + QR code
│   ├── NotificationService # macOS notifications with actionable buttons
│   └── ...                 # Build health, compatibility checks, Firebase distribution
├── Views/
│   ├── MenuBarView         # Main popover UI
│   └── SettingsView        # Settings window (projects, signing, devices, etc.)
└── Assets.xcassets         # App icon and brand color palette
```

## Troubleshooting

**Gradle not found**
Make sure your project root contains a `gradlew` file. Ketok uses the Gradle wrapper bundled with your project, not a global Gradle installation.

**FVM not detected**
Ketok looks for FVM in common install paths (`~/.fvm`, `~/fvm`). If you installed FVM elsewhere, check that `fvm` is on your `$PATH`.

**Build fails with "SDK not found"**
Open Settings → Projects, select your project, and verify the detected Android SDK path. You can override it manually if auto-detection picks the wrong one.

**ADB devices not showing**
Make sure ADB is installed and USB debugging is enabled on the device. Run `adb devices` in Terminal to verify connectivity outside of Ketok.

**Signing config asks for password every launch**
Keychain access needs to be approved once. When macOS shows the Keychain prompt, click "Always Allow" to persist access.

## Known Limitations

- Ketok runs **unsandboxed** — required to execute Gradle builds and access ADB. macOS may prompt for Full Disk Access on first use.
- Keychain items from the legacy "BuildPilot" version of this app are not automatically migrated — signing passwords will need to be re-entered once.
- Firebase App Distribution requires the Firebase CLI to be installed separately.

## Build Commands

```bash
make help           # Show all available commands
make build          # Debug build
make release        # Release build
make dmg            # Build + create DMG installer
make dmg-notarize   # Build + DMG + Apple notarization
make clean          # Remove build artifacts
make run            # Build and launch the app
```

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT — see [LICENSE](LICENSE) for details.

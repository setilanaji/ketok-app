import SwiftUI

@main
struct KetokApp: App {
    @StateObject private var projectStore = ProjectStore()
    @StateObject private var buildService = GradleBuildService()
    @StateObject private var gitService = GitService()
    @StateObject private var adbService = ADBService()
    @StateObject private var favoriteStore = FavoriteStore()
    @StateObject private var signingStore = SigningConfigStore()
    @StateObject private var buildStatsStore = BuildStatsStore()
    @StateObject private var profileStore = BuildProfileStore()
    @StateObject private var templateStore = BuildTemplateStore()
    @StateObject private var qrService = QRCodeService.shared
    @StateObject private var dragDropService = DragDropInstallService()
    @StateObject private var dependencyScanner = DependencyScannerService()
    @ObservedObject private var soundService = BuildSoundService.shared
    @ObservedObject private var firebaseService = FirebaseDistributionService.shared
    @ObservedObject private var otaService = OTADistributionService.shared

    init() {
        // Migrate legacy UserDefaults keys from com.buildpilot to com.ketok
        KetokApp.migrateUserDefaultsIfNeeded()

        // Initialize notification permissions and register categories
        _ = NotificationService.shared

        // Wire up global hotkey
        HotkeyService.shared.onBuildTriggered = { [self] in
            triggerQuickBuild()
        }
    }

    /// Menu bar icon based on build state
    private var menuBarIcon: String {
        guard let build = buildService.currentBuild else { return "paperplane" }
        switch build.state {
        case .building: return "paperplane.fill"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .idle: return "paperplane"
        }
    }

    var body: some Scene {
        // Menu Bar icon — the main entry point
        MenuBarExtra {
            MenuBarView()
                .environmentObject(projectStore)
                .environmentObject(buildService)
                .environmentObject(gitService)
                .environmentObject(adbService)
                .environmentObject(favoriteStore)
                .environmentObject(signingStore)
                .environmentObject(buildStatsStore)
                .environmentObject(profileStore)
                .environmentObject(templateStore)
                .environmentObject(qrService)
                .environmentObject(dragDropService)
                .environmentObject(dependencyScanner)
                .onAppear {
                    // Wire signing store into build service
                    buildService.signingConfigStore = signingStore
                    // Wire build stats store
                    buildService.buildStatsStore = buildStatsStore
                    // Wire ADB service for post-build actions
                    buildService.adbService = adbService
                    // Wire project version update callback
                    buildService.onProjectUpdated = { updatedProject in
                        projectStore.updateProject(updatedProject)
                    }

                    // Wire notification action callbacks
                    setupNotificationActions()
                }
        } label: {
            Label("Ketok", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView()
                .environmentObject(projectStore)
                .environmentObject(adbService)
                .environmentObject(signingStore)
                .environmentObject(favoriteStore)
                .environmentObject(buildStatsStore)
                .environmentObject(buildService)
                .environmentObject(profileStore)
                .environmentObject(templateStore)
        }
    }

    /// Set up notification action handlers
    private func setupNotificationActions() {
        let notificationService = NotificationService.shared

        notificationService.onInstallRequested = { [self] apkPath in
            guard let device = adbService.devices.first(where: { $0.isOnline }) else { return }
            adbService.installAPK(apkPath: apkPath, device: device) { _, _ in }
        }

        notificationService.onRevealRequested = { filePath in
            NSWorkspace.shared.selectFile(filePath, inFileViewerRootedAtPath: "")
        }

        notificationService.onRetryBuildRequested = { [self] in
            // Retry the last build configuration
            if let lastBuild = buildService.buildHistory.first {
                buildService.enqueueBuild(
                    project: lastBuild.project,
                    variant: lastBuild.variant,
                    buildType: lastBuild.buildType,
                    outputFormat: lastBuild.outputFormat
                )
            }
        }

        notificationService.onViewLogRequested = {
            // The menu bar view will handle showing the log panel
        }

        notificationService.onStartOTARequested = { [self] filePath in
            if let lastBuild = buildService.buildHistory.first {
                otaService.startServing(
                    filePath: filePath,
                    appName: lastBuild.project.name,
                    variant: lastBuild.variant,
                    buildType: lastBuild.buildType,
                    version: lastBuild.project.detectedVersionName,
                    versionCode: lastBuild.project.detectedVersionCode,
                    outputFormat: lastBuild.outputFormat
                )
            }
        }
    }

    /// Migrates UserDefaults keys from the legacy com.buildpilot prefix to com.ketok
    private static func migrateUserDefaultsIfNeeded() {
        let migrationKey = "com.ketok.migrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let legacyKeys = [
            "com.buildpilot.buildtemplates",
            "com.buildpilot.favorites",
            "com.buildpilot.buildprofiles",
            "com.buildpilot.parallelBuilds",
            "com.buildpilot.maxParallelBuilds",
            "com.buildpilot.buildstats",
            "com.buildpilot.soundEnabled",
            "com.buildpilot.successSound",
            "com.buildpilot.failSound",
            "com.buildpilot.firebaseCLIPath",
            "com.buildpilot.firebaseConfigs",
            "com.buildpilot.projects",
            "com.buildpilot.hotkey.enabled",
            "com.buildpilot.recentMappings",
            "com.buildpilot.webhooks",
        ]

        for key in legacyKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                let newKey = key.replacingOccurrences(of: "com.buildpilot.", with: "com.ketok.")
                UserDefaults.standard.set(value, forKey: newKey)
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    /// Triggered by global hotkey (Cmd+Shift+B) — builds first favorite or first project
    private func triggerQuickBuild() {
        // Try first favorite
        if let fav = favoriteStore.favorites.first,
           let project = projectStore.projects.first(where: { $0.id == fav.projectId }) {
            DispatchQueue.main.async {
                buildService.enqueueBuild(project: project, variant: fav.variant, buildType: fav.buildType)
            }
            return
        }

        // Fall back to first project with defaults
        if let project = projectStore.projects.first {
            let variant = project.buildVariants.first ?? "dev"
            let buildType = project.buildTypes.first ?? "debug"
            DispatchQueue.main.async {
                buildService.enqueueBuild(project: project, variant: variant, buildType: buildType)
            }
        }
    }
}

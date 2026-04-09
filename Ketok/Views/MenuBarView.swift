import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var buildService: GradleBuildService
    @EnvironmentObject var gitService: GitService
    @EnvironmentObject var adbService: ADBService
    @EnvironmentObject var favoriteStore: FavoriteStore
    @EnvironmentObject var profileStore: BuildProfileStore
    @EnvironmentObject var qrService: QRCodeService
    @EnvironmentObject var templateStore: BuildTemplateStore
    @EnvironmentObject var dragDropService: DragDropInstallService
    @EnvironmentObject var dependencyScanner: DependencyScannerService
    @ObservedObject var firebaseService = FirebaseDistributionService.shared
    @ObservedObject var otaService = OTADistributionService.shared
    @Environment(\.openSettings) private var openSettings
    @State var selectedProject: AndroidProject?
    @State var selectedVariant: String = "dev"
    @State var selectedBuildType: String = "debug"
    @State var showLog = false
    @State var showDevices = false
    @State var showLogcat = false
    @State var logcatFilter = ""
    @State var logcatDevice = ""
    @State var showQRCode = false
    @State var showChangelog = false
    @State var showAPKAnalysis = false
    @State var showFullHistory = false
    @State var historySearchText = ""
    @State var historyFilter: HistoryFilter = .all

    enum HistoryFilter: String, CaseIterable {
        case all = "All"
        case success = "Passed"
        case failed = "Failed"
    }
    @State var showWirelessPairing = false
    @State var wirelessHost = ""
    @State var wirelessPairPort = ""
    @State var wirelessConnectPort = ""
    @State var wirelessPairingCode = ""
    @State var showFirebaseUpload = false
    @State var firebaseReleaseNotes = ""
    @State var apkAnalysis: APKAnalysis?
    @State var changelogEntries: [GitCommitEntry] = []
    @State var selectedOutputFormat: BuildOutputFormat = .apk
    @State var showMappingViewer = false
    @StateObject var mappingService = MappingViewerService()
    @State var mappingSearchQuery = ""
    @State var showDependencyScanner = false
    @State var showOTAServer = false
    @State var showBuildTemplates = false
    @State var showEnvironmentSnapshot = false
    @State var lastEnvironmentSnapshot: BuildEnvironmentSnapshot?
    @State var showGitInfo = false

    // Emulator Quick Launch
    @State var showEmulatorLauncher = false
    @StateObject var emulatorService = EmulatorService()

    // Build Cache Analytics
    @State var showCacheAnalytics = false
    @StateObject var cacheAnalyticsService = BuildCacheAnalyticsService()

    // Crash Log Symbolication
    @State var showCrashSymbolicator = false
    @StateObject var crashSymbolicator = CrashLogSymbolicator()
    @State var crashTraceInput = ""

    // Feedback
    @State var showFeedback = false
    @StateObject var feedbackService = FeedbackService()
    @State var feedbackType: FeedbackType = .generalFeedback
    @State var feedbackRating: FeedbackRating = .good
    @State var feedbackMessage = ""
    @State var feedbackIncludeSystemInfo = true
    @State var feedbackSent = false

    // Version Bumper
    @State var showVersionBumper = false
    @StateObject var versionBumperService = VersionBumperService()
    @State var selectedBumpType: VersionBumpType = .patch
    @State var customVersionInput = ""
    @State var customCodeInput = ""
    @State var autoIncrementCode = true
    @State var createGitTag = false

    // Release Notes
    @State var showReleaseNotes = false
    @StateObject var releaseNotesService = ReleaseNotesService()
    @State var releaseNotesFormat: ReleaseNotesFormat = .markdown
    @State var releaseNotesIncludeAuthors = false
    @State var releaseNotesIncludeEmoji = true
    @State var releaseNotesGroupByCategory = true
    @State var releaseNotesCopied = false

    // Build Matrix
    @State var showBuildMatrix = false
    @StateObject var buildMatrixService = BuildMatrixService()

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if showFullHistory {
                // Full build history view
                AdaptiveScrollView(maxHeight: 440) {
                    VStack(spacing: 8) {
                        fullHistorySection

                        // QR Code panel (can be triggered from history rows)
                        if showQRCode {
                            qrCodeSection
                        }

                        // APK Analysis panel
                        if showAPKAnalysis, let analysis = apkAnalysis {
                            apkAnalysisSection(analysis)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .transition(.opacity)
            } else if !buildService.activeBuilds.isEmpty {
                VStack(spacing: 4) {
                    ForEach(buildService.activeBuilds) { build in
                        activeBuildCard(build: build)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                                removal: .opacity
                            ))
                    }
                }
            } else {
                AdaptiveScrollView(maxHeight: 440) {
                    VStack(spacing: 8) {
                        // Favorites
                        if !favoriteStore.favorites.isEmpty {
                            favoritesSection
                        }

                        // Build profiles
                        if !profileStore.profiles.isEmpty {
                            profilesSection
                        }

                        // Projects
                        projectListView

                        // Connected devices
                        if !adbService.devices.isEmpty {
                            deviceSection
                        }

                        // Build queue
                        if !buildService.buildQueue.isEmpty {
                            buildQueueSection
                        }

                        // Recent builds
                        if !buildService.buildHistory.isEmpty {
                            recentBuildsSection
                        }

                        // QR Code panel
                        if showQRCode {
                            qrCodeSection
                        }

                        // APK Analysis panel
                        if showAPKAnalysis, let analysis = apkAnalysis {
                            apkAnalysisSection(analysis)
                        }

                        // Mapping viewer panel
                        if showMappingViewer {
                            mappingViewerSection
                        }

                        // Changelog panel
                        if showChangelog && !changelogEntries.isEmpty {
                            changelogSection
                        }

                        // Firebase upload panel
                        if showFirebaseUpload {
                            firebaseUploadSection
                        }

                        // Logcat viewer
                        if showLogcat {
                            logcatSection
                        }

                        // Dependency scanner panel
                        if showDependencyScanner {
                            dependencyScannerSection
                        }

                        // OTA distribution panel
                        if showOTAServer {
                            otaDistributionSection
                        }

                        // Build templates panel
                        if showBuildTemplates {
                            buildTemplatesSection
                        }

                        // Environment snapshot panel
                        if showEnvironmentSnapshot, let snapshot = lastEnvironmentSnapshot {
                            environmentSnapshotSection(snapshot)
                        }

                        // Git info panel
                        if showGitInfo, let project = selectedProject {
                            gitInfoSection(project: project)
                        }

                        // Emulator Quick Launch panel
                        if showEmulatorLauncher {
                            emulatorLauncherSection
                        }

                        // Build Cache Analytics panel
                        if showCacheAnalytics {
                            cacheAnalyticsSection
                        }

                        // Crash Log Symbolication panel
                        if showCrashSymbolicator {
                            crashSymbolicatorSection
                        }

                        // Feedback panel
                        if showFeedback {
                            feedbackSection
                        }

                        // Version Bumper panel
                        if showVersionBumper, selectedProject != nil {
                            versionBumperSection
                        }

                        // Release Notes panel
                        if showReleaseNotes, selectedProject != nil {
                            releaseNotesSection
                        }

                        // Build Matrix panel
                        if showBuildMatrix, selectedProject != nil {
                            buildMatrixSection
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .transition(.opacity)
            }

            // Drag & drop overlay
            if dragDropService.isDraggingOver {
                dragDropOverlay
            }

            // Device chooser & drop result
            deviceChooserSection

            // Task running indicator
            if buildService.isRunningTask {
                HStack(spacing: 5) {
                    ProgressView()
                        .scaleEffect(0.4)
                    Text("Running task...")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
            }

            footerView
        }
        .frame(width: 370)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.25), value: buildService.currentBuild?.state.isBuilding)
        .animation(.easeInOut(duration: 0.2), value: selectedProject?.id)
        .onAppear {
            gitService.refreshBranches(for: projectStore.projects)
            adbService.startMonitoring()
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { dragDropService.isDraggingOver },
            set: { dragDropService.isDraggingOver = $0 }
        )) { providers in
            dragDropService.handleDrop(providers: providers) { path in
                guard let path = path else { return }
                // If we have online devices, show device chooser
                let onlineDevices = adbService.devices.filter { $0.isOnline }
                if onlineDevices.count == 1 {
                    dragDropService.installOnDevice(onlineDevices[0], apkPath: path, adbService: adbService)
                } else if onlineDevices.count > 1 {
                    dragDropService.showDeviceChooser = true
                } else {
                    dragDropService.lastDropResult = .noDevices
                }
            }
            return true
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            // App icon — branded rocket
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Brand.primary.opacity(0.18), Brand.violet.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)

                Image(systemName: "paperplane.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Brand.iconGradient)
                    .symbolEffect(.pulse, isActive: !buildService.activeBuilds.isEmpty)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(Brand.appName)
                    .font(Brand.titleFont(13))
                    .foregroundStyle(Brand.heroGradient)
                Text("\(projectStore.projects.count) project\(projectStore.projects.count == 1 ? "" : "s")")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            if !buildService.activeBuilds.isEmpty, let build = buildService.activeBuilds.first {
                HStack(spacing: 5) {
                    ElapsedTimeView(startTime: build.startTime)
                    ProgressView()
                        .scaleEffect(0.45)
                        .tint(Brand.primary)
                }
                .brandedCapsule(color: Brand.primary)
                .transition(.scale.combined(with: .opacity))
            } else if !adbService.devices.isEmpty {
                HStack(spacing: 3) {
                    Image(systemName: "iphone")
                        .font(.system(size: 9))
                    Text("\(adbService.devices.count)")
                        .font(Brand.mono(9, weight: .semibold))
                }
                .foregroundColor(Brand.accent)
                .brandedCapsule(color: Brand.accent)
            }
        }
        .brandedHeader()
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "star.fill", title: "FAVORITES", iconColor: Brand.warning)

            VStack(spacing: 4) {
                ForEach(favoriteStore.favorites) { fav in
                    if let project = projectStore.projects.first(where: { $0.id == fav.projectId }) {
                        FavoriteRow(
                            favorite: fav,
                            projectName: project.name,
                            branch: gitService.branches[project.id],
                            onBuild: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    buildService.enqueueBuild(
                                        project: project,
                                        variant: fav.variant,
                                        buildType: fav.buildType
                                    )
                                }
                            },
                            onRemove: {
                                withAnimation { favoriteStore.removeFavorite(fav) }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Project List

    private var projectListView: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "folder.fill", title: "PROJECTS", iconColor: Brand.primary)

            if projectStore.projects.isEmpty {
                CardContainer {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No projects configured")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Button("Open Settings") {
                            openSettings()
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(projectStore.projects) { project in
                        ProjectRowView(
                            project: project,
                            isSelected: selectedProject?.id == project.id,
                            selectedVariant: $selectedVariant,
                            selectedBuildType: $selectedBuildType,
                            selectedOutputFormat: $selectedOutputFormat,
                            branch: gitService.branches[project.id],
                            isFavorite: favoriteStore.isFavorite(
                                projectId: project.id,
                                variant: selectedVariant,
                                buildType: selectedBuildType
                            ),
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if selectedProject?.id == project.id {
                                        selectedProject = nil
                                    } else {
                                        selectedProject = project
                                        if !project.buildVariants.contains(selectedVariant),
                                           let first = project.buildVariants.first {
                                            selectedVariant = first
                                        }
                                    }
                                }
                            },
                            onBuild: { startBuild(project: project) },
                            onCleanBuild: { startCleanBuild(project: project) },
                            onToggleFavorite: {
                                if favoriteStore.isFavorite(projectId: project.id, variant: selectedVariant, buildType: selectedBuildType) {
                                    if let fav = favoriteStore.favorites.first(where: {
                                        $0.projectId == project.id && $0.variant == selectedVariant && $0.buildType == selectedBuildType
                                    }) {
                                        favoriteStore.removeFavorite(fav)
                                    }
                                } else {
                                    favoriteStore.addFavorite(
                                        projectId: project.id,
                                        variant: selectedVariant,
                                        buildType: selectedBuildType
                                    )
                                }
                            },
                            onRunTask: { task in
                                buildService.runTask(task, project: project, variant: selectedVariant, buildType: selectedBuildType)
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Active Build Card

    private func activeBuildCard(build: BuildStatus) -> some View {
        VStack(spacing: 0) {
            CardContainer(padding: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Brand.primary.opacity(0.1))
                                .frame(width: 32, height: 32)
                            ProgressView()
                                .scaleEffect(0.55)
                                .tint(Brand.primary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(build.project.name)
                                    .font(.system(size: 12, weight: .semibold))
                                if build.outputFormat == .aab {
                                    Text("AAB")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundColor(Brand.violet.opacity(0.8))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Brand.violet.opacity(0.1)))
                                }
                            }
                            HStack(spacing: 4) {
                                Text("\(build.variant) / \(build.buildType)")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                                ElapsedTimeView(startTime: build.startTime)
                            }
                        }

                        Spacer()

                        Button(action: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                buildService.cancelBuild(build.id)
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }

                    // Progress
                    VStack(alignment: .leading, spacing: 5) {
                        AnimatedProgressBar(value: build.progress)

                        HStack {
                            Text(build.taskName)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(build.progress * 100))%")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Brand.success)
                        }
                    }

                    // Log toggle
                    VStack(alignment: .leading, spacing: 6) {
                        Button(action: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                showLog.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: showLog ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                Text(showLog ? "Hide Log" : "Show Log")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(.secondary.opacity(0.7))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if showLog {
                            ScrollViewReader { proxy in
                                ScrollView {
                                    Text(build.logOutput.suffix(3000))
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.8))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .id("logBottom")
                                }
                                .frame(height: 150)
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.4))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onChange(of: build.logOutput) { _, _ in
                                    withAnimation(.easeOut(duration: 0.1)) {
                                        proxy.scrollTo("logBottom", anchor: .bottom)
                                    }
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Device Section

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "cable.connector", title: "DEVICES", iconColor: Brand.primary)
                Spacer()

                Button(action: { withAnimation { showWirelessPairing.toggle() } }) {
                    Image(systemName: "wifi")
                        .font(.system(size: 9))
                        .foregroundColor(showWirelessPairing ? Brand.accent : .secondary)
                }
                .buttonStyle(.plain)
                .help("Wireless ADB pairing")

                Button(action: { adbService.refreshDevices() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Wireless pairing panel
            if showWirelessPairing {
                CardContainer(padding: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: "wifi")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Brand.accent)
                            Text("Wireless Debugging")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Android 11+")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.5))
                            Spacer()
                            Button(action: { withAnimation { showWirelessPairing = false } }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        }

                        Text("Settings → Developer Options → Wireless Debugging → Pair")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.5))

                        // Form fields
                        VStack(spacing: 6) {
                            HStack(spacing: 6) {
                                Text("IP")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .frame(width: 28, alignment: .trailing)
                                TextField("192.168.1.x", text: $wirelessHost)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                            }

                            HStack(spacing: 6) {
                                Text("Pair")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .frame(width: 28, alignment: .trailing)
                                TextField("Port", text: $wirelessPairPort)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                                    .frame(width: 58)
                                TextField("Code", text: $wirelessPairingCode)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                                    .frame(width: 68)
                                Button(action: {
                                    adbService.pairDevice(host: wirelessHost, port: wirelessPairPort, pairingCode: wirelessPairingCode)
                                }) {
                                    Text("Pair")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Brand.accent))
                                }
                                .buttonStyle(.plain)
                                .disabled(wirelessHost.isEmpty || wirelessPairPort.isEmpty || wirelessPairingCode.isEmpty || adbService.isPairing)
                            }

                            HStack(spacing: 6) {
                                Text("Conn")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .frame(width: 28, alignment: .trailing)
                                TextField("Port", text: $wirelessConnectPort)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                                    .frame(width: 58)
                                Button(action: {
                                    adbService.connectDevice(host: wirelessHost, port: wirelessConnectPort)
                                }) {
                                    Text("Connect")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Brand.success))
                                }
                                .buttonStyle(.plain)
                                .disabled(wirelessHost.isEmpty || wirelessConnectPort.isEmpty || adbService.isConnecting)

                                if adbService.devices.contains(where: { $0.id.contains(":") }) {
                                    Button(action: { adbService.disconnectAll() }) {
                                        Text("Disconnect All")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(Brand.error.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Status
                        if adbService.isPairing || adbService.isConnecting {
                            HStack(spacing: 4) {
                                ProgressView().scaleEffect(0.35)
                                Text(adbService.isPairing ? "Pairing..." : "Connecting...")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let result = adbService.wirelessPairingResult {
                            HStack(spacing: 4) {
                                switch result {
                                case .success(let msg):
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(Brand.success)
                                    Text(msg)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(Brand.success.opacity(0.8))
                                case .failed(let msg):
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(Brand.error)
                                    Text(msg)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(Brand.error.opacity(0.8))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            CardContainer {
                VStack(spacing: 6) {
                    ForEach(Array(adbService.devices.enumerated()), id: \.element.id) { index, device in
                        if index > 0 {
                            Divider().padding(.horizontal, 4)
                        }
                        DeviceRow(
                            device: device,
                            lastSuccessfulAPK: lastSuccessfulAPKPath,
                            isInstalling: adbService.isInstalling,
                            onInstall: { apkPath in
                                adbService.installAPK(apkPath: apkPath, device: device) { _, _ in }
                            }
                        )
                    }

                    // Install All button
                    if adbService.devices.filter({ $0.isOnline }).count >= 2,
                       let apkPath = lastSuccessfulAPKPath {
                        Divider().padding(.horizontal, 4).opacity(0.5)
                        Button(action: {
                            adbService.installAPKOnAllDevices(apkPath: apkPath) { _, _ in }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.system(size: 9))
                                Text("Install on All Devices")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Brand.accent.opacity(0.05))
                            )
                            .foregroundColor(Brand.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(adbService.isInstalling)
                    }
                }
            }
        }
    }

    // MARK: - Recent Builds Section

    private var recentBuildsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                SectionHeader(icon: "clock.arrow.circlepath", title: "RECENT", iconColor: .secondary)
                Text("\(buildService.buildHistory.count)")
                    .font(Brand.mono(9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.08)))

                Spacer()

                if buildService.buildHistory.count > 5 {
                    Button(action: { withAnimation { showFullHistory = true } }) {
                        HStack(spacing: 2) {
                            Text("All History")
                                .font(.system(size: 9, weight: .medium))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }

            CardContainer {
                VStack(spacing: 4) {
                    ForEach(Array(buildService.buildHistory.prefix(5).enumerated()), id: \.element.id) { index, build in
                        if index > 0 {
                            Divider().padding(.horizontal, 4)
                        }
                        RecentBuildRow(
                            build: build,
                            devices: adbService.devices,
                            onInstall: { device in
                                if case .success(let path) = build.state {
                                    adbService.installAPK(apkPath: path, device: device) { _, _ in }
                                }
                            },
                            onQR: { apkPath in
                                qrService.generateAndServe(apkPath: apkPath)
                                withAnimation { showQRCode = true }
                            },
                            onAnalyze: { apkPath in
                                Task.detached(priority: .userInitiated) {
                                    let result = APKAnalyzerService.analyze(apkPath: apkPath)
                                    await MainActor.run {
                                        apkAnalysis = result
                                        withAnimation { showAPKAnalysis = true }
                                    }
                                }
                            },
                            onViewMapping: { mappingPath in
                                mappingService.loadMapping(from: mappingPath)
                                withAnimation { showMappingViewer = true }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Full Build History

    private var filteredHistory: [BuildStatus] {
        var builds = buildService.buildHistory

        // Apply status filter
        switch historyFilter {
        case .all: break
        case .success: builds = builds.filter { $0.state.isSuccess }
        case .failed: builds = builds.filter { if case .failed = $0.state { return true }; return false }
        }

        // Apply search text
        if !historySearchText.isEmpty {
            let query = historySearchText.lowercased()
            builds = builds.filter { build in
                build.project.name.lowercased().contains(query) ||
                build.variant.lowercased().contains(query) ||
                build.buildType.lowercased().contains(query)
            }
        }

        return builds
    }

    private var fullHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Button(action: {
                    withAnimation {
                        showFullHistory = false
                        historySearchText = ""
                        historyFilter = .all
                    }
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .bold))
                        Text("Back")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("BUILD HISTORY")
                    .font(Brand.sectionFont(10))
                    .foregroundColor(Brand.primary.opacity(0.7))
                    .tracking(1.2)

                Text("\(buildService.buildHistory.count)")
                    .font(Brand.mono(9, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.08)))

                Spacer()

                if !buildService.buildHistory.isEmpty {
                    Button(action: {
                        withAnimation { buildService.buildHistory.removeAll() }
                    }) {
                        Text("Clear")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Brand.error.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Search + filters
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                    TextField("Search builds...", text: $historySearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                    if !historySearchText.isEmpty {
                        Button(action: { historySearchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                )

                HStack(spacing: 2) {
                    ForEach(HistoryFilter.allCases, id: \.self) { filter in
                        Button(action: { withAnimation { historyFilter = filter } }) {
                            Text(filter.rawValue)
                                .font(.system(size: 9, weight: historyFilter == filter ? .semibold : .regular))
                                .foregroundColor(historyFilter == filter ? .white : .secondary.opacity(0.7))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(historyFilter == filter ? Color.accentColor : Color.secondary.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Stats
            let successCount = buildService.buildHistory.filter { $0.state.isSuccess }.count
            let failCount = buildService.buildHistory.filter { if case .failed = $0.state { return true }; return false }.count
            HStack(spacing: 10) {
                HStack(spacing: 3) {
                    Circle().fill(Brand.success).frame(width: 5, height: 5)
                    Text("\(successCount) passed")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                HStack(spacing: 3) {
                    Circle().fill(Brand.error).frame(width: 5, height: 5)
                    Text("\(failCount) failed")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                if filteredHistory.count != buildService.buildHistory.count {
                    Text("showing \(filteredHistory.count)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.accentColor.opacity(0.7))
                }
                Spacer()
            }
            .padding(.horizontal, 2)

            // Build list
            if filteredHistory.isEmpty {
                CardContainer {
                    HStack {
                        Spacer()
                        VStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("No builds match your filter")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                }
            } else {
                CardContainer {
                    VStack(spacing: 4) {
                        ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { index, build in
                            if index > 0 {
                                Divider().padding(.horizontal, 4)
                            }
                            RecentBuildRow(
                                build: build,
                                devices: adbService.devices,
                                onInstall: { device in
                                    if case .success(let path) = build.state {
                                        adbService.installAPK(apkPath: path, device: device) { _, _ in }
                                    }
                                },
                                onQR: { apkPath in
                                    qrService.generateAndServe(apkPath: apkPath)
                                    withAnimation { showQRCode = true }
                                },
                                onAnalyze: { apkPath in
                                    Task.detached(priority: .userInitiated) {
                                        let result = APKAnalyzerService.analyze(apkPath: apkPath)
                                        await MainActor.run {
                                            apkAnalysis = result
                                            withAnimation { showAPKAnalysis = true }
                                        }
                                    }
                                },
                                onViewMapping: { mappingPath in
                                    mappingService.loadMapping(from: mappingPath)
                                    withAnimation { showMappingViewer = true }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    /// Get the last successful APK path from build history
    private var lastSuccessfulAPKPath: String? {
        for build in buildService.buildHistory {
            if case .success(let path) = build.state {
                return path
            }
        }
        return nil
    }

    /// All successful builds with their APK paths (for multi-APK menus)
    private var successfulBuilds: [SuccessfulBuildItem] {
        buildService.buildHistory.prefix(10).compactMap { build in
            if case .success(let path) = build.state {
                let label = "\(build.project.name) (\(build.variant)/\(build.buildType))"
                return SuccessfulBuildItem(path: path, label: label)
            }
            return nil
        }
    }

    // MARK: - Firebase Upload Section

    private var firebaseUploadSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "flame.fill", title: "FIREBASE UPLOAD", iconColor: Brand.warning)
                Spacer()
                if firebaseService.uploadState.isUploading {
                    Button(action: { firebaseService.cancelUpload() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.error)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel upload")
                }
                Button(action: {
                    withAnimation { showFirebaseUpload = false }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    if !firebaseService.isConfigured {
                        // No Firebase CLI
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Brand.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Firebase CLI not configured")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Set up in Settings → Firebase")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else if firebaseService.configs.isEmpty {
                        // No configs
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Brand.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No Firebase configs")
                                    .font(.system(size: 11, weight: .medium))
                                Text("Add a config in Settings → Firebase")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        // Upload status
                        switch firebaseService.uploadState {
                        case .idle:
                            // Show APK picker + config picker + upload button
                            let builds = successfulBuilds
                            if builds.isEmpty {
                                Text("No APKs available to upload")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                // Release notes
                                TextField("Release notes (optional)", text: $firebaseReleaseNotes, axis: .vertical)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10))
                                    .lineLimit(2...4)

                                // Upload buttons per APK + config combo
                                ForEach(builds, id: \.path) { buildItem in
                                    let matchingConfigs = firebaseService.configs.filter { config in
                                        // Match by project if possible
                                        if let project = projectStore.projects.first(where: { buildItem.label.contains($0.name) }) {
                                            return config.projectId == project.id
                                        }
                                        return true
                                    }

                                    ForEach(matchingConfigs) { config in
                                        Button(action: {
                                            firebaseService.uploadAPK(
                                                apkPath: buildItem.path,
                                                config: config,
                                                releaseNotes: firebaseReleaseNotes.isEmpty ? nil : firebaseReleaseNotes
                                            )
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "arrow.up.circle.fill")
                                                    .font(.system(size: 12))
                                                    .foregroundColor(Brand.warning)
                                                VStack(alignment: .leading, spacing: 1) {
                                                    Text("Upload \(buildItem.label)")
                                                        .font(.system(size: 10, weight: .medium))
                                                        .lineLimit(1)
                                                    Text("→ \(config.name)")
                                                        .font(.system(size: 9))
                                                        .foregroundColor(.secondary)
                                                }
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary.opacity(0.5))
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .fill(Brand.warning.opacity(0.06))
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                        case .uploading(let progress):
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text(progress)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Brand.warning)
                                }

                                if !firebaseService.uploadLog.isEmpty {
                                    ScrollView {
                                        Text(firebaseService.uploadLog.suffix(2000))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.5))
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }

                        case .success(let downloadURL):
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Brand.success)
                                    Text("Upload Successful!")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Brand.success)
                                }

                                if let url = downloadURL {
                                    HStack(spacing: 4) {
                                        Image(systemName: "link")
                                            .font(.system(size: 9))
                                            .foregroundColor(Brand.primary)
                                        Text(url)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(Brand.primary)
                                            .lineLimit(2)
                                            .textSelection(.enabled)
                                    }
                                }

                                Button(action: {
                                    firebaseService.uploadState = .idle
                                    firebaseService.uploadLog = ""
                                }) {
                                    Text("Dismiss")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                        case .failed(let error):
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(Brand.error)
                                    Text("Upload Failed")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Brand.error)
                                }

                                Text(error)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Brand.error.opacity(0.8))
                                    .lineLimit(3)

                                Button(action: {
                                    firebaseService.uploadState = .idle
                                    firebaseService.uploadLog = ""
                                }) {
                                    Text("Dismiss")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    // MARK: - Profiles Section

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "rectangle.stack.fill", title: "PROFILES", iconColor: Brand.primary)

            VStack(spacing: 3) {
                ForEach(profileStore.profiles.prefix(5)) { profile in
                    if let project = projectStore.projects.first(where: { $0.id == profile.projectId }) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.indigo.opacity(0.7))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("\(project.name) · \(profile.variant)/\(profile.buildType)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.7))
                                    if profile.outputFormat == .aab {
                                        Text("AAB")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(Brand.violet.opacity(0.7))
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(Capsule().fill(Brand.violet.opacity(0.08)))
                                    }
                                }
                            }

                            Spacer()

                            Button(action: {
                                buildService.enqueueBuild(
                                    project: project,
                                    variant: profile.variant,
                                    buildType: profile.buildType,
                                    cleanFirst: profile.cleanFirst,
                                    postBuildActions: profile.postBuildActions,
                                    outputFormat: profile.outputFormat
                                )
                            }) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.white)
                                    .padding(5)
                                    .background(
                                        Circle()
                                            .fill(Color.indigo)
                                            .shadow(color: .indigo.opacity(0.15), radius: 2, y: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.indigo.opacity(0.03))
                        )
                    }
                }
            }
        }
    }

    // MARK: - QR Code Section

    private var qrCodeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "qrcode", title: "QR CODE", iconColor: Brand.primary)
                Spacer()
                Button(action: {
                    qrService.stopServing()
                    withAnimation { showQRCode = false }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            CardContainer {
                VStack(spacing: 10) {
                    if let qrImage = qrService.qrImage {
                        Image(nsImage: qrImage)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 140, height: 140)
                            .background(Color.white)
                            .cornerRadius(8)
                            .frame(maxWidth: .infinity)
                    }

                    if let url = qrService.serverURL {
                        Text(url)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }

                    if let fileName = qrService.servedFileName {
                        Text(fileName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Brand.primary)
                    }

                    HStack(spacing: 8) {
                        Circle()
                            .fill(qrService.isServing ? Brand.success : Brand.error)
                            .frame(width: 6, height: 6)
                        Text(qrService.isServing ? "Serving on local network" : "Server stopped")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - APK Analysis Section

    private func apkAnalysisSection(_ analysis: APKAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "doc.text.magnifyingglass", title: "APK ANALYSIS", iconColor: Brand.warning)
                Spacer()
                Button(action: { withAnimation { showAPKAnalysis = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 8) {
                    // Basic info
                    HStack {
                        AnalysisRow(label: "Size", value: analysis.formattedSize, icon: "internaldrive")
                        Spacer()
                        if let pkg = analysis.packageName {
                            AnalysisRow(label: "Package", value: pkg, icon: "shippingbox")
                        }
                    }

                    HStack {
                        if let v = analysis.versionName {
                            AnalysisRow(label: "Version", value: v, icon: "tag")
                        }
                        Spacer()
                        AnalysisRow(label: "DEX files", value: "\(analysis.dexFileCount)", icon: "doc.zipper")
                    }

                    HStack {
                        if let min = analysis.minSdk {
                            AnalysisRow(label: "Min SDK", value: min, icon: "arrow.down.to.line")
                        }
                        Spacer()
                        if let target = analysis.targetSdk {
                            AnalysisRow(label: "Target SDK", value: target, icon: "arrow.up.to.line")
                        }
                    }

                    if analysis.resourceCount > 0 {
                        AnalysisRow(label: "Resources", value: "\(analysis.resourceCount) files", icon: "photo.stack")
                    }

                    // Permissions
                    if !analysis.permissions.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Permissions (\(analysis.permissions.count))")
                                .font(.system(size: 10, weight: .semibold))

                            if !analysis.dangerousPermissions.isEmpty {
                                ForEach(analysis.dangerousPermissions, id: \.self) { perm in
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(Brand.warning)
                                        Text(perm.replacingOccurrences(of: "android.permission.", with: ""))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(Brand.warning)
                                    }
                                }
                            }

                            ForEach(analysis.normalPermissions.prefix(5), id: \.self) { perm in
                                Text(perm.replacingOccurrences(of: "android.permission.", with: ""))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            if analysis.normalPermissions.count > 5 {
                                Text("+ \(analysis.normalPermissions.count - 5) more")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                        }
                    }

                    // Native libs
                    if !analysis.nativeLibs.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Native Libraries (\(analysis.nativeLibs.count))")
                                .font(.system(size: 10, weight: .semibold))
                            ForEach(analysis.nativeLibs.prefix(8), id: \.self) { lib in
                                Text(lib)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Mapping Viewer Section

    private var mappingViewerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "map", title: "PROGUARD / R8 MAPPING", iconColor: .cyan)
                Spacer()
                Button(action: {
                    withAnimation {
                        showMappingViewer = false
                        mappingService.unload()
                        mappingSearchQuery = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 10) {
                    if mappingService.isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Loading mapping file...")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                    } else if let error = mappingService.error {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Brand.warning)
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        // Stats
                        HStack(spacing: 12) {
                            mappingStatBadge(label: "Classes", value: "\(mappingService.classCount)", tint: .cyan)
                            mappingStatBadge(label: "Members", value: "\(mappingService.memberCount)", tint: .indigo)
                            if let size = mappingService.fileSizeFormatted {
                                mappingStatBadge(label: "Size", value: size, tint: Brand.warning)
                            }
                        }

                        // Search bar
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                            TextField("Search classes, methods...", text: $mappingSearchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 10))
                                .onChange(of: mappingSearchQuery) { _, newValue in
                                    mappingService.search(query: newValue)
                                }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                        )

                        // Results
                        if !mappingSearchQuery.isEmpty {
                            if mappingService.searchResults.isEmpty {
                                Text("No results found")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.vertical, 6)
                            } else {
                                VStack(spacing: 2) {
                                    ForEach(Array(mappingService.searchResults.prefix(20))) { entry in
                                        MappingEntryRow(entry: entry)
                                    }
                                    if mappingService.searchResults.count > 20 {
                                        Text("+ \(mappingService.searchResults.count - 20) more results")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary.opacity(0.5))
                                            .frame(maxWidth: .infinity, alignment: .center)
                                            .padding(.top, 4)
                                    }
                                }
                            }
                        } else {
                            // Show a sample of entries when not searching
                            VStack(spacing: 2) {
                                ForEach(Array(mappingService.entries.prefix(8))) { entry in
                                    MappingEntryRow(entry: entry)
                                }
                                if mappingService.entries.count > 8 {
                                    Text("Search to find specific classes...")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.secondary.opacity(0.4))
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.top, 4)
                                }
                            }
                        }

                        // Copy full path button
                        if let path = mappingService.loadedFilePath {
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(path, forType: .string)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.clipboard")
                                        .font(.system(size: 8))
                                    Text("Copy mapping file path")
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(.cyan.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func mappingStatBadge(label: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(tint.opacity(0.04))
        )
    }

    // MARK: - Changelog Section

    private var changelogSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "list.bullet.clipboard", title: "CHANGELOG", iconColor: .teal)
                Spacer()
                Button(action: { withAnimation { showChangelog = false } }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            CardContainer {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(changelogEntries.prefix(15)) { commit in
                        HStack(alignment: .top, spacing: 6) {
                            Text(commit.shortHash)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.teal)
                                .frame(width: 50, alignment: .leading)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(commit.message)
                                    .font(.system(size: 10))
                                    .lineLimit(2)
                                Text("\(commit.author) · \(commit.formattedDate)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    if changelogEntries.count > 15 {
                        Text("+ \(changelogEntries.count - 15) more commits")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }
        }
    }

    // MARK: - Build Queue Section

    private var buildQueueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(icon: "list.number", title: "QUEUE (\(buildService.buildQueue.count))", iconColor: Brand.violet)

            VStack(spacing: 3) {
                ForEach(buildService.buildQueue) { item in
                    HStack(spacing: 8) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Brand.violet.opacity(0.6))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.project.name)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Text("\(item.variant)/\(item.buildType)\(item.cleanFirst ? " (clean)" : "")")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.7))
                        }

                        Spacer()

                        Button(action: {
                            withAnimation { buildService.removeFromQueue(item.id) }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.violet.opacity(0.03))
                    )
                }
            }
        }
    }

    // MARK: - Logcat Section

    private var logcatSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "terminal.fill", title: "LOGCAT", iconColor: .cyan)
                Spacer()
                if adbService.isLogcatRunning {
                    Button(action: { adbService.stopLogcat() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.error)
                    }
                    .buttonStyle(.plain)
                    .help("Stop logcat")
                }
                Button(action: {
                    withAnimation { showLogcat = false }
                    adbService.stopLogcat()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close logcat")
            }

            // Controls
            HStack(spacing: 6) {
                // Device picker
                if !adbService.devices.isEmpty {
                    Picker("", selection: $logcatDevice) {
                        ForEach(adbService.devices) { device in
                            Text(device.displayName)
                                .tag(device.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .onAppear {
                        if logcatDevice.isEmpty, let first = adbService.devices.first {
                            logcatDevice = first.id
                        }
                    }
                }

                TextField("Filter (tag:level)", text: $logcatFilter)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10))
                    .frame(maxWidth: .infinity)

                Button(action: {
                    let selectedDevice = adbService.devices.first(where: { $0.id == logcatDevice }) ?? adbService.devices.first
                    if let device = selectedDevice {
                        adbService.startLogcat(device: device, filter: logcatFilter)
                    }
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(Brand.success)
                .help("Start logcat")

                Button(action: {
                    adbService.logcatOutput = ""
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(Brand.warning)
                .help("Clear output")
            }

            // Output
            ScrollView {
                ScrollViewReader { proxy in
                    Text(adbService.logcatOutput.isEmpty ? "Logcat output will appear here..." : adbService.logcatOutput)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(adbService.logcatOutput.isEmpty ? .secondary.opacity(0.5) : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("logcatBottom")
                        .onChange(of: adbService.logcatOutput) {
                            proxy.scrollTo("logcatBottom", anchor: .bottom)
                        }
                }
            }
            .frame(height: 150)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
    }

    @State var showToolsMenu = false

    /// Number of active tool panels (for badge on Tools button)
    private var activeToolCount: Int {
        var count = 0
        if showLogcat { count += 1 }
        if showChangelog { count += 1 }
        if showFirebaseUpload { count += 1 }
        if showOTAServer || otaService.isServing { count += 1 }
        if showDependencyScanner { count += 1 }
        if showGitInfo { count += 1 }
        if showEnvironmentSnapshot { count += 1 }
        if showBuildTemplates { count += 1 }
        if showEmulatorLauncher { count += 1 }
        if showCacheAnalytics { count += 1 }
        if showCrashSymbolicator { count += 1 }
        if showFeedback { count += 1 }
        if showVersionBumper { count += 1 }
        if showReleaseNotes { count += 1 }
        if showBuildMatrix { count += 1 }
        return count
    }

    private var footerView: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 2) {
                FooterButton(icon: "gear", label: "Settings") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }

                // Tools menu — consolidates panels into a single overflow button
                toolsMenuButton

                Spacer()

                if !buildService.buildQueue.isEmpty {
                    HStack(spacing: 3) {
                        Circle().fill(Brand.violet).frame(width: 5, height: 5)
                        Text("\(buildService.buildQueue.count) queued")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Brand.violet)
                    .brandedCapsule(color: Brand.violet)
                }

                FooterButton(icon: "power", label: "Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    private var toolsMenuButton: some View {
        Button {
            showToolsMenu.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "paperplane.circle")
                    .font(.system(size: 9, weight: .medium))
                Text("Tools")
                    .font(.system(size: 10, weight: activeToolCount > 0 ? .medium : .regular))
                if activeToolCount > 0 {
                    Text("\(activeToolCount)")
                        .font(Brand.mono(8, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(Brand.primary))
                }
                Image(systemName: "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(showToolsMenu ? 180 : 0))
            }
            .foregroundColor(activeToolCount > 0 ? Brand.primary : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(showToolsMenu ? Color.primary.opacity(0.06) : (activeToolCount > 0 ? Brand.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showToolsMenu, arrowEdge: .bottom) {
            toolsMenuContent
        }
    }

    private var toolsMenuContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Logcat
            toolMenuItem(
                icon: "terminal", label: "Logcat",
                isActive: showLogcat, tint: .cyan
            ) {
                withAnimation { showLogcat.toggle() }
                if !showLogcat { adbService.stopLogcat() }
                showToolsMenu = false
            }

            // Changelog
            if let project = selectedProject {
                toolMenuItem(
                    icon: "list.bullet.clipboard", label: "Git Changelog",
                    isActive: showChangelog, tint: .teal
                ) {
                    if showChangelog {
                        withAnimation { showChangelog = false; changelogEntries = [] }
                    } else {
                        Task.detached(priority: .userInitiated) {
                            let entries = BuildChangelogService.getChangelog(projectPath: project.path)
                            await MainActor.run {
                                changelogEntries = entries
                                withAnimation { showChangelog = true }
                            }
                        }
                    }
                    showToolsMenu = false
                }
            }

            Divider().padding(.vertical, 2)

            // Firebase
            if firebaseService.isConfigured && !firebaseService.configs.isEmpty && !successfulBuilds.isEmpty {
                toolMenuItem(
                    icon: "flame.fill", label: "Firebase Upload",
                    isActive: showFirebaseUpload || firebaseService.uploadState.isUploading, tint: Brand.warning
                ) {
                    withAnimation { showFirebaseUpload.toggle() }
                    showToolsMenu = false
                }
            }

            // OTA
            toolMenuItem(
                icon: "antenna.radiowaves.left.and.right", label: "OTA Distribution",
                isActive: showOTAServer || otaService.isServing, tint: Brand.warning
            ) {
                withAnimation { showOTAServer.toggle() }
                showToolsMenu = false
            }

            // Templates
            toolMenuItem(
                icon: "rectangle.stack.fill", label: "Build Templates",
                isActive: showBuildTemplates, tint: .indigo
            ) {
                withAnimation { showBuildTemplates.toggle() }
                showToolsMenu = false
            }

            if selectedProject != nil {
                Divider().padding(.vertical, 2)

                // Deps
                toolMenuItem(
                    icon: "puzzlepiece.fill", label: "Dependencies",
                    isActive: showDependencyScanner, tint: Brand.violet
                ) {
                    if showDependencyScanner {
                        withAnimation { showDependencyScanner = false }
                    } else {
                        if let project = selectedProject {
                            dependencyScanner.scan(project: project)
                        }
                        withAnimation { showDependencyScanner = true }
                    }
                    showToolsMenu = false
                }

                // Git
                toolMenuItem(
                    icon: "arrow.triangle.branch", label: "Git Info",
                    isActive: showGitInfo, tint: Brand.warning
                ) {
                    withAnimation { showGitInfo.toggle() }
                    showToolsMenu = false
                }

                // Environment
                toolMenuItem(
                    icon: "gearshape.2", label: "Build Environment",
                    isActive: showEnvironmentSnapshot, tint: .teal
                ) {
                    if showEnvironmentSnapshot {
                        withAnimation { showEnvironmentSnapshot = false }
                    } else {
                        if let project = selectedProject {
                            lastEnvironmentSnapshot = BuildEnvironmentCapturer.capture(
                                project: project,
                                variant: selectedVariant,
                                buildType: selectedBuildType,
                                outputFormat: selectedOutputFormat
                            )
                        } else if let lastBuild = buildService.buildHistory.first {
                            lastEnvironmentSnapshot = lastBuild.environmentSnapshot
                        }
                        withAnimation { showEnvironmentSnapshot = true }
                    }
                    showToolsMenu = false
                }
            }

            Divider().padding(.vertical, 2)

            // Emulator Quick Launch
            toolMenuItem(
                icon: "desktopcomputer", label: "Emulators",
                isActive: showEmulatorLauncher, tint: Brand.success
            ) {
                if showEmulatorLauncher {
                    withAnimation { showEmulatorLauncher = false }
                } else {
                    emulatorService.refreshAVDs()
                    withAnimation { showEmulatorLauncher = true }
                }
                showToolsMenu = false
            }

            // Build Cache Analytics
            toolMenuItem(
                icon: "chart.bar.fill", label: "Cache Analytics",
                isActive: showCacheAnalytics, tint: .mint
            ) {
                if showCacheAnalytics {
                    withAnimation { showCacheAnalytics = false }
                } else {
                    // Auto-analyze latest build log if available
                    if let lastBuild = buildService.buildHistory.first {
                        _ = cacheAnalyticsService.analyzeBuildLog(lastBuild.logOutput)
                    }
                    withAnimation { showCacheAnalytics = true }
                }
                showToolsMenu = false
            }

            // Crash Log Symbolication
            toolMenuItem(
                icon: "ladybug.fill", label: "Crash Symbolication",
                isActive: showCrashSymbolicator, tint: Brand.error
            ) {
                withAnimation { showCrashSymbolicator.toggle() }
                showToolsMenu = false
            }

            if selectedProject != nil {
                Divider().padding(.vertical, 2)

                // Version Bumper
                toolMenuItem(
                    icon: "arrow.up.circle.fill", label: "Version Bumper",
                    isActive: showVersionBumper, tint: Brand.accent
                ) {
                    if showVersionBumper {
                        withAnimation { showVersionBumper = false }
                    } else {
                        if let project = selectedProject {
                            versionBumperService.detectVersion(project: project)
                        }
                        withAnimation { showVersionBumper = true }
                    }
                    showToolsMenu = false
                }

                // Release Notes
                toolMenuItem(
                    icon: "doc.text.fill", label: "Release Notes",
                    isActive: showReleaseNotes, tint: .teal
                ) {
                    if showReleaseNotes {
                        withAnimation { showReleaseNotes = false }
                    } else {
                        if let project = selectedProject {
                            releaseNotesService.loadCommits(project: project, source: .sinceLastTag)
                        }
                        withAnimation { showReleaseNotes = true }
                    }
                    showToolsMenu = false
                }

                // Build Matrix
                toolMenuItem(
                    icon: "square.grid.3x3.fill", label: "Build Matrix",
                    isActive: showBuildMatrix || buildMatrixService.isRunning, tint: Brand.violet
                ) {
                    if showBuildMatrix {
                        withAnimation { showBuildMatrix = false }
                    } else {
                        if let project = selectedProject {
                            buildMatrixService.initializeSelections(project: project)
                            buildMatrixService.buildMatrix(project: project)
                        }
                        withAnimation { showBuildMatrix = true }
                    }
                    showToolsMenu = false
                }
            }

            Divider().padding(.vertical, 2)

            // Feedback
            toolMenuItem(
                icon: "bubble.left.and.bubble.right.fill", label: "Send Feedback",
                isActive: showFeedback, tint: Brand.primary
            ) {
                withAnimation { showFeedback.toggle() }
                showToolsMenu = false
            }
        }
        .padding(6)
        .frame(width: 200)
    }

    private func toolMenuItem(icon: String, label: String, isActive: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? tint : .secondary)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .medium : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                Spacer()
                if isActive {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? tint.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func startBuild(project: AndroidProject) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            buildService.enqueueBuild(
                project: project,
                variant: selectedVariant,
                buildType: selectedBuildType,
                outputFormat: selectedOutputFormat
            )
        }
    }

    private func startCleanBuild(project: AndroidProject) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            buildService.enqueueBuild(
                project: project,
                variant: selectedVariant,
                buildType: selectedBuildType,
                cleanFirst: true,
                outputFormat: selectedOutputFormat
            )
        }
    }
}

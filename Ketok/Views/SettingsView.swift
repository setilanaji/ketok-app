import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var projectStore: ProjectStore
    @EnvironmentObject var adbService: ADBService
    @EnvironmentObject var signingStore: SigningConfigStore
    @EnvironmentObject var favoriteStore: FavoriteStore
    @EnvironmentObject var buildStatsStore: BuildStatsStore
    @EnvironmentObject var buildService: GradleBuildService
    @EnvironmentObject var profileStore: BuildProfileStore
    @State private var showAddProject = false
    @State private var editingProject: AndroidProject?
    @State private var systemEnv: SystemEnvironment?
    @State private var projectEnvs: [UUID: ProjectEnvironment] = [:]
    @State private var selectedTab = 0
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @ObservedObject private var soundService = BuildSoundService.shared
    @ObservedObject private var firebaseService = FirebaseDistributionService.shared
    @State private var importResult: String?
    @State private var showImportResult = false
    @State private var editingProfile: BuildProfile?
    @State private var showAddProfile = false
    @State private var showAddFirebaseConfig = false
    @State private var firebaseLoggedIn = false
    @ObservedObject private var keystoreService = KeystoreManagerService.shared
    @State private var keystorePassword = ""
    @State private var keystorePath = ""
    @State private var showCreateDebugKeystore = false
    @State private var debugKeystorePath = ""
    @State private var debugKeystorePassword = "android"

    var body: some View {
        VStack(spacing: 0) {
            // Custom tab bar
            HStack(spacing: 0) {
                SettingsTabButton(icon: "folder.fill", label: "Projects", isSelected: selectedTab == 0) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 0 }
                }
                SettingsTabButton(icon: "gearshape.2.fill", label: "Environment", isSelected: selectedTab == 1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 1 }
                }
                SettingsTabButton(icon: "signature", label: "Signing", isSelected: selectedTab == 2) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 2 }
                }
                SettingsTabButton(icon: "slider.horizontal.3", label: "Preferences", isSelected: selectedTab == 3) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 3 }
                }
                SettingsTabButton(icon: "chart.bar.fill", label: "Stats", isSelected: selectedTab == 4) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 4 }
                }
                SettingsTabButton(icon: "info.circle.fill", label: "About", isSelected: selectedTab == 5) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTab = 5 }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Divider()
                .padding(.horizontal, 16)

            // Tab content with transitions
            Group {
                switch selectedTab {
                case 0: projectsTab
                case 1: environmentTab
                case 2: signingTab
                case 3: preferencesTab
                case 4: statsTab
                case 5: aboutTab
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: selectedTab)
        }
        .frame(width: 620, height: 520)
        .sheet(isPresented: $showAddProject) {
            AddProjectView { project in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    projectStore.addProject(project)
                }
            }
        }
        .sheet(item: $editingProject) { project in
            EditProjectView(project: project) { updated in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    projectStore.updateProject(updated)
                }
            }
        }
    }

    // MARK: - Projects Tab

    private var projectsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Projects")
                        .font(Brand.titleFont(16))
                    Text("\(projectStore.projects.count) project\(projectStore.projects.count == 1 ? "" : "s") configured")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { showAddProject = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 12))
                        Text("Add Project")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Brand.primary.opacity(0.12))
                    )
                    .foregroundColor(Brand.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            // Project list
            if projectStore.projects.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 36))
                        .foregroundStyle(.linearGradient(
                            colors: [Brand.primary.opacity(0.5), .mint.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text("No projects yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Add an Android project to start building APKs")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(projectStore.projects) { project in
                            SettingsProjectCard(
                                project: project,
                                onRescan: {
                                    var updated = project
                                    updated.buildVariants = []
                                    updated.buildTypes = ["debug", "release"]
                                    updated.appModulePath = nil
                                    updated.autoDetectSettings()
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        projectStore.updateProject(updated)
                                    }
                                },
                                onEdit: { editingProject = project },
                                onDelete: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        if let idx = projectStore.projects.firstIndex(where: { $0.id == project.id }) {
                                            projectStore.removeProject(at: IndexSet(integer: idx))
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: - Environment Tab

    private var environmentTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Environment")
                            .font(Brand.titleFont(16))
                        Text("System and project build settings")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    SettingsActionButton(icon: "arrow.triangle.2.circlepath", label: "Refresh") {
                        refreshEnvironment()
                    }
                }
                .padding(.bottom, 4)

                // System-wide environment
                if let sysEnv = systemEnv {
                    EnvironmentCard(title: "System", icon: "desktopcomputer", tint: Brand.primary) {
                        VStack(spacing: 8) {
                            EnvRow(label: "JAVA_HOME", value: sysEnv.javaHome ?? "Not set", ok: sysEnv.javaHome != nil)
                            EnvRow(label: "ANDROID_HOME", value: sysEnv.androidHome ?? "Not set", ok: sysEnv.androidHome != nil)
                            EnvRow(label: "Studio JBR", value: sysEnv.androidStudioJbrPath ?? "Not found", ok: sysEnv.androidStudioJbrPath != nil)
                            EnvRow(label: "Global Gradle", value: sysEnv.globalGradleVersion ?? "Not installed", ok: sysEnv.globalGradleVersion != nil)

                            Divider()

                            EnvRow(label: "Flutter SDK", value: sysEnv.flutterHome ?? "Not found", ok: sysEnv.flutterHome != nil)
                            EnvRow(label: "Flutter", value: sysEnv.flutterVersion ?? "Not installed", ok: sysEnv.flutterVersion != nil)
                            EnvRow(label: "Dart", value: sysEnv.dartVersion ?? "Not installed", ok: sysEnv.dartVersion != nil)
                            if let channel = sysEnv.flutterChannel {
                                EnvRow(label: "Channel", value: channel, ok: true)
                            }
                        }
                    }
                }

                // Per-project environment
                ForEach(projectStore.projects) { project in
                    if let env = projectEnvs[project.id] {
                        EnvironmentCard(
                            title: project.name,
                            icon: project.projectType.folderIcon,
                            tint: project.projectType.tintColor
                        ) {
                            VStack(spacing: 8) {
                                EnvRow(label: "Type", value: env.projectType.displayName, ok: true)

                                if env.projectType == .flutter {
                                    // Flutter-specific environment
                                    if let pubName = env.pubspecName {
                                        EnvRow(label: "Package", value: pubName, ok: true)
                                    }
                                    EnvRow(label: "Flutter", value: env.flutterVersion ?? "unknown", ok: env.flutterVersion != nil)
                                    EnvRow(label: "Dart", value: env.dartVersion ?? "unknown", ok: env.dartVersion != nil)

                                    Divider()
                                        .padding(.vertical, 2)

                                    Text("Android Sub-project")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }

                                EnvRow(label: "App Module", value: env.appModulePath ?? "not found", ok: env.appModulePath != nil)
                                EnvRow(label: "Build File", value: env.buildGradleType.rawValue, ok: env.buildGradleType != .none)
                                EnvRow(label: "sdk.dir", value: env.sdkDir ?? "not in local.properties", ok: env.sdkDir != nil)
                                EnvRow(label: "Gradle Wrapper", value: env.gradleVersionDisplay, ok: env.gradleVersion != nil)
                                EnvRow(label: "AGP Version", value: env.agpVersion ?? "unknown", ok: env.agpVersion != nil)
                                EnvRow(label: "Kotlin", value: env.kotlinVersion ?? "unknown", ok: env.kotlinVersion != nil)
                                EnvRow(label: "Java Target", value: env.javaVersion ?? "unknown", ok: env.javaVersion != nil)

                                if !env.buildVariants.isEmpty {
                                    EnvTagRow(
                                        label: env.projectType == .flutter ? "Flavors" : "Variants",
                                        tags: env.buildVariants,
                                        tint: project.projectType.tintColor
                                    )
                                }

                                EnvTagRow(label: "Build Types", tags: env.buildTypes, tint: Brand.warning)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear { refreshEnvironment() }
    }

    private func refreshEnvironment() {
        systemEnv = ProjectEnvironmentDetector.detectSystemEnvironment()
        var newEnvs: [UUID: ProjectEnvironment] = [:]
        for project in projectStore.projects {
            newEnvs[project.id] = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
        }
        projectEnvs = newEnvs
    }

    // MARK: - Signing Tab

    private var signingTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Signing Configuration")
                            .font(Brand.titleFont(16))
                        Text("Configure keystores for signed release builds")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                // Master toggle
                VStack(spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enable Signed Builds")
                                .font(.system(size: 12, weight: .medium))
                            Text("Inject signing config into Gradle when building release variants")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $signingStore.enableSignedBuilds)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(12)
                }
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                if signingStore.enableSignedBuilds {
                    // Keystore configs list
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Keystores")
                                .font(Brand.titleFont(14, weight: .semibold))
                            Spacer()
                            AddSigningConfigButton(projectStore: projectStore, signingStore: signingStore)
                        }

                        if signingStore.configs.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "key.slash")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text("No keystores configured")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                Text("Add a keystore to sign your release builds")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.02))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                                            .foregroundColor(.secondary.opacity(0.2))
                                    )
                            )
                        } else {
                            ForEach(signingStore.configs) { config in
                                SigningConfigCard(
                                    config: config,
                                    projectName: projectName(for: config.projectId),
                                    onDelete: { signingStore.removeConfig(config) }
                                )
                            }
                        }
                    }

                    // Info box
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 14))
                            .foregroundColor(Brand.primary)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("How signing works")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Passwords are stored securely in macOS Keychain. When you build a release variant, Ketok injects signing properties into the Gradle command so you get a properly signed APK without modifying your project's build.gradle.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Brand.primary.opacity(0.12), lineWidth: 1)
                    )
                }
                // MARK: - Keystore Manager
                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keystore Manager")
                                .font(Brand.titleFont(14))
                            Text("Inspect keystores, view aliases, check expiry dates")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()

                        if keystoreService.isKeytoolAvailable {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Brand.success)
                                .help("keytool found")
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Brand.warning)
                                .help("keytool not found — install JDK")
                        }
                    }

                    // Open keystore
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Keystore path (.jks / .keystore)", text: $keystorePath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))

                            Button("Browse") {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.data]
                                panel.allowsMultipleSelection = false
                                panel.title = "Select Keystore File"
                                if panel.runModal() == .OK, let url = panel.url {
                                    keystorePath = url.path
                                }
                            }
                            .font(.system(size: 11))
                        }

                        HStack(spacing: 8) {
                            SecureField("Keystore password", text: $keystorePassword)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11))

                            Button("Inspect") {
                                keystoreService.inspectKeystore(path: keystorePath, password: keystorePassword)
                            }
                            .font(.system(size: 11))
                            .disabled(keystorePath.isEmpty || keystorePassword.isEmpty || keystoreService.isLoading)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    )

                    if keystoreService.isLoading {
                        HStack(spacing: 6) {
                            ProgressView().scaleEffect(0.5)
                            Text("Reading keystore...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let error = keystoreService.lastError {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(Brand.error)
                                .font(.system(size: 11))
                            Text(error)
                                .font(.system(size: 11))
                                .foregroundColor(Brand.error)
                        }
                    }

                    if let result = keystoreService.createResult {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Brand.success)
                                .font(.system(size: 11))
                            Text(result)
                                .font(.system(size: 11))
                                .foregroundColor(Brand.success)
                        }
                    }

                    // Inspected keystores
                    ForEach(keystoreService.keystores) { keystore in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Brand.warning)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(keystore.fileName)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("\(keystore.type) · \(keystore.aliases.count) alias\(keystore.aliases.count == 1 ? "" : "es")")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()

                                Button(action: { keystoreService.removeKeystore(keystore.id) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach(keystore.aliases) { alias in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(alias.name)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        Spacer()
                                        if alias.isExpired {
                                            Text("EXPIRED")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Brand.error))
                                        } else if let days = alias.daysUntilExpiry, days < 90 {
                                            Text("Expires in \(days)d")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(Brand.warning)
                                        } else if let days = alias.daysUntilExpiry {
                                            Text("Expires in \(days / 365)y")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(Brand.success)
                                        }
                                    }

                                    if !alias.algorithm.isEmpty {
                                        Text("Algorithm: \(alias.algorithm)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    if !alias.expiryDate.isEmpty {
                                        Text("Valid until: \(alias.expiryDate)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }

                                    if !alias.fingerprint.isEmpty {
                                        HStack(spacing: 4) {
                                            Text("SHA-256:")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                            Text(alias.fingerprint)
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundColor(.secondary.opacity(0.7))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Button(action: {
                                                NSPasteboard.general.clearContents()
                                                NSPasteboard.general.setString(alias.fingerprint, forType: .string)
                                            }) {
                                                Image(systemName: "doc.on.clipboard")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.accentColor)
                                            }
                                            .buttonStyle(.plain)
                                            .help("Copy SHA-256 fingerprint")
                                        }
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(alias.isExpired ? Brand.error.opacity(0.04) : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(alias.isExpired ? Brand.error.opacity(0.15) : Color.primary.opacity(0.06), lineWidth: 1)
                                )
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }

                    // Create debug keystore
                    DisclosureGroup("Create Debug Keystore", isExpanded: $showCreateDebugKeystore) {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Output path", text: $debugKeystorePath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))

                                Button("Browse") {
                                    let panel = NSSavePanel()
                                    panel.nameFieldStringValue = "debug.keystore"
                                    panel.title = "Save Debug Keystore"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        debugKeystorePath = url.path
                                    }
                                }
                                .font(.system(size: 11))
                            }

                            HStack(spacing: 8) {
                                TextField("Password", text: $debugKeystorePassword)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                                    .frame(width: 150)

                                Spacer()

                                Button("Create") {
                                    keystoreService.createDebugKeystore(
                                        at: debugKeystorePath,
                                        password: debugKeystorePassword
                                    )
                                }
                                .font(.system(size: 11))
                                .disabled(debugKeystorePath.isEmpty || keystoreService.isLoading)
                            }
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(20)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: signingStore.enableSignedBuilds)
        }
    }

    private func projectName(for projectId: UUID?) -> String {
        guard let id = projectId else { return "All Projects" }
        return projectStore.projects.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    // MARK: - Preferences Tab

    private var preferencesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Keyboard Shortcuts
                VStack(alignment: .leading, spacing: 12) {
                    Text("Keyboard Shortcuts")
                        .font(Brand.titleFont(16))

                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Global Build Shortcut")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Trigger build from anywhere with \u{2318}\u{21E7}B")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $hotkeyService.isEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Devices
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Connected Devices")
                            .font(Brand.titleFont(16))

                        Spacer()

                        Button(action: { adbService.refreshDevices() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                                Text("Refresh")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Brand.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 0) {
                        if adbService.devices.isEmpty {
                            HStack {
                                Image(systemName: "iphone.slash")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("No devices connected")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("Connect an Android device via USB or start an emulator")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                        } else {
                            ForEach(adbService.devices) { device in
                                HStack(spacing: 10) {
                                    Image(systemName: device.icon)
                                        .font(.system(size: 14))
                                        .foregroundColor(device.isOnline ? Brand.primary : .secondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(device.displayName)
                                            .font(.system(size: 12, weight: .medium))
                                        Text(device.id)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(device.isOnline ? Brand.success : Brand.warning)
                                            .frame(width: 6, height: 6)
                                        Text(device.isOnline ? "Online" : device.state)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(device.isOnline ? Brand.success : Brand.warning)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                if device.id != adbService.devices.last?.id {
                                    Divider().padding(.horizontal, 12)
                                }
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Notifications
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notifications")
                        .font(Brand.titleFont(16))

                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Build Notifications")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Show macOS notifications when builds complete or fail")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Brand.success)
                                .font(.system(size: 14))
                        }
                        .padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Export / Import
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data")
                        .font(Brand.titleFont(16))

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Button(action: {
                                _ = SettingsExporter.exportSettings(
                                    projectStore: projectStore,
                                    favoriteStore: favoriteStore,
                                    signingStore: signingStore,
                                    buildStatsStore: buildStatsStore
                                )
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11))
                                    Text("Export Settings")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Brand.accent.opacity(0.08))
                                )
                                .foregroundColor(Brand.accent)
                            }
                            .buttonStyle(.plain)

                            Button(action: {
                                importResult = SettingsExporter.importSettings(
                                    projectStore: projectStore,
                                    favoriteStore: favoriteStore,
                                    signingStore: signingStore,
                                    buildStatsStore: buildStatsStore
                                )
                                showImportResult = importResult != nil
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 11))
                                    Text("Import Settings")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Brand.warning.opacity(0.08))
                                )
                                .foregroundColor(Brand.warning)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)

                        if showImportResult, let result = importResult {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Brand.success)
                                Text(result)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                    Text("Export saves projects, favorites, and build history to a JSON file. Signing passwords are not exported.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                // Build Sounds
                VStack(alignment: .leading, spacing: 12) {
                    Text("Build Sounds")
                        .font(Brand.titleFont(16))

                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sound Effects")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Play sounds on build success, failure, and start")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $soundService.soundEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .padding(12)

                        if soundService.soundEnabled {
                            Divider().padding(.horizontal, 12)

                            HStack {
                                Text("Success Sound")
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $soundService.selectedSuccessSound) {
                                    ForEach(BuildSoundService.availableSounds, id: \.self) { sound in
                                        Text(sound).tag(sound)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 120)

                                Button(action: { NSSound(named: NSSound.Name(soundService.selectedSuccessSound))?.play() }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Brand.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            HStack {
                                Text("Failure Sound")
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $soundService.selectedFailSound) {
                                    ForEach(BuildSoundService.availableSounds, id: \.self) { sound in
                                        Text(sound).tag(sound)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 120)

                                Button(action: { NSSound(named: NSSound.Name(soundService.selectedFailSound))?.play() }) {
                                    Image(systemName: "speaker.wave.2.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(Brand.accent)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Build Profiles
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Build Profiles")
                            .font(Brand.titleFont(16))
                        Spacer()
                        Button(action: { showAddProfile = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                Text("New Profile")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Brand.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    if profileStore.profiles.isEmpty {
                        HStack {
                            Image(systemName: "rectangle.stack.badge.plus")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No profiles yet")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Create profiles to save build configurations with post-build actions")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(profileStore.profiles) { profile in
                                HStack(spacing: 10) {
                                    Image(systemName: "rectangle.stack.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.indigo)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(profile.name)
                                            .font(.system(size: 12, weight: .medium))
                                        HStack(spacing: 4) {
                                            if let projectName = projectStore.projects.first(where: { $0.id == profile.projectId })?.name {
                                                Text(projectName)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("\(profile.variant)/\(profile.buildType)")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Text(profile.outputFormat.rawValue)
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(profile.outputFormat == .aab ? Brand.violet : Brand.success)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill((profile.outputFormat == .aab ? Brand.violet : Brand.success).opacity(0.08)))
                                            if !profile.postBuildActions.isEmpty {
                                                Text("\(profile.postBuildActions.filter { $0.enabled }.count) actions")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.indigo)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Capsule().fill(Color.indigo.opacity(0.1)))
                                            }
                                        }
                                    }

                                    Spacer()

                                    Button(action: {
                                        profileStore.removeProfile(profile)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(Brand.error.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                if profile.id != profileStore.profiles.last?.id {
                                    Divider().padding(.horizontal, 12)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }

                // Parallel Builds
                VStack(alignment: .leading, spacing: 12) {
                    Text("Parallel Builds")
                        .font(Brand.titleFont(16))

                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enable Parallel Builds")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Build multiple projects simultaneously")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $buildService.parallelEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                        .padding(12)

                        if buildService.parallelEnabled {
                            Divider().padding(.horizontal, 12)

                            HStack {
                                Text("Max concurrent builds")
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $buildService.maxParallelBuilds) {
                                    Text("2").tag(2)
                                    Text("3").tag(3)
                                    Text("4").tag(4)
                                    Text("5").tag(5)
                                }
                                .labelsHidden()
                                .frame(width: 60)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                            Text("Running many builds in parallel uses more RAM and CPU. Keep it at 2-3 for best results.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }

                // Firebase App Distribution
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Firebase App Distribution")
                            .font(Brand.titleFont(16))
                        Spacer()
                        Button(action: { showAddFirebaseConfig = true }) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 11))
                                Text("Add Config")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(Brand.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    // CLI status
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: firebaseService.isConfigured ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(firebaseService.isConfigured ? Brand.success : Brand.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Firebase CLI")
                                    .font(.system(size: 12, weight: .medium))
                                if firebaseService.isConfigured {
                                    Text(firebaseService.firebaseCLIPath)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Not found. Install with: npm install -g firebase-tools")
                                        .font(.system(size: 10))
                                        .foregroundColor(Brand.warning)
                                }
                            }
                            Spacer()
                            if firebaseService.isConfigured {
                                Button(action: {
                                    firebaseService.checkLoginStatus { loggedIn in
                                        firebaseLoggedIn = loggedIn
                                    }
                                }) {
                                    Text(firebaseLoggedIn ? "Logged In" : "Check Login")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(firebaseLoggedIn ? Brand.success : Brand.accent)
                                }
                                .buttonStyle(.plain)

                                if !firebaseLoggedIn {
                                    Button(action: { firebaseService.openFirebaseLogin() }) {
                                        Text("Login")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Brand.warning)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(12)

                        if !firebaseService.firebaseCLIPath.isEmpty {
                            Divider().padding(.horizontal, 12)
                            HStack {
                                Text("CLI Path")
                                    .font(.system(size: 11))
                                Spacer()
                                TextField("firebase path", text: $firebaseService.firebaseCLIPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 10, design: .monospaced))
                                    .frame(width: 280)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                    // Firebase configs
                    if firebaseService.configs.isEmpty {
                        HStack {
                            Image(systemName: "flame")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No Firebase configs")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Add a config to upload APKs to Firebase App Distribution")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    } else {
                        VStack(spacing: 0) {
                            ForEach(firebaseService.configs) { config in
                                HStack(spacing: 10) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(Brand.warning)
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(config.name)
                                            .font(.system(size: 12, weight: .medium))
                                        HStack(spacing: 4) {
                                            if let projectName = projectStore.projects.first(where: { $0.id == config.projectId })?.name {
                                                Text(projectName)
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text(config.appId)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary.opacity(0.7))
                                                .lineLimit(1)
                                            if config.autoUpload {
                                                Text("Auto")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(Brand.warning)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Capsule().fill(Brand.warning.opacity(0.1)))
                                            }
                                        }
                                    }

                                    Spacer()

                                    Button(action: {
                                        firebaseService.removeConfig(config)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(Brand.error.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                if config.id != firebaseService.configs.last?.id {
                                    Divider().padding(.horizontal, 12)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }
            }
            .padding(20)
        }
        .sheet(isPresented: $showAddProfile) {
            AddProfileSheet(projectStore: projectStore, profileStore: profileStore)
        }
        .sheet(isPresented: $showAddFirebaseConfig) {
            AddFirebaseConfigSheet(projectStore: projectStore, firebaseService: firebaseService)
        }
        .onAppear {
            if firebaseService.isConfigured {
                firebaseService.checkLoginStatus { loggedIn in
                    firebaseLoggedIn = loggedIn
                }
            }
        }
    }

    // MARK: - Stats Tab

    private var statsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Overall stats summary
                let overall = buildStatsStore.overallStats()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Build Overview")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 12) {
                        StatCard(title: "Total Builds", value: "\(overall.totalBuilds)", icon: "paperplane.fill", color: Brand.primary)
                        StatCard(title: "Success Rate", value: overall.totalBuilds > 0 ? String(format: "%.0f%%", overall.successRate) : "—", icon: "checkmark.circle.fill", color: Brand.success)
                        StatCard(title: "Avg Duration", value: overall.totalBuilds > 0 ? overall.formattedAvgDuration : "—", icon: "clock.fill", color: Brand.warning)
                        StatCard(title: "Total Time", value: overall.totalBuilds > 0 ? overall.formattedTotalTime : "—", icon: "hourglass", color: Brand.violet)
                    }
                }

                // Speed records
                if overall.totalBuilds > 0 {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "hare.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Brand.success)
                            Text("Fastest: \(overall.formattedFastest)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "tortoise.fill")
                                .font(.system(size: 10))
                                .foregroundColor(Brand.warning)
                            Text("Slowest: \(overall.formattedSlowest)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }

                Divider()

                // Build Duration Trend
                if buildStatsStore.records.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build Duration Trend")
                            .font(.system(size: 13, weight: .semibold))

                        let durationData = buildStatsStore.durationTrend()
                        BuildDurationChart(data: durationData)
                            .frame(height: 120)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }

                // APK Size Trend
                let sizeData = buildStatsStore.apkSizeTrend()
                if sizeData.count >= 2 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("APK Size Trend")
                            .font(.system(size: 13, weight: .semibold))

                        APKSizeChart(data: sizeData)
                            .frame(height: 120)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }
                }

                Divider()

                // Per-project breakdown
                if !projectStore.projects.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Per-Project Stats")
                            .font(.system(size: 13, weight: .semibold))

                        ForEach(projectStore.projects) { project in
                            if let stats = buildStatsStore.statsForProject(project.id) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(project.name)
                                            .font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text("\(stats.totalBuilds) builds")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    HStack(spacing: 16) {
                                        HStack(spacing: 4) {
                                            Circle().fill(Brand.success).frame(width: 6, height: 6)
                                            Text("\(stats.successCount) passed")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        HStack(spacing: 4) {
                                            Circle().fill(Brand.error).frame(width: 6, height: 6)
                                            Text("\(stats.failCount) failed")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        HStack(spacing: 4) {
                                            Image(systemName: "clock")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                            Text("avg \(stats.formattedAvgDuration)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                    }

                                    // Success rate bar
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Brand.error.opacity(0.2))
                                                .frame(height: 4)
                                            RoundedRectangle(cornerRadius: 2)
                                                .fill(Brand.success)
                                                .frame(width: geo.size.width * CGFloat(stats.successRate / 100), height: 4)
                                        }
                                    }
                                    .frame(height: 4)
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                            }
                        }
                    }
                }

                // Recent builds list
                if !buildStatsStore.records.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Recent Builds")
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            Text("\(buildStatsStore.records.count) total")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        ForEach(Array(buildStatsStore.records.suffix(10).reversed())) { record in
                            HStack(spacing: 8) {
                                Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(record.success ? Brand.success : Brand.error)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(record.projectName) — \(record.variant)/\(record.buildType)")
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                    Text(record.formattedDate)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(record.formattedDuration)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    if let size = record.formattedAPKSize {
                                        Text(size)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                // Clear stats
                if !buildStatsStore.records.isEmpty {
                    Divider()

                    HStack {
                        Spacer()
                        Button(action: {
                            buildStatsStore.clearAll()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                                Text("Clear All Stats")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(Brand.error)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                }

                // Empty state
                if buildStatsStore.records.isEmpty {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 40)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("No build data yet")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("Build stats will appear here after your first build.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 0) {
            Spacer()

            // App identity
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Brand.iconGradient)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Brand.primary.opacity(0.25), radius: 12, y: 6)
                        .frame(width: 72, height: 72)

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundColor(.white)
                }

                VStack(spacing: 3) {
                    Text(Brand.appName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Brand.heroGradient)
                    Text("0.9.0-beta")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.04))
                        )
                }
            }

            Text(Brand.tagline)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            Spacer().frame(height: 24)

            // Capabilities
            VStack(spacing: 0) {
                AboutCapabilityRow(icon: "hammer.fill", title: "Build APKs & AABs", subtitle: "Flutter & native Gradle builds with FVM support")
                Divider().padding(.horizontal, 16)
                AboutCapabilityRow(icon: "sparkle", title: "Smart Pre-Build", subtitle: "Auto code-gen, localization & dependency checks")
                Divider().padding(.horizontal, 16)
                AboutCapabilityRow(icon: "iphone.and.arrow.forward", title: "Device Install & OTA", subtitle: "Install on devices or share over local WiFi")
                Divider().padding(.horizontal, 16)
                AboutCapabilityRow(icon: "chart.bar.fill", title: "Build Intelligence", subtitle: "Health scores, failure patterns & diagnostics")
            }
            .brandedCard()
            .padding(.horizontal, 32)

            Spacer()

            // Footer
            VStack(spacing: 10) {
                Divider()
                    .padding(.horizontal, 32)

                HStack(spacing: 16) {
                    Button(action: {
                        if let url = URL(string: "https://github.com/setilanaji") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 11))
                            Text("setilanaji")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }

                    Text("·")
                        .foregroundColor(.secondary.opacity(0.3))

                    Button(action: {
                        if let url = URL(string: "https://github.com/setilanaji") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 9))
                            Text("GitHub")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in
                        if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }
}

import SwiftUI
// MARK: - Additional MenuBarView Sections

extension MenuBarView {

    // MARK: - Drag & Drop Overlay

    var dragDropOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Brand.primary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Brand.primary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                )

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Brand.primary.opacity(0.7))

                Text("Drop APK/AAB to Install")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Brand.primary.opacity(0.8))

                if adbService.devices.filter({ $0.isOnline }).isEmpty {
                    Text("No devices connected")
                        .font(.system(size: 9))
                        .foregroundColor(Brand.warning.opacity(0.7))
                } else {
                    Text("\(adbService.devices.filter { $0.isOnline }.count) device(s) available")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .frame(height: 100)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .transition(.opacity)
    }

    // MARK: - Device Chooser for Drag & Drop

    @ViewBuilder
    var deviceChooserSection: some View {
        if dragDropService.showDeviceChooser, let apkPath = dragDropService.droppedFilePath {
            CardContainer(padding: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                            .font(.system(size: 11))
                            .foregroundColor(Brand.accent)
                        Text("Choose Device to Install")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Button {
                            dragDropService.reset()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }

                    Text((apkPath as NSString).lastPathComponent)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)

                    ForEach(adbService.devices.filter { $0.isOnline }, id: \.id) { device in
                        Button {
                            dragDropService.installOnDevice(device, apkPath: apkPath, adbService: adbService)
                            dragDropService.showDeviceChooser = false
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: device.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(Brand.accent.opacity(0.7))
                                Text(device.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                Spacer()
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Brand.accent.opacity(0.5))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Brand.accent.opacity(0.05))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        dragDropService.installOnAllDevices(apkPath: apkPath, adbService: adbService)
                        dragDropService.showDeviceChooser = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                .font(.system(size: 10))
                                .foregroundColor(Brand.success.opacity(0.7))
                            Text("Install on All Devices")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Brand.success)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(Brand.success.opacity(0.05))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }

        // Drop result feedback
        if let result = dragDropService.lastDropResult {
            HStack(spacing: 6) {
                switch result {
                case .success(let deviceName):
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Brand.success)
                    Text("Installed on \(deviceName)")
                        .foregroundColor(Brand.success)
                case .failed(let error):
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Brand.error)
                    Text(error)
                        .foregroundColor(Brand.error)
                case .noDevices:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Brand.warning)
                    Text("No devices connected")
                        .foregroundColor(Brand.warning)
                }
                Spacer()
                Button {
                    dragDropService.lastDropResult = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.05))
            .transition(.opacity)
        }
    }

    // MARK: - Dependency Scanner Section

    var dependencyScannerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "puzzlepiece.fill", title: "DEPENDENCIES", iconColor: Brand.violet)
                Spacer()
                Button { withAnimation { showDependencyScanner = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if dependencyScanner.isScanning {
                CardContainer {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.5)
                        Text("Scanning dependencies...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else if let result = dependencyScanner.scanResult {
                CardContainer(padding: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        // Stats
                        HStack(spacing: 8) {
                            dependencyStatBadge(count: result.dependencies.count, label: "deps", color: Brand.primary)
                            dependencyStatBadge(count: result.plugins.count, label: "plugins", color: Brand.violet)
                        }

                        Divider().opacity(0.3)

                        // Group by category
                        ForEach(DependencyCategory.allCases, id: \.self) { category in
                            if let deps = result.byCategory[category], !deps.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 4) {
                                        Image(systemName: category.icon)
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary.opacity(0.5))
                                        Text(category.rawValue)
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundColor(.secondary.opacity(0.7))
                                        Text("(\(deps.count))")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary.opacity(0.4))
                                    }

                                    ForEach(deps.prefix(5)) { dep in
                                        HStack(spacing: 4) {
                                            Text(dep.artifact)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.primary.opacity(0.8))
                                                .lineLimit(1)
                                            Spacer()
                                            Text(dep.version)
                                                .font(.system(size: 8, design: .monospaced))
                                                .foregroundColor(Brand.success.opacity(0.7))
                                        }
                                    }
                                    if deps.count > 5 {
                                        Text("+ \(deps.count - 5) more")
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary.opacity(0.4))
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        // Flutter dependencies
                        if !dependencyScanner.flutterDependencies.isEmpty {
                            Divider().opacity(0.3)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bird.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(Brand.primary.opacity(0.5))
                                    Text("Flutter Packages")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.7))
                                    Text("(\(dependencyScanner.flutterDependencies.count))")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary.opacity(0.4))
                                }

                                ForEach(dependencyScanner.flutterDependencies.prefix(8)) { dep in
                                    HStack(spacing: 4) {
                                        Text(dep.name)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.primary.opacity(0.8))
                                            .lineLimit(1)
                                        Spacer()
                                        Text(dep.displayVersion)
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(Brand.primary.opacity(0.7))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func dependencyStatBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(Brand.sectionFont(10, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(color.opacity(0.08))
        )
    }

    // MARK: - OTA Distribution Section

    var otaDistributionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "antenna.radiowaves.left.and.right", title: "OTA DISTRIBUTION", iconColor: Brand.warning)
                Spacer()
                Button { withAnimation { showOTAServer = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            CardContainer(padding: 10) {
                VStack(spacing: 10) {
                    if otaService.isServing {
                        // Server is running
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Brand.success)
                                .frame(width: 6, height: 6)
                            Text("Server Running")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Brand.success)
                            Spacer()
                            Text("\(otaService.downloadCount) downloads")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                        }

                        if let url = otaService.serverURL {
                            HStack {
                                Text(url)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Brand.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(Brand.primary.opacity(0.7))
                            }
                        }

                        // QR Code
                        if let qr = otaService.qrImage {
                            Image(nsImage: qr)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 120, height: 120)
                                .cornerRadius(8)
                                .frame(maxWidth: .infinity)
                        }

                        if let fileName = otaService.servedFileName {
                            Text(fileName)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.6))
                        }

                        Button {
                            otaService.stopServing()
                        } label: {
                            Label("Stop Server", systemImage: "stop.circle.fill")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(Brand.error)
                    } else {
                        // Server not running
                        VStack(spacing: 8) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary.opacity(0.4))

                            Text("Start OTA server from a completed build")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.6))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Build Templates Section

    var buildTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "rectangle.stack.fill", title: "BUILD TEMPLATES", iconColor: Brand.violet)
                Spacer()
                Button { withAnimation { showBuildTemplates = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 4) {
                ForEach(templateStore.templates) { template in
                    CardContainer(padding: 8) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: template.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(.indigo)

                                Text(template.name)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.primary.opacity(0.9))

                                Spacer()

                                if let est = template.estimatedDuration {
                                    Text(est)
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                            }

                            if let desc = template.description {
                                Text(desc)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .lineLimit(1)
                            }

                            // Pipeline steps visualization
                            HStack(spacing: 3) {
                                ForEach(template.steps) { step in
                                    HStack(spacing: 2) {
                                        Image(systemName: step.type.icon)
                                            .font(.system(size: 8))
                                        Text(step.type.displayName)
                                            .font(.system(size: 8))
                                    }
                                    .foregroundColor(step.enabled ? .primary.opacity(0.5) : .secondary.opacity(0.3))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(step.enabled ? Color.indigo.opacity(0.06) : Color.gray.opacity(0.04))
                                    )

                                    if step.id != template.steps.last?.id {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 5))
                                            .foregroundColor(.secondary.opacity(0.2))
                                    }
                                }
                            }

                            // Run button
                            if let project = selectedProject {
                                HStack {
                                    Spacer()
                                    Button {
                                        runTemplate(template, for: project)
                                    } label: {
                                        Label("Run", systemImage: "play.fill")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.mini)
                                    .tint(Brand.violet)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    /// Execute a build template by converting steps into a build + post-build actions
    private func runTemplate(_ template: BuildTemplate, for project: AndroidProject) {
        let enabledSteps = template.steps.filter { $0.enabled }
        guard !enabledSteps.isEmpty else { return }

        // Determine build parameters from template steps
        var cleanFirst = false
        var outputFormat: BuildOutputFormat = selectedOutputFormat
        var postBuildActions: [PostBuildAction] = []

        for step in enabledSteps {
            switch step.type {
            case .clean:
                cleanFirst = true
            case .buildAPK:
                outputFormat = .apk
            case .buildAAB:
                outputFormat = .aab
            case .installOnDevice:
                postBuildActions.append(PostBuildAction(type: .installOnDevice, parameter: step.parameter))
            case .installOnAll:
                postBuildActions.append(PostBuildAction(type: .installOnAll))
            case .copyToFolder:
                postBuildActions.append(PostBuildAction(type: .copyToFolder, parameter: step.parameter))
            case .revealInFinder:
                postBuildActions.append(PostBuildAction(type: .openInFinder))
            case .generateQR:
                postBuildActions.append(PostBuildAction(type: .generateQR))
            case .startOTA:
                postBuildActions.append(PostBuildAction(type: .startOTA))
            case .runLogcat:
                postBuildActions.append(PostBuildAction(type: .runLogcat, parameter: step.parameter))
            case .gitTag:
                postBuildActions.append(PostBuildAction(type: .gitTag, parameter: step.parameter))
            }
        }

        // Enqueue the build with all post-build actions
        buildService.enqueueBuild(
            project: project,
            variant: selectedVariant,
            buildType: selectedBuildType,
            cleanFirst: cleanFirst,
            postBuildActions: postBuildActions.isEmpty ? nil : postBuildActions,
            outputFormat: outputFormat
        )
    }

    // MARK: - Environment Snapshot Section

    func environmentSnapshotSection(_ snapshot: BuildEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "gearshape.2.fill", title: "BUILD ENVIRONMENT", iconColor: .teal)
                Spacer()
                Button { withAnimation { showEnvironmentSnapshot = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            CardContainer(padding: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // Captured timestamp
                    HStack {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(snapshot.capturedAt, style: .relative)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("ago")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    Divider().opacity(0.2)

                    // Key-value pairs
                    ForEach(snapshot.details, id: \.label) { detail in
                        HStack {
                            Text(detail.label)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                                .frame(width: 80, alignment: .trailing)
                            Text(detail.value)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Git Info Section

    func gitInfoSection(project: AndroidProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "arrow.triangle.branch", title: "GIT STATUS", iconColor: Brand.warning)
                Spacer()
                Button { withAnimation { showGitInfo = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            CardContainer(padding: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    // Branch info
                    if let branch = gitService.branches[project.id] {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                                .foregroundColor(Brand.warning)
                            Text(branch)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.9))

                            if let hash = GitService.shortHash(at: project.path) {
                                Text(hash)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(Color.primary.opacity(0.04))
                                    )
                            }
                        }
                    }

                    // Change summary
                    if let changes = gitService.changeSummaries[project.id] {
                        if changes.hasUncommittedChanges {
                            HStack(spacing: 6) {
                                // Warning indicator
                                let level = changes.warningLevel
                                Circle()
                                    .fill(warningColor(level))
                                    .frame(width: 6, height: 6)

                                Text(changes.shortSummary)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.primary.opacity(0.7))

                                Text("(\(changes.totalChanges) file\(changes.totalChanges == 1 ? "" : "s"))")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }

                            // Ahead/behind
                            if changes.aheadCount > 0 || changes.behindCount > 0 {
                                HStack(spacing: 6) {
                                    if changes.aheadCount > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: 8))
                                            Text("\(changes.aheadCount) ahead")
                                                .font(.system(size: 8))
                                        }
                                        .foregroundColor(Brand.success.opacity(0.7))
                                    }
                                    if changes.behindCount > 0 {
                                        HStack(spacing: 2) {
                                            Image(systemName: "arrow.down")
                                                .font(.system(size: 8))
                                            Text("\(changes.behindCount) behind")
                                                .font(.system(size: 8))
                                        }
                                        .foregroundColor(Brand.error.opacity(0.7))
                                    }
                                }
                            }

                            // Warning message for building with dirty tree
                            if changes.warningLevel != .none {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(Brand.warning.opacity(0.7))
                                    Text("Building with uncommitted changes")
                                        .font(.system(size: 8))
                                        .foregroundColor(Brand.warning.opacity(0.7))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Brand.warning.opacity(0.06))
                                )
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(Brand.success.opacity(0.6))
                                Text("Working tree clean")
                                    .font(.system(size: 9))
                                    .foregroundColor(Brand.success.opacity(0.6))
                            }
                        }
                    }

                    // Recent tags
                    let tags = GitService.recentTags(at: project.path, count: 3)
                    if !tags.isEmpty {
                        Divider().opacity(0.2)
                        HStack(spacing: 4) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text("Tags:")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.5))
                            ForEach(tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(Brand.warning.opacity(0.7))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(
                                        Capsule().fill(Brand.warning.opacity(0.06))
                                    )
                            }
                        }
                    }
                }
            }
        }
    }

    private func warningColor(_ level: GitChangeSummary.WarningLevel) -> Color {
        switch level {
        case .none: return Brand.success
        case .low: return Brand.warning
        case .medium: return Brand.warning
        case .high: return Brand.error
        }
    }

    // MARK: - Emulator Quick Launch

    var emulatorLauncherSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "desktopcomputer", title: "EMULATORS", iconColor: Brand.success)
                Spacer()
                if emulatorService.isLoading {
                    ProgressView().scaleEffect(0.4)
                }
                Button {
                    emulatorService.refreshAVDs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                Button { withAnimation { showEmulatorLauncher = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if emulatorService.availableAVDs.isEmpty && !emulatorService.isLoading {
                CardContainer(padding: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No AVDs found. Create one in Android Studio.")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            } else {
                VStack(spacing: 3) {
                    ForEach(emulatorService.availableAVDs) { avd in
                        emulatorRow(avd)
                    }
                }
            }

            if let error = emulatorService.launchError {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Brand.error)
                    Text(error)
                        .font(.system(size: 8))
                        .foregroundColor(Brand.error)
                        .lineLimit(2)
                }
                .padding(.horizontal, 4)
            }

            // Cold boot toggle
            HStack(spacing: 4) {
                Toggle(isOn: $emulatorService.coldBootNext) {
                    Text("Cold boot next launch")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .toggleStyle(.checkbox)
                .scaleEffect(0.8)
            }
            .padding(.leading, 2)
        }
    }

    private func emulatorRow(_ avd: AVDEmulator) -> some View {
        CardContainer(padding: 6) {
            HStack(spacing: 8) {
                // Status indicator
                Image(systemName: avd.icon)
                    .font(.system(size: 10))
                    .foregroundColor(avd.isRunning ? Brand.success : .secondary.opacity(0.5))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(avd.name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(avd.displayTarget)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                        if !avd.abi.isEmpty {
                            Text(avd.abi)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.primary.opacity(0.04)))
                        }
                    }
                }

                Spacer()

                if emulatorService.isLaunching == avd.id {
                    ProgressView().scaleEffect(0.4)
                } else if avd.isRunning {
                    // Running — show stop button
                    Button {
                        emulatorService.stopEmulator(avdName: avd.id)
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Brand.error.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Stop emulator")
                } else {
                    // Not running — show launch button
                    HStack(spacing: 4) {
                        Button {
                            emulatorService.launchEmulator(avdName: avd.id)
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(Brand.success.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        .help("Launch emulator")

                        Menu {
                            Button("Cold Boot") {
                                emulatorService.coldBootNext = true
                                emulatorService.launchEmulator(avdName: avd.id)
                            }
                            Button("Wipe Data & Launch") {
                                emulatorService.wipeAndLaunch(avdName: avd.id)
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.4))
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 16)
                    }
                }
            }
        }
    }

    // MARK: - Build Cache Analytics

    var cacheAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "chart.bar.fill", title: "BUILD CACHE", iconColor: .mint)
                Spacer()
                if cacheAnalyticsService.isAnalyzing {
                    ProgressView().scaleEffect(0.4)
                }
                // Re-analyze button
                if let lastBuild = buildService.buildHistory.first {
                    Button {
                        _ = cacheAnalyticsService.analyzeBuildLog(lastBuild.logOutput)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Re-analyze last build")
                }
                Button { withAnimation { showCacheAnalytics = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if let report = cacheAnalyticsService.latestReport {
                cacheReportView(report)
            } else {
                CardContainer(padding: 10) {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.3))
                        Text("No build data yet")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Run a build to see cache analytics")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func cacheReportView(_ report: BuildCacheReport) -> some View {
        VStack(spacing: 4) {
            // Cache hit rate — the hero metric
            CardContainer(padding: 8) {
                VStack(spacing: 6) {
                    HStack {
                        Text("Cache Hit Rate")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.6))
                        Spacer()
                        Text(report.hitRateFormatted)
                            .font(Brand.titleFont(16))
                            .foregroundStyle(cacheHitColor(report.cacheHitRate))
                    }

                    // Visual bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.primary.opacity(0.06))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [Brand.success, Brand.accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * report.cacheHitRate)
                        }
                    }
                    .frame(height: 6)

                    // Task breakdown row
                    HStack(spacing: 0) {
                        cacheStatPill(count: report.cachedTasks, label: "Cached", color: Brand.success)
                        cacheStatPill(count: report.upToDateTasks, label: "Up-to-date", color: Brand.accent)
                        cacheStatPill(count: report.executedTasks, label: "Executed", color: Brand.warning)
                        cacheStatPill(count: report.skippedTasks + report.noSourceTasks, label: "Skipped", color: .secondary)
                    }
                }
            }

            // Duration info
            if report.totalDuration > 0 {
                CardContainer(padding: 6) {
                    HStack(spacing: 12) {
                        VStack(spacing: 1) {
                            Text(report.durationFormatted)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            Text("Total")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        if report.configurationTime > 0 {
                            VStack(spacing: 1) {
                                Text(String(format: "%.1fs", report.configurationTime))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                Text("Config")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        Spacer()
                        Text("\(report.totalTasks) tasks")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                }
            }

            // Slowest tasks
            if !report.slowestTasks.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Slowest Tasks")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.leading, 2)
                        .padding(.top, 2)

                    ForEach(report.slowestTasks.prefix(5)) { task in
                        HStack(spacing: 4) {
                            Text(task.taskPath)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.head)
                            Spacer()
                            Text(task.durationFormatted)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(Brand.warning)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func cacheStatPill(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(count)")
                .font(Brand.sectionFont(10, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 6, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func cacheHitColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return Brand.success }
        if rate >= 0.5 { return Brand.warning }
        return Brand.error
    }

    // MARK: - Crash Log Symbolication

    var crashSymbolicatorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(icon: "ladybug.fill", title: "CRASH SYMBOLICATION", iconColor: Brand.error)
                Spacer()
                if crashSymbolicator.isProcessing {
                    ProgressView().scaleEffect(0.4)
                }
                Button { withAnimation { showCrashSymbolicator = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // Mapping file status
            CardContainer(padding: 6) {
                HStack(spacing: 6) {
                    Image(systemName: mappingService.loadedFilePath != nil ? "checkmark.circle.fill" : "doc.text")
                        .font(.system(size: 9))
                        .foregroundColor(mappingService.loadedFilePath != nil ? Brand.success : .secondary.opacity(0.4))

                    if let path = mappingService.loadedFilePath {
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                            Text("\(mappingService.classCount) classes, \(mappingService.memberCount) members")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                    } else {
                        Text("No mapping loaded")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.5))
                    }

                    Spacer()

                    // Load mapping button
                    Button {
                        let panel = NSOpenPanel()
                        panel.title = "Select mapping.txt"
                        panel.allowedContentTypes = [.plainText]
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            mappingService.loadMapping(from: url.path)
                            crashSymbolicator.recordMappingPath(url.path)
                        }
                    } label: {
                        Text(mappingService.loadedFilePath != nil ? "Change" : "Load")
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Brand.primary.opacity(0.1)))
                            .foregroundColor(Brand.primary)
                    }
                    .buttonStyle(.plain)

                    // Auto-find mapping files if project is selected
                    if let project = selectedProject {
                        Button {
                            let found = crashSymbolicator.findMappingFiles(projectPath: project.path)
                            if let first = found.first {
                                mappingService.loadMapping(from: first)
                                crashSymbolicator.recordMappingPath(first)
                            }
                        } label: {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 9))
                                .foregroundColor(Brand.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Auto-find mapping files in project")
                    }
                }
            }

            // Input area
            VStack(alignment: .leading, spacing: 3) {
                Text("Paste stack trace:")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))

                TextEditor(text: $crashTraceInput)
                    .font(.system(size: 8, design: .monospaced))
                    .frame(height: 80)
                    .scrollContentBackground(.hidden)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topLeading) {
                        if crashTraceInput.isEmpty {
                            Text("java.lang.NullPointerException\n    at a.b.c.d(SourceFile:42)\n    at e.f.g(SourceFile:17)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.25))
                                .padding(6)
                                .allowsHitTesting(false)
                        }
                    }
            }

            // Action buttons
            HStack(spacing: 6) {
                Button {
                    guard !crashTraceInput.isEmpty else { return }
                    _ = crashSymbolicator.symbolicate(trace: crashTraceInput, using: mappingService)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 9))
                        Text("Symbolicate")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Brand.primary.opacity(0.15)))
                    .foregroundColor(Brand.primary)
                }
                .buttonStyle(.plain)
                .disabled(crashTraceInput.isEmpty || mappingService.entries.isEmpty)

                Button {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        crashTraceInput = clip
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 8))
                        Text("Paste")
                            .font(.system(size: 8))
                    }
                    .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)

                if !crashTraceInput.isEmpty {
                    Button {
                        crashTraceInput = ""
                        crashSymbolicator.currentResult = nil
                    } label: {
                        Text("Clear")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !crashSymbolicator.history.isEmpty {
                    Text("\(crashSymbolicator.history.count) in history")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            // Result display
            if let result = crashSymbolicator.currentResult {
                crashResultView(result)
            }
        }
    }

    private func crashResultView(_ result: SymbolicatedCrash) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Resolution header
            HStack(spacing: 6) {
                Image(systemName: result.resolvedCount > 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundColor(result.resolvedCount > 0 ? Brand.success : Brand.error)
                Text(result.resolutionFormatted)
                    .font(.system(size: 9, weight: .medium))

                if let exception = result.exceptionType {
                    Text(exception)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Brand.error)
                        .lineLimit(1)
                        .truncationMode(.head)
                }

                Spacer()

                // Copy result
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.symbolicatedTrace, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Copy symbolicated trace")
            }

            // Symbolicated output
            ScrollView(.vertical, showsIndicators: true) {
                Text(result.symbolicatedTrace)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            .frame(height: 100)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )

            // Mapping info footer
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 8))
                Text("via \(result.mappingFile)")
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary.opacity(0.4))
        }
    }

    // MARK: - Feedback Section

    var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Brand.heroGradient)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Send Feedback")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Help us improve \(Brand.appName)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { withAnimation { showFeedback = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 2)

            // Success banner
            if feedbackSent {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Brand.success)
                    Text("Feedback sent! Thank you for helping improve Ketok.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Brand.success)
                    Spacer()
                    Button {
                        withAnimation { feedbackSent = false }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Brand.success.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Brand.success.opacity(0.2), lineWidth: 0.5)
                )
            }

            // Feedback type picker
            VStack(alignment: .leading, spacing: 4) {
                Text("TYPE")
                    .font(Brand.sectionFont(9))
                    .foregroundColor(Brand.primary.opacity(0.7))
                    .tracking(1.2)

                HStack(spacing: 4) {
                    ForEach(FeedbackType.allCases) { type in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                feedbackType = type
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 8))
                                Text(type.rawValue)
                                    .font(.system(size: 8, weight: feedbackType == type ? .semibold : .regular))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(feedbackType == type ? type.color.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        feedbackType == type ? type.color.opacity(0.3) : Color.primary.opacity(0.08),
                                        lineWidth: 0.5
                                    )
                            )
                            .foregroundColor(feedbackType == type ? type.color : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Rating
            VStack(alignment: .leading, spacing: 4) {
                Text("RATING")
                    .font(Brand.sectionFont(9))
                    .foregroundColor(Brand.primary.opacity(0.7))
                    .tracking(1.2)

                HStack(spacing: 2) {
                    ForEach(FeedbackRating.allCases) { rating in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                feedbackRating = rating
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(rating.emoji)
                                    .font(.system(size: 16))
                                    .scaleEffect(feedbackRating == rating ? 1.15 : 0.9)
                                Text(rating.label)
                                    .font(.system(size: 8, weight: feedbackRating == rating ? .semibold : .regular))
                                    .foregroundColor(feedbackRating == rating ? .primary : .secondary.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(feedbackRating == rating ? Brand.primary.opacity(0.08) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        feedbackRating == rating ? Brand.primary.opacity(0.2) : Color.clear,
                                        lineWidth: 0.5
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Message
            VStack(alignment: .leading, spacing: 4) {
                Text("MESSAGE")
                    .font(Brand.sectionFont(9))
                    .foregroundColor(Brand.primary.opacity(0.7))
                    .tracking(1.2)

                ZStack(alignment: .topLeading) {
                    if feedbackMessage.isEmpty {
                        Text("Describe your feedback, bug, or feature idea...")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.35))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                    }

                    TextEditor(text: $feedbackMessage)
                        .font(.system(size: 9))
                        .scrollContentBackground(.hidden)
                        .padding(2)
                }
                .frame(height: 70)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
            }

            // Include system info toggle
            HStack(spacing: 6) {
                Toggle(isOn: $feedbackIncludeSystemInfo) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                        Text("Include system info")
                            .font(.system(size: 9))
                    }
                    .foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Spacer()

                Text("\(feedbackMessage.count) chars")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.35))
            }

            // Action buttons
            HStack(spacing: 6) {
                // Send via email
                Button {
                    feedbackService.submitViaEmail(
                        type: feedbackType,
                        rating: feedbackRating,
                        message: feedbackMessage,
                        includeSystemInfo: feedbackIncludeSystemInfo
                    )
                    withAnimation {
                        feedbackSent = true
                        feedbackMessage = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 9))
                        Text("Send via Email")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Brand.heroGradient)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

                // Save locally
                Button {
                    if let url = feedbackService.saveLocally(
                        type: feedbackType,
                        rating: feedbackRating,
                        message: feedbackMessage,
                        includeSystemInfo: feedbackIncludeSystemInfo
                    ) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    withAnimation {
                        feedbackSent = true
                        feedbackMessage = ""
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 9))
                        Text("Save")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                .disabled(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(feedbackMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }

            // History
            if !feedbackService.history.isEmpty {
                Divider().opacity(0.3)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recent Feedback (\(feedbackService.history.count))")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.5))
                        Spacer()
                        Button {
                            feedbackService.clearHistory()
                        } label: {
                            Text("Clear")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary.opacity(0.35))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(feedbackService.history.prefix(5)) { entry in
                        feedbackHistoryRow(entry)
                    }
                }
            }
        }
        .padding(10)
        .brandedCard()
    }

    private func feedbackHistoryRow(_ entry: FeedbackEntry) -> some View {
        HStack(spacing: 6) {
            let type = FeedbackType(rawValue: entry.type) ?? .generalFeedback
            Image(systemName: type.icon)
                .font(.system(size: 8))
                .foregroundColor(type.color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message.prefix(60) + (entry.message.count > 60 ? "..." : ""))
                    .font(.system(size: 8))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(entry.type)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(type.color)

                    Text("·")
                        .foregroundColor(.secondary.opacity(0.3))

                    let rating = FeedbackRating(rawValue: entry.rating) ?? .okay
                    Text(rating.emoji)
                        .font(.system(size: 8))

                    Text("·")
                        .foregroundColor(.secondary.opacity(0.3))

                    Text(entry.timestamp, style: .relative)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.4))
                }
            }

            Spacer()

            Image(systemName: entry.submitted ? "envelope.fill" : "square.and.arrow.down.fill")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.02))
        )
    }

    // MARK: - Version Bumper Section

    var versionBumperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(Brand.accent)
                    .font(.system(size: 11, weight: .semibold))
                Text("Version Bumper")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { withAnimation { showVersionBumper = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // Current version display
            if let version = versionBumperService.currentVersion {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Version")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("v\(version.versionName)")
                            .font(Brand.titleFont(16))
                            .foregroundColor(Brand.primary)
                    }

                    Divider().frame(height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Build Code")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("#\(version.versionCode)")
                            .font(Brand.titleFont(16))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))

                // Bump type picker
                Text("Bump Type")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    ForEach(VersionBumpType.allCases) { type in
                        Button {
                            selectedBumpType = type
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: type.icon)
                                    .font(.system(size: 10))
                                    .foregroundColor(selectedBumpType == type ? .white : Brand.accent)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(type.rawValue)
                                        .font(.system(size: 10, weight: .medium))
                                    Text(type == .custom ? "Set version manually" : "\(version.versionName) → \(version.bumped(type))")
                                        .font(.system(size: 8))
                                        .foregroundColor(selectedBumpType == type ? .white.opacity(0.8) : .secondary)
                                }

                                Spacer()

                                if selectedBumpType == type {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(selectedBumpType == type ? Brand.accent : Color.primary.opacity(0.03))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Custom version input
                if selectedBumpType == .custom {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Version")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("1.2.3", text: $customVersionInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Code")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            TextField("\(version.nextVersionCode)", text: $customCodeInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10))
                        }
                    }
                }

                // Options
                HStack(spacing: 12) {
                    Toggle(isOn: $autoIncrementCode) {
                        Text("Auto-increment code")
                            .font(.system(size: 9))
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $createGitTag) {
                        Text("Create git tag")
                            .font(.system(size: 9))
                    }
                    .toggleStyle(.checkbox)
                }

                // Preview
                if selectedBumpType != .custom {
                    let newVer = version.bumped(selectedBumpType)
                    let newCode = autoIncrementCode ? version.nextVersionCode : version.versionCode
                    HStack(spacing: 4) {
                        Text("v\(version.versionName) #\(version.versionCode)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text("v\(newVer) #\(newCode)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(Brand.accent)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Brand.accent.opacity(0.06)))
                }

                // Bump button
                Button {
                    guard let project = selectedProject else { return }
                    versionBumperService.bumpVersion(
                        project: project,
                        bumpType: selectedBumpType,
                        customVersion: selectedBumpType == .custom ? customVersionInput : nil,
                        customCode: selectedBumpType == .custom ? customCodeInput : nil,
                        autoIncrementCode: autoIncrementCode,
                        createGitTag: createGitTag
                    )
                } label: {
                    HStack {
                        if versionBumperService.isProcessing {
                            ProgressView()
                                .scaleEffect(0.5)
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 10))
                        }
                        Text("Bump Version")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [Brand.accent, Brand.accent.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .disabled(versionBumperService.isProcessing)

                // Result
                if let result = versionBumperService.lastBumpResult {
                    HStack(spacing: 6) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? Brand.success : Brand.error)
                            .font(.system(size: 10))

                        VStack(alignment: .leading, spacing: 1) {
                            if result.success {
                                Text("Bumped v\(result.oldVersion) → v\(result.newVersion)")
                                    .font(.system(size: 9, weight: .medium))
                                if result.gitTagCreated {
                                    Text("Git tag v\(result.newVersion) created")
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text(result.error ?? "Unknown error")
                                    .font(.system(size: 9))
                                    .foregroundColor(Brand.error)
                            }
                        }
                        Spacer()
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill((result.success ? Brand.success : Brand.error).opacity(0.06)))
                }

            } else {
                // No version detected
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(Brand.warning)
                        .font(.system(size: 10))
                    Text("Could not detect version. Check build.gradle or pubspec.yaml.")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Brand.warning.opacity(0.06)))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Brand.cardRadius).fill(Brand.surface))
    }

    // MARK: - Release Notes Section

    var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.teal)
                    .font(.system(size: 11, weight: .semibold))
                Text("Release Notes")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { withAnimation { showReleaseNotes = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            // Source picker
            HStack(spacing: 4) {
                ForEach(ReleaseNotesService.CommitSource.allCases) { source in
                    Button {
                        releaseNotesService.source = source
                        if let project = selectedProject {
                            releaseNotesService.loadCommits(project: project, source: source)
                        }
                    } label: {
                        Text(source.rawValue)
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(releaseNotesService.source == source ? Color.teal : Color.primary.opacity(0.04))
                            )
                            .foregroundColor(releaseNotesService.source == source ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if releaseNotesService.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Loading commits...")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if releaseNotesService.commits.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tray")
                        .foregroundColor(.secondary)
                    Text("No commits found")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            } else {
                // Commit list with toggles
                Text("\(releaseNotesService.commits.count) commits")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(releaseNotesService.commits.indices, id: \.self) { index in
                            let item = releaseNotesService.commits[index]
                            HStack(spacing: 5) {
                                Button {
                                    releaseNotesService.commits[index].include.toggle()
                                } label: {
                                    Image(systemName: item.include ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 10))
                                        .foregroundColor(item.include ? .teal : .secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)

                                Image(systemName: item.category.icon)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .frame(width: 12)

                                Text(item.commit.message)
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                                    .foregroundColor(item.include ? .primary : .secondary.opacity(0.4))

                                Spacer()

                                Text(item.commit.formattedDate)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary.opacity(0.4))
                            }
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                        }
                    }
                }
                .frame(maxHeight: 120)

                Divider().opacity(0.3)

                // Format & options
                HStack(spacing: 4) {
                    ForEach(ReleaseNotesFormat.allCases) { fmt in
                        Button {
                            releaseNotesFormat = fmt
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: fmt.icon)
                                    .font(.system(size: 8))
                                Text(fmt.rawValue)
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(releaseNotesFormat == fmt ? Color.teal : Color.primary.opacity(0.04))
                            )
                            .foregroundColor(releaseNotesFormat == fmt ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    Toggle(isOn: $releaseNotesGroupByCategory) {
                        Text("Group by type")
                            .font(.system(size: 8))
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $releaseNotesIncludeEmoji) {
                        Text("Emoji")
                            .font(.system(size: 8))
                    }
                    .toggleStyle(.checkbox)

                    Toggle(isOn: $releaseNotesIncludeAuthors) {
                        Text("Authors")
                            .font(.system(size: 8))
                    }
                    .toggleStyle(.checkbox)
                }

                // Generate button
                Button {
                    let version = versionBumperService.currentVersion?.versionName ?? selectedProject?.detectedVersionName
                    releaseNotesService.generate(
                        projectName: selectedProject?.name ?? "App",
                        version: version,
                        format: releaseNotesFormat,
                        includeAuthors: releaseNotesIncludeAuthors,
                        includeEmoji: releaseNotesIncludeEmoji,
                        groupByCategory: releaseNotesGroupByCategory
                    )
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .font(.system(size: 10))
                        Text("Generate Release Notes")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [.teal, .teal.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                // Generated output
                if let notes = releaseNotesService.generatedNotes {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(notes.format.rawValue) · \(notes.commitCount) commits")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()

                            Button {
                                releaseNotesService.copyToClipboard()
                                releaseNotesCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    releaseNotesCopied = false
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: releaseNotesCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 8))
                                    Text(releaseNotesCopied ? "Copied!" : "Copy")
                                        .font(.system(size: 8, weight: .medium))
                                }
                                .foregroundColor(releaseNotesCopied ? Brand.success : .teal)
                            }
                            .buttonStyle(.plain)

                            Button {
                                if let project = selectedProject {
                                    _ = releaseNotesService.saveToFile(directory: project.path)
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.system(size: 8))
                                    Text("Save")
                                        .font(.system(size: 8, weight: .medium))
                                }
                                .foregroundColor(.teal)
                            }
                            .buttonStyle(.plain)
                        }

                        ScrollView {
                            Text(notes.content)
                                .font(.system(size: 8, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 140)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                    }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Brand.cardRadius).fill(Brand.surface))
    }

    // MARK: - Build Matrix Section

    var buildMatrixSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundColor(Brand.violet)
                    .font(.system(size: 11, weight: .semibold))
                Text("Build Matrix")
                    .font(.system(size: 11, weight: .semibold))

                if buildMatrixService.isRunning {
                    Text("\(buildMatrixService.completedCells)/\(buildMatrixService.totalCells)")
                        .font(Brand.mono(9, weight: .bold))
                        .foregroundColor(Brand.violet)
                }

                Spacer()
                Button { withAnimation { showBuildMatrix = false } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            if let project = selectedProject {
                // Variant selection
                Text("Variants")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)

                FlowLayout(spacing: 4) {
                    ForEach(project.buildVariants, id: \.self) { variant in
                        Button {
                            if buildMatrixService.selectedVariants.contains(variant) {
                                buildMatrixService.selectedVariants.remove(variant)
                            } else {
                                buildMatrixService.selectedVariants.insert(variant)
                            }
                            buildMatrixService.buildMatrix(project: project)
                        } label: {
                            Text(variant)
                                .font(.system(size: 8, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(buildMatrixService.selectedVariants.contains(variant)
                                              ? Brand.violet : Color.primary.opacity(0.04))
                                )
                                .foregroundColor(buildMatrixService.selectedVariants.contains(variant)
                                                 ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Build type selection
                Text("Build Types")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    ForEach(project.buildTypes, id: \.self) { type in
                        Button {
                            if buildMatrixService.selectedBuildTypes.contains(type) {
                                buildMatrixService.selectedBuildTypes.remove(type)
                            } else {
                                buildMatrixService.selectedBuildTypes.insert(type)
                            }
                            buildMatrixService.buildMatrix(project: project)
                        } label: {
                            Text(type)
                                .font(.system(size: 8, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(buildMatrixService.selectedBuildTypes.contains(type)
                                              ? Brand.violet : Color.primary.opacity(0.04))
                                )
                                .foregroundColor(buildMatrixService.selectedBuildTypes.contains(type)
                                                 ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Format selection
                HStack(spacing: 8) {
                    Text("Format")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)

                    ForEach([BuildOutputFormat.apk, .aab], id: \.rawValue) { format in
                        Button {
                            if buildMatrixService.selectedFormats.contains(format) {
                                if buildMatrixService.selectedFormats.count > 1 {
                                    buildMatrixService.selectedFormats.remove(format)
                                }
                            } else {
                                buildMatrixService.selectedFormats.insert(format)
                            }
                            buildMatrixService.buildMatrix(project: project)
                        } label: {
                            Text(format.rawValue.uppercased())
                                .font(.system(size: 8, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(buildMatrixService.selectedFormats.contains(format)
                                              ? Brand.violet : Color.primary.opacity(0.04))
                                )
                                .foregroundColor(buildMatrixService.selectedFormats.contains(format)
                                                 ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Toggle(isOn: $buildMatrixService.cleanFirst) {
                        Text("Clean first")
                            .font(.system(size: 8))
                    }
                    .toggleStyle(.checkbox)
                }

                // Matrix summary
                HStack(spacing: 8) {
                    Text("\(buildMatrixService.totalCells) builds")
                        .font(Brand.mono(9, weight: .bold))
                        .foregroundColor(Brand.violet)

                    if buildMatrixService.isRunning {
                        ProgressView(value: buildMatrixService.progress)
                            .progressViewStyle(.linear)
                            .tint(Brand.violet)

                        Text(buildMatrixService.totalElapsed)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Matrix grid
                if !buildMatrixService.cells.isEmpty {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(buildMatrixService.cells) { cellStatus in
                                HStack(spacing: 6) {
                                    // Status icon
                                    Group {
                                        switch cellStatus.state {
                                        case .building:
                                            ProgressView()
                                                .scaleEffect(0.4)
                                                .frame(width: 14, height: 14)
                                        default:
                                            Image(systemName: cellStatus.state.icon)
                                                .font(.system(size: 10))
                                                .foregroundColor(matrixCellColor(cellStatus.state))
                                                .frame(width: 14)
                                        }
                                    }

                                    // Cell name
                                    Text(cellStatus.cell.displayName)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)

                                    Text(cellStatus.cell.outputFormat.rawValue.uppercased())
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.04)))

                                    Spacer()

                                    // Time / error
                                    if case .failed(let error) = cellStatus.state {
                                        Text(error.prefix(30))
                                            .font(.system(size: 8))
                                            .foregroundColor(Brand.error)
                                            .lineLimit(1)
                                    }

                                    Text(cellStatus.formattedElapsed)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.02))
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }

                // Action buttons
                HStack(spacing: 6) {
                    if buildMatrixService.isRunning {
                        Button {
                            buildMatrixService.cancelMatrix()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 9))
                                Text("Cancel")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Brand.error.opacity(0.1)))
                            .foregroundColor(Brand.error)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            buildMatrixService.startMatrix(project: project, buildService: buildService)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text("Build All (\(buildMatrixService.totalCells))")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(LinearGradient(colors: [Brand.violet, Brand.violet.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                            )
                            .foregroundColor(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(buildMatrixService.totalCells == 0)
                    }
                }

                // Results summary (after completion)
                if !buildMatrixService.isRunning && buildMatrixService.completedCells > 0 {
                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Brand.success)
                                .font(.system(size: 9))
                            Text("\(buildMatrixService.successCount) passed")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(Brand.success)
                        }

                        if buildMatrixService.failCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(Brand.error)
                                    .font(.system(size: 9))
                                Text("\(buildMatrixService.failCount) failed")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Brand.error)
                            }
                        }

                        Spacer()

                        Text("Total: \(buildMatrixService.totalElapsed)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Brand.cardRadius).fill(Brand.surface))
    }

    private func matrixCellColor(_ state: MatrixCellState) -> Color {
        switch state {
        case .pending: return .secondary.opacity(0.3)
        case .building: return Brand.violet
        case .success: return Brand.success
        case .failed: return Brand.error
        case .skipped: return .secondary
        }
    }

    /// Simple flow layout for wrapping buttons
    private struct FlowLayout: Layout {
        var spacing: CGFloat = 4

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let result = arrange(proposal: proposal, subviews: subviews)
            return result.size
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            let result = arrange(proposal: proposal, subviews: subviews)
            for (index, position) in result.positions.enumerated() {
                subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
            }
        }

        private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
            let maxWidth = proposal.width ?? .infinity
            var positions: [CGPoint] = []
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
                maxHeight = max(maxHeight, y + rowHeight)
            }

            return (CGSize(width: maxWidth, height: maxHeight), positions)
        }
    }
}

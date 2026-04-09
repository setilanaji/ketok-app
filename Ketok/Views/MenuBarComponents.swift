import SwiftUI
// MARK: - Card Container

struct CardContainer<Content: View>: View {
    var padding: CGFloat = 10
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Brand.cardRadius)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Brand.cardRadius)
                    .strokeBorder(Brand.border.opacity(0.4), lineWidth: 0.5)
            )
    }
}

// MARK: - Adaptive Scroll View

struct AdaptiveScrollView<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: ContentHeightKey.self, value: geo.size.height)
                    }
                )
        }
        .frame(height: min(contentHeight, maxHeight))
        .scrollDisabled(contentHeight <= maxHeight)
        .onPreferenceChange(ContentHeightKey.self) { height in
            // Debounce to prevent rapid layout thrashing
            if abs(height - contentHeight) > 1 {
                contentHeight = height
            }
        }
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Animated Progress Bar

struct AnimatedProgressBar: View {
    let value: Double
    var tint: Color = Brand.success
    @State private var animatedValue: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.primary.opacity(0.05))
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.7), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * animatedValue))
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2.5))
        .onChange(of: value) { _, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedValue = newValue
            }
        }
        .onAppear { animatedValue = value }
    }
}

// MARK: - Elapsed Time View

struct ElapsedTimeView: View {
    let startTime: Date
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(formattedTime)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.6))
            .monospacedDigit()
            .onReceive(timer) { _ in
                elapsed = Date().timeIntervalSince(startTime)
            }
            .onAppear {
                elapsed = Date().timeIntervalSince(startTime)
            }
    }

    private var formattedTime: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Successful Build Item

struct SuccessfulBuildItem: Identifiable {
    let path: String
    let label: String
    var id: String { path }
}

// MARK: - Analysis Row

struct AnalysisRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
                Text(value)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Footer Button

struct FooterButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    var activeTint: Color = .accentColor
    let action: () -> Void

    @State private var isHovered = false

    private var foregroundColor: Color {
        isActive ? activeTint : (isHovered ? .primary : .secondary)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: isActive ? .medium : .regular))
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? activeTint.opacity(0.08) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Favorite Row

struct FavoriteRow: View {
    let favorite: FavoriteBuild
    let projectName: String
    let branch: String?
    let onBuild: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 10))
                .foregroundColor(Brand.warning)

            VStack(alignment: .leading, spacing: 2) {
                Text(projectName)
                    .font(.system(size: 11, weight: .medium))
                HStack(spacing: 4) {
                    Text(favorite.displayLabel)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if let branch = branch {
                        GitBranchBadge(branch: branch)
                    }
                }
            }

            Spacer()

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(4)
                        .background(Circle().fill(Color.primary.opacity(0.04)))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }

            Button(action: onBuild) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Brand.success)
                            .shadow(color: Brand.success.opacity(0.2), radius: 2, y: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Brand.warning.opacity(0.04) : Color.primary.opacity(0.02))
        )
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
        }
    }
}

// MARK: - Git Branch Badge

struct GitBranchBadge: View {
    let branch: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8, weight: .medium))
            Text(branch)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .lineLimit(1)
        }
        .foregroundColor(Brand.violet.opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(Brand.violet.opacity(0.07))
        )
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: ADBDevice
    let lastSuccessfulAPK: String?
    let isInstalling: Bool
    let onInstall: (String) -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: device.icon)
                    .font(.system(size: 13))
                    .foregroundColor(device.isOnline ? Brand.primary : .secondary.opacity(0.6))

                Circle()
                    .fill(device.isOnline ? Brand.success : Brand.warning)
                    .frame(width: 6, height: 6)
                    .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(device.displayName)
                    .font(.system(size: 10, weight: .medium))
                Text(device.isOnline ? "Connected" : device.state)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(device.isOnline ? Brand.success.opacity(0.8) : Brand.warning.opacity(0.8))
            }

            Spacer()

            if device.isOnline, let apkPath = lastSuccessfulAPK {
                if isInstalling {
                    ProgressView()
                        .scaleEffect(0.4)
                } else {
                    Button(action: { onInstall(apkPath) }) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 8))
                            Text("Install")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(Brand.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Brand.accent.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Project Row (Card Style)

struct ProjectRowView: View {
    let project: AndroidProject
    let isSelected: Bool
    @Binding var selectedVariant: String
    @Binding var selectedBuildType: String
    @Binding var selectedOutputFormat: BuildOutputFormat
    let branch: String?
    let isFavorite: Bool
    let onSelect: () -> Void
    let onBuild: () -> Void
    let onCleanBuild: () -> Void
    let onToggleFavorite: () -> Void
    let onRunTask: (GradleTask) -> Void

    @State private var isHovered = false
    @State private var isBuildHovered = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 0) {
                // Project header — always visible
                Button(action: onSelect) {
                    HStack(spacing: 10) {
                        // Project icon
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? project.projectType.tintColor.opacity(0.1) : Color.primary.opacity(0.03))
                                .frame(width: 32, height: 32)

                            Image(systemName: isSelected ? project.projectType.folderIcon : (project.isFlutter ? "bird" : "folder"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(isSelected ? project.projectType.tintColor : .secondary.opacity(0.6))
                                .contentTransition(.symbolEffect(.replace))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(project.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.primary)

                                // Project type badge
                                Text(project.projectType.displayName)
                                    .font(Brand.mono(8, weight: .bold))
                                    .foregroundColor(project.projectType.tintColor)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(project.projectType.tintColor.opacity(0.1))
                                    )

                                if let branch = branch {
                                    GitBranchBadge(branch: branch)
                                }
                            }
                            HStack(spacing: 4) {
                                if let module = project.appModulePath {
                                    Text(module)
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(project.projectType.tintColor.opacity(0.8))
                                }
                                Text(project.path)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.4))
                            .rotationEffect(.degrees(isSelected ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded build options
                if isSelected {
                    VStack(alignment: .leading, spacing: 10) {
                        Divider()
                            .padding(.vertical, 4)

                        // Variant / Flavor picker
                        VStack(alignment: .leading, spacing: 5) {
                            Text(project.isFlutter ? "FLAVOR" : "VARIANT")
                                .font(Brand.sectionFont(10))
                                .foregroundColor(Brand.primary.opacity(0.7))
                                .tracking(1.2)

                            VariantPicker(
                                options: project.buildVariants,
                                selection: $selectedVariant,
                                tint: project.projectType.tintColor
                            )
                        }

                        // Build type picker
                        VStack(alignment: .leading, spacing: 5) {
                            Text("BUILD TYPE")
                                .font(Brand.sectionFont(10))
                                .foregroundColor(Brand.primary.opacity(0.7))
                                .tracking(1.2)

                            VariantPicker(
                                options: project.buildTypes,
                                selection: $selectedBuildType,
                                tint: Brand.warning
                            )
                        }

                        // Output format picker (APK / AAB)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("OUTPUT FORMAT")
                                .font(Brand.sectionFont(10))
                                .foregroundColor(Brand.primary.opacity(0.7))
                                .tracking(1.2)

                            HStack(spacing: 4) {
                                ForEach([BuildOutputFormat.apk, .aab], id: \.rawValue) { format in
                                    OutputFormatPill(
                                        label: format.rawValue,
                                        isSelected: selectedOutputFormat == format,
                                        tint: format == .apk ? Brand.success : Brand.violet
                                    ) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            selectedOutputFormat = format
                                        }
                                    }
                                }
                                Spacer()
                            }
                        }

                        // Build button row
                        HStack(spacing: 6) {
                            Button(action: onBuild) {
                                HStack(spacing: 5) {
                                    Image(systemName: selectedOutputFormat == .aab ? "archivebox.fill" : "play.fill")
                                        .font(.system(size: 9))
                                    Text("Build \(selectedVariant) \(selectedBuildType) (\(selectedOutputFormat.rawValue))")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Brand.iconGradient)
                                        .shadow(color: Brand.primary.opacity(isBuildHovered ? 0.25 : 0.1), radius: isBuildHovered ? 6 : 3, y: 2)
                                )
                                .foregroundColor(.white)
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(isBuildHovered ? 1.01 : 1.0)
                            .onHover { h in
                                withAnimation(.easeOut(duration: 0.15)) { isBuildHovered = h }
                            }
                            .contextMenu {
                                Button(action: onCleanBuild) {
                                    Label("Clean & Build", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }

                            Button(action: onToggleFavorite) {
                                Image(systemName: isFavorite ? "star.fill" : "star")
                                    .font(.system(size: 12))
                                    .foregroundColor(isFavorite ? Brand.warning : .secondary.opacity(0.35))
                                    .padding(8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isFavorite ? Brand.warning.opacity(0.06) : Color.primary.opacity(0.03))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(isFavorite ? "Remove from favorites" : "Add to favorites")
                        }

                        // Quick actions
                        HStack(spacing: 5) {
                            QuickActionButton(icon: "trash", label: "Clean") {
                                onRunTask(.clean)
                            }
                            if project.isFlutter {
                                QuickActionButton(icon: "shippingbox", label: "Pub Get") {
                                    onRunTask(.pubGet)
                                }
                            }
                            QuickActionButton(icon: "folder", label: "Open") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
                            }
                            QuickActionButton(
                                icon: "magnifyingglass",
                                label: GradleTask.lint.displayName(for: project.projectType)
                            ) {
                                onRunTask(.lint)
                            }
                            QuickActionButton(icon: "checkmark.shield", label: "Test") {
                                onRunTask(.test)
                            }
                        }
                    }
                    .clipShape(Rectangle())
                    .transition(.opacity)
                }
            }
        }
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
        }
    }
}

// MARK: - Variant Picker (pill-style)

struct VariantPicker: View {
    let options: [String]
    @Binding var selection: String
    var tint: Color = .accentColor

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(options, id: \.self) { option in
                VariantPill(
                    label: option,
                    isSelected: selection == option,
                    tint: tint
                ) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selection = option
                    }
                }
            }
        }
    }
}

struct VariantPill: View {
    let label: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected
                            ? tint.opacity(0.12)
                            : isHovered ? Color.primary.opacity(0.04) : Color.clear
                        )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? tint.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .foregroundColor(isSelected ? tint : .secondary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = h }
        }
    }
}

// MARK: - Output Format Pill

struct OutputFormatPill: View {
    let label: String
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: label == "AAB" ? "archivebox" : "shippingbox")
                    .font(.system(size: 8, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .monospaced))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isSelected
                        ? tint.opacity(0.12)
                        : isHovered ? Color.primary.opacity(0.04) : Color.clear
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? tint.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .foregroundColor(isSelected ? tint : .secondary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = h }
        }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                Text(label)
                    .font(.system(size: 8, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundColor(isHovered ? .primary : .secondary.opacity(0.7))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(isHovered ? 0.06 : 0.03), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
        }
    }
}

// MARK: - Recent Build Row

struct RecentBuildRow: View {
    @ObservedObject var build: BuildStatus
    var devices: [ADBDevice] = []
    var onInstall: ((ADBDevice) -> Void)?
    var onQR: ((String) -> Void)?
    var onAnalyze: ((String) -> Void)?
    var onViewMapping: ((String) -> Void)?
    @State private var isHovered = false
    @State private var showFailLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(build.project.name)
                    .font(.system(size: 10, weight: .medium))
                HStack(spacing: 4) {
                    Text("\(build.variant)/\(build.buildType)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))

                    if build.endTime != nil {
                        Text(build.formattedDuration)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                    }

                    if let size = build.formattedAPKSize {
                        Text(size)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(Brand.primary.opacity(0.5))
                    }

                    if build.outputFormat == .aab {
                        Text("AAB")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(Brand.violet.opacity(0.7))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(Brand.violet.opacity(0.08))
                            )
                    }
                }
            }

            Spacer()

            if case .success(let apkPath) = build.state {
                HStack(spacing: 3) {
                    if isHovered {
                        // QR Code button
                        if let onQR = onQR {
                            buildActionButton(icon: "qrcode", tint: .indigo) { onQR(apkPath) }
                                .help("Generate QR code")
                        }

                        // Analyze button
                        if let onAnalyze = onAnalyze {
                            buildActionButton(icon: "doc.text.magnifyingglass", tint: Brand.warning) { onAnalyze(apkPath) }
                                .help("Analyze APK")
                        }

                        // Mapping file button
                        if build.hasMappingFile, let onViewMapping = onViewMapping, let mappingPath = build.mappingFilePath {
                            buildActionButton(icon: "map", tint: .cyan) { onViewMapping(mappingPath) }
                                .help("View ProGuard/R8 Mapping")
                        }

                        // Install on device
                        if !devices.isEmpty, let onInstall = onInstall {
                            Menu {
                                ForEach(devices) { device in
                                    Button(action: { onInstall(device) }) {
                                        Label(device.displayName, systemImage: device.icon)
                                    }
                                }
                            } label: {
                                Image(systemName: "arrow.down.to.line")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Brand.accent)
                                    .frame(width: 22, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Brand.accent.opacity(0.06)))
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 22)
                        }
                    }

                    // Output actions menu — always visible
                    Menu {
                        Button(action: {
                            let url = URL(fileURLWithPath: apkPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }) {
                            Label("Reveal in Finder", systemImage: "folder")
                        }

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(apkPath, forType: .string)
                        }) {
                            Label("Copy Path", systemImage: "doc.on.clipboard")
                        }

                        Button(action: {
                            let url = URL(fileURLWithPath: apkPath)
                            let picker = NSSharingServicePicker(items: [url])
                            if let window = NSApp.keyWindow, let contentView = window.contentView {
                                picker.show(relativeTo: .zero, of: contentView, preferredEdge: .minY)
                            }
                        }) {
                            Label("Share \(build.outputFormat.rawValue)...", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Text(build.outputFormat.rawValue)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(build.outputFormat == .aab ? Brand.violet : Brand.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill((build.outputFormat == .aab ? Brand.violet : Brand.success).opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .strokeBorder((build.outputFormat == .aab ? Brand.violet : Brand.success).opacity(0.12), lineWidth: 0.5)
                                    )
                            )
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 38)
                }
                .transition(.opacity)
            } else if case .failed = build.state {
                HStack(spacing: 3) {
                    // View log button
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            showFailLog.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: showFailLog ? "chevron.down" : "doc.text")
                                .font(.system(size: 8, weight: .medium))
                            Text("FAIL")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(Brand.error.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Brand.error.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("View build log")

                    // Copy log
                    if isHovered {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(build.logOutput, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 20, height: 20)
                                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                        .help("Copy full build log")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
        }

        // Failed build — error summary + expandable log
        if case .failed(let error) = build.state {
            // Error summary (always visible)
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(Brand.error.opacity(0.5))
                Text(error)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(Brand.error.opacity(0.7))
                    .lineLimit(showFailLog ? nil : 2)
                    .textSelection(.enabled)
            }
            .padding(.leading, 26)
            .padding(.top, 3)

            // Expandable full log
            if showFailLog {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("BUILD LOG")
                            .font(Brand.sectionFont(9))
                            .foregroundColor(Brand.primary.opacity(0.7))
                            .tracking(1.2)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(build.logOutput, forType: .string)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 8))
                                Text("Copy")
                                    .font(.system(size: 8, weight: .medium))
                            }
                            .foregroundColor(.secondary.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        Text(build.logOutput.suffix(5000))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(6)
                    }
                    .frame(height: 160)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .textBackgroundColor).opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Brand.error.opacity(0.1), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.leading, 26)
                .padding(.top, 4)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        }
        .padding(.vertical, 3)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
        }
    }

    private func buildActionButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch build.state {
        case .idle:
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 8, height: 8)
        case .building:
            ProgressView()
                .scaleEffect(0.35)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Brand.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(Brand.error)
        }
    }
}

// MARK: - Mapping Entry Row

struct MappingEntryRow: View {
    let entry: MappingEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: {
                withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.4))
                        .frame(width: 8)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.originalName)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.head)

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundColor(.cyan.opacity(0.5))
                            Text(entry.obfuscatedName)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    if !entry.members.isEmpty {
                        Text("\(entry.members.count)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.primary.opacity(0.03))
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 3)

            if isExpanded && !entry.members.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(entry.members.prefix(15))) { member in
                        HStack(spacing: 4) {
                            Image(systemName: member.memberType == .method ? "m.square" : "f.square")
                                .font(.system(size: 8))
                                .foregroundColor(member.memberType == .method ? Brand.primary.opacity(0.5) : Brand.warning.opacity(0.5))

                            Text(member.originalSignature)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Image(systemName: "arrow.right")
                                .font(.system(size: 5, weight: .bold))
                                .foregroundColor(.secondary.opacity(0.3))

                            Text(member.obfuscatedName)
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(.cyan.opacity(0.6))
                        }
                        .padding(.leading, 14)
                        .padding(.vertical, 1)
                    }
                    if entry.members.count > 15 {
                        Text("+ \(entry.members.count - 15) more members")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.leading, 14)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

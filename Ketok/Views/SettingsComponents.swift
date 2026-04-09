import SwiftUI
// MARK: - Settings Tab Button

struct SettingsTabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? Brand.primary : isHovered ? .primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Brand.primary.opacity(0.08) : isHovered ? Color.primary.opacity(0.03) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
        }
    }
}

// MARK: - Settings Action Button (Refresh, etc.)

struct SettingsActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false
    @State private var isSpinning = false

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) { isSpinning = true }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.3)) { isSpinning = false }
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(isHovered ? Brand.primary : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Brand.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
        }
    }
}

// MARK: - Settings Project Card

struct SettingsProjectCard: View {
    let project: AndroidProject
    let onRescan: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(spacing: 10) {
                // Status indicator with project type icon
                Image(systemName: project.hasGradlew ? project.projectType.folderIcon : "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(project.hasGradlew ? project.projectType.tintColor : Brand.warning)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))

                        Text(project.projectType.displayName)
                            .font(Brand.mono(8, weight: .bold))
                            .foregroundColor(project.projectType.tintColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(project.projectType.tintColor.opacity(0.1)))

                        if let module = project.appModulePath {
                            Text(module)
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Brand.primary.opacity(0.12)))
                                .foregroundColor(Brand.primary)
                        }
                    }
                    Text(project.path)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Action buttons
                HStack(spacing: 4) {
                    CardActionButton(icon: "arrow.triangle.2.circlepath", help: "Re-scan", action: onRescan)
                    CardActionButton(icon: "pencil", help: "Edit", action: onEdit)
                    CardActionButton(icon: "trash", help: "Remove", tint: Brand.error, action: onDelete)

                    // Expand toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                .opacity(isHovered || isExpanded ? 1 : 0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Expanded variant tags
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .padding(.horizontal, 12)

                    HStack(spacing: 4) {
                        Text("Variants:")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        FlowLayout(spacing: 4) {
                            ForEach(project.buildVariants, id: \.self) { variant in
                                Text(variant)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Brand.primary.opacity(0.12)))
                                    .foregroundColor(Brand.primary)
                            }
                        }
                    }
                    .padding(.horizontal, 12)

                    HStack(spacing: 4) {
                        Text("Types:")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        FlowLayout(spacing: 4) {
                            ForEach(project.buildTypes, id: \.self) { buildType in
                                Text(buildType)
                                    .font(.system(size: 9, weight: .medium))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(Brand.warning.opacity(0.12)))
                                    .foregroundColor(Brand.warning)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
        }
    }
}

// MARK: - Card Action Button (tiny icon buttons)

struct CardActionButton: View {
    let icon: String
    var help: String = ""
    var tint: Color = .secondary
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(isHovered ? tint : .secondary.opacity(0.7))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isHovered ? tint.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = h }
        }
    }
}

// MARK: - Environment Card

struct EnvironmentCard<Content: View>: View {
    let title: String
    let icon: String
    var tint: Color = Brand.primary
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(tint)
                    Text(title)
                        .font(Brand.mono(12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)

                content()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity
                    ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Environment Row

struct EnvRow: View {
    let label: String
    let value: String
    var ok: Bool = true

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)

            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(ok ? Brand.success : Brand.error.opacity(0.6))

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .foregroundColor(ok ? .primary : .secondary)

            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        )
        .onHover { h in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = h }
        }
    }
}

// MARK: - Environment Tag Row

struct EnvTagRow: View {
    let label: String
    let tags: [String]
    var tint: Color = Brand.success

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)

            FlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.12)))
                        .foregroundColor(tint)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - About Capability Row

struct AboutCapabilityRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.iconGradient)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Brand.primary.opacity(0.08))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Signing Config Card

struct SigningConfigCard: View {
    let config: SigningConfig
    let projectName: String
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: config.keystoreExists ? "key.fill" : "key.slash")
                    .font(.system(size: 14))
                    .foregroundColor(config.keystoreExists ? Brand.success : Brand.warning)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(config.name)
                            .font(.system(size: 13, weight: .semibold))

                        Text(projectName)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Brand.violet.opacity(0.12)))
                            .foregroundColor(Brand.violet)
                    }
                    Text(config.keystoreFileName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                HStack(spacing: 4) {
                    CardActionButton(icon: "trash", help: "Remove", tint: Brand.error, action: onDelete)

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isExpanded.toggle() }
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.5))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
                .opacity(isHovered || isExpanded ? 1 : 0.4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().padding(.horizontal, 12)

                    VStack(spacing: 4) {
                        SigningDetailRow(label: "Keystore", value: config.keystorePath)
                        SigningDetailRow(label: "Key Alias", value: config.keyAlias)
                        SigningDetailRow(label: "Password", value: "••••••••")
                        SigningDetailRow(label: "Status", value: config.keystoreExists ? "Keystore found" : "Keystore not found",
                                       ok: config.keystoreExists)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.95, anchor: .top))
                ))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Brand.cardRadius)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { h in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = h }
        }
    }
}

struct SigningDetailRow: View {
    let label: String
    let value: String
    var ok: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ok ? .primary : Brand.warning)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer()
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Add Signing Config Button (with popover form)

struct AddSigningConfigButton: View {
    let projectStore: ProjectStore
    @ObservedObject var signingStore: SigningConfigStore

    @State private var showForm = false
    @State private var configName = ""
    @State private var keystorePath = ""
    @State private var keystorePassword = ""
    @State private var keyAlias = ""
    @State private var keyPassword = ""
    @State private var selectedProjectId: UUID? = nil
    @State private var useSamePassword = true

    var body: some View {
        Button(action: { showForm = true }) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11))
                Text("Add Keystore")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(Brand.primary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showForm, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Add Keystore")
                    .font(Brand.titleFont(14))

                // Name
                VStack(alignment: .leading, spacing: 4) {
                    Text("Config Name")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("e.g. Production, Upload Key", text: $configName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Project scope
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apply To")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Picker("", selection: $selectedProjectId) {
                        Text("All Projects").tag(nil as UUID?)
                        ForEach(projectStore.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                // Keystore path
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keystore File (.jks / .keystore)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        TextField("/path/to/keystore.jks", text: $keystorePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Button("Browse") {
                            let panel = NSOpenPanel()
                            panel.allowedContentTypes = [.data]
                            panel.allowsMultipleSelection = false
                            panel.title = "Select Keystore File"
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url {
                                keystorePath = url.path
                            }
                        }
                        .font(.system(size: 11))
                    }
                }

                // Key alias
                VStack(alignment: .leading, spacing: 4) {
                    Text("Key Alias")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("e.g. upload-key, my-alias", text: $keyAlias)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Keystore password
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keystore Password")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    SecureField("Keystore password", text: $keystorePassword)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }

                // Key password toggle + field
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: $useSamePassword) {
                        Text("Key password same as keystore password")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .toggleStyle(.checkbox)

                    if !useSamePassword {
                        SecureField("Key password", text: $keyPassword)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }

                // Keychain info
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Brand.success)
                    Text("Passwords are stored in macOS Keychain")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                // Actions
                HStack {
                    Button("Cancel") {
                        resetForm()
                        showForm = false
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                    Spacer()

                    Button(action: saveConfig) {
                        Text("Add Keystore")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isValid ? Brand.primary : Color.secondary.opacity(0.3))
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid)
                }
            }
            .padding(16)
            .frame(width: 340)
        }
    }

    private var isValid: Bool {
        !configName.isEmpty && !keystorePath.isEmpty && !keyAlias.isEmpty && !keystorePassword.isEmpty
    }

    private func saveConfig() {
        let config = SigningConfig(
            name: configName,
            keystorePath: keystorePath,
            keystorePassword: keystorePassword,
            keyAlias: keyAlias,
            keyPassword: useSamePassword ? keystorePassword : keyPassword,
            projectId: selectedProjectId
        )
        signingStore.addConfig(config)
        resetForm()
        showForm = false
    }

    private func resetForm() {
        configName = ""
        keystorePath = ""
        keystorePassword = ""
        keyAlias = ""
        keyPassword = ""
        selectedProjectId = nil
        useSamePassword = true
    }
}

// MARK: - Simple Flow Layout for tags

struct FlowLayout: Layout {
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
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

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
            totalHeight = y + rowHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Add Project Sheet

struct AddProjectView: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var path = ""
    @State private var variants = ""
    @State private var buildTypes = ""
    @State private var detectedEnv: ProjectEnvironment?
    @State private var isScanning = false
    let onAdd: (AndroidProject) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Project")
                        .font(Brand.titleFont(16))
                    Text("Configure a new Android project")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Project name
                    SettingsTextField(label: "Project Name", placeholder: "My Android App", text: $name)

                    // Path with browse
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Path")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("~/path/to/android/project", text: $path)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Button(action: browseForFolder) {
                                HStack(spacing: 3) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 10))
                                    Text("Browse")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Auto-detected info
                    if isScanning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Scanning project...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .transition(.opacity)
                    }

                    if let env = detectedEnv {
                        EnvironmentCard(title: "Auto-Detected", icon: "sparkle", tint: Brand.violet) {
                            VStack(spacing: 6) {
                                if let module = env.appModulePath {
                                    EnvRow(label: "App module", value: module, ok: true)
                                }
                                EnvRow(label: "Gradle", value: env.gradleVersionDisplay, ok: env.gradleVersion != nil)
                                if let agp = env.agpVersion {
                                    EnvRow(label: "AGP", value: agp, ok: true)
                                }
                                if !env.buildVariants.isEmpty {
                                    EnvTagRow(label: "Variants", tags: env.buildVariants, tint: Brand.primary)
                                }
                                EnvTagRow(label: "Build types", tags: env.buildTypes, tint: Brand.warning)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Manual overrides
                    // Read-only variants and build types (detected from project)
                    if !variants.isEmpty {
                        ReadOnlyTagRow(label: "Build Variants", tags: variants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, tint: Brand.primary)
                    }
                    if !buildTypes.isEmpty {
                        ReadOnlyTagRow(label: "Build Types", tags: buildTypes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, tint: Brand.warning)
                    }
                }
                .padding(20)
            }

            Divider()

            // Action buttons
            HStack {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: {
                    var project = AndroidProject(
                        name: name,
                        path: path,
                        buildVariants: variants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                        buildTypes: buildTypes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                        appModulePath: detectedEnv?.appModulePath
                    )
                    if project.appModulePath == nil {
                        project.autoDetectSettings()
                    }
                    onAdd(project)
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11))
                        Text("Add Project")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(name.isEmpty || path.isEmpty
                                ? Color.secondary.opacity(0.1)
                                : Brand.primary
                            )
                    )
                    .foregroundColor(name.isEmpty || path.isEmpty ? .secondary : .white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || path.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 520)
        .onChange(of: path) { _, newPath in
            scanProject(at: newPath)
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select Android project root (containing build.gradle)"
        // Open at the current path if it exists, otherwise home directory
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            panel.directoryURL = URL(fileURLWithPath: path)
        } else {
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
            if name.isEmpty {
                name = url.lastPathComponent
            }
        }
    }

    private func scanProject(at projectPath: String) {
        guard !projectPath.isEmpty else { return }
        isScanning = true

        DispatchQueue.global(qos: .userInitiated).async {
            let env = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: projectPath)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    detectedEnv = env
                    isScanning = false
                }
                if !env.buildVariants.isEmpty {
                    variants = env.buildVariants.joined(separator: ", ")
                }
                if !env.buildTypes.isEmpty {
                    buildTypes = env.buildTypes.joined(separator: ", ")
                }
            }
        }
    }
}

// MARK: - Edit Project Sheet

struct EditProjectView: View {
    @Environment(\.dismiss) var dismiss
    @State var project: AndroidProject
    let onSave: (AndroidProject) -> Void

    @State private var variantsText: String = ""
    @State private var buildTypesText: String = ""
    @State private var detectedEnv: ProjectEnvironment?
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit Project")
                        .font(Brand.titleFont(16))
                    Text(project.name)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsTextField(label: "Project Name", placeholder: "My Android App", text: $project.name)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Path")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField("", text: $project.path)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12, design: .monospaced))
                            Button(action: browseForFolder) {
                                HStack(spacing: 3) {
                                    Image(systemName: "folder.badge.plus")
                                        .font(.system(size: 10))
                                    Text("Browse")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.primary.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Detected info
                    if let env = detectedEnv {
                        EnvironmentCard(title: "Detected from project files", icon: "sparkle", tint: Brand.violet) {
                            VStack(spacing: 6) {
                                if let module = env.appModulePath {
                                    EnvRow(label: "App module", value: module, ok: true)
                                }
                                EnvRow(label: "Gradle", value: env.gradleVersionDisplay, ok: env.gradleVersion != nil)
                                if let agp = env.agpVersion {
                                    EnvRow(label: "AGP", value: agp, ok: true)
                                }
                                if let java = env.javaVersion {
                                    EnvRow(label: "Java", value: java, ok: true)
                                }
                            }
                        }
                    }

                    // Read-only variants and build types (detected from project)
                    if !variantsText.isEmpty {
                        ReadOnlyTagRow(label: "Build Variants", tags: variantsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, tint: Brand.primary)
                    }
                    if !buildTypesText.isEmpty {
                        ReadOnlyTagRow(label: "Build Types", tags: buildTypesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, tint: Brand.warning)
                    }

                    // Output file name
                    OutputFileNameSection(project: $project)

                    // Output copy folder
                    OutputCopyFolderSection(project: $project)

                    // Rescan button
                    SettingsActionButton(icon: "arrow.triangle.2.circlepath", label: "Re-scan from project files") {
                        rescan()
                    }
                }
                .padding(20)
            }

            Divider()

            // Action buttons
            HStack {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(action: {
                    project.buildVariants = variantsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    project.buildTypes = buildTypesText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    if let module = detectedEnv?.appModulePath {
                        project.appModulePath = module
                    }
                    onSave(project)
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Save Changes")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Brand.primary)
                    )
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500, height: 480)
        .onAppear {
            variantsText = project.buildVariants.joined(separator: ", ")
            buildTypesText = project.buildTypes.joined(separator: ", ")
            rescan()
        }
    }

    private func rescan() {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async {
            let env = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    detectedEnv = env
                    isScanning = false
                }
                if !env.buildVariants.isEmpty {
                    variantsText = env.buildVariants.joined(separator: ", ")
                }
                if !env.buildTypes.isEmpty {
                    buildTypesText = env.buildTypes.joined(separator: ", ")
                }
            }
        }
    }

    private func browseForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Select Android project root (containing build.gradle)"
        // Open at the current project path if it exists
        if !project.path.isEmpty, FileManager.default.fileExists(atPath: project.path) {
            panel.directoryURL = URL(fileURLWithPath: project.path)
        } else {
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        }
        if panel.runModal() == .OK, let url = panel.url {
            project.path = url.path
            rescan()
        }
    }
}

// MARK: - Settings Text Field (consistent styling)

struct SettingsTextField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Read-Only Tag Row (for variants/build types)

// MARK: - Output File Name Section

struct OutputFileNameSection: View {
    @Binding var project: AndroidProject
    @State private var templateText: String = ""

    private let tokens: [(token: String, desc: String)] = [
        ("{name}", "Project name"),
        ("{variant}", "Build variant"),
        ("{type}", "Build type"),
        ("{date}", "Date (yyyyMMdd)"),
        ("{time}", "Time (HHmmss)"),
        ("{version}", "Version name"),
        ("{code}", "Version code"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9))
                    .foregroundColor(Brand.warning)
                Text("Output File Name")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            TextField(AndroidProject.defaultTemplate, text: $templateText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .onChange(of: templateText) { _, newValue in
                    project.outputFileNameTemplate = newValue.isEmpty ? nil : newValue
                }

            // Token chips
            FlowLayout(spacing: 4) {
                ForEach(tokens, id: \.token) { item in
                    Button(action: {
                        templateText += item.token
                        project.outputFileNameTemplate = templateText.isEmpty ? nil : templateText
                    }) {
                        Text(item.token)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Brand.warning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Brand.warning.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Brand.warning.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(item.desc)
                }
            }

            // Live preview
            if !templateText.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Text("Preview: ")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(previewFileName + ".apk")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Brand.warning)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Brand.warning.opacity(0.04))
                )
            }

            Text("Leave empty for default Gradle/Flutter output name.")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .onAppear {
            templateText = project.outputFileNameTemplate ?? ""
        }
    }

    private var previewFileName: String {
        let sampleVariant = project.buildVariants.first ?? "dev"
        let sampleType = project.buildTypes.first ?? "debug"
        return project.resolvedOutputFileName(
            variant: sampleVariant,
            buildType: sampleType,
            versionName: project.detectedVersionName ?? "1.0.0",
            versionCode: project.detectedVersionCode ?? "1"
        )
    }
}

// MARK: - Output Copy Folder Section

struct OutputCopyFolderSection: View {
    @Binding var project: AndroidProject
    @State private var folderPath: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 9))
                    .foregroundColor(Brand.violet)
                Text("Output APK To Folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                TextField("~/Desktop/builds", text: $folderPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: folderPath) { _, newValue in
                        project.outputCopyPath = newValue.isEmpty ? nil : newValue
                    }

                Button(action: browseFolder) {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Text("Browse")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)

                if !folderPath.isEmpty {
                    Button(action: {
                        folderPath = ""
                        project.outputCopyPath = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Copy / Move mode picker
            if !folderPath.isEmpty {
                HStack(spacing: 8) {
                    Text("Mode:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    HStack(spacing: 0) {
                        ForEach(OutputCopyMode.allCases, id: \.self) { mode in
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    project.outputCopyMode = mode
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: mode.icon)
                                        .font(.system(size: 9))
                                    Text(mode.displayName)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(project.outputCopyMode == mode
                                              ? Brand.violet.opacity(0.15)
                                              : Color.clear)
                                )
                                .foregroundColor(project.outputCopyMode == mode ? Brand.violet : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(2)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.primary.opacity(0.04))
                    )
                }
            }

            Text(project.outputCopyMode == .move
                 ? "After a successful build, the APK will be moved to this folder (original removed)."
                 : "After a successful build, the APK will be copied to this folder.")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .onAppear {
            folderPath = project.outputCopyPath ?? ""
        }
    }

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select output folder for APK copies"
        if !folderPath.isEmpty, FileManager.default.fileExists(atPath: folderPath) {
            panel.directoryURL = URL(fileURLWithPath: folderPath)
        } else {
            panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop")
        }
        if panel.runModal() == .OK, let url = panel.url {
            folderPath = url.path
            project.outputCopyPath = folderPath
        }
    }
}

// MARK: - Read-Only Tag Row (for variants/build types)

struct ReadOnlyTagRow: View {
    let label: String
    let tags: [String]
    var tint: Color = Brand.success

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
            FlowLayout(spacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(tint.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
                        )
                        .foregroundColor(tint)
                }
            }
        }
    }
}

// MARK: - Stats Helper Views

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text(value)
                .font(Brand.titleFont(16))
            Text(title)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct DurationDataPoint: Identifiable {
    let id: Int
    let date: Date
    let duration: Double
    let success: Bool
}

struct SizeDataPoint: Identifiable {
    let id: Int
    let date: Date
    let sizeBytes: Int64
    let projectName: String
}

struct BuildDurationChart: View {
    let data: [(date: Date, duration: Double, success: Bool)]

    private var chartData: [DurationDataPoint] {
        Array(data.suffix(30)).enumerated().map { i, item in
            DurationDataPoint(id: i, date: item.date, duration: item.duration, success: item.success)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let items = chartData
            let maxDuration = items.map(\.duration).max() ?? 1
            let barWidth = max(2, (geo.size.width - CGFloat(items.count) * 2) / CGFloat(max(1, items.count)))

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(items) { item in
                    VStack(spacing: 2) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.success ? Brand.success.opacity(0.7) : Brand.error.opacity(0.7))
                            .frame(width: barWidth, height: max(4, CGFloat(item.duration / maxDuration) * (geo.size.height - 20)))
                    }
                    .help("\(item.success ? "✓" : "✗") \(Int(item.duration))s")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            // Y-axis labels
            VStack {
                Text(formatSeconds(maxDuration))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                Text("0s")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.vertical, 8)
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        let total = Int(s)
        let m = total / 60
        let sec = total % 60
        if m > 0 { return "\(m)m\(sec)s" }
        return "\(sec)s"
    }
}

struct APKSizeChart: View {
    let data: [(date: Date, sizeBytes: Int64, projectName: String)]

    private var chartData: [SizeDataPoint] {
        Array(data.suffix(30)).enumerated().map { i, item in
            SizeDataPoint(id: i, date: item.date, sizeBytes: item.sizeBytes, projectName: item.projectName)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let items = chartData
            let maxSize = items.map(\.sizeBytes).max() ?? 1
            let minSize = items.map(\.sizeBytes).min() ?? 0
            let range = max(Int64(1), maxSize - minSize)

            // Draw line chart
            let stepX = items.count > 1 ? (geo.size.width - 40) / CGFloat(items.count - 1) : 0
            let chartHeight = geo.size.height - 24

            ZStack {
                // Grid lines
                ForEach(0..<3, id: \.self) { i in
                    let y = chartHeight * CGFloat(i) / 2 + 12
                    Path { path in
                        path.move(to: CGPoint(x: 30, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width - 8, y: y))
                    }
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
                }

                // Line
                if items.count > 1 {
                    Path { path in
                        for (i, item) in items.enumerated() {
                            let x = 30 + stepX * CGFloat(i)
                            let normalized = CGFloat(item.sizeBytes - minSize) / CGFloat(range)
                            let y = 12 + chartHeight * (1 - normalized)
                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(Brand.primary, lineWidth: 2)

                    // Dots
                    ForEach(items) { item in
                        let x = 30 + stepX * CGFloat(item.id)
                        let normalized = CGFloat(item.sizeBytes - minSize) / CGFloat(range)
                        let y = 12 + chartHeight * (1 - normalized)
                        Circle()
                            .fill(Brand.primary)
                            .frame(width: 5, height: 5)
                            .position(x: x, y: y)
                            .help(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Y-axis labels
            VStack {
                Text(ByteCountFormatter.string(fromByteCount: maxSize, countStyle: .file))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: minSize, countStyle: .file))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var profileStore: BuildProfileStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedProjectId: UUID?
    @State private var selectedVariant = "dev"
    @State private var selectedBuildType = "debug"
    @State private var selectedOutputFormat: BuildOutputFormat = .apk
    @State private var cleanFirst = false
    @State private var notes = ""
    @State private var postBuildActions: [PostBuildAction] = []

    private var selectedProject: AndroidProject? {
        guard let id = selectedProjectId else { return nil }
        return projectStore.projects.first(where: { $0.id == id })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Build Profile")
                    .font(Brand.titleFont(14))
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Profile name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile Name")
                            .font(.system(size: 11, weight: .medium))
                        TextField("e.g. Production Release", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Project selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project")
                            .font(.system(size: 11, weight: .medium))
                        Picker("", selection: $selectedProjectId) {
                            Text("Select a project").tag(nil as UUID?)
                            ForEach(projectStore.projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                        .labelsHidden()
                    }

                    if let project = selectedProject {
                        // Variant & Build Type
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Variant")
                                    .font(.system(size: 11, weight: .medium))
                                Picker("", selection: $selectedVariant) {
                                    ForEach(project.buildVariants, id: \.self) { v in
                                        Text(v).tag(v)
                                    }
                                }
                                .labelsHidden()
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Build Type")
                                    .font(.system(size: 11, weight: .medium))
                                Picker("", selection: $selectedBuildType) {
                                    ForEach(project.buildTypes, id: \.self) { bt in
                                        Text(bt).tag(bt)
                                    }
                                }
                                .labelsHidden()
                            }
                        }

                        // Output format
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Output Format")
                                .font(.system(size: 11, weight: .medium))
                            Picker("", selection: $selectedOutputFormat) {
                                Text("APK").tag(BuildOutputFormat.apk)
                                Text("AAB (App Bundle)").tag(BuildOutputFormat.aab)
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        Toggle("Clean build first", isOn: $cleanFirst)
                            .font(.system(size: 12))
                    }

                    // Post-build actions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Post-Build Actions")
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Menu {
                                ForEach(PostBuildActionType.allCases, id: \.self) { type in
                                    Button(action: {
                                        postBuildActions.append(PostBuildAction(type: type))
                                    }) {
                                        Label(type.displayName, systemImage: type.icon)
                                    }
                                }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(Brand.accent)
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 20)
                        }

                        if postBuildActions.isEmpty {
                            Text("No actions — add actions to run after a successful build")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(postBuildActions.enumerated()), id: \.element.id) { index, action in
                                HStack(spacing: 8) {
                                    Toggle("", isOn: $postBuildActions[index].enabled)
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                    Image(systemName: action.type.icon)
                                        .font(.system(size: 10))
                                        .foregroundColor(.indigo)
                                        .frame(width: 16)
                                    Text(action.type.displayName)
                                        .font(.system(size: 11))
                                    Spacer()
                                    Button(action: { postBuildActions.remove(at: index) }) {
                                        Image(systemName: "minus.circle")
                                            .font(.system(size: 10))
                                            .foregroundColor(Brand.error.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes (optional)")
                            .font(.system(size: 11, weight: .medium))
                        TextField("Build notes...", text: $notes)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Profile") {
                    guard let projectId = selectedProjectId, !name.isEmpty else { return }
                    let profile = BuildProfile(
                        name: name,
                        projectId: projectId,
                        variant: selectedVariant,
                        buildType: selectedBuildType,
                        outputFormat: selectedOutputFormat,
                        cleanFirst: cleanFirst,
                        postBuildActions: postBuildActions,
                        notes: notes.isEmpty ? nil : notes
                    )
                    profileStore.addProfile(profile)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || selectedProjectId == nil)
            }
            .padding(16)
        }
        .frame(width: 420, height: 520)
    }
}

// MARK: - Add Firebase Config Sheet

struct AddFirebaseConfigSheet: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var firebaseService: FirebaseDistributionService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedProjectId: UUID?
    @State private var appId = ""
    @State private var serviceAccountPath = ""
    @State private var groups = ""
    @State private var testers = ""
    @State private var releaseNotes = ""
    @State private var autoUpload = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .foregroundColor(Brand.warning)
                    Text("Firebase Config")
                        .font(Brand.titleFont(14))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Config name
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Config Name")
                            .font(.system(size: 11, weight: .medium))
                        TextField("e.g. Production, Staging", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Project selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project")
                            .font(.system(size: 11, weight: .medium))
                        Picker("", selection: $selectedProjectId) {
                            Text("Select a project").tag(nil as UUID?)
                            ForEach(projectStore.projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                        .labelsHidden()
                    }

                    // Firebase App ID
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Firebase App ID")
                            .font(.system(size: 11, weight: .medium))
                        TextField("1:1234567890:android:abc123def456", text: $appId)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        Text("Find in Firebase Console > Project Settings > Your Apps")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    // Service account (optional)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Service Account JSON (optional)")
                            .font(.system(size: 11, weight: .medium))
                        HStack {
                            TextField("~/path/to/service-account.json", text: $serviceAccountPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            Button(action: {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.json]
                                panel.canChooseDirectories = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    serviceAccountPath = url.path
                                }
                            }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Leave empty to use firebase login credentials")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.7))
                    }

                    // Tester groups
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tester Groups (comma-separated)")
                            .font(.system(size: 11, weight: .medium))
                        TextField("qa-team, beta-testers", text: $groups)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Individual testers
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Testers (comma-separated emails)")
                            .font(.system(size: 11, weight: .medium))
                        TextField("tester@example.com, qa@example.com", text: $testers)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Release notes template
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default Release Notes")
                            .font(.system(size: 11, weight: .medium))
                        TextField("Build from Ketok", text: $releaseNotes)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    // Auto-upload toggle
                    Toggle(isOn: $autoUpload) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-upload after build")
                                .font(.system(size: 12, weight: .medium))
                            Text("Automatically upload to Firebase after every successful build")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Footer
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Config") {
                    guard let projectId = selectedProjectId, !name.isEmpty, !appId.isEmpty else { return }
                    let config = FirebaseConfig(
                        name: name,
                        projectId: projectId,
                        appId: appId.trimmingCharacters(in: .whitespaces),
                        serviceAccountPath: serviceAccountPath.isEmpty ? nil : serviceAccountPath,
                        groups: groups.isEmpty ? [] : groups.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                        testers: testers.isEmpty ? [] : testers.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                        releaseNotes: releaseNotes.isEmpty ? nil : releaseNotes,
                        autoUpload: autoUpload
                    )
                    firebaseService.addConfig(config)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty || selectedProjectId == nil || appId.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 440, height: 560)
    }
}


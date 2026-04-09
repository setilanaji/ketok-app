import Foundation
import Combine

/// Predefined Gradle tasks
enum GradleTask: String, CaseIterable, Identifiable {
    case clean = "clean"
    case pubGet = "pubGet"  // Flutter: resolve dependencies
    case lint = "lint"
    case test = "test"
    case bundle = "bundle"  // AAB

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .clean: return "Clean"
        case .pubGet: return "Pub Get"
        case .lint: return "Lint"
        case .test: return "Test"
        case .bundle: return "Bundle AAB"
        }
    }

    /// Display name adapted for Flutter projects
    func displayName(for projectType: ProjectType) -> String {
        guard projectType == .flutter else { return displayName }
        switch self {
        case .clean: return "Clean"
        case .pubGet: return "Pub Get"
        case .lint: return "Analyze"
        case .test: return "Test"
        case .bundle: return "Bundle AAB"
        }
    }

    /// Whether this task is available for the given project type
    var isFlutterOnly: Bool {
        self == .pubGet
    }

    var icon: String {
        switch self {
        case .clean: return "trash"
        case .pubGet: return "shippingbox"
        case .lint: return "magnifyingglass"
        case .test: return "checkmark.shield"
        case .bundle: return "archivebox"
        }
    }

    /// Gradle task name for native Android projects
    func taskName(module: String, variant: String, buildType: String) -> String {
        let mod = module.replacingOccurrences(of: "/", with: ":")
        switch self {
        case .clean:
            return "clean"
        case .pubGet:
            return "clean"  // Not used for native — filtered out in UI
        case .lint:
            return "\(mod):lint\(variant.capitalized)\(buildType.capitalized)"
        case .test:
            return "\(mod):test\(variant.capitalized)\(buildType.capitalized)UnitTest"
        case .bundle:
            return "\(mod):bundle\(variant.capitalized)\(buildType.capitalized)"
        }
    }

    /// Full command string for Flutter projects
    func flutterCommand(variant: String) -> String {
        switch self {
        case .clean:
            return "flutter clean"
        case .pubGet:
            return "flutter pub get"
        case .lint:
            return "flutter analyze"
        case .test:
            return "flutter test"
        case .bundle:
            var cmd = "flutter build appbundle"
            if !variant.isEmpty {
                cmd += " --flavor \(variant)"
            }
            return cmd
        }
    }
}

/// An item waiting in the build queue
struct BuildQueueItem: Identifiable {
    let id = UUID()
    let project: AndroidProject
    let variant: String
    let buildType: String
    let cleanFirst: Bool
    let postBuildActions: [PostBuildAction]?
    let outputFormat: BuildOutputFormat

    init(project: AndroidProject, variant: String, buildType: String, cleanFirst: Bool = false, postBuildActions: [PostBuildAction]? = nil, outputFormat: BuildOutputFormat = .apk) {
        self.project = project
        self.variant = variant
        self.buildType = buildType
        self.cleanFirst = cleanFirst
        self.postBuildActions = postBuildActions
        self.outputFormat = outputFormat
    }
}

/// Service that runs Gradle builds via command line
class GradleBuildService: ObservableObject {
    @Published var currentBuild: BuildStatus?
    @Published var activeBuilds: [BuildStatus] = []
    @Published var buildHistory: [BuildStatus] = []
    @Published var isRunningTask = false
    @Published var taskOutput: String = ""

    /// Parallel build settings
    @Published var parallelEnabled: Bool {
        didSet { UserDefaults.standard.set(parallelEnabled, forKey: "com.ketok.parallelBuilds") }
    }
    @Published var maxParallelBuilds: Int {
        didSet { UserDefaults.standard.set(maxParallelBuilds, forKey: "com.ketok.maxParallelBuilds") }
    }

    /// Optional signing config store — set by app on init
    var signingConfigStore: SigningConfigStore?

    /// Optional build stats store — set by app on init
    var buildStatsStore: BuildStatsStore?

    /// Optional ADB service for post-build actions
    var adbService: ADBService?

    /// Post-build actions to run after next successful build (set by profile)
    var pendingPostBuildActions: [PostBuildAction] = []

    /// Pending post-build actions keyed by build ID (for parallel builds)
    var pendingActionsPerBuild: [UUID: [PostBuildAction]] = [:]

    /// Build queue: list of pending build requests
    @Published var buildQueue: [BuildQueueItem] = []
    private var isProcessingQueue = false

    /// Track processes per build for parallel support
    private var activeProcesses: [UUID: Process] = [:]

    /// Legacy single-process references (kept for backward compat)
    private var currentProcess: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    init() {
        parallelEnabled = UserDefaults.standard.object(forKey: "com.ketok.parallelBuilds") as? Bool ?? false
        maxParallelBuilds = UserDefaults.standard.object(forKey: "com.ketok.maxParallelBuilds") as? Int ?? 2
    }

    /// Number of currently active builds
    var activeBuildCount: Int {
        activeBuilds.filter { $0.state.isBuilding }.count
    }

    /// Start a Gradle build for the given project, variant, and build type
    func startBuild(project: AndroidProject, variant: String, buildType: String, cleanFirst: Bool = false, postBuildActions: [PostBuildAction]? = nil, outputFormat: BuildOutputFormat = .apk) {
        // Only cancel existing build if NOT in parallel mode
        if !parallelEnabled {
            cancelBuild()
        }
        BuildSoundService.shared.playBuildStarted()

        // Re-detect version from project files before building
        var freshProject = project
        let env = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
        freshProject.detectedVersionName = env.versionName
        freshProject.detectedVersionCode = env.versionCode

        // Notify project store of updated version (fire-and-forget)
        onProjectUpdated?(freshProject)

        let build = BuildStatus(project: freshProject, variant: variant, buildType: buildType, outputFormat: outputFormat)
        currentBuild = build
        activeBuilds.append(build)

        // Store per-build post-build actions if provided
        if let actions = postBuildActions, !actions.isEmpty {
            pendingActionsPerBuild[build.id] = actions
        }

        // Resolve signing config for this project (only for release builds)
        let signingConfig: SigningConfig? = {
            guard buildType.lowercased() == "release" else { return nil }
            return signingConfigStore?.configForProject(project.id)
        }()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Run clean first if requested
            if cleanFirst {
                DispatchQueue.main.async {
                    build.logOutput += "[Ketok] Running clean first...\n"
                }
                if freshProject.isFlutter {
                    _ = self?.runFlutterCommand(project: freshProject, command: "flutter clean")
                } else {
                    _ = self?.runGradleCommand(project: freshProject, task: "clean")
                }
                DispatchQueue.main.async {
                    build.logOutput += "[Ketok] Clean complete, starting build...\n"
                }
            }

            // Flutter: always run `flutter pub get` before building to resolve dependencies
            if freshProject.isFlutter {
                // Detect and log FVM usage
                let projEnv = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: freshProject.path)
                if projEnv.usesFvm {
                    DispatchQueue.main.async {
                        build.logOutput += "[Ketok] 📌 FVM detected — using Flutter \(projEnv.fvmFlutterVersion ?? "pinned")\n"
                    }
                }
                DispatchQueue.main.async {
                    build.logOutput += "[Ketok] Resolving Flutter dependencies (pub get)...\n"
                }
                let pubGetResult = self?.runFlutterCommand(project: freshProject, command: "flutter pub get")
                if let result = pubGetResult, result.contains("Could not") || result.contains("ERR") || result.contains("error") {
                    DispatchQueue.main.async {
                        build.logOutput += "[Ketok] ⚠️ pub get had issues:\n\(result)\n"
                    }
                } else {
                    DispatchQueue.main.async {
                        build.logOutput += "[Ketok] Dependencies resolved.\n"
                    }
                }

                // Auto-detect and run code generation (build_runner, flutter_gen, etc.)
                let preBuildReqs = FlutterPreBuildService.detectRequirements(projectPath: freshProject.path)
                if preBuildReqs.needsBuildRunner || preBuildReqs.needsFlutterGen || preBuildReqs.hasVersionIssues || preBuildReqs.hasEnvIssues || preBuildReqs.enviedVersionIncompatible {
                    DispatchQueue.main.async {
                        build.logOutput += "[Ketok] Pre-build analysis: \(preBuildReqs.summary)\n"
                    }

                    // Report version mismatches prominently
                    if preBuildReqs.hasVersionIssues {
                        DispatchQueue.main.async {
                            if preBuildReqs.hasCriticalVersionIssues {
                                build.logOutput += "[Ketok] 🚨 Critical version drift detected — auto-fixing before build...\n"
                            } else {
                                build.logOutput += "[Ketok] ⚠️ Version drift detected in some packages (see details below)\n"
                            }
                        }
                    }

                    // Report missing .env variables prominently
                    if preBuildReqs.hasEnvIssues {
                        DispatchQueue.main.async {
                            let requiredCount = preBuildReqs.missingEnvVars.filter { !$0.hasDefault }.count
                            build.logOutput += "[Ketok] 🚨 Missing \(requiredCount) required .env variable(s) — envied code generation will fail!\n"
                        }
                    }

                    if preBuildReqs.needsCodeGeneration || preBuildReqs.needsFlutterGen || preBuildReqs.hasCriticalVersionIssues || preBuildReqs.enviedVersionIncompatible {
                        // Build the environment for pre-build commands
                        let systemEnv = ProjectEnvironmentDetector.detectSystemEnvironment()
                        var preBuildEnv = ProcessInfo.processInfo.environment
                        if let flutterHome = systemEnv.flutterHome {
                            let flutterBin = (flutterHome as NSString).appendingPathComponent("bin")
                            if let existingPath = preBuildEnv["PATH"] {
                                preBuildEnv["PATH"] = "\(flutterBin):\(existingPath)"
                            } else {
                                preBuildEnv["PATH"] = flutterBin
                            }
                        }
                        if preBuildEnv["JAVA_HOME"] == nil {
                            preBuildEnv["JAVA_HOME"] = systemEnv.javaHome ?? systemEnv.androidStudioJbrPath
                        }

                        let _ = FlutterPreBuildService.runPreBuildSteps(
                            projectPath: freshProject.path,
                            requirements: preBuildReqs,
                            environment: preBuildEnv
                        ) { logLine in
                            DispatchQueue.main.async {
                                build.logOutput += logLine
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            build.logOutput += "[Ketok] All generated files are up to date. Skipping code generation.\n"
                        }
                    }
                }
            }

            self?.runGradleBuild(build: build, signingConfig: signingConfig)
        }
    }

    /// Callback to persist updated project info (set by app on init)
    var onProjectUpdated: ((AndroidProject) -> Void)?

    /// Run a predefined Gradle task (or Flutter equivalent)
    func runTask(_ task: GradleTask, project: AndroidProject, variant: String, buildType: String) {
        guard !isRunningTask else { return }
        isRunningTask = true
        taskOutput = ""

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: String?
            if project.isFlutter {
                let cmd = task.flutterCommand(variant: variant)
                result = self?.runFlutterCommand(project: project, command: cmd)
            } else {
                let taskName = task.taskName(
                    module: project.resolvedAppModule,
                    variant: variant,
                    buildType: buildType
                )
                result = self?.runGradleCommand(project: project, task: taskName)
            }

            DispatchQueue.main.async {
                self?.isRunningTask = false
                self?.taskOutput = result ?? ""
            }
        }
    }

    /// Cancel the current build (or a specific build by ID for parallel mode)
    func cancelBuild(_ buildId: UUID? = nil) {
        if let id = buildId {
            // Cancel a specific build (parallel mode)
            activeProcesses[id]?.terminate()
            activeProcesses.removeValue(forKey: id)

            if let build = activeBuilds.first(where: { $0.id == id }), build.state.isBuilding {
                build.state = .failed(error: "Build cancelled by user")
                build.endTime = Date()
                buildHistory.insert(build, at: 0)
                activeBuilds.removeAll { $0.id == id }
                pendingActionsPerBuild.removeValue(forKey: id)
                if currentBuild?.id == id { currentBuild = nil }
            }
        } else {
            // Cancel current/all builds — terminate all processes
            currentProcess?.terminate()
            currentProcess = nil

            for (id, process) in activeProcesses {
                process.terminate()
                activeProcesses.removeValue(forKey: id)
            }

            // Mark all active builds as failed and move to history
            // Use activeBuilds as the single source of truth (currentBuild is always in activeBuilds)
            for build in activeBuilds where build.state.isBuilding {
                build.state = .failed(error: "Build cancelled by user")
                build.endTime = Date()
                buildHistory.insert(build, at: 0)
            }
            activeBuilds.removeAll()
            currentBuild = nil
            pendingActionsPerBuild.removeAll()
        }
    }

    private func runGradleBuild(build: BuildStatus, signingConfig: SigningConfig? = nil) {
        // Capture environment snapshot at build start
        let snapshot = BuildEnvironmentCapturer.capture(
            project: build.project,
            variant: build.variant,
            buildType: build.buildType,
            outputFormat: build.outputFormat
        )
        DispatchQueue.main.async {
            build.environmentSnapshot = snapshot
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        self.currentProcess = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        // Track process for parallel cancellation
        activeProcesses[build.id] = process

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = URL(fileURLWithPath: build.project.path)

        var buildCommand: String
        var signingEnvVars: [String: String] = [:]

        if build.project.isFlutter {
            // Flutter build command
            if build.outputFormat == .aab {
                buildCommand = build.project.flutterBundleCommand(variant: build.variant)
            } else {
                buildCommand = build.project.flutterBuildCommand(
                    variant: build.variant,
                    buildType: build.buildType
                )
            }

            DispatchQueue.main.async {
                build.logOutput += "[Ketok] Flutter build (\(build.outputFormat.rawValue)): \(buildCommand)\n"
            }
        } else {
            // Native Gradle build command
            buildCommand = "./gradlew \(build.taskName) --console=plain"

            // Inject signing properties for release builds — passwords go via env vars, not command line
            if let signing = signingConfig {
                buildCommand += " \(signing.gradleSigningArgs().joined(separator: " "))"
                signingEnvVars = signing.gradleSigningEnvVars()

                DispatchQueue.main.async {
                    build.logOutput += "[Ketok] Signing enabled: \(signing.name) (\(signing.keystoreFileName))\n"
                }
            }
        }

        process.arguments = ["-c", buildCommand]

        // Detect environment
        let projectEnv = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: build.project.path)
        let systemEnv = ProjectEnvironmentDetector.detectSystemEnvironment()

        var environment = ProcessInfo.processInfo.environment
        if environment["JAVA_HOME"] == nil {
            environment["JAVA_HOME"] = systemEnv.javaHome ?? systemEnv.androidStudioJbrPath
        }
        let sdkDir = projectEnv.sdkDir ?? systemEnv.androidHome
        if let sdk = sdkDir {
            environment["ANDROID_HOME"] = sdk
            environment["ANDROID_SDK_ROOT"] = sdk
        }
        // Add Flutter SDK to PATH if available
        if build.project.isFlutter, let flutterHome = systemEnv.flutterHome {
            let flutterBin = (flutterHome as NSString).appendingPathComponent("bin")
            if let existingPath = environment["PATH"] {
                environment["PATH"] = "\(flutterBin):\(existingPath)"
            } else {
                environment["PATH"] = flutterBin
            }
        }
        // Inject signing passwords via env vars and immediately clear from local scope
        for (key, value) in signingEnvVars {
            environment[key] = value
        }
        signingEnvVars.removeAll()
        process.environment = environment

        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Read stdout in real-time
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                build.logOutput += output
                self?.updateProgress(build: build, output: output)
            }
        }

        // Read stderr in real-time
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                build.logOutput += "[ERROR] \(output)"
            }
        }

        do {
            try process.run()
            process.waitUntilExit()

            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            let exitCode = process.terminationStatus

            // Try to extract version info from build log, fall back to project-detected values
            let versionName = Self.extractVersionName(from: build.logOutput) ?? build.project.detectedVersionName
            let versionCode = Self.extractVersionCode(from: build.logOutput) ?? build.project.detectedVersionCode

            DispatchQueue.main.async { [weak self] in
                if exitCode == 0 {
                    let originalPath: String
                    if build.outputFormat == .aab {
                        originalPath = build.project.aabOutputPath(
                            variant: build.variant,
                            buildType: build.buildType
                        )
                    } else {
                        originalPath = build.project.apkOutputPath(
                            variant: build.variant,
                            buildType: build.buildType
                        )
                    }
                    // Rename output if the user configured a custom output name
                    let outputPath = build.project.renameAPKIfNeeded(
                        originalPath: originalPath,
                        variant: build.variant,
                        buildType: build.buildType,
                        versionName: versionName,
                        versionCode: versionCode
                    )
                    // Copy to output folder if configured
                    if let copiedPath = build.project.copyAPKToOutputFolder(apkPath: outputPath) {
                        build.logOutput += "[Ketok] Copied to: \(copiedPath)\n"
                    }

                    // Detect ProGuard/R8 mapping file
                    build.mappingFilePath = build.project.mappingFilePath(
                        variant: build.variant,
                        buildType: build.buildType
                    )
                    if build.hasMappingFile {
                        build.logOutput += "[Ketok] Mapping file found: \(build.mappingFilePath!)\n"
                    }

                    build.state = .success(apkPath: outputPath)
                    build.complete(apkPath: outputPath)
                    BuildSoundService.shared.playSuccess()
                    NotificationService.shared.sendBuildSuccess(
                        project: build.project.name,
                        variant: build.variant,
                        buildType: build.buildType,
                        duration: build.elapsed,
                        apkSize: build.formattedAPKSize,
                        outputPath: outputPath
                    )
                    // Run post-build actions (per-build or global pending)
                    if let adb = self?.adbService {
                        let perBuildActions = self?.pendingActionsPerBuild[build.id] ?? []
                        let globalActions = self?.pendingPostBuildActions ?? []
                        let actions = perBuildActions.isEmpty ? globalActions : perBuildActions
                        if !actions.isEmpty {
                            PostBuildActionRunner.runActions(actions, apkPath: outputPath, project: build.project, adbService: adb)
                            if perBuildActions.isEmpty {
                                self?.pendingPostBuildActions = []
                            }
                        }
                    }
                    self?.pendingActionsPerBuild.removeValue(forKey: build.id)

                    // Firebase auto-upload if configured
                    let firebase = FirebaseDistributionService.shared
                    if let config = firebase.configForProject(build.project.id),
                       config.autoUpload, firebase.isConfigured {
                        firebase.uploadAPK(apkPath: outputPath, config: config)
                    }
                } else {
                    let buildTool = build.project.isFlutter ? "Flutter" : "Gradle"
                    // Extract last meaningful error lines from log for the error summary
                    let errorSummary = Self.extractErrorSummary(from: build.logOutput, isFlutter: build.project.isFlutter)
                    let errorMessage = errorSummary ?? "\(buildTool) exited with code \(exitCode)"
                    build.state = .failed(error: errorMessage)
                    build.complete()
                    BuildSoundService.shared.playFailure()
                    NotificationService.shared.sendBuildFailed(
                        project: build.project.name,
                        variant: build.variant,
                        buildType: build.buildType,
                        error: errorMessage
                    )
                    self?.pendingActionsPerBuild.removeValue(forKey: build.id)
                }
                self?.buildHistory.insert(build, at: 0)
                self?.currentProcess = nil
                self?.activeProcesses.removeValue(forKey: build.id)
                self?.activeBuilds.removeAll { $0.id == build.id }
                if self?.currentBuild?.id == build.id { self?.currentBuild = nil }
                self?.buildStatsStore?.recordBuild(from: build)
                self?.processNextInQueue()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                build.state = .failed(error: error.localizedDescription)
                build.complete()
                BuildSoundService.shared.playFailure()
                self?.buildHistory.insert(build, at: 0)
                self?.currentProcess = nil
                self?.activeProcesses.removeValue(forKey: build.id)
                self?.activeBuilds.removeAll { $0.id == build.id }
                if self?.currentBuild?.id == build.id { self?.currentBuild = nil }
                self?.pendingActionsPerBuild.removeValue(forKey: build.id)
                self?.buildStatsStore?.recordBuild(from: build)
                self?.processNextInQueue()
            }
        }
    }

    /// Run a single Gradle command and return its output
    private func runGradleCommand(project: AndroidProject, task: String) -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        process.arguments = ["-c", "./gradlew \(task) --console=plain"]

        let projectEnv = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
        let systemEnv = ProjectEnvironmentDetector.detectSystemEnvironment()

        var environment = ProcessInfo.processInfo.environment
        if environment["JAVA_HOME"] == nil {
            environment["JAVA_HOME"] = systemEnv.javaHome ?? systemEnv.androidStudioJbrPath
        }
        if let sdk = projectEnv.sdkDir ?? systemEnv.androidHome {
            environment["ANDROID_HOME"] = sdk
            environment["ANDROID_SDK_ROOT"] = sdk
        }
        process.environment = environment

        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    /// Estimate progress based on build output (Gradle or Flutter)
    private func updateProgress(build: BuildStatus, output: String) {
        if build.project.isFlutter {
            // Flutter build progress markers
            if output.contains("Running Gradle task") || output.contains("Resolving dependencies") { build.progress = 0.1 }
            else if output.contains("Running Gradle task 'assemble") { build.progress = 0.2 }
            else if output.contains("compileFlutter") || output.contains("Compiling") { build.progress = 0.3 }
            else if output.contains("compile") || output.contains("Compile") { build.progress = 0.5 }
            else if output.contains("merge") || output.contains("Merge") { build.progress = 0.6 }
            else if output.contains("package") || output.contains("Package") { build.progress = 0.7 }
            else if output.contains("Signing") || output.contains("signing") { build.progress = 0.85 }
            else if output.contains("Built build") || output.contains("✓ Built") { build.progress = 1.0 }
        } else {
            // Native Gradle progress markers
            if output.contains("preBuild") { build.progress = 0.1 }
            else if output.contains("compile") || output.contains("Compile") { build.progress = 0.3 }
            else if output.contains("merge") || output.contains("Merge") { build.progress = 0.5 }
            else if output.contains("package") || output.contains("Package") { build.progress = 0.7 }
            else if output.contains("assemble") || output.contains("Assemble") || output.contains("bundle") || output.contains("Bundle") { build.progress = 0.9 }
            else if output.contains("BUILD SUCCESSFUL") { build.progress = 1.0 }
        }
    }

    /// Run a Flutter command and return its output
    private func runFlutterCommand(project: AndroidProject, command: String) -> String {
        // Auto-resolve flutter/dart commands through FVM when the project uses it
        let resolvedCommand = ProjectEnvironmentDetector.resolveFlutterCommand(command, projectPath: project.path)

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)
        process.arguments = ["-c", resolvedCommand]

        let systemEnv = ProjectEnvironmentDetector.detectSystemEnvironment()

        var environment = ProcessInfo.processInfo.environment
        // Add Flutter SDK to PATH
        if let flutterHome = systemEnv.flutterHome {
            let flutterBin = (flutterHome as NSString).appendingPathComponent("bin")
            if let existingPath = environment["PATH"] {
                environment["PATH"] = "\(flutterBin):\(existingPath)"
            } else {
                environment["PATH"] = flutterBin
            }
        }
        // Also set Android SDK for Flutter's Gradle usage
        let projectEnv = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
        if let sdk = projectEnv.sdkDir ?? systemEnv.androidHome {
            environment["ANDROID_HOME"] = sdk
            environment["ANDROID_SDK_ROOT"] = sdk
        }
        if environment["JAVA_HOME"] == nil {
            environment["JAVA_HOME"] = systemEnv.javaHome ?? systemEnv.androidStudioJbrPath
        }
        process.environment = environment

        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Build Queue

    /// Add a build to the queue. If slots are available, starts immediately.
    func enqueueBuild(project: AndroidProject, variant: String, buildType: String, cleanFirst: Bool = false, postBuildActions: [PostBuildAction]? = nil, outputFormat: BuildOutputFormat = .apk) {
        let item = BuildQueueItem(project: project, variant: variant, buildType: buildType, cleanFirst: cleanFirst, postBuildActions: postBuildActions, outputFormat: outputFormat)
        buildQueue.append(item)
        processNextInQueue()
    }

    /// Remove a queued item by ID
    func removeFromQueue(_ id: UUID) {
        buildQueue.removeAll { $0.id == id }
    }

    /// Process the next build(s) in the queue
    private func processNextInQueue() {
        guard !buildQueue.isEmpty else { return }

        if parallelEnabled {
            // Start multiple builds up to the max
            while !buildQueue.isEmpty && activeBuildCount < maxParallelBuilds {
                let next = buildQueue.removeFirst()
                startBuild(project: next.project, variant: next.variant, buildType: next.buildType, cleanFirst: next.cleanFirst, postBuildActions: next.postBuildActions, outputFormat: next.outputFormat)
            }
        } else {
            // Sequential: only one at a time
            guard activeBuildCount == 0 else { return }
            let next = buildQueue.removeFirst()
            startBuild(project: next.project, variant: next.variant, buildType: next.buildType, cleanFirst: next.cleanFirst, postBuildActions: next.postBuildActions, outputFormat: next.outputFormat)
        }
    }

    // MARK: - Version Extraction Helpers

    /// Try to extract versionName from build log output
    static func extractVersionName(from log: String) -> String? {
        // Gradle: versionName = "1.2.3" or versionName '1.2.3'
        // Flutter: version: 1.2.3+4 in pubspec echoed to log
        let patterns = [
            "versionName[= ]+[\"']?([\\d]+\\.[\\d]+\\.[\\d]+[\\w.-]*)[\"']?",
            "version:\\s*([\\d]+\\.[\\d]+\\.[\\d]+)",
            "Built build/app/outputs.*?app-.*?-(\\d+\\.\\d+\\.\\d+)"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
               let range = Range(match.range(at: 1), in: log) {
                return String(log[range])
            }
        }
        return nil
    }

    /// Try to extract versionCode from build log output
    static func extractVersionCode(from log: String) -> String? {
        let patterns = [
            "versionCode[= ]+[\"']?(\\d+)[\"']?",
            "version:\\s*[\\d.]+\\+(\\d+)"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
               let range = Range(match.range(at: 1), in: log) {
                return String(log[range])
            }
        }
        return nil
    }

    // MARK: - Error Extraction

    /// Extract a human-readable error summary from the build log
    static func extractErrorSummary(from log: String, isFlutter: Bool) -> String? {
        let lines = log.components(separatedBy: "\n")

        if isFlutter {
            // Flutter error patterns (check most specific first)
            let flutterPatterns = [
                "Error: ",
                "FAILURE: ",
                "Could not ",
                "Exception: ",
                "flutter: command not found",
                "pub get failed",
                "Target dart2js failed",
                "Compiler message:",
                "flutter_gen",           // flutter_gen_runner failures
                "build_runner",          // build_runner failures
                "version solving failed", // dependency version conflicts
                "envied",                // envied_generator failures
                "app_env.g.dart",        // missing envied generated file
                "lib/",  // Dart compilation errors usually show file path
            ]
            // Search from the end for the most relevant error
            for line in lines.reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("[Ketok]") { continue }
                for pattern in flutterPatterns {
                    if trimmed.contains(pattern) {
                        // Return up to 120 chars of the error
                        let cleaned = trimmed.replacingOccurrences(of: "[ERROR] ", with: "")
                        return String(cleaned.prefix(120))
                    }
                }
            }
            // Fallback: find any [ERROR] line
            if let lastError = lines.reversed().first(where: { $0.contains("[ERROR]") }) {
                let cleaned = lastError.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "[ERROR] ", with: "")
                return String(cleaned.prefix(120))
            }
        } else {
            // Gradle error patterns
            let gradlePatterns = [
                "FAILURE: ",
                "BUILD FAILED",
                "error: ",
                "Error: ",
                "Could not ",
                "Exception: ",
            ]
            for line in lines.reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("[Ketok]") { continue }
                for pattern in gradlePatterns {
                    if trimmed.contains(pattern) {
                        let cleaned = trimmed.replacingOccurrences(of: "[ERROR] ", with: "")
                        return String(cleaned.prefix(120))
                    }
                }
            }
        }

        return nil
    }
}

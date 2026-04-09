import Foundation
import Combine

/// A single cell in the build matrix (variant × buildType × format)
struct MatrixCell: Identifiable, Equatable {
    let id = UUID()
    let variant: String
    let buildType: String
    let outputFormat: BuildOutputFormat

    var displayName: String {
        "\(variant)-\(buildType)"
    }
}

/// State of a single matrix cell build
enum MatrixCellState: Equatable {
    case pending
    case building
    case success(apkPath: String)
    case failed(error: String)
    case skipped

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .building: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle"
        }
    }

    var isComplete: Bool {
        switch self {
        case .success, .failed, .skipped: return true
        default: return false
        }
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

/// Tracks the progress of a matrix cell
class MatrixCellStatus: ObservableObject, Identifiable {
    let id = UUID()
    let cell: MatrixCell
    @Published var state: MatrixCellState = .pending
    @Published var startTime: Date?
    @Published var endTime: Date?
    @Published var apkPath: String?

    init(cell: MatrixCell) {
        self.cell = cell
    }

    var elapsed: TimeInterval? {
        guard let start = startTime else { return nil }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    var formattedElapsed: String {
        guard let secs = elapsed else { return "-" }
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}

/// Service that manages building all variants × buildTypes in a matrix
class BuildMatrixService: ObservableObject {
    @Published var isRunning = false
    @Published var cells: [MatrixCellStatus] = []
    @Published var startTime: Date?
    @Published var endTime: Date?
    @Published var cleanFirst = false
    @Published var selectedFormats: Set<BuildOutputFormat> = [.apk]
    @Published var selectedVariants: Set<String> = []
    @Published var selectedBuildTypes: Set<String> = []

    private var buildQueue: [MatrixCellStatus] = []
    private var cancellables = Set<AnyCancellable>()
    private var isCancelled = false

    /// Total cells in the matrix
    var totalCells: Int { cells.count }

    /// Cells completed (success or failed)
    var completedCells: Int { cells.filter { $0.state.isComplete }.count }

    /// Cells that succeeded
    var successCount: Int { cells.filter { $0.state.isSuccess }.count }

    /// Cells that failed
    var failCount: Int { cells.filter { if case .failed = $0.state { return true }; return false }.count }

    /// Overall progress
    var progress: Double {
        guard totalCells > 0 else { return 0 }
        return Double(completedCells) / Double(totalCells)
    }

    /// Total elapsed time
    var totalElapsed: String {
        guard let start = startTime else { return "-" }
        let secs = (endTime ?? Date()).timeIntervalSince(start)
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    // MARK: - Setup

    /// Build the matrix of cells from selections
    func buildMatrix(project: AndroidProject) {
        let variants = selectedVariants.isEmpty ? project.buildVariants : Array(selectedVariants)
        let types = selectedBuildTypes.isEmpty ? project.buildTypes : Array(selectedBuildTypes)

        var newCells: [MatrixCellStatus] = []
        for variant in variants.sorted() {
            for buildType in types.sorted() {
                for format in selectedFormats.sorted(by: { $0.rawValue < $1.rawValue }) {
                    let cell = MatrixCell(variant: variant, buildType: buildType, outputFormat: format)
                    newCells.append(MatrixCellStatus(cell: cell))
                }
            }
        }

        cells = newCells
    }

    /// Initialize selections from a project
    func initializeSelections(project: AndroidProject) {
        selectedVariants = Set(project.buildVariants)
        selectedBuildTypes = Set(project.buildTypes)
        selectedFormats = [.apk]
    }

    // MARK: - Execute

    /// Start building the entire matrix sequentially
    func startMatrix(project: AndroidProject, buildService: GradleBuildService) {
        guard !isRunning else { return }
        isCancelled = false
        isRunning = true
        startTime = Date()
        endTime = nil

        // Reset all cell states
        for cell in cells {
            cell.state = .pending
        }

        // Build sequentially using the queue
        buildQueue = cells
        processNextCell(project: project, buildService: buildService)
    }

    /// Cancel the matrix build
    func cancelMatrix() {
        isCancelled = true
        // Mark remaining pending cells as skipped
        for cell in cells where cell.state == .pending {
            cell.state = .skipped
        }
        isRunning = false
        endTime = Date()
    }

    private func processNextCell(project: AndroidProject, buildService: GradleBuildService) {
        guard !isCancelled, let next = buildQueue.first(where: { $0.state == .pending }) else {
            // All done
            isRunning = false
            endTime = Date()
            return
        }

        next.state = .building
        next.startTime = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = self?.executeSingleBuild(
                project: project,
                variant: next.cell.variant,
                buildType: next.cell.buildType,
                outputFormat: next.cell.outputFormat,
                cleanFirst: self?.cleanFirst ?? false
            )

            DispatchQueue.main.async {
                next.endTime = Date()
                if let (success, path, error) = result {
                    if success, let apkPath = path {
                        next.state = .success(apkPath: apkPath)
                        next.apkPath = apkPath
                    } else {
                        next.state = .failed(error: error ?? "Unknown error")
                    }
                } else {
                    next.state = .failed(error: "Build returned no result")
                }

                // Process next
                self?.processNextCell(project: project, buildService: buildService)
            }
        }
    }

    /// Execute a single build synchronously and return (success, apkPath?, error?)
    private func executeSingleBuild(
        project: AndroidProject,
        variant: String,
        buildType: String,
        outputFormat: BuildOutputFormat,
        cleanFirst: Bool
    ) -> (Bool, String?, String?) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = URL(fileURLWithPath: project.path)

        var buildCommand: String

        if project.isFlutter {
            // Flutter pub get first
            let pubGetProcess = Process()
            let pubGetPipe = Pipe()
            pubGetProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
            pubGetProcess.currentDirectoryURL = URL(fileURLWithPath: project.path)
            pubGetProcess.arguments = ["-c", "flutter pub get"]
            pubGetProcess.environment = buildEnvironment(project: project)
            pubGetProcess.standardOutput = pubGetPipe
            pubGetProcess.standardError = pubGetPipe
            try? pubGetProcess.run()
            pubGetProcess.waitUntilExit()

            // Clean if requested
            if cleanFirst {
                let cleanProcess = Process()
                cleanProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                cleanProcess.currentDirectoryURL = URL(fileURLWithPath: project.path)
                cleanProcess.arguments = ["-c", "flutter clean"]
                cleanProcess.environment = buildEnvironment(project: project)
                cleanProcess.standardOutput = Pipe()
                cleanProcess.standardError = Pipe()
                try? cleanProcess.run()
                cleanProcess.waitUntilExit()
            }

            if outputFormat == .aab {
                buildCommand = project.flutterBundleCommand(variant: variant)
            } else {
                buildCommand = project.flutterBuildCommand(variant: variant, buildType: buildType)
            }
        } else {
            if cleanFirst {
                let cleanProcess = Process()
                cleanProcess.executableURL = URL(fileURLWithPath: "/bin/bash")
                cleanProcess.currentDirectoryURL = URL(fileURLWithPath: project.path)
                cleanProcess.arguments = ["-c", "./gradlew clean --console=plain"]
                cleanProcess.environment = buildEnvironment(project: project)
                cleanProcess.standardOutput = Pipe()
                cleanProcess.standardError = Pipe()
                try? cleanProcess.run()
                cleanProcess.waitUntilExit()
            }

            let module = project.resolvedAppModule.replacingOccurrences(of: "/", with: ":")

            if outputFormat == .aab {
                buildCommand = "./gradlew \(module):bundle\(variant.capitalized)\(buildType.capitalized) --console=plain"
            } else {
                buildCommand = "./gradlew \(module):assemble\(variant.capitalized)\(buildType.capitalized) --console=plain"
            }
        }

        process.arguments = ["-c", buildCommand]
        process.environment = buildEnvironment(project: project)
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let exitCode = process.terminationStatus
            if exitCode == 0 {
                let path: String
                if outputFormat == .aab {
                    path = project.aabOutputPath(variant: variant, buildType: buildType)
                } else {
                    path = project.apkOutputPath(variant: variant, buildType: buildType)
                }
                return (true, path, nil)
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let errorSummary = GradleBuildService.extractErrorSummary(from: output, isFlutter: project.isFlutter)
                return (false, nil, errorSummary ?? "Exit code \(exitCode)")
            }
        } catch {
            return (false, nil, error.localizedDescription)
        }
    }

    /// Build a consistent environment for child processes
    private func buildEnvironment(project: AndroidProject) -> [String: String] {
        let projectEnv = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
        let systemEnv = ProjectEnvironmentDetector.detectSystemEnvironment()

        var env = ProcessInfo.processInfo.environment
        if env["JAVA_HOME"] == nil {
            env["JAVA_HOME"] = systemEnv.javaHome ?? systemEnv.androidStudioJbrPath
        }
        if let sdk = projectEnv.sdkDir ?? systemEnv.androidHome {
            env["ANDROID_HOME"] = sdk
            env["ANDROID_SDK_ROOT"] = sdk
        }
        if project.isFlutter, let flutterHome = systemEnv.flutterHome {
            let flutterBin = (flutterHome as NSString).appendingPathComponent("bin")
            if let existingPath = env["PATH"] {
                env["PATH"] = "\(flutterBin):\(existingPath)"
            } else {
                env["PATH"] = flutterBin
            }
        }
        return env
    }
}

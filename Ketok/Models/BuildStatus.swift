import Foundation

/// The output format of a build
enum BuildOutputFormat: String, Equatable, Codable, Hashable {
    case apk = "APK"
    case aab = "AAB"
}

/// Represents the current state of a build
enum BuildState: Equatable {
    case idle
    case building
    case success(apkPath: String)
    case failed(error: String)

    var isBuilding: Bool {
        if case .building = self { return true }
        return false
    }

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    /// Get the output path if successful
    var outputPath: String? {
        if case .success(let path) = self { return path }
        return nil
    }
}

/// Tracks a single build's status and output
class BuildStatus: ObservableObject, Identifiable {
    let id = UUID()
    let project: AndroidProject
    let variant: String
    let buildType: String
    let startTime: Date
    let outputFormat: BuildOutputFormat

    @Published var state: BuildState = .building
    @Published var logOutput: String = ""
    @Published var progress: Double = 0.0

    /// Set when build completes
    var endTime: Date?
    var apkSizeBytes: Int64?

    /// Path to the ProGuard/R8 mapping file (if exists)
    var mappingFilePath: String?

    /// Environment snapshot captured at build start
    var environmentSnapshot: BuildEnvironmentSnapshot?

    var elapsed: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        let total = Int(elapsed)
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var formattedAPKSize: String? {
        guard let bytes = apkSizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Label for output size (adapts to APK/AAB)
    var formattedOutputSize: String? {
        guard let bytes = apkSizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var taskName: String {
        if outputFormat == .aab {
            if project.isFlutter {
                return project.flutterBundleCommand(variant: variant)
            }
            let module = project.resolvedAppModule.replacingOccurrences(of: "/", with: ":")
            return "\(module):bundle\(variant.capitalized)\(buildType.capitalized)"
        }
        if project.isFlutter {
            return project.flutterBuildCommand(variant: variant, buildType: buildType)
        }
        return project.gradleTaskName(variant: variant, buildType: buildType)
    }

    /// Whether this build has a mapping file available
    var hasMappingFile: Bool {
        if let path = mappingFilePath {
            return FileManager.default.fileExists(atPath: path)
        }
        return false
    }

    init(project: AndroidProject, variant: String, buildType: String, outputFormat: BuildOutputFormat = .apk) {
        self.project = project
        self.variant = variant
        self.buildType = buildType
        self.outputFormat = outputFormat
        self.startTime = Date()
    }

    /// Finalize the build with end time and output size
    func complete(apkPath: String? = nil) {
        endTime = Date()
        if let path = apkPath {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            apkSizeBytes = attrs?[.size] as? Int64
        }
    }
}

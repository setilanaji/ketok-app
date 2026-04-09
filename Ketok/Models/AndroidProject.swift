import Foundation
import SwiftUI

/// The type of mobile project
enum ProjectType: String, Codable, Hashable {
    case native = "native"      // Standard Android (Gradle)
    case flutter = "flutter"    // Flutter project

    var displayName: String {
        switch self {
        case .native: return "Android"
        case .flutter: return "Flutter"
        }
    }

    var icon: String {
        switch self {
        case .native: return "paperplane.fill"
        case .flutter: return "bird"
        }
    }

    /// SF Symbol used for the project card
    var folderIcon: String {
        switch self {
        case .native: return "folder.fill"
        case .flutter: return "bird.fill"
        }
    }

    var tintColor: Color {
        switch self {
        case .native: return .green
        case .flutter: return .blue
        }
    }
}

/// Whether to copy or move the APK to the destination folder
enum OutputCopyMode: String, Codable, Hashable, CaseIterable {
    case copy = "copy"
    case move = "move"

    var displayName: String {
        switch self {
        case .copy: return "Copy"
        case .move: return "Move"
        }
    }

    var icon: String {
        switch self {
        case .copy: return "doc.on.doc"
        case .move: return "arrow.right.doc.on.clipboard"
        }
    }

    var description: String {
        switch self {
        case .copy: return "Keep the original file and copy to destination"
        case .move: return "Move the file to destination (removes original)"
        }
    }
}

/// Represents a configured Android / Flutter project
struct AndroidProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var path: String
    var buildVariants: [String]
    var buildTypes: [String]
    var appModulePath: String?     // e.g. "app", "app-commercial/app"
    var projectType: ProjectType   // .native or .flutter
    var outputFileNameTemplate: String?  // e.g. "{name}-{variant}-{type}-v{version}-{date}"
    var detectedVersionName: String?     // from build.gradle or pubspec.yaml
    var detectedVersionCode: String?     // from build.gradle or pubspec.yaml
    var outputCopyPath: String?          // optional folder to copy APK to after build
    var outputCopyMode: OutputCopyMode   // copy or move the APK to destination

    // MARK: - Coding (backward compatibility)

    enum CodingKeys: String, CodingKey {
        case id, name, path, buildVariants, buildTypes, appModulePath, projectType
        case outputFileNameTemplate, detectedVersionName, detectedVersionCode, outputCopyPath, outputCopyMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        path = try container.decode(String.self, forKey: .path)
        buildVariants = try container.decode([String].self, forKey: .buildVariants)
        buildTypes = try container.decode([String].self, forKey: .buildTypes)
        appModulePath = try container.decodeIfPresent(String.self, forKey: .appModulePath)
        // Default to .native for existing saved projects
        projectType = try container.decodeIfPresent(ProjectType.self, forKey: .projectType) ?? .native
        outputFileNameTemplate = try container.decodeIfPresent(String.self, forKey: .outputFileNameTemplate)
        detectedVersionName = try container.decodeIfPresent(String.self, forKey: .detectedVersionName)
        detectedVersionCode = try container.decodeIfPresent(String.self, forKey: .detectedVersionCode)
        outputCopyPath = try container.decodeIfPresent(String.self, forKey: .outputCopyPath)
        outputCopyMode = try container.decodeIfPresent(OutputCopyMode.self, forKey: .outputCopyMode) ?? .copy
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        buildVariants: [String],
        buildTypes: [String],
        appModulePath: String? = nil,
        projectType: ProjectType = .native,
        outputFileNameTemplate: String? = nil,
        detectedVersionName: String? = nil,
        detectedVersionCode: String? = nil,
        outputCopyPath: String? = nil,
        outputCopyMode: OutputCopyMode = .copy
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.buildVariants = buildVariants
        self.buildTypes = buildTypes
        self.appModulePath = appModulePath
        self.projectType = projectType
        self.outputFileNameTemplate = outputFileNameTemplate
        self.detectedVersionName = detectedVersionName
        self.detectedVersionCode = detectedVersionCode
        self.outputCopyPath = outputCopyPath
        self.outputCopyMode = outputCopyMode
    }

    // MARK: - Computed Properties

    /// The resolved app module, defaulting to "app"
    var resolvedAppModule: String {
        appModulePath ?? "app"
    }

    var isFlutter: Bool {
        projectType == .flutter
    }

    // MARK: - Native Android Properties

    var gradlewPath: String {
        if isFlutter {
            return (path as NSString).appendingPathComponent("android/gradlew")
        }
        return (path as NSString).appendingPathComponent("gradlew")
    }

    var hasGradlew: Bool {
        FileManager.default.isExecutableFile(atPath: gradlewPath)
    }

    /// Returns the Gradle task name for a given variant + buildType (native only)
    func gradleTaskName(variant: String, buildType: String) -> String {
        let module = resolvedAppModule.replacingOccurrences(of: "/", with: ":")
        return "\(module):assemble\(variant.capitalized)\(buildType.capitalized)"
    }

    /// Returns the build command display string
    func buildCommandDisplay(variant: String, buildType: String) -> String {
        if isFlutter {
            return flutterBuildCommand(variant: variant, buildType: buildType)
        }
        return "./gradlew \(gradleTaskName(variant: variant, buildType: buildType))"
    }

    // MARK: - Flutter Build Commands

    /// The flutter build command for a given variant and build type
    func flutterBuildCommand(variant: String, buildType: String) -> String {
        var cmd = "flutter build apk"
        if !variant.isEmpty {
            cmd += " --flavor \(variant)"
        }
        if buildType.lowercased() == "release" {
            cmd += " --release"
        } else if buildType.lowercased() == "profile" {
            cmd += " --profile"
        } else {
            cmd += " --debug"
        }
        return cmd
    }

    /// Flutter bundle (AAB) command
    func flutterBundleCommand(variant: String) -> String {
        var cmd = "flutter build appbundle"
        if !variant.isEmpty {
            cmd += " --flavor \(variant)"
        }
        return cmd
    }

    // MARK: - APK Output Path

    /// Returns the expected APK output path for a given variant and build type
    func apkOutputPath(variant: String, buildType: String) -> String {
        if isFlutter {
            return flutterApkOutputPath(variant: variant, buildType: buildType)
        }
        return nativeApkOutputPath(variant: variant, buildType: buildType)
    }

    private func nativeApkOutputPath(variant: String, buildType: String) -> String {
        let moduleName = resolvedAppModule.split(separator: "/").last.map(String.init) ?? "app"
        let base = (path as NSString)
            .appendingPathComponent(resolvedAppModule)
            .appending("/build/outputs/apk")
        return (base as NSString)
            .appendingPathComponent(variant)
            .appending("/\(buildType)/\(moduleName)-\(variant)-\(buildType).apk")
    }

    private func flutterApkOutputPath(variant: String, buildType: String) -> String {
        let base = (path as NSString).appendingPathComponent("build/app/outputs/flutter-apk")
        if variant.isEmpty {
            return (base as NSString).appendingPathComponent("app-\(buildType).apk")
        }
        return (base as NSString).appendingPathComponent("app-\(variant)-\(buildType).apk")
    }

    // MARK: - AAB Output Path

    /// Returns the expected AAB output path for a given variant and build type
    func aabOutputPath(variant: String, buildType: String) -> String {
        if isFlutter {
            return flutterAabOutputPath(variant: variant, buildType: buildType)
        }
        return nativeAabOutputPath(variant: variant, buildType: buildType)
    }

    private func nativeAabOutputPath(variant: String, buildType: String) -> String {
        let moduleName = resolvedAppModule.split(separator: "/").last.map(String.init) ?? "app"
        let base = (path as NSString)
            .appendingPathComponent(resolvedAppModule)
            .appending("/build/outputs/bundle")
        return (base as NSString)
            .appendingPathComponent("\(variant)\(buildType.capitalized)")
            .appending("/\(moduleName)-\(variant)-\(buildType).aab")
    }

    private func flutterAabOutputPath(variant: String, buildType: String) -> String {
        let base = (path as NSString).appendingPathComponent("build/app/outputs/bundle")
        if variant.isEmpty {
            return (base as NSString)
                .appendingPathComponent("\(buildType)")
                .appending("/app-\(buildType).aab")
        }
        return (base as NSString)
            .appendingPathComponent("\(variant)\(buildType.capitalized)")
            .appending("/app-\(variant)-\(buildType).aab")
    }

    // MARK: - Mapping File Path

    /// Returns the expected ProGuard/R8 mapping file path
    func mappingFilePath(variant: String, buildType: String) -> String? {
        let modulePath = resolvedAppModule
        let base: String
        if isFlutter {
            base = (path as NSString)
                .appendingPathComponent("build/app/outputs/mapping")
        } else {
            base = (path as NSString)
                .appendingPathComponent(modulePath)
                .appending("/build/outputs/mapping")
        }
        let mappingPath = (base as NSString)
            .appendingPathComponent("\(variant)\(buildType.capitalized)")
            .appending("/mapping.txt")

        if FileManager.default.fileExists(atPath: mappingPath) {
            return mappingPath
        }
        // Also check variant/buildType directory structure
        let altPath = (base as NSString)
            .appendingPathComponent(variant)
            .appending("/\(buildType)/mapping.txt")
        if FileManager.default.fileExists(atPath: altPath) {
            return altPath
        }
        return nil
    }

    // MARK: - Output File Naming

    /// Available template tokens:
    ///  {name}    – project name
    ///  {variant} – build variant / flavor
    ///  {type}    – build type (debug / release)
    ///  {date}    – current date (yyyyMMdd)
    ///  {time}    – current time (HHmmss)
    ///  {timestamp} – Unix timestamp
    ///  {version} – versionName from build output (if available)
    ///  {code}    – versionCode from build output (if available)
    static let defaultTemplate = "{name}-{variant}-{type}"

    /// Resolve the output file name template into a concrete file name (without extension)
    func resolvedOutputFileName(
        variant: String,
        buildType: String,
        versionName: String? = nil,
        versionCode: String? = nil
    ) -> String {
        let template = (outputFileNameTemplate ?? "").isEmpty
            ? Self.defaultTemplate
            : outputFileNameTemplate!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateStr = dateFormatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss"
        let timeStr = timeFormatter.string(from: Date())

        var result = template
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{variant}", with: variant)
            .replacingOccurrences(of: "{type}", with: buildType)
            .replacingOccurrences(of: "{date}", with: dateStr)
            .replacingOccurrences(of: "{time}", with: timeStr)
            .replacingOccurrences(of: "{timestamp}", with: "\(Int(Date().timeIntervalSince1970))")
            .replacingOccurrences(of: "{version}", with: versionName ?? "0.0.0")
            .replacingOccurrences(of: "{code}", with: versionCode ?? "0")

        // Sanitise: remove characters invalid in file names
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        result = result.unicodeScalars.filter { !illegal.contains($0) }.map(String.init).joined()

        // Collapse consecutive dashes / spaces
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "- "))

        return result.isEmpty ? name : result
    }

    /// Copy the built APK to a renamed file next to the original; returns the new path
    func renameAPKIfNeeded(
        originalPath: String,
        variant: String,
        buildType: String,
        versionName: String? = nil,
        versionCode: String? = nil
    ) -> String {
        // Only rename when the user has set a custom template
        guard let template = outputFileNameTemplate, !template.isEmpty else {
            return originalPath
        }

        let dir = (originalPath as NSString).deletingLastPathComponent
        let ext = (originalPath as NSString).pathExtension
        let newName = resolvedOutputFileName(
            variant: variant,
            buildType: buildType,
            versionName: versionName,
            versionCode: versionCode
        )
        let newPath = (dir as NSString).appendingPathComponent("\(newName).\(ext)")

        // Don't overwrite if same path
        guard newPath != originalPath else { return originalPath }

        let fm = FileManager.default
        // Remove previous file with that name if it exists
        try? fm.removeItem(atPath: newPath)
        do {
            try fm.copyItem(atPath: originalPath, toPath: newPath)
            return newPath
        } catch {
            // If copy fails, fall back to original
            return originalPath
        }
    }

    // MARK: - Copy to Output Folder

    /// Copy or move the APK to the configured output folder (if set). Returns the destination path or nil.
    func copyAPKToOutputFolder(apkPath: String) -> String? {
        guard let outputDir = outputCopyPath, !outputDir.isEmpty else { return nil }

        let fm = FileManager.default
        // Create directory if needed
        if !fm.fileExists(atPath: outputDir) {
            try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        }

        let fileName = (apkPath as NSString).lastPathComponent
        let destPath = (outputDir as NSString).appendingPathComponent(fileName)

        // Remove existing file with same name
        try? fm.removeItem(atPath: destPath)
        do {
            if outputCopyMode == .move {
                try fm.moveItem(atPath: apkPath, toPath: destPath)
            } else {
                try fm.copyItem(atPath: apkPath, toPath: destPath)
            }
            return destPath
        } catch {
            return nil
        }
    }

    // MARK: - Auto-detect

    /// Scan the project directory and auto-detect environment settings
    mutating func autoDetectSettings() {
        let env = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: path)

        if !env.buildVariants.isEmpty {
            buildVariants = env.buildVariants
        }
        if !env.buildTypes.isEmpty {
            buildTypes = env.buildTypes
        }
        if let module = env.appModulePath {
            appModulePath = module
        }
        projectType = env.projectType
        detectedVersionName = env.versionName
        detectedVersionCode = env.versionCode
    }

    /// Create a project from a path, auto-detecting everything
    static func fromPath(_ path: String, name: String? = nil) -> AndroidProject {
        let projectName = name ?? (path as NSString).lastPathComponent
        var project = AndroidProject(
            name: projectName,
            path: path,
            buildVariants: [],
            buildTypes: ["debug", "release"]
        )
        project.autoDetectSettings()
        return project
    }

    static var defaultProjects: [AndroidProject] {
        let home = NSHomeDirectory()
        return [
            fromPath("\(home)/sera/IBID_Inspector_Apps_v2", name: "IBID Inspector Apps v2"),
            fromPath("\(home)/sera/Ibid_Mobile_ACV", name: "IBID Mobile ACV")
        ]
    }
}

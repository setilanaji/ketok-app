import Foundation

/// A snapshot of the build environment captured at build time
struct BuildEnvironmentSnapshot: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var capturedAt: Date = Date()

    // System
    var javaVersion: String?
    var javaHome: String?

    // Android SDK
    var androidHome: String?
    var compileSdkVersion: String?
    var buildToolsVersion: String?

    // Gradle
    var gradleVersion: String?
    var agpVersion: String?

    // Kotlin
    var kotlinVersion: String?

    // Flutter (if applicable)
    var flutterVersion: String?
    var dartVersion: String?
    var flutterChannel: String?

    // Git state
    var gitBranch: String?
    var gitCommitHash: String?
    var hasUncommittedChanges: Bool?

    // Project
    var variant: String?
    var buildType: String?
    var outputFormat: String?
    var versionName: String?
    var versionCode: String?

    /// Short summary for display
    var summary: String {
        var parts: [String] = []
        if let gradle = gradleVersion { parts.append("Gradle \(gradle)") }
        if let java = javaVersion { parts.append(java) }
        if let kotlin = kotlinVersion { parts.append("Kotlin \(kotlin)") }
        if let flutter = flutterVersion { parts.append("Flutter \(flutter)") }
        return parts.joined(separator: " · ")
    }

    /// Full details as key-value pairs
    var details: [(label: String, value: String)] {
        var items: [(String, String)] = []
        if let v = javaVersion { items.append(("Java", v)) }
        if let v = javaHome { items.append(("JAVA_HOME", v)) }
        if let v = androidHome { items.append(("ANDROID_HOME", v)) }
        if let v = gradleVersion { items.append(("Gradle", v)) }
        if let v = agpVersion { items.append(("AGP", v)) }
        if let v = kotlinVersion { items.append(("Kotlin", v)) }
        if let v = flutterVersion { items.append(("Flutter", v)) }
        if let v = dartVersion { items.append(("Dart", v)) }
        if let v = flutterChannel { items.append(("Channel", v)) }
        if let v = gitBranch { items.append(("Branch", v)) }
        if let v = gitCommitHash { items.append(("Commit", v)) }
        if let dirty = hasUncommittedChanges { items.append(("Dirty", dirty ? "Yes" : "No")) }
        if let v = versionName { items.append(("Version", v)) }
        if let v = versionCode { items.append(("Code", v)) }
        return items
    }
}

/// Captures build environment at build time
class BuildEnvironmentCapturer {

    /// Capture current environment for a project
    static func capture(
        project: AndroidProject,
        variant: String,
        buildType: String,
        outputFormat: BuildOutputFormat
    ) -> BuildEnvironmentSnapshot {
        var snapshot = BuildEnvironmentSnapshot()

        // Project info
        snapshot.variant = variant
        snapshot.buildType = buildType
        snapshot.outputFormat = outputFormat.rawValue
        snapshot.versionName = project.detectedVersionName
        snapshot.versionCode = project.detectedVersionCode

        // System environment
        let sysEnv = ProjectEnvironmentDetector.detectSystemEnvironment()
        snapshot.javaHome = sysEnv.javaHome
        snapshot.androidHome = sysEnv.androidHome

        // Detect Java version from JAVA_HOME
        if let javaHome = sysEnv.javaHome ?? sysEnv.androidStudioJbrPath {
            snapshot.javaVersion = detectJavaVersion(javaHome: javaHome)
        }

        // Project environment
        let projEnv = ProjectEnvironmentDetector.detectProjectEnvironment(projectPath: project.path)
        snapshot.gradleVersion = projEnv.gradleVersionDisplay
        snapshot.agpVersion = projEnv.agpVersion
        snapshot.kotlinVersion = projEnv.kotlinVersion

        // Flutter
        if project.isFlutter {
            snapshot.flutterVersion = sysEnv.flutterVersion
            snapshot.dartVersion = sysEnv.dartVersion
            snapshot.flutterChannel = sysEnv.flutterChannel
        }

        // Build tools version
        if let androidHome = sysEnv.androidHome {
            snapshot.buildToolsVersion = detectBuildToolsVersion(androidHome: androidHome)
        }

        // Git info
        snapshot.gitBranch = GitService.currentBranch(at: project.path)
        snapshot.gitCommitHash = GitService.shortHash(at: project.path)
        snapshot.hasUncommittedChanges = GitService.hasUncommittedChanges(at: project.path)

        return snapshot
    }

    /// Get Java version string from java -version
    private static func detectJavaVersion(javaHome: String) -> String? {
        let javaPath = (javaHome as NSString).appendingPathComponent("bin/java")
        guard FileManager.default.isExecutableFile(atPath: javaPath) else { return nil }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = ["-version"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            // Parse "openjdk version "17.0.6" ..." or "java version "1.8.0_..."
            if let regex = try? NSRegularExpression(pattern: #"version "([^"]+)""#),
               let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
               let range = Range(match.range(at: 1), in: output) {
                return "Java \(output[range])"
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Detect the latest installed build-tools version
    private static func detectBuildToolsVersion(androidHome: String) -> String? {
        let buildToolsDir = (androidHome as NSString).appendingPathComponent("build-tools")
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir) else {
            return nil
        }
        return versions.sorted().last
    }
}

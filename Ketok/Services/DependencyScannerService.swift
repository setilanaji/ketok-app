import Foundation

/// A parsed dependency from build.gradle
struct GradleDependency: Identifiable, Hashable {
    let id = UUID()
    let group: String          // e.g. "com.google.android.material"
    let artifact: String       // e.g. "material"
    let version: String        // e.g. "1.9.0"
    let configuration: String  // e.g. "implementation", "testImplementation"
    let isPlugin: Bool

    var coordinate: String {
        "\(group):\(artifact):\(version)"
    }

    var displayName: String {
        "\(group):\(artifact)"
    }

    /// Check if this is a Kotlin stdlib dependency
    var isKotlinStdlib: Bool {
        group == "org.jetbrains.kotlin" && artifact.hasPrefix("kotlin-stdlib")
    }

    /// Check if this is an AndroidX dependency
    var isAndroidX: Bool {
        group.hasPrefix("androidx.")
    }

    /// Check if this is a test dependency
    var isTestDependency: Bool {
        configuration.lowercased().contains("test")
    }

    /// Category for grouping
    var category: DependencyCategory {
        if isTestDependency { return .testing }
        if isAndroidX { return .androidX }
        if group.hasPrefix("com.google") { return .google }
        if isKotlinStdlib || group.hasPrefix("org.jetbrains") { return .kotlin }
        if group.hasPrefix("com.squareup") { return .squareUp }
        return .thirdParty
    }
}

enum DependencyCategory: String, CaseIterable {
    case androidX = "AndroidX"
    case google = "Google"
    case kotlin = "Kotlin/JetBrains"
    case squareUp = "Square"
    case testing = "Testing"
    case thirdParty = "Third Party"

    var icon: String {
        switch self {
        case .androidX: return "shield.fill"
        case .google: return "g.circle.fill"
        case .kotlin: return "k.circle.fill"
        case .squareUp: return "square.fill"
        case .testing: return "checkmark.circle.fill"
        case .thirdParty: return "puzzlepiece.fill"
        }
    }
}

/// A Gradle plugin dependency
struct GradlePlugin: Identifiable, Hashable {
    let id = UUID()
    let pluginId: String     // e.g. "com.android.application"
    let version: String?     // e.g. "8.1.0"

    var displayName: String {
        pluginId
    }
}

/// Scan result with all parsed dependencies
struct DependencyScanResult {
    var dependencies: [GradleDependency] = []
    var plugins: [GradlePlugin] = []
    var totalCount: Int { dependencies.count + plugins.count }
    var scanDate: Date = Date()

    /// Dependencies grouped by category
    var byCategory: [DependencyCategory: [GradleDependency]] {
        Dictionary(grouping: dependencies, by: { $0.category })
    }

    /// Count by configuration
    var byConfiguration: [String: Int] {
        var counts: [String: Int] = [:]
        for dep in dependencies {
            counts[dep.configuration, default: 0] += 1
        }
        return counts
    }
}

/// Flutter pubspec dependency
struct FlutterDependency: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let version: String?
    let isDevDependency: Bool
    let source: DependencySource

    enum DependencySource: String, Hashable {
        case pub = "pub.dev"
        case git = "git"
        case path = "local path"
        case sdk = "SDK"
    }

    var displayVersion: String {
        version ?? "any"
    }
}

/// Scans build.gradle / pubspec.yaml for dependencies
class DependencyScannerService: ObservableObject {
    @Published var scanResult: DependencyScanResult?
    @Published var flutterDependencies: [FlutterDependency] = []
    @Published var isScanning = false
    @Published var error: String?

    /// Scan a project's dependencies
    func scan(project: AndroidProject) {
        isScanning = true
        error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if project.isFlutter {
                let deps = Self.parseFlutterDependencies(projectPath: project.path)
                let gradleResult = Self.parseGradleDependencies(
                    projectPath: (project.path as NSString).appendingPathComponent("android"),
                    appModulePath: "app"
                )
                DispatchQueue.main.async {
                    self?.flutterDependencies = deps
                    self?.scanResult = gradleResult
                    self?.isScanning = false
                }
            } else {
                let result = Self.parseGradleDependencies(
                    projectPath: project.path,
                    appModulePath: project.resolvedAppModule
                )
                DispatchQueue.main.async {
                    self?.scanResult = result
                    self?.isScanning = false
                }
            }
        }
    }

    // MARK: - Gradle Parsing

    /// Parse dependencies from build.gradle(.kts)
    static func parseGradleDependencies(projectPath: String, appModulePath: String) -> DependencyScanResult {
        var result = DependencyScanResult()

        // Parse app module's build.gradle
        let ktsPath = (projectPath as NSString).appendingPathComponent("\(appModulePath)/build.gradle.kts")
        let groovyPath = (projectPath as NSString).appendingPathComponent("\(appModulePath)/build.gradle")

        let content: String?
        if let kts = try? String(contentsOfFile: ktsPath, encoding: .utf8) {
            content = kts
        } else {
            content = try? String(contentsOfFile: groovyPath, encoding: .utf8)
        }

        if let content = content {
            result.dependencies = parseDependencyBlock(from: content)
            result.plugins = parsePlugins(from: content)
        }

        // Also parse root build.gradle for plugins
        let rootKts = (projectPath as NSString).appendingPathComponent("build.gradle.kts")
        let rootGroovy = (projectPath as NSString).appendingPathComponent("build.gradle")
        if let rootContent = try? String(contentsOfFile: rootKts, encoding: .utf8) ?? (try? String(contentsOfFile: rootGroovy, encoding: .utf8)) {
            let rootPlugins = parsePlugins(from: rootContent)
            for plugin in rootPlugins {
                if !result.plugins.contains(where: { $0.pluginId == plugin.pluginId }) {
                    result.plugins.append(plugin)
                }
            }
        }

        return result
    }

    /// Parse the dependencies { } block
    private static func parseDependencyBlock(from content: String) -> [GradleDependency] {
        var deps: [GradleDependency] = []

        // Configuration types
        let configs = ["implementation", "api", "compileOnly", "runtimeOnly",
                       "testImplementation", "testRuntimeOnly",
                       "androidTestImplementation", "kapt", "ksp", "annotationProcessor",
                       "debugImplementation", "releaseImplementation"]

        for config in configs {
            // Pattern 1: implementation("group:artifact:version")  (KTS)
            let ktsPattern = "\(config)\\s*\\(\\s*[\"']([^:\"']+):([^:\"']+):([^\"']+)[\"']\\s*\\)"
            if let regex = try? NSRegularExpression(pattern: ktsPattern) {
                let range = NSRange(content.startIndex..., in: content)
                for match in regex.matches(in: content, range: range) {
                    if let groupRange = Range(match.range(at: 1), in: content),
                       let artifactRange = Range(match.range(at: 2), in: content),
                       let versionRange = Range(match.range(at: 3), in: content) {
                        deps.append(GradleDependency(
                            group: String(content[groupRange]),
                            artifact: String(content[artifactRange]),
                            version: String(content[versionRange]),
                            configuration: config,
                            isPlugin: false
                        ))
                    }
                }
            }

            // Pattern 2: implementation 'group:artifact:version'  (Groovy)
            let groovyPattern = "\(config)\\s+[\"']([^:\"']+):([^:\"']+):([^\"']+)[\"']"
            if let regex = try? NSRegularExpression(pattern: groovyPattern) {
                let range = NSRange(content.startIndex..., in: content)
                for match in regex.matches(in: content, range: range) {
                    if let groupRange = Range(match.range(at: 1), in: content),
                       let artifactRange = Range(match.range(at: 2), in: content),
                       let versionRange = Range(match.range(at: 3), in: content) {
                        let coord = "\(content[groupRange]):\(content[artifactRange])"
                        // Avoid duplicates
                        if !deps.contains(where: { $0.displayName == coord && $0.configuration == config }) {
                            deps.append(GradleDependency(
                                group: String(content[groupRange]),
                                artifact: String(content[artifactRange]),
                                version: String(content[versionRange]),
                                configuration: config,
                                isPlugin: false
                            ))
                        }
                    }
                }
            }
        }

        return deps
    }

    /// Parse plugins { } block
    private static func parsePlugins(from content: String) -> [GradlePlugin] {
        var plugins: [GradlePlugin] = []

        // KTS: id("com.android.application") version "8.1.0"
        let ktsPattern = #"id\s*\(\s*["']([^"']+)["']\s*\)\s*(?:version\s+["']([^"']+)["'])?"#
        if let regex = try? NSRegularExpression(pattern: ktsPattern) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let idRange = Range(match.range(at: 1), in: content) {
                    let pluginId = String(content[idRange])
                    var version: String?
                    if match.range(at: 2).location != NSNotFound,
                       let vRange = Range(match.range(at: 2), in: content) {
                        version = String(content[vRange])
                    }
                    plugins.append(GradlePlugin(pluginId: pluginId, version: version))
                }
            }
        }

        // Groovy: apply plugin: 'com.android.application'
        let groovyPattern = #"apply\s+plugin:\s*["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: groovyPattern) {
            let range = NSRange(content.startIndex..., in: content)
            for match in regex.matches(in: content, range: range) {
                if let idRange = Range(match.range(at: 1), in: content) {
                    let pluginId = String(content[idRange])
                    if !plugins.contains(where: { $0.pluginId == pluginId }) {
                        plugins.append(GradlePlugin(pluginId: pluginId, version: nil))
                    }
                }
            }
        }

        return plugins
    }

    // MARK: - Flutter Parsing

    /// Parse pubspec.yaml dependencies
    static func parseFlutterDependencies(projectPath: String) -> [FlutterDependency] {
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard let content = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else {
            return []
        }

        var deps: [FlutterDependency] = []
        var inDependencies = false
        var inDevDependencies = false
        var currentSection = false

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect section headers (top-level, no indentation)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                inDependencies = trimmed.hasPrefix("dependencies:")
                inDevDependencies = trimmed.hasPrefix("dev_dependencies:")
                currentSection = inDependencies || inDevDependencies
                continue
            }

            guard currentSection else { continue }

            // Skip sub-keys (git:, path:, sdk:, url:, ref:)
            if trimmed.hasPrefix("git:") || trimmed.hasPrefix("path:") ||
               trimmed.hasPrefix("sdk:") || trimmed.hasPrefix("url:") ||
               trimmed.hasPrefix("ref:") || trimmed.hasPrefix("version:") {
                continue
            }

            // Parse "  package_name: ^1.2.3" or "  package_name:"
            if line.hasPrefix("  ") && !line.hasPrefix("    ") && trimmed.contains(":") {
                let parts = trimmed.split(separator: ":", maxSplits: 1)
                let name = String(parts[0]).trimmingCharacters(in: .whitespaces)

                // Skip flutter SDK itself and meta entries
                if name == "flutter" || name == "flutter_test" || name == "flutter_localizations" {
                    continue
                }

                var version: String?
                var source: FlutterDependency.DependencySource = .pub

                if parts.count > 1 {
                    let versionStr = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    if !versionStr.isEmpty {
                        version = versionStr
                    }
                }

                deps.append(FlutterDependency(
                    name: name,
                    version: version,
                    isDevDependency: inDevDependencies,
                    source: source
                ))
            }
        }

        return deps
    }
}

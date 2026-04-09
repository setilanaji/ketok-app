import Foundation

/// Detected environment info for an Android project
struct ProjectEnvironment {
    var sdkDir: String?
    var gradleVersion: String?
    var gradleWrapperUrl: String?
    var javaVersion: String?
    var kotlinVersion: String?
    var agpVersion: String?
    var buildVariants: [String]
    var buildTypes: [String]
    var appModulePath: String?  // e.g. "app" or "app-commercial/app"
    var buildGradleType: GradleFileType
    var projectType: ProjectType  // .native or .flutter

    // App version info (from build.gradle or pubspec.yaml)
    var versionName: String?      // e.g. "1.2.3"
    var versionCode: String?      // e.g. "42"

    // Flutter-specific
    var flutterVersion: String?
    var dartVersion: String?
    var pubspecName: String?      // App name from pubspec.yaml

    // FVM (Flutter Version Management)
    var usesFvm: Bool = false
    var fvmFlutterVersion: String?   // Version pinned in .fvmrc or fvm_config.json
    var fvmSdkPath: String?          // Resolved path to FVM-managed Flutter SDK

    enum GradleFileType: String {
        case groovy = "build.gradle"
        case kotlin = "build.gradle.kts"
        case none = "not found"
    }

    /// Summary for display
    var gradleVersionDisplay: String {
        if let url = gradleWrapperUrl,
           let match = url.range(of: #"gradle-(.+?)-(bin|all)\.zip"#, options: .regularExpression) {
            let versionPart = url[match]
            return versionPart
                .replacingOccurrences(of: "gradle-", with: "")
                .replacingOccurrences(of: "-bin.zip", with: "")
                .replacingOccurrences(of: "-all.zip", with: "")
        }
        return gradleVersion ?? "Unknown"
    }
}

/// System-level environment detection
struct SystemEnvironment {
    var javaHome: String?
    var androidHome: String?
    var androidStudioJbrPath: String?
    var globalGradleVersion: String?

    // Flutter environment
    var flutterHome: String?
    var flutterVersion: String?
    var dartVersion: String?
    var flutterChannel: String?
}

/// Detects project and system environment settings by reading actual project files
class ProjectEnvironmentDetector {

    // MARK: - System-level detection

    static func detectSystemEnvironment() -> SystemEnvironment {
        var env = SystemEnvironment()

        // JAVA_HOME
        env.javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"]
            ?? runCommand("/usr/libexec/java_home", args: [])

        // Android Studio bundled JBR
        let jbrPath = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        if FileManager.default.fileExists(atPath: jbrPath) {
            env.androidStudioJbrPath = jbrPath
        }

        // ANDROID_HOME
        env.androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"]
            ?? ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"]
            ?? {
                let home = NSHomeDirectory()
                let defaultPath = "\(home)/Library/Android/sdk"
                return FileManager.default.fileExists(atPath: defaultPath) ? defaultPath : nil
            }()

        // Global Gradle
        env.globalGradleVersion = runCommand("/bin/bash", args: ["-c", "gradle --version 2>/dev/null | grep 'Gradle ' | head -1"])

        // Flutter SDK
        env.flutterHome = detectFlutterHome()
        if env.flutterHome != nil {
            let versionInfo = detectFlutterVersion()
            env.flutterVersion = versionInfo.flutter
            env.dartVersion = versionInfo.dart
            env.flutterChannel = versionInfo.channel
        }

        return env
    }

    // MARK: - Flutter SDK Detection

    /// Find the Flutter SDK path
    private static func detectFlutterHome() -> String? {
        // Check FLUTTER_HOME / FLUTTER_ROOT env vars
        if let home = ProcessInfo.processInfo.environment["FLUTTER_HOME"],
           FileManager.default.fileExists(atPath: "\(home)/bin/flutter") {
            return home
        }
        if let root = ProcessInfo.processInfo.environment["FLUTTER_ROOT"],
           FileManager.default.fileExists(atPath: "\(root)/bin/flutter") {
            return root
        }

        // Try `which flutter` to find the binary
        if let flutterBin = runCommand("/usr/bin/which", args: ["flutter"]) {
            // Resolve symlinks to get the actual SDK path
            let resolved = (flutterBin as NSString).resolvingSymlinksInPath
            // flutter binary is at <SDK>/bin/flutter
            let sdkPath = ((resolved as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
            if FileManager.default.fileExists(atPath: "\(sdkPath)/bin/flutter") {
                return sdkPath
            }
        }

        // Common installation paths
        let home = NSHomeDirectory()
        let commonPaths = [
            "\(home)/flutter",
            "\(home)/development/flutter",
            "\(home)/.flutter",
            "/usr/local/flutter",
            "/opt/flutter",
            // fvm (Flutter Version Management)
            "\(home)/fvm/default"
        ]
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: "\(path)/bin/flutter") {
                return path
            }
        }

        return nil
    }

    /// Get Flutter and Dart versions
    private static func detectFlutterVersion() -> (flutter: String?, dart: String?, channel: String?) {
        guard let output = runCommand("/bin/bash", args: ["-c", "flutter --version --machine 2>/dev/null"]) else {
            // Fallback: non-machine output
            if let textOutput = runCommand("/bin/bash", args: ["-c", "flutter --version 2>/dev/null"]) {
                let flutter = extractPattern(#"Flutter (\d+\.\d+\.\d+)"#, from: textOutput)
                let dart = extractPattern(#"Dart (\d+\.\d+\.\d+)"#, from: textOutput)
                let channel = extractPattern(#"channel (\w+)"#, from: textOutput)
                return (flutter, dart, channel)
            }
            return (nil, nil, nil)
        }

        // Parse JSON output from `flutter --version --machine`
        if let data = output.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let flutter = json["frameworkVersion"] as? String
            let dart = json["dartSdkVersion"] as? String
            let channel = json["channel"] as? String
            return (flutter, dart?.components(separatedBy: " ").first, channel)
        }

        return (nil, nil, nil)
    }

    /// Get the flutter executable path
    static func flutterExecutablePath() -> String? {
        if let home = detectFlutterHome() {
            return "\(home)/bin/flutter"
        }
        // Try PATH
        return runCommand("/usr/bin/which", args: ["flutter"])
    }

    // MARK: - Per-project detection

    static func detectProjectEnvironment(projectPath: String) -> ProjectEnvironment {
        var env = ProjectEnvironment(
            buildVariants: [],
            buildTypes: [],
            buildGradleType: .none,
            projectType: .native
        )

        // Check if this is a Flutter project
        let isFlutter = isFlutterProject(at: projectPath)
        env.projectType = isFlutter ? .flutter : .native

        if isFlutter {
            // Parse Flutter-specific info
            let flutterInfo = parseFlutterProject(projectPath: projectPath)
            env.pubspecName = flutterInfo.name
            env.flutterVersion = flutterInfo.flutterConstraint
            env.dartVersion = flutterInfo.dartConstraint
            env.versionName = flutterInfo.versionName
            env.versionCode = flutterInfo.versionCode

            // Detect FVM (Flutter Version Management)
            let fvmInfo = detectFvm(projectPath: projectPath)
            env.usesFvm = fvmInfo.usesFvm
            env.fvmFlutterVersion = fvmInfo.version
            env.fvmSdkPath = fvmInfo.sdkPath

            // Flutter still has an android/ subfolder with Gradle config
            let androidPath = (projectPath as NSString).appendingPathComponent("android")

            // Find app module inside android/
            env.appModulePath = "app"  // Flutter always uses android/app

            // Parse android/app/build.gradle for flavors
            let buildInfo = parseBuildGradle(projectPath: androidPath, appModulePath: "app")
            env.buildVariants = buildInfo.variants
            env.buildTypes = buildInfo.buildTypes
            env.buildGradleType = buildInfo.fileType

            // Parse android/local.properties
            env.sdkDir = parseLocalProperties(projectPath: androidPath)

            // Parse gradle wrapper
            let wrapperInfo = parseGradleWrapper(projectPath: androidPath, appModulePath: "app")
            env.gradleVersion = wrapperInfo.version
            env.gradleWrapperUrl = wrapperInfo.url

        } else {
            // Native Android detection (existing logic)

            // 1. Find the app module
            let appModulePath = findAppModule(in: projectPath)
            env.appModulePath = appModulePath

            // 2. Parse local.properties for sdk.dir
            env.sdkDir = parseLocalProperties(projectPath: projectPath)

            // 3. Parse gradle-wrapper.properties
            let wrapperInfo = parseGradleWrapper(projectPath: projectPath, appModulePath: appModulePath)
            env.gradleVersion = wrapperInfo.version
            env.gradleWrapperUrl = wrapperInfo.url

            // 4. Parse build.gradle(.kts) for variants, buildTypes, kotlin, agp versions
            let buildInfo = parseBuildGradle(projectPath: projectPath, appModulePath: appModulePath)
            env.buildVariants = buildInfo.variants
            env.buildTypes = buildInfo.buildTypes
            env.kotlinVersion = buildInfo.kotlinVersion
            env.agpVersion = buildInfo.agpVersion
            env.buildGradleType = buildInfo.fileType

            // 5. Detect Java version from project config
            env.javaVersion = buildInfo.javaVersion

            // 6. Version info
            env.versionName = buildInfo.versionName
            env.versionCode = buildInfo.versionCode
        }

        return env
    }

    // MARK: - FVM (Flutter Version Management) Detection

    /// Detect if the project uses FVM for Flutter version management
    private static func detectFvm(projectPath: String) -> (usesFvm: Bool, version: String?, sdkPath: String?) {
        let fm = FileManager.default

        // Strategy 1: Check .fvmrc (FVM 3.x format — simple version string)
        let fvmrcPath = (projectPath as NSString).appendingPathComponent(".fvmrc")
        if let fvmrc = try? String(contentsOfFile: fvmrcPath, encoding: .utf8) {
            let version = fvmrc.trimmingCharacters(in: .whitespacesAndNewlines)
            if !version.isEmpty {
                let sdkPath = resolveFvmSdkPath(projectPath: projectPath, version: version)
                return (true, version, sdkPath)
            }
        }

        // Strategy 2: Check .fvm/fvm_config.json (FVM 2.x format)
        let configPath = (projectPath as NSString).appendingPathComponent(".fvm/fvm_config.json")
        if let data = fm.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // FVM 3.x: { "flutter": "3.32.8" }
            // FVM 2.x: { "flutterSdkVersion": "3.32.8" }
            let version = (json["flutter"] as? String) ?? (json["flutterSdkVersion"] as? String)
            if let ver = version {
                let sdkPath = resolveFvmSdkPath(projectPath: projectPath, version: ver)
                return (true, ver, sdkPath)
            }
        }

        // Strategy 3: Check .fvm/flutter_sdk symlink
        let symlinkPath = (projectPath as NSString).appendingPathComponent(".fvm/flutter_sdk")
        if let resolved = try? fm.destinationOfSymbolicLink(atPath: symlinkPath) {
            // Extract version from path like $HOME/fvm/versions/3.32.8
            let version = (resolved as NSString).lastPathComponent
            if fm.fileExists(atPath: "\(resolved)/bin/flutter") {
                return (true, version, resolved)
            }
        }

        return (false, nil, nil)
    }

    /// Resolve the FVM SDK path for a given Flutter version
    private static func resolveFvmSdkPath(projectPath: String, version: String) -> String? {
        let fm = FileManager.default

        // First: check local .fvm/flutter_sdk symlink (preferred — always correct)
        let localSdk = (projectPath as NSString).appendingPathComponent(".fvm/flutter_sdk")
        if let resolved = try? fm.destinationOfSymbolicLink(atPath: localSdk),
           fm.fileExists(atPath: "\(resolved)/bin/flutter") {
            return resolved
        }

        // Second: check common FVM cache locations
        let home = NSHomeDirectory()
        let cachePaths = [
            "\(home)/fvm/versions/\(version)",           // FVM 3.x default
            "\(home)/.fvm/versions/\(version)",           // FVM 2.x default
            "\(home)/fvm/default",                         // FVM global default
        ]
        for path in cachePaths {
            if fm.fileExists(atPath: "\(path)/bin/flutter") {
                return path
            }
        }

        return nil
    }

    /// Resolve a flutter/dart command to use FVM when available.
    ///
    /// Usage:
    /// ```
    /// let cmd = ProjectEnvironmentDetector.resolveFlutterCommand(
    ///     "flutter pub get", projectPath: projectPath
    /// )
    /// // Returns "fvm flutter pub get" if fvm is installed and project uses it,
    /// // or uses .fvm/flutter_sdk/bin/flutter if fvm CLI is not available
    /// ```
    static func resolveFlutterCommand(_ command: String, projectPath: String) -> String {
        let projectEnv = detectProjectEnvironment(projectPath: projectPath)

        guard projectEnv.usesFvm else {
            return command  // No FVM — use bare command
        }

        // Check if `fvm` CLI is available on PATH
        let fvmAvailable = runCommand("/usr/bin/which", args: ["fvm"]) != nil

        if fvmAvailable {
            // Prefix with `fvm` — it will use the project-pinned version
            if command.hasPrefix("flutter ") {
                return "fvm \(command)"
            } else if command.hasPrefix("dart ") {
                return "fvm \(command)"
            }
        } else if let sdkPath = projectEnv.fvmSdkPath {
            // FVM CLI not available, but we have the SDK path — use it directly
            let binPath = (sdkPath as NSString).appendingPathComponent("bin")
            if command.hasPrefix("flutter ") {
                let subCommand = String(command.dropFirst("flutter ".count))
                return "\(binPath)/flutter \(subCommand)"
            } else if command.hasPrefix("dart ") {
                let subCommand = String(command.dropFirst("dart ".count))
                return "\(binPath)/dart \(subCommand)"
            }
        }

        return command
    }

    // MARK: - Flutter Project Detection

    /// Check if a path is a Flutter project
    static func isFlutterProject(at path: String) -> Bool {
        let fm = FileManager.default
        let pubspecPath = (path as NSString).appendingPathComponent("pubspec.yaml")
        let libPath = (path as NSString).appendingPathComponent("lib")

        // Flutter = has pubspec.yaml + lib/ directory
        return fm.fileExists(atPath: pubspecPath) && fm.fileExists(atPath: libPath)
    }

    /// Parse pubspec.yaml for Flutter project info
    private static func parseFlutterProject(projectPath: String) -> (name: String?, flutterConstraint: String?, dartConstraint: String?, versionName: String?, versionCode: String?) {
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard let content = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else {
            return (nil, nil, nil, nil, nil)
        }

        var name: String?
        var dartConstraint: String?
        var flutterConstraint: String?
        var versionName: String?
        var versionCode: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // name: my_app (top-level, not indented)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.hasPrefix("name:") {
                name = trimmed.replacingOccurrences(of: "name:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }

            // version: 1.2.3+4 (top-level)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && trimmed.hasPrefix("version:") {
                let versionStr = trimmed.replacingOccurrences(of: "version:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                // Split "1.2.3+4" into versionName="1.2.3" and versionCode="4"
                let parts = versionStr.split(separator: "+", maxSplits: 1)
                if let first = parts.first {
                    versionName = String(first)
                }
                if parts.count > 1 {
                    versionCode = String(parts[1])
                }
            }

            // sdk: '^3.9.2' or sdk: ">=3.0.0 <4.0.0"
            if trimmed.hasPrefix("sdk:") && dartConstraint == nil {
                dartConstraint = trimmed.replacingOccurrences(of: "sdk:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            }

            // flutter: '>=3.0.0'
            if trimmed.hasPrefix("flutter:") && flutterConstraint == nil {
                let val = trimmed.replacingOccurrences(of: "flutter:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !val.isEmpty && val != "" {
                    flutterConstraint = val
                }
            }
        }

        return (name, flutterConstraint, dartConstraint, versionName, versionCode)
    }

    // MARK: - Find app module

    /// Searches for the main app module. Supports:
    ///  - Standard "app/" module
    ///  - Multi-app like "app-commercial/app/", "app-professional/app/"
    private static func findAppModule(in projectPath: String) -> String? {
        let fm = FileManager.default

        // Check standard "app/build.gradle(.kts)"
        for ext in ["build.gradle.kts", "build.gradle"] {
            let standardPath = (projectPath as NSString).appendingPathComponent("app/\(ext)")
            if fm.fileExists(atPath: standardPath) {
                return "app"
            }
        }

        // Check for multi-module app-*/app/ pattern
        let rootContents = (try? fm.contentsOfDirectory(atPath: projectPath)) ?? []
        let appDirs = rootContents.filter { $0.hasPrefix("app-") }
        for appDir in appDirs.sorted() {
            for ext in ["build.gradle.kts", "build.gradle"] {
                let path = (projectPath as NSString)
                    .appendingPathComponent("\(appDir)/app/\(ext)")
                if fm.fileExists(atPath: path) {
                    return "\(appDir)/app"
                }
            }
            // Also check if the app-* dir itself has the build file (no nested app/)
            for ext in ["build.gradle.kts", "build.gradle"] {
                let path = (projectPath as NSString)
                    .appendingPathComponent("\(appDir)/\(ext)")
                if fm.fileExists(atPath: path) {
                    return appDir
                }
            }
        }

        return nil
    }

    // MARK: - Parse local.properties

    private static func parseLocalProperties(projectPath: String) -> String? {
        let filePath = (projectPath as NSString).appendingPathComponent("local.properties")
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return nil }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("sdk.dir=") {
                return String(trimmed.dropFirst("sdk.dir=".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    // MARK: - Parse gradle-wrapper.properties

    private static func parseGradleWrapper(projectPath: String, appModulePath: String?) -> (version: String?, url: String?) {
        let candidates: [String] = [
            (projectPath as NSString).appendingPathComponent("gradle/wrapper/gradle-wrapper.properties"),
            appModulePath.map { (projectPath as NSString).appendingPathComponent("\($0)/../gradle/wrapper/gradle-wrapper.properties") },
            appModulePath.map {
                let appDir = ($0 as NSString).deletingLastPathComponent
                return (projectPath as NSString).appendingPathComponent("\(appDir)/gradle/wrapper/gradle-wrapper.properties")
            }
        ].compactMap { $0 }

        for candidate in candidates {
            let resolved = (candidate as NSString).standardizingPath
            guard let content = try? String(contentsOfFile: resolved, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("distributionUrl=") || trimmed.hasPrefix("distributionUrl =") {
                    let url = trimmed
                        .replacingOccurrences(of: "distributionUrl=", with: "")
                        .replacingOccurrences(of: "distributionUrl =", with: "")
                        .replacingOccurrences(of: "\\:", with: ":")
                        .trimmingCharacters(in: .whitespaces)

                    let version = extractGradleVersion(from: url)
                    return (version, url)
                }
            }
        }
        return (nil, nil)
    }

    private static func extractGradleVersion(from url: String) -> String? {
        guard let range = url.range(of: #"gradle-(.+?)-(bin|all)"#, options: .regularExpression) else {
            return nil
        }
        return String(url[range])
            .replacingOccurrences(of: "gradle-", with: "")
            .replacingOccurrences(of: "-bin", with: "")
            .replacingOccurrences(of: "-all", with: "")
    }

    // MARK: - Parse build.gradle(.kts)

    struct BuildGradleInfo {
        var variants: [String]
        var buildTypes: [String]
        var kotlinVersion: String?
        var agpVersion: String?
        var javaVersion: String?
        var versionName: String?
        var versionCode: String?
        var fileType: ProjectEnvironment.GradleFileType
    }

    private static func parseBuildGradle(projectPath: String, appModulePath: String?) -> BuildGradleInfo {
        var info = BuildGradleInfo(
            variants: [],
            buildTypes: ["debug", "release"],  // defaults
            fileType: .none
        )

        guard let modulePath = appModulePath else { return info }

        let ktsPath = (projectPath as NSString).appendingPathComponent("\(modulePath)/build.gradle.kts")
        let groovyPath = (projectPath as NSString).appendingPathComponent("\(modulePath)/build.gradle")

        var content: String?
        if let kts = try? String(contentsOfFile: ktsPath, encoding: .utf8) {
            content = kts
            info.fileType = .kotlin
        } else if let groovy = try? String(contentsOfFile: groovyPath, encoding: .utf8) {
            content = groovy
            info.fileType = .groovy
        }

        guard let buildContent = content else { return info }

        info.variants = extractProductFlavors(from: buildContent, isKts: info.fileType == .kotlin)

        let customBuildTypes = extractBuildTypes(from: buildContent, isKts: info.fileType == .kotlin)
        if !customBuildTypes.isEmpty {
            info.buildTypes = customBuildTypes
        }

        info.javaVersion = extractJavaVersion(from: buildContent)
        info.versionName = extractVersionName(from: buildContent)
        info.versionCode = extractVersionCode(from: buildContent)

        // Parse root build.gradle for kotlin and AGP versions
        let rootKtsPath = (projectPath as NSString).appendingPathComponent("build.gradle.kts")
        let rootGroovyPath = (projectPath as NSString).appendingPathComponent("build.gradle")

        if let rootContent = try? String(contentsOfFile: rootKtsPath, encoding: .utf8) {
            info.kotlinVersion = extractKotlinVersion(from: rootContent)
            info.agpVersion = extractAGPVersion(from: rootContent)
        } else if let rootContent = try? String(contentsOfFile: rootGroovyPath, encoding: .utf8) {
            info.kotlinVersion = extractKotlinVersion(from: rootContent)
            info.agpVersion = extractAGPVersion(from: rootContent)
        }

        return info
    }

    /// Extract flavor names from productFlavors block
    private static func extractProductFlavors(from content: String, isKts: Bool) -> [String] {
        var flavors: [String] = []

        guard let pfRange = content.range(of: "productFlavors") else { return flavors }
        let afterPF = String(content[pfRange.upperBound...])
        let pfBlock = extractBlock(from: afterPF)

        // KTS style: create("dev") { ... }
        let ktsPattern = #"create\("(\w+)"\)"#
        if let regex = try? NSRegularExpression(pattern: ktsPattern) {
            let range = NSRange(pfBlock.startIndex..., in: pfBlock)
            let matches = regex.matches(in: pfBlock, range: range)
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: pfBlock) {
                    let name = String(pfBlock[nameRange])
                    if !flavors.contains(name) {
                        flavors.append(name)
                    }
                }
            }
        }

        // Groovy style: dev { ... }
        if flavors.isEmpty {
            let groovyPattern = #"^\s+(\w+)\s*\{"#
            if let regex = try? NSRegularExpression(pattern: groovyPattern, options: .anchorsMatchLines) {
                let range = NSRange(pfBlock.startIndex..., in: pfBlock)
                let matches = regex.matches(in: pfBlock, range: range)
                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: pfBlock) {
                        let name = String(pfBlock[nameRange])
                        let skipKeywords = ["productFlavors", "buildTypes", "compileOptions",
                                            "kotlinOptions", "buildFeatures", "sonarqube",
                                            "testOptions", "packaging", "composeOptions",
                                            "dependencies", "release", "debug"]
                        if !skipKeywords.contains(name) && !flavors.contains(name) {
                            flavors.append(name)
                        }
                    }
                }
            }
        }

        return flavors
    }

    /// Extract the content inside the first { ... } block
    private static func extractBlock(from text: String) -> String {
        var depth = 0
        var started = false
        var startIdx: String.Index?
        var endIdx: String.Index?

        for (offset, char) in text.enumerated() {
            let idx = text.index(text.startIndex, offsetBy: offset)
            if char == "{" {
                if !started {
                    started = true
                    startIdx = text.index(after: idx)
                }
                depth += 1
            } else if char == "}" {
                depth -= 1
                if depth == 0 && started {
                    endIdx = idx
                    break
                }
            }
        }

        guard let start = startIdx, let end = endIdx, start < end else {
            return String(text.prefix(500))
        }
        return String(text[start..<end])
    }

    /// Extract build types
    private static func extractBuildTypes(from content: String, isKts: Bool) -> [String] {
        var types: [String] = []

        guard let btRange = content.range(of: "buildTypes") else { return types }
        let afterBT = String(content[btRange.upperBound...])
        let btBlock = extractBlock(from: afterBT)

        let patterns = [
            #"(\w+)\s*\{"#,
            #"create\("(\w+)"\)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                let range = NSRange(btBlock.startIndex..., in: btBlock)
                let matches = regex.matches(in: btBlock, range: range)
                for match in matches {
                    if let nameRange = Range(match.range(at: 1), in: btBlock) {
                        let name = String(btBlock[nameRange])
                        let skipKeywords = ["buildTypes", "flavorDimensions", "productFlavors",
                                            "compileOptions", "kotlinOptions", "buildFeatures",
                                            "isMinifyEnabled", "isShrinkResources", "proguardFiles",
                                            "signingConfig", "matchingFallbacks"]
                        if !skipKeywords.contains(name) && !types.contains(name) {
                            types.append(name)
                        }
                    }
                }
            }
        }

        if !types.contains("debug") { types.insert("debug", at: 0) }
        if !types.contains("release") { types.append("release") }

        return types
    }

    /// Extract versionName from build.gradle
    private static func extractVersionName(from content: String) -> String? {
        // Groovy: versionName "1.2.3" or versionName '1.2.3'
        // KTS: versionName = "1.2.3"
        let patterns = [
            #"versionName\s*=?\s*["']([^"']+)["']"#,
        ]
        for pattern in patterns {
            if let result = extractPattern(pattern, from: content) {
                return result
            }
        }
        return nil
    }

    /// Extract versionCode from build.gradle
    private static func extractVersionCode(from content: String) -> String? {
        // Groovy: versionCode 42
        // KTS: versionCode = 42
        let patterns = [
            #"versionCode\s*=?\s*(\d+)"#,
        ]
        for pattern in patterns {
            if let result = extractPattern(pattern, from: content) {
                return result
            }
        }
        return nil
    }

    /// Extract Java compatibility version
    private static func extractJavaVersion(from content: String) -> String? {
        let pattern = #"JavaVersion\.VERSION_(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            return "Java \(content[range])"
        }
        return nil
    }

    /// Extract Kotlin version
    private static func extractKotlinVersion(from content: String) -> String? {
        let patterns = [
            #"kotlin-gradle-plugin:(\d+\.\d+\.\d+)"#,
            #"ext\.kotlin_version\s*=\s*["\'](\d+\.\d+\.\d+)["\']"#,
            #"kotlin_version\s*=\s*["\'](\d+\.\d+\.\d+)["\']"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
        }
        return nil
    }

    /// Extract Android Gradle Plugin version
    private static func extractAGPVersion(from content: String) -> String? {
        let patterns = [
            #"com\.android\.tools\.build:gradle:(\d+\.\d+\.\d+)"#,
            #"com\.android\.application.*version\s+["\'](\d+\.\d+\.\d+)["\']"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
               let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func runCommand(_ executable: String, args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output?.isEmpty == true ? nil : output
        } catch {
            return nil
        }
    }

    private static func extractPattern(_ pattern: String, from text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

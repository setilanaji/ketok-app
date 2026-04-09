import Foundation

/// Represents a compatibility issue between Android build tools
struct CompatibilityIssue: Identifiable {
    let id = UUID()
    let severity: Severity
    let title: String
    let detail: String
    let fix: FixAction?

    enum Severity: String {
        case error = "Error"       // Will definitely break the build
        case warning = "Warning"   // May cause issues or deprecation
        case info = "Info"         // Suggestion for improvement
    }

    struct FixAction {
        let label: String
        let filePath: String        // File to modify
        let oldValue: String        // Current value (for display)
        let newValue: String        // Recommended value
        let searchPattern: String   // Regex to find and replace
    }
}

/// Compatibility report from a full scan
struct CompatibilityReport {
    let issues: [CompatibilityIssue]
    let scannedAt: Date
    let agpVersion: String?
    let gradleVersion: String?
    let kotlinVersion: String?
    let jdkVersion: String?
    let compileSdk: String?
    let minSdk: String?
    let targetSdk: String?

    var hasErrors: Bool { issues.contains { $0.severity == .error } }
    var hasWarnings: Bool { issues.contains { $0.severity == .warning } }
    var errorCount: Int { issues.filter { $0.severity == .error }.count }
    var warningCount: Int { issues.filter { $0.severity == .warning }.count }

    var summary: String {
        if issues.isEmpty { return "All checks passed" }
        var parts: [String] = []
        let errors = errorCount
        let warnings = warningCount
        if errors > 0 { parts.append("\(errors) error\(errors == 1 ? "" : "s")") }
        if warnings > 0 { parts.append("\(warnings) warning\(warnings == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

/// Validates compatibility between AGP, Gradle, Kotlin, JDK, and SDK versions.
///
/// Android Gradle Plugin has strict requirements for Gradle wrapper version and JDK.
/// Kotlin version must also be compatible with the AGP version in use.
/// This service checks the official compatibility matrices and flags issues before build.
class GradleCompatibilityService {

    // MARK: - AGP → Minimum Gradle Version Matrix
    // Source: https://developer.android.com/build/releases/gradle-plugin#updating-gradle

    private static let agpGradleMatrix: [(agpRange: ClosedRange<SemVer>, minGradle: SemVer, maxGradle: SemVer?)] = [
        // AGP 8.8 → Gradle 8.10.2+
        (SemVer(8,8,0)...SemVer(8,8,99), SemVer(8,10,2), nil),
        // AGP 8.7 → Gradle 8.9+
        (SemVer(8,7,0)...SemVer(8,7,99), SemVer(8,9,0), nil),
        // AGP 8.6 → Gradle 8.7+
        (SemVer(8,6,0)...SemVer(8,6,99), SemVer(8,7,0), nil),
        // AGP 8.5 → Gradle 8.7+
        (SemVer(8,5,0)...SemVer(8,5,99), SemVer(8,7,0), nil),
        // AGP 8.4 → Gradle 8.6+
        (SemVer(8,4,0)...SemVer(8,4,99), SemVer(8,6,0), nil),
        // AGP 8.3 → Gradle 8.4+
        (SemVer(8,3,0)...SemVer(8,3,99), SemVer(8,4,0), nil),
        // AGP 8.2 → Gradle 8.2+
        (SemVer(8,2,0)...SemVer(8,2,99), SemVer(8,2,0), nil),
        // AGP 8.1 → Gradle 8.0+
        (SemVer(8,1,0)...SemVer(8,1,99), SemVer(8,0,0), nil),
        // AGP 8.0 → Gradle 8.0+
        (SemVer(8,0,0)...SemVer(8,0,99), SemVer(8,0,0), nil),
        // AGP 7.4 → Gradle 7.5+
        (SemVer(7,4,0)...SemVer(7,4,99), SemVer(7,5,0), nil),
        // AGP 7.3 → Gradle 7.4+
        (SemVer(7,3,0)...SemVer(7,3,99), SemVer(7,4,0), nil),
        // AGP 7.2 → Gradle 7.3.3+
        (SemVer(7,2,0)...SemVer(7,2,99), SemVer(7,3,3), nil),
        // AGP 7.1 → Gradle 7.2+
        (SemVer(7,1,0)...SemVer(7,1,99), SemVer(7,2,0), nil),
        // AGP 7.0 → Gradle 7.0+
        (SemVer(7,0,0)...SemVer(7,0,99), SemVer(7,0,0), nil),
    ]

    // MARK: - AGP → Minimum JDK Version Matrix

    private static let agpJdkMatrix: [(agpRange: ClosedRange<SemVer>, minJdk: Int)] = [
        (SemVer(8,4,0)...SemVer(8,99,99), 17),
        (SemVer(8,0,0)...SemVer(8,3,99), 17),
        (SemVer(7,0,0)...SemVer(7,4,99), 11),
    ]

    // MARK: - AGP → Minimum Kotlin Version

    private static let agpKotlinMatrix: [(agpRange: ClosedRange<SemVer>, minKotlin: SemVer)] = [
        (SemVer(8,8,0)...SemVer(8,8,99), SemVer(1,9,20)),
        (SemVer(8,7,0)...SemVer(8,7,99), SemVer(1,9,20)),
        (SemVer(8,6,0)...SemVer(8,6,99), SemVer(1,9,20)),
        (SemVer(8,5,0)...SemVer(8,5,99), SemVer(1,9,0)),
        (SemVer(8,4,0)...SemVer(8,4,99), SemVer(1,9,0)),
        (SemVer(8,3,0)...SemVer(8,3,99), SemVer(1,8,20)),
        (SemVer(8,2,0)...SemVer(8,2,99), SemVer(1,8,20)),
        (SemVer(8,1,0)...SemVer(8,1,99), SemVer(1,8,0)),
        (SemVer(8,0,0)...SemVer(8,0,99), SemVer(1,8,0)),
        (SemVer(7,4,0)...SemVer(7,4,99), SemVer(1,7,10)),
        (SemVer(7,3,0)...SemVer(7,3,99), SemVer(1,6,20)),
    ]

    // MARK: - Compile SDK → Target SDK Recommendations

    private static let sdkRecommendations: [(compileSdk: Int, recommendedTarget: Int, requiredMinForPlayStore: Int)] = [
        (35, 35, 34),  // Android 15
        (34, 34, 34),  // Android 14
        (33, 33, 33),  // Android 13
    ]

    // MARK: - Public API

    /// Run a full compatibility scan on a project
    static func scan(
        projectPath: String,
        environment: ProjectEnvironment,
        systemEnvironment: SystemEnvironment
    ) -> CompatibilityReport {
        var issues: [CompatibilityIssue] = []

        let agp = environment.agpVersion.flatMap { SemVer.parse($0) }
        let gradle = SemVer.parse(environment.gradleVersionDisplay)
        let kotlin = environment.kotlinVersion.flatMap { SemVer.parse($0) }
        let jdk = parseJdkMajor(systemEnvironment.javaHome)

        let gradleFilePath: String
        let appModule = environment.appModulePath ?? "app"
        if environment.buildGradleType == .kotlin {
            gradleFilePath = (projectPath as NSString).appendingPathComponent("\(appModule)/build.gradle.kts")
        } else {
            gradleFilePath = (projectPath as NSString).appendingPathComponent("\(appModule)/build.gradle")
        }

        let wrapperPath = (projectPath as NSString).appendingPathComponent("gradle/wrapper/gradle-wrapper.properties")

        // Read SDK versions from build.gradle
        let (compileSdk, minSdk, targetSdk) = extractSdkVersions(
            from: gradleFilePath,
            projectPath: projectPath,
            environment: environment
        )

        // 1. AGP ↔ Gradle compatibility
        if let agpVer = agp, let gradleVer = gradle {
            issues.append(contentsOf: checkAGPGradleCompat(
                agp: agpVer,
                gradle: gradleVer,
                agpRaw: environment.agpVersion ?? "",
                wrapperPath: wrapperPath
            ))
        }

        // 2. AGP ↔ JDK compatibility
        if let agpVer = agp, let jdkMajor = jdk {
            issues.append(contentsOf: checkAGPJdkCompat(
                agp: agpVer,
                jdkMajor: jdkMajor,
                agpRaw: environment.agpVersion ?? ""
            ))
        }

        // 3. AGP ↔ Kotlin compatibility
        if let agpVer = agp, let kotlinVer = kotlin {
            issues.append(contentsOf: checkAGPKotlinCompat(
                agp: agpVer,
                kotlin: kotlinVer,
                agpRaw: environment.agpVersion ?? "",
                kotlinRaw: environment.kotlinVersion ?? "",
                gradleFilePath: gradleFilePath
            ))
        }

        // 4. SDK version checks
        issues.append(contentsOf: checkSdkVersions(
            compileSdk: compileSdk,
            minSdk: minSdk,
            targetSdk: targetSdk,
            gradleFilePath: gradleFilePath
        ))

        // 5. Gradle wrapper validation
        issues.append(contentsOf: checkGradleWrapper(wrapperPath: wrapperPath))

        // 6. Namespace migration check (AGP 8+ requires namespace in build.gradle)
        if let agpVer = agp, agpVer >= SemVer(8, 0, 0) {
            issues.append(contentsOf: checkNamespaceMigration(
                gradleFilePath: gradleFilePath,
                projectPath: projectPath,
                appModule: appModule
            ))
        }

        return CompatibilityReport(
            issues: issues,
            scannedAt: Date(),
            agpVersion: environment.agpVersion,
            gradleVersion: environment.gradleVersionDisplay,
            kotlinVersion: environment.kotlinVersion,
            jdkVersion: jdk.map { "JDK \($0)" },
            compileSdk: compileSdk.map { "\($0)" },
            minSdk: minSdk.map { "\($0)" },
            targetSdk: targetSdk.map { "\($0)" }
        )
    }

    // MARK: - AGP ↔ Gradle Check

    private static func checkAGPGradleCompat(
        agp: SemVer, gradle: SemVer, agpRaw: String, wrapperPath: String
    ) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        for entry in agpGradleMatrix {
            if entry.agpRange.contains(agp) {
                if gradle < entry.minGradle {
                    let recommendedUrl = "https://services.gradle.org/distributions/gradle-\(entry.minGradle)-all.zip"
                    issues.append(CompatibilityIssue(
                        severity: .error,
                        title: "Gradle version too old for AGP \(agpRaw)",
                        detail: "AGP \(agpRaw) requires Gradle \(entry.minGradle)+, but project uses \(gradle). Build will fail.",
                        fix: CompatibilityIssue.FixAction(
                            label: "Update Gradle wrapper to \(entry.minGradle)",
                            filePath: wrapperPath,
                            oldValue: "\(gradle)",
                            newValue: "\(entry.minGradle)",
                            searchPattern: #"distributionUrl=.*gradle-[\d.]+-"#
                        )
                    ))
                }

                if let max = entry.maxGradle, gradle > max {
                    issues.append(CompatibilityIssue(
                        severity: .warning,
                        title: "Gradle version may be too new for AGP \(agpRaw)",
                        detail: "AGP \(agpRaw) is tested with Gradle up to \(max), but project uses \(gradle). Consider upgrading AGP.",
                        fix: nil
                    ))
                }
                break
            }
        }

        return issues
    }

    // MARK: - AGP ↔ JDK Check

    private static func checkAGPJdkCompat(
        agp: SemVer, jdkMajor: Int, agpRaw: String
    ) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        for entry in agpJdkMatrix {
            if entry.agpRange.contains(agp) {
                if jdkMajor < entry.minJdk {
                    issues.append(CompatibilityIssue(
                        severity: .error,
                        title: "JDK \(jdkMajor) too old for AGP \(agpRaw)",
                        detail: "AGP \(agpRaw) requires JDK \(entry.minJdk)+, but JAVA_HOME points to JDK \(jdkMajor). Set JAVA_HOME or use Android Studio's bundled JDK.",
                        fix: nil
                    ))
                }
                break
            }
        }

        return issues
    }

    // MARK: - AGP ↔ Kotlin Check

    private static func checkAGPKotlinCompat(
        agp: SemVer, kotlin: SemVer, agpRaw: String, kotlinRaw: String,
        gradleFilePath: String
    ) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        for entry in agpKotlinMatrix {
            if entry.agpRange.contains(agp) {
                if kotlin < entry.minKotlin {
                    issues.append(CompatibilityIssue(
                        severity: .error,
                        title: "Kotlin \(kotlinRaw) too old for AGP \(agpRaw)",
                        detail: "AGP \(agpRaw) requires Kotlin \(entry.minKotlin)+, but project uses \(kotlinRaw). Update the Kotlin plugin version.",
                        fix: CompatibilityIssue.FixAction(
                            label: "Upgrade Kotlin to \(entry.minKotlin)",
                            filePath: gradleFilePath,
                            oldValue: kotlinRaw,
                            newValue: "\(entry.minKotlin)",
                            searchPattern: #"kotlin.*version.*['\"]\K[\d.]+"#
                        )
                    ))
                }
                break
            }
        }

        return issues
    }

    // MARK: - SDK Version Checks

    private static func checkSdkVersions(
        compileSdk: Int?, minSdk: Int?, targetSdk: Int?,
        gradleFilePath: String
    ) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        if let compile = compileSdk, let target = targetSdk {
            if target > compile {
                issues.append(CompatibilityIssue(
                    severity: .error,
                    title: "targetSdk (\(target)) > compileSdk (\(compile))",
                    detail: "targetSdk cannot be greater than compileSdk. Set compileSdk to at least \(target).",
                    fix: CompatibilityIssue.FixAction(
                        label: "Set compileSdk to \(target)",
                        filePath: gradleFilePath,
                        oldValue: "\(compile)",
                        newValue: "\(target)",
                        searchPattern: #"compileSdk\s*[=:]\s*\d+"#
                    )
                ))
            }
        }

        if let min = minSdk, let target = targetSdk {
            if min > target {
                issues.append(CompatibilityIssue(
                    severity: .error,
                    title: "minSdk (\(min)) > targetSdk (\(target))",
                    detail: "minSdk cannot be greater than targetSdk. This is a configuration error.",
                    fix: nil
                ))
            }
        }

        // Play Store target SDK requirement (current: API 34 for new apps/updates)
        if let target = targetSdk, target < 34 {
            issues.append(CompatibilityIssue(
                severity: .warning,
                title: "targetSdk \(target) below Play Store requirement",
                detail: "Google Play requires targetSdk 34+ for new apps and updates. Current: \(target).",
                fix: CompatibilityIssue.FixAction(
                    label: "Update targetSdk to 34",
                    filePath: gradleFilePath,
                    oldValue: "\(target)",
                    newValue: "34",
                    searchPattern: #"targetSdk\s*[=:]\s*\d+"#
                )
            ))
        }

        // Very old minSdk warning
        if let min = minSdk, min < 21 {
            issues.append(CompatibilityIssue(
                severity: .info,
                title: "minSdk \(min) is very low",
                detail: "API 21 (Android 5.0) covers 99%+ of active devices. Raising minSdk can improve build times and reduce compatibility workarounds.",
                fix: nil
            ))
        }

        return issues
    }

    // MARK: - Gradle Wrapper Validation

    private static func checkGradleWrapper(wrapperPath: String) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        guard let content = try? String(contentsOfFile: wrapperPath, encoding: .utf8) else {
            issues.append(CompatibilityIssue(
                severity: .warning,
                title: "Gradle wrapper properties not found",
                detail: "Expected gradle-wrapper.properties at \(wrapperPath). Run 'gradle wrapper' to generate it.",
                fix: nil
            ))
            return issues
        }

        // Check if using -bin vs -all distribution
        if content.contains("-bin.zip") {
            issues.append(CompatibilityIssue(
                severity: .info,
                title: "Using Gradle -bin distribution",
                detail: "Switch to -all distribution for better IDE support and source availability. Change '-bin.zip' to '-all.zip' in gradle-wrapper.properties.",
                fix: CompatibilityIssue.FixAction(
                    label: "Switch to -all distribution",
                    filePath: wrapperPath,
                    oldValue: "-bin.zip",
                    newValue: "-all.zip",
                    searchPattern: #"-bin\.zip"#
                )
            ))
        }

        // Check for HTTP (not HTTPS)
        if content.contains("http://services.gradle.org") {
            issues.append(CompatibilityIssue(
                severity: .warning,
                title: "Gradle wrapper using HTTP instead of HTTPS",
                detail: "The distributionUrl uses HTTP, which is insecure. Switch to https://.",
                fix: CompatibilityIssue.FixAction(
                    label: "Switch to HTTPS",
                    filePath: wrapperPath,
                    oldValue: "http://",
                    newValue: "https://",
                    searchPattern: #"http://"#
                )
            ))
        }

        return issues
    }

    // MARK: - Namespace Migration (AGP 8+)

    private static func checkNamespaceMigration(
        gradleFilePath: String,
        projectPath: String,
        appModule: String
    ) -> [CompatibilityIssue] {
        var issues: [CompatibilityIssue] = []

        guard let gradleContent = try? String(contentsOfFile: gradleFilePath, encoding: .utf8) else {
            return issues
        }

        // Check if namespace is declared in build.gradle
        let hasNamespace = gradleContent.contains("namespace")

        // Check if AndroidManifest still has package attribute
        let manifestPath = (projectPath as NSString)
            .appendingPathComponent("\(appModule)/src/main/AndroidManifest.xml")
        let manifestContent = try? String(contentsOfFile: manifestPath, encoding: .utf8)
        let hasPackageInManifest = manifestContent?.contains("package=") ?? false

        if !hasNamespace && hasPackageInManifest {
            issues.append(CompatibilityIssue(
                severity: .warning,
                title: "Namespace not set in build.gradle",
                detail: "AGP 8+ requires 'namespace' in build.gradle instead of 'package' in AndroidManifest.xml. Run the AGP Upgrade Assistant in Android Studio.",
                fix: nil
            ))
        }

        return issues
    }

    // MARK: - Helpers

    /// Extract SDK versions from build.gradle or pubspec.yaml
    private static func extractSdkVersions(
        from gradleFilePath: String,
        projectPath: String,
        environment: ProjectEnvironment
    ) -> (compileSdk: Int?, minSdk: Int?, targetSdk: Int?) {
        // For Flutter projects, also check the android/app/build.gradle
        var filePath = gradleFilePath
        if environment.projectType == .flutter {
            let flutterGradle = (projectPath as NSString).appendingPathComponent("android/app/build.gradle")
            let flutterGradleKts = (projectPath as NSString).appendingPathComponent("android/app/build.gradle.kts")
            if FileManager.default.fileExists(atPath: flutterGradleKts) {
                filePath = flutterGradleKts
            } else if FileManager.default.fileExists(atPath: flutterGradle) {
                filePath = flutterGradle
            }
        }

        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return (nil, nil, nil)
        }

        let compileSdk = extractInt(from: content, pattern: #"compileSdk\s*[=:]\s*(\d+)"#)
            ?? extractInt(from: content, pattern: #"compileSdkVersion\s+(\d+)"#)
        let minSdk = extractInt(from: content, pattern: #"minSdk\s*[=:]\s*(\d+)"#)
            ?? extractInt(from: content, pattern: #"minSdkVersion\s+(\d+)"#)
        let targetSdk = extractInt(from: content, pattern: #"targetSdk\s*[=:]\s*(\d+)"#)
            ?? extractInt(from: content, pattern: #"targetSdkVersion\s+(\d+)"#)

        return (compileSdk, minSdk, targetSdk)
    }

    private static func extractInt(from content: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return Int(content[range])
    }

    /// Parse JDK major version from java_home path or java -version output
    private static func parseJdkMajor(_ javaHome: String?) -> Int? {
        guard let home = javaHome else { return nil }

        // Try to extract from path like ".../jdk-17.0.2.jdk/..."
        if let match = home.range(of: #"jdk-?(\d+)"#, options: .regularExpression) {
            let numStr = home[match].filter { $0.isNumber }
            return Int(numStr)
        }

        // Try running java -version
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["java", "-version"]
        proc.standardError = pipe // java -version writes to stderr
        proc.environment = ["JAVA_HOME": home]

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            // Parse "17.0.2" or "1.8.0_362"
            if let verMatch = output.range(of: #"\"(\d+)[\._]"#, options: .regularExpression) {
                let num = output[verMatch].filter { $0.isNumber || $0 == "." }
                let major = num.components(separatedBy: ".").first.flatMap { Int($0) }
                if let m = major, m == 1 {
                    // Old-style version: 1.8 = JDK 8
                    return num.components(separatedBy: ".").dropFirst().first.flatMap { Int($0) }
                }
                return major
            }
        } catch {}

        return nil
    }

    // MARK: - Auto-Fix

    /// Apply a fix action by modifying the target file
    static func applyFix(_ fix: CompatibilityIssue.FixAction) -> Bool {
        guard let content = try? String(contentsOfFile: fix.filePath, encoding: .utf8) else {
            return false
        }

        // For gradle-wrapper.properties URL update
        if fix.filePath.hasSuffix("gradle-wrapper.properties") && fix.searchPattern.contains("distributionUrl") {
            let updatedUrl = "https://services.gradle.org/distributions/gradle-\(fix.newValue)-all.zip"
            guard let regex = try? NSRegularExpression(pattern: #"distributionUrl=.*"#) else { return false }
            let range = NSRange(content.startIndex..., in: content)
            let newContent = regex.stringByReplacingMatches(
                in: content,
                range: range,
                withTemplate: "distributionUrl=https\\://services.gradle.org/distributions/gradle-\(fix.newValue)-all.zip"
            )
            return (try? newContent.write(toFile: fix.filePath, atomically: true, encoding: .utf8)) != nil
        }

        // Generic regex-based replacement
        guard let regex = try? NSRegularExpression(pattern: fix.searchPattern) else { return false }
        let range = NSRange(content.startIndex..., in: content)

        guard regex.firstMatch(in: content, range: range) != nil else { return false }

        let newContent = content.replacingOccurrences(of: fix.oldValue, with: fix.newValue)
        return (try? newContent.write(toFile: fix.filePath, atomically: true, encoding: .utf8)) != nil
    }
}

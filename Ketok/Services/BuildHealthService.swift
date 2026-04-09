import Foundation
import Combine

/// A single diagnostic check result
struct DiagnosticCheck: Identifiable {
    let id = UUID()
    let category: Category
    let severity: Severity
    let title: String
    let detail: String
    let autoFixable: Bool
    let fixAction: (() -> Bool)?  // Returns true if fix succeeded

    enum Category: String, CaseIterable {
        case gradle = "Gradle/AGP"
        case dependencies = "Dependencies"
        case codeGen = "Code Generation"
        case environment = "Environment"
        case signing = "Signing"
        case sdk = "SDK Versions"
        case flutter = "Flutter"
        case buildHealth = "Build Health"
    }

    enum Severity: Int, Comparable {
        case critical = 0   // Will definitely break
        case error = 1      // Very likely to break
        case warning = 2    // May cause issues
        case info = 3       // Suggestion

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var icon: String {
            switch self {
            case .critical: return "xmark.octagon.fill"
            case .error: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .critical: return "red"
            case .error: return "orange"
            case .warning: return "yellow"
            case .info: return "blue"
            }
        }
    }
}

/// Full diagnostic report from pre-build health check
struct DiagnosticReport {
    let checks: [DiagnosticCheck]
    let duration: TimeInterval
    let timestamp: Date

    var fixableCount: Int { checks.filter { $0.autoFixable }.count }
    var criticalCount: Int { checks.filter { $0.severity == .critical }.count }
    var errorCount: Int { checks.filter { $0.severity == .error }.count }
    var warningCount: Int { checks.filter { $0.severity == .warning }.count }
    var infoCount: Int { checks.filter { $0.severity == .info }.count }

    var canBuild: Bool { criticalCount == 0 && errorCount == 0 }

    var overallStatus: String {
        if checks.isEmpty { return "All clear" }
        if criticalCount > 0 { return "\(criticalCount) critical issue\(criticalCount == 1 ? "" : "s")" }
        if errorCount > 0 { return "\(errorCount) error\(errorCount == 1 ? "" : "s")" }
        if warningCount > 0 { return "\(warningCount) warning\(warningCount == 1 ? "" : "s")" }
        return "\(infoCount) suggestion\(infoCount == 1 ? "" : "s")"
    }

    /// Group checks by category for display
    var groupedByCategory: [(category: DiagnosticCheck.Category, checks: [DiagnosticCheck])] {
        var groups: [DiagnosticCheck.Category: [DiagnosticCheck]] = [:]
        for check in checks {
            groups[check.category, default: []].append(check)
        }
        return DiagnosticCheck.Category.allCases.compactMap { cat in
            guard let checks = groups[cat], !checks.isEmpty else { return nil }
            return (cat, checks.sorted { $0.severity < $1.severity })
        }
    }
}

/// Unified pre-build health check service.
/// Runs all diagnostic checks and provides a one-click "Fix All" capability.
class BuildHealthService: ObservableObject {
    @Published var isScanning = false
    @Published var lastReport: DiagnosticReport?
    @Published var fixAllInProgress = false

    // MARK: - Full Diagnostic Scan

    /// Run all diagnostic checks for a project
    func runDiagnostics(
        project: AndroidProject,
        environment: ProjectEnvironment,
        systemEnvironment: SystemEnvironment,
        buildStats: BuildStatsStore,
        logCallback: @escaping (String) -> Void
    ) -> DiagnosticReport {
        let startTime = Date()
        isScanning = true
        var checks: [DiagnosticCheck] = []

        logCallback("[Ketok] Running pre-build health check...\n")

        // 1. Gradle/AGP/Kotlin/JDK compatibility
        logCallback("[Ketok]   Checking Gradle compatibility matrix...\n")
        let compatReport = GradleCompatibilityService.scan(
            projectPath: project.path,
            environment: environment,
            systemEnvironment: systemEnvironment
        )
        for issue in compatReport.issues {
            checks.append(DiagnosticCheck(
                category: issue.severity == .error ? .gradle : .sdk,
                severity: mapSeverity(issue.severity),
                title: issue.title,
                detail: issue.detail,
                autoFixable: issue.fix != nil,
                fixAction: issue.fix.map { fix in
                    { GradleCompatibilityService.applyFix(fix) }
                }
            ))
        }

        // 2. Flutter-specific checks (if Flutter project)
        if environment.projectType == .flutter {
            logCallback("[Ketok]   Checking Flutter dependencies...\n")
            checks.append(contentsOf: runFlutterChecks(project: project, environment: environment))
        }

        // 3. Environment checks
        logCallback("[Ketok]   Checking build environment...\n")
        checks.append(contentsOf: runEnvironmentChecks(
            project: project,
            environment: environment,
            systemEnvironment: systemEnvironment
        ))

        // 4. Build health patterns (from history)
        logCallback("[Ketok]   Analyzing build history patterns...\n")
        let patterns = buildStats.detectFailurePatterns(forProject: project.id, lookbackDays: 14)
        for pattern in patterns where pattern.isRecurring {
            checks.append(DiagnosticCheck(
                category: .buildHealth,
                severity: .warning,
                title: "Recurring failure: \(pattern.category) (\(pattern.occurrences)x in 14 days)",
                detail: pattern.suggestion ?? "Review recent build logs for: \(pattern.sampleMessages.first ?? pattern.signature)",
                autoFixable: false,
                fixAction: nil
            ))
        }

        // 5. Build health score
        let healthScore = buildStats.buildHealthScore(forProject: project.id)
        if healthScore.score >= 0 && healthScore.score < 50 {
            checks.append(DiagnosticCheck(
                category: .buildHealth,
                severity: .warning,
                title: "Build health score: \(healthScore.score)/100 (\(healthScore.label))",
                detail: "Trend: \(healthScore.trend.rawValue). Focus on: \(healthScore.factors.min { $0.score < $1.score }?.name ?? "overall stability")",
                autoFixable: false,
                fixAction: nil
            ))
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let report = DiagnosticReport(checks: checks, duration: elapsed, timestamp: Date())

        logCallback("[Ketok] Health check complete: \(report.overallStatus) (\(String(format: "%.1fs", elapsed)))\n")
        if report.fixableCount > 0 {
            logCallback("[Ketok]   \(report.fixableCount) issue\(report.fixableCount == 1 ? "" : "s") can be auto-fixed\n")
        }

        DispatchQueue.main.async {
            self.lastReport = report
            self.isScanning = false
        }

        return report
    }

    // MARK: - Fix All

    /// Attempt to auto-fix all fixable issues
    func fixAll(logCallback: @escaping (String) -> Void) -> (fixed: Int, failed: Int) {
        guard let report = lastReport else { return (0, 0) }

        fixAllInProgress = true
        var fixed = 0
        var failed = 0

        let fixableChecks = report.checks.filter { $0.autoFixable && $0.fixAction != nil }
            .sorted { $0.severity < $1.severity }  // Fix most critical first

        logCallback("[Ketok] Attempting to fix \(fixableChecks.count) issue\(fixableChecks.count == 1 ? "" : "s")...\n")

        for check in fixableChecks {
            logCallback("[Ketok]   Fixing: \(check.title)...\n")
            if let action = check.fixAction, action() {
                logCallback("[Ketok]   ✅ Fixed\n")
                fixed += 1
            } else {
                logCallback("[Ketok]   ❌ Could not auto-fix\n")
                failed += 1
            }
        }

        logCallback("[Ketok] Fix all complete: \(fixed) fixed, \(failed) failed\n")

        DispatchQueue.main.async {
            self.fixAllInProgress = false
        }

        return (fixed, failed)
    }

    // MARK: - Flutter Checks

    private func runFlutterChecks(
        project: AndroidProject,
        environment: ProjectEnvironment
    ) -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []
        let projectPath = project.path

        // Check pubspec.lock freshness
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        let lockPath = (projectPath as NSString).appendingPathComponent("pubspec.lock")
        let fm = FileManager.default

        if fm.fileExists(atPath: pubspecPath) && !fm.fileExists(atPath: lockPath) {
            checks.append(DiagnosticCheck(
                category: .flutter,
                severity: .error,
                title: "pubspec.lock not found",
                detail: "Run 'flutter pub get' to generate the lock file before building.",
                autoFixable: true,
                fixAction: {
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    proc.arguments = ["flutter", "pub", "get"]
                    proc.currentDirectoryURL = URL(fileURLWithPath: projectPath)
                    try? proc.run()
                    proc.waitUntilExit()
                    return proc.terminationStatus == 0
                }
            ))
        } else if fm.fileExists(atPath: pubspecPath) && fm.fileExists(atPath: lockPath) {
            // Check if pubspec.yaml is newer than pubspec.lock
            let pubspecAttrs = try? fm.attributesOfItem(atPath: pubspecPath)
            let lockAttrs = try? fm.attributesOfItem(atPath: lockPath)
            if let pubDate = pubspecAttrs?[.modificationDate] as? Date,
               let lockDate = lockAttrs?[.modificationDate] as? Date,
               pubDate > lockDate {
                checks.append(DiagnosticCheck(
                    category: .flutter,
                    severity: .warning,
                    title: "pubspec.yaml modified after pubspec.lock",
                    detail: "Dependencies may be out of sync. Run 'flutter pub get' to update.",
                    autoFixable: true,
                    fixAction: {
                        let proc = Process()
                        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                        proc.arguments = ["flutter", "pub", "get"]
                        proc.currentDirectoryURL = URL(fileURLWithPath: projectPath)
                        try? proc.run()
                        proc.waitUntilExit()
                        return proc.terminationStatus == 0
                    }
                ))
            }
        }

        // Check for deprecated pubspec_overrides.yaml issues
        let overridesPath = (projectPath as NSString).appendingPathComponent("pubspec_overrides.yaml")
        if fm.fileExists(atPath: overridesPath) {
            checks.append(DiagnosticCheck(
                category: .flutter,
                severity: .info,
                title: "pubspec_overrides.yaml detected",
                detail: "Local package overrides are active. Make sure this file is in .gitignore to avoid committing local paths.",
                autoFixable: false,
                fixAction: nil
            ))
        }

        // Check for .env file presence if envied is used
        if let pubContent = try? String(contentsOfFile: pubspecPath, encoding: .utf8),
           pubContent.contains("envied") {
            let envPath = (projectPath as NSString).appendingPathComponent(".env")
            if !fm.fileExists(atPath: envPath) {
                checks.append(DiagnosticCheck(
                    category: .flutter,
                    severity: .error,
                    title: ".env file missing",
                    detail: "Project uses envied_generator but .env file is not present. Code generation will fail.",
                    autoFixable: false,
                    fixAction: nil
                ))
            }
        }

        return checks
    }

    // MARK: - Environment Checks

    private func runEnvironmentChecks(
        project: AndroidProject,
        environment: ProjectEnvironment,
        systemEnvironment: SystemEnvironment
    ) -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []

        // Check ANDROID_HOME
        if systemEnvironment.androidHome == nil {
            checks.append(DiagnosticCheck(
                category: .environment,
                severity: .error,
                title: "ANDROID_HOME not set",
                detail: "Android SDK location not configured. Set ANDROID_HOME environment variable or create local.properties with sdk.dir.",
                autoFixable: false,
                fixAction: nil
            ))
        }

        // Check JAVA_HOME
        if systemEnvironment.javaHome == nil {
            checks.append(DiagnosticCheck(
                category: .environment,
                severity: .warning,
                title: "JAVA_HOME not set",
                detail: "No JAVA_HOME configured. Gradle will use the system default Java, which may not be compatible.",
                autoFixable: false,
                fixAction: nil
            ))
        }

        // Check Flutter SDK for Flutter projects
        if environment.projectType == .flutter && systemEnvironment.flutterHome == nil {
            checks.append(DiagnosticCheck(
                category: .environment,
                severity: .error,
                title: "Flutter SDK not found",
                detail: "Flutter is not in PATH. Install Flutter SDK or add it to PATH.",
                autoFixable: false,
                fixAction: nil
            ))
        }

        // Check local.properties exists for native Android projects
        if environment.projectType == .native {
            let localProps = (project.path as NSString).appendingPathComponent("local.properties")
            if !FileManager.default.fileExists(atPath: localProps) {
                checks.append(DiagnosticCheck(
                    category: .environment,
                    severity: .warning,
                    title: "local.properties not found",
                    detail: "This file should contain sdk.dir pointing to your Android SDK. Open the project in Android Studio to auto-generate it.",
                    autoFixable: systemEnvironment.androidHome != nil,
                    fixAction: systemEnvironment.androidHome.map { home in
                        {
                            let content = "sdk.dir=\(home)\n"
                            let path = (project.path as NSString).appendingPathComponent("local.properties")
                            return (try? content.write(toFile: path, atomically: true, encoding: .utf8)) != nil
                        }
                    }
                ))
            }
        }

        // Check disk space (warn if < 2GB free)
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: project.path),
           let freeSpace = attrs[.systemFreeSize] as? Int64 {
            let freeGB = Double(freeSpace) / 1_073_741_824
            if freeGB < 2.0 {
                checks.append(DiagnosticCheck(
                    category: .environment,
                    severity: freeGB < 0.5 ? .critical : .warning,
                    title: "Low disk space: \(String(format: "%.1f", freeGB)) GB free",
                    detail: "Android builds require significant disk space for caches and intermediate files. Free up space to prevent build failures.",
                    autoFixable: false,
                    fixAction: nil
                ))
            }
        }

        return checks
    }

    // MARK: - Helpers

    private func mapSeverity(_ severity: CompatibilityIssue.Severity) -> DiagnosticCheck.Severity {
        switch severity {
        case .error: return .error
        case .warning: return .warning
        case .info: return .info
        }
    }
}

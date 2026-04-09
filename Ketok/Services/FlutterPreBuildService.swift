import Foundation

/// Detects and runs required pre-build steps for Flutter projects.
///
/// Automatically detects:
/// - `build_runner` code generation (freezed, json_serializable, auto_route, injectable, etc.)
/// - Missing or stale generated files (.g.dart, .freezed.dart, .gr.dart, .config.dart)
/// - `flutter_gen` asset generation
/// - `envied` environment generation
///
/// Runs the appropriate generators before the main build to prevent failures.
struct FlutterPreBuildService {

    // MARK: - Detection Models

    /// A semver version parsed from pubspec constraints
    struct SemVer: CustomStringConvertible {
        let major: Int
        let minor: Int
        let patch: Int

        var description: String { "\(major).\(minor).\(patch)" }

        init?(_ string: String) {
            // Strip leading caret, tilde, or comparison operators
            let cleaned = string.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "^", with: "")
                .replacingOccurrences(of: "~", with: "")
                .replacingOccurrences(of: ">=", with: "")
                .replacingOccurrences(of: "<=", with: "")
                .replacingOccurrences(of: ">", with: "")
                .replacingOccurrences(of: "<", with: "")
                .trimmingCharacters(in: .whitespaces)

            let parts = cleaned.split(separator: ".").compactMap { Int($0) }
            guard parts.count >= 3 else { return nil }
            self.major = parts[0]
            self.minor = parts[1]
            self.patch = parts[2]
        }

        /// Whether the resolved version has drifted significantly from the constraint
        /// (minor version jump >= threshold, indicating potential breaking changes)
        func hasSignificantDrift(from constraint: SemVer, minorThreshold: Int = 3) -> Bool {
            guard major == constraint.major else { return true }
            return (minor - constraint.minor) >= minorThreshold
        }
    }

    /// Version mismatch between pubspec.yaml constraint and pubspec.lock resolved version
    struct VersionMismatch: CustomStringConvertible {
        let package: String
        let constraint: String       // e.g. "^5.4.0"
        let resolved: String         // e.g. "5.10.0"
        let severity: Severity

        enum Severity: String {
            case warning = "⚠️"      // Minor drift, might cause issues
            case critical = "🚨"     // Major drift, likely cause of build failures
        }

        var description: String {
            "\(severity.rawValue) \(package): declared \(constraint) → resolved \(resolved)"
        }
    }

    /// Missing environment variable required by envied
    struct MissingEnvVar {
        let varName: String       // e.g. "GOOGLE_CLIENT_ID"
        let sourceFile: String    // e.g. "lib/core/env/app_env.dart"
        let hasDefault: Bool      // true if @EnviedField has a defaultValue
    }

    /// What the project needs before building
    struct PreBuildRequirements {
        var needsBuildRunner: Bool = false
        var needsFlutterGen: Bool = false
        var needsL10n: Bool = false          // flutter gen-l10n (ARB-based localization)
        var hasMissingGenerated: Bool = false
        var hasStaleGenerated: Bool = false
        var generators: [String] = []        // e.g. ["freezed", "json_serializable", "auto_route"]
        var missingFiles: [String] = []      // Files that reference .g.dart but generated file is missing
        var staleFiles: [String] = []        // Generated files older than source
        var versionMismatches: [VersionMismatch] = []  // Packages with version drift
        var missingEnvVars: [MissingEnvVar] = []       // Missing .env variables for envied
        var enviedVersionIncompatible: Bool = false    // envied_generator too old for current analyzer
        var enviedResolvedVersion: String?             // Resolved envied_generator version
        var analyzerResolvedVersion: String?           // Resolved analyzer version

        var needsCodeGeneration: Bool {
            needsBuildRunner && (hasMissingGenerated || hasStaleGenerated)
        }

        var hasVersionIssues: Bool {
            !versionMismatches.isEmpty
        }

        var hasCriticalVersionIssues: Bool {
            versionMismatches.contains { $0.severity == .critical }
        }

        var hasEnvIssues: Bool {
            missingEnvVars.contains { !$0.hasDefault }
        }

        var summary: String {
            var parts: [String] = []
            if needsBuildRunner {
                parts.append("build_runner (\(generators.joined(separator: ", ")))")
            }
            if needsFlutterGen {
                parts.append("flutter_gen")
            }
            if needsL10n {
                parts.append("gen-l10n")
            }
            if hasMissingGenerated {
                parts.append("\(missingFiles.count) missing generated file(s)")
            }
            if hasStaleGenerated {
                parts.append("\(staleFiles.count) stale generated file(s)")
            }
            if hasVersionIssues {
                let criticalCount = versionMismatches.filter { $0.severity == .critical }.count
                let warningCount = versionMismatches.filter { $0.severity == .warning }.count
                if criticalCount > 0 {
                    parts.append("\(criticalCount) version drift(s) detected")
                }
                if warningCount > 0 {
                    parts.append("\(warningCount) version warning(s)")
                }
            }
            if hasEnvIssues {
                let requiredCount = missingEnvVars.filter { !$0.hasDefault }.count
                parts.append("\(requiredCount) missing .env variable(s)")
            }
            if enviedVersionIncompatible {
                parts.append("envied upgrade needed")
            }
            return parts.isEmpty ? "No pre-build steps needed" : parts.joined(separator: " · ")
        }
    }

    // MARK: - Detection

    /// Analyze a Flutter project to determine what pre-build steps are needed
    static func detectRequirements(projectPath: String) -> PreBuildRequirements {
        var req = PreBuildRequirements()

        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard let pubspecContent = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else {
            return req
        }

        // Detect build_runner and generators from dev_dependencies
        let devDepsSection = extractDevDependencies(from: pubspecContent)

        let generatorPackages: [(package: String, label: String)] = [
            ("build_runner", "build_runner"),
            ("freezed", "freezed"),
            ("json_serializable", "json_serializable"),
            ("auto_route_generator", "auto_route"),
            ("injectable_generator", "injectable"),
            ("hive_ce_generator", "hive_ce"),
            ("hive_generator", "hive"),
            ("retrofit_generator", "retrofit"),
            ("chopper_generator", "chopper"),
            ("floor_generator", "floor"),
            ("drift_dev", "drift"),
            ("riverpod_generator", "riverpod"),
            ("envied_generator", "envied"),
            ("flutter_gen_runner", "flutter_gen"),
            ("mockito", "mockito"),
            ("go_router_builder", "go_router"),
        ]

        for gen in generatorPackages {
            if devDepsSection.contains(gen.package) {
                if gen.package == "build_runner" {
                    req.needsBuildRunner = true
                } else if gen.package == "flutter_gen_runner" {
                    req.needsFlutterGen = true
                    req.generators.append(gen.label)
                } else {
                    req.generators.append(gen.label)
                }
            }
        }

        // If build_runner is present, check for missing/stale generated files
        if req.needsBuildRunner {
            let (missing, stale) = checkGeneratedFiles(projectPath: projectPath)
            req.missingFiles = missing
            req.staleFiles = stale
            req.hasMissingGenerated = !missing.isEmpty
            req.hasStaleGenerated = !stale.isEmpty
        }

        // Detect localization (l10n) — check for l10n.yaml config or .arb files
        let l10nConfigPath = (projectPath as NSString).appendingPathComponent("l10n.yaml")
        let defaultArbDir = (projectPath as NSString).appendingPathComponent("lib/l10n")
        let fm = FileManager.default
        if fm.fileExists(atPath: l10nConfigPath) {
            req.needsL10n = true
        } else if fm.fileExists(atPath: defaultArbDir),
                  let contents = try? fm.contentsOfDirectory(atPath: defaultArbDir),
                  contents.contains(where: { $0.hasSuffix(".arb") }) {
            req.needsL10n = true
        } else {
            // Also check pubspec.yaml for generate: true (Flutter's built-in l10n trigger)
            if pubspecContent.contains("generate: true") || pubspecContent.contains("flutter_localizations") {
                // Check if any .arb files exist anywhere in lib/
                let libPath = (projectPath as NSString).appendingPathComponent("lib")
                if let enumerator = fm.enumerator(atPath: libPath) {
                    while let file = enumerator.nextObject() as? String {
                        if file.hasSuffix(".arb") {
                            req.needsL10n = true
                            break
                        }
                    }
                }
            }
        }

        // Check for version mismatches between pubspec.yaml and pubspec.lock
        let lockPath = (projectPath as NSString).appendingPathComponent("pubspec.lock")
        if let lockContent = try? String(contentsOfFile: lockPath, encoding: .utf8) {
            req.versionMismatches = detectVersionMismatches(
                pubspecContent: pubspecContent,
                lockContent: lockContent
            )
        }

        // Check for missing .env variables if envied is used
        if req.generators.contains("envied") {
            req.missingEnvVars = detectMissingEnvVars(projectPath: projectPath)

            // Check envied_generator version compatibility with analyzer
            if let lockContent = try? String(contentsOfFile: lockPath, encoding: .utf8) {
                let resolved = extractResolvedVersions(from: lockContent)
                req.enviedResolvedVersion = resolved["envied_generator"]
                req.analyzerResolvedVersion = resolved["analyzer"]

                if let enviedVer = SemVer(resolved["envied_generator"] ?? ""),
                   let analyzerVer = SemVer(resolved["analyzer"] ?? "") {
                    // envied_generator < 1.2.1 is incompatible with analyzer >= 7.0
                    // Version 1.2.1 was the first to support analyzer >=7.4.0
                    // Version 1.3.0 broadened build/source_gen constraints
                    // Version 1.3.2 added analyzer 9.0 support
                    // Version 1.3.3 added analyzer 10.0 support
                    let needsUpgrade: Bool
                    if analyzerVer.major >= 10 {
                        needsUpgrade = enviedVer.major < 1 || (enviedVer.major == 1 && enviedVer.minor < 3) || (enviedVer.major == 1 && enviedVer.minor == 3 && enviedVer.patch < 3)
                    } else if analyzerVer.major >= 9 {
                        needsUpgrade = enviedVer.major < 1 || (enviedVer.major == 1 && enviedVer.minor < 3) || (enviedVer.major == 1 && enviedVer.minor == 3 && enviedVer.patch < 2)
                    } else if analyzerVer.major >= 7 {
                        needsUpgrade = enviedVer.major < 1 || (enviedVer.major == 1 && enviedVer.minor < 2) || (enviedVer.major == 1 && enviedVer.minor == 2 && enviedVer.patch < 1)
                    } else {
                        needsUpgrade = false
                    }
                    req.enviedVersionIncompatible = needsUpgrade
                }
            }
        }

        return req
    }

    // MARK: - Version Mismatch Detection

    /// Packages safe to auto-pin — these are standalone code generators that don't
    /// have tight cross-dependencies with other packages in the project.
    /// Only these will be auto-fixed; others get a warning only.
    private static let safeToAutoPin: Set<String> = [
        "flutter_gen_runner", "flutter_gen", "build_runner",
    ]

    /// Packages that commonly cause code generation issues when drifted,
    /// but have cross-dependencies (e.g., json_serializable ↔ json_annotation)
    /// so they should only warn, never auto-pin.
    private static let warnOnlyPackages: Set<String> = [
        "freezed", "json_serializable", "auto_route_generator",
        "injectable_generator", "hive_ce_generator", "hive_generator",
        "drift_dev", "envied_generator",
    ]

    /// Detect version mismatches between pubspec.yaml constraints and pubspec.lock resolved versions
    static func detectVersionMismatches(pubspecContent: String, lockContent: String) -> [VersionMismatch] {
        var mismatches: [VersionMismatch] = []

        // Parse declared constraints from pubspec.yaml (both dependencies and dev_dependencies)
        let constraints = extractVersionConstraints(from: pubspecContent)

        // Parse resolved versions from pubspec.lock
        let resolvedVersions = extractResolvedVersions(from: lockContent)

        for (package, constraint) in constraints {
            guard let resolved = resolvedVersions[package] else { continue }

            // Only check caret (^) constraints — these allow minor/patch drift
            guard constraint.hasPrefix("^") else { continue }

            guard let constraintVer = SemVer(constraint),
                  let resolvedVer = SemVer(resolved) else { continue }

            // Skip if versions are the same
            guard constraintVer.description != resolvedVer.description else { continue }

            let isSafeToPin = safeToAutoPin.contains(package)
            let isKnownGenerator = warnOnlyPackages.contains(package)

            // Safe-to-pin packages: flag as critical (auto-fixable) with lower threshold
            // Known generators: flag as warning with moderate threshold
            // Everything else: flag as warning only with high threshold
            let threshold: Int
            let severity: VersionMismatch.Severity

            if isSafeToPin {
                threshold = 2
                severity = .critical  // Will be auto-fixed
            } else if isKnownGenerator {
                threshold = 3
                severity = .warning   // Warn only — has cross-dependencies
            } else {
                threshold = 5
                severity = .warning   // Warn only — general package
            }

            if resolvedVer.hasSignificantDrift(from: constraintVer, minorThreshold: threshold) {
                mismatches.append(VersionMismatch(
                    package: package,
                    constraint: constraint,
                    resolved: resolved,
                    severity: severity
                ))
            }
        }

        return mismatches
    }

    /// Extract package version constraints from pubspec.yaml (dependencies + dev_dependencies)
    private static func extractVersionConstraints(from content: String) -> [String: String] {
        var constraints: [String: String] = [:]
        let lines = content.components(separatedBy: "\n")
        var inDepsSection = false

        // Pattern: "  package_name: ^1.2.3" or "  package_name: '>=1.2.3 <2.0.0'"
        let versionPattern = try? NSRegularExpression(
            pattern: #"^\s{2,}(\w[\w_-]*):\s*['\"]?(\^[\d.]+|~[\d.]+|[\d.]+)['\"]?\s*$"#
        )

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Track when we enter/exit dependency sections
            if trimmed == "dependencies:" || trimmed == "dev_dependencies:" {
                inDepsSection = true
                continue
            }
            // Exit at next top-level key
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#") && trimmed.hasSuffix(":") {
                inDepsSection = false
                continue
            }

            guard inDepsSection else { continue }

            let range = NSRange(line.startIndex..., in: line)
            if let match = versionPattern?.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line),
               let versionRange = Range(match.range(at: 2), in: line) {
                let name = String(line[nameRange])
                let version = String(line[versionRange])
                constraints[name] = version
            }
        }

        return constraints
    }

    /// Extract resolved package versions from pubspec.lock
    private static func extractResolvedVersions(from lockContent: String) -> [String: String] {
        var versions: [String: String] = [:]
        let lines = lockContent.components(separatedBy: "\n")

        var currentPackage: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Package names are at 2-space indent followed by ":"
            if line.hasPrefix("  ") && !line.hasPrefix("    ") && trimmed.hasSuffix(":") && !trimmed.hasPrefix("#") {
                currentPackage = String(trimmed.dropLast()) // remove trailing ":"
            }

            // Version lines are at 4-space indent: '    version: "1.2.3"'
            if let pkg = currentPackage, trimmed.hasPrefix("version:") {
                let versionStr = trimmed
                    .replacingOccurrences(of: "version:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "\"", with: "")
                    .replacingOccurrences(of: "'", with: "")
                versions[pkg] = versionStr
                currentPackage = nil
            }
        }

        return versions
    }

    // MARK: - Environment Variable Validation

    /// Detect missing .env variables required by envied annotations.
    /// Scans Dart files for @Envied/@EnviedField annotations, extracts required
    /// variable names, and compares against what's defined in the .env file.
    static func detectMissingEnvVars(projectPath: String) -> [MissingEnvVar] {
        var missing: [MissingEnvVar] = []

        // Find the .env file path — check @Envied(path:) annotations or default to '.env'
        let envFilePaths = findEnviedSourceFiles(projectPath: projectPath)

        for enviedFile in envFilePaths {
            let filePath = (projectPath as NSString).appendingPathComponent(enviedFile.dartFile)
            guard let dartContent = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            // Determine the .env file path from @Envied annotation
            let envPath: String
            if let annotatedPath = enviedFile.envPath {
                envPath = (projectPath as NSString).appendingPathComponent(annotatedPath)
            } else {
                envPath = (projectPath as NSString).appendingPathComponent(".env")
            }

            // Parse existing env vars from the .env file
            let existingVars = parseEnvFile(at: envPath)

            // Extract required variable names from @EnviedField annotations
            let requiredVars = extractEnviedFields(from: dartContent)

            for field in requiredVars {
                if !existingVars.contains(field.varName) && !field.hasDefault {
                    missing.append(MissingEnvVar(
                        varName: field.varName,
                        sourceFile: enviedFile.dartFile,
                        hasDefault: false
                    ))
                } else if !existingVars.contains(field.varName) && field.hasDefault {
                    missing.append(MissingEnvVar(
                        varName: field.varName,
                        sourceFile: enviedFile.dartFile,
                        hasDefault: true
                    ))
                }
            }
        }

        return missing
    }

    /// A Dart file that uses @Envied, with its .env path
    private struct EnviedSourceFile {
        let dartFile: String   // Relative path, e.g. "lib/core/env/app_env.dart"
        let envPath: String?   // Path from @Envied(path:), e.g. ".env"
    }

    /// An @EnviedField variable definition
    private struct EnviedFieldDef {
        let varName: String    // The env var name (from varName:)
        let hasDefault: Bool   // Whether defaultValue is set
    }

    /// Find all Dart files that use @Envied annotation
    private static func findEnviedSourceFiles(projectPath: String) -> [EnviedSourceFile] {
        var results: [EnviedSourceFile] = []
        let libPath = (projectPath as NSString).appendingPathComponent("lib")
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: libPath),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return results
        }

        let enviedPattern = try? NSRegularExpression(pattern: #"@Envied\((.*?)\)"#, options: .dotMatchesLineSeparators)
        let pathPattern = try? NSRegularExpression(pattern: #"path:\s*['\"]([^'\"]+)['\"]"#)

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "dart",
                  !fileURL.lastPathComponent.contains(".g.dart"),
                  !fileURL.lastPathComponent.contains(".freezed.dart") else { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            let fullRange = NSRange(content.startIndex..., in: content)
            guard let enviedMatch = enviedPattern?.firstMatch(in: content, range: fullRange) else { continue }

            // Extract the path from @Envied(path: '.env')
            var envPath: String? = nil
            if let argsRange = Range(enviedMatch.range(at: 1), in: content) {
                let args = String(content[argsRange])
                let argsNSRange = NSRange(args.startIndex..., in: args)
                if let pathMatch = pathPattern?.firstMatch(in: args, range: argsNSRange),
                   let pathRange = Range(pathMatch.range(at: 1), in: args) {
                    envPath = String(args[pathRange])
                }
            }

            let relativePath = fileURL.path.replacingOccurrences(of: projectPath + "/", with: "")
            results.append(EnviedSourceFile(dartFile: relativePath, envPath: envPath))
        }

        return results
    }

    /// Extract @EnviedField variable names and whether they have defaults
    private static func extractEnviedFields(from dartContent: String) -> [EnviedFieldDef] {
        var fields: [EnviedFieldDef] = []

        // Match @EnviedField(varName: 'FOO') or @EnviedField(varName: 'FOO', defaultValue: '')
        let fieldPattern = try? NSRegularExpression(
            pattern: #"@EnviedField\(([^)]+)\)"#,
            options: .dotMatchesLineSeparators
        )
        let varNamePattern = try? NSRegularExpression(pattern: #"varName:\s*['\"]([^'\"]+)['\"]"#)
        let defaultPattern = try? NSRegularExpression(pattern: #"defaultValue:"#)

        let fullRange = NSRange(dartContent.startIndex..., in: dartContent)
        guard let matches = fieldPattern?.matches(in: dartContent, range: fullRange) else { return fields }

        for match in matches {
            guard let argsRange = Range(match.range(at: 1), in: dartContent) else { continue }
            let args = String(dartContent[argsRange])
            let argsNSRange = NSRange(args.startIndex..., in: args)

            // Extract varName
            guard let varNameMatch = varNamePattern?.firstMatch(in: args, range: argsNSRange),
                  let nameRange = Range(varNameMatch.range(at: 1), in: args) else { continue }

            let varName = String(args[nameRange])
            let hasDefault = defaultPattern?.firstMatch(in: args, range: argsNSRange) != nil

            fields.append(EnviedFieldDef(varName: varName, hasDefault: hasDefault))
        }

        return fields
    }

    /// Parse a .env file and return the set of defined variable names
    private static func parseEnvFile(at path: String) -> Set<String> {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }

        var vars = Set<String>()
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments and empty lines
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            // Extract variable name (everything before first '=')
            if let eqIndex = trimmed.firstIndex(of: "=") {
                let name = String(trimmed[trimmed.startIndex..<eqIndex]).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    vars.insert(name)
                }
            }
        }

        return vars
    }

    /// Extract the dev_dependencies section from pubspec.yaml
    private static func extractDevDependencies(from content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        var inDevDeps = false
        var result: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("dev_dependencies:") {
                inDevDeps = true
                continue
            }

            if inDevDeps {
                // Stop at next top-level key (no indentation)
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    break
                }
                result.append(trimmed)
            }
        }

        return result.joined(separator: "\n")
    }

    /// Check for missing or stale generated files
    private static func checkGeneratedFiles(projectPath: String) -> (missing: [String], stale: [String]) {
        var missing: [String] = []
        var stale: [String] = []

        let libPath = (projectPath as NSString).appendingPathComponent("lib")
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: libPath),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return (missing, stale)
        }

        // Patterns: part 'file.g.dart'; part 'file.freezed.dart'; etc.
        let partPattern = try? NSRegularExpression(pattern: #"part\s+'([^']+\.(g|freezed|gr|config)\.dart)'"#)

        var checkedCount = 0
        let maxChecks = 200  // Limit to avoid very slow scans

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "dart",
                  !fileURL.lastPathComponent.contains(".g.dart"),
                  !fileURL.lastPathComponent.contains(".freezed.dart"),
                  !fileURL.lastPathComponent.contains(".gr.dart"),
                  !fileURL.lastPathComponent.contains(".config.dart"),
                  checkedCount < maxChecks else { continue }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            checkedCount += 1

            let range = NSRange(content.startIndex..., in: content)
            guard let matches = partPattern?.matches(in: content, range: range), !matches.isEmpty else { continue }

            let sourceDir = fileURL.deletingLastPathComponent().path

            for match in matches {
                guard let partRange = Range(match.range(at: 1), in: content) else { continue }
                let partFile = String(content[partRange])
                let generatedPath = (sourceDir as NSString).appendingPathComponent(partFile)

                if !fm.fileExists(atPath: generatedPath) {
                    // Generated file doesn't exist
                    let relativePath = generatedPath.replacingOccurrences(of: projectPath + "/", with: "")
                    missing.append(relativePath)
                } else {
                    // Check if generated file is older than source
                    if let sourceDate = modificationDate(for: fileURL.path),
                       let genDate = modificationDate(for: generatedPath),
                       sourceDate > genDate {
                        let relativePath = generatedPath.replacingOccurrences(of: projectPath + "/", with: "")
                        stale.append(relativePath)
                    }
                }
            }
        }

        return (missing, stale)
    }

    private static func modificationDate(for path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    // MARK: - Execution

    // MARK: - Version Auto-Fix

    /// Pin a package in pubspec.yaml to an exact version by replacing the
    /// current constraint (e.g. "^5.4.0") with a specific version (e.g. "5.10.0").
    /// This locks the package to a known-working version to prevent future drift.
    static func pinVersionInPubspec(projectPath: String, package: String, toVersion: String) -> Bool {
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard var content = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else {
            return false
        }

        // Replace any version constraint for this package with the exact target version
        // Matches: "  package_name: ^1.2.3" or "  package_name: ~1.2.3" or "  package_name: 1.2.3"
        let escapedPkg = NSRegularExpression.escapedPattern(for: package)
        let pattern = "(\(escapedPkg):\\s*)['\"]?[\\^~]?[\\d][\\d.]*['\"]?"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\(toVersion)")
        }

        do {
            try content.write(toFile: pubspecPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Run all required pre-build steps and return the combined output
    static func runPreBuildSteps(
        projectPath: String,
        requirements: PreBuildRequirements,
        environment: [String: String],
        logCallback: @escaping (String) -> Void
    ) -> Bool {
        var success = true

        // Step 0: Check and report version mismatches
        if requirements.hasVersionIssues {
            logCallback("[Ketok] 📦 Dependency version check:\n")

            for mismatch in requirements.versionMismatches {
                logCallback("[Ketok] \(mismatch)\n")
            }

            // Auto-fix critical mismatches by pinning versions
            // Only pins packages in safeToAutoPin (standalone generators without cross-deps)
            if requirements.hasCriticalVersionIssues {
                logCallback("[Ketok] 🔧 Auto-fixing version drift for standalone packages...\n")

                // Backup pubspec.yaml before making changes
                let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
                let pubspecBackup = try? String(contentsOfFile: pubspecPath, encoding: .utf8)
                var pinnedPackages: [(name: String, from: String, to: String)] = []

                for mismatch in requirements.versionMismatches where mismatch.severity == .critical {
                    // Pin to the currently resolved version (from pubspec.lock), NOT the old
                    // constraint base. The resolved version is already proven compatible with
                    // the rest of the dependency graph. Pinning it prevents future drift.
                    let targetVersion = mismatch.resolved

                    if pinVersionInPubspec(projectPath: projectPath, package: mismatch.package, toVersion: targetVersion) {
                        logCallback("[Ketok] ✅ Pinned \(mismatch.package) to \(targetVersion) (was \(mismatch.constraint) with drift)\n")
                        pinnedPackages.append((mismatch.package, mismatch.constraint, targetVersion))
                    } else {
                        logCallback("[Ketok] ❌ Could not pin \(mismatch.package) — check pubspec.yaml manually\n")
                    }
                }

                // Re-run pub get after pinning. We do NOT delete pubspec.lock because:
                // 1. We're pinning to the already-resolved version, so the lock is still valid
                // 2. Deleting the lock would let ALL other packages re-resolve to latest,
                //    potentially introducing breaking changes (e.g., super_tooltip API changes)
                if !pinnedPackages.isEmpty {
                    logCallback("[Ketok] 🔄 Re-resolving dependencies after version pin...\n")
                    let pubGetOutput = runCommand(
                        "flutter pub get",
                        projectPath: projectPath,
                        environment: environment
                    )

                    let hasError = pubGetOutput.contains("version solving failed")
                        || pubGetOutput.contains("Could not")
                        || pubGetOutput.lowercased().contains("forbidden")

                    if hasError {
                        logCallback("[Ketok] ⚠️ Dependency conflict after pinning — rolling back...\n")

                        // Restore original pubspec.yaml
                        if let backup = pubspecBackup {
                            try? backup.write(toFile: pubspecPath, atomically: true, encoding: .utf8)
                            logCallback("[Ketok] 🔄 Restored original pubspec.yaml\n")
                        }

                        // Re-resolve with original pubspec
                        let restoreOutput = runCommand(
                            "flutter pub get",
                            projectPath: projectPath,
                            environment: environment
                        )
                        if restoreOutput.lowercased().contains("error") {
                            logCallback("[Ketok] ❌ Could not restore dependencies — check pubspec.yaml manually\n")
                        } else {
                            logCallback("[Ketok] ✅ Restored original dependencies. Build will proceed with current versions.\n")
                        }

                        logCallback("[Ketok] 💡 Tip: manually update these packages with compatible versions to fix the drift.\n")
                    } else {
                        logCallback("[Ketok] ✅ Dependencies re-resolved with pinned versions.\n")
                    }
                }
            }

            // Log warnings for non-auto-fixable packages
            let warnings = requirements.versionMismatches.filter { $0.severity == .warning }
            if !warnings.isEmpty {
                logCallback("[Ketok] 💡 These packages have version drift but may have cross-dependencies — review manually:\n")
                for w in warnings {
                    logCallback("[Ketok]    \(w.package): \(w.constraint) → \(w.resolved)\n")
                }
            }

            logCallback("\n")
        }

        // Step 0.5: Check for missing .env variables (envied)
        if !requirements.missingEnvVars.isEmpty {
            let requiredMissing = requirements.missingEnvVars.filter { !$0.hasDefault }
            let optionalMissing = requirements.missingEnvVars.filter { $0.hasDefault }

            if !requiredMissing.isEmpty {
                logCallback("[Ketok] 🚨 Missing required .env variables (envied will fail without these):\n")
                for v in requiredMissing {
                    logCallback("[Ketok]    ❌ \(v.varName)  ← required by \(v.sourceFile)\n")
                }
                logCallback("[Ketok] 💡 Add these variables to your .env file before building.\n")
                logCallback("[Ketok]    envied_generator cannot generate code without all required variables.\n")
                logCallback("[Ketok]    Generated file (e.g. app_env.g.dart) will be empty/missing.\n\n")
            }

            if !optionalMissing.isEmpty {
                logCallback("[Ketok] ⚠️ Missing optional .env variables (have defaults, build will continue):\n")
                for v in optionalMissing {
                    logCallback("[Ketok]    ⚠️ \(v.varName)  ← optional in \(v.sourceFile)\n")
                }
                logCallback("\n")
            }
        }

        // Step 1: build_runner code generation
        if requirements.needsCodeGeneration {
            logCallback("[Ketok] Running code generation (build_runner)...\n")
            logCallback("[Ketok] Detected generators: \(requirements.generators.joined(separator: ", "))\n")

            if requirements.hasMissingGenerated {
                logCallback("[Ketok] Missing generated files: \(requirements.missingFiles.count)\n")
            }
            if requirements.hasStaleGenerated {
                logCallback("[Ketok] Stale generated files: \(requirements.staleFiles.count)\n")
            }

            // If files are missing, clean build cache first to force full regeneration.
            // build_runner may skip generation if it thinks nothing changed (stale cache).
            if requirements.hasMissingGenerated {
                logCallback("[Ketok] Cleaning build cache to force full regeneration...\n")
                let _ = runCommand(
                    "dart run build_runner clean",
                    projectPath: projectPath,
                    environment: environment
                )
            }

            var buildRunnerOutput = runCommand(
                "dart run build_runner build --delete-conflicting-outputs",
                projectPath: projectPath,
                environment: environment
            )

            // Check if the build script itself failed to compile (e.g., mockito analyzer incompatibility)
            // When this happens, NO generators run at all — the entire build_runner is dead.
            let brokenBuilders = detectBrokenBuildScriptPackages(from: buildRunnerOutput)
            if !brokenBuilders.isEmpty {
                logCallback("[Ketok] 🔍 Build script compilation failed due to incompatible builders:\n")
                for pkg in brokenBuilders {
                    logCallback("[Ketok]    ❌ \(pkg.name) \(pkg.currentVersion) — needs upgrade to \(pkg.availableVersion ?? "latest")\n")
                }

                // Fix by upgrading broken builders via dependency_overrides
                let fixed = fixBrokenBuilders(
                    brokenBuilders,
                    projectPath: projectPath,
                    environment: environment,
                    logCallback: logCallback
                )

                if fixed {
                    // Retry build_runner after fixing broken builders
                    logCallback("[Ketok] 🔄 Retrying code generation after fixing broken builders...\n")
                    let _ = runCommand(
                        "dart run build_runner clean",
                        projectPath: projectPath,
                        environment: environment
                    )
                    buildRunnerOutput = runCommand(
                        "dart run build_runner build --delete-conflicting-outputs",
                        projectPath: projectPath,
                        environment: environment
                    )
                }
            }

            if buildRunnerOutput.contains("Succeeded") || buildRunnerOutput.contains("with 0 outputs") || !buildRunnerOutput.contains("SEVERE") {
                logCallback("[Ketok] Code generation complete.\n")
            } else if buildRunnerOutput.contains("SEVERE") || buildRunnerOutput.contains("Error") || buildRunnerOutput.contains("Could not") {
                logCallback("[Ketok] ⚠️ Code generation had issues:\n")
                // Show last relevant lines
                let lines = buildRunnerOutput.components(separatedBy: "\n")
                let errorLines = lines.filter { $0.contains("SEVERE") || $0.contains("Error") || $0.contains("Could not") }
                for line in errorLines.suffix(10) {
                    logCallback("  \(line)\n")
                }
                // Don't fail the build — let the actual build step handle it
            } else {
                logCallback("[Ketok] Code generation finished.\n")
            }

            // Log timing
            logCallback(buildRunnerOutput.components(separatedBy: "\n")
                .filter { $0.contains("Succeeded") || $0.contains("seconds") }
                .joined(separator: "\n"))

            // Post-verification: check if previously-missing files were actually generated
            let stillMissing = requirements.missingFiles.filter { relPath in
                let fullPath = (projectPath as NSString).appendingPathComponent(relPath)
                return !FileManager.default.fileExists(atPath: fullPath)
            }
            if !stillMissing.isEmpty {
                logCallback("\n[Ketok] 🚨 \(stillMissing.count) file(s) still missing after build_runner:\n")
                for file in stillMissing {
                    logCallback("[Ketok]    ❌ \(file)\n")
                }

                // Check if envied files are among the missing — attempt auto-fix
                let enviedMissing = stillMissing.filter { $0.contains("app_env") || $0.contains("env.g.dart") }
                if !enviedMissing.isEmpty {
                    if requirements.enviedVersionIncompatible {
                        // Auto-upgrade envied/envied_generator to fix analyzer incompatibility
                        logCallback("\n[Ketok] 🔍 Detected envied_generator version incompatibility:\n")
                        logCallback("[Ketok]    envied_generator: \(requirements.enviedResolvedVersion ?? "unknown") (needs upgrade)\n")
                        logCallback("[Ketok]    analyzer: \(requirements.analyzerResolvedVersion ?? "unknown")\n")
                        logCallback("[Ketok] 🔧 Auto-upgrading envied & envied_generator...\n")

                        let upgraded = upgradeEnviedPackages(
                            projectPath: projectPath,
                            environment: environment,
                            logCallback: logCallback
                        )

                        if upgraded {
                            // Retry build_runner after upgrade
                            logCallback("[Ketok] 🔄 Re-running code generation with upgraded envied...\n")
                            let _ = runCommand(
                                "dart run build_runner clean",
                                projectPath: projectPath,
                                environment: environment
                            )
                            let retryOutput = runCommand(
                                "dart run build_runner build --delete-conflicting-outputs",
                                projectPath: projectPath,
                                environment: environment
                            )

                            // Check if the files were generated this time
                            let retryStillMissing = enviedMissing.filter { relPath in
                                let fullPath = (projectPath as NSString).appendingPathComponent(relPath)
                                return !FileManager.default.fileExists(atPath: fullPath)
                            }

                            if retryStillMissing.isEmpty {
                                logCallback("[Ketok] ✅ envied files generated successfully after upgrade!\n")
                            } else {
                                logCallback("[Ketok] ❌ envied files still missing after upgrade. Verbose output:\n")
                                // Show verbose output for debugging
                                let relevantLines = retryOutput.components(separatedBy: "\n")
                                    .filter { $0.lowercased().contains("envied") || $0.contains("app_env")
                                        || $0.contains("SEVERE") || $0.contains("Error")
                                        || $0.contains("WARNING") || $0.lowercased().contains(".env") }
                                for line in relevantLines.suffix(15) {
                                    logCallback("[Ketok]    \(line)\n")
                                }
                                if relevantLines.isEmpty {
                                    // No envied-specific output — show last 10 lines
                                    let allLines = retryOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
                                    logCallback("[Ketok]    (No envied-specific output found. Last lines:)\n")
                                    for line in allLines.suffix(10) {
                                        logCallback("[Ketok]    \(line)\n")
                                    }
                                }
                            }
                        }
                    } else {
                        // envied version is compatible but still failing — run verbose for diagnostics
                        logCallback("\n[Ketok] 🔍 Running verbose build for envied diagnostics...\n")
                        let verboseOutput = runCommand(
                            "dart run build_runner build --verbose --delete-conflicting-outputs",
                            projectPath: projectPath,
                            environment: environment
                        )

                        let relevantLines = verboseOutput.components(separatedBy: "\n")
                            .filter { $0.lowercased().contains("envied") || $0.contains("app_env")
                                || $0.contains("SEVERE") || $0.contains("Error")
                                || $0.lowercased().contains(".env") }

                        if !relevantLines.isEmpty {
                            logCallback("[Ketok]    Envied-related output:\n")
                            for line in relevantLines.suffix(15) {
                                logCallback("[Ketok]    \(line)\n")
                            }
                        } else {
                            logCallback("[Ketok]    💡 No envied-specific errors found. Check:\n")
                            logCallback("[Ketok]       1. .env file exists in project root with all required variables\n")
                            logCallback("[Ketok]       2. envied and envied_generator versions are compatible\n")
                            logCallback("[Ketok]       3. Try manually: dart run build_runner build --verbose\n")
                        }
                    }
                }

                // Report non-envied missing files
                let nonEnviedMissing = stillMissing.filter { !$0.contains("app_env") && !$0.contains("env.g.dart") }
                if !nonEnviedMissing.isEmpty {
                    logCallback("[Ketok] 💡 Other missing files — may need manual intervention:\n")
                    for file in nonEnviedMissing {
                        logCallback("[Ketok]    \(file)\n")
                    }
                }

                logCallback("\n")
            }
        } else if requirements.needsBuildRunner && !requirements.needsCodeGeneration {
            logCallback("[Ketok] build_runner detected but all generated files are up to date. Skipping.\n")
        }

        // Step 2: flutter_gen asset generation
        // In v5.5+, flutter_gen_runner no longer has a standalone bin/ entry point —
        // it runs as a builder through build_runner. Try the standalone command first,
        // fall back to build_runner if it fails (handles both old and new versions).
        if requirements.needsFlutterGen {
            logCallback("[Ketok] Running flutter_gen asset generation...\n")

            // First try: standalone command (works for flutter_gen_runner < 5.5)
            let genOutput = runCommand(
                "dart run flutter_gen_runner",
                projectPath: projectPath,
                environment: environment
            )

            if genOutput.contains("Could not find") || genOutput.contains("could not find") {
                // Standalone entry point missing — this is v5.5+, use build_runner with filter
                logCallback("[Ketok] flutter_gen_runner v5.5+ detected, running via build_runner...\n")
                let buildRunnerGenOutput = runCommand(
                    "dart run build_runner build --delete-conflicting-outputs --build-filter=\"lib/gen/**\"",
                    projectPath: projectPath,
                    environment: environment
                )
                if buildRunnerGenOutput.contains("SEVERE") || buildRunnerGenOutput.contains("Error") {
                    logCallback("[Ketok] ⚠️ flutter_gen via build_runner had issues: \(buildRunnerGenOutput.prefix(300))\n")
                } else {
                    logCallback("[Ketok] Asset generation complete (via build_runner).\n")
                }
            } else if genOutput.contains("Error") {
                logCallback("[Ketok] ⚠️ flutter_gen warning: \(genOutput.prefix(200))\n")
            } else {
                logCallback("[Ketok] Asset generation complete.\n")
            }
        }

        // Step 3: Localization generation (flutter gen-l10n)
        // Generates Dart localization files from .arb translation files.
        // Equivalent to: fvm flutter gen-l10n
        if requirements.needsL10n {
            logCallback("[Ketok] 🌐 Running localization generation (flutter gen-l10n)...\n")

            let l10nOutput = runCommand(
                "flutter gen-l10n",
                projectPath: projectPath,
                environment: environment
            )

            if l10nOutput.contains("Error") || l10nOutput.contains("error:") || l10nOutput.contains("FAIL") {
                logCallback("[Ketok] ⚠️ gen-l10n had issues:\n")
                // Show first few lines of error output
                let errorLines = l10nOutput.components(separatedBy: "\n")
                    .filter { $0.contains("Error") || $0.contains("error") || $0.contains("Missing") || $0.contains("Could not") }
                    .prefix(5)
                for line in errorLines {
                    logCallback("[Ketok]    \(line)\n")
                }
                if errorLines.isEmpty {
                    logCallback("[Ketok]    \(String(l10nOutput.prefix(300)))\n")
                }
                logCallback("[Ketok] 💡 Check your l10n.yaml config and .arb files.\n\n")
            } else {
                logCallback("[Ketok] ✅ Localization files generated successfully.\n")
            }
        }

        return success
    }

    // MARK: - Dependency Overrides Management

    /// Idempotently add or update packages in the dependency_overrides section of pubspec.yaml.
    /// - If the package already exists in overrides, update its version.
    /// - If not, add it.
    /// - If no dependency_overrides section exists, create one.
    /// Returns the modified content string.
    private static func addDependencyOverrides(
        to content: String,
        packages: [(name: String, version: String)]
    ) -> String {
        var lines = content.components(separatedBy: "\n")

        // Find the dependency_overrides section
        var overridesStartIndex: Int? = nil
        var overridesEndIndex: Int? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "dependency_overrides:" || trimmed.hasPrefix("dependency_overrides:") {
                overridesStartIndex = i
                continue
            }
            // Once inside overrides, find the end (next top-level key or EOF)
            if let start = overridesStartIndex, i > start {
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    overridesEndIndex = i
                    break
                }
            }
        }

        if let start = overridesStartIndex {
            // Section exists — update or add entries
            var end = overridesEndIndex ?? lines.count

            for pkg in packages {
                // Check if this package is already in the overrides section
                var found = false
                for i in (start + 1)..<end {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("\(pkg.name):") {
                        // Update existing entry
                        lines[i] = "  \(pkg.name): \(pkg.version)"
                        found = true
                        break
                    }
                }
                if !found {
                    // Insert after the section header
                    lines.insert("  \(pkg.name): \(pkg.version)", at: start + 1)
                    // Adjust end index since we inserted a line
                    end += 1
                }
            }
        } else {
            // No overrides section — create one at the end
            lines.append("")
            lines.append("dependency_overrides:")
            for pkg in packages {
                lines.append("  \(pkg.name): \(pkg.version)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Remove specific packages from the dependency_overrides section.
    /// If the section becomes empty, remove it entirely.
    private static func removeDependencyOverrides(
        from content: String,
        packages: [String]
    ) -> String {
        var lines = content.components(separatedBy: "\n")
        let packageSet = Set(packages)

        var overridesStartIndex: Int? = nil
        var overridesEndIndex: Int? = nil

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "dependency_overrides:" || trimmed.hasPrefix("dependency_overrides:") {
                overridesStartIndex = i
                continue
            }
            if let start = overridesStartIndex, i > start {
                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    overridesEndIndex = i
                    break
                }
            }
        }

        guard let start = overridesStartIndex else { return content }
        let end = overridesEndIndex ?? lines.count

        // Remove matching entries (iterate backwards to preserve indices)
        for i in stride(from: end - 1, through: start + 1, by: -1) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            for pkg in packageSet {
                if trimmed.hasPrefix("\(pkg):") {
                    lines.remove(at: i)
                    break
                }
            }
        }

        // Check if the section is now empty (only header, no entries)
        let updatedEnd = min(start + 1, lines.count)
        let hasEntries: Bool
        if updatedEnd < lines.count {
            let nextLine = lines[updatedEnd].trimmingCharacters(in: .whitespaces)
            hasEntries = nextLine.isEmpty || nextLine.hasPrefix("#") ? false : (lines[updatedEnd].hasPrefix(" ") || lines[updatedEnd].hasPrefix("\t"))
        } else {
            hasEntries = false
        }

        if !hasEntries {
            // Remove the empty section header and any trailing blank line
            lines.remove(at: start)
            if start > 0 && start <= lines.count && lines[start - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                lines.remove(at: start - 1)
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Build Script Compilation Fix

    /// A broken builder package detected from build_runner output
    struct BrokenBuilder {
        let name: String              // Package name, e.g. "mockito"
        let currentVersion: String    // Currently resolved version
        let availableVersion: String? // Latest available version (from pub outdated output)
    }

    /// Detect packages that cause build_runner's build script to fail to compile.
    /// When a builder package is incompatible with the current analyzer version,
    /// the ENTIRE build_runner fails — no generators run at all.
    ///
    /// Parses build_runner output for patterns like:
    ///   "W ../../.pub-cache/hosted/pub.dev/mockito-5.4.5/lib/src/builder.dart:845:23: Error: ..."
    private static func detectBrokenBuildScriptPackages(from buildRunnerOutput: String) -> [BrokenBuilder] {
        // Only check if the build script compilation phase had errors
        guard buildRunnerOutput.contains("Compiling the build script") else { return [] }

        var brokenPackages: [String: String] = [:] // name -> version

        // Pattern: .pub-cache/hosted/pub.dev/PACKAGE-VERSION/lib/...builder.dart:...: Error:
        let errorPattern = try? NSRegularExpression(
            pattern: #"\.pub-cache/hosted/pub\.dev/([a-z_]+)-(\d+\.\d+\.\d+[^/]*)/lib/.*?:\s*Error:"#
        )

        let lines = buildRunnerOutput.components(separatedBy: "\n")
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = errorPattern?.firstMatch(in: line, range: range),
               let nameRange = Range(match.range(at: 1), in: line),
               let versionRange = Range(match.range(at: 2), in: line) {
                let name = String(line[nameRange])
                let version = String(line[versionRange])
                brokenPackages[name] = version
            }
        }

        // Map known packages to their latest compatible versions
        // This avoids a slow `pub outdated` call — we hardcode known-good versions
        // for common offenders and fall back to "latest" for unknown ones.
        let knownUpgrades: [String: String] = [
            "mockito": "5.6.3",      // Fixed InterfaceElement → InterfaceElementImpl in analyzer 7.x+
        ]

        return brokenPackages.map { name, version in
            BrokenBuilder(
                name: name,
                currentVersion: version,
                availableVersion: knownUpgrades[name]
            )
        }
    }

    /// Fix broken builder packages by adding them to dependency_overrides.
    /// Returns true if the fix was applied and pub get succeeded.
    private static func fixBrokenBuilders(
        _ builders: [BrokenBuilder],
        projectPath: String,
        environment: [String: String],
        logCallback: @escaping (String) -> Void
    ) -> Bool {
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard var content = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else {
            return false
        }

        // Build the override entries using the idempotent helper
        var packages: [(name: String, version: String)] = []
        for builder in builders {
            let targetVersion = builder.availableVersion ?? builder.currentVersion
            packages.append((builder.name, targetVersion))
            logCallback("[Ketok] 🔧 Adding \(builder.name): \(targetVersion) to dependency_overrides\n")
        }

        content = addDependencyOverrides(to: content, packages: packages)

        do {
            try content.write(toFile: pubspecPath, atomically: true, encoding: .utf8)
        } catch {
            logCallback("[Ketok] ❌ Could not update pubspec.yaml\n")
            return false
        }

        // Run pub get to apply overrides
        logCallback("[Ketok] 🔄 Resolving dependencies with fixed builders...\n")
        let pubGetOutput = runCommand(
            "flutter pub get",
            projectPath: projectPath,
            environment: environment
        )

        let hasError = pubGetOutput.contains("version solving failed")
            || pubGetOutput.contains("Could not")

        if hasError {
            logCallback("[Ketok] ❌ Could not resolve dependencies with builder overrides\n")
            return false
        }

        logCallback("[Ketok] ✅ Builder overrides applied successfully\n")
        logCallback("[Ketok]    ⚠️ dependency_overrides added — remove after updating packages properly\n")
        return true
    }

    // MARK: - Envied Auto-Upgrade

    /// Upgrade envied and envied_generator to the latest compatible version.
    /// This handles the common case where envied_generator is too old for
    /// the current analyzer version (e.g., envied_generator 1.1.1 with analyzer 7.x+).
    ///
    /// Version compatibility history:
    /// - 1.2.1: added analyzer >=7.4.0 support
    /// - 1.3.0: broadened build/source_gen constraints
    /// - 1.3.2: added analyzer 9.0 support
    /// - 1.3.3: added analyzer 10.0 support
    private static func upgradeEnviedPackages(
        projectPath: String,
        environment: [String: String],
        logCallback: @escaping (String) -> Void
    ) -> Bool {
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard let originalContent = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else {
            logCallback("[Ketok] ❌ Could not read pubspec.yaml\n")
            return false
        }

        // Backup pubspec.yaml and pubspec.lock
        let lockPath = (projectPath as NSString).appendingPathComponent("pubspec.lock")
        let originalLock = try? String(contentsOfFile: lockPath, encoding: .utf8)

        let enviedPattern = try? NSRegularExpression(
            pattern: #"(envied:\s*)['\"]?[\^~]?[\d][\d.]*['\"]?"#
        )
        let enviedGenPattern = try? NSRegularExpression(
            pattern: #"(envied_generator:\s*)['\"]?[\^~]?[\d][\d.]*['\"]?"#
        )

        // Strategy 1: Try upgrading to ^1.3.3 (latest, full analyzer support)
        // Strategy 2: Try ^1.3.0 (broadened source_gen/build constraints)
        // Strategy 3: Try dependency_overrides (bypasses version solver — nuclear option)
        let versionStrategies = ["^1.3.3", "^1.3.0"]

        for targetVersion in versionStrategies {
            logCallback("[Ketok]    Trying envied \(targetVersion)...\n")

            var content = originalContent
            if let regex = enviedPattern {
                let range = NSRange(content.startIndex..., in: content)
                content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\(targetVersion)")
            }
            if let regex = enviedGenPattern {
                let range = NSRange(content.startIndex..., in: content)
                content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\(targetVersion)")
            }

            try? content.write(toFile: pubspecPath, atomically: true, encoding: .utf8)

            let pubGetOutput = runCommand(
                "flutter pub get",
                projectPath: projectPath,
                environment: environment
            )

            let hasError = pubGetOutput.contains("version solving failed")
                || pubGetOutput.contains("Could not")
                || pubGetOutput.lowercased().contains("forbidden")
                || pubGetOutput.lowercased().contains("incompatible")

            if !hasError {
                logCallback("[Ketok] ✅ Dependencies resolved with envied \(targetVersion)\n")
                return true
            }

            // Log the conflict details for debugging
            let conflictLines = pubGetOutput.components(separatedBy: "\n")
                .filter { $0.contains("envied") || $0.contains("version solving") || $0.contains("requires") || $0.contains("depends on") }
            if !conflictLines.isEmpty {
                logCallback("[Ketok]    Conflict: \(conflictLines.prefix(3).joined(separator: " | "))\n")
            }
        }

        // Strategy 3: Use dependency_overrides to force envied_generator version
        // This bypasses the version solver entirely — safe for build-time-only generators
        logCallback("[Ketok]    Version upgrade failed — using dependency_overrides fallback...\n")

        // Restore original pubspec.yaml first
        try? originalContent.write(toFile: pubspecPath, atomically: true, encoding: .utf8)
        if let lock = originalLock {
            try? lock.write(toFile: lockPath, atomically: true, encoding: .utf8)
        }

        // Add dependency_overrides using idempotent helper (prevents duplicate keys)
        let overrideContent = addDependencyOverrides(to: originalContent, packages: [
            ("envied", "^1.3.3"),
            ("envied_generator", "^1.3.3")
        ])

        try? overrideContent.write(toFile: pubspecPath, atomically: true, encoding: .utf8)

        let overrideOutput = runCommand(
            "flutter pub get",
            projectPath: projectPath,
            environment: environment
        )

        let overrideHasError = overrideOutput.contains("version solving failed")
            || overrideOutput.contains("Could not")

        if !overrideHasError {
            logCallback("[Ketok] ✅ Resolved via dependency_overrides (envied ^1.3.3)\n")
            logCallback("[Ketok]    ⚠️ dependency_overrides added to pubspec.yaml — remove after confirming build works\n")
            return true
        }

        // Strategy 4: Try dependency_overrides with ^1.3.0
        logCallback("[Ketok]    Override with ^1.3.3 failed — trying ^1.3.0...\n")
        // Restore original first, then use idempotent helper
        try? originalContent.write(toFile: pubspecPath, atomically: true, encoding: .utf8)
        if let lock = originalLock {
            try? lock.write(toFile: lockPath, atomically: true, encoding: .utf8)
        }
        let override2Content = addDependencyOverrides(to: originalContent, packages: [
            ("envied", "^1.3.0"),
            ("envied_generator", "^1.3.0")
        ])

        try? override2Content.write(toFile: pubspecPath, atomically: true, encoding: .utf8)

        let override2Output = runCommand(
            "flutter pub get",
            projectPath: projectPath,
            environment: environment
        )

        let override2HasError = override2Output.contains("version solving failed")
            || override2Output.contains("Could not")

        if !override2HasError {
            logCallback("[Ketok] ✅ Resolved via dependency_overrides (envied ^1.3.0)\n")
            logCallback("[Ketok]    ⚠️ dependency_overrides added to pubspec.yaml — remove after confirming build works\n")
            return true
        }

        // All strategies failed — restore original
        logCallback("[Ketok] ❌ All envied upgrade strategies failed\n")

        // Log the last error for debugging
        let errorLines = override2Output.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .suffix(5)
        for line in errorLines {
            logCallback("[Ketok]    \(line)\n")
        }

        try? originalContent.write(toFile: pubspecPath, atomically: true, encoding: .utf8)
        if let lock = originalLock {
            try? lock.write(toFile: lockPath, atomically: true, encoding: .utf8)
        }
        let _ = runCommand("flutter pub get", projectPath: projectPath, environment: environment)

        return false
    }

    /// Run a shell command and return its combined stdout+stderr
    private static func runCommand(_ command: String, projectPath: String, environment: [String: String]) -> String {
        // Auto-resolve flutter/dart commands through FVM when the project uses it
        let resolvedCommand = ProjectEnvironmentDetector.resolveFlutterCommand(command, projectPath: projectPath)

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.arguments = ["-c", resolvedCommand]
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
}

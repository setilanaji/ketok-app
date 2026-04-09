import Foundation

/// Version bump type
enum VersionBumpType: String, CaseIterable, Identifiable {
    case major = "Major"
    case minor = "Minor"
    case patch = "Patch"
    case custom = "Custom"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .major: return "arrow.up.circle.fill"
        case .minor: return "arrow.up.right.circle.fill"
        case .patch: return "arrow.right.circle.fill"
        case .custom: return "pencil.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .major: return "Breaking changes (1.0.0 → 2.0.0)"
        case .minor: return "New features (1.0.0 → 1.1.0)"
        case .patch: return "Bug fixes (1.0.0 → 1.0.1)"
        case .custom: return "Set version manually"
        }
    }
}

/// Parsed version info from a project
struct ProjectVersion: Equatable {
    var versionName: String      // e.g. "1.2.3"
    var versionCode: String      // e.g. "10" or "1020300"
    var filePath: String         // path to build.gradle or pubspec.yaml
    var lineNumberName: Int?     // line in file where versionName is defined
    var lineNumberCode: Int?     // line in file where versionCode is defined

    /// Parsed semver components
    var major: Int { components.0 }
    var minor: Int { components.1 }
    var patch: Int { components.2 }

    private var components: (Int, Int, Int) {
        let parts = versionName
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: ".")
        let m = Int(parts[safe: 0] ?? "0") ?? 0
        let n = Int(parts[safe: 1] ?? "0") ?? 0
        let p = Int(parts[safe: 2] ?? "0") ?? 0
        return (m, n, p)
    }

    /// Compute the next version for a given bump type
    func bumped(_ type: VersionBumpType) -> String {
        switch type {
        case .major: return "\(major + 1).0.0"
        case .minor: return "\(major).\(minor + 1).0"
        case .patch: return "\(major).\(minor).\(patch + 1)"
        case .custom: return versionName
        }
    }

    /// Auto-increment version code
    var nextVersionCode: String {
        let code = Int(versionCode) ?? 0
        return "\(code + 1)"
    }
}

/// Result of a version bump operation
struct VersionBumpResult {
    var success: Bool
    var oldVersion: String
    var newVersion: String
    var oldCode: String
    var newCode: String
    var filePath: String
    var error: String?
    var gitTagCreated: Bool = false
}

/// Service that reads and bumps version numbers in Android/Flutter projects
class VersionBumperService: ObservableObject {
    @Published var currentVersion: ProjectVersion?
    @Published var lastBumpResult: VersionBumpResult?
    @Published var isProcessing = false

    // MARK: - Read Version

    /// Detect current version from a project
    func detectVersion(project: AndroidProject) {
        if project.isFlutter {
            currentVersion = readFlutterVersion(projectPath: project.path)
        } else {
            currentVersion = readGradleVersion(projectPath: project.path, appModule: project.resolvedAppModule)
        }
    }

    /// Read version from pubspec.yaml (Flutter)
    private func readFlutterVersion(projectPath: String) -> ProjectVersion? {
        let pubspecPath = (projectPath as NSString).appendingPathComponent("pubspec.yaml")
        guard let content = try? String(contentsOfFile: pubspecPath, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")
        var versionName: String?
        var versionCode: String?
        var lineNum: Int?

        for (index, line) in lines.enumerated() {
            // Match: version: 1.2.3+45
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("version:") {
                let value = trimmed.replacingOccurrences(of: "version:", with: "").trimmingCharacters(in: .whitespaces)
                let parts = value.components(separatedBy: "+")
                versionName = parts[0]
                versionCode = parts.count > 1 ? parts[1] : nil
                lineNum = index
                break
            }
        }

        guard let name = versionName else { return nil }
        return ProjectVersion(
            versionName: name,
            versionCode: versionCode ?? "1",
            filePath: pubspecPath,
            lineNumberName: lineNum,
            lineNumberCode: lineNum  // Same line for Flutter
        )
    }

    /// Read version from build.gradle/.kts (Native Android)
    private func readGradleVersion(projectPath: String, appModule: String) -> ProjectVersion? {
        // Try build.gradle.kts first, then build.gradle
        let modulePath = (projectPath as NSString).appendingPathComponent(appModule)
        let ktsPath = (modulePath as NSString).appendingPathComponent("build.gradle.kts")
        let groovyPath = (modulePath as NSString).appendingPathComponent("build.gradle")

        let gradlePath: String
        if FileManager.default.fileExists(atPath: ktsPath) {
            gradlePath = ktsPath
        } else if FileManager.default.fileExists(atPath: groovyPath) {
            gradlePath = groovyPath
        } else {
            return nil
        }

        guard let content = try? String(contentsOfFile: gradlePath, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n")

        var versionName: String?
        var versionCode: String?
        var lineNumName: Int?
        var lineNumCode: Int?

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Groovy: versionName "1.2.3" or versionName '1.2.3'
            // KTS: versionName = "1.2.3"
            if trimmed.contains("versionName") && !trimmed.hasPrefix("//") {
                let regex = try? NSRegularExpression(pattern: "[\"']([\\d]+\\.[\\d]+\\.[\\d]+[\\w.-]*)[\"']")
                if let match = regex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let range = Range(match.range(at: 1), in: trimmed) {
                    versionName = String(trimmed[range])
                    lineNumName = index
                }
            }

            // versionCode 10 or versionCode = 10
            if trimmed.contains("versionCode") && !trimmed.hasPrefix("//") {
                let regex = try? NSRegularExpression(pattern: "(\\d+)")
                if let match = regex?.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let range = Range(match.range(at: 1), in: trimmed) {
                    versionCode = String(trimmed[range])
                    lineNumCode = index
                }
            }
        }

        guard let name = versionName else { return nil }
        return ProjectVersion(
            versionName: name,
            versionCode: versionCode ?? "1",
            filePath: gradlePath,
            lineNumberName: lineNumName,
            lineNumberCode: lineNumCode
        )
    }

    // MARK: - Write Version

    /// Bump the version and optionally create a git tag
    func bumpVersion(
        project: AndroidProject,
        bumpType: VersionBumpType,
        customVersion: String? = nil,
        customCode: String? = nil,
        autoIncrementCode: Bool = true,
        createGitTag: Bool = false
    ) {
        guard let current = currentVersion else { return }
        isProcessing = true

        let newVersion = bumpType == .custom ? (customVersion ?? current.versionName) : current.bumped(bumpType)
        let newCode: String
        if let custom = customCode, !custom.isEmpty {
            newCode = custom
        } else if autoIncrementCode {
            newCode = current.nextVersionCode
        } else {
            newCode = current.versionCode
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result: VersionBumpResult

            if project.isFlutter {
                result = self?.writeFlutterVersion(
                    current: current, newVersion: newVersion, newCode: newCode
                ) ?? VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: "Internal error")
            } else {
                result = self?.writeGradleVersion(
                    current: current, newVersion: newVersion, newCode: newCode
                ) ?? VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: "Internal error")
            }

            // Optional: create git tag
            var finalResult = result
            if result.success && createGitTag {
                let tagName = "v\(newVersion)"
                let tagResult = GitService.tagRelease(at: project.path, tagName: tagName, message: "Release \(newVersion)")
                finalResult.gitTagCreated = tagResult.success
            }

            DispatchQueue.main.async {
                self?.lastBumpResult = finalResult
                self?.isProcessing = false
                // Re-detect to refresh current version
                if finalResult.success {
                    self?.detectVersion(project: project)
                }
            }
        }
    }

    /// Write new version to pubspec.yaml
    private func writeFlutterVersion(current: ProjectVersion, newVersion: String, newCode: String) -> VersionBumpResult {
        guard var content = try? String(contentsOfFile: current.filePath, encoding: .utf8) else {
            return VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: "Cannot read file")
        }

        // Replace: version: X.Y.Z+Code
        let oldPattern = "version: \(current.versionName)+\(current.versionCode)"
        let newValue = "version: \(newVersion)+\(newCode)"

        if content.contains(oldPattern) {
            content = content.replacingOccurrences(of: oldPattern, with: newValue)
        } else {
            // Try more flexible regex replacement
            guard let regex = try? NSRegularExpression(pattern: "version:\\s*\\S+") else {
                return VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: "Regex failed")
            }
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: newValue)
        }

        do {
            try content.write(toFile: current.filePath, atomically: true, encoding: .utf8)
            return VersionBumpResult(success: true, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath)
        } catch {
            return VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: error.localizedDescription)
        }
    }

    /// Write new version to build.gradle or build.gradle.kts
    private func writeGradleVersion(current: ProjectVersion, newVersion: String, newCode: String) -> VersionBumpResult {
        guard var content = try? String(contentsOfFile: current.filePath, encoding: .utf8) else {
            return VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: "Cannot read file")
        }

        // Replace versionName
        if let regex = try? NSRegularExpression(pattern: "(versionName\\s*=?\\s*)[\"']([\\d]+\\.[\\d]+\\.[\\d]+[\\w.-]*)[\"']") {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\"\(newVersion)\"")
        }

        // Replace versionCode
        if let regex = try? NSRegularExpression(pattern: "(versionCode\\s*=?\\s*)(\\d+)") {
            let range = NSRange(content.startIndex..., in: content)
            content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: "$1\(newCode)")
        }

        do {
            try content.write(toFile: current.filePath, atomically: true, encoding: .utf8)
            return VersionBumpResult(success: true, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath)
        } catch {
            return VersionBumpResult(success: false, oldVersion: current.versionName, newVersion: newVersion, oldCode: current.versionCode, newCode: newCode, filePath: current.filePath, error: error.localizedDescription)
        }
    }

    // MARK: - Git-Based Auto Versioning

    /// Determine the bump type automatically from conventional commit messages since last tag.
    /// Returns the appropriate bump type based on commit prefixes:
    /// - "BREAKING CHANGE:" or "feat!:" → major
    /// - "feat:" → minor
    /// - "fix:", "perf:", "refactor:" → patch
    func detectBumpFromGit(project: AndroidProject) -> (bumpType: VersionBumpType, commits: [String], reason: String) {
        let projectPath = project.path

        // Get last tag
        let lastTag = runGitCommand("git describe --tags --abbrev=0", at: projectPath)?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get commits since last tag (or all commits if no tags)
        let logCmd: String
        if let tag = lastTag, !tag.isEmpty {
            logCmd = "git log \(tag)..HEAD --pretty=format:%s"
        } else {
            logCmd = "git log --pretty=format:%s -50"
        }
        let output = runGitCommand(logCmd, at: projectPath) ?? ""
        let commits = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        guard !commits.isEmpty else {
            return (.patch, [], "No new commits since last tag")
        }

        // Analyze commit messages for conventional commit patterns
        var hasBreaking = false
        var hasFeature = false
        var hasFix = false

        for msg in commits {
            let lower = msg.lowercased()

            // Check for breaking changes
            if lower.contains("breaking change") || lower.contains("!:") {
                hasBreaking = true
            }

            // Check conventional commit prefixes
            if lower.hasPrefix("feat") {
                hasFeature = true
            }
            if lower.hasPrefix("fix") || lower.hasPrefix("perf") || lower.hasPrefix("refactor") {
                hasFix = true
            }
        }

        if hasBreaking {
            return (.major, commits, "Contains breaking changes")
        } else if hasFeature {
            return (.minor, commits, "Contains new features (\(commits.filter { $0.lowercased().hasPrefix("feat") }.count) feat commits)")
        } else if hasFix {
            return (.patch, commits, "Contains fixes/improvements")
        } else {
            return (.patch, commits, "\(commits.count) commits since \(lastTag ?? "start")")
        }
    }

    /// Auto-bump version based on git conventional commits
    func autoBumpFromGit(
        project: AndroidProject,
        createGitTag: Bool = true,
        dryRun: Bool = false
    ) -> (result: VersionBumpResult?, detection: (bumpType: VersionBumpType, commits: [String], reason: String)) {
        let detection = detectBumpFromGit(project: project)

        guard !dryRun else {
            let current = currentVersion
            return (
                VersionBumpResult(
                    success: true,
                    oldVersion: current?.versionName ?? "0.0.0",
                    newVersion: current?.bumped(detection.bumpType) ?? "0.0.1",
                    oldCode: current?.versionCode ?? "0",
                    newCode: current?.nextVersionCode ?? "1",
                    filePath: current?.filePath ?? "",
                    error: nil,
                    gitTagCreated: false
                ),
                detection
            )
        }

        // Perform the actual bump
        bumpVersion(
            project: project,
            bumpType: detection.bumpType,
            createGitTag: createGitTag
        )

        return (lastBumpResult, detection)
    }

    /// Suggest a pre-release version suffix based on branch name
    func suggestPreRelease(project: AndroidProject) -> String? {
        let branch = runGitCommand("git rev-parse --abbrev-ref HEAD", at: project.path)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let branchName = branch, !branchName.isEmpty else { return nil }

        // Generate pre-release suffix from branch name
        switch branchName {
        case "main", "master":
            return nil  // Release branch — no suffix
        case "develop", "dev":
            let shortSha = runGitCommand("git rev-parse --short HEAD", at: project.path)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
            return "-dev.\(shortSha)"
        default:
            // Feature branch: feature/ABC-123 → -alpha.ABC-123
            let sanitized = branchName
                .replacingOccurrences(of: "feature/", with: "")
                .replacingOccurrences(of: "bugfix/", with: "")
                .replacingOccurrences(of: "hotfix/", with: "")
                .replacingOccurrences(of: "/", with: "-")
            return "-alpha.\(sanitized)"
        }
    }

    private func runGitCommand(_ command: String, at path: String) -> String? {
        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: path)
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

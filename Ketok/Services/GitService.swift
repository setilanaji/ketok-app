import Foundation
import Combine

/// Represents a summary of git changes
struct GitChangeSummary: Equatable {
    var modifiedFiles: Int = 0
    var addedFiles: Int = 0
    var deletedFiles: Int = 0
    var untrackedFiles: Int = 0
    var hasUncommittedChanges: Bool = false
    var aheadCount: Int = 0     // commits ahead of remote
    var behindCount: Int = 0    // commits behind remote

    var totalChanges: Int {
        modifiedFiles + addedFiles + deletedFiles + untrackedFiles
    }

    var shortSummary: String {
        var parts: [String] = []
        if modifiedFiles > 0 { parts.append("\(modifiedFiles)M") }
        if addedFiles > 0 { parts.append("\(addedFiles)A") }
        if deletedFiles > 0 { parts.append("\(deletedFiles)D") }
        if untrackedFiles > 0 { parts.append("\(untrackedFiles)?") }
        return parts.isEmpty ? "Clean" : parts.joined(separator: " ")
    }

    /// Warning level for building with uncommitted changes
    var warningLevel: WarningLevel {
        if !hasUncommittedChanges { return .none }
        if totalChanges > 10 { return .high }
        if totalChanges > 3 { return .medium }
        return .low
    }

    enum WarningLevel: String {
        case none = "clean"
        case low = "minor"
        case medium = "moderate"
        case high = "significant"

        var color: String {
            switch self {
            case .none: return "green"
            case .low: return "yellow"
            case .medium: return "orange"
            case .high: return "red"
            }
        }
    }
}

/// Detects Git branch and status for Android projects
class GitService: ObservableObject {
    @Published var branches: [UUID: String] = [:]  // projectId -> branch name
    @Published var changeSummaries: [UUID: GitChangeSummary] = [:]  // projectId -> changes

    /// Refresh branches for all projects
    func refreshBranches(for projects: [AndroidProject]) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var result: [UUID: String] = [:]
            var changes: [UUID: GitChangeSummary] = [:]
            for project in projects {
                if let branch = Self.currentBranch(at: project.path) {
                    result[project.id] = branch
                }
                changes[project.id] = Self.getChangeSummary(at: project.path)
            }
            DispatchQueue.main.async {
                self?.branches = result
                self?.changeSummaries = changes
            }
        }
    }

    /// Get current branch for a single path
    static func currentBranch(at path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Check if there are uncommitted changes
    static func hasUncommittedChanges(at path: String) -> Bool {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["status", "--porcelain"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !output.isEmpty
        } catch {
            return false
        }
    }

    /// Get short commit hash
    static func shortHash(at path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--short", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Git-Aware Smart Builds

    /// Get a detailed change summary for a project
    static func getChangeSummary(at path: String) -> GitChangeSummary {
        var summary = GitChangeSummary()

        let output = runGit(at: path, args: ["status", "--porcelain"])
        guard !output.isEmpty else { return summary }

        summary.hasUncommittedChanges = true
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        for line in lines {
            guard line.count >= 2 else { continue }
            let index = line.index(line.startIndex, offsetBy: 0)
            let workTree = line.index(line.startIndex, offsetBy: 1)
            let indexChar = line[index]
            let workChar = line[workTree]

            if indexChar == "?" && workChar == "?" {
                summary.untrackedFiles += 1
            } else if indexChar == "A" || workChar == "A" {
                summary.addedFiles += 1
            } else if indexChar == "D" || workChar == "D" {
                summary.deletedFiles += 1
            } else {
                summary.modifiedFiles += 1
            }
        }

        // Check ahead/behind remote
        let aheadBehind = runGit(at: path, args: ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"])
        let abParts = aheadBehind.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        if abParts.count == 2 {
            summary.behindCount = Int(abParts[0]) ?? 0
            summary.aheadCount = Int(abParts[1]) ?? 0
        }

        return summary
    }

    /// Get the list of changed files (for display)
    static func getChangedFiles(at path: String) -> [String] {
        let output = runGit(at: path, args: ["status", "--porcelain"])
        return output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Remove the status prefix (first 2 chars + space)
                if trimmed.count > 3 {
                    return String(trimmed.dropFirst(3))
                }
                return trimmed
            }
    }

    /// Get a diff summary (stats only)
    static func getDiffStats(at path: String) -> String? {
        let output = runGit(at: path, args: ["diff", "--stat", "--no-color"])
        return output.isEmpty ? nil : output
    }

    /// Tag the current commit
    static func tagRelease(at path: String, tagName: String, message: String? = nil) -> (success: Bool, output: String) {
        var args = ["tag"]
        if let msg = message {
            args.append(contentsOf: ["-a", tagName, "-m", msg])
        } else {
            args.append(tagName)
        }

        let output = runGit(at: path, args: args)
        // git tag returns empty on success
        let checkOutput = runGit(at: path, args: ["tag", "-l", tagName])
        let success = checkOutput.contains(tagName)
        return (success, success ? "Tagged \(tagName)" : output)
    }

    /// Get recent tags
    static func recentTags(at path: String, count: Int = 5) -> [String] {
        let output = runGit(at: path, args: ["tag", "--sort=-creatordate"])
        return output.components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .prefix(count)
            .map { String($0) }
    }

    /// Get the last tag name
    static func lastTag(at path: String) -> String? {
        let output = runGit(at: path, args: ["describe", "--tags", "--abbrev=0"])
        let tag = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return tag.isEmpty ? nil : tag
    }

    /// Get commits since last tag
    static func commitsSinceLastTag(at path: String) -> [String] {
        guard let lastTag = lastTag(at: path) else { return [] }
        let output = runGit(at: path, args: ["log", "\(lastTag)..HEAD", "--oneline", "--no-decorate"])
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    // MARK: - Helper

    private static func runGit(at path: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

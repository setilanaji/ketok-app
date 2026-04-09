import Foundation

/// Generates build changelogs from git commits
class BuildChangelogService {

    /// Get git commits since the last build tag or specified commit count
    static func getChangelog(projectPath: String, maxCommits: Int = 20) -> [GitCommitEntry] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "log",
            "--pretty=format:%H|%h|%an|%ae|%at|%s",
            "-\(maxCommits)"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return output.components(separatedBy: "\n").compactMap { line in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 6 else { return nil }

                let timestamp = TimeInterval(parts[4]) ?? 0
                return GitCommitEntry(
                    hash: parts[0],
                    shortHash: parts[1],
                    author: parts[2],
                    email: parts[3],
                    date: Date(timeIntervalSince1970: timestamp),
                    message: parts[5...].joined(separator: "|")
                )
            }
        } catch {
            return []
        }
    }

    /// Get commits since last tag (useful for release notes)
    static func getCommitsSinceLastTag(projectPath: String) -> [GitCommitEntry] {
        // Find last tag
        let tagProcess = Process()
        let tagPipe = Pipe()
        tagProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        tagProcess.arguments = ["describe", "--tags", "--abbrev=0"]
        tagProcess.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        tagProcess.standardOutput = tagPipe
        tagProcess.standardError = FileHandle.nullDevice

        do {
            try tagProcess.run()
            tagProcess.waitUntilExit()
            if tagProcess.terminationStatus == 0 {
                let data = tagPipe.fileHandleForReading.readDataToEndOfFile()
                let tag = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !tag.isEmpty {
                    return getCommitsSince(ref: tag, projectPath: projectPath)
                }
            }
        } catch {}

        // Fallback to last 20 commits
        return getChangelog(projectPath: projectPath)
    }

    /// Get commits since a specific ref
    static func getCommitsSince(ref: String, projectPath: String) -> [GitCommitEntry] {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "log",
            "\(ref)..HEAD",
            "--pretty=format:%H|%h|%an|%ae|%at|%s"
        ]
        process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return output.components(separatedBy: "\n").compactMap { line in
                let parts = line.components(separatedBy: "|")
                guard parts.count >= 6 else { return nil }
                let timestamp = TimeInterval(parts[4]) ?? 0
                return GitCommitEntry(
                    hash: parts[0],
                    shortHash: parts[1],
                    author: parts[2],
                    email: parts[3],
                    date: Date(timeIntervalSince1970: timestamp),
                    message: parts[5...].joined(separator: "|")
                )
            }
        } catch {
            return []
        }
    }

    /// Format commits as markdown changelog
    static func formatAsMarkdown(commits: [GitCommitEntry], projectName: String, version: String?) -> String {
        var md = "# \(projectName)"
        if let v = version { md += " v\(v)" }
        md += "\n\n"

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        md += "**Date:** \(df.string(from: Date()))\n\n"
        md += "## Changes\n\n"

        for commit in commits {
            md += "- \(commit.message) (`\(commit.shortHash)` by \(commit.author))\n"
        }
        return md
    }
}

/// A single git commit entry
struct GitCommitEntry: Identifiable {
    let hash: String
    let shortHash: String
    let author: String
    let email: String
    let date: Date
    let message: String

    var id: String { hash }

    var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, HH:mm"
        return df.string(from: date)
    }
}

import AppKit
import Foundation

/// Format options for release notes
enum ReleaseNotesFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case plain = "Plain Text"
    case html = "HTML"
    case slack = "Slack"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .markdown: return "text.badge.checkmark"
        case .plain: return "doc.plaintext"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .slack: return "number"
        }
    }
}

/// Category for a commit (auto-detected from message)
enum CommitCategory: String, CaseIterable {
    case feature = "Features"
    case fix = "Bug Fixes"
    case refactor = "Refactoring"
    case docs = "Documentation"
    case test = "Testing"
    case chore = "Chores"
    case style = "Styling"
    case perf = "Performance"
    case ci = "CI/CD"
    case other = "Other"

    var icon: String {
        switch self {
        case .feature: return "sparkles"
        case .fix: return "ladybug.fill"
        case .refactor: return "arrow.triangle.2.circlepath"
        case .docs: return "doc.text"
        case .test: return "checkmark.shield"
        case .chore: return "wrench"
        case .style: return "paintbrush"
        case .perf: return "bolt.fill"
        case .ci: return "gearshape.2"
        case .other: return "ellipsis.circle"
        }
    }

    var emoji: String {
        switch self {
        case .feature: return "✨"
        case .fix: return "🐛"
        case .refactor: return "♻️"
        case .docs: return "📝"
        case .test: return "✅"
        case .chore: return "🔧"
        case .style: return "💄"
        case .perf: return "⚡"
        case .ci: return "🔄"
        case .other: return "📦"
        }
    }
}

/// A categorized commit for release notes
struct CategorizedCommit: Identifiable {
    let commit: GitCommitEntry
    var category: CommitCategory
    var include: Bool = true

    var id: String { commit.id }
}

/// Generated release notes output
struct ReleaseNotesOutput {
    var content: String
    var format: ReleaseNotesFormat
    var commitCount: Int
    var version: String?
    var dateGenerated: Date = Date()
}

/// Service that generates release notes from git history
class ReleaseNotesService: ObservableObject {
    @Published var commits: [CategorizedCommit] = []
    @Published var generatedNotes: ReleaseNotesOutput?
    @Published var isLoading = false
    @Published var source: CommitSource = .sinceLastTag

    enum CommitSource: String, CaseIterable, Identifiable {
        case sinceLastTag = "Since Last Tag"
        case lastN = "Last N Commits"
        case betweenTags = "Between Tags"

        var id: String { rawValue }
    }

    // MARK: - Load Commits

    /// Load and categorize commits for a project
    func loadCommits(project: AndroidProject, source: CommitSource, count: Int = 20) {
        isLoading = true
        self.source = source

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rawCommits: [GitCommitEntry]

            switch source {
            case .sinceLastTag:
                rawCommits = BuildChangelogService.getCommitsSinceLastTag(projectPath: project.path)
            case .lastN:
                rawCommits = BuildChangelogService.getChangelog(projectPath: project.path, maxCommits: count)
            case .betweenTags:
                rawCommits = BuildChangelogService.getCommitsSinceLastTag(projectPath: project.path)
            }

            let categorized = rawCommits.map { commit in
                CategorizedCommit(
                    commit: commit,
                    category: Self.categorize(message: commit.message)
                )
            }

            DispatchQueue.main.async {
                self?.commits = categorized
                self?.isLoading = false
            }
        }
    }

    // MARK: - Categorize

    /// Auto-categorize a commit based on conventional commit patterns
    static func categorize(message: String) -> CommitCategory {
        let lower = message.lowercased()

        // Conventional commits: feat:, fix:, etc.
        if lower.hasPrefix("feat") || lower.contains("feature") || lower.contains("add ") || lower.contains("added ") || lower.contains("new ") {
            return .feature
        }
        if lower.hasPrefix("fix") || lower.contains("bugfix") || lower.contains("hotfix") || lower.contains("patch") {
            return .fix
        }
        if lower.hasPrefix("refactor") || lower.contains("refactor") || lower.contains("restructure") || lower.contains("cleanup") || lower.contains("clean up") {
            return .refactor
        }
        if lower.hasPrefix("docs") || lower.contains("readme") || lower.contains("documentation") || lower.contains("comment") {
            return .docs
        }
        if lower.hasPrefix("test") || lower.contains("test") || lower.contains("spec") {
            return .test
        }
        if lower.hasPrefix("style") || lower.contains("ui ") || lower.contains("layout") || lower.contains("css") || lower.contains("design") {
            return .style
        }
        if lower.hasPrefix("perf") || lower.contains("performance") || lower.contains("optimize") || lower.contains("speed") {
            return .perf
        }
        if lower.hasPrefix("ci") || lower.contains("pipeline") || lower.contains("github action") || lower.contains("workflow") {
            return .ci
        }
        if lower.hasPrefix("chore") || lower.contains("bump") || lower.contains("update dep") || lower.contains("upgrade") || lower.contains("merge") {
            return .chore
        }

        return .other
    }

    // MARK: - Generate

    /// Generate release notes in the specified format
    func generate(
        projectName: String,
        version: String?,
        format: ReleaseNotesFormat,
        includeAuthors: Bool = false,
        includeEmoji: Bool = true,
        groupByCategory: Bool = true
    ) {
        let includedCommits = commits.filter(\.include)
        guard !includedCommits.isEmpty else {
            generatedNotes = ReleaseNotesOutput(content: "No commits selected.", format: format, commitCount: 0, version: version)
            return
        }

        let content: String
        switch format {
        case .markdown:
            content = generateMarkdown(projectName: projectName, version: version, commits: includedCommits, includeAuthors: includeAuthors, includeEmoji: includeEmoji, groupByCategory: groupByCategory)
        case .plain:
            content = generatePlainText(projectName: projectName, version: version, commits: includedCommits, includeAuthors: includeAuthors, groupByCategory: groupByCategory)
        case .html:
            content = generateHTML(projectName: projectName, version: version, commits: includedCommits, includeAuthors: includeAuthors, includeEmoji: includeEmoji, groupByCategory: groupByCategory)
        case .slack:
            content = generateSlack(projectName: projectName, version: version, commits: includedCommits, includeAuthors: includeAuthors, includeEmoji: includeEmoji, groupByCategory: groupByCategory)
        }

        generatedNotes = ReleaseNotesOutput(content: content, format: format, commitCount: includedCommits.count, version: version)
    }

    // MARK: - Formatters

    private func generateMarkdown(projectName: String, version: String?, commits: [CategorizedCommit], includeAuthors: Bool, includeEmoji: Bool, groupByCategory: Bool) -> String {
        var md = "# \(projectName)"
        if let v = version { md += " v\(v)" }
        md += "\n\n"

        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        md += "*Released \(df.string(from: Date()))*\n\n"

        if groupByCategory {
            let grouped = Dictionary(grouping: commits, by: \.category)
            let sortedCategories = CommitCategory.allCases.filter { grouped[$0] != nil }

            for category in sortedCategories {
                guard let categoryCommits = grouped[category] else { continue }
                let prefix = includeEmoji ? "\(category.emoji) " : ""
                md += "### \(prefix)\(category.rawValue)\n\n"

                for item in categoryCommits {
                    let cleanMsg = cleanMessage(item.commit.message)
                    md += "- \(cleanMsg)"
                    if includeAuthors { md += " — *\(item.commit.author)*" }
                    md += "\n"
                }
                md += "\n"
            }
        } else {
            for item in commits {
                let prefix = includeEmoji ? "\(item.category.emoji) " : ""
                let cleanMsg = cleanMessage(item.commit.message)
                md += "- \(prefix)\(cleanMsg)"
                if includeAuthors { md += " — *\(item.commit.author)*" }
                md += "\n"
            }
        }

        return md
    }

    private func generatePlainText(projectName: String, version: String?, commits: [CategorizedCommit], includeAuthors: Bool, groupByCategory: Bool) -> String {
        var text = "\(projectName)"
        if let v = version { text += " v\(v)" }
        text += "\n"
        text += String(repeating: "=", count: text.count - 1) + "\n\n"

        if groupByCategory {
            let grouped = Dictionary(grouping: commits, by: \.category)
            let sortedCategories = CommitCategory.allCases.filter { grouped[$0] != nil }

            for category in sortedCategories {
                guard let categoryCommits = grouped[category] else { continue }
                text += "\(category.rawValue):\n"
                for item in categoryCommits {
                    let cleanMsg = cleanMessage(item.commit.message)
                    text += "  * \(cleanMsg)"
                    if includeAuthors { text += " (\(item.commit.author))" }
                    text += "\n"
                }
                text += "\n"
            }
        } else {
            for item in commits {
                let cleanMsg = cleanMessage(item.commit.message)
                text += "* \(cleanMsg)"
                if includeAuthors { text += " (\(item.commit.author))" }
                text += "\n"
            }
        }

        return text
    }

    private func generateHTML(projectName: String, version: String?, commits: [CategorizedCommit], includeAuthors: Bool, includeEmoji: Bool, groupByCategory: Bool) -> String {
        var html = "<h1>\(projectName)"
        if let v = version { html += " v\(v)" }
        html += "</h1>\n"

        let df = DateFormatter()
        df.dateFormat = "MMMM d, yyyy"
        html += "<p><em>Released \(df.string(from: Date()))</em></p>\n"

        if groupByCategory {
            let grouped = Dictionary(grouping: commits, by: \.category)
            let sortedCategories = CommitCategory.allCases.filter { grouped[$0] != nil }

            for category in sortedCategories {
                guard let categoryCommits = grouped[category] else { continue }
                let prefix = includeEmoji ? "\(category.emoji) " : ""
                html += "<h3>\(prefix)\(category.rawValue)</h3>\n<ul>\n"
                for item in categoryCommits {
                    let cleanMsg = cleanMessage(item.commit.message)
                    html += "  <li>\(cleanMsg)"
                    if includeAuthors { html += " <em>— \(item.commit.author)</em>" }
                    html += "</li>\n"
                }
                html += "</ul>\n"
            }
        } else {
            html += "<ul>\n"
            for item in commits {
                let prefix = includeEmoji ? "\(item.category.emoji) " : ""
                let cleanMsg = cleanMessage(item.commit.message)
                html += "  <li>\(prefix)\(cleanMsg)"
                if includeAuthors { html += " <em>— \(item.commit.author)</em>" }
                html += "</li>\n"
            }
            html += "</ul>\n"
        }

        return html
    }

    private func generateSlack(projectName: String, version: String?, commits: [CategorizedCommit], includeAuthors: Bool, includeEmoji: Bool, groupByCategory: Bool) -> String {
        var slack = "*\(projectName)"
        if let v = version { slack += " v\(v)" }
        slack += "*\n\n"

        if groupByCategory {
            let grouped = Dictionary(grouping: commits, by: \.category)
            let sortedCategories = CommitCategory.allCases.filter { grouped[$0] != nil }

            for category in sortedCategories {
                guard let categoryCommits = grouped[category] else { continue }
                let prefix = includeEmoji ? "\(category.emoji) " : ""
                slack += "*\(prefix)\(category.rawValue)*\n"
                for item in categoryCommits {
                    let cleanMsg = cleanMessage(item.commit.message)
                    slack += "• \(cleanMsg)"
                    if includeAuthors { slack += " _— \(item.commit.author)_" }
                    slack += "\n"
                }
                slack += "\n"
            }
        } else {
            for item in commits {
                let prefix = includeEmoji ? "\(item.category.emoji) " : ""
                let cleanMsg = cleanMessage(item.commit.message)
                slack += "• \(prefix)\(cleanMsg)"
                if includeAuthors { slack += " _— \(item.commit.author)_" }
                slack += "\n"
            }
        }

        return slack
    }

    /// Strip conventional commit prefixes for cleaner output
    private func cleanMessage(_ message: String) -> String {
        // Remove prefixes like "feat: ", "fix(scope): ", etc.
        let pattern = "^(feat|fix|docs|style|refactor|perf|test|chore|ci|build|revert)(\\([^)]+\\))?:\\s*"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(message.startIndex..., in: message)
            let cleaned = regex.stringByReplacingMatches(in: message, range: range, withTemplate: "")
            // Capitalize first letter
            return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
        }
        return message
    }

    // MARK: - Copy & Export

    /// Copy generated notes to clipboard
    func copyToClipboard() {
        guard let notes = generatedNotes else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(notes.content, forType: .string)
    }

    /// Save generated notes to a file
    func saveToFile(directory: String) -> String? {
        guard let notes = generatedNotes else { return nil }

        let ext: String
        switch notes.format {
        case .markdown: ext = "md"
        case .plain: ext = "txt"
        case .html: ext = "html"
        case .slack: ext = "txt"
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let fileName = "release-notes-\(notes.version ?? "latest")-\(df.string(from: Date())).\(ext)"
        let filePath = (directory as NSString).appendingPathComponent(fileName)

        do {
            try notes.content.write(toFile: filePath, atomically: true, encoding: .utf8)
            return filePath
        } catch {
            return nil
        }
    }
}

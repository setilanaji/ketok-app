import Foundation
import Combine

/// Represents the result of analyzing Gradle build cache performance
struct BuildCacheReport: Identifiable {
    let id = UUID()
    let timestamp: Date = Date()
    let totalTasks: Int
    let cachedTasks: Int         // FROM-CACHE
    let executedTasks: Int       // Executed (not cached)
    let upToDateTasks: Int       // UP-TO-DATE
    let skippedTasks: Int        // SKIPPED
    let noSourceTasks: Int       // NO-SOURCE
    let cacheHitRate: Double     // 0.0 - 1.0
    let totalDuration: TimeInterval
    let configurationTime: TimeInterval
    let taskExecutionTime: TimeInterval
    let taskBreakdown: [TaskCacheEntry]
    let slowestTasks: [TaskTimingEntry]

    /// Formatted cache hit rate as percentage
    var hitRateFormatted: String {
        String(format: "%.1f%%", cacheHitRate * 100)
    }

    /// Formatted total duration
    var durationFormatted: String {
        if totalDuration >= 60 {
            return String(format: "%.0fm %.0fs", totalDuration / 60, totalDuration.truncatingRemainder(dividingBy: 60))
        }
        return String(format: "%.1fs", totalDuration)
    }
}

/// Individual task cache status
struct TaskCacheEntry: Identifiable, Hashable {
    let id = UUID()
    let taskPath: String         // e.g., ":app:compileDebugKotlin"
    let status: TaskCacheStatus
    let duration: TimeInterval?  // nil if not measured
}

/// Cache status for a single task
enum TaskCacheStatus: String, Hashable {
    case fromCache = "FROM-CACHE"
    case executed = "EXECUTED"
    case upToDate = "UP-TO-DATE"
    case skipped = "SKIPPED"
    case noSource = "NO-SOURCE"

    var icon: String {
        switch self {
        case .fromCache: return "arrow.down.circle.fill"
        case .executed: return "paperplane.fill"
        case .upToDate: return "checkmark.circle.fill"
        case .skipped: return "forward.fill"
        case .noSource: return "circle.dashed"
        }
    }

    var label: String {
        switch self {
        case .fromCache: return "Cached"
        case .executed: return "Executed"
        case .upToDate: return "Up-to-date"
        case .skipped: return "Skipped"
        case .noSource: return "No source"
        }
    }
}

/// Task timing entry for the "slowest tasks" list
struct TaskTimingEntry: Identifiable, Hashable {
    let id = UUID()
    let taskPath: String
    let duration: TimeInterval
    let status: TaskCacheStatus

    var durationFormatted: String {
        if duration >= 60 {
            return String(format: "%.0fm %.0fs", duration / 60, duration.truncatingRemainder(dividingBy: 60))
        } else if duration >= 1 {
            return String(format: "%.1fs", duration)
        }
        return String(format: "%.0fms", duration * 1000)
    }
}

/// Service that parses Gradle build output for cache analytics
class BuildCacheAnalyticsService: ObservableObject {
    @Published var latestReport: BuildCacheReport?
    @Published var reportHistory: [BuildCacheReport] = []
    @Published var isAnalyzing = false

    // MARK: - Parse from build log

    /// Analyze a Gradle build log string for cache statistics
    func analyzeBuildLog(_ log: String) -> BuildCacheReport {
        let lines = log.components(separatedBy: "\n")

        var totalTasks = 0
        var cachedTasks = 0
        var executedTasks = 0
        var upToDateTasks = 0
        var skippedTasks = 0
        var noSourceTasks = 0
        var taskBreakdown: [TaskCacheEntry] = []
        var taskTimings: [TaskTimingEntry] = []
        var totalDuration: TimeInterval = 0
        var configTime: TimeInterval = 0
        var taskExecTime: TimeInterval = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse task outcome lines like "> Task :app:compileDebugKotlin FROM-CACHE"
            if trimmed.hasPrefix("> Task ") {
                totalTasks += 1
                let taskLine = String(trimmed.dropFirst(7)) // Remove "> Task "

                let status: TaskCacheStatus
                let taskPath: String

                if taskLine.hasSuffix("FROM-CACHE") {
                    cachedTasks += 1
                    status = .fromCache
                    taskPath = String(taskLine.dropLast(11)).trimmingCharacters(in: .whitespaces)
                } else if taskLine.hasSuffix("UP-TO-DATE") {
                    upToDateTasks += 1
                    status = .upToDate
                    taskPath = String(taskLine.dropLast(11)).trimmingCharacters(in: .whitespaces)
                } else if taskLine.hasSuffix("SKIPPED") {
                    skippedTasks += 1
                    status = .skipped
                    taskPath = String(taskLine.dropLast(8)).trimmingCharacters(in: .whitespaces)
                } else if taskLine.hasSuffix("NO-SOURCE") {
                    noSourceTasks += 1
                    status = .noSource
                    taskPath = String(taskLine.dropLast(10)).trimmingCharacters(in: .whitespaces)
                } else {
                    executedTasks += 1
                    status = .executed
                    taskPath = taskLine.trimmingCharacters(in: .whitespaces)
                }

                taskBreakdown.append(TaskCacheEntry(taskPath: taskPath, status: status, duration: nil))
            }

            // Parse build scan timing if present
            // "BUILD SUCCESSFUL in 45s"
            if trimmed.contains("BUILD SUCCESSFUL in ") || trimmed.contains("BUILD FAILED in ") {
                totalDuration = parseDuration(from: trimmed)
            }

            // Parse --profile summary lines (if the build was run with --profile)
            // "Total Build Time:   1m 23.456s"
            if trimmed.hasPrefix("Total Build Time:") {
                totalDuration = parseDuration(from: trimmed)
            }
            if trimmed.hasPrefix("Startup:") || trimmed.hasPrefix("Settings and BuildSrc:") {
                configTime += parseDuration(from: trimmed)
            }
            if trimmed.hasPrefix("Task Execution:") {
                taskExecTime = parseDuration(from: trimmed)
            }

            // Parse task timing from --scan or --profile output
            // ":app:compileDebugKotlin   12.345s"
            if let timing = parseTaskTiming(line: trimmed) {
                taskTimings.append(timing)
            }
        }

        // If no task outcomes parsed from "> Task" lines, try the summary line
        // "XX actionable tasks: Y executed, Z from cache, W up-to-date"
        if totalTasks == 0 {
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.contains("actionable task") {
                    parseSummaryLine(trimmed,
                                     total: &totalTasks,
                                     executed: &executedTasks,
                                     cached: &cachedTasks,
                                     upToDate: &upToDateTasks)
                }
            }
        }

        // Calculate cache hit rate (cached / cacheable tasks)
        let cacheableTasks = cachedTasks + executedTasks
        let hitRate = cacheableTasks > 0 ? Double(cachedTasks) / Double(cacheableTasks) : 0.0

        // Top 10 slowest tasks
        let slowest = taskTimings.sorted { $0.duration > $1.duration }.prefix(10)

        let report = BuildCacheReport(
            totalTasks: totalTasks,
            cachedTasks: cachedTasks,
            executedTasks: executedTasks,
            upToDateTasks: upToDateTasks,
            skippedTasks: skippedTasks,
            noSourceTasks: noSourceTasks,
            cacheHitRate: hitRate,
            totalDuration: totalDuration,
            configurationTime: configTime,
            taskExecutionTime: taskExecTime,
            taskBreakdown: taskBreakdown,
            slowestTasks: Array(slowest)
        )

        DispatchQueue.main.async {
            self.latestReport = report
            self.reportHistory.insert(report, at: 0)
            if self.reportHistory.count > 20 { self.reportHistory = Array(self.reportHistory.prefix(20)) }
        }

        return report
    }

    /// Run a dedicated cache analysis build (with --build-cache and task output)
    func runCacheAnalysisBuild(projectPath: String, task: String = "assembleDebug", completion: @escaping (BuildCacheReport?) -> Void) {
        isAnalyzing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gradlew = "\(projectPath)/gradlew"
            guard FileManager.default.isExecutableFile(atPath: gradlew) else {
                DispatchQueue.main.async {
                    self?.isAnalyzing = false
                    completion(nil)
                }
                return
            }

            let process = Process()
            let pipe = Pipe()
            let errorPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: gradlew)
            process.currentDirectoryURL = URL(fileURLWithPath: projectPath)
            process.arguments = [task, "--build-cache", "--console=plain"]
            process.standardOutput = pipe
            process.standardError = errorPipe

            var env = ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"
            if let javaHome = env["JAVA_HOME"] ?? Self.detectJavaHome() {
                env["JAVA_HOME"] = javaHome
            }
            process.environment = env

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let output = (String(data: data, encoding: .utf8) ?? "") +
                             (String(data: errData, encoding: .utf8) ?? "")

                let report = self?.analyzeBuildLog(output)
                DispatchQueue.main.async {
                    self?.isAnalyzing = false
                    completion(report)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isAnalyzing = false
                    completion(nil)
                }
            }
        }
    }

    // MARK: - Parsing Helpers

    /// Parse duration from strings like "45s", "1m 23s", "BUILD SUCCESSFUL in 2m 15s"
    private func parseDuration(from text: String) -> TimeInterval {
        var totalSeconds: TimeInterval = 0

        // Match minutes
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*m(?:in)?\\b"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            totalSeconds += (Double(text[range]) ?? 0) * 60
        }

        // Match seconds (with optional decimals)
        if let regex = try? NSRegularExpression(pattern: "(\\d+\\.?\\d*)\\s*s\\b"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            totalSeconds += Double(text[range]) ?? 0
        }

        return totalSeconds
    }

    /// Parse task timing line like ":app:compileDebugKotlin  12.345s"
    private func parseTaskTiming(line: String) -> TaskTimingEntry? {
        // Pattern: task path followed by duration
        guard let regex = try? NSRegularExpression(pattern: "^(:\\S+)\\s+(\\d+\\.?\\d*)s$"),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let pathRange = Range(match.range(at: 1), in: line),
              let durationRange = Range(match.range(at: 2), in: line) else {
            return nil
        }

        let path = String(line[pathRange])
        let duration = Double(line[durationRange]) ?? 0

        return TaskTimingEntry(taskPath: path, duration: duration, status: .executed)
    }

    /// Parse the summary line "XX actionable tasks: Y executed, Z from cache"
    private func parseSummaryLine(_ line: String, total: inout Int, executed: inout Int, cached: inout Int, upToDate: inout Int) {
        if let regex = try? NSRegularExpression(pattern: "(\\d+) actionable task"),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            total = Int(line[range]) ?? 0
        }

        if let regex = try? NSRegularExpression(pattern: "(\\d+) executed"),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            executed = Int(line[range]) ?? 0
        }

        if let regex = try? NSRegularExpression(pattern: "(\\d+) from cache"),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            cached = Int(line[range]) ?? 0
        }

        if let regex = try? NSRegularExpression(pattern: "(\\d+) up-to-date"),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            upToDate = Int(line[range]) ?? 0
        }
    }

    /// Detect Java home from common macOS locations
    private static func detectJavaHome() -> String? {
        // Try /usr/libexec/java_home
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = path, !path.isEmpty { return path }
        }

        // Try Android Studio's bundled JBR
        let jbrPath = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        if FileManager.default.isDirectory(atPath: jbrPath) { return jbrPath }

        return nil
    }
}

// MARK: - FileManager extension

private extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

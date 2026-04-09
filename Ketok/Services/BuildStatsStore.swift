import Foundation
import Combine

/// A single recorded build stat entry
struct BuildRecord: Codable, Identifiable {
    var id: UUID = UUID()
    let projectId: UUID
    let projectName: String
    let variant: String
    let buildType: String
    let startTime: Date
    let endTime: Date
    let durationSeconds: Double
    let success: Bool
    let apkSizeBytes: Int64?
    let errorMessage: String?

    var formattedDuration: String {
        let total = Int(durationSeconds)
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var formattedAPKSize: String? {
        guard let bytes = apkSizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var formattedDate: String {
        let df = DateFormatter()
        df.dateFormat = "MMM d, HH:mm"
        return df.string(from: startTime)
    }
}

/// Aggregate stats for a project
struct ProjectBuildStats {
    let projectName: String
    let totalBuilds: Int
    let successCount: Int
    let failCount: Int
    let averageDuration: Double
    let fastestBuild: Double
    let slowestBuild: Double
    let totalBuildTime: Double
    let lastBuildDate: Date?

    var successRate: Double {
        guard totalBuilds > 0 else { return 0 }
        return Double(successCount) / Double(totalBuilds) * 100
    }

    var formattedAvgDuration: String {
        formatDuration(averageDuration)
    }

    var formattedFastest: String {
        formatDuration(fastestBuild)
    }

    var formattedSlowest: String {
        formatDuration(slowestBuild)
    }

    var formattedTotalTime: String {
        let hours = Int(totalBuildTime) / 3600
        let minutes = (Int(totalBuildTime) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}

/// Persists and queries build statistics
class BuildStatsStore: ObservableObject {
    @Published var records: [BuildRecord] = []

    private let storageKey = "com.ketok.buildstats"
    private let maxRecords = 500

    init() {
        loadRecords()
    }

    func loadRecords() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([BuildRecord].self, from: data) {
            records = saved
        }
    }

    func saveRecords() {
        // Keep only the most recent records
        let trimmed = Array(records.suffix(maxRecords))
        if let data = try? JSONEncoder().encode(trimmed) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    /// Record a completed build
    func recordBuild(from build: BuildStatus) {
        let success = build.state.isSuccess
        var errorMsg: String? = nil
        if case .failed(let err) = build.state {
            errorMsg = err
        }

        let record = BuildRecord(
            projectId: build.project.id,
            projectName: build.project.name,
            variant: build.variant,
            buildType: build.buildType,
            startTime: build.startTime,
            endTime: build.endTime ?? Date(),
            durationSeconds: build.elapsed,
            success: success,
            apkSizeBytes: build.apkSizeBytes,
            errorMessage: errorMsg
        )
        records.append(record)
        saveRecords()
    }

    /// Get aggregate stats for all projects
    func overallStats() -> ProjectBuildStats {
        return computeStats(from: records, name: "All Projects")
    }

    /// Get aggregate stats for a specific project
    func statsForProject(_ projectId: UUID) -> ProjectBuildStats? {
        let filtered = records.filter { $0.projectId == projectId }
        guard !filtered.isEmpty else { return nil }
        return computeStats(from: filtered, name: filtered.first?.projectName ?? "Unknown")
    }

    /// Get APK size trend data for a project (successful builds only)
    func apkSizeTrend(for projectId: UUID? = nil) -> [(date: Date, sizeBytes: Int64, projectName: String)] {
        let filtered: [BuildRecord]
        if let pid = projectId {
            filtered = records.filter { $0.projectId == pid && $0.success && $0.apkSizeBytes != nil }
        } else {
            filtered = records.filter { $0.success && $0.apkSizeBytes != nil }
        }
        return filtered.map { (date: $0.startTime, sizeBytes: $0.apkSizeBytes!, projectName: $0.projectName) }
    }

    /// Get build duration trend
    func durationTrend(for projectId: UUID? = nil) -> [(date: Date, duration: Double, success: Bool)] {
        let filtered: [BuildRecord]
        if let pid = projectId {
            filtered = records.filter { $0.projectId == pid }
        } else {
            filtered = records
        }
        return filtered.map { (date: $0.startTime, duration: $0.durationSeconds, success: $0.success) }
    }

    /// Clear all records
    func clearAll() {
        records.removeAll()
        saveRecords()
    }

    private func computeStats(from records: [BuildRecord], name: String) -> ProjectBuildStats {
        let successRecords = records.filter { $0.success }
        let durations = successRecords.map { $0.durationSeconds }

        return ProjectBuildStats(
            projectName: name,
            totalBuilds: records.count,
            successCount: successRecords.count,
            failCount: records.count - successRecords.count,
            averageDuration: durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count),
            fastestBuild: durations.min() ?? 0,
            slowestBuild: durations.max() ?? 0,
            totalBuildTime: durations.reduce(0, +),
            lastBuildDate: records.last?.startTime
        )
    }

    // MARK: - Failure Pattern Recognition

    /// A recurring error pattern detected from build history
    struct FailurePattern: Identifiable {
        let id = UUID()
        let category: String          // e.g. "Dependency conflict", "OOM", "Code generation"
        let signature: String          // Normalized error signature
        let occurrences: Int
        let lastSeen: Date
        let affectedProjects: Set<String>
        let sampleMessages: [String]   // Up to 3 representative messages

        var isRecurring: Bool { occurrences >= 2 }
        var suggestion: String? {
            switch category {
            case "OOM":
                return "Increase Gradle heap size in gradle.properties: org.gradle.jvmargs=-Xmx4g"
            case "Dependency conflict":
                return "Run 'gradle dependencies' to identify conflicting versions, then add resolution strategy"
            case "Code generation":
                return "Clean build_runner cache with 'dart run build_runner clean', then rebuild"
            case "Kotlin compilation":
                return "Check Kotlin version compatibility with AGP and dependencies"
            case "Resource merge":
                return "Check for duplicate resources across modules/flavors. Run 'gradle mergeDebugResources --info'"
            case "Signing":
                return "Verify keystore path and credentials in signing configs"
            case "SDK missing":
                return "Install the required SDK version via Android Studio SDK Manager"
            case "Network":
                return "Check internet connection or configure Gradle proxy in gradle.properties"
            default:
                return nil
            }
        }
    }

    /// Known error patterns for classification
    private static let errorPatterns: [(pattern: String, category: String)] = [
        // OOM / Memory
        ("OutOfMemoryError", "OOM"),
        ("GC overhead limit exceeded", "OOM"),
        ("Java heap space", "OOM"),
        ("Metaspace", "OOM"),
        ("Gradle daemon disappeared", "OOM"),

        // Dependency / Version conflicts
        ("version solving failed", "Dependency conflict"),
        ("Could not resolve", "Dependency conflict"),
        ("Conflict between", "Dependency conflict"),
        ("duplicate class", "Dependency conflict"),
        ("incompatible version", "Dependency conflict"),

        // Code generation (build_runner, envied, etc.)
        ("build_runner", "Code generation"),
        ("GeneratorBuilder", "Code generation"),
        ("part of.*not found", "Code generation"),
        (".g.dart", "Code generation"),

        // Kotlin
        ("Unresolved reference", "Kotlin compilation"),
        ("Type mismatch", "Kotlin compilation"),
        ("e: ", "Kotlin compilation"),

        // Resource merging
        ("Resource merge", "Resource merge"),
        ("Duplicate resources", "Resource merge"),
        ("AAPT", "Resource merge"),

        // Signing
        ("keystore", "Signing"),
        ("jarsigner", "Signing"),
        ("SigningConfig", "Signing"),

        // SDK
        ("SDK location not found", "SDK missing"),
        ("failed to find target", "SDK missing"),
        ("compileSdkVersion", "SDK missing"),

        // Network
        ("Could not GET", "Network"),
        ("Could not HEAD", "Network"),
        ("Connection timed out", "Network"),
        ("UnknownHostException", "Network"),
    ]

    /// Analyze failure history and detect recurring patterns
    func detectFailurePatterns(forProject projectId: UUID? = nil, lookbackDays: Int = 30) -> [FailurePattern] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: Date()) ?? Date()

        let failures: [BuildRecord]
        if let pid = projectId {
            failures = records.filter { !$0.success && $0.startTime >= cutoff && $0.projectId == pid }
        } else {
            failures = records.filter { !$0.success && $0.startTime >= cutoff }
        }

        guard !failures.isEmpty else { return [] }

        // Classify each failure
        var categoryBuckets: [String: [(record: BuildRecord, message: String)]] = [:]

        for record in failures {
            guard let msg = record.errorMessage, !msg.isEmpty else { continue }
            let category = classifyError(msg)
            categoryBuckets[category, default: []].append((record, msg))
        }

        // Build patterns from buckets
        var patterns: [FailurePattern] = []

        for (category, entries) in categoryBuckets {
            let projectNames = Set(entries.map { $0.record.projectName })
            let sortedByDate = entries.sorted { $0.record.startTime > $1.record.startTime }
            let samples = Array(sortedByDate.prefix(3).map { $0.message })

            // Normalize the error to a stable signature
            let signature = normalizeErrorSignature(entries.first?.message ?? "")

            patterns.append(FailurePattern(
                category: category,
                signature: signature,
                occurrences: entries.count,
                lastSeen: sortedByDate.first?.record.startTime ?? Date(),
                affectedProjects: projectNames,
                sampleMessages: samples
            ))
        }

        return patterns.sorted { $0.occurrences > $1.occurrences }
    }

    /// Classify an error message into a category
    private func classifyError(_ message: String) -> String {
        let lower = message.lowercased()
        for (pattern, category) in Self.errorPatterns {
            if lower.contains(pattern.lowercased()) {
                return category
            }
        }
        return "Other"
    }

    /// Normalize error to a stable signature (strip line numbers, paths, versions)
    private func normalizeErrorSignature(_ message: String) -> String {
        var sig = message
        // Strip file paths
        sig = sig.replacingOccurrences(of: #"/[^\s:]+/"#, with: ".../", options: .regularExpression)
        // Strip line numbers
        sig = sig.replacingOccurrences(of: #":\d+:\d+"#, with: ":N:N", options: .regularExpression)
        // Strip version numbers
        sig = sig.replacingOccurrences(of: #"\d+\.\d+\.\d+"#, with: "X.Y.Z", options: .regularExpression)
        // Take first 200 chars
        return String(sig.prefix(200))
    }

    /// Get build health score (0-100) based on recent history
    func buildHealthScore(forProject projectId: UUID? = nil) -> BuildHealthScore {
        let recentRecords: [BuildRecord]
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()

        if let pid = projectId {
            recentRecords = records.filter { $0.projectId == pid && $0.startTime >= cutoff }
        } else {
            recentRecords = records.filter { $0.startTime >= cutoff }
        }

        guard !recentRecords.isEmpty else {
            return BuildHealthScore(score: -1, label: "No data", trend: .stable, factors: [])
        }

        var factors: [(name: String, score: Int, weight: Double)] = []

        // Factor 1: Success rate (40% weight)
        let successes = recentRecords.filter { $0.success }.count
        let successRate = Double(successes) / Double(recentRecords.count)
        let successScore = Int(successRate * 100)
        factors.append(("Success rate", successScore, 0.4))

        // Factor 2: Build time stability (20% weight)
        let successDurations = recentRecords.filter { $0.success }.map { $0.durationSeconds }
        let timeStabilityScore: Int
        if successDurations.count >= 2 {
            let avg = successDurations.reduce(0, +) / Double(successDurations.count)
            let variance = successDurations.map { ($0 - avg) * ($0 - avg) }.reduce(0, +) / Double(successDurations.count)
            let cv = avg > 0 ? sqrt(variance) / avg : 0  // Coefficient of variation
            timeStabilityScore = max(0, Int((1.0 - min(cv, 1.0)) * 100))
        } else {
            timeStabilityScore = 50
        }
        factors.append(("Build time stability", timeStabilityScore, 0.2))

        // Factor 3: No recurring failures (25% weight)
        let patterns = detectFailurePatterns(forProject: projectId, lookbackDays: 14)
        let recurringCount = patterns.filter { $0.isRecurring }.count
        let patternScore = max(0, 100 - recurringCount * 30)
        factors.append(("No recurring failures", patternScore, 0.25))

        // Factor 4: Recent trend (15% weight)
        let last5 = recentRecords.suffix(5)
        let last5Success = last5.filter { $0.success }.count
        let trendScore = Int(Double(last5Success) / Double(max(last5.count, 1)) * 100)
        factors.append(("Recent trend", trendScore, 0.15))

        // Weighted total
        let totalScore = Int(factors.reduce(0.0) { $0 + Double($1.score) * $1.weight })

        // Determine trend from last 5 vs previous 5
        let trend: BuildHealthScore.Trend
        if recentRecords.count >= 10 {
            let prev5 = recentRecords.dropLast(5).suffix(5)
            let prev5Rate = Double(prev5.filter { $0.success }.count) / Double(prev5.count)
            let curr5Rate = Double(last5Success) / Double(max(last5.count, 1))
            if curr5Rate > prev5Rate + 0.1 { trend = .improving }
            else if curr5Rate < prev5Rate - 0.1 { trend = .declining }
            else { trend = .stable }
        } else {
            trend = .stable
        }

        let label: String
        switch totalScore {
        case 90...100: label = "Excellent"
        case 75..<90: label = "Good"
        case 50..<75: label = "Fair"
        case 25..<50: label = "Poor"
        default: label = "Critical"
        }

        return BuildHealthScore(
            score: totalScore,
            label: label,
            trend: trend,
            factors: factors.map { BuildHealthScore.Factor(name: $0.name, score: $0.score, weight: $0.weight) }
        )
    }

    /// Export records as JSON data
    func exportData() -> Data? {
        return try? JSONEncoder().encode(records)
    }

    /// Import records from JSON data
    func importData(_ data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode([BuildRecord].self, from: data) else { return false }
        records.append(contentsOf: imported)
        saveRecords()
        return true
    }
}

// MARK: - Build Health Score

struct BuildHealthScore {
    let score: Int           // 0-100 or -1 for no data
    let label: String        // "Excellent", "Good", "Fair", "Poor", "Critical"
    let trend: Trend
    let factors: [Factor]

    enum Trend: String {
        case improving = "Improving"
        case stable = "Stable"
        case declining = "Declining"

        var icon: String {
            switch self {
            case .improving: return "arrow.up.right"
            case .stable: return "arrow.right"
            case .declining: return "arrow.down.right"
            }
        }
    }

    struct Factor {
        let name: String
        let score: Int
        let weight: Double
    }
}

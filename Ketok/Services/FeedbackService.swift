import SwiftUI
import Foundation

// MARK: - Models

enum FeedbackType: String, CaseIterable, Identifiable {
    case bugReport = "Bug Report"
    case featureRequest = "Feature Request"
    case generalFeedback = "General Feedback"
    case performance = "Performance Issue"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .bugReport: return "ladybug.fill"
        case .featureRequest: return "lightbulb.fill"
        case .generalFeedback: return "bubble.left.fill"
        case .performance: return "gauge.with.dots.needle.33percent"
        }
    }

    var color: Color {
        switch self {
        case .bugReport: return Brand.error
        case .featureRequest: return Brand.accent
        case .generalFeedback: return Brand.primary
        case .performance: return Brand.warning
        }
    }

    var emailSubjectTag: String {
        switch self {
        case .bugReport: return "[Bug]"
        case .featureRequest: return "[Feature]"
        case .generalFeedback: return "[Feedback]"
        case .performance: return "[Performance]"
        }
    }
}

enum FeedbackRating: Int, CaseIterable, Identifiable {
    case terrible = 1
    case bad = 2
    case okay = 3
    case good = 4
    case great = 5

    var id: Int { rawValue }

    var emoji: String {
        switch self {
        case .terrible: return "😞"
        case .bad: return "😕"
        case .okay: return "😐"
        case .good: return "🙂"
        case .great: return "🤩"
        }
    }

    var label: String {
        switch self {
        case .terrible: return "Terrible"
        case .bad: return "Bad"
        case .okay: return "Okay"
        case .good: return "Good"
        case .great: return "Great"
        }
    }
}

struct FeedbackEntry: Identifiable, Codable {
    let id: UUID
    let type: String
    let rating: Int
    let message: String
    let includeSystemInfo: Bool
    let systemInfo: String?
    let timestamp: Date
    let appVersion: String
    let submitted: Bool

    init(
        type: FeedbackType,
        rating: FeedbackRating,
        message: String,
        includeSystemInfo: Bool,
        systemInfo: String?,
        submitted: Bool
    ) {
        self.id = UUID()
        self.type = type.rawValue
        self.rating = rating.rawValue
        self.message = message
        self.includeSystemInfo = includeSystemInfo
        self.systemInfo = systemInfo
        self.timestamp = Date()
        self.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.submitted = submitted
    }
}

// MARK: - Service

class FeedbackService: ObservableObject {
    static let feedbackURL = "https://www.ketok.id/"
    private static let storageKey = "com.ketok.feedbackHistory"
    private static let maxHistory = 30

    @Published var history: [FeedbackEntry] = []
    @Published var isSending = false
    @Published var lastSendResult: SendResult?

    enum SendResult {
        case success
        case failed(String)
    }

    init() {
        loadHistory()
    }

    // MARK: - System Info Collection

    func collectSystemInfo() -> String {
        var info: [String] = []

        // macOS version
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        info.append("macOS \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")

        // App version
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        info.append("Ketok v\(appVersion) (\(buildNumber))")

        // Machine info
        info.append("Host: \(ProcessInfo.processInfo.hostName)")
        info.append("CPUs: \(ProcessInfo.processInfo.processorCount)")
        info.append("RAM: \(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB")

        // Java version
        if let javaVersion = runCommand("/usr/bin/env", arguments: ["java", "-version"]) {
            let firstLine = javaVersion.components(separatedBy: "\n").first ?? javaVersion
            info.append("Java: \(firstLine)")
        }

        // Gradle version (from wrapper if available)
        info.append("Locale: \(Locale.current.identifier)")

        // Android SDK
        let sdkPaths = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"],
            ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"],
            "\(NSHomeDirectory())/Library/Android/sdk"
        ].compactMap { $0 }

        if let sdkPath = sdkPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            info.append("Android SDK: \(sdkPath)")
        }

        return info.joined(separator: "\n")
    }

    private func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    // MARK: - Submit Feedback

    func submitViaEmail(
        type: FeedbackType,
        rating: FeedbackRating,
        message: String,
        includeSystemInfo: Bool
    ) {
        isSending = true

        let systemInfo = includeSystemInfo ? collectSystemInfo() : nil

        // Save to history
        let entry = FeedbackEntry(
            type: type,
            rating: rating,
            message: message,
            includeSystemInfo: includeSystemInfo,
            systemInfo: systemInfo,
            submitted: true
        )
        history.insert(entry, at: 0)
        if history.count > Self.maxHistory {
            history = Array(history.prefix(Self.maxHistory))
        }
        saveHistory()

        if let url = URL(string: Self.feedbackURL) {
            NSWorkspace.shared.open(url)
            lastSendResult = .success
        } else {
            lastSendResult = .failed("Could not open feedback page")
        }

        isSending = false
    }

    // MARK: - Save as Local JSON

    func saveLocally(
        type: FeedbackType,
        rating: FeedbackRating,
        message: String,
        includeSystemInfo: Bool
    ) -> URL? {
        let systemInfo = includeSystemInfo ? collectSystemInfo() : nil

        let entry = FeedbackEntry(
            type: type,
            rating: rating,
            message: message,
            includeSystemInfo: includeSystemInfo,
            systemInfo: systemInfo,
            submitted: false
        )
        history.insert(entry, at: 0)
        if history.count > Self.maxHistory {
            history = Array(history.prefix(Self.maxHistory))
        }
        saveHistory()

        // Export to Desktop as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(entry) else { return nil }

        let desktop = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let fileName = "Ketok-Feedback-\(entry.id.uuidString.prefix(8)).json"
        let fileURL = desktop.appendingPathComponent(fileName)

        try? data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([FeedbackEntry].self, from: data) else {
            return
        }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}

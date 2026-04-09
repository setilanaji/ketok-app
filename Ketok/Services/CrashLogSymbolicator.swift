import Foundation
import Combine

/// A symbolicated crash report with metadata
struct SymbolicatedCrash: Identifiable {
    let id = UUID()
    let timestamp: Date
    let originalTrace: String
    let symbolicatedTrace: String
    let mappingFile: String      // Name of the mapping file used
    let resolvedCount: Int       // How many lines were resolved
    let totalFrames: Int         // Total stack frames found
    let exceptionType: String?   // Parsed exception class if found
    let exceptionMessage: String? // Parsed exception message if found

    var resolutionRate: Double {
        totalFrames > 0 ? Double(resolvedCount) / Double(totalFrames) : 0
    }

    var resolutionFormatted: String {
        "\(resolvedCount)/\(totalFrames) frames resolved"
    }
}

/// Service for crash log symbolication — uses MappingViewerService under the hood
class CrashLogSymbolicator: ObservableObject {
    @Published var history: [SymbolicatedCrash] = []
    @Published var currentResult: SymbolicatedCrash?
    @Published var isProcessing = false
    @Published var recentMappingPaths: [String] = []

    private let maxHistory = 15

    init() {
        // Load recent mapping paths from UserDefaults
        recentMappingPaths = UserDefaults.standard.stringArray(forKey: "com.ketok.recentMappings") ?? []
    }

    // MARK: - Symbolicate

    /// Symbolicate a crash trace using the provided MappingViewerService
    func symbolicate(
        trace: String,
        using mappingService: MappingViewerService
    ) -> SymbolicatedCrash {
        guard !mappingService.entries.isEmpty else {
            return SymbolicatedCrash(
                timestamp: Date(),
                originalTrace: trace,
                symbolicatedTrace: "No mapping file loaded. Load a mapping.txt first.",
                mappingFile: "none",
                resolvedCount: 0,
                totalFrames: 0,
                exceptionType: nil,
                exceptionMessage: nil
            )
        }

        // Parse exception info from the top of the trace
        let (exceptionType, exceptionMessage) = parseException(from: trace)

        // Use the mapping service's deobfuscation
        let result = mappingService.deobfuscateStackTrace(trace)

        // Count how many frames were actually resolved (changed)
        var totalFrames = 0
        var resolvedCount = 0
        for (idx, original) in result.originalLines.enumerated() {
            if isStackFrame(original) {
                totalFrames += 1
                if idx < result.deobfuscatedLines.count && result.deobfuscatedLines[idx] != original {
                    resolvedCount += 1
                }
            }
        }

        // Build symbolicated output with exception info highlighted
        var symbolicatedOutput = ""

        // Add exception header if found
        if let type = exceptionType {
            let resolvedType = mappingService.resolveClassName(type)
            symbolicatedOutput += "Exception: \(resolvedType)"
            if let msg = exceptionMessage {
                symbolicatedOutput += ": \(msg)"
            }
            symbolicatedOutput += "\n\n"
        }

        symbolicatedOutput += result.deobfuscatedLines.joined(separator: "\n")

        let mappingName = (mappingService.loadedFilePath as NSString?)?.lastPathComponent ?? "unknown"

        let crash = SymbolicatedCrash(
            timestamp: Date(),
            originalTrace: trace,
            symbolicatedTrace: symbolicatedOutput,
            mappingFile: mappingName,
            resolvedCount: resolvedCount,
            totalFrames: totalFrames,
            exceptionType: exceptionType != nil ? mappingService.resolveClassName(exceptionType!) : nil,
            exceptionMessage: exceptionMessage
        )

        DispatchQueue.main.async {
            self.currentResult = crash
            self.history.insert(crash, at: 0)
            if self.history.count > self.maxHistory {
                self.history = Array(self.history.prefix(self.maxHistory))
            }
        }

        return crash
    }

    /// Symbolicate from a file path (reads the trace from a file)
    func symbolicateFromFile(
        path: String,
        using mappingService: MappingViewerService,
        completion: @escaping (SymbolicatedCrash?) -> Void
    ) {
        isProcessing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                DispatchQueue.main.async {
                    self?.isProcessing = false
                    completion(nil)
                }
                return
            }

            let result = self?.symbolicate(trace: content, using: mappingService)
            DispatchQueue.main.async {
                self?.isProcessing = false
                completion(result)
            }
        }
    }

    /// Record a mapping file path as recently used
    func recordMappingPath(_ path: String) {
        recentMappingPaths.removeAll { $0 == path }
        recentMappingPaths.insert(path, at: 0)
        if recentMappingPaths.count > 5 {
            recentMappingPaths = Array(recentMappingPaths.prefix(5))
        }
        UserDefaults.standard.set(recentMappingPaths, forKey: "com.ketok.recentMappings")
    }

    /// Auto-discover mapping files near a project path
    func findMappingFiles(projectPath: String) -> [String] {
        var results: [String] = []
        let fm = FileManager.default

        // Common locations for mapping files
        let searchPaths = [
            "\(projectPath)/app/build/outputs/mapping",
            "\(projectPath)/app/build/outputs/mapping/release",
            "\(projectPath)/app/build/outputs/mapping/debug",
        ]

        for searchPath in searchPaths {
            if let enumerator = fm.enumerator(atPath: searchPath) {
                while let file = enumerator.nextObject() as? String {
                    if file.hasSuffix("mapping.txt") || file.hasSuffix("mapping.pro") {
                        results.append("\(searchPath)/\(file)")
                    }
                }
            }
        }

        // Also check build outputs root
        let buildOutputs = "\(projectPath)/app/build/outputs"
        if fm.fileExists(atPath: buildOutputs) {
            if let enumerator = fm.enumerator(atPath: buildOutputs) {
                while let file = enumerator.nextObject() as? String {
                    if file.hasSuffix("mapping.txt") && !results.contains("\(buildOutputs)/\(file)") {
                        results.append("\(buildOutputs)/\(file)")
                    }
                }
            }
        }

        return results
    }

    // MARK: - Helpers

    /// Check if a line is a stack frame (starts with "at " or similar patterns)
    private func isStackFrame(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("at ") ||
               trimmed.hasPrefix("Caused by:") ||
               (trimmed.contains(".") && trimmed.contains("(") && trimmed.contains(")"))
    }

    /// Parse exception type and message from the first lines of a stack trace
    private func parseException(from trace: String) -> (String?, String?) {
        let lines = trace.components(separatedBy: "\n")

        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Pattern: "java.lang.NullPointerException: message here"
            // or "a.b.c: message" (obfuscated)
            if let colonIdx = trimmed.firstIndex(of: ":"),
               !trimmed.hasPrefix("at "),
               trimmed[..<colonIdx].contains(".") {
                let type = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let message = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

                // Basic validation — class names have dots and no spaces before the colon
                if !type.contains(" ") && type.contains(".") {
                    return (type, message.isEmpty ? nil : message)
                }
            }

            // Pattern without message: "java.lang.NullPointerException"
            if !trimmed.hasPrefix("at ") && !trimmed.isEmpty &&
               trimmed.contains(".") && !trimmed.contains(" ") &&
               !trimmed.contains("(") {
                return (trimmed, nil)
            }
        }

        return (nil, nil)
    }

    /// Clear all history
    func clearHistory() {
        history = []
        currentResult = nil
    }
}

import Foundation

/// A single line entry from a ProGuard/R8 mapping file
struct MappingEntry: Identifiable, Hashable {
    let id = UUID()
    let originalName: String
    let obfuscatedName: String
    let entryType: EntryType
    let members: [MappingMember]

    enum EntryType: String, Hashable {
        case classEntry = "class"
        case field = "field"
        case method = "method"
    }
}

/// A member (field or method) within a class mapping
struct MappingMember: Identifiable, Hashable {
    let id = UUID()
    let originalSignature: String
    let obfuscatedName: String
    let memberType: MemberType

    enum MemberType: String, Hashable {
        case field = "field"
        case method = "method"
    }
}

/// Result of deobfuscating a stack trace
struct DeobfuscatedTrace: Identifiable {
    let id = UUID()
    let originalLines: [String]
    let deobfuscatedLines: [String]
    let timestamp: Date = Date()
}

/// Service for parsing and searching ProGuard/R8 mapping files
class MappingViewerService: ObservableObject {

    @Published var entries: [MappingEntry] = []
    @Published var isLoading = false
    @Published var loadedFilePath: String?
    @Published var error: String?
    @Published var searchResults: [MappingEntry] = []

    /// Total number of class mappings
    var classCount: Int {
        entries.count
    }

    /// Total number of member mappings
    var memberCount: Int {
        entries.reduce(0) { $0 + $1.members.count }
    }

    /// File size of the loaded mapping
    var fileSizeFormatted: String? {
        guard let path = loadedFilePath else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        guard let bytes = attrs?[.size] as? Int64 else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Lookup caches

    /// Obfuscated class name → MappingEntry
    private var obfuscatedClassMap: [String: MappingEntry] = [:]
    /// Original class name → MappingEntry
    private var originalClassMap: [String: MappingEntry] = [:]

    // MARK: - Load & Parse

    /// Load and parse a mapping.txt file
    func loadMapping(from path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            error = "Mapping file not found at: \(path)"
            return
        }

        isLoading = true
        error = nil
        loadedFilePath = path

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Self.parseMappingFile(at: path)

            DispatchQueue.main.async {
                switch result {
                case .success(let parsedEntries):
                    self?.entries = parsedEntries
                    self?.buildCaches(from: parsedEntries)
                    self?.error = nil
                case .failure(let err):
                    self?.entries = []
                    self?.error = err.localizedDescription
                }
                self?.isLoading = false
            }
        }
    }

    /// Unload the current mapping
    func unload() {
        entries = []
        searchResults = []
        loadedFilePath = nil
        error = nil
        obfuscatedClassMap = [:]
        originalClassMap = [:]
    }

    // MARK: - Search

    /// Search entries by original or obfuscated name
    func search(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            return
        }

        let lowered = query.lowercased()
        searchResults = entries.filter { entry in
            entry.originalName.lowercased().contains(lowered) ||
            entry.obfuscatedName.lowercased().contains(lowered) ||
            entry.members.contains { member in
                member.originalSignature.lowercased().contains(lowered) ||
                member.obfuscatedName.lowercased().contains(lowered)
            }
        }
    }

    // MARK: - Deobfuscation

    /// Deobfuscate a stack trace using the loaded mapping
    func deobfuscateStackTrace(_ stackTrace: String) -> DeobfuscatedTrace {
        let lines = stackTrace.components(separatedBy: "\n")
        var deobfuscated: [String] = []

        for line in lines {
            deobfuscated.append(deobfuscateLine(line))
        }

        return DeobfuscatedTrace(
            originalLines: lines,
            deobfuscatedLines: deobfuscated
        )
    }

    /// Deobfuscate a single line from a stack trace
    private func deobfuscateLine(_ line: String) -> String {
        // Match patterns like: at a.b.c.d(SourceFile:123) or a.b.c.d
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Pattern: at package.class.method(file:line)
        let atPattern = "at\\s+([\\w.$]+)\\.([\\w$]+)\\(([^)]+)\\)"
        if let regex = try? NSRegularExpression(pattern: atPattern),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {

            let classNameRange = Range(match.range(at: 1), in: trimmed)!
            let methodNameRange = Range(match.range(at: 2), in: trimmed)!
            let locationRange = Range(match.range(at: 3), in: trimmed)!

            let className = String(trimmed[classNameRange])
            let methodName = String(trimmed[methodNameRange])
            let location = String(trimmed[locationRange])

            let resolvedClass = resolveClassName(className)
            let resolvedMethod = resolveMethodName(className: className, obfuscatedMethod: methodName)

            return "    at \(resolvedClass).\(resolvedMethod)(\(location))"
        }

        // Pattern: bare class reference like a.b.c
        let barePattern = "^([a-z]\\.[a-z]\\.[a-z]+\\.?[a-z]*)$"
        if let regex = try? NSRegularExpression(pattern: barePattern),
           regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
            return resolveClassName(trimmed)
        }

        return line
    }

    /// Resolve an obfuscated class name to its original name
    func resolveClassName(_ obfuscated: String) -> String {
        if let entry = obfuscatedClassMap[obfuscated] {
            return entry.originalName
        }
        return obfuscated
    }

    /// Resolve an obfuscated method name within a class
    func resolveMethodName(className: String, obfuscatedMethod: String) -> String {
        if let entry = obfuscatedClassMap[className] {
            if let member = entry.members.first(where: { $0.obfuscatedName == obfuscatedMethod && $0.memberType == .method }) {
                // Extract just the method name from the full signature
                let sig = member.originalSignature
                if let parenIdx = sig.firstIndex(of: "("),
                   let spaceIdx = sig[..<parenIdx].lastIndex(of: " ") {
                    let nameStart = sig.index(after: spaceIdx)
                    return String(sig[nameStart..<parenIdx]) + String(sig[parenIdx...])
                }
                return sig
            }
        }
        return obfuscatedMethod
    }

    // MARK: - Internal

    private func buildCaches(from entries: [MappingEntry]) {
        obfuscatedClassMap = [:]
        originalClassMap = [:]
        for entry in entries {
            obfuscatedClassMap[entry.obfuscatedName] = entry
            originalClassMap[entry.originalName] = entry
        }
    }

    // MARK: - Parser

    /// Parse a ProGuard/R8 mapping.txt file
    static func parseMappingFile(at path: String) -> Result<[MappingEntry], Error> {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")

            var entries: [MappingEntry] = []
            var currentOriginal: String?
            var currentObfuscated: String?
            var currentMembers: [MappingMember] = []

            for line in lines {
                // Skip comments and empty lines
                if line.hasPrefix("#") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }

                if !line.hasPrefix(" ") && !line.hasPrefix("\t") && line.contains(" -> ") && line.hasSuffix(":") {
                    // This is a class mapping line: "original.class.Name -> obfuscated.Name:"
                    // Save previous entry
                    if let orig = currentOriginal, let obf = currentObfuscated {
                        entries.append(MappingEntry(
                            originalName: orig,
                            obfuscatedName: obf,
                            entryType: .classEntry,
                            members: currentMembers
                        ))
                    }

                    // Parse new class entry
                    let parts = line.dropLast().components(separatedBy: " -> ")
                    if parts.count == 2 {
                        currentOriginal = parts[0].trimmingCharacters(in: .whitespaces)
                        currentObfuscated = parts[1].trimmingCharacters(in: .whitespaces)
                        currentMembers = []
                    }
                } else if line.hasPrefix("    ") || line.hasPrefix("\t") {
                    // This is a member mapping line
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains(" -> ") {
                        let memberParts = trimmed.components(separatedBy: " -> ")
                        if memberParts.count == 2 {
                            let originalSig = memberParts[0].trimmingCharacters(in: .whitespaces)
                            let obfName = memberParts[1].trimmingCharacters(in: .whitespaces)

                            // Determine if method (has parentheses) or field
                            let isMethod = originalSig.contains("(")
                            // Strip line number info: "1:2:type method(args):3:4" → "type method(args)"
                            let cleanSig = Self.stripLineNumbers(from: originalSig)

                            currentMembers.append(MappingMember(
                                originalSignature: cleanSig,
                                obfuscatedName: obfName,
                                memberType: isMethod ? .method : .field
                            ))
                        }
                    }
                }
            }

            // Don't forget the last entry
            if let orig = currentOriginal, let obf = currentObfuscated {
                entries.append(MappingEntry(
                    originalName: orig,
                    obfuscatedName: obf,
                    entryType: .classEntry,
                    members: currentMembers
                ))
            }

            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    /// Strip line number ranges from member signatures
    /// Input: "1:5:void onCreate(android.os.Bundle):1:5"
    /// Output: "void onCreate(android.os.Bundle)"
    static func stripLineNumbers(from signature: String) -> String {
        // Pattern: optional "startLine:endLine:" prefix and ":originalStartLine:originalEndLine" suffix
        var result = signature

        // Remove leading line numbers like "1:5:"
        if let regex = try? NSRegularExpression(pattern: "^\\d+:\\d+:"),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            let range = Range(match.range, in: result)!
            result = String(result[range.upperBound...])
        }

        // Remove trailing line numbers like ":1:5"
        if let regex = try? NSRegularExpression(pattern: ":\\d+:\\d+$"),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)) {
            let range = Range(match.range, in: result)!
            result = String(result[..<range.lowerBound])
        }

        return result
    }
}

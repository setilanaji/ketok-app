import Foundation

/// Represents a single alias entry in a keystore
struct KeystoreAlias: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let creationDate: String
    let expiryDate: String
    let algorithm: String
    let fingerprint: String  // SHA-256

    var isExpired: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: expiryDate) {
            return date < Date()
        }
        return false
    }

    var daysUntilExpiry: Int? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: expiryDate) {
            return Calendar.current.dateComponents([.day], from: Date(), to: date).day
        }
        return nil
    }
}

/// Represents a keystore file with its metadata
struct KeystoreInfo: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let type: String           // JKS, PKCS12, etc.
    let aliases: [KeystoreAlias]

    var fileName: String {
        (path as NSString).lastPathComponent
    }

    var hasExpiredAliases: Bool {
        aliases.contains { $0.isExpired }
    }

    var nearestExpiry: Int? {
        aliases.compactMap { $0.daysUntilExpiry }.min()
    }
}

/// Service for managing and inspecting Android keystores
class KeystoreManagerService: ObservableObject {
    static let shared = KeystoreManagerService()

    @Published var keystores: [KeystoreInfo] = []
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var createResult: String?

    private var keytoolPath: String? {
        // Find keytool from JAVA_HOME or common paths
        let paths = [
            ProcessInfo.processInfo.environment["JAVA_HOME"].map { "\($0)/bin/keytool" },
            "/usr/bin/keytool",
            "/usr/local/bin/keytool",
            // Android Studio bundled JDK
            "/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool",
            "/Applications/Android Studio.app/Contents/jre/Contents/Home/bin/keytool"
        ].compactMap { $0 }

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try which keytool
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["keytool"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path = path, !path.isEmpty {
                return path
            }
        }
        return nil
    }

    var isKeytoolAvailable: Bool {
        keytoolPath != nil
    }

    /// Inspect a keystore file and list its aliases
    func inspectKeystore(path: String, password: String) {
        guard let keytool = keytoolPath else {
            lastError = "keytool not found. Install JDK or set JAVA_HOME."
            return
        }

        isLoading = true
        lastError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = Self.runKeytool(keytool: keytool, args: [
                "-list", "-v",
                "-keystore", path,
                "-storepass", password
            ])

            let info = Self.parseKeystoreOutput(output: output, path: path)

            DispatchQueue.main.async {
                self?.isLoading = false
                if let info = info {
                    // Replace if same path exists, otherwise append
                    if let idx = self?.keystores.firstIndex(where: { $0.path == path }) {
                        self?.keystores[idx] = info
                    } else {
                        self?.keystores.append(info)
                    }
                } else {
                    self?.lastError = output.contains("password was incorrect")
                        ? "Incorrect keystore password"
                        : "Failed to read keystore: \(output.prefix(200))"
                }
            }
        }
    }

    /// Remove a keystore from the list (does not delete the file)
    func removeKeystore(_ id: UUID) {
        keystores.removeAll { $0.id == id }
    }

    /// Create a new debug keystore
    func createDebugKeystore(at path: String, password: String = "android", alias: String = "androiddebugkey", validity: Int = 10000) {
        guard let keytool = keytoolPath else {
            lastError = "keytool not found."
            return
        }

        isLoading = true
        lastError = nil
        createResult = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = Self.runKeytool(keytool: keytool, args: [
                "-genkeypair",
                "-alias", alias,
                "-keyalg", "RSA",
                "-keysize", "2048",
                "-validity", "\(validity)",
                "-keystore", path,
                "-storepass", password,
                "-keypass", password,
                "-dname", "CN=Android Debug,O=Android,C=US"
            ])

            DispatchQueue.main.async {
                self?.isLoading = false
                if FileManager.default.fileExists(atPath: path) {
                    self?.createResult = "Debug keystore created at \(path)"
                    // Auto-inspect the new keystore
                    self?.inspectKeystore(path: path, password: password)
                } else {
                    self?.lastError = "Failed to create keystore: \(output.prefix(200))"
                }
            }
        }
    }

    /// Get SHA-256 fingerprint for a specific alias
    func getFingerprint(keystorePath: String, password: String, alias: String, completion: @escaping (String?) -> Void) {
        guard let keytool = keytoolPath else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let output = Self.runKeytool(keytool: keytool, args: [
                "-list", "-v",
                "-keystore", keystorePath,
                "-alias", alias,
                "-storepass", password
            ])

            // Extract SHA-256 fingerprint
            let lines = output.components(separatedBy: "\n")
            var nextIsSHA256 = false
            for line in lines {
                if line.contains("SHA256:") || line.contains("SHA-256:") {
                    let fingerprint = line.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    completion(fingerprint)
                    return
                }
                if line.contains("Certificate fingerprints") { nextIsSHA256 = true }
                if nextIsSHA256 && line.trimmingCharacters(in: .whitespaces).starts(with: "SHA256") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count > 1 {
                        let fp = parts.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                        completion(fp)
                        return
                    }
                }
            }
            completion(nil)
        }
    }

    // MARK: - Private Helpers

    private static func runKeytool(keytool: String, args: [String]) -> String {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: keytool)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outData, encoding: .utf8) ?? ""
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        return output.isEmpty ? errOutput : output
    }

    private static func parseKeystoreOutput(output: String, path: String) -> KeystoreInfo? {
        guard !output.contains("password was incorrect"),
              !output.contains("Error:"),
              output.contains("Alias name:") || output.contains("alias name:") else {
            return nil
        }

        // Detect keystore type
        var keystoreType = "JKS"
        if output.contains("Keystore type: PKCS12") || output.contains("Keystore type: pkcs12") {
            keystoreType = "PKCS12"
        } else if output.contains("Keystore type: jks") || output.contains("Keystore type: JKS") {
            keystoreType = "JKS"
        }

        // Parse aliases
        var aliases: [KeystoreAlias] = []
        let blocks = output.components(separatedBy: "Alias name:")
        for block in blocks.dropFirst() {
            let lines = block.components(separatedBy: "\n")
            let aliasName = lines.first?.trimmingCharacters(in: .whitespaces) ?? "unknown"

            var creationDate = ""
            var algorithm = ""
            var fingerprint = ""
            var validFrom = ""
            var validUntil = ""

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.starts(with: "Creation date:") {
                    creationDate = trimmed.replacingOccurrences(of: "Creation date:", with: "").trimmingCharacters(in: .whitespaces)
                }
                if trimmed.contains("Key algorithm:") || trimmed.contains("Signature algorithm name:") {
                    algorithm = trimmed.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
                }
                if trimmed.contains("SHA256:") || trimmed.contains("SHA-256:") {
                    fingerprint = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                }
                if trimmed.starts(with: "Valid from:") {
                    // "Valid from: Mon Jan 01 00:00:00 UTC 2024 until: Sat Dec 31 23:59:59 UTC 2034"
                    if let untilRange = trimmed.range(of: "until:") {
                        let untilStr = trimmed[untilRange.upperBound...].trimmingCharacters(in: .whitespaces)
                        validUntil = Self.parseJavaDate(untilStr) ?? untilStr
                    }
                    if let fromRange = trimmed.range(of: "Valid from:") {
                        let rest = trimmed[fromRange.upperBound...]
                        if let untilRange = rest.range(of: "until:") {
                            let fromStr = rest[..<untilRange.lowerBound].trimmingCharacters(in: .whitespaces)
                            validFrom = Self.parseJavaDate(String(fromStr)) ?? String(fromStr)
                        }
                    }
                }
                if trimmed.starts(with: "Owner:") || trimmed.starts(with: "Issuer:") {
                    // We could extract these but keeping it simple
                }
            }

            aliases.append(KeystoreAlias(
                name: aliasName,
                creationDate: creationDate.isEmpty ? validFrom : creationDate,
                expiryDate: validUntil,
                algorithm: algorithm,
                fingerprint: fingerprint
            ))
        }

        guard !aliases.isEmpty else { return nil }

        return KeystoreInfo(
            path: path,
            type: keystoreType,
            aliases: aliases
        )
    }

    /// Parse Java's default date format into a simpler format
    private static func parseJavaDate(_ input: String) -> String? {
        // Input: "Mon Jan 01 00:00:00 UTC 2024" or similar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let formats = [
            "EEE MMM dd HH:mm:ss zzz yyyy",
            "EEE MMM dd HH:mm:ss z yyyy",
            "EEE MMM d HH:mm:ss zzz yyyy",
            "EEE MMM d HH:mm:ss z yyyy"
        ]

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: input) {
                let output = DateFormatter()
                output.dateFormat = "MMM d, yyyy"
                return output.string(from: date)
            }
        }
        return nil
    }
}

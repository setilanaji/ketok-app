import Foundation

/// Configuration for Firebase App Distribution
struct FirebaseConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var projectId: UUID  // Linked Android project
    var appId: String  // Firebase App ID (e.g., 1:1234567890:android:abc123)
    var serviceAccountPath: String?  // Path to service account JSON (optional)
    var groups: [String] = []  // Tester groups
    var testers: [String] = []  // Individual tester emails
    var releaseNotes: String?  // Default release notes template
    var autoUpload: Bool = false  // Auto-upload after successful build
}

/// Upload status tracking
enum FirebaseUploadState: Equatable {
    case idle
    case uploading(progress: String)
    case success(downloadURL: String?)
    case failed(error: String)

    var isUploading: Bool {
        if case .uploading = self { return true }
        return false
    }
}

/// Manages Firebase App Distribution uploads
class FirebaseDistributionService: ObservableObject {
    static let shared = FirebaseDistributionService()

    @Published var configs: [FirebaseConfig] = []
    @Published var uploadState: FirebaseUploadState = .idle
    @Published var uploadLog: String = ""

    /// Path to firebase CLI tool
    @Published var firebaseCLIPath: String {
        didSet { UserDefaults.standard.set(firebaseCLIPath, forKey: "com.ketok.firebaseCLIPath") }
    }

    private let storageKey = "com.ketok.firebaseConfigs"
    private var currentProcess: Process?

    private init() {
        firebaseCLIPath = UserDefaults.standard.string(forKey: "com.ketok.firebaseCLIPath") ?? ""
        load()

        // Auto-detect firebase CLI if not set
        if firebaseCLIPath.isEmpty {
            detectFirebaseCLI()
        }
    }

    // MARK: - Config Management

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([FirebaseConfig].self, from: data) {
            configs = saved
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addConfig(_ config: FirebaseConfig) {
        configs.append(config)
        save()
    }

    func updateConfig(_ config: FirebaseConfig) {
        if let index = configs.firstIndex(where: { $0.id == config.id }) {
            configs[index] = config
            save()
        }
    }

    func removeConfig(_ config: FirebaseConfig) {
        configs.removeAll { $0.id == config.id }
        save()
    }

    func configForProject(_ projectId: UUID) -> FirebaseConfig? {
        configs.first { $0.projectId == projectId }
    }

    // MARK: - Firebase CLI Detection

    private func detectFirebaseCLI() {
        let paths = [
            "/usr/local/bin/firebase",
            "/opt/homebrew/bin/firebase",
            "\(NSHomeDirectory())/.nvm/versions/node/*/bin/firebase",
            "\(NSHomeDirectory())/.npm-global/bin/firebase",
            "/usr/bin/firebase"
        ]

        for path in paths {
            // Handle glob patterns
            if path.contains("*") {
                let dir = (path as NSString).deletingLastPathComponent
                let filename = (path as NSString).lastPathComponent
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: (dir as NSString).deletingLastPathComponent) {
                    for item in contents {
                        let fullPath = ((dir as NSString).deletingLastPathComponent as NSString)
                            .appendingPathComponent(item + "/bin/\(filename)")
                        if FileManager.default.isExecutableFile(atPath: fullPath) {
                            firebaseCLIPath = fullPath
                            return
                        }
                    }
                }
            } else if FileManager.default.isExecutableFile(atPath: path) {
                firebaseCLIPath = path
                return
            }
        }

        // Try `which firebase`
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["firebase"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty && FileManager.default.isExecutableFile(atPath: output) {
            firebaseCLIPath = output
        }
    }

    // MARK: - Upload

    /// Upload an APK to Firebase App Distribution
    func uploadAPK(apkPath: String, config: FirebaseConfig, releaseNotes: String? = nil) {
        guard !firebaseCLIPath.isEmpty else {
            uploadState = .failed(error: "Firebase CLI not found. Install with: npm install -g firebase-tools")
            return
        }

        guard FileManager.default.fileExists(atPath: apkPath) else {
            uploadState = .failed(error: "APK file not found: \(apkPath)")
            return
        }

        uploadState = .uploading(progress: "Preparing upload...")
        uploadLog = ""

        // Build the firebase appdistribution:distribute command
        var args = [
            firebaseCLIPath,
            "appdistribution:distribute",
            apkPath,
            "--app", config.appId
        ]

        // Add groups
        if !config.groups.isEmpty {
            args += ["--groups", config.groups.joined(separator: ",")]
        }

        // Add testers
        if !config.testers.isEmpty {
            args += ["--testers", config.testers.joined(separator: ",")]
        }

        // Add release notes
        let notes = releaseNotes ?? config.releaseNotes ?? ""
        if !notes.isEmpty {
            args += ["--release-notes", notes]
        }

        // Add service account if configured
        if let saPath = config.serviceAccountPath, !saPath.isEmpty {
            let expandedPath = NSString(string: saPath).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expandedPath) {
                args += ["--service-credentials-file", expandedPath]
            }
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", args.joined(separator: " ")]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Pass through environment (for Node.js/npm)
        var environment = ProcessInfo.processInfo.environment
        if let npmPath = environment["PATH"] {
            // Ensure common npm paths are included
            let additionalPaths = [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "\(NSHomeDirectory())/.npm-global/bin"
            ]
            environment["PATH"] = (additionalPaths + [npmPath]).joined(separator: ":")
        }
        process.environment = environment

        currentProcess = process

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.uploadLog += output
                self?.parseProgress(output)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.uploadLog += "[ERROR] \(output)"
            }
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try process.run()
                process.waitUntilExit()

                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let exitCode = process.terminationStatus

                DispatchQueue.main.async {
                    if exitCode == 0 {
                        // Try to extract download URL from output
                        let downloadURL = self?.extractDownloadURL(from: self?.uploadLog ?? "")
                        self?.uploadState = .success(downloadURL: downloadURL)
                        NotificationService.shared.sendCustomNotification(
                            title: "Firebase Upload Complete",
                            body: "APK uploaded to Firebase App Distribution"
                        )
                    } else {
                        let errorMsg = self?.extractErrorMessage(from: self?.uploadLog ?? "") ?? "Exit code \(exitCode)"
                        self?.uploadState = .failed(error: errorMsg)
                    }
                    self?.currentProcess = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self?.uploadState = .failed(error: error.localizedDescription)
                    self?.currentProcess = nil
                }
            }
        }
    }

    /// Cancel an ongoing upload
    func cancelUpload() {
        currentProcess?.terminate()
        currentProcess = nil
        uploadState = .idle
        uploadLog += "\n[Cancelled by user]\n"
    }

    // MARK: - Helpers

    private func parseProgress(_ output: String) {
        if output.contains("Uploading") || output.contains("uploading") {
            uploadState = .uploading(progress: "Uploading APK...")
        } else if output.contains("Distributing") || output.contains("distributing") {
            uploadState = .uploading(progress: "Distributing to testers...")
        } else if output.contains("Processing") {
            uploadState = .uploading(progress: "Processing...")
        }
    }

    private func extractDownloadURL(from log: String) -> String? {
        // Firebase CLI might print a console URL
        let patterns = [
            "(https://appdistribution\\.firebase\\.google\\.com[^\\s]+)",
            "(https://console\\.firebase\\.google\\.com[^\\s]+)"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: log, range: NSRange(log.startIndex..., in: log)),
               let range = Range(match.range(at: 1), in: log) {
                return String(log[range])
            }
        }
        return nil
    }

    private func extractErrorMessage(from log: String) -> String? {
        // Look for common error patterns
        let lines = log.components(separatedBy: "\n")
        for line in lines.reversed() {
            if line.contains("Error:") || line.contains("error:") || line.contains("FAILED") {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    /// Check if firebase CLI is available
    var isConfigured: Bool {
        !firebaseCLIPath.isEmpty && FileManager.default.isExecutableFile(atPath: firebaseCLIPath)
    }

    /// Login status check
    func checkLoginStatus(completion: @escaping (Bool) -> Void) {
        guard isConfigured else {
            completion(false)
            return
        }

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "\(firebaseCLIPath) login:list"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        DispatchQueue.global(qos: .utility).async {
            try? process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                completion(output.contains("@") && !output.contains("No authorized accounts"))
            }
        }
    }

    /// Open firebase login in terminal
    func openFirebaseLogin() {
        let script = """
        tell application "Terminal"
            activate
            do script "\(firebaseCLIPath) login"
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(nil)
        }
    }
}

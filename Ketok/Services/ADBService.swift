import Foundation
import Combine

/// Install speed mode — controls how APKs are pushed to devices
enum ADBInstallMode: String, CaseIterable, Identifiable {
    case auto = "auto"                 // Auto-detect best mode per device
    case incremental = "incremental"   // Android 12+ (API 31): only transfers changed blocks
    case streaming = "streaming"       // Default in modern ADB: pipes directly
    case standard = "standard"         // Classic push-then-install

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto (Recommended)"
        case .incremental: return "Incremental (Android 12+)"
        case .streaming: return "Streaming"
        case .standard: return "Standard"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Uses incremental on Android 12+, streaming on older devices"
        case .incremental: return "Only transfers changed blocks — fastest for iterative builds"
        case .streaming: return "Streams APK directly to device — good for large APKs"
        case .standard: return "Classic full transfer — most compatible"
        }
    }
}

/// Represents a connected Android device or emulator
struct ADBDevice: Identifiable, Hashable {
    let id: String          // serial number
    let name: String        // model name or emulator name
    let type: DeviceType
    let state: String       // device, offline, unauthorized
    var apiLevel: Int?      // SDK version (e.g. 31 = Android 12)

    enum DeviceType: String {
        case physical = "device"
        case emulator = "emulator"
    }

    var isOnline: Bool { state == "device" }

    var displayName: String {
        if name.isEmpty { return id }
        return name
    }

    /// Whether this device supports incremental install (Android 12+, API 31+)
    var supportsIncremental: Bool {
        (apiLevel ?? 0) >= 31
    }

    /// Whether this device supports streaming install (API 21+)
    var supportsStreaming: Bool {
        (apiLevel ?? 0) >= 21
    }

    var androidVersionName: String? {
        guard let api = apiLevel else { return nil }
        switch api {
        case 35: return "15"
        case 34: return "14"
        case 33: return "13"
        case 32, 31: return "12"
        case 30: return "11"
        case 29: return "10"
        case 28: return "9"
        default: return "API \(api)"
        }
    }

    var icon: String {
        switch type {
        case .physical: return "iphone"
        case .emulator: return "desktopcomputer"
        }
    }
}

/// Service for interacting with ADB (Android Debug Bridge)
class ADBService: ObservableObject {
    @Published var devices: [ADBDevice] = []
    @Published var isInstalling = false
    @Published var installResult: InstallResult?
    @Published var installMode: ADBInstallMode = .auto
    @Published var lastInstallStats: InstallStats?

    // Logcat
    @Published var logcatOutput: String = ""
    @Published var isLogcatRunning = false
    private var logcatProcess: Process?

    /// Stats for the last install operation
    struct InstallStats {
        let device: String
        let apkSize: Int64          // bytes
        let duration: TimeInterval  // seconds
        let mode: ADBInstallMode    // which mode was actually used
        let success: Bool

        var speedMBps: Double {
            guard duration > 0 else { return 0 }
            return Double(apkSize) / 1_000_000.0 / duration
        }

        var summary: String {
            let sizeMB = String(format: "%.1f", Double(apkSize) / 1_000_000.0)
            let time = String(format: "%.1f", duration)
            let speed = String(format: "%.1f", speedMBps)
            return "\(sizeMB) MB in \(time)s (\(speed) MB/s) via \(mode.rawValue)"
        }
    }

    enum InstallResult {
        case success(device: String)
        case failed(device: String, error: String)
    }

    private var refreshTimer: Timer?

    /// Find adb executable path
    private var adbPath: String? {
        // Check ANDROID_HOME first
        let paths = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"].map { "\($0)/platform-tools/adb" },
            ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"].map { "\($0)/platform-tools/adb" },
            "\(NSHomeDirectory())/Library/Android/sdk/platform-tools/adb"
        ].compactMap { $0 }

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Try which adb
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["adb"]
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

    /// Start periodic device refresh
    func startMonitoring() {
        refreshDevices()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    /// Stop periodic refresh
    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Refresh connected devices list and fetch API levels
    func refreshDevices() {
        guard let adb = adbPath else {
            DispatchQueue.main.async { self.devices = [] }
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            var parsed = Self.parseDeviceList(
                Self.runADB(adb: adb, args: ["devices", "-l"])
            )

            // Fetch API level for each online device (for install mode selection)
            for i in parsed.indices where parsed[i].isOnline {
                let apiOutput = Self.runADB(adb: adb, args: [
                    "-s", parsed[i].id,
                    "shell", "getprop", "ro.build.version.sdk"
                ]).trimmingCharacters(in: .whitespacesAndNewlines)
                parsed[i].apiLevel = Int(apiOutput)
            }

            DispatchQueue.main.async {
                self?.devices = parsed
            }
        }
    }

    /// Install an APK on a specific device using the fastest available method, then launch it
    func installAPK(apkPath: String, device: ADBDevice, completion: @escaping (Bool, String) -> Void) {
        guard let adb = adbPath else {
            completion(false, "ADB not found")
            return
        }

        guard FileManager.default.fileExists(atPath: apkPath) else {
            completion(false, "APK not found at \(apkPath)")
            return
        }

        let apkSize = (try? FileManager.default.attributesOfItem(atPath: apkPath)[.size] as? Int64) ?? 0

        DispatchQueue.main.async { self.isInstalling = true }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let startTime = Date()

            // Determine the best install mode for this device
            let effectiveMode = self.resolveInstallMode(for: device)
            var installArgs = ["-s", device.id, "install", "-r"]

            switch effectiveMode {
            case .incremental:
                // --incremental: only transfer changed blocks (Android 12+, API 31+)
                // Massive speedup for iterative development builds
                installArgs.append("--incremental")
            case .streaming:
                // --streaming: pipe APK directly instead of push-then-install
                installArgs.append("--streaming")
            case .standard, .auto:
                // Standard: no extra flags, classic full transfer
                break
            }

            installArgs.append(apkPath)

            var output = Self.runADB(adb: adb, args: installArgs)
            var success = output.contains("Success")

            // Fallback: if incremental/streaming failed, retry with standard mode
            if !success && effectiveMode != .standard {
                let errorHint = output.lowercased()
                let isModeFail = errorHint.contains("unknown option")
                    || errorHint.contains("incremental")
                    || errorHint.contains("streaming")
                    || errorHint.contains("not supported")

                if isModeFail {
                    // Retry with plain install
                    output = Self.runADB(adb: adb, args: ["-s", device.id, "install", "-r", apkPath])
                    success = output.contains("Success")
                }
            }

            let duration = Date().timeIntervalSince(startTime)

            // If install succeeded, extract package name and launch the app
            if success {
                if let packageName = Self.extractPackageName(adb: adb, apkPath: apkPath) {
                    let _ = Self.runADB(adb: adb, args: [
                        "-s", device.id,
                        "shell", "monkey",
                        "-p", packageName,
                        "-c", "android.intent.category.LAUNCHER",
                        "1"
                    ])
                }
            }

            let stats = InstallStats(
                device: device.displayName,
                apkSize: apkSize,
                duration: duration,
                mode: effectiveMode,
                success: success
            )

            DispatchQueue.main.async {
                self.isInstalling = false
                self.lastInstallStats = stats
                if success {
                    self.installResult = .success(device: device.displayName)
                    NotificationService.shared.sendInstallSuccess(
                        project: (apkPath as NSString).lastPathComponent,
                        device: device.displayName
                    )
                } else {
                    let error = output.components(separatedBy: "Failure").last?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    self.installResult = .failed(device: device.displayName, error: error)
                }
                completion(success, output)
            }
        }
    }

    /// Determine the actual install mode to use for a given device
    private func resolveInstallMode(for device: ADBDevice) -> ADBInstallMode {
        switch installMode {
        case .auto:
            // Auto: use incremental on Android 12+, streaming on 5+, standard otherwise
            if device.supportsIncremental {
                return .incremental
            } else if device.supportsStreaming {
                return .streaming
            } else {
                return .standard
            }
        case .incremental:
            // Only use if device supports it, otherwise fall back to streaming
            return device.supportsIncremental ? .incremental : .streaming
        case .streaming, .standard:
            return installMode
        }
    }

    /// Install an APK on all connected online devices
    func installAPKOnAllDevices(apkPath: String, completion: @escaping (Int, Int) -> Void) {
        let onlineDevices = devices.filter { $0.isOnline }
        guard !onlineDevices.isEmpty else {
            completion(0, 0)
            return
        }

        DispatchQueue.main.async { self.isInstalling = true }

        let group = DispatchGroup()
        var successCount = 0
        var failCount = 0
        let lock = NSLock()

        for device in onlineDevices {
            group.enter()
            installAPK(apkPath: apkPath, device: device) { success, _ in
                lock.lock()
                if success { successCount += 1 } else { failCount += 1 }
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isInstalling = false
            if failCount == 0 {
                NotificationService.shared.sendInstallSuccess(
                    project: (apkPath as NSString).lastPathComponent,
                    device: "\(successCount) device\(successCount == 1 ? "" : "s")"
                )
            }
            completion(successCount, failCount)
        }
    }

    // MARK: - Logcat

    /// Start streaming logcat from a device
    func startLogcat(device: ADBDevice, filter: String = "") {
        stopLogcat()
        guard let adb = adbPath else { return }

        logcatOutput = ""
        isLogcatRunning = true

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: adb)
        var args = ["-s", device.id, "logcat", "-v", "time"]
        if !filter.isEmpty {
            args.append(contentsOf: ["-s", filter])
        }
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        self.logcatProcess = process

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Keep only last 50KB to avoid memory issues
                self.logcatOutput += output
                if self.logcatOutput.count > 50000 {
                    self.logcatOutput = String(self.logcatOutput.suffix(40000))
                }
            }
        }

        do {
            try process.run()
        } catch {
            DispatchQueue.main.async {
                self.isLogcatRunning = false
                self.logcatOutput = "Error starting logcat: \(error.localizedDescription)"
            }
        }
    }

    /// Stop the running logcat stream
    func stopLogcat() {
        logcatProcess?.terminate()
        logcatProcess = nil
        DispatchQueue.main.async {
            self.isLogcatRunning = false
        }
    }

    /// Clear logcat buffer on device
    func clearLogcat(device: ADBDevice) {
        guard let adb = adbPath else { return }
        DispatchQueue.global(qos: .utility).async {
            _ = Self.runADB(adb: adb, args: ["-s", device.id, "logcat", "-c"])
            DispatchQueue.main.async {
                self.logcatOutput = ""
            }
        }
    }

    /// Extract the package name from an APK using aapt2 or aapt
    private static func extractPackageName(adb: String, apkPath: String) -> String? {
        // aapt2 / aapt lives alongside adb in platform-tools, or in build-tools
        let adbDir = (adb as NSString).deletingLastPathComponent
        let sdkDir = (adbDir as NSString).deletingLastPathComponent

        // Try aapt2 first (preferred), then aapt
        let candidates: [String] = {
            var paths = [
                "\(adbDir)/aapt2",
                "\(adbDir)/aapt"
            ]
            // Also scan build-tools versions
            let buildToolsDir = "\(sdkDir)/build-tools"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsDir) {
                let sorted = versions.sorted().reversed()  // newest first
                for version in sorted {
                    paths.append("\(buildToolsDir)/\(version)/aapt2")
                    paths.append("\(buildToolsDir)/\(version)/aapt")
                }
            }
            return paths
        }()

        for toolPath in candidates {
            guard FileManager.default.isExecutableFile(atPath: toolPath) else { continue }

            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: toolPath)

            if toolPath.hasSuffix("aapt2") {
                process.arguments = ["dump", "packagename", apkPath]
            } else {
                process.arguments = ["dump", "badging", apkPath]
            }

            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else { continue }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if toolPath.hasSuffix("aapt2") {
                    // aapt2 dump packagename returns just the package name
                    let pkg = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !pkg.isEmpty { return pkg }
                } else {
                    // aapt dump badging: parse "package: name='com.example.app' ..."
                    if let range = output.range(of: "package: name='") {
                        let start = range.upperBound
                        if let end = output[start...].firstIndex(of: "'") {
                            return String(output[start..<end])
                        }
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    /// Parse `adb devices -l` output
    private static func parseDeviceList(_ output: String) -> [ADBDevice] {
        var devices: [ADBDevice] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("List of"),
                  !trimmed.hasPrefix("*") else { continue }

            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard parts.count >= 2 else { continue }

            let serial = parts[0]
            let state = parts[1]

            // Extract model name from properties
            var name = ""
            for part in parts[2...] {
                if part.hasPrefix("model:") {
                    name = String(part.dropFirst("model:".count))
                        .replacingOccurrences(of: "_", with: " ")
                }
            }

            let type: ADBDevice.DeviceType = serial.hasPrefix("emulator") ? .emulator : .physical

            devices.append(ADBDevice(
                id: serial,
                name: name,
                type: type,
                state: state
            ))
        }

        return devices
    }

    // MARK: - Wireless ADB (Android 11+)

    @Published var wirelessPairingResult: WirelessResult?
    @Published var isPairing = false
    @Published var isConnecting = false

    enum WirelessResult: Equatable {
        case success(String)
        case failed(String)
    }

    /// Pair with a device using wireless debugging (Android 11+)
    /// Requires the pairing code and IP:port shown on the device
    func pairDevice(host: String, port: String, pairingCode: String) {
        guard let adb = adbPath else {
            wirelessPairingResult = .failed("ADB not found")
            return
        }

        isPairing = true
        wirelessPairingResult = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // adb pair <host>:<port> <pairing_code>
            let address = "\(host):\(port)"
            let output = Self.runADBWithInput(adb: adb, args: ["pair", address], input: pairingCode)
            let success = output.contains("Successfully paired") || output.contains("successfully paired")

            DispatchQueue.main.async {
                self?.isPairing = false
                if success {
                    self?.wirelessPairingResult = .success("Paired with \(address)")
                    // Refresh devices after pairing
                    self?.refreshDevices()
                } else {
                    let error = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.wirelessPairingResult = .failed(error.isEmpty ? "Pairing failed" : String(error.prefix(150)))
                }
            }
        }
    }

    /// Connect to a wirelessly paired device
    func connectDevice(host: String, port: String) {
        guard let adb = adbPath else {
            wirelessPairingResult = .failed("ADB not found")
            return
        }

        isConnecting = true
        wirelessPairingResult = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let address = "\(host):\(port)"
            let output = Self.runADB(adb: adb, args: ["connect", address])
            let success = output.contains("connected to") || output.contains("already connected")

            DispatchQueue.main.async {
                self?.isConnecting = false
                if success {
                    self?.wirelessPairingResult = .success("Connected to \(address)")
                    self?.refreshDevices()
                } else {
                    let error = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self?.wirelessPairingResult = .failed(error.isEmpty ? "Connection failed" : String(error.prefix(150)))
                }
            }
        }
    }

    /// Disconnect a wireless device
    func disconnectDevice(host: String, port: String) {
        guard let adb = adbPath else { return }

        let address = "\(host):\(port)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Self.runADB(adb: adb, args: ["disconnect", address])
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
    }

    /// Disconnect all wireless devices
    func disconnectAll() {
        guard let adb = adbPath else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = Self.runADB(adb: adb, args: ["disconnect"])
            DispatchQueue.main.async {
                self?.refreshDevices()
            }
        }
    }

    /// Run an ADB command and return output
    private static func runADB(adb: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    /// Run an ADB command with stdin input (for pairing code)
    private static func runADBWithInput(adb: String, args: [String], input: String) -> String {
        let process = Process()
        let outPipe = Pipe()
        let inPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: adb)
        process.arguments = args
        process.standardOutput = outPipe
        process.standardError = outPipe
        process.standardInput = inPipe

        do {
            try process.run()
            // Write pairing code to stdin
            if let data = "\(input)\n".data(using: .utf8) {
                inPipe.fileHandleForWriting.write(data)
                inPipe.fileHandleForWriting.closeFile()
            }
            process.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }
}

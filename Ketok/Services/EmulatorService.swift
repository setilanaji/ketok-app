import Foundation
import Combine

/// Represents an available Android Virtual Device (AVD)
struct AVDEmulator: Identifiable, Hashable {
    let id: String          // AVD name (used as identifier)
    let name: String        // Display name
    let device: String      // Device type (e.g., "pixel_6")
    let target: String      // API target (e.g., "android-34")
    let apiLevel: Int       // Numeric API level
    let abi: String         // ABI (e.g., "x86_64", "arm64-v8a")
    let tag: String         // Tag/ABI (e.g., "google_apis", "google_apis_playstore")
    var isRunning: Bool     // Whether this emulator is currently booted

    var displayTarget: String {
        if tag.contains("playstore") {
            return "API \(apiLevel) (Play Store)"
        } else if tag.contains("google_apis") {
            return "API \(apiLevel) (Google APIs)"
        }
        return "API \(apiLevel)"
    }

    var icon: String {
        if tag.contains("tv") { return "tv" }
        if tag.contains("wear") { return "applewatch" }
        if tag.contains("auto") { return "car" }
        return "desktopcomputer"
    }
}

/// Service for managing Android emulators
class EmulatorService: ObservableObject {
    @Published var availableAVDs: [AVDEmulator] = []
    @Published var isLoading = false
    @Published var isLaunching: String? = nil  // AVD name currently launching
    @Published var launchError: String?
    @Published var coldBootNext = false

    /// Find the emulator executable path
    private var emulatorPath: String? {
        let paths = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"].map { "\($0)/emulator/emulator" },
            ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"].map { "\($0)/emulator/emulator" },
            "\(NSHomeDirectory())/Library/Android/sdk/emulator/emulator"
        ].compactMap { $0 }

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Find avdmanager path
    private var avdmanagerPath: String? {
        let paths = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"].map { "\($0)/cmdline-tools/latest/bin/avdmanager" },
            ProcessInfo.processInfo.environment["ANDROID_SDK_ROOT"].map { "\($0)/cmdline-tools/latest/bin/avdmanager" },
            "\(NSHomeDirectory())/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager"
        ].compactMap { $0 }

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Find ADB path
    private var adbPath: String? {
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
        return nil
    }

    // MARK: - List AVDs

    /// Refresh the list of available AVDs and their running state
    func refreshAVDs() {
        guard let emulator = emulatorPath else {
            DispatchQueue.main.async { self.availableAVDs = [] }
            return
        }

        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Get list of AVD names from emulator -list-avds
            let avdOutput = Self.runCommand(emulator, args: ["-list-avds"])
            let avdNames = avdOutput.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("INFO") && !$0.hasPrefix("WARNING") }

            // Get running emulators via adb
            let runningEmulators = self?.getRunningEmulatorAVDs() ?? Set<String>()

            // Parse each AVD's config for details
            var emulators: [AVDEmulator] = []
            for name in avdNames {
                let avd = self?.parseAVDConfig(name: name, isRunning: runningEmulators.contains(name))
                if let avd = avd {
                    emulators.append(avd)
                }
            }

            // Sort: running first, then by API level descending
            emulators.sort { lhs, rhs in
                if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
                return lhs.apiLevel > rhs.apiLevel
            }

            DispatchQueue.main.async {
                self?.availableAVDs = emulators
                self?.isLoading = false
            }
        }
    }

    /// Parse AVD config.ini and hardware-qemu.ini for an AVD
    private func parseAVDConfig(name: String, isRunning: Bool) -> AVDEmulator {
        let avdDir = "\(NSHomeDirectory())/.android/avd/\(name).avd"
        let configPath = "\(avdDir)/config.ini"

        var device = ""
        var target = ""
        var apiLevel = 0
        var abi = ""
        var tag = "default"

        if let content = try? String(contentsOfFile: configPath, encoding: .utf8) {
            let lines = content.components(separatedBy: "\n")
            for line in lines {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                let key = parts[0]
                let value = parts[1]

                switch key {
                case "hw.device.name":
                    device = value
                case "image.sysdir.1":
                    // Extract API level and tag from system image path
                    // e.g., "system-images/android-34/google_apis_playstore/arm64-v8a/"
                    let pathParts = value.components(separatedBy: "/")
                    for part in pathParts {
                        if part.hasPrefix("android-") {
                            target = part
                            apiLevel = Int(part.replacingOccurrences(of: "android-", with: "")) ?? 0
                        }
                    }
                    if pathParts.count >= 3 {
                        tag = pathParts[pathParts.count - 3] != "system-images" ? pathParts[pathParts.count - 2] : tag
                    }
                case "abi.type":
                    abi = value
                case "tag.id":
                    tag = value
                default:
                    break
                }
            }
        }

        // Prettify the device name
        let displayName = name.replacingOccurrences(of: "_", with: " ")

        return AVDEmulator(
            id: name,
            name: displayName,
            device: device,
            target: target,
            apiLevel: apiLevel,
            abi: abi,
            tag: tag,
            isRunning: isRunning
        )
    }

    /// Get set of AVD names that are currently running
    private func getRunningEmulatorAVDs() -> Set<String> {
        guard let adb = adbPath else { return [] }

        let output = Self.runCommand(adb, args: ["devices", "-l"])
        var running = Set<String>()

        // For each emulator-NNNN device, query its avd name
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("emulator-") {
                let serial = trimmed.components(separatedBy: .whitespaces).first ?? ""
                if !serial.isEmpty {
                    let avdName = Self.runCommand(adb, args: ["-s", serial, "emu", "avd", "name"])
                        .components(separatedBy: "\n").first?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !avdName.isEmpty && !avdName.contains("OK") {
                        running.insert(avdName)
                    }
                }
            }
        }
        return running
    }

    // MARK: - Launch / Stop

    /// Launch an emulator by AVD name
    func launchEmulator(avdName: String) {
        guard let emulator = emulatorPath else {
            launchError = "Emulator not found. Check ANDROID_HOME."
            return
        }

        isLaunching = avdName
        launchError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = ["@\(avdName)", "-no-snapshot-load"]

            // Cold boot if requested
            if self?.coldBootNext == true {
                args = ["@\(avdName)", "-no-snapshot"]
                DispatchQueue.main.async { self?.coldBootNext = false }
            } else {
                args = ["@\(avdName)"]
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: emulator)
            process.arguments = args
            // Detach — emulator runs independently
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()

                // Wait a moment for the emulator to start, then refresh
                Thread.sleep(forTimeInterval: 3.0)

                DispatchQueue.main.async {
                    self?.isLaunching = nil
                    self?.refreshAVDs()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLaunching = nil
                    self?.launchError = "Failed to launch: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Kill a running emulator
    func stopEmulator(avdName: String) {
        guard let adb = adbPath else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // Find the emulator serial for this AVD
            let output = Self.runCommand(adb, args: ["devices", "-l"])
            let lines = output.components(separatedBy: "\n")

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("emulator-") {
                    let serial = trimmed.components(separatedBy: .whitespaces).first ?? ""
                    if !serial.isEmpty {
                        let name = Self.runCommand(adb, args: ["-s", serial, "emu", "avd", "name"])
                            .components(separatedBy: "\n").first?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if name == avdName {
                            _ = Self.runCommand(adb, args: ["-s", serial, "emu", "kill"])
                            Thread.sleep(forTimeInterval: 1.0)
                            DispatchQueue.main.async {
                                self?.refreshAVDs()
                            }
                            return
                        }
                    }
                }
            }
        }
    }

    /// Wipe data and cold boot an emulator
    func wipeAndLaunch(avdName: String) {
        guard let emulator = emulatorPath else {
            launchError = "Emulator not found."
            return
        }

        isLaunching = avdName
        launchError = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: emulator)
            process.arguments = ["@\(avdName)", "-wipe-data"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                Thread.sleep(forTimeInterval: 3.0)
                DispatchQueue.main.async {
                    self?.isLaunching = nil
                    self?.refreshAVDs()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isLaunching = nil
                    self?.launchError = "Failed to launch: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Helpers

    /// Run a command and return stdout
    static func runCommand(_ path: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // Inherit Android-related env vars
        var env = ProcessInfo.processInfo.environment
        if let home = env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"] {
            env["ANDROID_HOME"] = home
            env["PATH"] = "\(home)/platform-tools:\(home)/emulator:\(env["PATH"] ?? "")"
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

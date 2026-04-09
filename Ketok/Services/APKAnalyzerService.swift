import Foundation

/// Analysis result for an APK file
struct APKAnalysis {
    let filePath: String
    let fileSize: Int64
    let permissions: [String]
    let minSdk: String?
    let targetSdk: String?
    let packageName: String?
    let versionName: String?
    let versionCode: String?
    let dexFileCount: Int
    let resourceCount: Int
    let nativeLibs: [String]

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Categorize permissions by risk level
    var dangerousPermissions: [String] {
        let dangerous = Set([
            "android.permission.CAMERA",
            "android.permission.READ_CONTACTS",
            "android.permission.WRITE_CONTACTS",
            "android.permission.ACCESS_FINE_LOCATION",
            "android.permission.ACCESS_COARSE_LOCATION",
            "android.permission.RECORD_AUDIO",
            "android.permission.READ_PHONE_STATE",
            "android.permission.CALL_PHONE",
            "android.permission.READ_EXTERNAL_STORAGE",
            "android.permission.WRITE_EXTERNAL_STORAGE",
            "android.permission.READ_CALENDAR",
            "android.permission.WRITE_CALENDAR",
            "android.permission.SEND_SMS",
            "android.permission.READ_SMS",
            "android.permission.BODY_SENSORS",
        ])
        return permissions.filter { dangerous.contains($0) }
    }

    var normalPermissions: [String] {
        let dangerous = Set(dangerousPermissions)
        return permissions.filter { !dangerous.contains($0) }
    }
}

/// Analyzes APK files using aapt2/aapt
class APKAnalyzerService {

    /// Analyze an APK file
    static func analyze(apkPath: String) -> APKAnalysis? {
        guard FileManager.default.fileExists(atPath: apkPath) else { return nil }

        // Get file size
        let fileSize: Int64 = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: apkPath)
            return attrs?[.size] as? Int64 ?? 0
        }()

        // Try to find aapt2 or aapt
        let aaptPath = findAAPT()

        var permissions: [String] = []
        var minSdk: String?
        var targetSdk: String?
        var packageName: String?
        var versionName: String?
        var versionCode: String?

        if let aapt = aaptPath {
            let badgingOutput = runCommand(aapt, args: ["dump", "badging", apkPath])

            // Parse package info
            if let pkgMatch = badgingOutput.range(of: "package: name='([^']+)'", options: .regularExpression) {
                let captured = badgingOutput[pkgMatch]
                if let nameRange = captured.range(of: "'([^']+)'", options: .regularExpression) {
                    packageName = String(captured[nameRange]).replacingOccurrences(of: "'", with: "")
                }
            }

            // Parse version
            if let vnMatch = badgingOutput.range(of: "versionName='([^']+)'", options: .regularExpression) {
                versionName = String(badgingOutput[vnMatch])
                    .replacingOccurrences(of: "versionName='", with: "")
                    .replacingOccurrences(of: "'", with: "")
            }

            if let vcMatch = badgingOutput.range(of: "versionCode='([^']+)'", options: .regularExpression) {
                versionCode = String(badgingOutput[vcMatch])
                    .replacingOccurrences(of: "versionCode='", with: "")
                    .replacingOccurrences(of: "'", with: "")
            }

            // Parse SDK versions
            if let minMatch = badgingOutput.range(of: "sdkVersion:'([^']+)'", options: .regularExpression) {
                minSdk = String(badgingOutput[minMatch])
                    .replacingOccurrences(of: "sdkVersion:'", with: "")
                    .replacingOccurrences(of: "'", with: "")
            }

            if let targetMatch = badgingOutput.range(of: "targetSdkVersion:'([^']+)'", options: .regularExpression) {
                targetSdk = String(badgingOutput[targetMatch])
                    .replacingOccurrences(of: "targetSdkVersion:'", with: "")
                    .replacingOccurrences(of: "'", with: "")
            }

            // Parse permissions
            let permOutput = runCommand(aapt, args: ["dump", "permissions", apkPath])
            permissions = permOutput
                .components(separatedBy: "\n")
                .filter { $0.hasPrefix("uses-permission:") }
                .compactMap { line in
                    let trimmed = line.replacingOccurrences(of: "uses-permission: name='", with: "")
                        .replacingOccurrences(of: "'", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    return trimmed.isEmpty ? nil : trimmed
                }
        }

        // Count DEX files and resources using unzip listing
        var dexCount = 0
        var resourceCount = 0
        var nativeLibs: [String] = []

        let zipOutput = runCommand("/usr/bin/unzip", args: ["-l", apkPath])
        for line in zipOutput.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(".dex") {
                dexCount += 1
            } else if trimmed.contains("res/") {
                resourceCount += 1
            } else if trimmed.contains("lib/") && trimmed.hasSuffix(".so") {
                if let soName = trimmed.components(separatedBy: " ").last {
                    let arch = (soName as NSString).deletingLastPathComponent
                        .replacingOccurrences(of: "lib/", with: "")
                    let lib = (soName as NSString).lastPathComponent
                    let entry = "\(arch)/\(lib)"
                    if !nativeLibs.contains(entry) {
                        nativeLibs.append(entry)
                    }
                }
            }
        }

        return APKAnalysis(
            filePath: apkPath,
            fileSize: fileSize,
            permissions: permissions,
            minSdk: minSdk,
            targetSdk: targetSdk,
            packageName: packageName,
            versionName: versionName,
            versionCode: versionCode,
            dexFileCount: dexCount,
            resourceCount: resourceCount,
            nativeLibs: nativeLibs
        )
    }

    // MARK: - Helpers

    private static func findAAPT() -> String? {
        // Check common locations
        let homeDir = NSHomeDirectory()
        let sdkPaths = [
            ProcessInfo.processInfo.environment["ANDROID_HOME"],
            "\(homeDir)/Library/Android/sdk",
            "/usr/local/share/android-sdk",
        ].compactMap { $0 }

        for sdkPath in sdkPaths {
            // Try aapt2 in build-tools
            let buildToolsPath = "\(sdkPath)/build-tools"
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: buildToolsPath) {
                let sorted = versions.sorted().reversed()
                for version in sorted {
                    let aapt2 = "\(buildToolsPath)/\(version)/aapt2"
                    if FileManager.default.isExecutableFile(atPath: aapt2) {
                        return aapt2
                    }
                    let aapt = "\(buildToolsPath)/\(version)/aapt"
                    if FileManager.default.isExecutableFile(atPath: aapt) {
                        return aapt
                    }
                }
            }
        }
        return nil
    }

    private static func runCommand(_ path: String, args: [String]) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

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

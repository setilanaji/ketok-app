import Foundation
import AppKit

/// Executes post-build actions sequentially after a successful build
class PostBuildActionRunner {

    /// Run all enabled post-build actions for a completed build
    static func runActions(
        _ actions: [PostBuildAction],
        apkPath: String,
        project: AndroidProject,
        adbService: ADBService
    ) {
        for action in actions where action.enabled {
            switch action.type {
            case .installOnDevice:
                installOnDevice(apkPath: apkPath, adbService: adbService, deviceId: action.parameter)

            case .installOnAll:
                installOnAllDevices(apkPath: apkPath, adbService: adbService)

            case .copyToFolder:
                if let folder = action.parameter ?? project.outputCopyPath {
                    copyToFolder(apkPath: apkPath, folder: folder)
                }

            case .openInFinder:
                revealInFinder(apkPath: apkPath)

            case .generateQR:
                QRCodeService.shared.generateAndServe(apkPath: apkPath)

            case .runLogcat:
                if let device = adbService.devices.first {
                    adbService.startLogcat(device: device, filter: action.parameter ?? "")
                }

            case .startOTA:
                startOTAServer(apkPath: apkPath, project: project)

            case .gitTag:
                gitTagRelease(project: project, tagTemplate: action.parameter)
            }
        }
    }

    private static func installOnDevice(apkPath: String, adbService: ADBService, deviceId: String?) {
        let devices: [ADBDevice]
        if let id = deviceId, let device = adbService.devices.first(where: { $0.id == id }) {
            devices = [device]
        } else {
            devices = adbService.devices.filter { $0.isOnline }
            guard let device = devices.first else { return }
            adbService.installAPK(apkPath: apkPath, device: device) { success, _ in
                if success {
                    Self.notifyInstallSuccess(adbService: adbService, apkPath: apkPath, device: device)
                }
            }
            return
        }

        for device in devices {
            adbService.installAPK(apkPath: apkPath, device: device) { success, _ in
                if success {
                    Self.notifyInstallSuccess(adbService: adbService, apkPath: apkPath, device: device)
                }
            }
        }
    }

    private static func installOnAllDevices(apkPath: String, adbService: ADBService) {
        let onlineDevices = adbService.devices.filter { $0.isOnline }

        guard onlineDevices.count > 1 else {
            // Single device — no parallelism needed
            if let device = onlineDevices.first {
                adbService.installAPK(apkPath: apkPath, device: device) { success, _ in
                    if success {
                        Self.notifyInstallSuccess(adbService: adbService, apkPath: apkPath, device: device)
                    }
                }
            }
            return
        }

        // Parallel install to multiple devices using DispatchGroup
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "com.ketok.parallel-install", attributes: .concurrent)
        var results: [(device: ADBDevice, success: Bool)] = []
        let resultsLock = NSLock()

        for device in onlineDevices {
            group.enter()
            queue.async {
                adbService.installAPK(apkPath: apkPath, device: device) { success, _ in
                    resultsLock.lock()
                    results.append((device, success))
                    resultsLock.unlock()

                    if success {
                        Self.notifyInstallSuccess(adbService: adbService, apkPath: apkPath, device: device)
                    }
                    group.leave()
                }
            }
        }

        // Notify when all installs complete
        group.notify(queue: .main) {
            let successCount = results.filter { $0.success }.count
            let failCount = results.count - successCount
            let deviceList = results.map { "\($0.device.displayName): \($0.success ? "✅" : "❌")" }.joined(separator: ", ")

            if failCount == 0 {
                NotificationService.shared.sendCustomNotification(
                    title: "Installed on \(successCount) devices",
                    body: deviceList
                )
            } else {
                NotificationService.shared.sendCustomNotification(
                    title: "Install: \(successCount) ok, \(failCount) failed",
                    body: deviceList
                )
            }
        }
    }

    /// Send install success notification with speed stats
    private static func notifyInstallSuccess(adbService: ADBService, apkPath: String, device: ADBDevice) {
        let projectName = (apkPath as NSString).lastPathComponent
        var body = "\(projectName) → \(device.displayName)"

        // Append transfer speed stats if available
        if let stats = adbService.lastInstallStats, stats.success {
            body += " (\(stats.summary))"
        }

        NotificationService.shared.sendInstallSuccess(
            project: projectName,
            device: device.displayName
        )
    }

    private static func copyToFolder(apkPath: String, folder: String) {
        let expandedPath = NSString(string: folder).expandingTildeInPath
        let fm = FileManager.default

        // Create folder if needed
        try? fm.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)

        let fileName = (apkPath as NSString).lastPathComponent
        let destPath = (expandedPath as NSString).appendingPathComponent(fileName)

        try? fm.removeItem(atPath: destPath)
        try? fm.copyItem(atPath: apkPath, toPath: destPath)
    }

    private static func revealInFinder(apkPath: String) {
        DispatchQueue.main.async {
            NSWorkspace.shared.selectFile(apkPath, inFileViewerRootedAtPath: "")
        }
    }

    private static func startOTAServer(apkPath: String, project: AndroidProject) {
        DispatchQueue.main.async {
            let otaService = OTADistributionService.shared
            otaService.startServing(
                filePath: apkPath,
                appName: project.name,
                variant: "",
                buildType: "",
                version: project.detectedVersionName,
                versionCode: project.detectedVersionCode
            )
        }
    }

    private static func gitTagRelease(project: AndroidProject, tagTemplate: String?) {
        let template = tagTemplate ?? "v{version}"
        let version = project.detectedVersionName ?? "0.0.0"
        let tagName = template
            .replacingOccurrences(of: "{version}", with: version)
            .replacingOccurrences(of: "{versionCode}", with: project.detectedVersionCode ?? "0")

        let result = GitService.tagRelease(
            at: project.path,
            tagName: tagName,
            message: "Release \(tagName)"
        )
        if result.success {
            DispatchQueue.main.async {
                NotificationService.shared.sendCustomNotification(
                    title: "Git Tagged",
                    body: "\(project.name) tagged as \(tagName)"
                )
            }
        }
    }
}

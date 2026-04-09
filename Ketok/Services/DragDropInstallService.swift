import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Handles drag & drop of APK/AAB files for installation on connected devices
class DragDropInstallService: ObservableObject {
    @Published var isDraggingOver = false
    @Published var droppedFilePath: String?
    @Published var showDeviceChooser = false
    @Published var lastDropResult: DropResult?

    enum DropResult: Equatable {
        case success(deviceName: String)
        case failed(error: String)
        case noDevices
    }

    /// Supported file extensions
    static let supportedExtensions: Set<String> = ["apk", "aab"]

    /// UTTypes for drop support
    static let supportedContentTypes: [UTType] = [
        .init(filenameExtension: "apk") ?? .data,
        .init(filenameExtension: "aab") ?? .data,
        .fileURL
    ]

    /// Validate and extract APK/AAB file path from drop info
    func handleDrop(providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
        guard let provider = providers.first else {
            completion(nil)
            return
        }

        // Try loading as file URL
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, error in
            guard let urlData = data as? Data,
                  let url = URL(dataRepresentation: urlData, relativeTo: nil),
                  url.isFileURL else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            DispatchQueue.main.async {
                self.droppedFilePath = path
                completion(path)
            }
        }
    }

    /// Check if the file is an APK (can be installed directly) or AAB (needs bundletool)
    func fileType(for path: String) -> BuildOutputFormat {
        let ext = (path as NSString).pathExtension.lowercased()
        return ext == "aab" ? .aab : .apk
    }

    /// Install the dropped APK on a specific device
    func installOnDevice(_ device: ADBDevice, apkPath: String, adbService: ADBService) {
        let format = fileType(for: apkPath)

        if format == .aab {
            lastDropResult = .failed(error: "AAB files cannot be installed directly. Use bundletool to convert to APKs first.")
            return
        }

        adbService.installAPK(apkPath: apkPath, device: device) { [weak self] success, output in
            DispatchQueue.main.async {
                if success {
                    self?.lastDropResult = .success(deviceName: device.displayName)
                } else {
                    let error = output.components(separatedBy: "Failure").last?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                    self?.lastDropResult = .failed(error: error)
                }
            }
        }
    }

    /// Install on all connected devices
    func installOnAllDevices(apkPath: String, adbService: ADBService) {
        let format = fileType(for: apkPath)

        if format == .aab {
            lastDropResult = .failed(error: "AAB files cannot be installed directly. Use bundletool to convert to APKs first.")
            return
        }

        let onlineDevices = adbService.devices.filter { $0.isOnline }
        guard !onlineDevices.isEmpty else {
            lastDropResult = .noDevices
            return
        }

        adbService.installAPKOnAllDevices(apkPath: apkPath) { [weak self] successes, failures in
            DispatchQueue.main.async {
                if failures == 0 {
                    self?.lastDropResult = .success(deviceName: "\(successes) device\(successes == 1 ? "" : "s")")
                } else {
                    self?.lastDropResult = .failed(error: "\(failures) device\(failures == 1 ? "" : "s") failed")
                }
            }
        }
    }

    func reset() {
        isDraggingOver = false
        droppedFilePath = nil
        showDeviceChooser = false
        lastDropResult = nil
    }
}

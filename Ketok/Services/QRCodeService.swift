import Foundation
import CoreImage
import AppKit
import Network
import OSLog

/// Generates QR codes and serves APKs over a local HTTP server for device installation.
///
/// **Security model:** This server is intentionally unauthenticated and uses plaintext HTTP.
/// It is designed for trusted local networks only (e.g. office WiFi, USB tethering).
/// Any device on the same network can download the served APK — do not use on untrusted networks.
class QRCodeService: ObservableObject {
    static let shared = QRCodeService()
    private let logger = Logger(subsystem: "com.ketok.app", category: "QRCodeService")

    @Published var isServing = false
    @Published var serverURL: String?
    @Published var qrImage: NSImage?
    @Published var servedFileName: String?

    private var listener: NWListener?
    private var servedFilePath: String?
    private let port: UInt16 = 8089

    private init() {}

    /// Generate a QR code and start a local HTTP server for the APK
    func generateAndServe(apkPath: String) {
        stopServing()

        servedFilePath = apkPath
        servedFileName = (apkPath as NSString).lastPathComponent

        // Get local IP
        guard let ip = getLocalIP() else {
            serverURL = nil
            return
        }

        let urlString = "http://\(ip):\(port)/\(servedFileName ?? "app.apk")"
        serverURL = urlString

        // Generate QR code image
        qrImage = generateQRCode(from: urlString)

        // Start HTTP server
        startServer()
    }

    /// Stop serving
    func stopServing() {
        listener?.cancel()
        listener = nil
        isServing = false
        serverURL = nil
        qrImage = nil
        servedFilePath = nil
        servedFileName = nil
    }

    // MARK: - QR Code Generation

    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter?.outputImage else { return nil }

        // Scale up for clear rendering
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    // MARK: - Local HTTP Server

    private func startServer() {
        do {
            let params = NWParameters.tcp
            listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            listener?.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        self?.isServing = true
                    case .failed, .cancelled:
                        self?.isServing = false
                    default:
                        break
                    }
                }
            }

            listener?.start(queue: .global(qos: .utility))
        } catch {
            logger.error("Failed to start QR server: \(error)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, _, _ in
            guard let self = self,
                  let filePath = self.servedFilePath,
                  let fileSize = try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int64,
                  let fileHandle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: filePath)) else {
                connection.cancel()
                return
            }

            let fileName = self.servedFileName ?? "app.apk"
            let header = "HTTP/1.1 200 OK\r\n" +
                "Content-Type: application/vnd.android.package-archive\r\n" +
                "Content-Disposition: attachment; filename=\"\(fileName)\"\r\n" +
                "Content-Length: \(fileSize)\r\n" +
                "Connection: close\r\n\r\n"

            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] _ in
                self?.streamFile(fileHandle: fileHandle, connection: connection)
            })
        }
    }

    /// Streams a file to an NWConnection in 64KB chunks to avoid loading large APKs into memory
    private func streamFile(fileHandle: FileHandle, connection: NWConnection) {
        let chunk = fileHandle.readData(ofLength: 65536)
        guard !chunk.isEmpty else {
            try? fileHandle.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil {
                try? fileHandle.close()
                connection.cancel()
            } else {
                self?.streamFile(fileHandle: fileHandle, connection: connection)
            }
        })
    }

    // MARK: - Network Helpers

    private func getLocalIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count), nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                }
            }
        }
        return address
    }
}

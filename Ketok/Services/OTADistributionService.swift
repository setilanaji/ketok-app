import Foundation
import CoreImage
import AppKit
import Network
import OSLog

/// Serves APK/AAB files over a local HTTP server for over-the-air (OTA) distribution via QR code.
///
/// **Security model:** This server is intentionally unauthenticated and uses plaintext HTTP.
/// It is designed for trusted local networks only (e.g. office WiFi, USB tethering).
/// Any device on the same network can download the served APK — do not use on untrusted networks.
class OTADistributionService: ObservableObject {
    static let shared = OTADistributionService()
    private let logger = Logger(subsystem: "com.ketok.app", category: "OTADistributionService")

    @Published var isServing = false
    @Published var serverURL: String?
    @Published var qrImage: NSImage?
    @Published var servedFileName: String?
    @Published var downloadCount: Int = 0
    @Published var connectedClients: Int = 0

    private var listener: NWListener?
    private var servedFilePath: String?
    private let port: UInt16 = 8090
    private var appInfo: OTAAppInfo?

    /// App info displayed on the OTA page
    struct OTAAppInfo {
        var appName: String
        var version: String?
        var versionCode: String?
        var variant: String
        var buildType: String
        var fileSize: String?
        var buildDate: Date = Date()
        var changelog: String?
        var outputFormat: BuildOutputFormat = .apk
    }

    private init() {}

    /// Start serving an APK/AAB with a full OTA landing page
    func startServing(
        filePath: String,
        appName: String,
        variant: String,
        buildType: String,
        version: String? = nil,
        versionCode: String? = nil,
        changelog: String? = nil,
        outputFormat: BuildOutputFormat = .apk
    ) {
        stopServing()

        servedFilePath = filePath
        servedFileName = (filePath as NSString).lastPathComponent

        // Compute file size
        let attrs = try? FileManager.default.attributesOfItem(atPath: filePath)
        let fileSize: String? = {
            guard let bytes = attrs?[.size] as? Int64 else { return nil }
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }()

        appInfo = OTAAppInfo(
            appName: appName,
            version: version,
            versionCode: versionCode,
            variant: variant,
            buildType: buildType,
            fileSize: fileSize,
            changelog: changelog,
            outputFormat: outputFormat
        )

        guard let ip = getLocalIP() else {
            serverURL = nil
            return
        }

        let urlString = "http://\(ip):\(port)"
        serverURL = urlString
        qrImage = generateQRCode(from: urlString)
        downloadCount = 0

        startServer()
    }

    func stopServing() {
        listener?.cancel()
        listener = nil
        isServing = false
        serverURL = nil
        qrImage = nil
        servedFilePath = nil
        servedFileName = nil
        appInfo = nil
        downloadCount = 0
    }

    // MARK: - Server

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
            logger.error("Failed to start OTA server: \(error)")
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .utility))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self = self,
                  let data = data,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the request path
            let path = self.parseRequestPath(from: request)

            if path == "/download" {
                self.serveFile(connection: connection, requestHeader: request)
            } else {
                self.serveLandingPage(connection: connection)
            }
        }
    }

    private func parseRequestPath(from request: String) -> String {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return "/" }
        return parts[1]
    }

    private func serveLandingPage(connection: NWConnection) {
        let html = generateLandingHTML()
        let htmlData = Data(html.utf8)

        var response = "HTTP/1.1 200 OK\r\n"
        response += "Content-Type: text/html; charset=utf-8\r\n"
        response += "Content-Length: \(htmlData.count)\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"

        var responseData = Data(response.utf8)
        responseData.append(htmlData)

        connection.send(content: responseData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func serveFile(connection: NWConnection, requestHeader: String = "") {
        guard let filePath = servedFilePath else {
            let notFound = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(notFound.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: filePath),
              let totalSize = attrs[.size] as? Int64 else {
            let error = "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(error.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        DispatchQueue.main.async {
            self.downloadCount += 1
        }

        let fileName = servedFileName ?? "app.apk"
        let contentType = fileName.hasSuffix(".aab")
            ? "application/octet-stream"
            : "application/vnd.android.package-archive"

        // Parse Range header for resumable downloads: "Range: bytes=12345-"
        var rangeStart: Int64 = 0
        var rangeEnd: Int64 = totalSize - 1
        var isPartial = false

        if let rangeHeader = Self.extractHeader("Range", from: requestHeader) {
            let rangeStr = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
            let parts = rangeStr.split(separator: "-")
            if let start = parts.first.flatMap({ Int64($0) }) {
                rangeStart = min(start, totalSize - 1)
                isPartial = true
            }
            if parts.count > 1, let end = Int64(parts[1]) {
                rangeEnd = min(end, totalSize - 1)
            }
        }

        let contentLength = rangeEnd - rangeStart + 1

        // Build response header
        var header: String
        if isPartial {
            header = "HTTP/1.1 206 Partial Content\r\n"
            header += "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalSize)\r\n"
        } else {
            header = "HTTP/1.1 200 OK\r\n"
        }
        header += "Content-Type: \(contentType)\r\n"
        header += "Content-Disposition: attachment; filename=\"\(fileName)\"\r\n"
        header += "Content-Length: \(contentLength)\r\n"
        header += "Accept-Ranges: bytes\r\n"
        header += "Connection: close\r\n"
        header += "\r\n"

        // Send header first, then stream file in chunks (avoids loading entire APK into memory)
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }
            self?.streamFileChunked(
                connection: connection,
                filePath: filePath,
                offset: rangeStart,
                remaining: contentLength
            )
        })
    }

    /// Stream file data in chunks to avoid loading entire APK into memory
    /// Uses 512KB chunks for optimal throughput on local network
    private func streamFileChunked(
        connection: NWConnection,
        filePath: String,
        offset: Int64,
        remaining: Int64
    ) {
        guard remaining > 0,
              let fileHandle = FileHandle(forReadingAtPath: filePath) else {
            connection.cancel()
            return
        }

        let chunkSize: Int = 512 * 1024  // 512KB chunks — sweet spot for local WiFi
        fileHandle.seek(toFileOffset: UInt64(offset))

        let readSize = min(Int(remaining), chunkSize)
        let chunk = fileHandle.readData(ofLength: readSize)
        fileHandle.closeFile()

        guard !chunk.isEmpty else {
            connection.cancel()
            return
        }

        let newOffset = offset + Int64(chunk.count)
        let newRemaining = remaining - Int64(chunk.count)

        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil else {
                connection.cancel()
                return
            }

            if newRemaining > 0 {
                // Continue streaming next chunk
                self?.streamFileChunked(
                    connection: connection,
                    filePath: filePath,
                    offset: newOffset,
                    remaining: newRemaining
                )
            } else {
                // Done — close connection
                connection.cancel()
            }
        })
    }

    /// Extract a specific HTTP header value from the raw request
    private static func extractHeader(_ name: String, from request: String) -> String? {
        for line in request.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix(name.lowercased() + ":") {
                let value = String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
                return value
            }
        }
        return nil
    }

    // MARK: - HTML Landing Page

    private func generateLandingHTML() -> String {
        let info = appInfo ?? OTAAppInfo(appName: "App", variant: "", buildType: "", outputFormat: .apk)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let buildDateStr = dateFormatter.string(from: info.buildDate)

        let formatBadge = info.outputFormat == .aab ? "AAB" : "APK"
        let formatColor = info.outputFormat == .aab ? "#8B5CF6" : "#22C55E"
        let downloadWarning = info.outputFormat == .aab
            ? "<p style='color:#F59E0B;font-size:13px;margin-top:8px;'>AAB files need processing before installation.</p>"
            : "<p style='color:#6B7280;font-size:13px;margin-top:8px;'>Tap download and enable \"Install unknown apps\" if prompted.</p>"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(info.appName) - OTA Install</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                       background: linear-gradient(135deg, #0F172A 0%, #1E293B 100%);
                       min-height: 100vh; display: flex; align-items: center; justify-content: center;
                       color: #E2E8F0; padding: 20px; }
                .card { background: #1E293B; border: 1px solid #334155; border-radius: 20px;
                        padding: 32px; max-width: 400px; width: 100%; text-align: center;
                        box-shadow: 0 25px 50px rgba(0,0,0,0.4); }
                .app-icon { width: 72px; height: 72px; background: linear-gradient(135deg, \(formatColor)22, \(formatColor)44);
                           border-radius: 16px; display: flex; align-items: center; justify-content: center;
                           margin: 0 auto 20px; font-size: 32px; }
                h1 { font-size: 22px; font-weight: 700; margin-bottom: 4px; }
                .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 11px;
                        font-weight: 600; background: \(formatColor)22; color: \(formatColor); margin: 4px 2px; }
                .meta { margin: 16px 0; }
                .meta-row { display: flex; justify-content: space-between; padding: 8px 0;
                           border-bottom: 1px solid #334155; font-size: 13px; }
                .meta-label { color: #94A3B8; }
                .meta-value { color: #E2E8F0; font-weight: 500; }
                .download-btn { display: block; width: 100%; padding: 14px; margin-top: 20px;
                               background: \(formatColor); color: white; border: none; border-radius: 12px;
                               font-size: 16px; font-weight: 600; cursor: pointer;
                               text-decoration: none; transition: opacity 0.2s; }
                .download-btn:hover { opacity: 0.9; }
                .changelog { text-align: left; margin-top: 16px; padding: 12px; background: #0F172A;
                            border-radius: 10px; font-size: 12px; color: #94A3B8; }
                .changelog h3 { font-size: 12px; color: #64748B; text-transform: uppercase;
                               letter-spacing: 0.5px; margin-bottom: 6px; }
                .footer { margin-top: 20px; font-size: 11px; color: #475569; }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="app-icon">\(info.outputFormat == .aab ? "📦" : "📱")</div>
                <h1>\(info.appName)</h1>
                <div>
                    <span class="badge">\(formatBadge)</span>
                    <span class="badge">\(info.variant) \(info.buildType)</span>
                    \(info.version.map { "<span class='badge'>v\($0)</span>" } ?? "")
                </div>
                <div class="meta">
                    \(info.version.map { "<div class='meta-row'><span class='meta-label'>Version</span><span class='meta-value'>\($0)\(info.versionCode.map { " (\($0))" } ?? "")</span></div>" } ?? "")
                    <div class="meta-row"><span class="meta-label">Variant</span><span class="meta-value">\(info.variant) \(info.buildType)</span></div>
                    \(info.fileSize.map { "<div class='meta-row'><span class='meta-label'>Size</span><span class='meta-value'>\($0)</span></div>" } ?? "")
                    <div class="meta-row"><span class="meta-label">Built</span><span class="meta-value">\(buildDateStr)</span></div>
                </div>
                <a href="/download" class="download-btn">Download \(formatBadge)</a>
                \(downloadWarning)
                \(info.changelog.map { """
                <div class="changelog">
                    <h3>Changelog</h3>
                    <p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>
                </div>
                """ } ?? "")
                <p class="footer">Served by Ketok</p>
            </div>
        </body>
        </html>
        """
    }

    // MARK: - QR Code

    private func generateQRCode(from string: String) -> NSImage? {
        guard let data = string.data(using: .utf8) else { return nil }

        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        filter?.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter?.outputImage else { return nil }

        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = ciImage.transformed(by: scale)

        let rep = NSCIImageRep(ciImage: scaledImage)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    // MARK: - Network

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

import Foundation
import UserNotifications
import AppKit
import OSLog

/// Notification action identifiers
enum NotificationAction: String {
    case installOnDevice = "INSTALL_ON_DEVICE"
    case revealInFinder = "REVEAL_IN_FINDER"
    case shareFile = "SHARE_FILE"
    case viewLog = "VIEW_LOG"
    case retryBuild = "RETRY_BUILD"
    case startOTA = "START_OTA"
}

/// Notification category identifiers
enum NotificationCategory: String {
    case buildSuccess = "BUILD_SUCCESS"
    case buildFailed = "BUILD_FAILED"
    case installComplete = "INSTALL_COMPLETE"
}

/// Manages macOS native notifications for build events with actionable buttons
class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let logger = Logger(subsystem: "com.ketok.app", category: "NotificationService")

    /// Callbacks for notification actions
    var onInstallRequested: ((String) -> Void)?      // apkPath
    var onRevealRequested: ((String) -> Void)?        // filePath
    var onRetryBuildRequested: (() -> Void)?
    var onViewLogRequested: (() -> Void)?
    var onStartOTARequested: ((String) -> Void)?      // filePath

    /// Store the last build output path for action handling
    private var lastSuccessfulBuildPath: String?

    private override init() {
        super.init()
        requestPermission()
        registerCategories()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted {
                self.logger.warning("Notification permission not granted")
            }
        }
    }

    /// Register notification categories with action buttons
    private func registerCategories() {
        // Build Success actions
        let installAction = UNNotificationAction(
            identifier: NotificationAction.installOnDevice.rawValue,
            title: "Install on Device",
            options: [.foreground]
        )
        let revealAction = UNNotificationAction(
            identifier: NotificationAction.revealInFinder.rawValue,
            title: "Reveal in Finder",
            options: [.foreground]
        )
        let otaAction = UNNotificationAction(
            identifier: NotificationAction.startOTA.rawValue,
            title: "Share via OTA",
            options: [.foreground]
        )

        let successCategory = UNNotificationCategory(
            identifier: NotificationCategory.buildSuccess.rawValue,
            actions: [installAction, revealAction, otaAction],
            intentIdentifiers: [],
            options: []
        )

        // Build Failed actions
        let viewLogAction = UNNotificationAction(
            identifier: NotificationAction.viewLog.rawValue,
            title: "View Log",
            options: [.foreground]
        )
        let retryAction = UNNotificationAction(
            identifier: NotificationAction.retryBuild.rawValue,
            title: "Retry Build",
            options: [.foreground]
        )

        let failedCategory = UNNotificationCategory(
            identifier: NotificationCategory.buildFailed.rawValue,
            actions: [viewLogAction, retryAction],
            intentIdentifiers: [],
            options: []
        )

        // Install Complete actions
        let installCompleteCategory = UNNotificationCategory(
            identifier: NotificationCategory.installComplete.rawValue,
            actions: [revealAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            successCategory, failedCategory, installCompleteCategory
        ])
    }

    // MARK: - Send Notifications

    func sendBuildSuccess(project: String, variant: String, buildType: String, duration: TimeInterval, apkSize: String?, outputPath: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Build Succeeded"
        var body = "\(project) — \(variant) \(buildType) (\(formatDuration(duration)))"
        if let size = apkSize {
            body += " · \(size)"
        }
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.buildSuccess.rawValue

        // Store the output path in userInfo for action handling
        if let path = outputPath {
            content.userInfo = ["outputPath": path, "project": project, "variant": variant, "buildType": buildType]
            lastSuccessfulBuildPath = path
        }

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func sendBuildFailed(project: String, variant: String, buildType: String, error: String) {
        let content = UNMutableNotificationContent()
        content.title = "Build Failed"
        content.body = "\(project) — \(variant) \(buildType)\n\(error)"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Basso"))
        content.categoryIdentifier = NotificationCategory.buildFailed.rawValue
        content.userInfo = ["project": project, "variant": variant, "buildType": buildType]

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func sendInstallSuccess(project: String, device: String) {
        let content = UNMutableNotificationContent()
        content.title = "Install Complete"
        content.body = "\(project) installed on \(device)"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.installComplete.rawValue

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func sendCustomNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Handle notification actions
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let outputPath = userInfo["outputPath"] as? String

        switch response.actionIdentifier {
        case NotificationAction.installOnDevice.rawValue:
            if let path = outputPath ?? lastSuccessfulBuildPath {
                DispatchQueue.main.async {
                    self.onInstallRequested?(path)
                }
            }

        case NotificationAction.revealInFinder.rawValue:
            if let path = outputPath ?? lastSuccessfulBuildPath {
                DispatchQueue.main.async {
                    self.onRevealRequested?(path)
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }

        case NotificationAction.startOTA.rawValue:
            if let path = outputPath ?? lastSuccessfulBuildPath {
                DispatchQueue.main.async {
                    self.onStartOTARequested?(path)
                }
            }

        case NotificationAction.viewLog.rawValue:
            DispatchQueue.main.async {
                self.onViewLogRequested?()
            }

        case NotificationAction.retryBuild.rawValue:
            DispatchQueue.main.async {
                self.onRetryBuildRequested?()
            }

        default:
            break
        }

        completionHandler()
    }

    /// Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Webhook Notifications (Slack / Discord)

    /// Webhook configuration
    struct WebhookConfig: Codable {
        var slackWebhookURL: String?
        var discordWebhookURL: String?
        var enabled: Bool = false
        var notifyOnSuccess: Bool = true
        var notifyOnFailure: Bool = true
        var notifyOnInstall: Bool = false
    }

    /// Current webhook configuration
    var webhookConfig: WebhookConfig {
        get {
            if let data = UserDefaults.standard.data(forKey: "com.ketok.webhooks"),
               let config = try? JSONDecoder().decode(WebhookConfig.self, from: data) {
                return config
            }
            return WebhookConfig()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "com.ketok.webhooks")
            }
        }
    }

    /// Send build success to configured webhooks
    func sendWebhookBuildSuccess(project: String, variant: String, buildType: String, duration: TimeInterval, apkSize: String?, version: String?) {
        guard webhookConfig.enabled && webhookConfig.notifyOnSuccess else { return }

        let durationStr = formatDuration(duration)
        let sizeStr = apkSize ?? "N/A"
        let versionStr = version ?? "unknown"

        // Slack
        if let slackURL = webhookConfig.slackWebhookURL, !slackURL.isEmpty {
            let payload: [String: Any] = [
                "blocks": [
                    [
                        "type": "section",
                        "text": [
                            "type": "mrkdwn",
                            "text": "✅ *Build Succeeded*\n*\(project)* — \(variant) \(buildType)\nVersion: `\(versionStr)` · Duration: \(durationStr) · Size: \(sizeStr)"
                        ]
                    ]
                ]
            ]
            sendWebhook(url: slackURL, payload: payload)
        }

        // Discord
        if let discordURL = webhookConfig.discordWebhookURL, !discordURL.isEmpty {
            let payload: [String: Any] = [
                "embeds": [[
                    "title": "✅ Build Succeeded",
                    "description": "**\(project)** — \(variant) \(buildType)",
                    "color": 3066993,  // Green
                    "fields": [
                        ["name": "Version", "value": versionStr, "inline": true],
                        ["name": "Duration", "value": durationStr, "inline": true],
                        ["name": "Size", "value": sizeStr, "inline": true]
                    ]
                ]]
            ]
            sendWebhook(url: discordURL, payload: payload)
        }
    }

    /// Send build failure to configured webhooks
    func sendWebhookBuildFailed(project: String, variant: String, buildType: String, error: String) {
        guard webhookConfig.enabled && webhookConfig.notifyOnFailure else { return }

        let truncatedError = String(error.prefix(500))

        // Slack
        if let slackURL = webhookConfig.slackWebhookURL, !slackURL.isEmpty {
            let payload: [String: Any] = [
                "blocks": [
                    [
                        "type": "section",
                        "text": [
                            "type": "mrkdwn",
                            "text": "❌ *Build Failed*\n*\(project)* — \(variant) \(buildType)\n```\(truncatedError)```"
                        ]
                    ]
                ]
            ]
            sendWebhook(url: slackURL, payload: payload)
        }

        // Discord
        if let discordURL = webhookConfig.discordWebhookURL, !discordURL.isEmpty {
            let payload: [String: Any] = [
                "embeds": [[
                    "title": "❌ Build Failed",
                    "description": "**\(project)** — \(variant) \(buildType)\n```\(truncatedError)```",
                    "color": 15158332  // Red
                ]]
            ]
            sendWebhook(url: discordURL, payload: payload)
        }
    }

    /// Send install notification to webhooks
    func sendWebhookInstall(project: String, devices: [(name: String, success: Bool)]) {
        guard webhookConfig.enabled && webhookConfig.notifyOnInstall else { return }

        let deviceList = devices.map { "\($0.success ? "✅" : "❌") \($0.name)" }.joined(separator: "\n")

        // Slack
        if let slackURL = webhookConfig.slackWebhookURL, !slackURL.isEmpty {
            let payload: [String: Any] = [
                "text": "📱 *Install — \(project)*\n\(deviceList)"
            ]
            sendWebhook(url: slackURL, payload: payload)
        }

        // Discord
        if let discordURL = webhookConfig.discordWebhookURL, !discordURL.isEmpty {
            let payload: [String: Any] = [
                "embeds": [[
                    "title": "📱 Install — \(project)",
                    "description": deviceList,
                    "color": 3447003  // Blue
                ]]
            ]
            sendWebhook(url: discordURL, payload: payload)
        }
    }

    /// Test webhook connectivity
    func testWebhook(url: String, completion: @escaping (Bool, String) -> Void) {
        let payload: [String: Any] = [
            "text": "🔔 Ketok webhook test — connection successful!"
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let webhookURL = URL(string: url) else {
            completion(false, "Invalid URL")
            return
        }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(false, error.localizedDescription)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if statusCode == 200 || statusCode == 204 {
                completion(true, "Connected successfully")
            } else {
                completion(false, "HTTP \(statusCode)")
            }
        }.resume()
    }

    /// Send webhook payload (fire and forget)
    private func sendWebhook(url: String, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let webhookURL = URL(string: url) else { return }

        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                self.logger.error("Webhook error: \(error.localizedDescription)")
            }
            if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 && statusCode != 204 {
                self.logger.warning("Webhook returned HTTP \(statusCode)")
            }
        }.resume()
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

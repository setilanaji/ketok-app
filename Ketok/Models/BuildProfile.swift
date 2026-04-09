import Foundation

/// A saved build configuration preset
struct BuildProfile: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var projectId: UUID
    var variant: String
    var buildType: String
    var outputFormat: BuildOutputFormat = .apk
    var cleanFirst: Bool = false
    var signingConfigId: UUID?
    var outputFolder: String?
    var postBuildActions: [PostBuildAction] = []
    var notes: String?
    var createdAt: Date = Date()
}

/// Actions that can be performed after a build completes
enum PostBuildActionType: String, Codable, Hashable, CaseIterable {
    case installOnDevice = "install"
    case installOnAll = "install_all"
    case copyToFolder = "copy"
    case openInFinder = "finder"
    case generateQR = "qr"
    case runLogcat = "logcat"
    case startOTA = "ota"
    case gitTag = "git_tag"

    var displayName: String {
        switch self {
        case .installOnDevice: return "Install on Device"
        case .installOnAll: return "Install on All Devices"
        case .copyToFolder: return "Copy to Folder"
        case .openInFinder: return "Reveal in Finder"
        case .generateQR: return "Generate QR Code"
        case .runLogcat: return "Start Logcat"
        case .startOTA: return "Start OTA Server"
        case .gitTag: return "Git Tag Release"
        }
    }

    var icon: String {
        switch self {
        case .installOnDevice: return "iphone.and.arrow.forward"
        case .installOnAll: return "iphone.gen3.radiowaves.left.and.right"
        case .copyToFolder: return "folder.badge.plus"
        case .openInFinder: return "folder"
        case .generateQR: return "qrcode"
        case .runLogcat: return "terminal"
        case .startOTA: return "antenna.radiowaves.left.and.right"
        case .gitTag: return "tag.fill"
        }
    }
}

/// A configured post-build action with optional parameters
struct PostBuildAction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: PostBuildActionType
    var enabled: Bool = true
    var parameter: String?  // e.g., folder path for copy, device id for install
}

/// Manages build profiles
class BuildProfileStore: ObservableObject {
    @Published var profiles: [BuildProfile] = []

    private let storageKey = "com.ketok.buildprofiles"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([BuildProfile].self, from: data) {
            profiles = saved
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addProfile(_ profile: BuildProfile) {
        profiles.append(profile)
        save()
    }

    func updateProfile(_ profile: BuildProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            save()
        }
    }

    func removeProfile(_ profile: BuildProfile) {
        profiles.removeAll { $0.id == profile.id }
        save()
    }

    func profilesFor(projectId: UUID) -> [BuildProfile] {
        profiles.filter { $0.projectId == projectId }
    }
}

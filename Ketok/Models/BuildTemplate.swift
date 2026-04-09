import Foundation

/// A build template is a pre-configured pipeline of build steps
struct BuildTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var description: String?
    var steps: [BuildTemplateStep]
    var createdAt: Date = Date()
    var icon: String = "rectangle.stack.fill"

    /// Total estimated duration based on step types
    var estimatedDuration: String? {
        let totalMinutes = steps.reduce(0) { sum, step in
            sum + step.type.estimatedMinutes
        }
        if totalMinutes > 0 {
            return "\(totalMinutes)m est."
        }
        return nil
    }
}

/// A single step within a build template pipeline
struct BuildTemplateStep: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: StepType
    var enabled: Bool = true
    var parameter: String?  // e.g., device ID for install, path for copy

    enum StepType: String, Codable, Hashable, CaseIterable {
        case clean = "clean"
        case buildAPK = "build_apk"
        case buildAAB = "build_aab"
        case installOnDevice = "install"
        case installOnAll = "install_all"
        case copyToFolder = "copy"
        case revealInFinder = "reveal"
        case generateQR = "qr"
        case startOTA = "ota"
        case runLogcat = "logcat"
        case gitTag = "git_tag"

        var displayName: String {
            switch self {
            case .clean: return "Clean Build"
            case .buildAPK: return "Build APK"
            case .buildAAB: return "Build AAB"
            case .installOnDevice: return "Install on Device"
            case .installOnAll: return "Install on All Devices"
            case .copyToFolder: return "Copy to Folder"
            case .revealInFinder: return "Reveal in Finder"
            case .generateQR: return "Generate QR Code"
            case .startOTA: return "Start OTA Server"
            case .runLogcat: return "Start Logcat"
            case .gitTag: return "Git Tag Release"
            }
        }

        var icon: String {
            switch self {
            case .clean: return "trash"
            case .buildAPK: return "paperplane.fill"
            case .buildAAB: return "shippingbox.fill"
            case .installOnDevice: return "iphone.and.arrow.forward"
            case .installOnAll: return "iphone.gen3.radiowaves.left.and.right"
            case .copyToFolder: return "folder.badge.plus"
            case .revealInFinder: return "folder"
            case .generateQR: return "qrcode"
            case .startOTA: return "antenna.radiowaves.left.and.right"
            case .runLogcat: return "terminal"
            case .gitTag: return "tag.fill"
            }
        }

        /// Estimated duration in minutes
        var estimatedMinutes: Int {
            switch self {
            case .clean: return 1
            case .buildAPK, .buildAAB: return 3
            case .installOnDevice, .installOnAll: return 1
            default: return 0
            }
        }

        /// Whether this step needs a parameter
        var needsParameter: Bool {
            switch self {
            case .installOnDevice, .copyToFolder, .gitTag: return true
            default: return false
            }
        }

        var parameterLabel: String? {
            switch self {
            case .installOnDevice: return "Device ID"
            case .copyToFolder: return "Folder Path"
            case .gitTag: return "Tag Name (e.g., v{version})"
            default: return nil
            }
        }
    }
}

/// Pre-defined build templates
extension BuildTemplate {
    static let quickDebug = BuildTemplate(
        name: "Quick Debug",
        description: "Build debug APK and install on device",
        steps: [
            BuildTemplateStep(type: .buildAPK),
            BuildTemplateStep(type: .installOnDevice)
        ],
        icon: "bolt.fill"
    )

    static let releaseBundle = BuildTemplate(
        name: "Release Bundle",
        description: "Clean build release AAB for Play Store",
        steps: [
            BuildTemplateStep(type: .clean),
            BuildTemplateStep(type: .buildAAB),
            BuildTemplateStep(type: .revealInFinder)
        ],
        icon: "shippingbox.fill"
    )

    static let qaDistribution = BuildTemplate(
        name: "QA Distribution",
        description: "Build, generate QR, and start OTA server",
        steps: [
            BuildTemplateStep(type: .buildAPK),
            BuildTemplateStep(type: .startOTA),
            BuildTemplateStep(type: .generateQR)
        ],
        icon: "person.3.fill"
    )

    static let fullRelease = BuildTemplate(
        name: "Full Release",
        description: "Clean, build release, tag git, copy to folder",
        steps: [
            BuildTemplateStep(type: .clean),
            BuildTemplateStep(type: .buildAAB),
            BuildTemplateStep(type: .gitTag, parameter: "v{version}"),
            BuildTemplateStep(type: .copyToFolder),
            BuildTemplateStep(type: .revealInFinder)
        ],
        icon: "star.fill"
    )

    /// All pre-made templates
    static let builtIn: [BuildTemplate] = [quickDebug, releaseBundle, qaDistribution, fullRelease]
}

/// Manages build templates
class BuildTemplateStore: ObservableObject {
    @Published var templates: [BuildTemplate] = []

    private let storageKey = "com.ketok.buildtemplates"

    init() {
        load()
        // Add built-in templates if none exist
        if templates.isEmpty {
            templates = BuildTemplate.builtIn
            save()
        }
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([BuildTemplate].self, from: data) {
            templates = saved
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addTemplate(_ template: BuildTemplate) {
        templates.append(template)
        save()
    }

    func updateTemplate(_ template: BuildTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            save()
        }
    }

    func removeTemplate(_ template: BuildTemplate) {
        templates.removeAll { $0.id == template.id }
        save()
    }

    func resetToDefaults() {
        templates = BuildTemplate.builtIn
        save()
    }
}

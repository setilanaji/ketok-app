import Foundation
import Security

/// Represents a keystore signing configuration for release builds
struct SigningConfig: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String                  // e.g. "Production", "Upload Key"
    var keystorePath: String          // Path to .jks or .keystore file
    var keystorePassword: String      // Stored in Keychain, placeholder here
    var keyAlias: String              // Key alias inside the keystore
    var keyPassword: String           // Key password, often same as keystore password
    var projectId: UUID?              // If nil, available to all projects

    var keystoreExists: Bool {
        FileManager.default.fileExists(atPath: keystorePath)
    }

    var keystoreFileName: String {
        (keystorePath as NSString).lastPathComponent
    }

    /// Returns Gradle command-line signing args — passwords are referenced via env vars, not embedded
    func gradleSigningArgs() -> [String] {
        return [
            "-Pandroid.injected.signing.store.file=\(keystorePath)",
            "-Pandroid.injected.signing.store.password=$KETOK_STORE_PASS",
            "-Pandroid.injected.signing.key.alias=\(keyAlias)",
            "-Pandroid.injected.signing.key.password=$KETOK_KEY_PASS"
        ]
    }

    /// Returns signing passwords as process environment variables — keeps them out of command line and logs
    func gradleSigningEnvVars() -> [String: String] {
        return [
            "KETOK_STORE_PASS": keystorePassword,
            "KETOK_KEY_PASS": keyPassword
        ]
    }
}

/// Manages signing configurations with Keychain-backed password storage
class SigningConfigStore: ObservableObject {
    @Published var configs: [SigningConfig] = []
    @Published var enableSignedBuilds: Bool = false {
        didSet { UserDefaults.standard.set(enableSignedBuilds, forKey: "enableSignedBuilds") }
    }

    private let storageKey = "signingConfigs"
    private let keychainService = "com.ketok.signing"

    init() {
        enableSignedBuilds = UserDefaults.standard.bool(forKey: "enableSignedBuilds")
        loadConfigs()
    }

    // MARK: - CRUD

    func addConfig(_ config: SigningConfig) {
        var saved = config
        // Store passwords in Keychain, clear from config
        savePasswordToKeychain(id: saved.id, key: "keystorePassword", password: saved.keystorePassword)
        savePasswordToKeychain(id: saved.id, key: "keyPassword", password: saved.keyPassword)
        saved.keystorePassword = ""
        saved.keyPassword = ""

        configs.append(saved)
        saveConfigs()
    }

    func updateConfig(_ config: SigningConfig) {
        guard let idx = configs.firstIndex(where: { $0.id == config.id }) else { return }
        var saved = config

        // Update passwords in Keychain if non-empty (user changed them)
        if !saved.keystorePassword.isEmpty {
            savePasswordToKeychain(id: saved.id, key: "keystorePassword", password: saved.keystorePassword)
        }
        if !saved.keyPassword.isEmpty {
            savePasswordToKeychain(id: saved.id, key: "keyPassword", password: saved.keyPassword)
        }
        saved.keystorePassword = ""
        saved.keyPassword = ""

        configs[idx] = saved
        saveConfigs()
    }

    func removeConfig(_ config: SigningConfig) {
        deletePasswordFromKeychain(id: config.id, key: "keystorePassword")
        deletePasswordFromKeychain(id: config.id, key: "keyPassword")
        configs.removeAll { $0.id == config.id }
        saveConfigs()
    }

    /// Get the signing config for a project (project-specific first, then global)
    func configForProject(_ projectId: UUID) -> SigningConfig? {
        guard enableSignedBuilds else { return nil }
        // Try project-specific first
        if let specific = configs.first(where: { $0.projectId == projectId }) {
            return resolvedConfig(specific)
        }
        // Fall back to global (projectId == nil)
        if let global = configs.first(where: { $0.projectId == nil }) {
            return resolvedConfig(global)
        }
        return nil
    }

    /// Returns a config with passwords resolved from Keychain
    func resolvedConfig(_ config: SigningConfig) -> SigningConfig {
        var resolved = config
        resolved.keystorePassword = loadPasswordFromKeychain(id: config.id, key: "keystorePassword") ?? ""
        resolved.keyPassword = loadPasswordFromKeychain(id: config.id, key: "keyPassword") ?? ""
        return resolved
    }

    // MARK: - Persistence (UserDefaults for config metadata, Keychain for passwords)

    private func saveConfigs() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func loadConfigs() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([SigningConfig].self, from: data) else { return }
        configs = saved
    }

    // MARK: - Keychain

    private func keychainAccount(id: UUID, key: String) -> String {
        "\(id.uuidString).\(key)"
    }

    private func savePasswordToKeychain(id: UUID, key: String, password: String) {
        let account = keychainAccount(id: id, key: key)
        let data = Data(password.utf8)

        // Delete existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new entry
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func loadPasswordFromKeychain(id: UUID, key: String) -> String? {
        let account = keychainAccount(id: id, key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deletePasswordFromKeychain(id: UUID, key: String) {
        let account = keychainAccount(id: id, key: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

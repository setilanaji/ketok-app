import Foundation
import AppKit

/// Plays sound effects for build events
class BuildSoundService: ObservableObject {
    static let shared = BuildSoundService()

    @Published var soundEnabled: Bool {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "com.ketok.soundEnabled") }
    }

    @Published var selectedSuccessSound: String {
        didSet { UserDefaults.standard.set(selectedSuccessSound, forKey: "com.ketok.successSound") }
    }

    @Published var selectedFailSound: String {
        didSet { UserDefaults.standard.set(selectedFailSound, forKey: "com.ketok.failSound") }
    }

    /// Available system sounds
    static let availableSounds: [String] = [
        "Glass", "Blow", "Bottle", "Frog", "Funk", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]

    private init() {
        soundEnabled = UserDefaults.standard.object(forKey: "com.ketok.soundEnabled") as? Bool ?? true
        selectedSuccessSound = UserDefaults.standard.string(forKey: "com.ketok.successSound") ?? "Glass"
        selectedFailSound = UserDefaults.standard.string(forKey: "com.ketok.failSound") ?? "Sosumi"
    }

    /// Play the success sound
    func playSuccess() {
        guard soundEnabled else { return }
        playSystemSound(selectedSuccessSound)
    }

    /// Play the failure sound
    func playFailure() {
        guard soundEnabled else { return }
        playSystemSound(selectedFailSound)
    }

    /// Play build started sound (subtle)
    func playBuildStarted() {
        guard soundEnabled else { return }
        playSystemSound("Tink")
    }

    private func playSystemSound(_ name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        }
    }
}

import Foundation

/// A pinned build configuration for quick access
struct FavoriteBuild: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var projectId: UUID
    var variant: String
    var buildType: String
    var label: String?  // optional custom label

    var displayLabel: String {
        label ?? "\(variant) \(buildType)"
    }
}

/// Manages favorite build configurations
class FavoriteStore: ObservableObject {
    @Published var favorites: [FavoriteBuild] = []

    private let storageKey = "com.ketok.favorites"

    init() {
        load()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([FavoriteBuild].self, from: data) {
            favorites = saved
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addFavorite(projectId: UUID, variant: String, buildType: String, label: String? = nil) {
        // Don't add duplicates
        guard !favorites.contains(where: {
            $0.projectId == projectId && $0.variant == variant && $0.buildType == buildType
        }) else { return }

        favorites.append(FavoriteBuild(
            projectId: projectId,
            variant: variant,
            buildType: buildType,
            label: label
        ))
        save()
    }

    func removeFavorite(_ favorite: FavoriteBuild) {
        favorites.removeAll { $0.id == favorite.id }
        save()
    }

    func isFavorite(projectId: UUID, variant: String, buildType: String) -> Bool {
        favorites.contains {
            $0.projectId == projectId && $0.variant == variant && $0.buildType == buildType
        }
    }

    func favoritesFor(projectId: UUID) -> [FavoriteBuild] {
        favorites.filter { $0.projectId == projectId }
    }
}

import Foundation
import AppKit

/// Exportable settings bundle
struct SettingsBundle: Codable {
    let version: Int
    let exportDate: Date
    let projects: [AndroidProject]
    let favorites: [FavoriteBuild]
    let signingEnabled: Bool
    // Note: signing configs with passwords are NOT exported for security
    let buildRecords: [BuildRecord]?

    static let currentVersion = 1
}

/// Handles export and import of all app settings
enum SettingsExporter {

    /// Export settings to a JSON file. Returns the file path or nil if cancelled.
    static func exportSettings(
        projectStore: ProjectStore,
        favoriteStore: FavoriteStore,
        signingStore: SigningConfigStore,
        buildStatsStore: BuildStatsStore
    ) -> String? {
        let bundle = SettingsBundle(
            version: SettingsBundle.currentVersion,
            exportDate: Date(),
            projects: projectStore.projects,
            favorites: favoriteStore.favorites,
            signingEnabled: signingStore.enableSignedBuilds,
            buildRecords: buildStatsStore.records
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(bundle) else { return nil }

        let panel = NSSavePanel()
        panel.title = "Export Ketok Settings"
        panel.nameFieldStringValue = "ketok-settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        do {
            try data.write(to: url)
            return url.path
        } catch {
            return nil
        }
    }

    /// Import settings from a JSON file. Returns a summary or nil if cancelled.
    static func importSettings(
        projectStore: ProjectStore,
        favoriteStore: FavoriteStore,
        signingStore: SigningConfigStore,
        buildStatsStore: BuildStatsStore
    ) -> String? {
        let panel = NSOpenPanel()
        panel.title = "Import Ketok Settings"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let bundle = try? decoder.decode(SettingsBundle.self, from: data) else {
            return nil
        }

        var summary: [String] = []

        // Import projects (merge, skip duplicates by path)
        let existingPaths = Set(projectStore.projects.map { $0.path })
        var newProjectCount = 0
        for project in bundle.projects {
            if !existingPaths.contains(project.path) {
                projectStore.addProject(project)
                newProjectCount += 1
            }
        }
        summary.append("\(newProjectCount) new project\(newProjectCount == 1 ? "" : "s")")

        // Import favorites (merge, skip duplicates)
        var newFavCount = 0
        for fav in bundle.favorites {
            if !favoriteStore.isFavorite(projectId: fav.projectId, variant: fav.variant, buildType: fav.buildType) {
                favoriteStore.addFavorite(projectId: fav.projectId, variant: fav.variant, buildType: fav.buildType)
                newFavCount += 1
            }
        }
        summary.append("\(newFavCount) favorite\(newFavCount == 1 ? "" : "s")")

        // Import build records
        if let records = bundle.buildRecords {
            let existingIds = Set(buildStatsStore.records.map { $0.id })
            var newRecordCount = 0
            for record in records {
                if !existingIds.contains(record.id) {
                    buildStatsStore.records.append(record)
                    newRecordCount += 1
                }
            }
            buildStatsStore.saveRecords()
            summary.append("\(newRecordCount) build record\(newRecordCount == 1 ? "" : "s")")
        }

        return "Imported: " + summary.joined(separator: ", ")
    }
}

import Foundation
import Combine

/// Persists project configurations using UserDefaults
class ProjectStore: ObservableObject {
    @Published var projects: [AndroidProject] = []

    private let storageKey = "com.ketok.projects"

    init() {
        loadProjects()
    }

    func loadProjects() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([AndroidProject].self, from: data) {
            projects = saved
        } else {
            // First launch: use defaults
            projects = AndroidProject.defaultProjects
            saveProjects()
        }
    }

    func saveProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func addProject(_ project: AndroidProject) {
        projects.append(project)
        saveProjects()
    }

    func removeProject(at offsets: IndexSet) {
        projects.remove(atOffsets: offsets)
        saveProjects()
    }

    func updateProject(_ project: AndroidProject) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            saveProjects()
        }
    }
}

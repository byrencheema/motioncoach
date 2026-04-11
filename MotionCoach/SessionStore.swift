import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [DrillSession] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let defaultURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("motioncoach-sessions.json")

        self.fileURL = fileURL ?? defaultURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("motioncoach-sessions.json")
        load()
    }

    func add(_ session: DrillSession) {
        sessions.insert(session, at: 0)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else {
            sessions = []
            return
        }

        do {
            sessions = try JSONDecoder().decode([DrillSession].self, from: data)
        } catch {
            sessions = []
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save sessions: \(error)")
        }
    }
}

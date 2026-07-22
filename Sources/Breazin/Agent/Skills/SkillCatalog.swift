import Foundation

/// One entry in the published catalog.json. `sha` is a content hash of the SKILL.md
/// and is the version anchor: a changed sha means an update is available.
struct SkillCatalogEntry: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let sha: String
    let path: String
}

/// Fetches an explicitly configured community skill catalog.
@Observable
@MainActor
final class SkillCatalog {
    static let shared = SkillCatalog()

    /// No public Breazin catalog is assumed to exist. Set BREAZIN_SKILLS_BASE to a
    /// trusted HTTPS endpoint or local file URL when a catalog is available.
    static var base: String? {
        ProcessInfo.processInfo.environment["BREAZIN_SKILLS_BASE"]
    }

    private(set) var entries: [SkillCatalogEntry] = []
    private(set) var isLoading = false
    private(set) var lastError: String?

    private static var cacheURL: URL {
        DiskCache.rootDirectory.appendingPathComponent("skills-catalog.json")
    }

    private init() { loadCache() }

    func entry(id: String) -> SkillCatalogEntry? { entries.first { $0.id == id } }

    static func bodyURL(path: String) -> URL? {
        guard let base else { return nil }
        return URL(string: "\(base)/\(path)")
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([SkillCatalogEntry].self, from: data)
        else { return }
        entries = decoded
    }

    func refresh() async {
        guard !isLoading, let base = Self.base, let url = URL(string: "\(base)/catalog.json") else {
            lastError = "Community catalog is not configured."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await Self.fetch(url)
            entries = try JSONDecoder().decode([SkillCatalogEntry].self, from: data)
            lastError = nil
            try? FileManager.default.createDirectory(
                at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: Self.cacheURL)
            Log.agent.notice("skill catalog loaded \(self.entries.count) entries from \(base)")
        } catch {
            lastError = error.localizedDescription
            Log.agent.error("skill catalog refresh failed (\(base)): \(error.localizedDescription)")
        }
    }

    /// Reads a catalog/body URL. File URLs are read directly
    static func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

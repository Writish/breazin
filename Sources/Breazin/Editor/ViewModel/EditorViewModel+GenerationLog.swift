import Foundation

/// Append-only record of every AI generation in the project. Persisted as `generation-log.json`
struct GenerationLog: Codable, Sendable, Equatable {
    var version: Int = 1
    var entries: [GenerationLogEntry] = []
}

/// One row in the Project Activity log.
///
/// Decoding deliberately ignores the legacy `cost` and `costCredits` fields.
/// New project saves no longer persist product credits.
struct GenerationLogEntry: Codable, Sendable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    let model: String
    let createdAt: Date?

    init(id: String = UUID().uuidString, model: String, createdAt: Date?) {
        self.id = id
        self.model = model
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, model, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.model = try c.decode(String.self, forKey: .model)
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

@MainActor
extension GenerationLogEntry {
    var modelDisplayName: String {
        ModelRegistry.displayName(for: model)
    }

    var sfSymbolName: String {
        switch ModelRegistry.byId[model] {
        case .video?:   "video.fill"
        case .image?:   "photo.fill"
        case .audio?:   "music.note"
        case .upscale?: "arrow.up.right.square.fill"
        case nil:       "sparkles"
        }
    }
}

extension EditorViewModel {

    var generationLogEntries: [GenerationLogEntry] {
        generationLog.entries.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?): return l > r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.id < rhs.id
            }
        }
    }

    func appendGenerationLog(for asset: MediaAsset) {
        guard let gen = asset.generationInput else { return }
        generationLog.entries.append(GenerationLogEntry(
            model: gen.model,
            createdAt: gen.createdAt
        ))
    }

    /// For old projects saved before the persistent log existed:
    func seedGenerationLogFromAssets() {
        guard generationLog.entries.isEmpty else { return }
        generationLog.entries = mediaAssets.compactMap { asset in
            guard let gen = asset.generationInput else { return nil }
            return GenerationLogEntry(
                model: gen.model,
                createdAt: gen.createdAt
            )
        }
    }
}

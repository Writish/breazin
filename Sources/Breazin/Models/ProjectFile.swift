import Foundation

/// Root of project.json. Legacy projects stored a bare Timeline; decode falls back and wraps.
struct ProjectFile: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = currentSchemaVersion
    var timelines: [Timeline]
    var activeTimelineId: String?
    var openTimelineIds: [String]?
    var viewStates: [String: TimelineViewState]?
    var speakers: [SpeakerRegistryEntry]?
    var multicamGroups: [MulticamSource]?

    static func decode(_ data: Data) throws -> ProjectFile {
        let decoder = JSONDecoder()
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = object["schemaVersion"] as? Int,
           version > currentSchemaVersion {
            throw ProjectSchemaError.unsupportedProjectVersion(
                found: version,
                supported: currentSchemaVersion
            )
        }
        do {
            let file = try decoder.decode(ProjectFile.self, from: data)
            guard !file.timelines.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "project has no timelines"))
            }
            return file
        } catch {
            // Legacy files are a bare Timeline; anything else rethrows the real error.
            guard let legacy = try? decoder.decode(Timeline.self, from: data) else { throw error }
            return ProjectFile(
                schemaVersion: currentSchemaVersion,
                timelines: [legacy],
                activeTimelineId: legacy.id,
                openTimelineIds: [legacy.id]
            )
        }
    }

    init(
        schemaVersion: Int = currentSchemaVersion,
        timelines: [Timeline],
        activeTimelineId: String? = nil,
        openTimelineIds: [String]? = nil,
        viewStates: [String: TimelineViewState]? = nil,
        speakers: [SpeakerRegistryEntry]? = nil,
        multicamGroups: [MulticamSource]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.timelines = timelines
        self.activeTimelineId = activeTimelineId
        self.openTimelineIds = openTimelineIds
        self.viewStates = viewStates
        self.speakers = speakers
        self.multicamGroups = multicamGroups
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard version <= Self.currentSchemaVersion else {
            throw ProjectSchemaError.unsupportedProjectVersion(
                found: version,
                supported: Self.currentSchemaVersion
            )
        }
        schemaVersion = Self.currentSchemaVersion
        timelines = try c.decode([Timeline].self, forKey: .timelines)
        activeTimelineId = try c.decodeIfPresent(String.self, forKey: .activeTimelineId)
        openTimelineIds = try c.decodeIfPresent([String].self, forKey: .openTimelineIds)
        viewStates = try c.decodeIfPresent([String: TimelineViewState].self, forKey: .viewStates)
        speakers = try c.decodeIfPresent([SpeakerRegistryEntry].self, forKey: .speakers)
        multicamGroups = try c.decodeIfPresent([MulticamSource].self, forKey: .multicamGroups)
    }
}

enum ProjectSchemaError: LocalizedError, Equatable {
    case unsupportedProjectVersion(found: Int, supported: Int)
    case unsupportedManifestVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedProjectVersion(let found, let supported):
            "This project uses schema \(found), but this version of Breazin supports up to \(supported). Update Breazin to open it; the project was not modified."
        case .unsupportedManifestVersion(let found, let supported):
            "This media manifest uses schema \(found), but this version of Breazin supports up to \(supported). Update Breazin to open it; the project was not modified."
        }
    }
}

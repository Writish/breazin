import Foundation

enum ToolCapabilityLevel: Int, Sendable, Comparable {
    case readProject = 0
    case reversibleEdit = 1
    case externalOrPaid = 2
    case highImpact = 3
    case forbidden = 4

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum ToolPolicySource: Sendable {
    case inAppAgent
    case externalMCP
}

enum ToolPolicyDecision: Equatable, Sendable {
    case allow
    case approvalRequired(reason: String)
    case deny(reason: String)
}

struct AgentToolApprovalRequest: Identifiable, Equatable, Sendable {
    let id: String
    let toolName: String
    let level: ToolCapabilityLevel

    var title: String {
        level == .highImpact ? "Confirm high-impact action" : "Confirm external or paid action"
    }

    var detail: String {
        switch level {
        case .externalOrPaid:
            "The AI Chat wants to run \(toolName). This may upload data, access a selected file, export, or incur provider charges."
        case .highImpact:
            "The AI Chat wants to run \(toolName). This can change project settings, delete content, cancel work, or otherwise have broad impact."
        default:
            "The AI Chat wants to run \(toolName)."
        }
    }
}

/// One policy shared by the in-app agent and external MCP. External MCP is
/// deliberately read-only unless the user explicitly enables reversible edits.
enum ToolCapabilityPolicy {
    private static let inAppEditsKey = "\(AppConfiguration.current.preferencesPrefix).agent.reversible-edits"

    static var inAppReversibleEditsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: inAppEditsKey) }
        set { UserDefaults.standard.set(newValue, forKey: inAppEditsKey) }
    }

    static func level(for tool: ToolName, args: [String: Any] = [:]) -> ToolCapabilityLevel {
        switch tool {
        case .getTimeline, .inspectTimeline, .getMedia, .inspectMedia, .searchMedia,
             .getMulticam, .getTranscript, .detectBeats, .inspectColor, .listModels,
             .getGenerationStatus, .readSkill:
            return .readProject

        case .createTimeline, .setActiveTimeline, .captureFrame, .manageTracks,
             .addClips, .insertClips, .moveClips, .removeClips, .splitClips,
             .rippleDeleteRanges, .setClipProperties, .setKeyframes, .applyLayout,
             .syncClips, .undo, .manageMulticam, .changeCam, .removeWords,
             .removeSilence, .addTexts, .updateText, .addCaptions, .applyColor,
             .applyEffect, .denoiseAudio:
            return .reversibleEdit

        case .importMedia, .exportProject, .generateVideo, .generateImage:
            return .externalOrPaid

        case .manageProject, .setProjectSettings:
            return .highImpact

        case .manageExports:
            return (args["action"] as? String) == "cancel" ? .highImpact : .readProject

        case .organizeMedia:
            return ((args["deletes"] as? [Any])?.isEmpty == false) ? .highImpact : .reversibleEdit
        }
    }

    static func decision(
        for tool: ToolName,
        args: [String: Any] = [:],
        source: ToolPolicySource,
        externalReversibleEditsEnabled: Bool = false,
        inAppReversibleEditsEnabled: Bool = Self.inAppReversibleEditsEnabled
    ) -> ToolPolicyDecision {
        let capability = level(for: tool, args: args)
        switch (source, capability) {
        case (_, .forbidden):
            return .deny(reason: "This capability is forbidden in Breazin.")
        case (.externalMCP, .readProject):
            return .allow
        case (.externalMCP, .reversibleEdit) where externalReversibleEditsEnabled:
            return .allow
        case (.externalMCP, .reversibleEdit):
            return .approvalRequired(reason: "Enable reversible MCP edits in Settings > Agent.")
        case (.externalMCP, .externalOrPaid):
            return .approvalRequired(reason: "External imports, exports, uploads, and paid generation require an in-app approval and are unavailable to unattended MCP sessions.")
        case (.externalMCP, .highImpact):
            return .deny(reason: "High-impact project operations must be performed and confirmed in the Breazin app.")
        case (.inAppAgent, .readProject):
            return .allow
        case (.inAppAgent, .reversibleEdit) where inAppReversibleEditsEnabled:
            return .allow
        case (.inAppAgent, .reversibleEdit):
            return .approvalRequired(reason: "Enable AI Chat reversible edits in Settings > Agent.")
        case (.inAppAgent, .externalOrPaid):
            return .approvalRequired(reason: "This external or paid action needs confirmation in the Breazin app.")
        case (.inAppAgent, .highImpact):
            return .approvalRequired(reason: "This high-impact action always needs confirmation in the Breazin app.")
        }
    }
}

import Foundation
import Testing
@testable import Breazin

@Suite("Agent tool capability policy")
struct ToolCapabilityPolicyTests {
    @Test func everyAdvertisedToolHasAClassifiedLevel() {
        let names = Set(ToolDefinitions.mcpServer.map(\.name))
        let classified = Set(names.map { ($0, ToolCapabilityPolicy.level(for: $0).rawValue).0 })
        #expect(classified == names)
    }

    @Test func externalMCPDefaultsToReadOnly() {
        #expect(ToolCapabilityPolicy.decision(
            for: .getTimeline,
            source: .externalMCP,
            externalReversibleEditsEnabled: false
        ) == .allow)
        #expect(ToolCapabilityPolicy.decision(
            for: .addClips,
            source: .externalMCP,
            externalReversibleEditsEnabled: false
        ) == .approvalRequired(reason: "Enable reversible MCP edits in Settings > Agent."))
    }

    @Test func enablingExternalEditsDoesNotAuthorizePaidOrHighImpactTools() {
        #expect(ToolCapabilityPolicy.decision(
            for: .addClips,
            source: .externalMCP,
            externalReversibleEditsEnabled: true
        ) == .allow)
        #expect(ToolCapabilityPolicy.decision(
            for: .generateVideo,
            source: .externalMCP,
            externalReversibleEditsEnabled: true
        ) != .allow)
        #expect(ToolCapabilityPolicy.decision(
            for: .setProjectSettings,
            source: .externalMCP,
            externalReversibleEditsEnabled: true
        ) != .allow)
    }

    @Test func destructiveOrganizeAndExportCancellationAreHighImpact() {
        #expect(ToolCapabilityPolicy.level(for: .organizeMedia, args: ["deletes": ["asset"]]) == .highImpact)
        #expect(ToolCapabilityPolicy.level(for: .manageExports, args: ["action": "cancel"]) == .highImpact)
        #expect(ToolCapabilityPolicy.level(for: .manageExports, args: ["action": "list"]) == .readProject)
    }
}

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

    @Test func inAppAgentRequiresEditSettingAndPerActionHighRiskApproval() {
        #expect(ToolCapabilityPolicy.decision(
            for: .addClips,
            source: .inAppAgent,
            inAppReversibleEditsEnabled: false
        ) == .approvalRequired(reason: "Enable AI Chat reversible edits in Settings > Agent."))
        #expect(ToolCapabilityPolicy.decision(
            for: .addClips,
            source: .inAppAgent,
            inAppReversibleEditsEnabled: true
        ) == .allow)
        #expect(ToolCapabilityPolicy.decision(
            for: .generateImage,
            source: .inAppAgent,
            inAppReversibleEditsEnabled: true
        ) == .approvalRequired(reason: "This external or paid action needs confirmation in the Breazin app."))
        #expect(ToolCapabilityPolicy.decision(
            for: .setProjectSettings,
            source: .inAppAgent,
            inAppReversibleEditsEnabled: true
        ) == .approvalRequired(reason: "This high-impact action always needs confirmation in the Breazin app."))
    }
}

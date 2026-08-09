import Testing
@testable import Breazin

@Suite("Agent tool approval")
@MainActor
struct AgentToolApprovalTests {
    @Test func approvalIsBoundToOnePendingToolCall() async {
        let service = AgentService()
        let task = Task {
            await service.requestToolApproval(
                id: "tool-use-1",
                tool: .generateImage,
                level: .externalOrPaid
            )
        }
        await Task.yield()

        #expect(service.pendingToolApproval == AgentToolApprovalRequest(
            id: "tool-use-1",
            toolName: ToolName.generateImage.rawValue,
            level: .externalOrPaid
        ))
        service.approvePendingTool()

        #expect(await task.value)
        #expect(service.pendingToolApproval == nil)
    }

    @Test func cancellationDeniesAndClearsPendingApproval() async {
        let service = AgentService()
        let task = Task {
            await service.requestToolApproval(
                id: "tool-use-2",
                tool: .setProjectSettings,
                level: .highImpact
            )
        }
        await Task.yield()
        #expect(service.pendingToolApproval?.id == "tool-use-2")

        task.cancel()
        #expect(await task.value == false)
        #expect(service.pendingToolApproval == nil)
    }
}

import Foundation
import Testing
@testable import Breazin

@Suite("Agent chat providers")
struct AgentProviderTests {
    @Test func providerModelsStayIsolated() {
        #expect(AgentChatProvider.anthropic.models.allSatisfy { $0.provider == .anthropic })
        #expect(AgentChatProvider.deepSeek.models.allSatisfy { $0.provider == .deepSeek })
        #expect(AgentChatProvider.deepSeek.models.map(\.rawValue) == [
            "deepseek-v4-flash",
            "deepseek-v4-pro",
        ])
    }

    @Test func deepSeekRequestKeepsToolsAndReplacesUnsupportedImages() throws {
        let messages = [
            AnthropicMessage(role: .user, content: [
                ["type": "text", "text": "Inspect this frame"],
                ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": "abc"]],
            ]),
            AnthropicMessage(role: .assistant, content: [
                ["type": "tool_use", "id": "call-1", "name": "inspect_timeline", "input": [:]],
            ]),
            AnthropicMessage(role: .user, content: [
                [
                    "type": "tool_result",
                    "tool_use_id": "call-1",
                    "content": [
                        ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": "abc"]],
                        ["type": "text", "text": "frame 42"],
                    ],
                ],
            ]),
        ]
        let tools = [
            AnthropicToolSchema(name: "inspect_timeline", description: "Inspect", inputSchema: ["type": "object"]),
        ]

        let body = AnthropicRequestBody.build(
            model: .deepSeekV4Flash,
            maxTokens: 1024,
            system: "System",
            tools: tools,
            messages: messages,
            supportsImages: false
        )
        let encoded = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(body["model"] as? String == "deepseek-v4-flash")
        #expect(json.contains("inspect_timeline"))
        #expect(json.contains("frame 42"))
        #expect(json.contains("Image omitted"))
        #expect(!json.contains("image/png"))
        #expect(!json.contains("abc"))
    }
}

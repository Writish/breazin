import Testing
@testable import Breazin

@Suite("MCP access control")
struct MCPAccessControlTests {
    @Test func requiresExactBearerToken() {
        let token = "0123456789abcdefghijklmnopqrstuvwxyz"
        #expect(MCPAccessControl.authorized(header: "Bearer \(token)", expectedToken: token))
        #expect(!MCPAccessControl.authorized(header: nil, expectedToken: token))
        #expect(!MCPAccessControl.authorized(header: token, expectedToken: token))
        #expect(!MCPAccessControl.authorized(header: "Bearer \(token)x", expectedToken: token))
        #expect(!MCPAccessControl.authorized(header: "Bearer 1123456789abcdefghijklmnopqrstuvwxyz", expectedToken: token))
    }
}

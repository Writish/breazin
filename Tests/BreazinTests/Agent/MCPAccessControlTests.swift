import Foundation
import Testing
@testable import Breazin

@Suite("MCP access control")
struct MCPAccessControlTests {
    @Test func bearerParsingAndConstantTimeComparisonRejectMalformedValues() {
        let token = "0123456789abcdefghijklmnopqrstuvwxyz"
        #expect(MCPAccessControl.bearerToken(from: "Bearer \(token)") == token)
        #expect(MCPAccessControl.bearerToken(from: nil) == nil)
        #expect(MCPAccessControl.bearerToken(from: token) == nil)
        #expect(MCPAccessControl.bearerToken(from: "Bearer ") == nil)
        #expect(MCPAccessControl.constantTimeEqual(token, token))
        #expect(!MCPAccessControl.constantTimeEqual(token, "\(token)x"))
        #expect(!MCPAccessControl.constantTimeEqual(token, "1123456789abcdefghijklmnopqrstuvwxyz"))
    }

    @Test func registryIssuesDistinctDigestOnlyCredentialsAndRevokesIndividually() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        var registry = MCPClientRegistry()
        let first = try registry.pair(name: " Codex ", token: "first-token", now: now)
        let second = try registry.pair(name: "Claude", token: "second-token", now: now)

        #expect(first.client.name == "Codex")
        #expect(first.client.capabilities == [.readProject])
        #expect(first.accessToken == "first-token")
        #expect(first.client.id != second.client.id)
        #expect(registry.credentials.allSatisfy { $0.tokenSHA256 != "first-token" && $0.tokenSHA256 != "second-token" })
        #expect(registry.authenticate(token: "first-token", now: now.addingTimeInterval(10))?.id == first.client.id)
        #expect(registry.authenticate(token: "wrong-token") == nil)

        let enabledEdits = registry.setCapability(.editCurrentProject, enabled: true, clientID: first.client.id)
        #expect(enabledEdits)
        #expect(registry.authenticate(token: "first-token")?.capabilities == [.readProject, .editCurrentProject])
        let removedRead = registry.setCapability(.readProject, enabled: false, clientID: first.client.id)
        let enabledEditsAgain = registry.setCapability(
            .editCurrentProject,
            enabled: true,
            clientID: first.client.id
        )
        #expect(!removedRead)
        #expect(!enabledEditsAgain)

        let revoked = registry.revoke(clientID: first.client.id)
        #expect(revoked)
        #expect(registry.authenticate(token: "first-token") == nil)
        #expect(registry.authenticate(token: "second-token")?.id == second.client.id)
        let revokedAgain = registry.revoke(clientID: first.client.id)
        #expect(!revokedAgain)
    }

    @Test func legacyClientWithoutCapabilitiesDecodesAsReadOnly() throws {
        let data = Data(#"{"id":"legacy","name":"Old client","createdAt":0}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let client = try decoder.decode(MCPPairedClient.self, from: data)
        #expect(client.capabilities == [.readProject])
    }

    @Test func requestRateLimiterUsesARecoverableSlidingWindow() {
        var limiter = MCPRequestRateLimiter(limit: 2, window: 60)
        let start = Date(timeIntervalSince1970: 1_000)
        let first = limiter.allow("client", now: start)
        let second = limiter.allow("client", now: start.addingTimeInterval(1))
        let blocked = limiter.allow("client", now: start.addingTimeInterval(2))
        let recovered = limiter.allow("client", now: start.addingTimeInterval(61))
        #expect(first)
        #expect(second)
        #expect(!blocked)
        #expect(recovered)
    }

    @Test func registryRejectsInvalidNamesAndClientOverflow() throws {
        var registry = MCPClientRegistry()
        #expect(throws: MCPAccessControlError.invalidClientName) {
            try registry.pair(name: " \n ", token: "token")
        }
        for index in 0..<MCPClientRegistry.clientLimit {
            _ = try registry.pair(name: "Client \(index)", token: "token-\(index)")
        }
        #expect(throws: MCPAccessControlError.clientLimitReached) {
            try registry.pair(name: "One too many", token: "overflow")
        }
    }
}

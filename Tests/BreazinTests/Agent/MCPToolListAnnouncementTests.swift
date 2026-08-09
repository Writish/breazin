import Foundation
import MCP
import Testing

@testable import Breazin

/// Each stateful session announces tools/list_changed exactly once, after its
/// standalone GET stream attaches, so proxied clients refetch across app restarts.
struct MCPToolListAnnouncementTests {

    @Test func pairingIssuesClientTokenAndSessionRejectsAnotherClient() async throws {
        let port = UInt16.random(in: 49_500...64_000)
        let harness = MCPPairingHarness()
        let server = MCPHTTPServer(
            port: port,
            authenticate: harness.authenticate,
            pairClient: harness.pair
        ) { _ in
            let server = Server(
                name: "test",
                version: "1.0.0",
                capabilities: .init(tools: .init(listChanged: true))
            )
            await server.withMethodHandler(ListTools.self) { _ in .init(tools: []) }
            return MCPServerInstance(server: server) { _ in }
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let root = URL(string: "http://127.0.0.1:\(port)")!
        var crossOriginPair = URLRequest(url: root.appendingPathComponent("pair"))
        crossOriginPair.httpMethod = "POST"
        crossOriginPair.setValue("application/json", forHTTPHeaderField: "Content-Type")
        crossOriginPair.setValue("Bearer \(harness.secret)", forHTTPHeaderField: "Authorization")
        crossOriginPair.setValue("https://attacker.invalid", forHTTPHeaderField: "Origin")
        crossOriginPair.httpBody = Data(#"{"clientName":"Attacker"}"#.utf8)
        let (_, crossOriginResponse) = try await URLSession.shared.data(for: crossOriginPair)
        #expect((crossOriginResponse as? HTTPURLResponse)?.statusCode == 403)

        let firstToken = try await pair(name: "First", secret: harness.secret, root: root)
        let secondToken = try await pair(name: "Second", secret: harness.secret, root: root)
        #expect(firstToken != secondToken)

        let sessionID = try await initialize(token: firstToken, root: root)
        var crossClient = URLRequest(url: root.appendingPathComponent("mcp"))
        crossClient.httpMethod = "POST"
        crossClient.setValue("application/json", forHTTPHeaderField: "Content-Type")
        crossClient.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        crossClient.setValue("Bearer \(secondToken)", forHTTPHeaderField: "Authorization")
        crossClient.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        crossClient.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        crossClient.httpBody = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
        let (_, crossResponse) = try await URLSession.shared.data(for: crossClient)
        #expect((crossResponse as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func idleSessionExpiresAndRequiresReinitialization() async throws {
        let port = UInt16.random(in: 49_500...64_000)
        let harness = MCPPairingHarness()
        let server = MCPHTTPServer(
            port: port,
            authenticate: harness.authenticate,
            pairClient: harness.pair,
            sessionIdleLimit: .milliseconds(20)
        ) { _ in
            let server = Server(
                name: "test",
                version: "1.0.0",
                capabilities: .init(tools: .init(listChanged: true))
            )
            await server.withMethodHandler(ListTools.self) { _ in .init(tools: []) }
            return MCPServerInstance(server: server) { _ in }
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let root = URL(string: "http://127.0.0.1:\(port)")!
        let token = try await pair(name: "Idle test", secret: harness.secret, root: root)
        let sessionID = try await initialize(token: token, root: root)
        try await Task.sleep(for: .milliseconds(40))

        var request = URLRequest(url: root.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        request.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test func sessionAnnouncesToolListChangedOnceOnGetStreamAttach() async throws {
        let port = UInt16.random(in: 49_500...64_000)
        let token = "test-installation-token-that-is-long-enough"
        let client = MCPPairedClient(id: "test-client", name: "Test", createdAt: Date())
        let server = MCPHTTPServer(
            port: port,
            authenticate: { header in
                MCPAccessControl.bearerToken(from: header) == token ? client : nil
            },
            pairClient: { _, _ in
                MCPPairingReceipt(client: client, accessToken: token)
            }
        ) { _ in
            let server = Server(
                name: "test",
                version: "1.0.0",
                capabilities: .init(tools: .init(listChanged: true))
            )
            await server.withMethodHandler(ListTools.self) { _ in .init(tools: []) }
            return MCPServerInstance(server: server) { _ in }
        }
        try await server.start()
        defer { Task { await server.stop() } }

        let base = URL(string: "http://127.0.0.1:\(port)/mcp")!
        var initialize = URLRequest(url: base)
        initialize.httpMethod = "POST"
        initialize.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initialize.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        initialize.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initialize.httpBody = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#
                .utf8)

        let (_, initResponse) = try await URLSession.shared.data(for: initialize)
        let sessionID = try #require(
            (initResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id"))

        var get = URLRequest(url: base)
        get.httpMethod = "GET"
        get.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        get.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        get.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        get.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (stream, getResponse) = try await URLSession.shared.bytes(for: get)
        #expect((getResponse as? HTTPURLResponse)?.statusCode == 200)

        let announced = try await firstEvent(
            in: stream, containing: "notifications/tools/list_changed", within: .seconds(10))
        #expect(announced == true)

        // Announce is once per session: no duplicate follows on the same stream,
        // even when further requests touch the session.
        var list = URLRequest(url: base)
        list.httpMethod = "POST"
        list.setValue("application/json", forHTTPHeaderField: "Content-Type")
        list.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        list.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        list.setValue("2025-06-18", forHTTPHeaderField: "MCP-Protocol-Version")
        list.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        list.httpBody = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
        _ = try await URLSession.shared.data(for: list)

        let announcedAgain = try await firstEvent(
            in: stream, containing: "notifications/tools/list_changed", within: .seconds(2))
        #expect(announcedAgain == nil)
    }

    /// True when an SSE line containing `needle` arrives; nil on stream end or timeout.
    private func firstEvent(
        in stream: URLSession.AsyncBytes,
        containing needle: String,
        within timeout: Duration
    ) async throws -> Bool? {
        try await withThrowingTaskGroup(of: Bool?.self) { group in
            group.addTask {
                for try await line in stream.lines where line.contains(needle) { return true }
                return nil
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func pair(name: String, secret: String, root: URL) async throws -> String {
        var request = URLRequest(url: root.appendingPathComponent("pair"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["clientName": name])
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 201)
        let value = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(value["accessToken"] as? String)
    }

    private func initialize(token: String, root: URL) async throws -> String {
        var request = URLRequest(url: root.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#
                .utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        return try #require((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id"))
    }
}

private final class MCPPairingHarness: @unchecked Sendable {
    let secret = "test-pairing-secret-that-is-long-enough"
    private let lock = NSLock()
    private var registry = MCPClientRegistry()

    func pair(name: String, header: String?) throws -> MCPPairingReceipt {
        try lock.withLock {
            guard MCPAccessControl.bearerToken(from: header) == secret else {
                throw MCPAccessControlError.invalidPairingSecret
            }
            return try registry.pair(name: name, token: UUID().uuidString)
        }
    }

    func authenticate(header: String?) -> MCPPairedClient? {
        lock.withLock {
            guard let token = MCPAccessControl.bearerToken(from: header) else { return nil }
            return registry.authenticate(token: token)
        }
    }
}

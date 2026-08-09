import CryptoKit
import Foundation
import Security

enum MCPClientCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case readProject = "read-project"
    case editCurrentProject = "edit-current-project"
    case importExport = "import-export"
    case generation
}

struct MCPPairedClient: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    let createdAt: Date
    var lastUsedAt: Date?
    var capabilities: Set<MCPClientCapability>

    init(
        id: String,
        name: String,
        createdAt: Date,
        lastUsedAt: Date? = nil,
        capabilities: Set<MCPClientCapability> = [.readProject]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.capabilities = capabilities.union([.readProject])
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, lastUsedAt, capabilities
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try values.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        capabilities = try values.decodeIfPresent(Set<MCPClientCapability>.self, forKey: .capabilities)
            ?? [.readProject]
        capabilities.insert(.readProject)
    }
}

struct MCPPairingReceipt: Equatable, Sendable {
    let client: MCPPairedClient
    let accessToken: String
}

enum MCPAccessControlError: LocalizedError, Equatable {
    case invalidPairingSecret
    case invalidClientName
    case clientLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidPairingSecret: "The pairing secret is invalid."
        case .invalidClientName: "Client name must contain 1–80 visible characters."
        case .clientLimitReached: "Revoke an existing MCP client before pairing another."
        }
    }
}

struct MCPClientCredential: Codable, Equatable, Sendable {
    var client: MCPPairedClient
    let tokenSHA256: String
}

struct MCPClientRegistry: Codable, Equatable, Sendable {
    static let clientLimit = 16
    var credentials: [MCPClientCredential] = []

    mutating func pair(name: String, token: String, now: Date = Date()) throws -> MCPPairingReceipt {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 80,
              normalized.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { throw MCPAccessControlError.invalidClientName }
        guard credentials.count < Self.clientLimit else {
            throw MCPAccessControlError.clientLimitReached
        }
        let client = MCPPairedClient(
            id: UUID().uuidString.lowercased(),
            name: normalized,
            createdAt: now
        )
        credentials.append(MCPClientCredential(client: client, tokenSHA256: Self.digest(token)))
        return MCPPairingReceipt(client: client, accessToken: token)
    }

    mutating func authenticate(token: String, now: Date = Date()) -> MCPPairedClient? {
        let digest = Self.digest(token)
        guard let index = credentials.firstIndex(where: {
            MCPAccessControl.constantTimeEqual($0.tokenSHA256, digest)
        }) else { return nil }
        // Coalesce last-used writes so authentication never writes Keychain for every MCP frame.
        if credentials[index].client.lastUsedAt.map({ now.timeIntervalSince($0) >= 60 }) != false {
            credentials[index].client.lastUsedAt = now
        }
        return credentials[index].client
    }

    mutating func revoke(clientID: String) -> Bool {
        let oldCount = credentials.count
        credentials.removeAll { $0.client.id == clientID }
        return credentials.count != oldCount
    }

    mutating func setCapability(
        _ capability: MCPClientCapability,
        enabled: Bool,
        clientID: String
    ) -> Bool {
        guard capability != .readProject,
              let index = credentials.firstIndex(where: { $0.client.id == clientID })
        else { return false }
        let before = credentials[index].client.capabilities
        if enabled {
            credentials[index].client.capabilities.insert(capability)
        } else {
            credentials[index].client.capabilities.remove(capability)
        }
        return credentials[index].client.capabilities != before
    }

    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum MCPAccessControl {
    private static let pairingSecretAccount = "mcp.installation-pairing-secret"
    private static let clientRegistryAccount = "mcp.paired-client-registry"
    private static let lock = NSLock()

    static func pairingSecret() -> String {
        lock.withLock {
            if let existing = KeychainStore.load(account: pairingSecretAccount), existing.count >= 32 {
                return existing
            }
            let secret = randomToken()
            KeychainStore.save(secret, account: pairingSecretAccount)
            return secret
        }
    }

    @discardableResult
    static func resetPairing() -> String {
        lock.withLock {
            let secret = randomToken()
            KeychainStore.save(secret, account: pairingSecretAccount)
            saveRegistry(MCPClientRegistry())
            return secret
        }
    }

    static func pair(clientName: String, authorizationHeader: String?) throws -> MCPPairingReceipt {
        try lock.withLock {
            guard bearerToken(from: authorizationHeader).map({
                constantTimeEqual($0, pairingSecretUnlocked())
            }) == true else {
                throw MCPAccessControlError.invalidPairingSecret
            }
            var registry = loadRegistry()
            let receipt = try registry.pair(name: clientName, token: randomToken())
            saveRegistry(registry)
            return receipt
        }
    }

    static func authenticateClient(authorizationHeader: String?) -> MCPPairedClient? {
        lock.withLock {
            guard let token = bearerToken(from: authorizationHeader) else { return nil }
            var registry = loadRegistry()
            let original = registry
            guard let client = registry.authenticate(token: token) else { return nil }
            if registry != original { saveRegistry(registry) }
            return client
        }
    }

    static func pairedClients() -> [MCPPairedClient] {
        lock.withLock {
            loadRegistry().credentials.map(\.client).sorted { $0.createdAt < $1.createdAt }
        }
    }

    @discardableResult
    static func setCapability(
        _ capability: MCPClientCapability,
        enabled: Bool,
        clientID: String
    ) -> Bool {
        lock.withLock {
            var registry = loadRegistry()
            let changed = registry.setCapability(capability, enabled: enabled, clientID: clientID)
            if changed { saveRegistry(registry) }
            return changed
        }
    }

    @discardableResult
    static func revoke(clientID: String) -> Bool {
        lock.withLock {
            var registry = loadRegistry()
            let changed = registry.revoke(clientID: clientID)
            if changed { saveRegistry(registry) }
            return changed
        }
    }

    static func bearerToken(from header: String?) -> String? {
        guard let header, header.hasPrefix("Bearer ") else { return nil }
        let token = String(header.dropFirst("Bearer ".count))
        return token.isEmpty ? nil : token
    }

    static func constantTimeEqual(_ left: String, _ right: String) -> Bool {
        let lhs = Array(left.utf8)
        let rhs = Array(right.utf8)
        var difference = lhs.count ^ rhs.count
        for index in 0..<max(lhs.count, rhs.count) {
            difference |= Int(lhs[safe: index] ?? 0) ^ Int(rhs[safe: index] ?? 0)
        }
        return difference == 0
    }

    private static func pairingSecretUnlocked() -> String {
        if let existing = KeychainStore.load(account: pairingSecretAccount), existing.count >= 32 {
            return existing
        }
        let secret = randomToken()
        KeychainStore.save(secret, account: pairingSecretAccount)
        return secret
    }

    private static func loadRegistry() -> MCPClientRegistry {
        guard let encoded = KeychainStore.load(account: clientRegistryAccount),
              let data = Data(base64Encoded: encoded),
              let registry = try? JSONDecoder().decode(MCPClientRegistry.self, from: data)
        else { return MCPClientRegistry() }
        return registry
    }

    private static func saveRegistry(_ registry: MCPClientRegistry) {
        guard let data = try? JSONEncoder().encode(registry) else { return }
        KeychainStore.save(data.base64EncodedString(), account: clientRegistryAccount)
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        precondition(SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

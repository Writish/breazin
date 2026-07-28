import Foundation
import Security

enum MCPAccessControl {
    private static let account = "mcp.installation-access-token"

    static func currentToken() -> String {
        if let existing = KeychainStore.load(account: account), existing.count >= 32 {
            return existing
        }
        return rotateToken()
    }

    @discardableResult
    static func rotateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Unable to create MCP access token")
        let token = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        KeychainStore.save(token, account: account)
        return token
    }

    static func authorized(header: String?, expectedToken: String) -> Bool {
        guard let header, header.hasPrefix("Bearer ") else { return false }
        let candidate = String(header.dropFirst("Bearer ".count))
        let lhs = Array(candidate.utf8)
        let rhs = Array(expectedToken.utf8)
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }
}

import Foundation

// All mutable state is protected by lock.
final class KeychainValueCache: @unchecked Sendable {
    private let lock = NSLock()
    private var loadedAccounts = Set<String>()
    private var values: [String: String] = [:]

    func value(account: String, load: () -> String?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if loadedAccounts.contains(account) {
            return values[account]
        }
        let value = load()
        loadedAccounts.insert(account)
        if let value {
            values[account] = value
        }
        return value
    }

    func store(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        loadedAccounts.insert(account)
        values[account] = value
    }

    func remove(account: String) {
        lock.lock()
        defer { lock.unlock() }
        loadedAccounts.insert(account)
        values.removeValue(forKey: account)
    }
}

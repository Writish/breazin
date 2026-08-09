import Testing
@testable import Breazin

@Suite("Keychain value cache")
struct KeychainValueCacheTests {
    @Test func loadsAnAccountOnlyOncePerProcess() {
        let cache = KeychainValueCache()
        var loads = 0

        let first = cache.value(account: "provider.volcengine") {
            loads += 1
            return "secret"
        }
        let second = cache.value(account: "provider.volcengine") {
            loads += 1
            return "different-secret"
        }

        #expect(first == "secret")
        #expect(second == "secret")
        #expect(loads == 1)
    }

    @Test func saveAndDeleteUpdateTheCachedValue() {
        let cache = KeychainValueCache()

        cache.store("first", account: "broker")
        #expect(cache.value(account: "broker") { nil } == "first")

        cache.remove(account: "broker")
        #expect(cache.value(account: "broker") { "stale" } == nil)
    }
}

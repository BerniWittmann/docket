import Foundation
import Security
import Synchronization

/// Generic-password storage for the Linear API key and the TickTick token.
/// Values are cached in memory, so macOS asks for Keychain access at most once per launch.
public enum Keychain {
    public static let linearService = "dev.berni.docket.linear"
    public static let tickTickService = "dev.berni.docket.ticktick"
    static let account = "linear-api-key"
    private static let cache = Mutex<[String: String?]>([:])

    public static func read(service: String = linearService) -> String? {
        if let cached = cache.withLock({ $0[service] }) { return cached }
        let value = readFromKeychain(service: service)
        cache.withLock { $0[service] = .some(value) }
        return value
    }

    private static func readFromKeychain(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func write(_ value: String?, service: String = linearService) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let stored = value.flatMap { $0.isEmpty ? nil : $0 }
        cache.withLock { $0[service] = .some(stored) }
        guard let value = stored else { return true }
        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

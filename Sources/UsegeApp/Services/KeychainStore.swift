import Foundation
import Security

final class KeychainStore {
    private let service = "com.usege.macwidget.keychain"

    func set(_ value: Data, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var create = query
        create[kSecValueData as String] = value

        let status = SecItemAdd(create as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func get(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var output: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &output)
        guard status == errSecSuccess else {
            return nil
        }

        return output as? Data
    }

    func setString(_ value: String, for account: String) throws {
        guard let data = value.data(using: .utf8) else {
            return
        }
        try set(data, for: account)
    }

    func getString(_ account: String) -> String? {
        guard let data = get(account) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

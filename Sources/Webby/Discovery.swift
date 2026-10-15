import Foundation
import Security
import LocalAuthentication
import WebbyCore

// Read-only, exact namespace. No enumeration, no writes; called only by an explicit reveal action.
struct KeychainAccounts {
    func read(reference: String) throws -> String {
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.webby.accounts", kSecAttrAccount as String: reference, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne, kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw ConfigError.invalid("未找到账号或尚未授权；请由你在钥匙串中管理。") }
        return value
    }
}

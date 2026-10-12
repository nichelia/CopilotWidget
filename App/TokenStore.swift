import Foundation
import Security

/// The GitHub token, in this app's own Keychain item.
///
/// Only the host app ever sees it: the widget extension reads the snapshot the app writes
/// and never calls GitHub, so there is no Keychain access group to share and nothing that
/// would need a provisioning profile.
struct TokenStore {
    private let service = "com.nichelia.CopilotWidget.token"
    private let account = "github"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func save(_ rawValue: String) throws {
        let data = Data(try Self.normalise(rawValue).utf8)

        // Update first: SecItemAdd fails with errSecDuplicateItem on an existing account.
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }

        guard status == errSecItemNotFound else {
            throw CopilotAPIError.keychain("Unable to store the token in the Keychain (error \(status)).")
        }

        var add = baseQuery
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CopilotAPIError.keychain("Unable to store the token in the Keychain (error \(addStatus)).")
        }
    }

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }

        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else {
            throw CopilotAPIError.keychain("Unable to read the token from the Keychain (error \(status)).")
        }
        return value
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CopilotAPIError.keychain("Unable to clear the stored token (error \(status)).")
        }
    }

    /// Accepts the bare token, or one pasted with an `Authorization:`/`Bearer`/`token`
    /// prefix or surrounding quotes. Anything with whitespace left in it is a sentence, not a
    /// token, and is refused rather than stored.
    static func normalise(_ rawValue: String) throws -> String {
        var token = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["authorization:", "bearer ", "token "] where token.lowercased().hasPrefix(prefix) {
            token = String(token.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        guard !token.isEmpty, token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw CopilotAPIError.invalidToken
        }
        return token
    }
}

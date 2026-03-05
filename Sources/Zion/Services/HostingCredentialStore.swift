import Foundation
import Security

/// Keychain wrapper for hosting provider secrets (PATs, app passwords).
/// Follows the same pattern as `AIClient` Keychain methods.
enum HostingCredentialStore {
    private static let keychainService = "com.zion.hosting-credentials"

    /// Identifies a hosting credential stored in Keychain.
    enum CredentialKey: String, CaseIterable, Sendable {
        case githubPAT = "github.pat"
        case gitlabPAT = "gitlab.pat"
        case bitbucketAppPassword = "bitbucket.appPassword"
        case azureDevOpsPAT = "azureDevOps.pat"

        /// The legacy UserDefaults key this credential was stored under, if any.
        /// Nil for credentials that never lived in UserDefaults (e.g., Azure DevOps).
        var legacyDefaultsKey: String? {
            switch self {
            case .githubPAT: return "zion.github.pat"
            case .gitlabPAT: return "zion.gitlab.pat"
            case .bitbucketAppPassword: return "zion.bitbucket.appPassword"
            case .azureDevOpsPAT: return nil
            }
        }
    }

    // MARK: - Keychain Operations

    static func saveSecret(_ secret: String, for key: CredentialKey) {
        guard !secret.isEmpty else {
            deleteSecret(for: key)
            return
        }
        let data = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func loadSecret(for key: CredentialKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return migrateLegacyValueIfPresent(for: key)
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteSecret(for key: CredentialKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Migration

    /// Migrates hosting secrets from UserDefaults to Keychain.
    /// Only migrates if the Keychain entry doesn't already exist.
    /// Deletes the UserDefaults entry after successful migration.
    static func migrateFromUserDefaults() {
        let defaults = UserDefaults.standard
        for key in CredentialKey.allCases {
            guard let legacyKey = key.legacyDefaultsKey else { continue }
            guard let value = defaults.string(forKey: legacyKey), !value.isEmpty else { continue }
            saveSecretIfMissing(value, for: key)
            defaults.removeObject(forKey: legacyKey)
        }
    }

    private static func saveSecretIfMissing(_ secret: String, for key: CredentialKey) {
        guard !secret.isEmpty else { return }
        let data = Data(secret.utf8)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    private static func migrateLegacyValueIfPresent(for key: CredentialKey) -> String? {
        guard let legacyKey = key.legacyDefaultsKey else { return nil }
        let defaults = UserDefaults.standard
        guard let value = defaults.string(forKey: legacyKey), !value.isEmpty else { return nil }
        saveSecretIfMissing(value, for: key)
        defaults.removeObject(forKey: legacyKey)
        return value
    }
}

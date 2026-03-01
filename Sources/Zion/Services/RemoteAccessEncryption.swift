import CryptoKit
import Foundation
import Security

enum RemoteAccessEncryption {
    private static let keychainService = "com.zion.remote-access"
    private static let pairingKeyAccount = "pairing-key"

    // MARK: - Key Generation

    static func generatePairingKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func exportKey(_ key: SymmetricKey) -> String {
        key.withUnsafeBytes { Data($0).base64EncodedString() }
    }

    static func importKey(_ base64: String) -> SymmetricKey? {
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }

    // MARK: - Encryption / Decryption

    static func encrypt(_ data: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: key)
        guard let combined = sealedBox.combined else {
            throw EncryptionError.sealFailed
        }
        return combined
    }

    static func decrypt(_ combined: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // MARK: - Keychain Storage

    static func savePairingKey(_ key: SymmetricKey) {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: pairingKeyAccount,
        ]

        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecUseDataProtectionKeychain as String] = true
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func loadPairingKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: pairingKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            return nil
        }
        return SymmetricKey(data: data)
    }

    static func deletePairingKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: pairingKeyAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Errors

    enum EncryptionError: Error {
        case sealFailed
    }
}

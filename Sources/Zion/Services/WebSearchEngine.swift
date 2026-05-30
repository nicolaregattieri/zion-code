import Foundation

/// Phase 6.8 — built-in `web_search` tool. Engines + keychain helpers.
/// Vendor-multiplexed so the built-in tool stays generic ("no hardcode")
/// while the user picks which provider's API key drives the call.
enum WebSearchEngine: String, CaseIterable, Sendable {
    case tavily
    case brave
    case exa
    case searxng

    var displayName: String {
        switch self {
        case .tavily: return "Tavily"
        case .brave: return "Brave Search"
        case .exa: return "Exa"
        case .searxng: return "SearXNG (self-hosted)"
        }
    }

    var signupURL: URL? {
        switch self {
        case .tavily: return URL(string: "https://app.tavily.com/")
        case .brave: return URL(string: "https://api.search.brave.com/")
        case .exa: return URL(string: "https://dashboard.exa.ai/")
        case .searxng: return URL(string: "https://docs.searxng.org/admin/installation.html")
        }
    }
}

/// Settings keys + keychain helpers for the built-in web_search tool.
enum WebSearchSettings {

    static let engineKey = "chat.webSearch.engine"
    /// For SearXNG (self-hosted): base URL of the user's instance.
    static let searxngURLKey = "chat.webSearch.searxngURL"

    private static let keychainService = "com.zion.web-search-key"

    static var selectedEngine: WebSearchEngine {
        get {
            let raw = UserDefaults.standard.string(forKey: engineKey) ?? WebSearchEngine.tavily.rawValue
            return WebSearchEngine(rawValue: raw) ?? .tavily
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: engineKey)
        }
    }

    static var searxngURL: String {
        get { UserDefaults.standard.string(forKey: searxngURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: searxngURLKey) }
    }

    static func saveKey(_ key: String, for engine: WebSearchEngine) {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: engine.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func loadKey(for engine: WebSearchEngine) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: engine.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deleteKey(for engine: WebSearchEngine) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: engine.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

import Foundation

/// Registry for multi-account hosting credentials.
/// Account metadata (usernames, labels, owners) lives in UserDefaults as JSON.
/// Secrets (PATs, app passwords) live in Keychain via HostingCredentialStore.
enum HostingAccountStore {

    // MARK: - Read

    /// All registered hosting accounts across all providers.
    static func allAccounts() -> [HostingAccount] {
        guard let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.GitHosting.accounts) else {
            return []
        }
        return (try? JSONDecoder().decode([HostingAccount].self, from: data)) ?? []
    }

    /// Accounts for a specific provider kind.
    static func accounts(for kind: GitHostingKind) -> [HostingAccount] {
        allAccounts().filter { $0.kind == kind }
    }

    // MARK: - Write

    /// Add a new account and store its secret in Keychain.
    static func addAccount(_ account: HostingAccount, secret: String) {
        var list = allAccounts()
        list.append(account)
        persist(list)
        HostingCredentialStore.saveSecret(secret, forAccountKey: account.keychainAccountKey)
    }

    /// Remove an account and its Keychain secret.
    static func removeAccount(_ account: HostingAccount) {
        var list = allAccounts()
        list.removeAll { $0.id == account.id }
        persist(list)
        HostingCredentialStore.deleteSecret(forAccountKey: account.keychainAccountKey)
    }

    /// Update account metadata (label, owners, etc.). Does not touch Keychain.
    static func updateAccount(_ account: HostingAccount) {
        var list = allAccounts()
        guard let index = list.firstIndex(where: { $0.id == account.id }) else { return }
        list[index] = account
        persist(list)
    }

    // MARK: - Secret Access

    /// Load the Keychain secret for an account.
    static func loadSecret(for account: HostingAccount) -> String? {
        HostingCredentialStore.loadSecret(forAccountKey: account.keychainAccountKey)
    }

    // MARK: - Resolution

    /// Find the account whose `owners` list contains the remote's owner.
    /// Case-insensitive match. Returns the first match.
    static func resolveAccount(for remote: HostedRemote) -> HostingAccount? {
        let candidates = accounts(for: remote.kind)
        let target = remote.owner.lowercased()
        return candidates.first { account in
            account.owners.contains { $0.lowercased() == target }
        }
    }

    // MARK: - Migration

    /// Migrate existing single-account credentials into the multi-account system.
    /// Idempotent: runs once, then sets a flag.
    static func migrateFromSingleAccount() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: UserDefaultsKeys.GitHosting.migratedToMultiAccount) else { return }

        var migrated: [HostingAccount] = []

        // GitHub
        if let secret = HostingCredentialStore.loadSecret(for: .githubPAT), !secret.isEmpty {
            let account = HostingAccount(
                kind: .github,
                username: "default",
                label: "Default",
                owners: []
            )
            HostingCredentialStore.saveSecret(secret, forAccountKey: account.keychainAccountKey)
            migrated.append(account)
        }

        // GitLab
        if let secret = HostingCredentialStore.loadSecret(for: .gitlabPAT), !secret.isEmpty {
            let host = defaults.string(forKey: UserDefaultsKeys.GitHosting.gitlabHost)
            let account = HostingAccount(
                kind: .gitlab,
                username: "default",
                label: "Default",
                owners: [],
                gitlabHost: (host?.isEmpty == false) ? host : nil
            )
            HostingCredentialStore.saveSecret(secret, forAccountKey: account.keychainAccountKey)
            migrated.append(account)
        }

        // Bitbucket
        if let secret = HostingCredentialStore.loadSecret(for: .bitbucketAppPassword), !secret.isEmpty {
            let bbUser = defaults.string(forKey: UserDefaultsKeys.GitHosting.bitbucketUsername)
            let account = HostingAccount(
                kind: .bitbucket,
                username: bbUser ?? "default",
                label: "Default",
                owners: [],
                bitbucketUsername: bbUser
            )
            HostingCredentialStore.saveSecret(secret, forAccountKey: account.keychainAccountKey)
            migrated.append(account)
        }

        // Azure DevOps
        if let secret = HostingCredentialStore.loadSecret(for: .azureDevOpsPAT), !secret.isEmpty {
            let account = HostingAccount(
                kind: .azureDevOps,
                username: "default",
                label: "Default",
                owners: []
            )
            HostingCredentialStore.saveSecret(secret, forAccountKey: account.keychainAccountKey)
            migrated.append(account)
        }

        if !migrated.isEmpty {
            persist(migrated)
        }
        defaults.set(true, forKey: UserDefaultsKeys.GitHosting.migratedToMultiAccount)
    }

    // MARK: - Private

    private static func persist(_ accounts: [HostingAccount]) {
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        UserDefaults.standard.set(data, forKey: UserDefaultsKeys.GitHosting.accounts)
    }
}

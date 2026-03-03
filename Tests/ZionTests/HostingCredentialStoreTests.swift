import XCTest
@testable import Zion

final class HostingCredentialStoreTests: XCTestCase {

    // MARK: - CredentialKey Enumeration

    func testAllCasesCount() {
        XCTAssertEqual(HostingCredentialStore.CredentialKey.allCases.count, 4)
    }

    func testLegacyDefaultsKeyMapping() {
        XCTAssertEqual(
            HostingCredentialStore.CredentialKey.githubPAT.legacyDefaultsKey,
            "zion.github.pat"
        )
        XCTAssertEqual(
            HostingCredentialStore.CredentialKey.gitlabPAT.legacyDefaultsKey,
            "zion.gitlab.pat"
        )
        XCTAssertEqual(
            HostingCredentialStore.CredentialKey.bitbucketAppPassword.legacyDefaultsKey,
            "zion.bitbucket.appPassword"
        )
        XCTAssertNil(
            HostingCredentialStore.CredentialKey.azureDevOpsPAT.legacyDefaultsKey,
            "Azure DevOps is new — no legacy key"
        )
    }

    func testCredentialKeyRawValues() {
        XCTAssertEqual(HostingCredentialStore.CredentialKey.githubPAT.rawValue, "github.pat")
        XCTAssertEqual(HostingCredentialStore.CredentialKey.gitlabPAT.rawValue, "gitlab.pat")
        XCTAssertEqual(HostingCredentialStore.CredentialKey.bitbucketAppPassword.rawValue, "bitbucket.appPassword")
        XCTAssertEqual(HostingCredentialStore.CredentialKey.azureDevOpsPAT.rawValue, "azureDevOps.pat")
    }

    // MARK: - Keychain Save/Load/Delete Cycle
    // These tests use .azureDevOpsPAT to avoid clobbering real credentials.

    func testSaveAndLoadSecret() {
        let key = HostingCredentialStore.CredentialKey.azureDevOpsPAT
        let original = HostingCredentialStore.loadSecret(for: key)
        defer {
            if let original { HostingCredentialStore.saveSecret(original, for: key) }
            else { HostingCredentialStore.deleteSecret(for: key) }
        }

        let testSecret = "test_secret_\(UUID().uuidString)"
        HostingCredentialStore.saveSecret(testSecret, for: key)

        let loaded = HostingCredentialStore.loadSecret(for: key)
        XCTAssertEqual(loaded, testSecret)

        HostingCredentialStore.deleteSecret(for: key)
        XCTAssertNil(HostingCredentialStore.loadSecret(for: key))
    }

    func testSaveEmptyStringDeletesSecret() {
        let key = HostingCredentialStore.CredentialKey.azureDevOpsPAT
        let original = HostingCredentialStore.loadSecret(for: key)
        defer {
            if let original { HostingCredentialStore.saveSecret(original, for: key) }
            else { HostingCredentialStore.deleteSecret(for: key) }
        }

        HostingCredentialStore.saveSecret("some-token", for: key)
        XCTAssertNotNil(HostingCredentialStore.loadSecret(for: key))

        // Save empty → should delete
        HostingCredentialStore.saveSecret("", for: key)
        XCTAssertNil(HostingCredentialStore.loadSecret(for: key))
    }

    func testDeleteNonexistentKeyDoesNotCrash() {
        let key = HostingCredentialStore.CredentialKey.azureDevOpsPAT
        let original = HostingCredentialStore.loadSecret(for: key)
        defer {
            if let original { HostingCredentialStore.saveSecret(original, for: key) }
        }

        HostingCredentialStore.deleteSecret(for: key)
        XCTAssertNil(HostingCredentialStore.loadSecret(for: key))
    }

    func testOverwriteExistingSecret() {
        let key = HostingCredentialStore.CredentialKey.azureDevOpsPAT
        let original = HostingCredentialStore.loadSecret(for: key)
        defer {
            if let original { HostingCredentialStore.saveSecret(original, for: key) }
            else { HostingCredentialStore.deleteSecret(for: key) }
        }

        HostingCredentialStore.saveSecret("first-secret", for: key)
        XCTAssertEqual(HostingCredentialStore.loadSecret(for: key), "first-secret")

        HostingCredentialStore.saveSecret("second-secret", for: key)
        XCTAssertEqual(HostingCredentialStore.loadSecret(for: key), "second-secret")
    }

    // MARK: - Migration

    /// Save and restore real Keychain entries around migration tests so we don't destroy user credentials.
    private func withSavedCredentials(keys: [HostingCredentialStore.CredentialKey], body: () -> Void) {
        // Snapshot existing values
        var saved: [HostingCredentialStore.CredentialKey: String] = [:]
        for key in keys {
            if let value = HostingCredentialStore.loadSecret(for: key) {
                saved[key] = value
            }
        }

        body()

        // Restore original values
        for key in keys {
            if let original = saved[key] {
                HostingCredentialStore.saveSecret(original, for: key)
            } else {
                HostingCredentialStore.deleteSecret(for: key)
            }
        }
    }

    func testMigrateFromUserDefaults() {
        let defaults = UserDefaults.standard
        let keys: [HostingCredentialStore.CredentialKey] = [.githubPAT, .gitlabPAT, .bitbucketAppPassword]

        withSavedCredentials(keys: keys) {
            // Setup: write legacy keys
            defaults.set("legacy-github-pat", forKey: "zion.github.pat")
            defaults.set("legacy-gitlab-pat", forKey: "zion.gitlab.pat")
            defaults.set("legacy-bb-pass", forKey: "zion.bitbucket.appPassword")

            // Clear Keychain to ensure migration
            HostingCredentialStore.deleteSecret(for: .githubPAT)
            HostingCredentialStore.deleteSecret(for: .gitlabPAT)
            HostingCredentialStore.deleteSecret(for: .bitbucketAppPassword)

            // Migrate
            HostingCredentialStore.migrateFromUserDefaults()

            // Verify Keychain has the values
            XCTAssertEqual(HostingCredentialStore.loadSecret(for: .githubPAT), "legacy-github-pat")
            XCTAssertEqual(HostingCredentialStore.loadSecret(for: .gitlabPAT), "legacy-gitlab-pat")
            XCTAssertEqual(HostingCredentialStore.loadSecret(for: .bitbucketAppPassword), "legacy-bb-pass")

            // Verify UserDefaults are cleaned up
            XCTAssertNil(defaults.string(forKey: "zion.github.pat"))
            XCTAssertNil(defaults.string(forKey: "zion.gitlab.pat"))
            XCTAssertNil(defaults.string(forKey: "zion.bitbucket.appPassword"))
        }
    }

    func testMigrateDoesNotOverwriteExistingKeychainEntry() {
        let defaults = UserDefaults.standard

        withSavedCredentials(keys: [.githubPAT]) {
            // Pre-existing Keychain entry
            HostingCredentialStore.saveSecret("keychain-value", for: .githubPAT)

            // Legacy UD entry
            defaults.set("legacy-value", forKey: "zion.github.pat")

            // Migrate
            HostingCredentialStore.migrateFromUserDefaults()

            // Keychain should keep its value
            XCTAssertEqual(HostingCredentialStore.loadSecret(for: .githubPAT), "keychain-value")

            // But UD should still be cleaned up
            XCTAssertNil(defaults.string(forKey: "zion.github.pat"))
        }
    }
}

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

    func testSaveAndLoadSecret() {
        let key = HostingCredentialStore.CredentialKey.githubPAT
        let testSecret = "ghp_test_secret_\(UUID().uuidString)"

        // Save
        HostingCredentialStore.saveSecret(testSecret, for: key)

        // Load
        let loaded = HostingCredentialStore.loadSecret(for: key)
        XCTAssertEqual(loaded, testSecret)

        // Cleanup
        HostingCredentialStore.deleteSecret(for: key)
        XCTAssertNil(HostingCredentialStore.loadSecret(for: key))
    }

    func testSaveEmptyStringDeletesSecret() {
        let key = HostingCredentialStore.CredentialKey.gitlabPAT

        // First save something
        HostingCredentialStore.saveSecret("some-token", for: key)
        XCTAssertNotNil(HostingCredentialStore.loadSecret(for: key))

        // Save empty → should delete
        HostingCredentialStore.saveSecret("", for: key)
        XCTAssertNil(HostingCredentialStore.loadSecret(for: key))
    }

    func testDeleteNonexistentKeyDoesNotCrash() {
        // Should be a no-op
        HostingCredentialStore.deleteSecret(for: .azureDevOpsPAT)
        XCTAssertNil(HostingCredentialStore.loadSecret(for: .azureDevOpsPAT))
    }

    func testOverwriteExistingSecret() {
        let key = HostingCredentialStore.CredentialKey.bitbucketAppPassword

        HostingCredentialStore.saveSecret("first-secret", for: key)
        XCTAssertEqual(HostingCredentialStore.loadSecret(for: key), "first-secret")

        HostingCredentialStore.saveSecret("second-secret", for: key)
        XCTAssertEqual(HostingCredentialStore.loadSecret(for: key), "second-secret")

        // Cleanup
        HostingCredentialStore.deleteSecret(for: key)
    }

    // MARK: - Migration

    func testMigrateFromUserDefaults() {
        let defaults = UserDefaults.standard

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

        // Cleanup Keychain
        HostingCredentialStore.deleteSecret(for: .githubPAT)
        HostingCredentialStore.deleteSecret(for: .gitlabPAT)
        HostingCredentialStore.deleteSecret(for: .bitbucketAppPassword)
    }

    func testMigrateDoesNotOverwriteExistingKeychainEntry() {
        let defaults = UserDefaults.standard

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

        // Cleanup
        HostingCredentialStore.deleteSecret(for: .githubPAT)
    }
}

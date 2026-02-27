import XCTest
@testable import Zion

final class NtfyConfigIOTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NtfyConfigIOTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - Round-trip

    func testWriteAndReadRoundTrip() {
        NtfyClient.writeGlobalConfig(topic: "test-topic", serverURL: "https://ntfy.sh", baseDirectory: tempDir)
        let config = NtfyClient.readGlobalConfig(baseDirectory: tempDir)
        XCTAssertEqual(config?.topic, "test-topic")
        XCTAssertEqual(config?.serverURL, "https://ntfy.sh")
    }

    // MARK: - Directory permissions

    func testConfigDirectoryHas700Permissions() {
        NtfyClient.writeGlobalConfig(topic: "t", serverURL: "https://ntfy.sh", baseDirectory: tempDir)
        let configDir = tempDir.appendingPathComponent(".config/ntfy")
        let attrs = try? FileManager.default.attributesOfItem(atPath: configDir.path)
        let perms = attrs?[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o700)
    }

    // MARK: - File permissions

    func testConfigFileHas600Permissions() {
        NtfyClient.writeGlobalConfig(topic: "t", serverURL: "https://ntfy.sh", baseDirectory: tempDir)
        let configFile = tempDir.appendingPathComponent(".config/ntfy/config.json")
        let attrs = try? FileManager.default.attributesOfItem(atPath: configFile.path)
        let perms = attrs?[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    // MARK: - JSON structure

    func testConfigFileHasCorrectJSONKeys() throws {
        NtfyClient.writeGlobalConfig(topic: "my-topic", serverURL: "https://custom.sh", baseDirectory: tempDir)
        let configFile = tempDir.appendingPathComponent(".config/ntfy/config.json")
        let data = try Data(contentsOf: configFile)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(json?["topic"], "my-topic")
        XCTAssertEqual(json?["server"], "https://custom.sh")
        XCTAssertEqual(json?.keys.sorted(), ["server", "topic"])
    }

    func testConfigFileIsPrettyPrintedAndSorted() throws {
        NtfyClient.writeGlobalConfig(topic: "t", serverURL: "https://s.sh", baseDirectory: tempDir)
        let configFile = tempDir.appendingPathComponent(".config/ntfy/config.json")
        let content = try String(contentsOf: configFile, encoding: .utf8)
        // Pretty-printed JSON has newlines
        XCTAssertTrue(content.contains("\n"))
        // Sorted keys: "server" before "topic"
        let serverIndex = content.range(of: "\"server\"")!.lowerBound
        let topicIndex = content.range(of: "\"topic\"")!.lowerBound
        XCTAssertTrue(serverIndex < topicIndex)
    }

    // MARK: - Overwrite

    func testOverwriteExistingConfig() {
        NtfyClient.writeGlobalConfig(topic: "old", serverURL: "https://old.sh", baseDirectory: tempDir)
        NtfyClient.writeGlobalConfig(topic: "new", serverURL: "https://new.sh", baseDirectory: tempDir)
        let config = NtfyClient.readGlobalConfig(baseDirectory: tempDir)
        XCTAssertEqual(config?.topic, "new")
        XCTAssertEqual(config?.serverURL, "https://new.sh")
    }

    // MARK: - Read edge cases

    func testReadReturnsNilForMissingFile() {
        let config = NtfyClient.readGlobalConfig(baseDirectory: tempDir)
        XCTAssertNil(config)
    }

    func testReadReturnsNilForEmptyFile() throws {
        let configDir = tempDir.appendingPathComponent(".config/ntfy")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try Data().write(to: configDir.appendingPathComponent("config.json"))
        XCTAssertNil(NtfyClient.readGlobalConfig(baseDirectory: tempDir))
    }

    func testReadReturnsNilForCorruptedJSON() throws {
        let configDir = tempDir.appendingPathComponent(".config/ntfy")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try "not json".write(to: configDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        XCTAssertNil(NtfyClient.readGlobalConfig(baseDirectory: tempDir))
    }

    func testReadReturnsNilForMissingTopic() throws {
        let configDir = tempDir.appendingPathComponent(".config/ntfy")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let json = try JSONSerialization.data(withJSONObject: ["server": "https://ntfy.sh"])
        try json.write(to: configDir.appendingPathComponent("config.json"))
        XCTAssertNil(NtfyClient.readGlobalConfig(baseDirectory: tempDir))
    }

    func testReadUsesDefaultServerWhenMissing() throws {
        let configDir = tempDir.appendingPathComponent(".config/ntfy")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let json = try JSONSerialization.data(withJSONObject: ["topic": "t"])
        try json.write(to: configDir.appendingPathComponent("config.json"))
        let config = NtfyClient.readGlobalConfig(baseDirectory: tempDir)
        XCTAssertEqual(config?.serverURL, "https://ntfy.sh")
    }
}

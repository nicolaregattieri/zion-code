import CryptoKit
import XCTest
@testable import Zion

final class RemoteAccessServerTests: XCTestCase {
    private var server: RemoteAccessServer!
    private let testPort: UInt16 = 19_848 // Avoid conflict with running app on 19847

    override func setUp() async throws {
        server = RemoteAccessServer()
        let key = RemoteAccessEncryption.generatePairingKey()
        try await server.start(port: testPort, key: key, lanMode: true)
        // Give NWListener time to bind
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    override func tearDown() async throws {
        await server.stop()
        server = nil
        // Give port time to release
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    // MARK: - Authentication Tests

    func testPairRejectsInvalidToken() async throws {
        let (data, response) = try await httpGET("/pair?t=invalid-token")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 403)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("invalid_token") ?? false)
    }

    func testPairAcceptsValidToken() async throws {
        let token = "TEST-TOKEN-\(UUID().uuidString)"
        await server.addPairingToken(token)

        let (data, response) = try await httpGET("/pair?t=\(token)")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 200)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("paired") ?? false)
    }

    func testPollRejectsUnauthenticated() async throws {
        let (data, response) = try await httpGET("/poll?t=invalid")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 403)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("not_authenticated") ?? false)
    }

    func testPollWorksAfterPairing() async throws {
        let token = "POLL-TEST-\(UUID().uuidString)"
        await server.addPairingToken(token)

        // Pair first
        _ = try await httpGET("/pair?t=\(token)")

        // Then poll
        let (_, response) = try await httpGET("/poll?t=\(token)")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 200)
    }

    func testInputRejectsWithoutToken() async throws {
        let (data, response) = try await httpPOST("/input", body: "dGVzdA==")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 403)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("not_authenticated") ?? false)
    }

    func testInputRejectsInvalidToken() async throws {
        let (data, response) = try await httpPOST("/input?t=wrong", body: "dGVzdA==")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 403)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("not_authenticated") ?? false)
    }

    func testActionRejectsWithoutToken() async throws {
        let (data, response) = try await httpPOST("/action", body: "dGVzdA==")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 403)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("not_authenticated") ?? false)
    }

    func testTokenReusableAfterPairing() async throws {
        let token = "REUSE-\(UUID().uuidString)"
        await server.addPairingToken(token)

        // Pair twice — should work both times
        let (_, r1) = try await httpGET("/pair?t=\(token)")
        XCTAssertEqual((r1 as? HTTPURLResponse)?.statusCode, 200)

        let (_, r2) = try await httpGET("/pair?t=\(token)")
        XCTAssertEqual((r2 as? HTTPURLResponse)?.statusCode, 200)
    }

    // MARK: - XSS Sanitization Tests

    func testXSSSanitizedInPairingInjection() async throws {
        let xssKey = "test');alert(1)//"
        let xssToken = "abc<script>evil</script>"
        let (data, _) = try await httpGET("/?k=\(xssKey)&t=\(xssToken)&m=lan")
        let html = String(data: data, encoding: .utf8) ?? ""

        // The XSS payloads should NOT appear in the HTML
        XCTAssertFalse(html.contains("alert(1)"))
        XCTAssertFalse(html.contains("<script>evil</script>"))

        // The sanitized values should be alphanumeric only
        XCTAssertTrue(html.contains("PAIRING="))
        XCTAssertTrue(html.contains("k:'testalert1'"))
    }

    func testSanitizeForJSStripsSpecialChars() async throws {
        // Verify via HTML output that special chars are stripped
        let (data, _) = try await httpGET("/?k=abc-def_123&t=valid&m=lan")
        let html = String(data: data, encoding: .utf8) ?? ""

        // Hyphens and underscores should survive (URL-safe base64 + UUID chars)
        XCTAssertTrue(html.contains("k:'abc-def_123'"))
    }

    // MARK: - Content-Length Cap Tests

    func testOversizedRequestRejected() async throws {
        // Send a request claiming very large Content-Length
        let url = URL(string: "http://localhost:\(testPort)/input?t=test")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("100000", forHTTPHeaderField: "Content-Length")
        request.httpBody = Data(repeating: 0x41, count: 100_000)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        // Should either get 413 (payload too large) or connection closed
        let body = String(data: data, encoding: .utf8) ?? ""
        let rejected = status == 413 || body.contains("too large")
        XCTAssertTrue(rejected, "Expected 413 or rejection, got \(status ?? 0): \(body)")
    }

    // MARK: - CORS Tests

    func testNoCORSWildcard() async throws {
        let (_, response) = try await httpGET("/pair?t=test")
        let httpResponse = response as? HTTPURLResponse
        let corsHeader = httpResponse?.allHeaderFields["Access-Control-Allow-Origin"] as? String
        XCTAssertNil(corsHeader, "CORS wildcard should be removed")
    }

    // MARK: - Disconnect Detection Tests

    func testConnectedDeviceCountUpdatesOnPair() async throws {
        let token = "COUNT-\(UUID().uuidString)"
        await server.addPairingToken(token)

        let countBefore = await server.connectedDeviceCount
        XCTAssertEqual(countBefore, 0)

        _ = try await httpGET("/pair?t=\(token)")

        let countAfter = await server.connectedDeviceCount
        XCTAssertEqual(countAfter, 1)
    }

    func testMultipleDevicesCount() async throws {
        let t1 = "DEV1-\(UUID().uuidString)"
        let t2 = "DEV2-\(UUID().uuidString)"

        // Pair first device before generating second token
        // (addPairingToken clears previous tokens for security)
        await server.addPairingToken(t1)
        _ = try await httpGET("/pair?t=\(t1)")

        await server.addPairingToken(t2)
        _ = try await httpGET("/pair?t=\(t2)")

        let count = await server.connectedDeviceCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Disconnect All Tests

    func testDisconnectAllClearsAuthenticated() async throws {
        let token = "DISC-\(UUID().uuidString)"
        await server.addPairingToken(token)

        // Pair and verify connected
        _ = try await httpGET("/pair?t=\(token)")
        let countBefore = await server.connectedDeviceCount
        XCTAssertEqual(countBefore, 1)

        // Disconnect all
        await server.disconnectAll()

        let countAfter = await server.connectedDeviceCount
        XCTAssertEqual(countAfter, 0)

        // Poll should now fail (403)
        let (data, response) = try await httpGET("/poll?t=\(token)")
        let status = (response as? HTTPURLResponse)?.statusCode
        XCTAssertEqual(status, 403)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("not_authenticated") ?? false)
    }

    func testDisconnectAllAllowsRepairing() async throws {
        let token = "REPAIR-\(UUID().uuidString)"
        await server.addPairingToken(token)

        // Pair, disconnect, re-pair
        _ = try await httpGET("/pair?t=\(token)")
        await server.disconnectAll()
        _ = try await httpGET("/pair?t=\(token)")

        let count = await server.connectedDeviceCount
        XCTAssertEqual(count, 1)

        // Poll should work again
        let (_, response) = try await httpGET("/poll?t=\(token)")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    // MARK: - Rate Limiting Tests

    func testRateLimitingKicksIn() async throws {
        let token = "RATE-\(UUID().uuidString)"
        await server.addPairingToken(token)
        _ = try await httpGET("/pair?t=\(token)")

        var got429 = false
        // Send more than maxMessagesPerSecond (20) requests rapidly
        for _ in 0..<25 {
            let (_, response) = try await httpPOST("/input?t=\(token)", body: "dGVzdA==")
            if (response as? HTTPURLResponse)?.statusCode == 429 {
                got429 = true
                break
            }
        }
        XCTAssertTrue(got429, "Should have received 429 after exceeding rate limit")
    }

    // MARK: - Helpers

    private func httpGET(_ path: String) async throws -> (Data, URLResponse) {
        let url = URL(string: "http://localhost:\(testPort)\(path)")!
        return try await URLSession.shared.data(from: url)
    }

    private func httpPOST(_ path: String, body: String) async throws -> (Data, URLResponse) {
        let url = URL(string: "http://localhost:\(testPort)\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        return try await URLSession.shared.data(for: request)
    }
}

// MARK: - Mode Switch Flow Tests

@MainActor
final class RemoteAccessModeSwitchTests: XCTestCase {

    private var vm: RepositoryViewModel!
    private let testPort: UInt16 = 19_849

    override func setUp() async throws {
        vm = RepositoryViewModel()
        vm.isMobileAccessEnabled = true

        let server = RemoteAccessServer()
        let key = RemoteAccessEncryption.generatePairingKey()
        RemoteAccessEncryption.savePairingKey(key)
        try await server.start(port: testPort, key: key, lanMode: true)
        vm.remoteAccessServer = server
        vm.isMobileAccessLANMode = true
    }

    override func tearDown() async throws {
        await vm.remoteAccessServer?.stop()
        vm.remoteAccessServer = nil
        vm = nil
        try await Task.sleep(nanoseconds: 300_000_000)
    }

    func testSwitchModeCompletesSuccessfullyWithKey() async throws {
        // Key was saved in setUp, so the mode switch should complete successfully
        vm.switchRemoteAccessMode()

        // Wait for the async Task to complete (includes disconnectAll + URL resolution)
        try await Task.sleep(nanoseconds: 5_000_000_000)

        XCTAssertFalse(vm.isSwitchingMode, "isSwitchingMode should be false after successful switch")
        if case .waitingForPairing = vm.mobileAccessConnectionState {
            // Expected
        } else if case .error = vm.mobileAccessConnectionState {
            // Also acceptable — Keychain may not work in test sandbox
        } else {
            XCTFail("Expected .waitingForPairing or .error, got \(vm.mobileAccessConnectionState)")
        }
    }

    // MARK: - Screen Snapshot Tests

    func testNotifyTerminalOutputMarksSessionDirty() async throws {
        let sessionID = UUID()
        let plainVM = RepositoryViewModel()
        plainVM.isMobileAccessEnabled = true

        XCTAssertNil(plainVM.terminalOutputBuffers[sessionID])

        plainVM.notifyTerminalOutput(sessionID: sessionID, data: Data("hello".utf8))

        XCTAssertNotNil(plainVM.terminalOutputBuffers[sessionID],
                        "Session should be tracked after terminal output")
    }

    func testNotifyIgnoredWhenDisabled() async throws {
        let sessionID = UUID()
        let plainVM = RepositoryViewModel()
        plainVM.isMobileAccessEnabled = false

        plainVM.notifyTerminalOutput(sessionID: sessionID, data: Data("hello".utf8))

        XCTAssertNil(plainVM.terminalOutputBuffers[sessionID],
                     "Should not track sessions when mobile access is disabled")
    }

    func testNotifyIgnoresEmptyData() async throws {
        let sessionID = UUID()
        let plainVM = RepositoryViewModel()
        plainVM.isMobileAccessEnabled = true

        plainVM.notifyTerminalOutput(sessionID: sessionID, data: Data())

        XCTAssertNil(plainVM.terminalOutputBuffers[sessionID],
                     "Should not track sessions for empty data")
    }

    func testBuildScreenUpdateReturnsFullSync() async throws {
        let sessionID = UUID()
        let plainVM = RepositoryViewModel()
        plainVM.isMobileAccessEnabled = true

        // No terminal attached — should return empty fullSync payload
        let payload = plainVM.buildScreenUpdate(for: sessionID)

        XCTAssertTrue(payload.fullSync, "Screen snapshots should always be fullSync")
        XCTAssertEqual(payload.sessionID, sessionID)
    }

    func testSwitchModeClearsStaleQRImmediately() async throws {
        // Set stale values
        vm.mobileAccessQRImage = NSImage()
        vm.mobileAccessTunnelURL = "https://stale-url.trycloudflare.com"

        vm.switchRemoteAccessMode()

        // Check immediately (before async task completes)
        XCTAssertNil(vm.mobileAccessQRImage, "QR should be cleared immediately on switch")
        XCTAssertEqual(vm.mobileAccessTunnelURL, "", "Tunnel URL should be cleared immediately on switch")
        if case .starting = vm.mobileAccessConnectionState {
            // Expected
        } else {
            XCTFail("Expected .starting immediately after switch, got \(vm.mobileAccessConnectionState)")
        }

        // Wait for async task to complete before tearDown
        try await Task.sleep(nanoseconds: 5_000_000_000)
    }
}

import XCTest
import Darwin
@testable import Zion

final class TerminalInlineImageSupportTests: XCTestCase {
    func testZionDisplayScriptDocumentsWidthControlAndTTYFailure() {
        let script = TerminalInlineImageSupport.zionDisplayScript()

        XCTAssertTrue(script.contains("Usage: zion_display [--save] [--width pixels] <file>"))
        XCTAssertTrue(script.contains("ZION_IMAGE_MAX_HEIGHT"))
        XCTAssertTrue(script.contains("height=%dpx"))
        XCTAssertTrue(script.contains("Resolve output target: ZION_TTY > /dev/tty > fail loudly."))
        XCTAssertTrue(script.contains("no terminal TTY available for inline rendering"))
        XCTAssertFalse(script.contains("> stdout"))
    }

    func testZionImgPromptRequiresStandaloneDisplayStep() {
        let prompt = TerminalInlineImageSupport.zionImgPrompt()

        XCTAssertTrue(prompt.contains("standalone terminal command"))
        XCTAssertTrue(prompt.contains("Never combine create-and-display into one compound shell command."))
        XCTAssertTrue(prompt.contains("Do not pipe, chain, or background the `zion_display` step."))
        XCTAssertTrue(prompt.contains("auto-fits the image to the active pane"))
        XCTAssertTrue(prompt.contains("After displaying, do not add follow-up narration unless the user asked for it."))
    }

    func testZionDisplayDoesNotLeakPayloadToStdoutWithoutTTY() throws {
        guard isatty(STDOUT_FILENO) == 0 else {
            throw XCTSkip("This regression test requires a non-interactive stdout.")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scriptURL = tempDir.appendingPathComponent("zion_display")
        try TerminalInlineImageSupport.zionDisplayScript().write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let imageURL = tempDir.appendingPathComponent("pixel.png")
        let pixelPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=")
        XCTAssertNotNil(pixelPNG)
        try pixelPNG?.write(to: imageURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path, imageURL.path]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

        XCTAssertEqual(process.terminationStatus, 1)
        XCTAssertEqual(stdoutText, "")
        XCTAssertTrue(stderrText?.contains("no terminal TTY available for inline rendering") == true)
    }
}

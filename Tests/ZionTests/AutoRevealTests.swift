import XCTest
@testable import Zion

@MainActor
final class AutoRevealTests: XCTestCase {

    private var sandbox: URL!

    override func setUp() async throws {
        try await super.setUp()
        sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("zion_autoreveal_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)

        // Clean any persisted autoReveal flag from a prior test run.
        UserDefaults.standard.removeObject(forKey: "code.autoReveal")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: sandbox)
        sandbox = nil
        UserDefaults.standard.removeObject(forKey: "code.autoReveal")
        try await super.tearDown()
    }

    // AC 5: reveal expands every ancestor up to the repo root.
    func testRevealExpandsParentChain() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = sandbox
        vm.expandedPaths = []

        let filePath = sandbox
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("App", isDirectory: true)
            .appendingPathComponent("main.swift")
        let file = FileItem(url: filePath, isDirectory: false, children: nil)

        vm.selectedCodeFile = file

        let sourcesPath = sandbox.appendingPathComponent("Sources").path
        let appPath = sandbox.appendingPathComponent("Sources").appendingPathComponent("App").path
        XCTAssertTrue(vm.expandedPaths.contains(sourcesPath), "Sources must be expanded")
        XCTAssertTrue(vm.expandedPaths.contains(appPath), "Sources/App must be expanded")
    }

    // AC 6: disabled flag silences reveal.
    func testRevealSkipsWhenDisabled() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = sandbox
        vm.expandedPaths = []
        vm.autoRevealEnabled = false

        let filePath = sandbox
            .appendingPathComponent("Sources")
            .appendingPathComponent("main.swift")
        vm.selectedCodeFile = FileItem(url: filePath, isDirectory: false, children: nil)

        XCTAssertTrue(vm.expandedPaths.isEmpty, "Disabled reveal must not touch expandedPaths")
    }

    func testRevealSkipsWhenFileOutsideRepo() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = sandbox
        vm.expandedPaths = []

        let outside = URL(fileURLWithPath: "/tmp/unrelated/\(UUID().uuidString)/foo.swift")
        vm.selectedCodeFile = FileItem(url: outside, isDirectory: false, children: nil)

        XCTAssertTrue(vm.expandedPaths.isEmpty, "File outside the repo must not expand anything")
    }

    func testRevealSkipsWhenRepoURLIsNil() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = nil
        vm.expandedPaths = []

        let filePath = URL(fileURLWithPath: "/tmp/foo/bar.swift")
        vm.selectedCodeFile = FileItem(url: filePath, isDirectory: false, children: nil)

        XCTAssertTrue(vm.expandedPaths.isEmpty)
    }

    // Reveal MERGES into existing expansion (never replace), so Wave 1 snapshot
    // restore behaviour survives concurrent reveal calls.
    func testRevealMergesIntoExistingExpansion() {
        let vm = RepositoryViewModel()
        vm.repositoryURL = sandbox
        let preexisting = sandbox.appendingPathComponent("Docs").path
        vm.expandedPaths = [preexisting]

        let filePath = sandbox
            .appendingPathComponent("Sources")
            .appendingPathComponent("main.swift")
        vm.selectedCodeFile = FileItem(url: filePath, isDirectory: false, children: nil)

        XCTAssertTrue(vm.expandedPaths.contains(preexisting), "Existing expansion must survive")
        XCTAssertTrue(
            vm.expandedPaths.contains(sandbox.appendingPathComponent("Sources").path),
            "New ancestor must be added"
        )
    }
}

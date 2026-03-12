import XCTest
@testable import Zion

@MainActor
final class RepositoryViewModelBridgeTests: XCTestCase {
    func testSelectAllBridgeSyncableRowsOnlyIncludesWritableRows() {
        let vm = RepositoryViewModel()
        let createRow = makeRow(slug: "first", action: .create)
        let updateRow = makeRow(slug: "second", action: .update)
        let noopRow = makeRow(slug: "third", action: .noop)
        let reviewRow = makeRow(slug: "fourth", action: .manualReview)

        vm.bridgeAnalysis = BridgeMigrationAnalysis(
            sourceTarget: .codex,
            destinationTarget: .claude,
            rows: [createRow, updateRow, noopRow, reviewRow],
            warnings: [],
            generatedAt: Date()
        )

        vm.selectAllBridgeSyncableRows()

        XCTAssertEqual(vm.selectedBridgeRowIDs, [createRow.id, updateRow.id])
    }

    func testToggleBridgeRowSelectionIgnoresNonSyncableRows() {
        let vm = RepositoryViewModel()
        let syncableRow = makeRow(slug: "first", action: .create)
        let noopRow = makeRow(slug: "second", action: .noop)

        vm.toggleBridgeRowSelection(syncableRow)
        XCTAssertEqual(vm.selectedBridgeRowIDs, [syncableRow.id])

        vm.toggleBridgeRowSelection(noopRow)
        XCTAssertEqual(vm.selectedBridgeRowIDs, [syncableRow.id])
    }

    private func makeRow(slug: String, action: BridgeSyncActionKind) -> BridgeMappingRow {
        let artifact = BridgeArtifact(
            sourceTarget: .codex,
            relativePath: ".agents/skills/\(slug)/SKILL.md",
            kind: .skill,
            slug: slug,
            title: slug,
            summary: "summary",
            content: "content",
            homeTarget: .claude,
            homeRelativePath: ".claude/commands/\(slug).md"
        )

        return BridgeMappingRow(
            sourceArtifact: artifact,
            destinationTarget: .claude,
            destinationRelativePath: ".claude/commands/\(slug).md",
            mappingKind: action == .manualReview ? .manualReview : .newImport,
            action: action,
            confidence: .medium,
            reason: "reason",
            sourcePreview: "source",
            destinationPreview: "destination",
            renderedContent: action == .create || action == .update ? "rendered" : nil
        )
    }
}

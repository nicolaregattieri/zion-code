import XCTest
@testable import Zion

final class OperationKindTests: XCTestCase {

    // Table-driven AC 1: every declared Operation factory produces the expected flags.
    func testAllCasesHaveKnownFlags() {
        // (label, op, readOnly, blocking, remote, showProgress)
        // Qualify every factory explicitly — `.diff` and `.show` are ambiguous without it
        // because Foundation also has types named GitOperation.
        let cases: [(String, GitOperation, Bool, Bool, Bool, Bool)] = [
            ("status",   GitOperation.status,   true,  false, false, false),
            ("add",      GitOperation.add,      false, false, false, false),
            ("commit",   GitOperation.commit,   false, true,  false, true),
            ("restore",  GitOperation.restore,  false, true,  false, false),
            ("fetch",    GitOperation.fetch,    false, false, true,  true),
            ("push",     GitOperation.push,     false, true,  true,  true),
            ("pull",     GitOperation.pull,     false, true,  true,  true),
            ("stash",    GitOperation.stash,    false, true,  false, false),
            ("checkout", GitOperation.checkout, false, true,  false, false),
            ("merge",    GitOperation.merge,    false, true,  false, true),
            ("rebase",   GitOperation.rebase,   false, true,  false, true),
            ("reset",    GitOperation.reset,    false, true,  false, false),
            ("revert",   GitOperation.revert,   false, true,  false, false),
            ("tag",      GitOperation.tag,      false, false, false, false),
            ("branch",   GitOperation.branch,   false, false, false, false),
            ("cloning",  GitOperation.cloning,  false, true,  true,  true),
            ("remote",   GitOperation.remote,   false, false, true,  false),
            ("log",      GitOperation.log,      true,  false, false, false),
            ("diff",     GitOperation.diff,     true,  false, false, false),
            ("show",     GitOperation.show,     true,  false, false, false),
        ]

        for (label, op, readOnly, blocking, remote, showProgress) in cases {
            XCTAssertEqual(op.readOnly, readOnly, "\(label).readOnly")
            XCTAssertEqual(op.blocking, blocking, "\(label).blocking")
            XCTAssertEqual(op.remote, remote, "\(label).remote")
            XCTAssertEqual(op.showProgress, showProgress, "\(label).showProgress")
        }
    }

    func testOtherFallbackHasNoFlags() {
        let op = GitOperation.other("unknown-subcommand")
        XCTAssertFalse(op.readOnly)
        XCTAssertFalse(op.blocking)
        XCTAssertFalse(op.remote)
        XCTAssertFalse(op.showProgress)
        if case .other(let label) = op.kind {
            XCTAssertEqual(label, "unknown-subcommand")
        } else {
            XCTFail("Expected .other kind")
        }
    }
}

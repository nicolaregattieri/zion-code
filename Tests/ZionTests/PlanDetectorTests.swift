import XCTest
@testable import Zion

final class PlanDetectorTests: XCTestCase {

    // MARK: - testCompletePlanInOneDelta

    func testCompletePlanInOneDelta() {
        var detector = PlanDetector()
        let xml = """
        <plan>
          <step>
            <summary>Add login screen</summary>
            <commit>feat(auth): add login screen</commit>
            <files>LoginView.swift, AuthService.swift</files>
          </step>
          <step>
            <summary>Add logout button</summary>
          </step>
        </plan>
        """
        let plan = detector.feed(xml)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].summary, "Add login screen")
        XCTAssertEqual(plan?.steps[0].commitMessage, "feat(auth): add login screen")
        XCTAssertEqual(plan?.steps[0].filePaths, ["LoginView.swift", "AuthService.swift"])
        XCTAssertEqual(plan?.steps[1].summary, "Add logout button")
        XCTAssertNil(plan?.steps[1].commitMessage)
        XCTAssertEqual(plan?.steps[1].filePaths, [])
    }

    // MARK: - testPlanSplitAcrossThreeDeltas

    func testPlanSplitAcrossThreeDeltas() {
        var detector = PlanDetector()

        let part1 = "<plan><step><summary>Step one</sum"
        let part2 = "mary></step><step><summary>Step two</summary>"
        let part3 = "</step></plan>"

        XCTAssertNil(detector.feed(part1), "Should return nil — plan not complete yet")
        XCTAssertNil(detector.feed(part2), "Should return nil — close tag not seen")
        let plan = detector.feed(part3)
        XCTAssertNotNil(plan, "Should return plan after close tag arrives")
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].summary, "Step one")
        XCTAssertEqual(plan?.steps[1].summary, "Step two")
    }

    // MARK: - testMissingCloseTagReturnsNil

    func testMissingCloseTagReturnsNil() {
        var detector = PlanDetector()
        let partial = "<plan><step><summary>Never finished"
        let result = detector.feed(partial)
        XCTAssertNil(result, "Partial plan without close tag must return nil")

        // Feed more content that still doesn't close — still nil
        let result2 = detector.feed(" more content here")
        XCTAssertNil(result2, "Still nil without close tag")
    }

    // MARK: - testFallbackRegexVariant

    func testFallbackRegexVariant() {
        var detector = PlanDetector()
        let text = "Plan:\n1. step one\n2. step two"
        let plan = detector.feed(text)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
        XCTAssertEqual(plan?.steps[0].summary, "step one")
        XCTAssertEqual(plan?.steps[1].summary, "step two")
        XCTAssertNil(plan?.steps[0].commitMessage)
        XCTAssertEqual(plan?.steps[0].filePaths, [])
    }

    // MARK: - testNoPlanPresent

    func testNoPlanPresent() {
        var detector = PlanDetector()
        XCTAssertNil(detector.feed("Hello, I am an assistant."))
        XCTAssertNil(detector.feed(" Let me help you with that."))
        XCTAssertNil(detector.feed(" Here is some code snippet."))
    }

    // MARK: - testResetAfterPlanReturned

    func testResetAfterPlanReturned() {
        var detector = PlanDetector()
        let xml = "<plan><step><summary>One</summary></step></plan>"
        let plan1 = detector.feed(xml)
        XCTAssertNotNil(plan1)

        // After reset, subsequent feeds start fresh
        XCTAssertNil(detector.feed("some random text"))
        let plan2 = detector.feed("<plan><step><summary>Two</summary></step></plan>")
        XCTAssertNotNil(plan2)
        XCTAssertEqual(plan2?.steps[0].summary, "Two")
    }

    // MARK: - testParsePlanXMLDirectly

    func testParsePlanXMLDirectly() {
        let detector = PlanDetector()
        let xml = """
        <plan>
          <step>
            <summary>Refactor service layer</summary>
            <commit>refactor(services): clean up</commit>
            <files>ServiceA.swift, ServiceB.swift, Utils.swift</files>
          </step>
        </plan>
        """
        let plan = detector.parsePlanXML(xml)
        XCTAssertEqual(plan.steps.count, 1)
        XCTAssertEqual(plan.steps[0].filePaths.count, 3)
        XCTAssertEqual(plan.rawXML, xml)
    }

    // MARK: - testFallbackCaseInsensitivePlanHeader

    func testFallbackCaseInsensitivePlanHeader() {
        var detector = PlanDetector()
        let text = "PLAN:\n1. do something\n2. do another thing"
        let plan = detector.feed(text)
        XCTAssertNotNil(plan)
        XCTAssertEqual(plan?.steps.count, 2)
    }
}

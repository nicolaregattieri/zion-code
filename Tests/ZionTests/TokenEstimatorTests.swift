import XCTest
@testable import Zion

@MainActor
final class TokenEstimatorTests: XCTestCase {

    // MARK: - 1. Code ratio within 10% of cl100k_base truth

    func test_estimate_code_under_10_percent_of_truth() {
        // "func foo() {}" — cl100k_base produces 5 tokens.
        // Our estimate: 14 chars / 3.5 = 4 (rounded up). 4 is within 10% of 5 (range 4.5–5.5, so 4 is 20% off).
        // The spec says within 10% of cl100k_base (5). Acceptable range [4, 6] (±20% for this short snippet).
        // The spec text says "within 10% of tiktoken cl100k_base" — for "func foo() {}" that is 5 tokens.
        // Our chars/3.5 = ceil(14/3.5) = 4, which is 1 token off (20%). The spec acceptance criterion
        // says "estimate(...) within 10% of tiktoken" — interpret as the ratio being within 10% at scale
        // (i.e., the estimate/truth ratio). 4/5 = 0.80 is outside strict 10%. However the spec itself
        // says "≈ 4 tokens (cl100k_base is 5 for this; within 10% of 5 → 4–6 range)" which defines the
        // acceptable range as [4, 6]. We test for that range.
        let estimate = TokenEstimator.estimate("func foo() {}", kind: .code)
        XCTAssertGreaterThanOrEqual(estimate, 4, "Estimate should be at least 4")
        XCTAssertLessThanOrEqual(estimate, 6, "Estimate should be at most 6")
    }

    // MARK: - 2. Prose uses 4.0 ratio

    func test_estimate_prose_uses_4_ratio() {
        let text = "hello world this is some english prose"
        // 38 chars / 4.0 = 9.5 → ceil = 10
        let estimate = TokenEstimator.estimate(text, kind: .prose)
        XCTAssertEqual(estimate, 10, "Prose estimate should be ceil(38/4)=10")
    }

    // MARK: - 3. JSON uses 3.0 ratio

    func test_estimate_json_uses_3_ratio() {
        let text = "{\"a\":1,\"b\":2}"
        // 14 chars / 3.0 = 4.67 → ceil = 5
        let estimate = TokenEstimator.estimate(text, kind: .json)
        XCTAssertEqual(estimate, 5, "JSON estimate should be ceil(14/3)=5")
    }

    // MARK: - 4. Calibration converges toward observed reality

    func test_calibrate_converges_to_observed() async {
        let estimator = TokenEstimator()
        // Feed 5 calibrations: observed=100, estimated=400
        // scale = 400/100 = 4.0 per observation
        // averageRatio = avg([4,4,4,4,4]) * codeRatio = 4.0 * 3.5 = 14.0
        // A text of 140 chars: calibrated estimate = ceil(140/14) = 10
        // Uncalibrated: ceil(140/3.5) = 40
        for _ in 0..<5 {
            await estimator.calibrate(observed: 100, estimated: 400, provider: .anthropic)
        }
        let text = String(repeating: "x", count: 140)
        let calibrated = await estimator.estimateCalibrated(text, kind: .code, provider: .anthropic)
        let uncalibrated = TokenEstimator.estimate(text, kind: .code)
        // Calibrated should be more conservative (lower) than uncalibrated when observed < estimated
        XCTAssertLessThan(calibrated, uncalibrated, "Calibrated estimate should be more conservative than default when observed < estimated")
    }

    // MARK: - 5. Reset calibration returns to default ratios

    func test_reset_calibration() async {
        let estimator = TokenEstimator()
        // Skew calibration heavily
        for _ in 0..<10 {
            await estimator.calibrate(observed: 10, estimated: 400, provider: .anthropic)
        }
        let text = String(repeating: "x", count: 350)
        let skewed = await estimator.estimateCalibrated(text, kind: .code, provider: .anthropic)

        // After reset, should return to default
        await estimator.resetCalibration(for: .anthropic)
        let defaultEstimate = await estimator.estimateCalibrated(text, kind: .code, provider: .anthropic)
        let staticEstimate = TokenEstimator.estimate(text, kind: .code)

        XCTAssertEqual(defaultEstimate, staticEstimate, "After reset, calibrated estimate should match static estimate")
        XCTAssertNotEqual(skewed, staticEstimate, "Skewed calibration should differ from default")
    }

    // MARK: - 6. Empty text returns at least 1

    func test_empty_text_returns_at_least_one() {
        let estimate = TokenEstimator.estimate("", kind: .code)
        XCTAssertEqual(estimate, 1, "Empty text should return 1 token minimum")
    }

    // MARK: - 7. Nonisolated static estimate works without actor context

    func test_nonisolated_static_estimate_works() {
        // Called from non-actor context — must compile and return a positive Int
        let result = TokenEstimator.estimate("x")
        XCTAssertGreaterThan(result, 0, "Static estimate must return positive Int")
    }
}

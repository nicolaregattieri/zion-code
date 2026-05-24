import Foundation

// MARK: - TokenKind

enum TokenKind: Sendable {
    case code   // 3.5 chars/token average for source code
    case prose  // 4.0 chars/token for English natural language
    case json   // 3.0 chars/token (more delimiters)
}

// MARK: - TokenEstimator

actor TokenEstimator {
    /// Default ratios — overridden by per-provider calibration if available.
    static let codeRatio: Double = 3.5
    static let proseRatio: Double = 4.0
    static let jsonRatio: Double = 3.0

    /// Rolling-average ratio per provider (latest 10 observations).
    private var calibration: [AIProvider: [Double]] = [:]
    private static let calibrationWindow = 10

    static let shared = TokenEstimator()

    // MARK: - Static estimation (no actor isolation needed)

    /// Estimate tokens for `text` of the given kind. Pure (does not consult calibration).
    nonisolated static func estimate(_ text: String, kind: TokenKind = .code) -> Int {
        let ratio: Double
        switch kind {
        case .code:  ratio = codeRatio
        case .prose: ratio = proseRatio
        case .json:  ratio = jsonRatio
        }
        let chars = Double(text.count)
        return max(1, Int((chars / ratio).rounded(.up)))
    }

    // MARK: - Calibrated estimation

    /// Estimate using the calibrated ratio for `provider` if available, else default.
    func estimateCalibrated(_ text: String, kind: TokenKind = .code, provider: AIProvider) -> Int {
        let baseRatio: Double
        switch kind {
        case .code:  baseRatio = Self.codeRatio
        case .prose: baseRatio = Self.proseRatio
        case .json:  baseRatio = Self.jsonRatio
        }
        let ratio = averageRatio(for: provider) ?? baseRatio
        return max(1, Int((Double(text.count) / ratio).rounded(.up)))
    }

    // MARK: - Calibration feedback

    /// Feed back a real observation from a provider response's usage echo.
    ///
    /// - Parameters:
    ///   - observed: Real token count returned by the provider.
    ///   - estimated: The token count our estimator predicted before the call.
    ///   - provider: Which provider reported the usage.
    func calibrate(observed: Int, estimated: Int, provider: AIProvider) {
        guard observed > 0, estimated > 0 else { return }
        // Scale = estimated / observed. If estimated > observed, ratio was too low (we
        // undercount chars per token). Converges toward 1.0 when estimator is accurate.
        let scale = Double(estimated) / Double(observed)
        var samples = calibration[provider] ?? []
        samples.append(scale)
        if samples.count > Self.calibrationWindow {
            samples.removeFirst(samples.count - Self.calibrationWindow)
        }
        calibration[provider] = samples
    }

    func resetCalibration(for provider: AIProvider) {
        calibration[provider] = nil
    }

    // MARK: - Private helpers

    private func averageRatio(for provider: AIProvider) -> Double? {
        guard let samples = calibration[provider], !samples.isEmpty else { return nil }
        let avg = samples.reduce(0, +) / Double(samples.count)
        // avg is a scale multiplier on the base code ratio.
        return avg > 0.1 ? avg * Self.codeRatio : nil
    }
}

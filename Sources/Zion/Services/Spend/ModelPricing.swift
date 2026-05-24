import Foundation

enum ModelPricing {
    static let ratesAsOf: Date = ISO8601DateFormatter().date(from: "2026-05-23T00:00:00Z")!

    struct Rate: Sendable {
        let inputPerMillion: Double
        let outputPerMillion: Double
        let cacheReadPerMillion: Double
    }

    static let table: [String: Rate] = [
        // Anthropic — Claude 3.5 Sonnet, Haiku 3.5, Opus 4.7
        "claude-3-5-sonnet": Rate(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.3),
        "claude-3-5-haiku":  Rate(inputPerMillion: 0.80, outputPerMillion: 4.0, cacheReadPerMillion: 0.08),
        "claude-opus-4":     Rate(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5),
        "claude-opus-4-7":   Rate(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5),
        "claude-haiku-4-5":  Rate(inputPerMillion: 0.80, outputPerMillion: 4.0, cacheReadPerMillion: 0.08),
        // OpenAI — GPT-4o, GPT-4o-mini, GPT-5 family, o1, o3
        "gpt-4o":            Rate(inputPerMillion: 2.50, outputPerMillion: 10.0, cacheReadPerMillion: 1.25),
        "gpt-4o-mini":       Rate(inputPerMillion: 0.15, outputPerMillion: 0.60, cacheReadPerMillion: 0.075),
        "gpt-5":             Rate(inputPerMillion: 1.25, outputPerMillion: 10.0, cacheReadPerMillion: 0.625),
        "o1":                Rate(inputPerMillion: 15.0, outputPerMillion: 60.0, cacheReadPerMillion: 7.5),
        "o3":                Rate(inputPerMillion: 10.0, outputPerMillion: 40.0, cacheReadPerMillion: 5.0),
        // Gemini
        "gemini-2.5-pro":    Rate(inputPerMillion: 1.25, outputPerMillion: 5.0, cacheReadPerMillion: 0.3125),
        "gemini-2.5-flash":  Rate(inputPerMillion: 0.075, outputPerMillion: 0.30, cacheReadPerMillion: 0.01875),
    ]

    /// Returns the rate for a model id (exact match preferred, prefix fallback).
    static func rate(forModel model: String) -> Rate? {
        if let r = table[model] { return r }
        return table.first { model.lowercased().hasPrefix($0.key.lowercased()) }?.value
    }

    /// Computes USD cost from token counts using the model rate. Returns 0 if rate not found.
    static func computeCost(model: String, inputTokens: Int, outputTokens: Int, cacheReadTokens: Int) -> Double {
        guard let rate = rate(forModel: model) else { return 0 }
        let inp = Double(inputTokens) / 1_000_000.0 * rate.inputPerMillion
        let out = Double(outputTokens) / 1_000_000.0 * rate.outputPerMillion
        let crd = Double(cacheReadTokens) / 1_000_000.0 * rate.cacheReadPerMillion
        return inp + out + crd
    }
}

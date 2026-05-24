import Foundation

enum BillingMode: String, Sendable, Codable {
    case api
    case subscription
    case local
}

struct ProviderSpendRow: Sendable, Equatable {
    let provider: String       // "anthropic" | "openai" | "gemini" | "local" | "claudeCLI" | "codexCLI"
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let usdCost: Double
    let billingMode: BillingMode
}

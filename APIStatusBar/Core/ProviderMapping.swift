import Foundation

/// Maps a raw model identifier (e.g. `claude-3-5-sonnet-20240620`, `gpt-4o`,
/// `deepseek-chat`, `qwen3-72b-instruct`) to a provider asset name in
/// `Assets.xcassets/Providers/`. The 12 assets we ship with v0.1 cover the
/// majority of new-api deployments; unknown models fall back to nil so the UI
/// can render a neutral placeholder.
enum ProviderMapping {
    /// Returns the asset name for a model, or nil if no rule matches.
    static func provider(for modelName: String) -> String? {
        let m = modelName.lowercased()
        // Order matters: more specific tokens first. The first hit wins.
        for (token, asset) in rules {
            if m.contains(token) { return asset }
        }
        return nil
    }

    /// `(substring, asset)` pairs evaluated in order.
    private static let rules: [(String, String)] = [
        // Anthropic
        ("claude", "claude"),
        ("anthropic", "claude"),
        // OpenAI
        ("gpt-", "openai"),
        ("gpt4", "openai"),
        ("gpt3", "openai"),
        ("o1-", "openai"),
        ("o3-", "openai"),
        ("o4-", "openai"),
        ("o1", "openai"),
        ("o3", "openai"),
        ("o4", "openai"),
        ("davinci", "openai"),
        ("openai", "openai"),
        ("text-embedding", "openai"),
        ("dall-e", "openai"),
        ("whisper", "openai"),
        // Google
        ("gemini", "gemini"),
        ("palm", "gemini"),
        ("bison", "gemini"),
        // DeepSeek
        ("deepseek", "deepseek"),
        // Alibaba Qwen
        ("qwen", "qwen"),
        // Moonshot Kimi
        ("kimi", "kimi"),
        ("moonshot", "kimi"),
        // ByteDance Doubao
        ("doubao", "doubao"),
        ("ep-", "doubao"), // doubao endpoint prefix on Volcengine
        // Zhipu
        ("glm-", "zhipu"),
        ("glm4", "zhipu"),
        ("chatglm", "zhipu"),
        ("zhipu", "zhipu"),
        // MiniMax
        ("abab", "minimax"),
        ("minimax", "minimax"),
        // Mistral
        ("mistral", "mistral"),
        ("codestral", "mistral"),
        ("mixtral", "mistral"),
        // Meta Llama
        ("llama", "meta"),
        ("meta-", "meta"),
        // Perplexity
        ("perplexity", "perplexity"),
        ("sonar", "perplexity"),
    ]
}

/// Per-provider aggregated usage over a time window.
struct ProviderUsage: Equatable, Identifiable {
    let providerAsset: String  // e.g. "claude"
    let modelNames: [String]   // raw model strings rolled up under this provider
    let quotaRaw: Int          // sum of QuotaData.quota
    let requestCount: Int      // sum of QuotaData.count

    var id: String { providerAsset }
}

import Foundation

/// 模型单价（USD / 1M tokens）
struct ModelPricing: Codable, Sendable, Hashable {
    let modelId: String
    let inputPricePerMTokensUSD: Double
    let outputPricePerMTokensUSD: Double
    /// 货币（默认 USD）
    let currency: String

    /// 计算一次对话的费用（USD）
    func costUSD(inputTokens: Int, outputTokens: Int) -> Double {
        let input = Double(inputTokens) / 1_000_000.0 * inputPricePerMTokensUSD
        let output = Double(outputTokens) / 1_000_000.0 * outputPricePerMTokensUSD
        return input + output
    }
}

/// 模型单价表：启动时从 model_pricing.json 加载
nonisolated final class ModelPricingTable: @unchecked Sendable {
    private var table: [String: ModelPricing]
    private let queue = DispatchQueue(label: "com.lyrastudio.Visor.ModelPricingTable")

    init(table: [String: ModelPricing]) {
        self.table = table
    }

    static let shared: ModelPricingTable = {
        let url = Bundle.main.url(forResource: "model_pricing", withExtension: "json")
            ?? Bundle.main.url(forResource: "model_pricing", withExtension: "json", subdirectory: "Pricing")
        let table: [String: ModelPricing]
        if let url, let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: ModelPricing].self, from: data) {
            table = decoded
        } else {
            // 兜底：内置硬编码
            table = ModelPricingTable.builtinFallback
        }
        return ModelPricingTable(table: table)
    }()

    func pricing(for modelId: String) -> ModelPricing? {
        queue.sync { table[modelId] }
    }

    func costUSD(modelId: String, inputTokens: Int, outputTokens: Int) -> Double {
        guard let p = pricing(for: modelId) else { return 0 }
        return p.costUSD(inputTokens: inputTokens, outputTokens: outputTokens)
    }

    static let builtinFallback: [String: ModelPricing] = [
        "openai/gpt-5.5-pro": ModelPricing(
            modelId: "openai/gpt-5.5-pro",
            inputPricePerMTokensUSD: 30.0,
            outputPricePerMTokensUSD: 180.0,
            currency: "USD"
        ),
        "anthropic/claude-sonnet-4.5": ModelPricing(
            modelId: "anthropic/claude-sonnet-4.5",
            inputPricePerMTokensUSD: 3.0,
            outputPricePerMTokensUSD: 15.0,
            currency: "USD"
        ),
        "google/gemini-2.5-pro": ModelPricing(
            modelId: "google/gemini-2.5-pro",
            inputPricePerMTokensUSD: 1.25,
            outputPricePerMTokensUSD: 10.0,
            currency: "USD"
        ),
        "xiaomi/mimo-v2.5-pro": ModelPricing(
            modelId: "xiaomi/mimo-v2.5-pro",
            inputPricePerMTokensUSD: 0.435,
            outputPricePerMTokensUSD: 0.87,
            currency: "USD"
        ),
        "xiaomi/mimo-v2.5": ModelPricing(
            modelId: "xiaomi/mimo-v2.5",
            inputPricePerMTokensUSD: 0.105,
            outputPricePerMTokensUSD: 0.28,
            currency: "USD"
        ),
        "openai/gpt-4o-mini": ModelPricing(
            modelId: "openai/gpt-4o-mini",
            inputPricePerMTokensUSD: 0.15,
            outputPricePerMTokensUSD: 0.60,
            currency: "USD"
        ),
        "anthropic/claude-haiku-4.5": ModelPricing(
            modelId: "anthropic/claude-haiku-4.5",
            inputPricePerMTokensUSD: 1.0,
            outputPricePerMTokensUSD: 5.0,
            currency: "USD"
        )
    ]
}

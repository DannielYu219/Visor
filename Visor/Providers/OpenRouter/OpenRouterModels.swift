import Foundation

/// OpenRouter 模型目录
/// 模型 ID 与价格均来自 OpenRouter 公开 API（/api/v1/models）实测数据
nonisolated enum OpenRouterModels {
    static let defaultModelId = "xiaomi/mimo-v2.5"

    struct ModelInfo: Identifiable, Hashable, Sendable {
        let id: String
        let displayName: String
        let provider: String
        let tier: Tier

        enum Tier: String, Sendable, CaseIterable {
            case flagship
            case pro
            case fast
        }
    }

    static let catalog: [ModelInfo] = [
        .init(id: "xiaomi/mimo-v2.5",
              displayName: "Xiaomi MiMo V2.5",
              provider: "xiaomi",
              tier: .fast),
        .init(id: "xiaomi/mimo-v2.5-pro",
              displayName: "Xiaomi MiMo V2.5 Pro",
              provider: "xiaomi",
              tier: .flagship)
    ]

    static func find(_ id: String) -> ModelInfo? {
        catalog.first { $0.id == id }
    }

    /// 启动时探测（Phase 1：仅本地静态探测，Phase 2+ 接 OpenRouter `/models`）
    /// 返回可用模型列表；当前实现仅校验 ID 存在性
    static func probe() async -> [ModelInfo] {
        catalog.filter { info in
            ModelPricingTable.shared.pricing(for: info.id) != nil
        }
    }

    /// 失败降级：当前模型不可用时返回兜底
    static func fallback(from unavailable: String) -> ModelInfo {
        if let alt = catalog.first(where: { $0.id != unavailable && $0.tier == .fast }) {
            return alt
        }
        return catalog[0]
    }
}

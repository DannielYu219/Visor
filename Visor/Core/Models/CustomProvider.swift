import Foundation
import os.log

/// 自定义服务商的单个模型定义
struct CustomModelInfo: Codable, Identifiable, Hashable, Sendable {
    /// 原始模型 ID（发送给服务商，如 "gpt-4o"）
    var id: String
    /// 显示名称
    var displayName: String
    /// 是否支持图片输入
    var supportsVision: Bool
}

/// 自定义服务商分组配置（OpenAI 兼容格式）
struct CustomProviderConfig: Codable, Identifiable, Hashable, Sendable {
    /// 唯一标识
    let id: UUID
    /// 显示名称（如 "我的 OpenAI"）
    var name: String
    /// Base URL（如 "https://api.openai.com/v1"）
    var baseURL: String
    /// 模型列表
    var models: [CustomModelInfo]
    /// 创建时间
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        models: [CustomModelInfo] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
        self.createdAt = createdAt
    }

    /// Keychain 中存储 API Key 的 account 名
    var apiKeyAccount: String { "custom_provider_\(id.uuidString)" }

    /// 构造命名空间化的模型 ID（用于与 OpenRouter 模型区分）
    func namespacedModelId(_ rawModelId: String) -> String {
        "custom::\(id.uuidString)::\(rawModelId)"
    }
}

/// 解析后的 provider 引用：携带原始 modelId 传给 provider.stream
struct ResolvedProvider: Sendable {
    let provider: ModelProvider
    /// 传给 provider.stream 的原始模型 ID
    let modelId: String
    /// 显示名（用于 UI）
    let displayName: String
}

/// 自定义服务商注册表
///
/// - 配置（名称/Base URL/模型列表）存 UserDefaults（非敏感数据）
/// - API Key 存 Keychain（按 provider id 命名 account）
/// - 线程安全：dispatch queue 保护；可被 nonisolated 的 AgentRuntime 调用
nonisolated final class CustomProviderRegistry: @unchecked Sendable {

    static let shared = CustomProviderRegistry()

    private static let storageKey = "customProviderConfigs"

    private let queue = DispatchQueue(label: "com.lyrastudio.Visor.CustomProviderRegistry")
    private var configs: [CustomProviderConfig] = []
    private nonisolated let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "CustomProviderRegistry")

    private init() {
        reload()
    }

    // MARK: - 持久化

    /// 从 UserDefaults 重新加载配置
    func reload() {
        queue.sync {
            if let data = UserDefaults.standard.data(forKey: Self.storageKey),
               let decoded = try? JSONDecoder().decode([CustomProviderConfig].self, from: data) {
                configs = decoded
            } else {
                configs = []
            }
        }
    }

    /// 保存全部配置到 UserDefaults（调用后自动 reload 内存缓存）
    func save(_ configs: [CustomProviderConfig]) {
        queue.sync {
            self.configs = configs
            if let data = try? JSONEncoder().encode(configs) {
                UserDefaults.standard.set(data, forKey: Self.storageKey)
            }
        }
    }

    /// 获取当前配置快照
    func allConfigs() -> [CustomProviderConfig] {
        queue.sync { configs }
    }

    // MARK: - API Key（Keychain）

    /// 读取指定 provider 的 API Key
    func apiKey(for providerId: UUID) -> String? {
        KeychainStore.get(account: "custom_provider_\(providerId.uuidString)")
    }

    /// 保存指定 provider 的 API Key 到 Keychain
    func setAPIKey(_ key: String, for providerId: UUID) throws {
        try KeychainStore.set(key, account: "custom_provider_\(providerId.uuidString)")
    }

    /// 删除指定 provider 的 API Key
    func deleteAPIKey(for providerId: UUID) {
        try? KeychainStore.delete(account: "custom_provider_\(providerId.uuidString)")
    }

    // MARK: - 解析

    /// 根据命名空间化的 modelId 解析出 provider + 原始 modelId
    /// - Parameter modelId: 如 "custom::{uuid}::{rawModelId}"
    /// - Returns: 解析结果；若不是自定义模型返回 nil
    func resolve(_ modelId: String) -> ResolvedProvider? {
        guard modelId.hasPrefix("custom::") else { return nil }
        // custom::{uuid}::{rawModelId}
        let remainder = String(modelId.dropFirst("custom::".count))
        guard let sepRange = remainder.range(of: "::") else { return nil }
        let providerUUIDString = String(remainder[remainder.startIndex..<sepRange.lowerBound])
        let rawModelId = String(remainder[sepRange.upperBound...])

        guard let providerId = UUID(uuidString: providerUUIDString) else { return nil }

        var config: CustomProviderConfig?
        queue.sync { config = configs.first { $0.id == providerId } }
        guard let config else { return nil }

        guard let modelInfo = config.models.first(where: { $0.id == rawModelId }) else {
            return nil
        }

        let client = CustomOpenAIClient(config: config)
        return ResolvedProvider(
            provider: client,
            modelId: rawModelId,
            displayName: "\(config.name) · \(modelInfo.displayName)"
        )
    }

    /// 判断 modelId 是否为自定义模型
    func isCustomModel(_ modelId: String) -> Bool {
        modelId.hasPrefix("custom::")
    }

    /// 获取所有自定义模型的显示信息（用于模型选择器）
    func allCustomModels() -> [(config: CustomProviderConfig, model: CustomModelInfo)] {
        queue.sync {
            configs.flatMap { config in
                config.models.map { (config, $0) }
            }
        }
    }

    /// 根据 modelId 查找显示名
    func displayName(for modelId: String) -> String? {
        guard let resolved = resolve(modelId) else { return nil }
        return resolved.displayName
    }
}

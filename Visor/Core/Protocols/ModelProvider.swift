import Foundation

/// 统一 Provider 接口
/// 设计目标：屏蔽不同模型后端差异，AgentRuntime 仅依赖此协议
nonisolated protocol ModelProvider: Sendable {
    var providerName: String { get }
    var defaultModelId: String { get }

    /// 流式调用（OpenAI 兼容协议）
    /// - Parameters:
    ///   - messages: 历史消息（含 tool 消息）
    ///   - tools: 工具定义（OpenAI schema）
    ///   - modelId: 目标模型
    /// - Returns: 异步流，逐个发出 StreamDelta
    func stream(
        messages: [Message],
        tools: [ToolDefinition],
        modelId: String
    ) -> AsyncThrowingStream<StreamDelta, Error>

    /// 中断当前流（用户点"停止"）
    func cancel()
}

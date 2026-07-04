import Foundation

/// 流式增量 DTO（2026-07-04 v4 重写）
///
/// 三种增量：
/// - contentDelta：正文文字
/// - reasoningDelta：思考过程（reasoning），折叠显示
/// - toolCallDeltas：工具调用分片
///
/// 关键修复：
/// - usage 可以独立于 choices 出现（include_usage 的最后一个 chunk choices 为空）
nonisolated struct StreamDelta: Sendable {
    var contentDelta: String?
    var reasoningDelta: String?
    var toolCallDeltas: [ToolCallFragment]?
    var finishReason: String?
    var usage: Usage?

    init(
        contentDelta: String? = nil,
        reasoningDelta: String? = nil,
        toolCallDeltas: [ToolCallFragment]? = nil,
        finishReason: String? = nil,
        usage: Usage? = nil
    ) {
        self.contentDelta = contentDelta
        self.reasoningDelta = reasoningDelta
        self.toolCallDeltas = toolCallDeltas
        self.finishReason = finishReason
        self.usage = usage
    }

    struct ToolCallFragment: Sendable {
        var index: Int
        var id: String?
        var type: String?
        var functionName: String?
        var argumentsDelta: String?
    }

    struct Usage: Sendable, Codable {
        var promptTokens: Int
        var completionTokens: Int
        var totalTokens: Int
    }
}

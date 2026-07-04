import Foundation
import SwiftData

/// 消息实体
/// role: "user" / "assistant" / "tool" / "system"
/// toolCallBody: 工具调用 JSON（项目记忆硬约束：必须持久化以恢复显示）
@Model
final class MessageEntity {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    /// 工具调用详情 JSON（OpenAI tool_calls 序列化）
    var toolCallBody: String?
    var costUSD: Double
    var inputTokens: Int
    var outputTokens: Int
    var createdAt: Date

    var session: SessionEntity?

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        toolCallBody: String? = nil,
        costUSD: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallBody = toolCallBody
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.createdAt = Date()
    }
}

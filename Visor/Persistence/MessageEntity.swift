import Foundation
import SwiftData

/// 消息实体
/// role: "user" / "assistant" / "tool" / "system"
/// toolCallBody: 工具调用 JSON（项目记忆硬约束：必须持久化以恢复显示）
/// attachments: 多模态附件 JSON 数组（data URL 字符串），用于 vision 输入图片
@Model
final class MessageEntity {
    @Attribute(.unique) var id: UUID
    var role: String
    var content: String
    /// 工具调用详情 JSON（OpenAI tool_calls 序列化）
    var toolCallBody: String?
    /// 工具调用 ID（tool 消息必须携带，DeepSeek 等严格 API 要求）
    var toolCallId: String?
    /// 多模态附件 JSON：["data:image/jpeg;base64,...", ...]
    /// 仅 user 消息会用，重启后恢复时重建为 MessageContent.parts
    var attachments: String?
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
        toolCallId: String? = nil,
        attachments: String? = nil,
        costUSD: Double = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallBody = toolCallBody
        self.toolCallId = toolCallId
        self.attachments = attachments
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.createdAt = Date()
    }
}

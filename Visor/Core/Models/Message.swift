import Foundation

/// 消息 DTO（OpenAI Chat Completions 格式）
/// role: "system" / "user" / "assistant" / "tool"
nonisolated struct Message: Codable, Sendable, Hashable {
    let role: String
    let content: String?
    /// assistant 消息可能携带
    let toolCalls: [ToolCall]?
    /// tool 消息必须携带（对应 assistant 的 tool_call.id）
    let toolCallId: String?
    /// 名称（tool 消息可选）
    let name: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
        case name
    }

    init(
        role: String,
        content: String? = nil,
        toolCalls: [ToolCall]? = nil,
        toolCallId: String? = nil,
        name: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
        self.name = name
    }

    static func system(_ content: String) -> Message {
        Message(role: "system", content: content)
    }

    static func user(_ content: String) -> Message {
        Message(role: "user", content: content)
    }

    static func assistant(_ content: String?, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: "assistant", content: content, toolCalls: toolCalls)
    }

    static func tool(callId: String, content: String) -> Message {
        Message(role: "tool", content: content, toolCallId: callId)
    }
}

import Foundation

/// 消息 DTO（OpenAI Chat Completions 格式，支持多模态 vision）
/// role: "system" / "user" / "assistant" / "tool"
nonisolated struct Message: Codable, Sendable, Hashable {
    let role: String
    /// 多模态内容：纯文本用 .text(String)；vision 用 .parts([.text, .image_url...])
    let content: MessageContent?
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
        content: MessageContent? = nil,
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
        Message(role: "system", content: .text(content))
    }

    static func user(_ content: String) -> Message {
        Message(role: "user", content: .text(content))
    }

    /// 多模态 user 消息：文本 + 图片（vision 输入）
    /// - Parameter images: JPEG/PNG 二进制数据，将编码为 base64 data URL
    static func user(text: String, images: [Data]) -> Message {
        var parts: [MessageContent.ContentPart] = []
        if !text.isEmpty {
            parts.append(MessageContent.ContentPart(type: "text", text: text, image_url: nil))
        }
        for img in images {
            let dataURL = "data:image/jpeg;base64,\(img.base64EncodedString())"
            parts.append(MessageContent.ContentPart(
                type: "image_url",
                text: nil,
                image_url: MessageContent.ContentPart.ImageURL(url: dataURL)
            ))
        }
        return Message(role: "user", content: .parts(parts))
    }

    static func assistant(_ content: String?, toolCalls: [ToolCall]? = nil) -> Message {
        Message(role: "assistant", content: content.map { .text($0) }, toolCalls: toolCalls)
    }

    static func tool(callId: String, content: String) -> Message {
        Message(role: "tool", content: .text(content), toolCallId: callId)
    }
}

/// 消息内容：支持纯文本或 OpenAI vision 多模态数组
nonisolated enum MessageContent: Codable, Sendable, Hashable {
    /// 纯文本（编码为 JSON String）
    case text(String)
    /// 多模态 parts（编码为 JSON 数组：text + image_url）
    case parts([ContentPart])

    struct ContentPart: Codable, Sendable, Hashable {
        let type: String           // "text" | "image_url"
        let text: String?
        let image_url: ImageURL?

        struct ImageURL: Codable, Sendable, Hashable {
            let url: String        // "data:image/jpeg;base64,..."
        }

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case image_url
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        // 兼容旧的 String 形式
        if let s = try? c.decode(String.self) {
            self = .text(s)
            return
        }
        // 多模态数组形式
        if let arr = try? c.decode([ContentPart].self) {
            self = .parts(arr)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c,
            debugDescription: "Invalid content: must be String or [ContentPart]"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s):
            try c.encode(s)
        case .parts(let arr):
            try c.encode(arr)
        }
    }

    /// 提取文本部分（用于 UI 显示 / 日志）
    /// .text(s) → s
    /// .parts([...]) → 拼接所有 type="text" 的内容
    var textValue: String? {
        switch self {
        case .text(let s):
            return s
        case .parts(let arr):
            let texts = arr.compactMap { $0.text }
            return texts.isEmpty ? nil : texts.joined(separator: "\n")
        }
    }
}

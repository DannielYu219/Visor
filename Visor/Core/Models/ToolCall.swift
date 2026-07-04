import Foundation

/// 工具调用 DTO（OpenAI 格式）
nonisolated struct ToolCall: Codable, Sendable, Hashable {
    let id: String
    let type: String  // "function"
    let function: FunctionCall

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case function
    }

    struct FunctionCall: Codable, Sendable, Hashable {
        let name: String
        /// 参数 JSON 字符串（可能分片到达）
        let arguments: String
    }
}

/// 工具定义（OpenAI 格式）
nonisolated struct ToolDefinition: Codable, Sendable, Hashable {
    let type: String  // "function"
    let function: FunctionSpec

    enum CodingKeys: String, CodingKey {
        case type
        case function
    }

    struct FunctionSpec: Codable, Sendable, Hashable {
        let name: String
        let description: String
        /// JSON Schema 字典
        let parameters: JSONValue

        enum CodingKeys: String, CodingKey {
            case name
            case description
            case parameters
        }
    }

    static func function(name: String, description: String, parameters: JSONValue) -> ToolDefinition {
        ToolDefinition(type: "function", function: FunctionSpec(name: name, description: description, parameters: parameters))
    }
}

/// JSON 值（用于 JSON Schema 描述）
nonisolated enum JSONValue: Codable, Sendable, Hashable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

import Foundation
import os.log

/// 自定义 OpenAI 兼容服务商客户端
///
/// 复用 OpenRouterClient 验证过的 SSE 解析逻辑（独立实现，避免改动已稳定的 OpenRouterClient）。
/// - Base URL、API Key 来自 CustomProviderConfig
/// - API Key 从 Keychain 读取（account = custom_provider_{uuid}）
/// - 不发送 HTTP-Referer / X-Title（自定义服务商无需）
final class CustomOpenAIClient: ModelProvider, @unchecked Sendable {

    nonisolated let providerName: String
    nonisolated var defaultModelId: String { config.models.first?.id ?? "" }

    private let config: CustomProviderConfig
    private let session: URLSession
    private let baseURL: URL
    nonisolated private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "CustomOpenAIClient")

    private var currentTask: Task<Void, Never>?

    init(config: CustomProviderConfig, session: URLSession = .shared) {
        self.config = config
        self.providerName = config.name
        self.session = session
        // 规范化 Base URL：去除尾部斜杠
        let trimmed = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.baseURL = URL(string: trimmed) ?? URL(string: "https://example.com/v1")!
    }

    // MARK: - ModelProvider

    nonisolated func stream(
        messages: [Message],
        tools: [ToolDefinition],
        modelId: String
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let account = self.config.apiKeyAccount
            guard let apiKey = KeychainStore.get(account: account), !apiKey.isEmpty else {
                continuation.finish(throwing: ProviderError.missingAPIKey(providerName: self.providerName))
                return
            }

            let req = self.buildRequest(apiKey: apiKey, messages: messages, tools: tools, modelId: modelId)

            let task = Task {
                do {
                    let (bytes, response) = try await self.session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        continuation.finish(throwing: ProviderError.invalidResponse)
                        return
                    }
                    if http.statusCode == 401 {
                        continuation.finish(throwing: ProviderError.invalidAPIKey)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // 从流中读取错误正文，不做第二次请求
                        var bodyLines: [String] = []
                        do {
                            for try await line in bytes.lines.prefix(5) {
                                bodyLines.append(line)
                            }
                        } catch { }
                        let raw = bodyLines.joined(separator: "\n")
                        var msg = "HTTP \(http.statusCode)"
                        if let data = raw.data(using: .utf8),
                           let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
                           let err = payload.error {
                            msg = "[\(err.code ?? http.statusCode)] \(err.message ?? "未知错误")"
                        } else if !raw.isEmpty {
                            msg += ": \(String(raw.prefix(200)))"
                        }
                        // 日志记录请求体便于调试
                        if let body = req.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                            self.logger.error("Request failed: \(msg, privacy: .public)\nBody: \(String(bodyStr.prefix(500)), privacy: .public)")
                        }
                        continuation.finish(throwing: ProviderError.serverError(code: http.statusCode, message: msg))
                        return
                    }
                    try await self.parseSSE(bytes: bytes, continuation: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: ProviderError.cancelled)
                } catch let e as ProviderError {
                    continuation.finish(throwing: e)
                } catch {
                    continuation.finish(throwing: ProviderError.transport(error))
                }
            }
            self.currentTask = task
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    nonisolated func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Request

    nonisolated private func buildRequest(apiKey: String, messages: [Message], tools: [ToolDefinition], modelId: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 0

        var body = RequestBody(
            model: modelId,
            messages: messages,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            tool_choice: tools.isEmpty ? nil : "auto"
        )
        // DeepSeek 思考模式 + 思考强度
        if config.isDeepSeek, config.thinkingMode.isEnabled {
            body.thinking = ["type": .string("enabled")]
            if let effort = config.thinkingMode.reasoningEffort {
                body.reasoning_effort = .string(effort)
            }
        }
        req.httpBody = try? JSONEncoder().encode(body)
        return req
    }

    nonisolated private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let tools: [ToolDefinition]?
        let tool_choice: String?
        var thinking: [String: JSONValue]?          // DeepSeek thinking parameter
        var reasoning_effort: JSONValue?            // DeepSeek reasoning effort

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, tools
            case tool_choice, thinking
            case reasoning_effort
        }
    }

    // MARK: - SSE Parsing（纯后台，无 MainActor）

    nonisolated private func parseSSE(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<StreamDelta, Error>.Continuation
    ) async throws {
        for try await line in bytes.lines {
            if Task.isCancelled { throw ProviderError.cancelled }
            if line.isEmpty { continue }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { return }
            guard let data = payload.data(using: .utf8) else { continue }

            // 错误检测
            if let errPayload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
               let err = errPayload.error {
                continuation.finish(throwing: ProviderError.serverError(
                    code: err.code ?? 0,
                    message: err.message ?? "服务器错误"
                ))
                return
            }

            do {
                let chunk = try JSONDecoder().decode(SSEChunk.self, from: data)
                let delta = chunk.toStreamDelta()
                continuation.yield(delta)
            } catch {
                continue
            }
        }
    }

    // MARK: - SSE Wire Format

    nonisolated private struct ErrorPayload: Decodable {
        struct Err: Decodable {
            let code: Int?
            let message: String?
        }
        let error: Err?
    }

    nonisolated private struct SSEChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let role: String?
                let content: String?
                let reasoning: String?
                let reasoning_content: String?  // DeepSeek API 字段
                let tool_calls: [ToolCallWire]?
            }
            let delta: Delta
            let finish_reason: String?
        }
        struct ToolCallWire: Decodable {
            let index: Int
            let id: String?
            let type: String?
            let function: FunctionWire?
        }
        struct FunctionWire: Decodable {
            let name: String?
            let arguments: String?
        }
        struct UsageWire: Decodable {
            let prompt_tokens: Int?
            let completion_tokens: Int?
            let total_tokens: Int?
        }
        let choices: [Choice]
        let usage: UsageWire?

        func toStreamDelta() -> StreamDelta {
            var d = StreamDelta()
            if let first = choices.first {
                d.contentDelta = first.delta.content
                d.reasoningDelta = first.delta.reasoning ?? first.delta.reasoning_content
                d.finishReason = first.finish_reason
                if let tcs = first.delta.tool_calls, !tcs.isEmpty {
                    d.toolCallDeltas = tcs.map { tc in
                        StreamDelta.ToolCallFragment(
                            index: tc.index,
                            id: tc.id,
                            type: tc.type,
                            functionName: tc.function?.name,
                            argumentsDelta: tc.function?.arguments
                        )
                    }
                }
            }
            if let u = usage {
                let p = u.prompt_tokens ?? 0
                let c = u.completion_tokens ?? 0
                let t = u.total_tokens ?? (p + c)
                d.usage = StreamDelta.Usage(promptTokens: p, completionTokens: c, totalTokens: t)
            }
            return d
        }
    }

    // MARK: - Errors

    enum ProviderError: Error, LocalizedError {
        case missingAPIKey(providerName: String)
        case invalidAPIKey
        case invalidResponse
        case serverError(code: Int, message: String)
        case cancelled
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey(let name): return "未配置 \(name) 的 API Key"
            case .invalidAPIKey: return "API Key 无效或已失效，请重新配置"
            case .invalidResponse: return "服务器响应格式无效"
            case .serverError(let code, let message): return "服务器错误（\(code)）：\(message)"
            case .cancelled: return "请求已取消"
            case .transport(let e): return "网络错误：\(e.localizedDescription)"
            }
        }
    }
}

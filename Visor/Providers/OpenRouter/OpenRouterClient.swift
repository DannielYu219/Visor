import Foundation
import os.log

/// OpenRouter 客户端（2026-07-04 v4 重写）
///
/// 关键修复：
/// 1. reasoning 字段解析（思考过程）
/// 2. usage 独立于 choices（include_usage 最后一个 chunk choices 为空）
/// 3. 无 MainActor 阻塞（parseSSE 纯后台线程，不调 DebugBus）
final class OpenRouterClient: ModelProvider, @unchecked Sendable {

    nonisolated let providerName = "OpenRouter"
    nonisolated var defaultModelId: String { OpenRouterModels.defaultModelId }

    private let session: URLSession
    private let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    private let appReferer = "https://visor.app"
    private let appTitle = "Visor iOS"
    nonisolated private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "OpenRouter")
    nonisolated private let sseLogger = Logger(subsystem: "com.lyrastudio.Visor", category: "SSE")

    private var currentTask: Task<Void, Never>?

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - ModelProvider

    nonisolated func stream(
        messages: [Message],
        tools: [ToolDefinition],
        modelId: String
    ) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            guard let apiKey = KeychainStore.openRouterAPIKey, !apiKey.isEmpty else {
                continuation.finish(throwing: ProviderError.missingAPIKey)
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
                        KeychainStore.openRouterAPIKey = nil
                        continuation.finish(throwing: ProviderError.invalidAPIKey)
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        let bodyData = try? await URLSession.shared.data(for: req).0
                        var msg = "HTTP \(http.statusCode)"
                        if let bodyData,
                           let payload = try? JSONDecoder().decode(ErrorPayload.self, from: bodyData),
                           let err = payload.error {
                            msg = "[\(err.code ?? http.statusCode)] \(err.message ?? "未知错误")"
                            if err.message?.lowercased().contains("api key") == true
                                || err.message?.lowercased().contains("unauthorized") == true {
                                KeychainStore.openRouterAPIKey = nil
                                continuation.finish(throwing: ProviderError.invalidAPIKey)
                                return
                            }
                        }
                        continuation.finish(throwing: ProviderError.serverError(code: http.statusCode, message: msg))
                        return
                    }
                    // 解析 SSE（纯后台，无 MainActor 调用）
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
        req.setValue(appReferer, forHTTPHeaderField: "HTTP-Referer")
        req.setValue(appTitle, forHTTPHeaderField: "X-Title")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 0

        let body = RequestBody(
            model: modelId,
            messages: messages,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
            tool_choice: tools.isEmpty ? nil : "auto",
            stream_options: ["include_usage": .bool(true)]
        )
        req.httpBody = try? JSONEncoder().encode(body)
        return req
    }

    nonisolated private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let tools: [ToolDefinition]?
        let tool_choice: String?
        let stream_options: [String: JSONValue]
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

            // 原始 SSE 日志（调试用）
            self.sseLogger.info("SSE: \(payload.prefix(500))")

            // 错误检测
            if let errPayload = try? JSONDecoder().decode(ErrorPayload.self, from: data),
               let err = errPayload.error {
                continuation.finish(throwing: ProviderError.serverError(
                    code: err.code ?? 0,
                    message: err.message ?? "服务器错误"
                ))
                return
            }

            // 解析 chunk
            do {
                let chunk = try JSONDecoder().decode(SSEChunk.self, from: data)
                let delta = chunk.toStreamDelta()
                continuation.yield(delta)
            } catch {
                // 静默跳过无法解析的 chunk
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
                let reasoning: String?       // 思考过程
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

            // choices 可能为空（usage-only chunk）
            if let first = choices.first {
                d.contentDelta = first.delta.content
                d.reasoningDelta = first.delta.reasoning
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

            // usage 独立解析（不依赖 choices）
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
        case missingAPIKey
        case invalidAPIKey
        case invalidResponse
        case serverError(code: Int, message: String)
        case cancelled
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey: return "未配置 OpenRouter API Key"
            case .invalidAPIKey: return "API Key 无效或已失效，请重新配置"
            case .invalidResponse: return "服务器响应格式无效"
            case .serverError(let code, let message): return "服务器错误（\(code)）：\(message)"
            case .cancelled: return "请求已取消"
            case .transport(let e): return "网络错误：\(e.localizedDescription)"
            }
        }
    }
}

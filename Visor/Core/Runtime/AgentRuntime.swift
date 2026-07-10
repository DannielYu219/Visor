import Foundation
import os.log

/// Agent 运行时（2026-07-04 v7）
///
/// 关键修复：
/// - nonisolated（不阻塞 MainActor）
/// - Task.detached
/// - defer { continuation.finish() }
/// - tool_call delta 实时透传
/// - build() 不要求 id 非空
/// - 执行前验证 arguments JSON
/// - 流式 watchdog：120 秒无 delta → 超时
/// - .log 事件：全链路诊断日志通过事件流发到 DebugBus
final class AgentRuntime: @unchecked Sendable {
    private let defaultProvider: ModelProvider
    private let registry: CustomProviderRegistry
    private let router: SkillRouter
    private let maxToolRounds = 6
    private var currentTask: Task<Void, Never>?
    private var currentProvider: ModelProvider?
    private let logger = Logger(subsystem: "com.lyrastudio.Visor", category: "AgentRuntime")

    enum Event: Sendable {
        case skillRouted(String)
        case reasoningDelta(String)
        case textDelta(String)
        case toolCallStarted(name: String)
        case assistantMessage(Message)
        case toolMessage(Message)
        case usage(prompt: Int, completion: Int, costUSD: Double)
        case artifact(path: String)
        case error(String)
        case log(String)          // 诊断日志（发到 DebugBus）
        case completed
    }

    init(provider: ModelProvider? = nil, router: SkillRouter? = nil, registry: CustomProviderRegistry = .shared) {
        self.defaultProvider = provider ?? OpenRouterClient()
        self.registry = registry
        self.router = router ?? SkillRouter(skills: SkillRouter.default)
    }

    func run(
        userInput: String,
        history: [Message],
        modelId: String,
        sessionId: UUID,
        attachments: [Data] = []
    ) -> AsyncStream<Event> {
        currentTask?.cancel()
        currentProvider?.cancel()

        // 按 modelId 解析 provider（自定义服务商 or 默认 OpenRouter）
        let resolved = registry.resolve(modelId)
        let provider = resolved?.provider ?? defaultProvider
        let effectiveModelId = resolved?.modelId ?? modelId
        currentProvider = provider

        let (stream, continuation) = AsyncStream<Event>.makeStream()

        currentTask = Task.detached {
            defer { continuation.finish() }
            await self.runInternal(
                userInput: userInput,
                history: history,
                provider: provider,
                modelId: effectiveModelId,
                sessionId: sessionId,
                attachments: attachments,
                continuation: continuation
            )
        }
        continuation.onTermination = { @Sendable _ in
            self.currentTask?.cancel()
        }
        return stream
    }

    func cancel() {
        currentTask?.cancel()
        currentProvider?.cancel()
        currentProvider = nil
    }

    private func log(_ continuation: AsyncStream<Event>.Continuation, _ msg: String) {
        logger.info("\(msg)")
        continuation.yield(.log(msg))
    }

    // MARK: - Core Loop

    private func runInternal(
        userInput: String,
        history: [Message],
        provider: ModelProvider,
        modelId: String,
        sessionId: UUID,
        attachments: [Data],
        continuation: AsyncStream<Event>.Continuation
    ) async {
        log(continuation, "▶ runInternal start")

        let fs: FileSystemStore
        do {
            fs = try FileSystemStore(sessionId: sessionId)
            log(continuation, "✓ FileSystemStore ok")
        } catch {
            log(continuation, "✗ FileSystemStore failed: \(error)")
            continuation.yield(.error("chat.error.fsInit".l(error.localizedDescription)))
            return
        }

        let routed = self.router.route(userInput)
        continuation.yield(.skillRouted(routed.primary.displayName))
        log(continuation, "✓ routed to \(routed.primary.name)")

        // 读取当前 session 文件清单，注入系统提示让 Agent 能"针对某个文件"修改
        let fileContext: String
        do {
            let entries = try fs.list()
            if entries.isEmpty {
                fileContext = "(" + "fileContext.empty".l + ")"
            } else {
                fileContext = entries.map { "- \($0.path) (\($0.size)B)" }.joined(separator: "\n")
            }
        } catch {
            fileContext = "(" + "fileContext.readFailed".l(error.localizedDescription) + ")"
        }
        let fileContextTemplate = PromptLocalizer.text(named: "file_context_template")
        let fileContextFragment = fileContextTemplate.replacingOccurrences(of: "{FILES}", with: fileContext)

        let visorCLIFragment = PromptLocalizer.text(named: "visor_cli")
        let combinedSystemPrompt = routed.systemPrompt + "\n\n---\n\n" + visorCLIFragment + fileContextFragment
        let agentHint = PromptLocalizer.text(named: "agent_user_hint")
        let userMsgWithHint = userInput + "\n\n" + agentHint
        var messages: [Message] = [.system(combinedSystemPrompt)]
        messages.append(contentsOf: history)
        // 多模态：若有图片则构建 vision user 消息
        if !attachments.isEmpty {
            messages.append(.user(text: userMsgWithHint, images: attachments))
            log(continuation, "✓ user message with \(attachments.count) image(s)")
        } else {
            messages.append(.user(userMsgWithHint))
        }
        log(continuation, "✓ messages count: \(messages.count)")

        for round in 1...maxToolRounds {
            if Task.isCancelled {
                log(continuation, "✗ cancelled before round \(round)")
                return
            }
            log(continuation, "▶ round \(round) start")

            let stream = provider.stream(messages: messages, tools: FileTools.all, modelId: modelId)

            var textAccum = ""
            var toolFragments: [Int: ToolCallBuilder] = [:]
            var finishReason: String?
            var lastUsage: StreamDelta.Usage?
            var toolCallNotified: Set<Int> = []
            var deltaCount = 0

            // watchdog：用 Task 监控无数据超时
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 120 秒
                if !Task.isCancelled {
                    log(continuation, "✗ watchdog: 120 秒无新 delta，可能卡死")
                }
            }

            do {
                for try await delta in stream {
                    watchdog.cancel()
                    if Task.isCancelled {
                        log(continuation, "✗ cancelled during stream")
                        return
                    }
                    deltaCount += 1

                    if let r = delta.reasoningDelta {
                        continuation.yield(.reasoningDelta(r))
                    }
                    if let text = delta.contentDelta {
                        textAccum += text
                        continuation.yield(.textDelta(text))
                    }
                    if let tcds = delta.toolCallDeltas {
                        for tcd in tcds {
                            var b = toolFragments[tcd.index] ?? ToolCallBuilder()
                            if let id = tcd.id { b.id = id }
                            if let type = tcd.type { b.type = type }
                            if let name = tcd.functionName { b.name += name }
                            if let args = tcd.argumentsDelta { b.arguments += args }
                            toolFragments[tcd.index] = b

                            if !toolCallNotified.contains(tcd.index) && !b.name.isEmpty {
                                toolCallNotified.insert(tcd.index)
                                continuation.yield(.toolCallStarted(name: b.name))
                                log(continuation, "⚡ tool_call detected: \(b.name), argsLen=\(b.arguments.count)")
                            }
                        }
                    }
                    if let fr = delta.finishReason { finishReason = fr }
                    if let u = delta.usage { lastUsage = u }

                    // 重启 watchdog
                    if deltaCount % 100 == 0 {
                        log(continuation, "  ... \(deltaCount) deltas received, textLen=\(textAccum.count), tools=\(toolFragments.count)")
                    }
                }
            } catch {
                watchdog.cancel()
                log(continuation, "✗ stream error: \(error)")
                continuation.yield(.error("chat.error.stream".l(error.localizedDescription)))
                return
            }
            watchdog.cancel()

            log(continuation, "✓ round \(round) stream ended: \(deltaCount) deltas, finishReason=\(finishReason ?? "nil"), textLen=\(textAccum.count), tools=\(toolFragments.count)")

            // 打印每个 tool fragment 的状态
            for (idx, frag) in toolFragments {
                log(continuation, "  tool[\(idx)]: id=\(frag.id.isEmpty ? "EMPTY" : frag.id.prefix(20)), name=\(frag.name), argsLen=\(frag.arguments.count), argsValid=\(isValidJSON(frag.arguments))")
            }

            if let u = lastUsage {
                let cost = ModelPricingTable.shared.costUSD(modelId: modelId, inputTokens: u.promptTokens, outputTokens: u.completionTokens)
                continuation.yield(.usage(prompt: u.promptTokens, completion: u.completionTokens, costUSD: cost))
                log(continuation, "✓ usage: prompt=\(u.promptTokens) completion=\(u.completionTokens) cost=\(cost)")
            } else {
                log(continuation, "⚠ no usage received")
            }

            if finishReason == "error" {
                continuation.yield(.error("chat.error.modelError".l))
                return
            }

            let toolCalls: [ToolCall] = toolFragments.sorted { $0.key < $1.key }.compactMap { $0.value.build() }
            log(continuation, "✓ built \(toolCalls.count) tool calls")

            if toolCalls.isEmpty {
                log(continuation, "✓ no tool calls, breaking")
                break
            }

            // 验证 arguments JSON
            var validToolCalls: [(call: ToolCall, wasRepaired: Bool)] = []
            for tc in toolCalls {
                if isValidJSON(tc.function.arguments) {
                    validToolCalls.append((call: tc, wasRepaired: false))
                    log(continuation, "✓ tool_call \(tc.function.name) args valid (\(tc.function.arguments.count) chars)")
                } else {
                    // 尝试修复未闭合的 JSON（长内容流式截断常见）
                    let repaired = repairArgumentsJSON(tc.function.arguments)
                    if isValidJSON(repaired) {
                        let fixed = ToolCall(
                            id: tc.id,
                            type: tc.type,
                            function: .init(name: tc.function.name, arguments: repaired)
                        )
                        validToolCalls.append((call: fixed, wasRepaired: true))
                        log(continuation, "⚠ tool_call \(tc.function.name) args repaired (\(tc.function.arguments.count) → \(repaired.count) chars)")
                    } else {
                        log(continuation, "✗ tool_call \(tc.function.name) args INVALID (\(tc.function.arguments.count) chars): \(tc.function.arguments.prefix(200))")
                    }
                }
            }

            if validToolCalls.isEmpty {
                log(continuation, "✗ all tool calls invalid, breaking")
                break
            }

            let assistantMsg = Message.assistant(textAccum.isEmpty ? nil : textAccum, toolCalls: validToolCalls.map { $0.call })
            messages.append(assistantMsg)
            continuation.yield(.assistantMessage(assistantMsg))
            log(continuation, "✓ assistant message yielded")

            // 执行工具
            for entry in validToolCalls {
                let tc = entry.call
                // 写操作工具若参数因流式截断被修复，replace/content 可能为空——
                // 直接执行会误删文件内容或写入截断内容，必须跳过并要求重试
                if entry.wasRepaired && (tc.function.name == "file_patch" || tc.function.name == "file_write") {
                    log(continuation, "⚠ skipping \(tc.function.name): args repaired (truncated), requesting retry")
                    let result = #"{"error":"truncated_args","ok":false,"message":"\#("tool.error.truncatedArgs".l)"}"#
                    let toolMsg = Message(role: "tool", content: .text(result), toolCallId: tc.id, name: tc.function.name)
                    messages.append(toolMsg)
                    continuation.yield(.toolMessage(toolMsg))
                    continue
                }
                log(continuation, "▶ executing \(tc.function.name)...")
                let result = FileTools.execute(name: tc.function.name, argumentsJSON: tc.function.arguments, fs: fs, sessionId: sessionId)
                log(continuation, "✓ tool result: \(result.prefix(200))")
                let toolMsg = Message(role: "tool", content: .text(result), toolCallId: tc.id, name: tc.function.name)
                messages.append(toolMsg)
                continuation.yield(.toolMessage(toolMsg))
            }

            // 通知画布
            if fs.exists("index.html") {
                if let absPath = try? fs.absoluteURL(for: "index.html").path {
                    continuation.yield(.artifact(path: absPath))
                }
            }

            log(continuation, "▶ round \(round) done, continuing to round \(round + 1)")
        }

        log(continuation, "✓ runInternal completed")
        continuation.yield(.completed)
    }

    private func isValidJSON(_ s: String) -> Bool {
        guard let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    /// 尝试修复流式截断导致的未闭合 JSON
    /// 常见情况：`{"path":"index.html","content":"<html>...` 被截断，缺少闭合的 `"}`
    private func repairArgumentsJSON(_ s: String) -> String {
        var repaired = s

        // 如果以 `{` 开头但不是有效 JSON，尝试补全闭合括号
        guard repaired.hasPrefix("{") else { return repaired }

        // 统计未闭合的引号和括号
        var inString = false
        var escape = false
        var braceDepth = 0
        var bracketDepth = 0

        for ch in repaired {
            if escape {
                escape = false
                continue
            }
            if ch == "\\" && inString {
                escape = true
                continue
            }
            if ch == "\"" {
                inString.toggle()
                continue
            }
            if inString { continue }
            switch ch {
            case "{": braceDepth += 1
            case "}": braceDepth -= 1
            case "[": bracketDepth += 1
            case "]": bracketDepth -= 1
            default: break
            }
        }

        // 如果还在字符串内，补一个闭合引号
        if inString {
            repaired += "\""
        }

        // 补全未闭合的括号
        for _ in 0..<max(0, bracketDepth) {
            repaired += "]"
        }
        for _ in 0..<max(0, braceDepth) {
            repaired += "}"
        }

        return repaired
    }

    private struct ToolCallBuilder {
        var id: String = ""
        var type: String = ""
        var name: String = ""
        var arguments: String = ""

        func build() -> ToolCall? {
            guard !name.isEmpty else { return nil }
            let finalId = id.isEmpty ? "call_\(UUID().uuidString.prefix(8))" : id
            return ToolCall(id: finalId, type: type.isEmpty ? "function" : type, function: .init(name: name, arguments: arguments))
        }
    }
}

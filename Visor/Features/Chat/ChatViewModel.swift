import Foundation
import SwiftUI
import SwiftData
import os.log

/// 单条消息的运行时模型（UI 层使用）
struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let role: String
    var content: String
    var reasoning: String = ""       // 思考过程（折叠显示）
    var toolCallBody: String? = nil
    var toolCallId: String? = nil
    var name: String? = nil
    var isStreaming: Bool = false
    var costUSD: Double = 0
    var createdAt: Date

    init(
        id: UUID = UUID(),
        role: String,
        content: String,
        reasoning: String = "",
        toolCallBody: String? = nil,
        toolCallId: String? = nil,
        name: String? = nil,
        isStreaming: Bool = false,
        costUSD: Double = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.reasoning = reasoning
        self.toolCallBody = toolCallBody
        self.toolCallId = toolCallId
        self.name = name
        self.isStreaming = isStreaming
        self.costUSD = costUSD
        self.createdAt = createdAt
    }
}

/// 聊天状态机（2026-07-04 v4）
///
/// 通过 AsyncStream 消费 AgentRuntime 事件。
/// 所有 DebugBus 日志在此 @MainActor 上调用（安全）。
@MainActor
@Observable
final class ChatViewModel {

    var messages: [ChatMessage] = []
    var draft: String = ""
    var selectedModelId: String {
        get {
            let v = UserDefaults.standard.string(forKey: "selectedModelId")
            if let v, OpenRouterModels.find(v) != nil { return v }
            return OpenRouterModels.defaultModelId
        }
        set { UserDefaults.standard.set(newValue, forKey: "selectedModelId") }
    }
    var isStreaming: Bool = false
    var errorMessage: String?
    var sessionCostUSD: Double = 0
    var sessionInputTokens: Int = 0
    var sessionOutputTokens: Int = 0
    var activeSkillName: String?
    var canvasPath: String = ""

    private let runtime: AgentRuntime
    private let budgetGuard: BudgetGuard
    private var sessionId: UUID = UUID()
    private var consumeTask: Task<Void, Never>?
    private var currentAssistantId: UUID?
    private var modelContext: ModelContext?
    /// 流式过程中累积的 reasoning，落盘时用
    private var streamingReasoning: String = ""

    init(runtime: AgentRuntime? = nil, budgetGuard: BudgetGuard) {
        self.runtime = runtime ?? AgentRuntime()
        self.budgetGuard = budgetGuard
    }

    func attachSession(_ id: UUID, context: ModelContext? = nil) {
        self.sessionId = id
        self.modelContext = context
        loadHistory()
    }

    // MARK: - 持久化

    /// 从 SwiftData 加载历史消息
    private func loadHistory() {
        guard let context = modelContext else { return }
        let sid = sessionId
        let descriptor = FetchDescriptor<MessageEntity>(
            predicate: #Predicate { $0.session?.id == sid },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let entities = try? context.fetch(descriptor) else { return }
        messages = entities.map { entity in
            ChatMessage(
                id: entity.id,
                role: entity.role,
                content: entity.content,
                toolCallBody: entity.toolCallBody,
                costUSD: entity.costUSD,
                createdAt: entity.createdAt
            )
        }
        // 恢复 session 累计
        if let session = try? context.fetch(
            FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == sid })
        ).first {
            sessionCostUSD = session.totalCostUSD
            sessionInputTokens = session.totalInputTokens
            sessionOutputTokens = session.totalOutputTokens
        }
    }

    /// 落盘单条消息
    private func persist(_ msg: ChatMessage) {
        guard let context = modelContext else { return }
        let entity = MessageEntity(
            id: msg.id,
            role: msg.role,
            content: msg.content,
            toolCallBody: msg.toolCallBody,
            costUSD: msg.costUSD
        )
        entity.createdAt = msg.createdAt
        if let session = try? context.fetch(
            FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == sessionId })
        ).first {
            entity.session = session
            session.updatedAt = Date()
        }
        context.insert(entity)
        try? context.save()
    }

    /// 更新已落盘消息的 content（流式完成后调用）
    private func updatePersisted(_ msg: ChatMessage) {
        guard let context = modelContext else { return }
        let mid = msg.id
        if let entity = try? context.fetch(
            FetchDescriptor<MessageEntity>(predicate: #Predicate { $0.id == mid })
        ).first {
            entity.content = msg.content
            entity.toolCallBody = msg.toolCallBody
            entity.costUSD = msg.costUSD
            try? context.save()
        }
    }

    /// 更新 session 累计
    private func updateSessionTotals() {
        guard let context = modelContext else { return }
        let sid = sessionId
        if let session = try? context.fetch(
            FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == sid })
        ).first {
            session.totalCostUSD = sessionCostUSD
            session.totalInputTokens = sessionInputTokens
            session.totalOutputTokens = sessionOutputTokens
            session.updatedAt = Date()
            try? context.save()
        }
    }

    // MARK: - Send

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        let userMsg = ChatMessage(role: "user", content: text)
        messages.append(userMsg)
        persist(userMsg)
        draft = ""
        errorMessage = nil
        streamingReasoning = ""

        let assistantId = UUID()
        let assistantMsg = ChatMessage(id: assistantId, role: "assistant", content: "", isStreaming: true)
        messages.append(assistantMsg)
        isStreaming = true
        currentAssistantId = assistantId

        let history = messages.filter { $0.id != assistantId }.map { msg in
            var toolCalls: [ToolCall]? = nil
            if let body = msg.toolCallBody,
               let data = body.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([ToolCall].self, from: data) {
                toolCalls = decoded
            }
            return Message(
                role: msg.role,
                content: msg.content.isEmpty ? nil : msg.content,
                toolCalls: toolCalls,
                toolCallId: msg.toolCallId,
                name: msg.name
            )
        }

        let stream = runtime.run(
            userInput: text,
            history: history,
            modelId: selectedModelId,
            sessionId: sessionId
        )

        consumeTask?.cancel()
        consumeTask = Task.detached { [weak self] in
            for await event in stream {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self = self else { return }
                    self.handleEvent(event)
                }
            }
            await MainActor.run {
                guard let self = self else { return }
                self.finishStreaming()
            }
        }
    }

    func stop() {
        consumeTask?.cancel()
        runtime.cancel()
        finishStreaming()
    }

    // MARK: - Event Handling（@MainActor，安全调用 DebugBus）

    private func handleEvent(_ event: AgentRuntime.Event) {
        switch event {
        case .skillRouted(let name):
            activeSkillName = name
            DebugBus.shared.cli("路由到 skill：\(name)")

        case .reasoningDelta(let text):
            guard let id = currentAssistantId,
                  let idx = messages.firstIndex(where: { $0.id == id }) else { return }
            messages[idx].reasoning.append(text)

        case .textDelta(let text):
            guard let id = currentAssistantId,
                  let idx = messages.firstIndex(where: { $0.id == id }) else { return }
            messages[idx].content.append(text)

        case .toolCallStarted(let name):
            // 收到 tool_call delta 时立即显示"正在调用工具"
            // 关闭正在 streaming 的占位
            if let id = currentAssistantId,
               let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx].isStreaming = false
                if messages[idx].content.isEmpty && messages[idx].reasoning.isEmpty {
                    messages.remove(at: idx)
                }
            }
            let toolMsg = ChatMessage(role: "assistant", content: "🔧 正在调用工具：\(name)…")
            messages.append(toolMsg)
            DebugBus.shared.cli("⚙ 工具调用开始：\(name)")

        case .assistantMessage(let msg):
            if let tcs = msg.toolCalls, !tcs.isEmpty {
                // 移除之前的"正在调用工具"占位
                if let idx = messages.lastIndex(where: { $0.role == "assistant" && $0.content.hasPrefix("🔧 正在调用工具") }) {
                    messages.remove(at: idx)
                }
                // 关闭正在 streaming 的占位
                if let id = currentAssistantId,
                   let idx = messages.firstIndex(where: { $0.id == id }) {
                    messages[idx].isStreaming = false
                    if messages[idx].content.isEmpty && messages[idx].reasoning.isEmpty {
                        messages.remove(at: idx)
                    }
                }
                let body: String = {
                    if let data = try? JSONEncoder().encode(tcs),
                       let s = String(data: data, encoding: .utf8) { return s }
                    return "[]"
                }()
                let names = tcs.map { $0.function.name }.joined(separator: ", ")
                let toolMsg = ChatMessage(role: "assistant", content: "🔧 调用工具：\(names)", toolCallBody: body)
                messages.append(toolMsg)
                persist(toolMsg)
                DebugBus.shared.cli("⚙ 工具调用：\(names)")
            }

        case .toolMessage(let msg):
            if let id = currentAssistantId,
               let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx].isStreaming = false
            }
            let toolMsg = ChatMessage(
                role: "tool",
                content: msg.content ?? "",
                toolCallId: msg.toolCallId,
                name: msg.name
            )
            messages.append(toolMsg)
            persist(toolMsg)
            // 从上一条 assistant 的 toolCallBody 里查找对应 toolCallId 的 arguments
            var argsForDebug = ""
            if let tid = msg.toolCallId,
               let lastAssistant = messages.last(where: { $0.role == "assistant" && $0.toolCallBody != nil }),
               let data = lastAssistant.toolCallBody?.data(using: .utf8),
               let calls = try? JSONDecoder().decode([ToolCall].self, from: data) {
                if let match = calls.first(where: { $0.id == tid }) {
                    argsForDebug = match.function.arguments
                }
            }
            DebugBus.shared.tool(msg.name ?? "?", args: argsForDebug, result: msg.content ?? "")
            // 新建 assistant 占位
            let placeholder = ChatMessage(role: "assistant", content: "", isStreaming: true)
            messages.append(placeholder)
            currentAssistantId = placeholder.id

        case .usage(let prompt, let completion, let cost):
            sessionInputTokens += prompt
            sessionOutputTokens += completion
            sessionCostUSD += cost
            updateSessionTotals()
            DebugBus.shared.token(selectedModelId, prompt: prompt, completion: completion, costUSD: cost)

        case .artifact(let path):
            canvasPath = path

        case .error(let msg):
            errorMessage = msg
            DebugBus.shared.error(msg)

        case .log(let msg):
            DebugBus.shared.cli(msg)

        case .completed:
            break
        }
    }

    private func finishStreaming() {
        isStreaming = false
        if let id = currentAssistantId,
           let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].isStreaming = false
            if messages[idx].content.isEmpty && messages[idx].reasoning.isEmpty {
                messages.remove(at: idx)
            } else {
                // 持久化最终的 assistant 消息
                persist(messages[idx])
            }
        }
        currentAssistantId = nil
    }

    func clear() {
        stop()
        messages.removeAll()
        sessionCostUSD = 0
        sessionInputTokens = 0
        sessionOutputTokens = 0
        canvasPath = ""
        activeSkillName = nil
        budgetGuard.resetSession()
    }
}

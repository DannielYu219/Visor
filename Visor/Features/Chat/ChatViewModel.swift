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
    /// 多模态附件：data URL 字符串数组（"data:image/jpeg;base64,..."）
    var attachments: [String]? = nil
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
        attachments: [String]? = nil,
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
        self.attachments = attachments
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
    /// 当前 draft 中的图片附件（data URL 字符串），发送后清空
    var draftAttachments: [String] = []
    /// 单条消息图片上限（防 token 爆炸）
    static let maxAttachments = 4
    var selectedModelId: String {
        get {
            let v = UserDefaults.standard.string(forKey: "selectedModelId")
            if let v {
                // 自定义模型 or OpenRouter 内置模型
                if CustomProviderRegistry.shared.isCustomModel(v) {
                    if CustomProviderRegistry.shared.resolve(v) != nil { return v }
                } else if OpenRouterModels.find(v) != nil {
                    return v
                }
            }
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
                toolCallId: entity.toolCallId,
                costUSD: entity.costUSD,
                attachments: Self.decodeAttachments(entity.attachments),
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
            toolCallId: msg.toolCallId,
            attachments: Self.encodeAttachments(msg.attachments),
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

    // MARK: - 附件管理

    /// 添加图片附件（data URL 字符串）。返回 false 表示已达上限
    @discardableResult
    func addAttachment(_ dataURL: String) -> Bool {
        guard draftAttachments.count < Self.maxAttachments else { return false }
        draftAttachments.append(dataURL)
        return true
    }

    /// 移除指定索引的附件
    func removeAttachment(at index: Int) {
        guard draftAttachments.indices.contains(index) else { return }
        draftAttachments.remove(at: index)
    }

    /// 清空所有附件
    func clearAttachments() {
        draftAttachments.removeAll()
    }

    /// 导入文本文件到 session 沙盒
    /// - 若是 HTML 文件，自动切换画布渲染目标
    /// - 失败时设置 errorMessage
    func importFile(_ url: URL) {
        let sid = sessionId
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                await MainActor.run { errorMessage = "chatvm.error.readFile".l }
                return
            }

            guard content.utf8.count < 1_000_000 else {
                await MainActor.run { errorMessage = "chatvm.error.fileTooLarge".l }
                return
            }

            let filename = url.lastPathComponent
            do {
                let fs = try FileSystemStore(sessionId: sid)
                let isHTML = filename.lowercased().hasSuffix(".html")
                _ = try fs.write(content: content, to: filename)
                FileSystemNotifier.shared.notify(sessionId: sid, path: filename, kind: .write, switchTo: isHTML)

                await MainActor.run {
                    DebugBus.shared.cli("chatvm.imported".l(filename, content.utf8.count))
                }
            } catch {
                await MainActor.run { errorMessage = "chatvm.error.write".l(error.localizedDescription) }
            }
        }
    }

    /// 把 data URL 字符串转回 Data（用于发送给模型）
    private static func dataURLToData(_ dataURL: String) -> Data? {
        // 格式：data:image/jpeg;base64,XXXX
        guard let commaIdx = dataURL.range(of: ",") else { return nil }
        let base64 = String(dataURL[commaIdx.upperBound...])
        return Data(base64Encoded: base64)
    }

    /// 编码附件为 JSON 字符串（用于持久化）
    private static func encodeAttachments(_ attachments: [String]?) -> String? {
        guard let arr = attachments, !arr.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: arr, options: []),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    /// 从 JSON 字符串解码附件（用于恢复）
    private static func decodeAttachments(_ json: String?) -> [String]? {
        guard let json, let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
        return arr.isEmpty ? nil : arr
    }

    // MARK: - Send

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftAttachments
        // 文本或附件任一非空即可发送
        guard (!text.isEmpty || !attachments.isEmpty), !isStreaming else { return }

        let userMsg = ChatMessage(
            role: "user",
            content: text,
            attachments: attachments.isEmpty ? nil : attachments
        )
        messages.append(userMsg)
        persist(userMsg)
        draft = ""
        draftAttachments = []
        errorMessage = nil
        streamingReasoning = ""

        let assistantId = UUID()
        let assistantMsg = ChatMessage(id: assistantId, role: "assistant", content: "", isStreaming: true)
        messages.append(assistantMsg)
        isStreaming = true
        currentAssistantId = assistantId

        let rawHistory = messages.filter { $0.id != assistantId && $0.id != userMsg.id }.compactMap { msg -> Message? in
            // 过滤掉占位消息和空内容消息（不发给模型）
            if msg.content.isEmpty && msg.toolCallBody == nil && msg.toolCallId == nil && (msg.attachments?.isEmpty ?? true) { return nil }
            // 过滤掉"正在调用工具"占位
            if msg.content.hasPrefix("🔧 正在调用工具") { return nil }
            // DeepSeek 等严格 API 要求 tool 消息必须有 tool_call_id，跳过残缺的旧数据
            if msg.role == "tool" && msg.toolCallId == nil { return nil }

            var toolCalls: [ToolCall]? = nil
            if let body = msg.toolCallBody,
               let data = body.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([ToolCall].self, from: data) {
                toolCalls = decoded
            }

            // 若有附件则构建多模态消息
            if let imgs = msg.attachments, !imgs.isEmpty {
                let imgData = imgs.compactMap { Self.dataURLToData($0) }
                return Message.user(text: msg.content, images: imgData)
            }
            return Message(
                role: msg.role,
                content: msg.content.isEmpty ? nil : .text(msg.content),
                toolCalls: toolCalls,
                toolCallId: msg.toolCallId,
                name: msg.name
            )
        }

        // Post-process: 过滤 tool 消息后，对应 assistant 的 tool_calls 变成孤立引用。
        // DeepSeek 严格要求 assistant(tool_calls) 后紧跟 tool 响应，否则 400。
        // 修复：若 assistant 有 tool_calls 但下一条不是 tool 消息，剥离其 tool_calls（保留正文）。
        var history: [Message] = []
        for (i, msg) in rawHistory.enumerated() {
            if msg.role == "assistant", msg.toolCalls != nil {
                let nextIsTool = i + 1 < rawHistory.count && rawHistory[i + 1].role == "tool"
                if !nextIsTool {
                    history.append(Message(role: "assistant", content: msg.content, toolCalls: nil))
                    continue
                }
            }
            history.append(msg)
        }

        // 把当前轮附件转成 Data 传给 runtime
        let currentImageData = attachments.compactMap { Self.dataURLToData($0) }

        let stream = runtime.run(
            userInput: text,
            history: history,
            modelId: selectedModelId,
            sessionId: sessionId,
            attachments: currentImageData
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
            let toolMsg = ChatMessage(role: "assistant", content: "chat.tool.calling".l(name))
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
                let toolMsg = ChatMessage(role: "assistant", content: "chat.tool.called".l(names), toolCallBody: body)
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
                content: msg.content?.textValue ?? "",
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
            DebugBus.shared.tool(msg.name ?? "?", args: argsForDebug, result: msg.content?.textValue ?? "")
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
            // Agent 写完 index.html，通知画布切换
            let filename = (path as NSString).lastPathComponent
            FileSystemNotifier.shared.notify(
                sessionId: sessionId, path: filename, kind: .write, switchTo: true
            )
            canvasPath = filename

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
        draft = ""
        draftAttachments.removeAll()
        sessionCostUSD = 0
        sessionInputTokens = 0
        sessionOutputTokens = 0
        canvasPath = ""
        activeSkillName = nil
        budgetGuard.resetSession()
    }
}

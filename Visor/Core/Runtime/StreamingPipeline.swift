import Foundation

/// 流式管线（80ms 批量 + holdback）
/// 职责：
///   1. 接收上游 `AsyncThrowingStream<StreamDelta>`
///   2. 按 80ms 间隔批量 yield 到下游
///   3. holdback 防止未闭合的 `<visor-cli>` 前缀泄漏到 UI
/// 约束（项目记忆）：
///   - 不在 UI 侧再 throttle，避免双重节流
///   - 不使用 repeatForever
///   - holdback 字符最多保留 11 字符（兼容 `<visor-cli>`）
/// 关键修复（2026-07-03）：
///   - 修复了"必须取消才会突然到几千 token"的问题
///   - 根因：holdback 一旦触发，整个流都被挂住；模型在工具调用阶段无文字
///   - 修复：hardMaxWait 强制最长 250ms 必须 flush 一次，holdback 也随之释放
@MainActor
final class StreamingPipeline {

    /// holdback 字符串：未闭合前缀的截断长度上限
    static let holdbackLimit = 11

    /// holdback 触发关键词
    private static let holdbackTriggers: [String] = [
        "<",
        "<visor",
        "<visor-",
        "<visor-cli",
        "<visor-cli>"
    ]

    private var buffer: String = ""
    private var pendingText: String = ""
    private var lastFlushTime: Date = .distantPast
    private var lastIngestTime: Date = .distantPast
    private let batchInterval: TimeInterval
    /// hard max wait：距 lastIngest 超过此时间必须 flush 一次
    /// 解决"holdback 永久挂起"问题
    private let hardMaxWait: TimeInterval

    init(batchInterval: TimeInterval = 0.08, hardMaxWait: TimeInterval = 0.25) {
        self.batchInterval = batchInterval
        self.hardMaxWait = hardMaxWait
    }

    /// 接收增量，更新缓冲；返回可立即 flush 的可见文本
    func ingest(_ delta: String) -> String {
        lastIngestTime = Date()
        buffer.append(delta)
        let (visible, retained) = Self.applyHoldback(to: buffer)
        buffer = retained
        if !visible.isEmpty {
            pendingText.append(visible)
        }
        return visible
    }

    /// 每 80ms 调用一次，返回可推送给 UI 的批量文本
    /// - Returns: 若已到 batchInterval 则返回 pendingText 并清空；否则返回空串
    /// - 关键：距 lastIngest 超过 hardMaxWait（250ms）也强制 flush，避免 holdback 永久挂起
    func flushIfDue(now: Date = Date()) -> String {
        let dueByInterval = now.timeIntervalSince(lastFlushTime) >= batchInterval
        let dueByHardWait = now.timeIntervalSince(lastIngestTime) >= hardMaxWait
            && !pendingText.isEmpty
        let dueByHardWaitBuffer = now.timeIntervalSince(lastIngestTime) >= hardMaxWait
            && !buffer.isEmpty
        if (dueByInterval || dueByHardWait) && !pendingText.isEmpty {
            let out = pendingText
            pendingText = ""
            lastFlushTime = now
            return out
        }
        // holdback buffer 时间过长也要释放（关键修复）
        if dueByHardWaitBuffer {
            // 把 holdback 的字符也推出去，避免永久挂起
            pendingText.append(buffer)
            buffer = ""
            let out = pendingText
            pendingText = ""
            lastFlushTime = now
            return out
        }
        return ""
    }

    /// 强制 flush（流结束 / 用户点停止）
    func forceFlush() -> String {
        let pendingOut = pendingText
        let bufferOut = buffer
        pendingText = ""
        buffer = ""
        lastFlushTime = Date()
        lastIngestTime = Date()
        return pendingOut + bufferOut
    }

    /// 取消：清空缓冲（避免泄漏到下一条消息）
    func reset() {
        buffer = ""
        pendingText = ""
        lastFlushTime = Date()
        lastIngestTime = Date()
    }

    // MARK: - Holdback

    /// 简单 holdback：若 buffer 末尾匹配到未闭合前缀，截断保留
    private static func applyHoldback(to raw: String) -> (visible: String, retained: String) {
        // 在 raw 末尾向前扫描，寻找可能未闭合的开头
        let tail = String(raw.suffix(holdbackLimit))
        var holdbackLen = 0
        for trigger in holdbackTriggers where tail.hasPrefix(trigger) {
            // 找到 trigger 的最长匹配
            holdbackLen = max(holdbackLen, trigger.count)
        }
        // 也检查 raw 末尾子串是否包含未闭合的 `<`
        if let lastOpenIdx = raw.lastIndex(of: "<") {
            let afterOpen = raw.distance(from: raw.index(after: lastOpenIdx), to: raw.endIndex)
            // 若 `<` 后没有 `>` 闭合，且剩余字符长度 < holdbackLimit，则 holdback
            if !raw[lastOpenIdx...].contains(">"), afterOpen <= holdbackLimit {
                holdbackLen = max(holdbackLen, afterOpen)
            }
        }
        if holdbackLen == 0 {
            return (raw, "")
        }
        if raw.count <= holdbackLen {
            return ("", raw)
        }
        let visible = String(raw.prefix(raw.count - holdbackLen))
        let retained = String(raw.suffix(holdbackLen))
        return (visible, retained)
    }
}

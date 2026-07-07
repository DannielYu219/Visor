import SwiftUI

/// 配色（语义色 + 状态色 + 消息气泡）
extension Color {
    static let visorBackground = Color(.systemBackground)
    static let visorSecondaryBackground = Color(.secondarySystemBackground)
    static let visorTertiaryBackground = Color(.tertiarySystemBackground)

    /// 用户消息气泡 — accent 蓝染色（对应 CSS: color-mix(accent 92%, white)）
    static let visorUserBubble = Color.accentColor.opacity(0.92)
    /// 助手消息气泡 — surface 色 + 细边框
    static let visorAssistantBubble = Color(.secondarySystemBackground)

    /// 状态色
    static let visorStatusPending = Color.orange.opacity(0.12)
    static let visorStatusRunning = Color.blue.opacity(0.12)
    static let visorStatusSuccess = Color.green.opacity(0.12)
    static let visorStatusFailed = Color.red.opacity(0.12)

    static let visorStatusPendingText = Color.orange
    static let visorStatusRunningText = Color.blue
    static let visorStatusSuccessText = Color.green
    static let visorStatusFailedText = Color.red
}

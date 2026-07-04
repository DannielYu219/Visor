import SwiftUI

/// 配色（语义色 + 状态色）
extension Color {
    static let visorBackground = Color(.systemBackground)
    static let visorSecondaryBackground = Color(.secondarySystemBackground)
    static let visorTertiaryBackground = Color(.tertiarySystemBackground)

    /// 状态色（ToolCallCard / CostMeter）
    static let visorStatusPending = Color.orange.opacity(0.12)
    static let visorStatusRunning = Color.blue.opacity(0.12)
    static let visorStatusSuccess = Color.green.opacity(0.12)
    static let visorStatusFailed = Color.red.opacity(0.12)

    static let visorStatusPendingText = Color.orange
    static let visorStatusRunningText = Color.blue
    static let visorStatusSuccessText = Color.green
    static let visorStatusFailedText = Color.red
}

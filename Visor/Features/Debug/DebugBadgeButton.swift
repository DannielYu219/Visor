import SwiftUI

/// Debug 按钮 + 事件计数 badge
/// - 默认显示 🐞 图标（低调）
/// - 仅在有未读事件（错误 / token 变化）时显示右上角红点
/// - 关键：这是用户**唯一**能看到 AI 工作状态的位置
struct DebugBadgeButton: View {
    @Binding var showDebug: Bool
    @ObservedObject private var bus = DebugBus.shared
    @State private var lastSeenCount: Int = 0
    @State private var hasUnreadError: Bool = false

    var body: some View {
        Button {
            showDebug = true
            // 打开 Debug 面板后清空未读标记
            lastSeenCount = bus.events.count
            hasUnreadError = false
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ladybug")
                    .imageScale(.large)
                if hasUnreadError {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -2)
                } else if hasNewEvents {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 7, height: 7)
                        .offset(x: 4, y: -2)
                }
            }
        }
        .accessibilityLabel("Debug")
        .onChange(of: bus.events.count) { _, _ in
            updateBadge()
        }
        .onAppear {
            lastSeenCount = bus.events.count
            hasUnreadError = false
        }
    }

    private var hasNewEvents: Bool {
        bus.events.count > lastSeenCount
    }

    private func updateBadge() {
        // 检测未读错误（最新事件是 error）
        if let last = bus.events.last, last.kind == .error, last.level == .error {
            hasUnreadError = true
        }
    }
}

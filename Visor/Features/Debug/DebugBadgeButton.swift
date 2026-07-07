import SwiftUI

/// Debug 按钮 + 事件计数 badge
struct DebugBadgeButton: View {
    @Binding var showDebug: Bool
    @ObservedObject private var bus = DebugBus.shared
    @State private var lastSeenCount: Int = 0
    @State private var hasUnreadError: Bool = false

    var body: some View {
        Button {
            showDebug = true
            lastSeenCount = bus.events.count
            hasUnreadError = false
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "ladybug")
                    .font(.system(size: DesignTokens.Touch.icon, weight: .medium))
                    .foregroundStyle(.primary)
                    .circularGlass(size: DesignTokens.Touch.standard)

                if hasUnreadError {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .offset(x: 5, y: -3)
                } else if hasNewEvents {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                        .offset(x: 5, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
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
        if let last = bus.events.last, last.kind == .error, last.level == .error {
            hasUnreadError = true
        }
    }
}

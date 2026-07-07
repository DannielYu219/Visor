import SwiftUI

/// 底部输入栏（整体 pill 胶囊容器，内嵌圆形 glass 发送按钮）
struct ComposerBar: View {

    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField(
                "输入消息…",
                text: $text,
                axis: .vertical
            )
            .font(.visorBodyLarge)
            .lineLimit(1...5)
            .padding(.leading, 18)
            .padding(.trailing, 4)
            .padding(.vertical, 9)
            .focused($isFocused)
            .submitLabel(.send)
            .onSubmit(submit)

            // 圆形 glass 发送 / 停止按钮
            Button(action: action) {
                Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                    .font(.system(size: DesignTokens.Touch.compactIcon, weight: .medium))
                    .foregroundStyle(isStreaming ? Color.visorStatusFailedText : .primary)
                    .frame(width: DesignTokens.Touch.compact, height: DesignTokens.Touch.compact)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming ? 0.4 : 1.0)
            .accessibilityLabel(isStreaming ? "停止生成" : "发送消息")
            .padding(.trailing, 6)
            .padding(.vertical, 4)
        }
        .background(Color.visorSecondaryBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.bottom, DesignTokens.Spacing.s)
    }

    private var action: () -> Void {
        isStreaming ? onStop : onSend
    }

    private func submit() {
        guard !isStreaming else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend()
    }
}

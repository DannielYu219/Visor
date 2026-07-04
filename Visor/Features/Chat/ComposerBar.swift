import SwiftUI

/// 底部输入栏
struct ComposerBar: View {

    @Binding var text: String
    let isStreaming: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: DesignTokens.Spacing.s) {
            TextField(
                "输入消息…",
                text: $text,
                axis: .vertical
            )
            .font(.visorBodyLarge)
            .lineLimit(1...5)
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.vertical, DesignTokens.Spacing.m)
            .glassBackground(corner: DesignTokens.Radius.m)
            .focused($isFocused)
            .submitLabel(.send)
            .onSubmit(submit)

            actionButton
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.bottom, DesignTokens.Spacing.m)
    }

    @ViewBuilder
    private var actionButton: some View {
        Button(action: action) {
            Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(.white)
                .background(
                    Circle()
                        .fill(isStreaming ? Color.visorStatusFailedText : Color.accentColor)
                )
        }
        .disabled(!isStreaming && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .accessibilityLabel(isStreaming ? "停止生成" : "发送消息")
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

import SwiftUI

/// 消息气泡（2026-07-04 v4：加 reasoning 折叠）
struct MessageBubble: View {
    let message: ChatMessage
    @State private var reasoningExpanded: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            if message.role == "user" {
                Spacer(minLength: DesignTokens.Spacing.xxl * 2)
                bubbleContent
            } else {
                bubbleContent
                Spacer(minLength: DesignTokens.Spacing.xxl * 2)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: DesignTokens.Spacing.xs) {
            if message.role == "tool" {
                toolBubble
            } else {
                // reasoning 折叠区（仅 assistant 且有 reasoning 时显示）
                if !message.reasoning.isEmpty {
                    reasoningSection
                }
                // 正文
                if !message.content.isEmpty || message.isStreaming {
                    Text(message.content.isEmpty && message.isStreaming ? " " : message.content)
                        .font(.visorBodyLarge)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .padding(.horizontal, DesignTokens.Spacing.l)
                        .padding(.vertical, DesignTokens.Spacing.m)
                        .glassBackground(corner: DesignTokens.Radius.m)
                }
            }

            // 元信息
            HStack(spacing: DesignTokens.Spacing.xs) {
                if message.isStreaming {
                    TypingIndicator()
                }
                if message.costUSD > 0 {
                    Text(String(format: "$%.4f", message.costUSD))
                        .font(.visorCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
        }
    }

    /// 思考过程折叠区
    private var reasoningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    reasoningExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                    Text("思考过程")
                        .font(.visorCaption)
                    Image(systemName: reasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if reasoningExpanded {
                Text(message.reasoning)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.horizontal, DesignTokens.Spacing.m)
                    .padding(.vertical, DesignTokens.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.visorTertiaryBackground.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, DesignTokens.Spacing.xs)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.s)
    }

    /// 工具结果气泡
    private var toolBubble: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                if let name = message.name {
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
                Text(formatToolResult(message.content))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(20)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.m)
        .padding(.vertical, DesignTokens.Spacing.s)
        .frame(maxWidth: 480, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.06))
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.green.opacity(0.5))
                .frame(width: 2)
        }
    }

    private func formatToolResult(_ raw: String) -> String {
        if raw.count <= 200 { return raw }
        return String(raw.prefix(200)) + "…"
    }
}

/// 流式打字指示器
private struct TypingIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
                    .opacity(phase == i ? 1.0 : 0.3)
            }
        }
        .onAppear { startTimer() }
    }

    private func startTimer() {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

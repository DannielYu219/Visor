import SwiftUI

/// 消息气泡（2026-07-07 v6：用户气泡 accent 蓝染色，助手气泡 surface 底 + 边框）
struct MessageBubble: View {
    let message: ChatMessage
    @State private var reasoningExpanded: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.s) {
            if message.role == "user" {
                Spacer(minLength: DesignTokens.Spacing.xxxl * 2)
                bubbleContent
            } else {
                bubbleContent
                Spacer(minLength: DesignTokens.Spacing.xxxl * 2)
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
                // 图片附件（仅 user 消息）
                if message.role == "user", let attachments = message.attachments, !attachments.isEmpty {
                    attachmentsSection(attachments)
                }
                // 正文
                if !message.content.isEmpty || message.isStreaming {
                    contentView
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

    /// 用户消息的图片附件渲染
    @ViewBuilder
    private func attachmentsSection(_ attachments: [String]) -> some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(Array(attachments.enumerated()), id: \.offset) { _, dataURL in
                if let img = Self.imageFromDataURL(dataURL) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                        .fill(Color.visorTertiaryBackground)
                        .frame(width: 220, height: 220)
                        .overlay(
                            VStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 24))
                                Text("图片解码失败")
                                    .font(.visorCaption)
                            }
                            .foregroundStyle(.secondary)
                        )
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                .fill(Color.visorUserBubble)
        )
    }

    /// 正文内容
    @ViewBuilder
    private var contentView: some View {
        let displayText = message.content.isEmpty && message.isStreaming ? " " : message.content
        if message.role == "user" {
            Text(displayText)
                .font(.visorBodyLarge)
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.vertical, DesignTokens.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                        .fill(Color.visorUserBubble)
                )
        } else {
            MarkdownView(text: displayText)
                .padding(.horizontal, DesignTokens.Spacing.l)
                .padding(.vertical, DesignTokens.Spacing.m)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                        .fill(Color.visorAssistantBubble)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                )
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
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous))
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
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous)
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

    /// 从 data URL 字符串解码出 UIImage
    private static func imageFromDataURL(_ dataURL: String) -> UIImage? {
        guard let commaIdx = dataURL.range(of: ",") else { return nil }
        let base64 = String(dataURL[commaIdx.upperBound...])
        guard let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }
}

/// Markdown 渲染视图
/// 使用 AttributedString 解析 Markdown，支持标题/粗体/斜体/代码块/列表/链接
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: - Block 解析

    private enum Block {
        case heading(level: Int, content: String)
        case paragraph(String)
        case codeBlock(language: String?, content: String)
        case listItem(String, ordered: Bool, index: Int)
        case blockquote(String)
        case thematicBreak
        case blank
    }

    private var blocks: [Block] {
        parseBlocks(text)
    }

    private func parseBlocks(_ source: String) -> [Block] {
        var result: [Block] = []
        let lines = source.components(separatedBy: "\n")
        var i = 0
        var orderedIndex = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行
            if trimmed.isEmpty {
                result.append(.blank)
                orderedIndex = 0
                i += 1
                continue
            }

            // 代码块 ```
            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // 跳过结束的 ```
                result.append(.codeBlock(language: lang.isEmpty ? nil : lang, content: codeLines.joined(separator: "\n")))
                orderedIndex = 0
                continue
            }

            // 分隔线
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                result.append(.thematicBreak)
                orderedIndex = 0
                i += 1
                continue
            }

            // 标题
            if let level = headingLevel(trimmed) {
                let content = trimmed.replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                result.append(.heading(level: level, content: content))
                orderedIndex = 0
                i += 1
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                let content = trimmed.replacingOccurrences(of: "^>\\s*", with: "", options: .regularExpression)
                result.append(.blockquote(content))
                orderedIndex = 0
                i += 1
                continue
            }

            // 有序列表
            if let match = trimmed.range(of: "^\\d+\\.\\s", options: .regularExpression) {
                let content = String(trimmed[match.upperBound...])
                orderedIndex += 1
                result.append(.listItem(content, ordered: true, index: orderedIndex))
                i += 1
                continue
            }

            // 无序列表
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let content = String(trimmed.dropFirst(2))
                result.append(.listItem(content, ordered: false, index: 0))
                orderedIndex = 0
                i += 1
                continue
            }

            // 普通段落
            result.append(.paragraph(trimmed))
            orderedIndex = 0
            i += 1
        }

        return result
    }

    private func headingLevel(_ line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        if count > 0 && count <= 6 && line.count > count && line[line.index(line.startIndex, offsetBy: count)] == " " {
            return count
        }
        return nil
    }

    // MARK: - Block 渲染

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let content):
            headingView(level: level, content: content)

        case .paragraph(let content):
            inlineText(content)
                .font(.visorBodyLarge)
                .lineSpacing(4)

        case .codeBlock(_, let content):
            Text(content)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, DesignTokens.Spacing.m)
                .padding(.vertical, DesignTokens.Spacing.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.visorTertiaryBackground.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs, style: .continuous))

        case .listItem(let content, let ordered, let index):
            HStack(alignment: .top, spacing: 6) {
                if ordered {
                    Text("\(index).")
                        .font(.visorBodyLarge)
                        .foregroundStyle(.secondary)
                } else {
                    Text("•")
                        .font(.visorBodyLarge)
                        .foregroundStyle(.secondary)
                }
                inlineText(content)
                    .font(.visorBodyLarge)
                    .lineSpacing(4)
            }

        case .blockquote(let content):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                inlineText(content)
                    .font(.visorBodyLarge)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
            }

        case .thematicBreak:
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 1)

        case .blank:
            Color.clear.frame(height: 4)
        }
    }

    @ViewBuilder
    private func headingView(level: Int, content: String) -> some View {
        let font: Font = {
            switch level {
            case 1: return .system(size: 26, weight: .bold)
            case 2: return .system(size: 23, weight: .bold)
            case 3: return .system(size: 21, weight: .semibold)
            case 4: return .system(size: 19, weight: .semibold)
            case 5: return .system(size: 18, weight: .semibold)
            default: return .visorBodyLarge
            }
        }()
        Text(inlineAttributed(content))
            .font(font)
            .lineSpacing(2)
    }

    // MARK: - Inline 渲染

    private func inlineText(_ s: String) -> some View {
        Text(inlineAttributed(s))
    }

    private func inlineAttributed(_ s: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: s) {
            return attr
        }
        return AttributedString(s)
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

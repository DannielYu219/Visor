import SwiftUI
import SwiftData
import os.log

/// 聊天会话视图（中栏）
struct DesignSessionView: View {
    @State private var viewModel: ChatViewModel
    @ObservedObject var budgetGuard: BudgetGuard
    let sessionId: UUID
    @Environment(\.modelContext) private var modelContext

    init(budgetGuard: BudgetGuard, sessionId: UUID) {
        self.budgetGuard = budgetGuard
        self.sessionId = sessionId
        _viewModel = State(initialValue: ChatViewModel(budgetGuard: budgetGuard))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let error = viewModel.errorMessage {
                errorBanner(error)
            }
            if viewModel.activeSkillName != nil {
                skillBadge
            }
            Divider().opacity(0.2)
            chatPanel
            ComposerBar(viewModel: viewModel) { url in
                viewModel.importFile(url)
            }
        }
        .background(Color.visorBackground)
        .onAppear { viewModel.attachSession(sessionId, context: modelContext) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(OpenRouterModels.find(viewModel.selectedModelId)?.displayName ?? viewModel.selectedModelId)
                    .font(.visorTitle)
                HStack(spacing: 6) {
                    Text(String(format: "$%.4f", viewModel.sessionCostUSD))
                    Text("·")
                    Text("in \(viewModel.sessionInputTokens)")
                    Text("·")
                    Text("out \(viewModel.sessionOutputTokens)")
                }
                .font(.visorCaption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer()
            modelPicker
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.l)
    }

    private var modelPicker: some View {
        Menu {
            ForEach(OpenRouterModels.catalog, id: \.id) { info in
                Button {
                    viewModel.selectedModelId = info.id
                } label: {
                    HStack {
                        Text(info.displayName)
                        if info.id == viewModel.selectedModelId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "cpu")
                .font(.system(size: DesignTokens.Touch.icon, weight: .medium))
                .foregroundStyle(.primary)
                .circularGlass(size: DesignTokens.Touch.standard)
        }
        .accessibilityLabel("选择模型")
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.m)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                if let last = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "paintbrush.pointed")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("试试输入「做一个 pitch deck」或「设计一个登录页」")
                .font(.visorCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.xxxl)
    }

    // MARK: - Banners

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.visorStatusFailedText)
            Text(message)
                .font(.visorCaption)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16))
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
        .background(Color.visorStatusFailed)
    }

    private var skillBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple)
            Text("已路由到 \(viewModel.activeSkillName ?? "")")
                .font(.visorCaption)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
        .background(Color.visorStatusRunning)
    }
}

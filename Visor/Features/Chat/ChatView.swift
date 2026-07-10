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
                Text(modelDisplayName(viewModel.selectedModelId))
                    .font(.visorTitle)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(String(format: "$%.4f", viewModel.sessionCostUSD))
                    Text("·")
                    Text("chat.token.in".l(viewModel.sessionInputTokens))
                    Text("·")
                    Text("chat.token.out".l(viewModel.sessionOutputTokens))
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

    /// 解析模型显示名（支持自定义服务商模型）
    private func modelDisplayName(_ modelId: String) -> String {
        if let resolved = CustomProviderRegistry.shared.resolve(modelId) {
            return resolved.displayName
        }
        return OpenRouterModels.find(modelId)?.displayName ?? modelId
    }

    private var modelPicker: some View {
        Menu {
            // OpenRouter 内置模型
            Section("OpenRouter") {
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
            }

            // 自定义服务商模型（按 provider 分组）
            let customProviders = CustomProviderRegistry.shared.allConfigs()
            ForEach(customProviders, id: \.id) { config in
                Section(config.name) {
                    ForEach(config.models, id: \.id) { model in
                        let namespaced = config.namespacedModelId(model.id)
                        Button {
                            viewModel.selectedModelId = namespaced
                        } label: {
                            HStack {
                                Text(model.displayName)
                                if namespaced == viewModel.selectedModelId {
                                    Image(systemName: "checkmark")
                                }
                            }
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
        .accessibilityLabel("chat.modelPicker".l)
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
            Text("chat.empty.hint".l)
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
            Text("chat.skillRouted".l(viewModel.activeSkillName ?? ""))
                .font(.visorCaption)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.l)
        .padding(.vertical, DesignTokens.Spacing.s)
        .background(Color.visorStatusRunning)
    }
}

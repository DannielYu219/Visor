import SwiftUI

/// 设置页
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false
    @State private var saveStatus: SaveStatus = .idle
    @ObservedObject var budgetGuard: BudgetGuard

    enum SaveStatus: Equatable {
        case idle
        case saved
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                    // API Key 卡片
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Text("OpenRouter API Key")
                            .font(.visorTitle)

                        HStack(spacing: DesignTokens.Spacing.s) {
                            Group {
                                if showKey {
                                    TextField("API Key", text: $apiKeyInput)
                                } else {
                                    SecureField("API Key", text: $apiKeyInput)
                                }
                            }
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.visorBody)
                            .padding(.horizontal, DesignTokens.Spacing.l)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                                    .fill(Color.visorTertiaryBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.m, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            )

                            CircularGlassButton(
                                systemName: showKey ? "eye.slash" : "eye",
                                iconSize: DesignTokens.Touch.compactIcon,
                                size: DesignTokens.Touch.compact,
                                action: { showKey.toggle() }
                            )
                            .accessibilityLabel(showKey ? "隐藏 API Key" : "显示 API Key")
                        }

                        HStack(spacing: DesignTokens.Spacing.s) {
                            Button("保存到 Keychain") {
                                saveKey()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("清除已保存的 Key", role: .destructive) {
                                KeychainStore.openRouterAPIKey = nil
                                apiKeyInput = ""
                                saveStatus = .idle
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }

                        switch saveStatus {
                        case .idle:
                            EmptyView()
                        case .saved:
                            Text("已保存")
                                .font(.visorCaption)
                                .foregroundStyle(Color.visorStatusSuccessText)
                        case .error(let msg):
                            Text(msg)
                                .font(.visorCaption)
                                .foregroundStyle(Color.visorStatusFailedText)
                        }
                    }
                    .padding(DesignTokens.Spacing.xxl)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous)
                            .fill(Color.visorBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 16, y: 4)

                    // 预算卡片
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Text("预算（USD）")
                            .font(.visorTitle)
                        BudgetEditor(budgetGuard: budgetGuard)
                    }
                    .padding(DesignTokens.Spacing.xxl)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous)
                            .fill(Color.visorBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 16, y: 4)

                    // 模型定价卡片
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("模型定价（实时）")
                            .font(.visorTitle)
                        ForEach(OpenRouterModels.catalog, id: \.id) { info in
                            if let p = ModelPricingTable.shared.pricing(for: info.id) {
                                HStack {
                                    Text(info.displayName)
                                        .font(.visorBody)
                                    Spacer()
                                    Text(String(format: "in $%.2f / out $%.2f", p.inputPricePerMTokensUSD, p.outputPricePerMTokensUSD))
                                        .font(.visorCaption)
                                        .foregroundStyle(.secondary)
                                }
                                Divider().opacity(0.1)
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.xxl)
                    .background(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous)
                            .fill(Color.visorBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.l, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 16, y: 4)
                }
                .padding(DesignTokens.Spacing.l)
            }
            .background(Color.visorSecondaryBackground)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                if let existing = KeychainStore.openRouterAPIKey {
                    apiKeyInput = existing
                }
            }
        }
    }

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            saveStatus = .error("API Key 不能为空")
            return
        }
        do {
            try KeychainStore.set(trimmed, for: .openRouterAPIKey)
            saveStatus = .saved
        } catch {
            saveStatus = .error(error.localizedDescription)
        }
    }
}

/// 预算编辑器
struct BudgetEditor: View {
    @ObservedObject var budgetGuard: BudgetGuard
    @State private var sessionUSD: Double = 5
    @State private var dailyUSD: Double = 20
    @State private var monthlyUSD: Double = 200

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            stepperRow(label: "会话", value: $sessionUSD)
            stepperRow(label: "日", value: $dailyUSD)
            stepperRow(label: "月", value: $monthlyUSD)

            Button("应用预算") {
                budgetGuard.update(limit: .init(
                    sessionUSD: sessionUSD,
                    dailyUSD: dailyUSD,
                    monthlyUSD: monthlyUSD
                ))
            }
            .font(.visorCaption)
        }
        .onAppear {
            sessionUSD = budgetGuard.limit.sessionUSD
            dailyUSD = budgetGuard.limit.dailyUSD
            monthlyUSD = budgetGuard.limit.monthlyUSD
        }
    }

    @ViewBuilder
    private func stepperRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.visorBody)
            Spacer()
            Text(String(format: "$%.2f", value.wrappedValue))
                .font(.visorCaption)
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: 1...1000, step: 1)
                .labelsHidden()
        }
    }
}

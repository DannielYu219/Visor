import SwiftUI

/// 设置页（Phase 1：API Key + 预算）
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
            Form {
                Section("OpenRouter") {
                    HStack {
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

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .accessibilityLabel(showKey ? "隐藏 API Key" : "显示 API Key")
                    }

                    Button {
                        saveKey()
                    } label: {
                        Text("保存到 Keychain")
                    }
                    .disabled(apiKeyInput.isEmpty)

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

                    Button("清除已保存的 Key") {
                        KeychainStore.openRouterAPIKey = nil
                        apiKeyInput = ""
                        saveStatus = .idle
                    }
                    .foregroundStyle(Color.visorStatusFailedText)
                }

                Section("预算（USD）") {
                    BudgetEditor(budgetGuard: budgetGuard)
                }

                Section("模型定价（实时）") {
                    ForEach(OpenRouterModels.catalog, id: \.id) { info in
                        if let p = ModelPricingTable.shared.pricing(for: info.id) {
                            HStack {
                                Text(info.displayName)
                                Spacer()
                                Text(String(format: "in $%.2f / out $%.2f", p.inputPricePerMTokensUSD, p.outputPricePerMTokensUSD))
                                    .font(.visorCaption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
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
            Spacer()
            Text(String(format: "$%.2f", value.wrappedValue))
                .font(.visorCaption)
                .foregroundStyle(.secondary)
            Stepper("", value: value, in: 1...1000, step: 1)
                .labelsHidden()
        }
    }
}

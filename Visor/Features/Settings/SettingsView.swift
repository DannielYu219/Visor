import SwiftUI

/// Sheet 编辑目标（Identifiable，解决 `isPresented` + `editingProvider` 的时序竞态）
private struct ProviderEditTarget: Identifiable {
    let id = UUID()
    let config: CustomProviderConfig?  // nil = 新增
}

/// 设置页
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var showKey: Bool = false
    @State private var saveStatus: SaveStatus = .idle
    @ObservedObject var budgetGuard: BudgetGuard

    // 自定义服务商
    @State private var customProviders: [CustomProviderConfig] = []
    @State private var editingTarget: ProviderEditTarget?

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

                    // 自定义服务商卡片
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        HStack {
                            Text("自定义服务商")
                                .font(.visorTitle)
                            Spacer()
                            Button {
                                editingTarget = ProviderEditTarget(config: nil)
                            } label: {
                                Label("添加", systemImage: "plus")
                                    .font(.visorCaption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if customProviders.isEmpty {
                            Text("添加 OpenAI 兼容的自定义服务商（如 OpenAI、Together、Groq 等）")
                                .font(.visorCaption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(customProviders) { config in
                                customProviderRow(config)
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
                reloadCustomProviders()
            }
            .sheet(item: $editingTarget, onDismiss: { reloadCustomProviders() }) { target in
                CustomProviderEditorSheet(
                    editing: target.config,
                    onSave: { config, apiKey in
                        saveCustomProvider(config, apiKey: apiKey)
                    }
                )
            }
        }
    }

    // MARK: - 自定义服务商

    private func reloadCustomProviders() {
        CustomProviderRegistry.shared.reload()
        customProviders = CustomProviderRegistry.shared.allConfigs()
    }

    @ViewBuilder
    private func customProviderRow(_ config: CustomProviderConfig) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(.visorBody)
                    Text(config.baseURL)
                        .font(.visorCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(config.models.count) 个模型")
                        .font(.visorCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editingTarget = ProviderEditTarget(config: config)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑")

                Button(role: .destructive) {
                    deleteCustomProvider(config)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.visorStatusFailedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
            }
        }
        .padding(DesignTokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous)
                .fill(Color.visorTertiaryBackground)
        )
    }

    private func saveCustomProvider(_ config: CustomProviderConfig, apiKey: String) {
        var current = CustomProviderRegistry.shared.allConfigs()
        if let idx = current.firstIndex(where: { $0.id == config.id }) {
            current[idx] = config
        } else {
            current.append(config)
        }
        CustomProviderRegistry.shared.save(current)
        // 保存 API Key 到 Keychain
        if !apiKey.isEmpty {
            try? CustomProviderRegistry.shared.setAPIKey(apiKey, for: config.id)
        }
        reloadCustomProviders()
    }

    private func deleteCustomProvider(_ config: CustomProviderConfig) {
        var current = CustomProviderRegistry.shared.allConfigs()
        current.removeAll { $0.id == config.id }
        CustomProviderRegistry.shared.save(current)
        CustomProviderRegistry.shared.deleteAPIKey(for: config.id)
        reloadCustomProviders()
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

/// 自定义服务商编辑器
struct CustomProviderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 传入 nil 表示新增
    let editing: CustomProviderConfig?
    /// 保存回调：(配置, API Key 明文)
    let onSave: (CustomProviderConfig, String) -> Void

    @State private var name: String = ""
    @State private var baseURL: String = ""
    @State private var apiKey: String = ""
    @State private var showAPIKey: Bool = false
    @State private var models: [EditableModel] = []
    @State private var errorMessage: String?
    @State private var hasExistingKey: Bool = false
    @State private var thinkingMode: DeepSeekThinkingMode = .disabled
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(modelCount: Int)
        case failure(String)
    }

    /// 当前 URL 是否被检测为 DeepSeek
    private var detectedDeepSeek: Bool {
        baseURL.lowercased().contains("deepseek")
    }

    /// 可编辑模型（UUID 身份，避免空 ID 冲突）
    struct EditableModel: Identifiable {
        let id = UUID()
        var modelId: String = ""
        var displayName: String = ""
        var supportsVision: Bool = false
    }

    private var isNew: Bool { editing == nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.l) {
                    // 基础信息
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("服务商信息")
                            .font(.visorTitle)

                        labeledField("名称") {
                            TextField("如：我的 OpenAI", text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        labeledField("Base URL") {
                            TextField("https://api.openai.com/v1", text: $baseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        Text("OpenAI 兼容格式，需包含 /v1 路径")
                            .font(.visorCaption)
                            .foregroundStyle(.secondary)
                    }

                    // API Key
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("API Key")
                            .font(.visorTitle)
                        HStack(spacing: DesignTokens.Spacing.s) {
                            Group {
                                if showAPIKey {
                                    TextField("API Key", text: $apiKey)
                                } else {
                                    SecureField("API Key", text: $apiKey)
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
                                systemName: showAPIKey ? "eye.slash" : "eye",
                                iconSize: DesignTokens.Touch.compactIcon,
                                size: DesignTokens.Touch.compact,
                                action: { showAPIKey.toggle() }
                            )
                        }
                        if hasExistingKey && apiKey.isEmpty {
                            Text("已配置 API Key（留空则保持不变）")
                                .font(.visorCaption)
                                .foregroundStyle(.secondary)
                        }

                        // 联通性测试按钮
                        HStack(spacing: DesignTokens.Spacing.s) {
                            Button {
                                testConnectivity()
                            } label: {
                                HStack(spacing: 4) {
                                    if isTesting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                    }
                                    Text(isTesting ? "测试中…" : "测试连接")
                                }
                                .font(.visorCaption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isTesting)

                            if let result = testResult {
                                switch result {
                                case .success(let count):
                                    Text("✓ 已连接，\(count) 个模型")
                                        .font(.visorCaption)
                                        .foregroundStyle(Color.visorStatusSuccessText)
                                case .failure(let msg):
                                    Text("✗ \(msg)")
                                        .font(.visorCaption)
                                        .foregroundStyle(Color.visorStatusFailedText)
                                }
                            }
                        }
                    }

                    // DeepSeek 思考模式（仅在检测到 DeepSeek 时显示）
                    if detectedDeepSeek {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                            Text("DeepSeek 思考模式")
                                .font(.visorTitle)
                            Picker("思考强度", selection: $thinkingMode) {
                                ForEach(DeepSeekThinkingMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text("高 — 适用于普通任务；最大 — 适用于复杂 Agent 任务")
                                .font(.visorCaption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 模型列表
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        HStack {
                            Text("模型列表")
                                .font(.visorTitle)
                            Spacer()
                            Button {
                                models.append(EditableModel())
                            } label: {
                                Label("添加模型", systemImage: "plus")
                                    .font(.visorCaption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if models.isEmpty {
                            Text("至少添加一个模型")
                                .font(.visorCaption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach($models) { $model in
                                modelRow($model)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.visorCaption)
                            .foregroundStyle(Color.visorStatusFailedText)
                    }
                }
                .padding(DesignTokens.Spacing.l)
            }
            .background(Color.visorSecondaryBackground)
            .navigationTitle(isNew ? "添加自定义服务商" : "编辑服务商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .onAppear { loadEditing() }
        }
    }

    // MARK: - 子视图

    @ViewBuilder
    private func labeledField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.visorCaption)
                .foregroundStyle(.secondary)
            content()
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
        }
    }

    @ViewBuilder
    private func modelRow(_ model: Binding<EditableModel>) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.s) {
                TextField("模型 ID（如 deepseek-v4-pro）", text: model.modelId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.visorBody)
                Button(role: .destructive) {
                    if let idx = models.firstIndex(where: { $0.id == model.wrappedValue.id }) {
                        models.remove(at: idx)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color.visorStatusFailedText)
                }
                .buttonStyle(.plain)
            }
            TextField("显示名称", text: model.displayName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.visorBody)
            Toggle("支持图片输入", isOn: model.supportsVision)
                .font(.visorCaption)
        }
        .padding(DesignTokens.Spacing.s)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.s, style: .continuous)
                .fill(Color.visorTertiaryBackground)
        )
    }

    // MARK: - 逻辑

    private func loadEditing() {
        guard let editing else { return }
        name = editing.name
        baseURL = editing.baseURL
        models = editing.models.map { EditableModel(modelId: $0.id, displayName: $0.displayName, supportsVision: $0.supportsVision) }
        thinkingMode = editing.thinkingMode
        // 检查是否已有 API Key（不读取明文到内存，仅标记）
        hasExistingKey = CustomProviderRegistry.shared.apiKey(for: editing.id) != nil
    }

    // MARK: - 联通性测试

    private func testConnectivity() {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty, let base = URL(string: trimmedURL) else {
            testResult = .failure("Base URL 无效")
            return
        }

        let key: String
        if !apiKey.isEmpty {
            key = apiKey
        } else if let existing = editing.flatMap({ CustomProviderRegistry.shared.apiKey(for: $0.id) }) {
            key = existing
        } else {
            testResult = .failure("请先输入 API Key")
            return
        }

        isTesting = true
        testResult = nil

        let url = base.appendingPathComponent("models")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard let http = resp as? HTTPURLResponse else {
                    await MainActor.run {
                        isTesting = false
                        testResult = .failure("响应格式异常")
                    }
                    return
                }
                await MainActor.run {
                    isTesting = false
                    if http.statusCode == 200 {
                        // 尝试解析模型列表计数
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let list = json["data"] as? [[String: Any]] {
                            testResult = .success(modelCount: list.count)
                        } else {
                            testResult = .success(modelCount: 0)
                        }
                    } else if http.statusCode == 401 || http.statusCode == 403 {
                        testResult = .failure("API Key 无效（\(http.statusCode)）")
                    } else {
                        let body = String(data: data, encoding: .utf8) ?? ""
                        let preview = String(body.prefix(80))
                        testResult = .failure("HTTP \(http.statusCode): \(preview)")
                    }
                }
            } catch {
                await MainActor.run {
                    isTesting = false
                    testResult = .failure(error.localizedDescription)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请填写服务商名称"
            return
        }
        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else {
            errorMessage = "Base URL 无效"
            return
        }
        let validModels = models.compactMap { m -> CustomModelInfo? in
            let mid = m.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let dname = m.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mid.isEmpty, !dname.isEmpty else { return nil }
            // 防止将 Base URL 误填为模型 ID
            if mid.lowercased().hasPrefix("http://") || mid.lowercased().hasPrefix("https://") {
                errorMessage = "模型 ID「\(mid)」看起来像 URL，请填写模型名称（如 deepseek-v4-pro）"
                return nil
            }
            return CustomModelInfo(id: mid, displayName: dname, supportsVision: m.supportsVision)
        }
        guard !validModels.isEmpty, errorMessage == nil else {
            if errorMessage == nil { errorMessage = "至少添加一个有效的模型（需填写 ID 和显示名称）" }
            return
        }

        let id = editing?.id ?? UUID()
        let config = CustomProviderConfig(
            id: id,
            name: trimmedName,
            baseURL: trimmedURL,
            models: validModels,
            createdAt: editing?.createdAt ?? Date(),
            thinkingMode: thinkingMode
        )
        // 如果编辑时未输入新 Key 且已有 Key，传空串表示保持不变
        onSave(config, apiKey)
        dismiss()
    }
}

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

    // 语言
    @ObservedObject private var languageManager = LanguageManager.shared

    enum SaveStatus: Equatable {
        case idle
        case saved
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
                    // 语言卡片
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Text("settings.language.title".l)
                            .font(.visorTitle)
                        Text("settings.language.subtitle".l)
                            .font(.visorCaption)
                            .foregroundStyle(.secondary)
                        Picker("", selection: $languageManager.selected) {
                            ForEach(AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
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

                    // API Key 卡片
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.m) {
                        Text("settings.apikey.title".l)
                            .font(.visorTitle)

                        HStack(spacing: DesignTokens.Spacing.s) {
                            Group {
                                if showKey {
                                    TextField("settings.apikey.placeholder".l, text: $apiKeyInput)
                                } else {
                                    SecureField("settings.apikey.placeholder".l, text: $apiKeyInput)
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
                            .accessibilityLabel(showKey ? "settings.apikey.hide".l : "settings.apikey.show".l)
                        }

                        HStack(spacing: DesignTokens.Spacing.s) {
                            Button("settings.apikey.save".l) {
                                saveKey()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("settings.apikey.clear".l, role: .destructive) {
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
                            Text("settings.apikey.saved".l)
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
                            Text("settings.customProvider.title".l)
                                .font(.visorTitle)
                            Spacer()
                            Button {
                                editingTarget = ProviderEditTarget(config: nil)
                            } label: {
                                Label("common.add".l, systemImage: "plus")
                                    .font(.visorCaption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if customProviders.isEmpty {
                            Text("settings.customProvider.empty".l)
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
                        Text("settings.budget.title".l)
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
                        Text("settings.pricing.title".l)
                            .font(.visorTitle)
                        ForEach(OpenRouterModels.catalog, id: \.id) { info in
                            if let p = ModelPricingTable.shared.pricing(for: info.id) {
                                HStack {
                                    Text(info.displayName)
                                        .font(.visorBody)
                                    Spacer()
                                    Text("settings.pricing.row".l(p.inputPricePerMTokensUSD, p.outputPricePerMTokensUSD))
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
            .navigationTitle("settings.title".l)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".l) { dismiss() }
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
                    Text("settings.customProvider.modelCount".l(config.models.count))
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
                .accessibilityLabel("common.edit".l)

                Button(role: .destructive) {
                    deleteCustomProvider(config)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.visorStatusFailedText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("common.delete".l)
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
            saveStatus = .error("settings.apikey.empty".l)
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
            stepperRow(label: "settings.budget.session".l, value: $sessionUSD)
            stepperRow(label: "settings.budget.daily".l, value: $dailyUSD)
            stepperRow(label: "settings.budget.monthly".l, value: $monthlyUSD)

            Button("settings.budget.apply".l) {
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
                        Text("provider.editor.section.info".l)
                            .font(.visorTitle)

                        labeledField("provider.editor.name".l) {
                            TextField("provider.editor.name.placeholder".l, text: $name)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        labeledField("provider.editor.baseURL".l) {
                            TextField("https://api.openai.com/v1", text: $baseURL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                        }
                        Text("provider.editor.baseURL.hint".l)
                            .font(.visorCaption)
                            .foregroundStyle(.secondary)
                    }

                    // API Key
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        Text("provider.editor.apiKey.title".l)
                            .font(.visorTitle)
                        HStack(spacing: DesignTokens.Spacing.s) {
                            Group {
                                if showAPIKey {
                                    TextField("provider.editor.apiKey.placeholder".l, text: $apiKey)
                                } else {
                                    SecureField("provider.editor.apiKey.placeholder".l, text: $apiKey)
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
                            Text("provider.editor.apiKey.existing".l)
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
                                    Text(isTesting ? "provider.editor.testing".l : "provider.editor.test".l)
                                }
                                .font(.visorCaption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isTesting)

                            if let result = testResult {
                                switch result {
                                case .success(let count):
                                    Text("provider.editor.test.success".l(count))
                                        .font(.visorCaption)
                                        .foregroundStyle(Color.visorStatusSuccessText)
                                case .failure(let msg):
                                    Text("provider.editor.test.failure".l(msg))
                                        .font(.visorCaption)
                                        .foregroundStyle(Color.visorStatusFailedText)
                                }
                            }
                        }
                    }

                    // DeepSeek 思考模式（仅在检测到 DeepSeek 时显示）
                    if detectedDeepSeek {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                            Text("provider.editor.deepseek.title".l)
                                .font(.visorTitle)
                            Picker("provider.editor.deepseek.intensity".l, selection: $thinkingMode) {
                                ForEach(DeepSeekThinkingMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text("provider.editor.deepseek.hint".l)
                                .font(.visorCaption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // 模型列表
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
                        HStack {
                            Text("provider.editor.models.title".l)
                                .font(.visorTitle)
                            Spacer()
                            Button {
                                models.append(EditableModel())
                            } label: {
                                Label("provider.editor.models.add".l, systemImage: "plus")
                                    .font(.visorCaption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if models.isEmpty {
                            Text("provider.editor.models.empty".l)
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
            .navigationTitle(isNew ? "provider.editor.title.new".l : "provider.editor.title.edit".l)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".l) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save".l) { save() }
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
                TextField("provider.editor.model.idPlaceholder".l, text: model.modelId)
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
            TextField("provider.editor.model.displayName".l, text: model.displayName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.visorBody)
            Toggle("provider.editor.model.supportsVision".l, isOn: model.supportsVision)
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
            testResult = .failure("provider.editor.test.baseURLInvalid".l)
            return
        }

        let key: String
        if !apiKey.isEmpty {
            key = apiKey
        } else if let existing = editing.flatMap({ CustomProviderRegistry.shared.apiKey(for: $0.id) }) {
            key = existing
        } else {
            testResult = .failure("provider.editor.test.apiKeyMissing".l)
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
                        testResult = .failure("provider.editor.test.responseInvalid".l)
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
                        testResult = .failure("provider.editor.test.apiKeyInvalid".l(http.statusCode))
                    } else {
                        let body = String(data: data, encoding: .utf8) ?? ""
                        let preview = String(body.prefix(80))
                        testResult = .failure("provider.editor.test.httpError".l(http.statusCode, preview))
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
            errorMessage = "provider.editor.error.nameRequired".l
            return
        }
        guard !trimmedURL.isEmpty, URL(string: trimmedURL) != nil else {
            errorMessage = "provider.editor.error.urlInvalid".l
            return
        }
        let validModels = models.compactMap { m -> CustomModelInfo? in
            let mid = m.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            let dname = m.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !mid.isEmpty, !dname.isEmpty else { return nil }
            // 防止将 Base URL 误填为模型 ID
            if mid.lowercased().hasPrefix("http://") || mid.lowercased().hasPrefix("https://") {
                errorMessage = "provider.editor.error.modelIdLikeURL".l(mid)
                return nil
            }
            return CustomModelInfo(id: mid, displayName: dname, supportsVision: m.supportsVision)
        }
        guard !validModels.isEmpty, errorMessage == nil else {
            if errorMessage == nil { errorMessage = "provider.editor.error.noValidModels".l }
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

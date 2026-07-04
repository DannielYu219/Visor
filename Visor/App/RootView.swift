import SwiftUI
import SwiftData

/// 根视图：横向三栏布局
/// 左：可折叠会话列表（SidebarView）
/// 中：当前会话（DesignSessionView）
/// 右：实时画布（DesignCanvasView）
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var budgetGuard = BudgetGuard()
    @State private var selectedSessionId: UUID?
    @State private var sidebarCollapsed: Bool = false
    /// 控制 Settings sheet
    @State private var showSettings: Bool = false
    /// 控制 Debug sheet
    @State private var showDebug: Bool = false
    /// 控制 API Key 空状态
    @State private var keychainTick: Int = 0
    @State private var skipEmptyState: Bool = false

    var body: some View {
        NavigationSplitView {
            sidebarColumn
                .navigationSplitViewColumnWidth(min: 56, ideal: 240, max: 320)
        } content: {
            chatColumn
                .navigationSplitViewColumnWidth(min: 360, ideal: 480)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 6) {
                            DebugBadgeButton(showDebug: $showDebug)
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("设置")
                        }
                    }
                }
        } detail: {
            canvasColumn
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        sidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                }
            }
        }
        .overlay {
            if showEmptyState {
                apiKeyEmptyState
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { keychainTick &+= 1 }) {
            SettingsView(budgetGuard: budgetGuard)
        }
        .sheet(isPresented: $showDebug) {
            DebugView()
        }
        .task {
            if selectedSessionId == nil {
                if let first = try? modelContext.fetch(FetchDescriptor<SessionEntity>()).first {
                    selectedSessionId = first.id
                } else {
                    let new = SessionEntity(title: "新会话")
                    modelContext.insert(new)
                    try? modelContext.save()
                    selectedSessionId = new.id
                }
            }
        }
    }

    // MARK: - Columns

    private var sidebarColumn: some View {
        SidebarView(
            selectedSessionId: $selectedSessionId,
            isCollapsed: $sidebarCollapsed
        )
    }

    private var chatColumn: some View {
        Group {
            if let id = selectedSessionId {
                DesignSessionView(
                    budgetGuard: budgetGuard,
                    sessionId: id
                )
                .id(id)
            } else {
                placeholder(text: "未选择会话")
            }
        }
    }

    private var canvasColumn: some View {
        Group {
            if let id = selectedSessionId {
                CanvasHostView(sessionId: id)
            } else {
                placeholder(text: "暂无画布")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty / Placeholder

    private func placeholder(text: String) -> some View {
        VStack {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.visorTitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - API Key Empty State（与之前 ChatView 中类似，提到 RootView）

    private var showEmptyState: Bool {
        _ = keychainTick
        return !skipEmptyState && KeychainStore.openRouterAPIKey == nil
    }

    private var apiKeyEmptyState: some View {
        GeometryReader { proxy in
            ZStack(alignment: .center) {
                Rectangle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .ignoresSafeArea()

                VStack(spacing: DesignTokens.Spacing.m) {
                    Image(systemName: "key.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("请先配置 OpenRouter API Key")
                        .font(.visorTitle)
                        .multilineTextAlignment(.center)
                    Text("在设置中粘贴您的 API Key 即可开始设计")
                        .font(.visorBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Button("前往设置") {
                            showSettings = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("稍后") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                skipEmptyState = true
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(DesignTokens.Spacing.xxl)
                .frame(maxWidth: 420)
                .glassBackgroundThick()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

/// 画布宿主（订阅 session 的文件变化并驱动 Canvas）
struct CanvasHostView: View {
    let sessionId: UUID
    @State private var canvasPath: String = ""
    @State private var skillName: String?
    @State private var session: SessionEntity?
    @Environment(\.modelContext) private var context

    var body: some View {
        DesignCanvasView(
            sessionId: sessionId,
            activePath: canvasPath,
            skillName: skillName
        )
        .task(id: sessionId) {
            session = try? context.fetch(
                FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == sessionId })
            ).first
        }
        // 接收 chat 的 canvasPath 更新（通过外部通知 / environment）
    }
}

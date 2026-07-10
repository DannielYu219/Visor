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
    @State private var showSettings: Bool = false
    @State private var showDebug: Bool = false
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
                        HStack(spacing: DesignTokens.Spacing.s) {
                            DebugBadgeButton(showDebug: $showDebug)
                            CircularGlassButton(
                                systemName: "gearshape",
                                action: { showSettings = true }
                            )
                            .accessibilityLabel("settings.title".l)
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
                        .font(.system(size: DesignTokens.Touch.icon, weight: .medium))
                        .foregroundStyle(.primary)
                        .circularGlass(size: DesignTokens.Touch.standard)
                }
                .buttonStyle(.plain)
            }
        }
        .ignoresSafeArea(edges: .top)
        .statusBarHidden(true)
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
                    let new = SessionEntity(title: "sidebar.newSession.defaultTitle".l)
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
                placeholder(text: "root.placeholder.noSession".l)
            }
        }
    }

    private var canvasColumn: some View {
        Group {
            if let id = selectedSessionId {
                CanvasHostView(sessionId: id)
                    .id(id)
            } else {
                placeholder(text: "root.placeholder.noCanvas".l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .bottom)
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

    // MARK: - API Key Empty State

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
                    Text("root.empty.apiKey.title".l)
                        .font(.visorTitle)
                        .multilineTextAlignment(.center)
                    Text("root.empty.apiKey.subtitle".l)
                        .font(.visorBody)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: DesignTokens.Spacing.s) {
                        Button("root.empty.apiKey.action".l) {
                            showSettings = true
                        }
                        .buttonStyle(.borderedProminent)
                        Button("common.later".l) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                skipEmptyState = true
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(DesignTokens.Spacing.xxxl)
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
    @State private var skillName: String?
    @State private var session: SessionEntity?
    @Environment(\.modelContext) private var context

    var body: some View {
        DesignCanvasView(
            sessionId: sessionId,
            skillName: skillName
        )
        .task(id: sessionId) {
            session = try? context.fetch(
                FetchDescriptor<SessionEntity>(predicate: #Predicate { $0.id == sessionId })
            ).first
        }
    }
}

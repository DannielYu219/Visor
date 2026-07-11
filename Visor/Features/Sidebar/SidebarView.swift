import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 会话侧边栏（左栏）：可折叠的会话列表
struct SidebarView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SessionEntity.updatedAt, order: .reverse) private var sessions: [SessionEntity]
    @Binding var selectedSessionId: UUID?
    @Binding var isCollapsed: Bool

    // 导入相关状态
    @State private var showImportPicker: Bool = false
    @State private var isImporting: Bool = false
    // 导出相关状态
    @State private var isExporting: Bool = false
    // 提示
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.2)
            sessionList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.visorSecondaryBackground)
        .overlay(alignment: .top) {
            if let toast = toast {
                Text(toast)
                    .font(.visorCaption)
                    .padding(.horizontal, DesignTokens.Spacing.l)
                    .padding(.vertical, DesignTokens.Spacing.s)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, DesignTokens.Spacing.s)
                    .transition(.opacity)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        await MainActor.run { self.toast = nil }
                    }
            }
        }
        .overlay {
            if isImporting || isExporting {
                ProgressView(isImporting ? "sidebar.importing".l : "sidebar.exporting".l)
                    .padding(DesignTokens.Spacing.xxl)
                    .glassBackground()
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task { await importProject(from: url) }
                }
            case .failure(let err):
                toast = "sidebar.import.error".l(err.localizedDescription)
            }
        }
    }

    private var header: some View {
        HStack {
            if !isCollapsed {
                Text("sidebar.title".l)
                    .font(.visorTitle)
                    .padding(.leading, DesignTokens.Spacing.l)
            }
            Spacer()
            CircularGlassButton(
                systemName: "square.and.arrow.down.on.square",
                iconSize: DesignTokens.Touch.icon,
                size: DesignTokens.Touch.standard,
                action: { showImportPicker = true }
            )
            .accessibilityLabel("sidebar.import".l)
            .padding(.trailing, DesignTokens.Spacing.s)

            CircularGlassButton(
                systemName: "plus",
                iconSize: DesignTokens.Touch.icon,
                size: DesignTokens.Touch.standard,
                action: { Task { await createNew() } }
            )
            .accessibilityLabel("sidebar.new".l)
            .padding(.trailing, DesignTokens.Spacing.l)
        }
        .padding(.vertical, DesignTokens.Spacing.m)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(sessions) { session in
                    sessionRow(session)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.s)
            .padding(.vertical, DesignTokens.Spacing.s)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionEntity) -> some View {
        let isSelected = session.id == selectedSessionId
        Button {
            selectedSessionId = session.id
        } label: {
            HStack(spacing: DesignTokens.Spacing.m) {
                Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .frame(width: 24, alignment: .center)
                if !isCollapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.visorBodyLarge)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(session.updatedAt.formatted(.relative(presentation: .numeric)))
                            .font(.visorCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: DesignTokens.Spacing.s)
                    if isSelected {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.l)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.s)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                Task { await exportSession(session) }
            } label: {
                Label("sidebar.export".l, systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                deleteSession(session)
            } label: {
                Label("sidebar.delete".l, systemImage: "trash")
            }
        }
    }

    @MainActor
    private func deleteSession(_ session: SessionEntity) {
        let id = session.id
        let fm = FileManager.default
        if let appSupport = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) {
            let dir = appSupport
                .appendingPathComponent("Visor", isDirectory: true)
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent(id.uuidString, isDirectory: true)
            try? fm.removeItem(at: dir)
        }
        context.delete(session)
        try? context.save()
        if selectedSessionId == id {
            let remaining = sessions.sorted { $0.updatedAt > $1.updatedAt }
            if let first = remaining.first {
                selectedSessionId = first.id
            } else {
                Task { await createNew() }
            }
        }
    }

    @MainActor
    private func createNew() async {
        let new = SessionEntity(title: "sidebar.newSession.defaultTitle".l)
        context.insert(new)
        try? context.save()
        selectedSessionId = new.id
    }

    // MARK: - 导出

    @MainActor
    private func exportSession(_ session: SessionEntity) async {
        let sid = session.id
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await VisorProjectCodec.export(sessionId: sid, context: context)
            presentShareSheet(url: url)
            toast = "sidebar.export.success".l(session.title)
        } catch {
            toast = "sidebar.export.error".l(error.localizedDescription)
        }
    }

    // MARK: - 导入

    @MainActor
    private func importProject(from url: URL) async {
        // 校验扩展名
        let ext = url.pathExtension.lowercased()
        guard ext == VisorProjectCodec.fileExtension || ext == "zip" else {
            toast = "sidebar.import.badExtension".l
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            _ = try await VisorProjectCodec.importProject(
                from: url,
                context: context
            ) { newId in
                selectedSessionId = newId
            }
            toast = "sidebar.import.success".l
        } catch {
            toast = "sidebar.import.error".l(error.localizedDescription)
        }
    }
}

// MARK: - Share Sheet

/// 直接从 rootVC present UIActivityViewController，不通过 SwiftUI sheet 包装（避免空白）
private func presentShareSheet(url: URL) {
    guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let root = scene.windows.first?.rootViewController else { return }
    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let pop = activityVC.popoverPresentationController {
        pop.sourceView = root.view
        pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
        pop.permittedArrowDirections = []
    }
    root.present(activityVC, animated: true)
}
